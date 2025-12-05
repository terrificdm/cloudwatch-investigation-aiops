#!/usr/bin/env python3
import os
import time
import pymysql
from flask import Flask, jsonify, request
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database configuration from environment variables
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')
DB_NAME = os.environ.get('DB_NAME', 'demoapp')

def get_db_connection():
    """Create database connection"""
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        connect_timeout=5
    )

@app.route('/')
def home():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'ec2-app', 'timestamp': time.time()})

@app.route('/health')
def health():
    """Detailed health check with DB connection"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        conn.close()
        return jsonify({'status': 'healthy', 'database': 'connected', 'timestamp': time.time()})
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({'status': 'unhealthy', 'database': 'disconnected', 'error': str(e), 'timestamp': time.time()}), 503

@app.route('/api/users', methods=['GET'])
def get_users():
    """Get all users from database"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(pymysql.cursors.DictCursor)
        cursor.execute("SELECT id, name, email, created_at FROM users")
        users = cursor.fetchall()
        cursor.close()
        conn.close()
        return jsonify({'success': True, 'count': len(users), 'users': users})
    except Exception as e:
        logger.error(f"Failed to get users: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/users', methods=['POST'])
def create_user():
    """Create a new user"""
    try:
        data = request.get_json()
        name = data.get('name')
        email = data.get('email')
        if not name or not email:
            return jsonify({'success': False, 'error': 'Name and email are required'}), 400
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("INSERT INTO users (name, email) VALUES (%s, %s)", (name, email))
        conn.commit()
        user_id = cursor.lastrowid
        cursor.close()
        conn.close()
        return jsonify({'success': True, 'user_id': user_id, 'name': name, 'email': email}), 201
    except Exception as e:
        logger.error(f"Failed to create user: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/slow-query')
def slow_query():
    """Slow query endpoint for demo - holds DB connection for extended time"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # Execute a long-running query to keep connection active
        # This will hold the connection for 40 seconds
        cursor.execute("SELECT SLEEP(40)")
        cursor.close()
        conn.close()
        return jsonify({'success': True, 'message': 'Slow query completed', 'timestamp': time.time()})
    except Exception as e:
        logger.error(f"Slow query failed: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
