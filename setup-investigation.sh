#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Investigation Integration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get stack outputs
echo -e "${YELLOW}Getting stack information...${NC}"
INVESTIGATION_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`InvestigationGroupRoleArn`].OutputValue' \
    --output text 2>/dev/null)

if [ -z "$INVESTIGATION_ROLE_ARN" ]; then
    echo -e "${RED}✗ Stack not found. Please run ./deploy.sh first${NC}"
    exit 1
fi

EC2_INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2InstanceId`].OutputValue' \
    --output text)

echo -e "${GREEN}✓ Stack information retrieved${NC}"
echo ""

# Setup Investigation Group
echo -e "${YELLOW}Setting up Investigation Group...${NC}"
INVESTIGATION_GROUP_ARN=$(aws aiops list-investigation-groups \
    --region $REGION \
    --query 'investigationGroups[0].arn' \
    --output text 2>/dev/null)

if [ -n "$INVESTIGATION_GROUP_ARN" ] && [ "$INVESTIGATION_GROUP_ARN" != "None" ]; then
    echo -e "${GREEN}✓ Using existing Investigation Group${NC}"
else
    echo -e "${YELLOW}Creating Investigation Group...${NC}"
    INVESTIGATION_GROUP_ARN=$(aws aiops create-investigation-group \
        --name cw-investigations-demo-group \
        --role-arn "$INVESTIGATION_ROLE_ARN" \
        --retention-in-days 30 \
        --is-cloud-trail-event-history-enabled \
        --region $REGION \
        --query 'investigationGroupArn' \
        --output text 2>/dev/null)
    
    if [ -n "$INVESTIGATION_GROUP_ARN" ] && [ "$INVESTIGATION_GROUP_ARN" != "None" ]; then
        echo -e "${GREEN}✓ Investigation Group created${NC}"
    else
        echo -e "${RED}✗ Failed to create Investigation Group${NC}"
        echo -e "${YELLOW}  This feature may not be available in region: $REGION${NC}"
        exit 1
    fi
fi

echo -e "  ARN: ${INVESTIGATION_GROUP_ARN}"
echo ""

# Create Investigation Group policy
echo -e "${YELLOW}Creating Investigation Group policy...${NC}"
aws aiops put-investigation-group-policy \
    --investigation-group-arn "$INVESTIGATION_GROUP_ARN" \
    --region $REGION \
    --policy-document "{
        \"Version\": \"2008-10-17\",
        \"Statement\": [{
            \"Effect\": \"Allow\",
            \"Principal\": {\"Service\": \"aiops.alarms.cloudwatch.amazonaws.com\"},
            \"Action\": [\"aiops:CreateInvestigation\", \"aiops:CreateInvestigationEvent\"],
            \"Resource\": \"*\",
            \"Condition\": {
                \"StringEquals\": {\"aws:SourceAccount\": \"$ACCOUNT_ID\"},
                \"ArnLike\": {\"aws:SourceArn\": \"arn:aws:cloudwatch:$REGION:$ACCOUNT_ID:alarm:*\"}
            }
        }]
    }" > /dev/null 2>&1

echo -e "${GREEN}✓ Investigation Group policy configured${NC}"
echo ""

# Configure EC2 CPU alarm for auto-trigger (Scenario 1 only)
echo -e "${YELLOW}Configuring EC2 CPU alarm for auto-trigger...${NC}"

aws cloudwatch put-metric-alarm \
    --alarm-name cw-demo-ec2-high-cpu \
    --alarm-description "Triggers when EC2 CPU exceeds 80%" \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --period 60 \
    --evaluation-periods 2 \
    --datapoints-to-alarm 2 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=InstanceId,Value=$EC2_INSTANCE_ID \
    --treat-missing-data notBreaching \
    --alarm-actions "$INVESTIGATION_GROUP_ARN#DEDUPE_STRING=ec2-performance" \
    --region $REGION

echo -e "${GREEN}✓ EC2 CPU alarm configured for auto-trigger${NC}"
echo ""

# Verify configuration
echo -e "${YELLOW}Verifying alarm configuration...${NC}"
ALARM_ACTIONS=$(aws cloudwatch describe-alarms \
    --alarm-names cw-demo-ec2-high-cpu \
    --region $REGION \
    --query 'MetricAlarms[0].AlarmActions[0]' \
    --output text 2>/dev/null)

if [[ "$ALARM_ACTIONS" == *"investigation-group"* ]]; then
    echo -e "${GREEN}✓ Verification successful!${NC}"
    echo -e "  Alarm Action: ${ALARM_ACTIONS}"
else
    echo -e "${RED}✗ Verification failed${NC}"
    echo -e "  Expected: Investigation Group ARN"
    echo -e "  Got: ${ALARM_ACTIONS}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo -e "  ✓ Investigation Group: Created/Verified"
echo -e "  ✓ Resource Policy: Configured"
echo -e "  ✓ EC2 CPU Alarm: Auto-trigger enabled (Scenario 1)"
echo -e "  ✓ Lambda/RDS Alarms: Manual start (Scenarios 2 & 3)"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Run: ${GREEN}./scenarios/scenario-1.sh${NC}"
echo -e "  2. Wait 2-3 minutes for alarm to trigger"
echo -e "  3. Investigation will auto-start!"
echo ""
echo -e "${YELLOW}Investigation Console:${NC}"
echo -e "  https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#investigations:"
echo ""
