#!/bin/bash

REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="cw-investigations-demo"

echo "Initializing database..."

RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' \
  --output text)

EC2_ID=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`EC2InstanceId`].OutputValue' \
  --output text)

echo "RDS: $RDS_ENDPOINT"
echo "EC2: $EC2_ID"

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$EC2_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["mariadb -h '"$RDS_ENDPOINT"' -u admin -pDemoPassword123! << '\''EOF'\''
CREATE DATABASE IF NOT EXISTS demoapp;
USE demoapp;
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
INSERT INTO users (name, email) VALUES
    (\"Alice Johnson\", \"alice@example.com\"),
    (\"Bob Smith\", \"bob@example.com\"),
    (\"Charlie Brown\", \"charlie@example.com\")
ON DUPLICATE KEY UPDATE name=VALUES(name);
EOF"]' \
  --region $REGION \
  --output text \
  --query 'Command.CommandId')

echo "Command: $COMMAND_ID"
sleep 5

API_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text)

echo "Testing database..."
curl -s "${API_ENDPOINT}/api/users" | jq .
echo ""
echo "✓ Database initialized"
