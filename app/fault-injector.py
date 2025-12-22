import json
import boto3
import os

ssm = boto3.client('ssm')

def lambda_handler(event, context):
    """
    Fault injector Lambda function
    Triggers slow query load for demo
    """
    
    scenario = event.get('scenario', 'slow-query-load')
    instance_id = os.environ.get('EC2_INSTANCE_ID')
    
    if not instance_id:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'EC2_INSTANCE_ID not configured'})
        }
    
    try:
        if scenario == 'slow-query-load':
            return trigger_slow_query_load(instance_id, event)
        elif scenario == 'stop-load':
            return stop_load(instance_id)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown scenario: {scenario}'})
            }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def trigger_slow_query_load(instance_id, event):
    """Trigger slow query load on EC2 Flask application"""
    duration = event.get('duration', 1800)  # Default 30 minutes
    concurrent = event.get('concurrent', 150)  # Default 150 concurrent requests
    
    commands = [
        '#!/bin/bash',
        'echo "Starting slow query load test..."',
        'END_TIME=$(($(date +%s) + ' + str(duration) + '))',
        '',
        '# Function to start concurrent requests',
        'start_requests() {',
        f'  for i in {{1..{concurrent}}}; do',
        '    curl -s http://localhost:5000/api/slow-query > /dev/null 2>&1 &',
        '  done',
        '}',
        '',
        '# Keep sending requests until duration expires',
        'while [ $(date +%s) -lt $END_TIME ]; do',
        '  start_requests',
        f'  echo "Started {concurrent} concurrent slow queries at $(date)"',
        '  sleep 35  # Wait slightly longer than query duration (30s) before next batch',
        'done',
        '',
        'echo "Load test duration completed, waiting for remaining requests..."',
        'wait',
        'echo "Load test completed"'
    ]
    
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': commands},
        Comment='Demo: Trigger slow query load for CloudWatch Investigations'
    )
    
    command_id = response['Command']['CommandId']
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Slow query load triggered',
            'instance_id': instance_id,
            'concurrent': concurrent,
            'duration': duration,
            'command_id': command_id
        })
    }

def stop_load(instance_id):
    """Stop slow query load on EC2 instance"""
    commands = [
        '#!/bin/bash',
        'echo "Stopping slow query load..."',
        'pkill -f "curl.*slow-query" || true',
        'echo "Slow query load stopped"'
    ]
    
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': commands},
        Comment='Demo: Stop slow query load'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Slow query load stopped',
            'instance_id': instance_id,
            'command_id': response['Command']['CommandId']
        })
    }
