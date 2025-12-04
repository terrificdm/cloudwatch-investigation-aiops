import json
import boto3
import os

ssm = boto3.client('ssm')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    """
    Fault injector Lambda function
    Triggers different failure scenarios for demo
    """
    
    scenario = event.get('scenario', 'cpu-stress')
    instance_id = os.environ.get('EC2_INSTANCE_ID')
    
    if not instance_id:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'EC2_INSTANCE_ID not configured'})
        }
    
    try:
        if scenario == 'cpu-stress':
            return trigger_cpu_stress(instance_id, event)
        elif scenario == 'memory-leak':
            return trigger_memory_leak(instance_id, event)
        elif scenario == 'stop-stress':
            return stop_stress(instance_id)
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

def trigger_cpu_stress(instance_id, event):
    """Trigger CPU stress test on EC2 instance"""
    duration = event.get('duration', 300)  # Default 5 minutes
    cpu_workers = event.get('cpu_workers', 0)  # 0 = all CPUs
    
    commands = [
        '#!/bin/bash',
        'echo "Starting CPU stress test..."',
        f'nohup stress-ng --cpu {cpu_workers} --timeout {duration}s --metrics-brief > /tmp/stress.log 2>&1 &',
        'echo "Stress test started in background"',
        'echo "PID: $(pgrep -f stress-ng)"'
    ]
    
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': commands},
        Comment='Demo: Trigger CPU stress for CloudWatch Investigations'
    )
    
    command_id = response['Command']['CommandId']
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'CPU stress test triggered',
            'instance_id': instance_id,
            'duration': duration,
            'command_id': command_id
        })
    }

def trigger_memory_leak(instance_id, event):
    """Trigger memory leak simulation on EC2 instance"""
    duration = event.get('duration', 300)
    memory_mb = event.get('memory_mb', 512)
    
    commands = [
        '#!/bin/bash',
        'echo "Starting memory stress test..."',
        f'nohup stress-ng --vm 1 --vm-bytes {memory_mb}M --timeout {duration}s > /tmp/stress-mem.log 2>&1 &',
        'echo "Memory stress test started"',
        'echo "PID: $(pgrep -f stress-ng)"'
    ]
    
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': commands},
        Comment='Demo: Trigger memory stress for CloudWatch Investigations'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Memory stress test triggered',
            'instance_id': instance_id,
            'duration': duration,
            'command_id': response['Command']['CommandId']
        })
    }

def stop_stress(instance_id):
    """Stop all stress tests on EC2 instance"""
    commands = [
        '#!/bin/bash',
        'echo "Stopping all stress tests..."',
        'pkill -9 -f stress-ng',
        'echo "Stress tests stopped"'
    ]
    
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': commands},
        Comment='Demo: Stop stress tests'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Stress tests stopped',
            'instance_id': instance_id,
            'command_id': response['Command']['CommandId']
        })
    }
