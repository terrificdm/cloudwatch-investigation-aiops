#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${YELLOW}Stopping slow query load...${NC}"

# Get resources
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2InstanceId`].OutputValue' \
    --output text)

AUTOMATION_ROLE=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`SSMAutomationRoleArn`].OutputValue' \
    --output text)

# Start SSM Automation
echo -e "${YELLOW}Executing SSM Automation Document...${NC}"
EXECUTION_ID=$(aws ssm start-automation-execution \
    --document-name "RemediateRDSHighConnections" \
    --parameters "InstanceId=$INSTANCE_ID,AutomationAssumeRole=$AUTOMATION_ROLE" \
    --region $REGION \
    --query 'AutomationExecutionId' \
    --output text)

echo -e "${GREEN}✓ Automation started: $EXECUTION_ID${NC}"
echo -e "${YELLOW}Waiting for execution to complete...${NC}"

# Wait for automation to complete
aws ssm wait automation-execution-success \
    --automation-execution-id $EXECUTION_ID \
    --region $REGION 2>/dev/null || {
    STATUS=$(aws ssm describe-automation-executions \
        --filters Key=ExecutionId,Values=$EXECUTION_ID \
        --region $REGION \
        --query 'AutomationExecutionMetadataList[0].AutomationExecutionStatus' \
        --output text)
    echo -e "${YELLOW}⚠ Automation status: $STATUS${NC}"
}

echo -e "${GREEN}✓ Slow query load stopped${NC}"
echo -e "${YELLOW}RDS connections should return to normal in 1-2 minutes${NC}"
