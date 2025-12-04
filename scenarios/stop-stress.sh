#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${YELLOW}Stopping all stress tests...${NC}"

# Get instance ID
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2InstanceId`].OutputValue' \
    --output text)

# Stop stress processes
aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["pkill -9 -f stress-ng || true","echo Stress tests stopped"]' \
    --region $REGION \
    --output text > /dev/null

echo -e "${GREEN}✓ Stress tests stopped${NC}"
echo -e "${YELLOW}CPU should return to normal in 1-2 minutes${NC}"
