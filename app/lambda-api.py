import json
import os
import time
import pymysql
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch libraries for X-Ray tracing
patch_all()

# Database configuration
DB_HOST = os.environ.get('DB_HOST')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
DB_NAME = os.environ.get('DB_NAME', 'demoapp')

def get_db_connection():
    """Create database connection with X-Ray tracing"""
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        connect_timeout=5
    )

@xray_recorder.capture('lambda_handler')
def lambda_handler(event, context):
    """Main Lambda handler"""
    
    # Parse request
    http_method = event.get('httpMethod', event.get('requestContext', {}).get('http', {}).get('method', 'GET'))
    raw_path = event.get('path', event.get('rawPath', '/'))
    
    # Log for debugging
    print(f"DEBUG: http_method={http_method}, raw_path={raw_path}")
    
    # Handle both direct paths and paths with stage prefix
    path = raw_path.replace('/prod', '').replace('/$default', '') or '/'
    
    print(f"DEBUG: normalized path={path}")
    
    try:
        # Route requests
        if path == '/' or path == '/health':
            return health_check()
        elif path == '/api/users' and http_method == 'GET':
            return get_users()
        elif path == '/api/users' and http_method == 'POST':
            return create_user(event)
        elif path == '/api/slow':
            return slow_endpoint(event)
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Not found', 'path': raw_path, 'normalized': path})
            }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

@xray_recorder.capture('health_check')
def health_check():
    """Health check endpoint"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'status': 'healthy',
                'service': 'lambda-api',
                'database': 'connected',
                'timestamp': time.time()
            })
        }
    except Exception as e:
        return {
            'statusCode': 503,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'status': 'unhealthy',
                'database': 'disconnected',
                'error': str(e)
            })
        }

@xray_recorder.capture('get_users')
def get_users():
    """Get all users from database"""
    conn = get_db_connection()
    cursor = conn.cursor(pymysql.cursors.DictCursor)
    cursor.execute("SELECT id, name, email, created_at FROM users LIMIT 100")
    users = cursor.fetchall()
    cursor.close()
    conn.close()
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'success': True,
            'count': len(users),
            'users': users
        }, default=str)
    }

@xray_recorder.capture('create_user')
def create_user(event):
    """Create a new user"""
    body = json.loads(event.get('body', '{}'))
    name = body.get('name')
    email = body.get('email')
    
    if not name or not email:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Name and email are required'})
        }
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO users (name, email) VALUES (%s, %s)",
        (name, email)
    )
    conn.commit()
    user_id = cursor.lastrowid
    cursor.close()
    conn.close()
    
    return {
        'statusCode': 201,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'success': True,
            'user_id': user_id,
            'name': name,
            'email': email
        })
    }

@xray_recorder.capture('slow_endpoint')
def slow_endpoint(event):
    """Simulate slow query for timeout scenario"""
    # Get delay parameter (default 10 seconds)
    query_params = event.get('queryStringParameters') or {}
    delay = int(query_params.get('delay', 10))
    
    # Simulate slow database query
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # This will cause timeout if delay > Lambda timeout
    cursor.execute(f"SELECT SLEEP({delay})")
    cursor.execute("SELECT COUNT(*) FROM users")
    result = cursor.fetchone()
    
    cursor.close()
    conn.close()
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': f'Completed after {delay} seconds',
            'user_count': result[0]
        })
    }

