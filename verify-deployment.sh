#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Verifying CloudWatch Investigations Demo${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check if stack exists
echo -e "${YELLOW}Checking CloudFormation stack...${NC}"
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
    echo -e "${RED}✗ Stack not found${NC}"
    echo -e "${YELLOW}Run ./deploy.sh to deploy the demo${NC}"
    exit 1
fi

STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].StackStatus' \
    --output text)

if [[ "$STACK_STATUS" == *"COMPLETE"* ]]; then
    echo -e "${GREEN}✓ Stack status: $STACK_STATUS${NC}"
else
    echo -e "${RED}✗ Stack status: $STACK_STATUS${NC}"
    exit 1
fi

# Get outputs
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs' \
    --output json)

EC2_INSTANCE_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="EC2InstanceId") | .OutputValue')
EC2_PUBLIC_IP=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="EC2PublicIP") | .OutputValue')
API_ENDPOINT=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="ApiEndpoint") | .OutputValue')

echo ""
echo -e "${YELLOW}Checking EC2 instance...${NC}"
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids $EC2_INSTANCE_ID \
    --region $REGION \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

if [ "$INSTANCE_STATE" == "running" ]; then
    echo -e "${GREEN}✓ EC2 instance is running${NC}"
else
    echo -e "${RED}✗ EC2 instance state: $INSTANCE_STATE${NC}"
fi

# Check SSM Agent
echo -e "${YELLOW}Checking SSM Agent...${NC}"
SSM_STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$EC2_INSTANCE_ID" \
    --region $REGION \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null || echo "Unknown")

if [ "$SSM_STATUS" == "Online" ]; then
    echo -e "${GREEN}✓ SSM Agent is online${NC}"
else
    echo -e "${YELLOW}⚠ SSM Agent status: $SSM_STATUS (may need more time)${NC}"
fi

# Check EC2 app
echo -e "${YELLOW}Checking EC2 application...${NC}"
if curl -s -f -m 5 "http://${EC2_PUBLIC_IP}:5000/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ EC2 app is responding${NC}"
    EC2_RESPONSE=$(curl -s "http://${EC2_PUBLIC_IP}:5000/health")
    echo -e "  Response: $(echo $EC2_RESPONSE | jq -r '.service')"
else
    echo -e "${YELLOW}⚠ EC2 app not responding (may still be starting)${NC}"
fi

# Check Lambda API
echo -e "${YELLOW}Checking Lambda API...${NC}"
if curl -s -f -m 10 "${API_ENDPOINT}/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Lambda API is responding${NC}"
    API_RESPONSE=$(curl -s "${API_ENDPOINT}/health")
    echo -e "  Response: $(echo $API_RESPONSE | jq -r '.service')"
else
    echo -e "${YELLOW}⚠ Lambda API not responding${NC}"
fi

# Test users endpoint (Lambda → RDS)
echo -e "${YELLOW}Testing Lambda database query...${NC}"
if curl -s -f -m 10 "${API_ENDPOINT}/api/users" > /dev/null 2>&1; then
    USERS_RESPONSE=$(curl -s "${API_ENDPOINT}/api/users")
    USER_COUNT=$(echo $USERS_RESPONSE | jq -r '.count')
    echo -e "${GREEN}✓ Lambda → RDS query successful (found $USER_COUNT users)${NC}"
else
    echo -e "${YELLOW}⚠ Lambda database query failed${NC}"
fi

# Check RDS
echo -e "${YELLOW}Checking RDS database...${NC}"
RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier cw-investigations-demo-db \
    --region $REGION \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "Unknown")

if [ "$RDS_STATUS" == "available" ]; then
    echo -e "${GREEN}✓ RDS database is available${NC}"
else
    echo -e "${YELLOW}⚠ RDS status: $RDS_STATUS${NC}"
fi

# Check Investigation Group
echo -e "${YELLOW}Checking Investigation Group...${NC}"
IG_STATUS=$(aws aiops list-investigation-groups \
    --region $REGION \
    --query 'investigationGroups[0].name' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$IG_STATUS" ] && [ "$IG_STATUS" != "None" ]; then
    echo -e "${GREEN}✓ Investigation Group exists: $IG_STATUS${NC}"
else
    echo -e "${RED}✗ Investigation Group not found${NC}"
fi

# Check CloudWatch Alarms
echo -e "${YELLOW}Checking CloudWatch Alarms...${NC}"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "cw-demo-" \
    --region $REGION \
    --query 'length(MetricAlarms)' \
    --output text)

echo -e "${GREEN}✓ Found $ALARM_COUNT alarms${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Verification Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}📊 Resources:${NC}"
echo -e "  EC2: http://${EC2_PUBLIC_IP}:5000/health"
echo -e "  API: ${API_ENDPOINT}/health"
echo ""
echo -e "${YELLOW}🏗️  Architecture:${NC}"
echo -e "  Scenario 1: EC2 Flask App → RDS (slow query load)"
echo -e "  Scenario 2: API Gateway → Lambda → RDS"
echo ""
echo -e "${YELLOW}🚀 Ready to run scenarios:${NC}"
echo -e "  ./scenarios/scenario-1.sh  # EC2 slow query load → RDS connections"
echo -e "  ./scenarios/scenario-2.sh  # Lambda slow query"
