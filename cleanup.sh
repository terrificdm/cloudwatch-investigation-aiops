#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}CloudWatch Investigations Demo Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Confirm deletion
read -p "Are you sure you want to delete all demo resources? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "${YELLOW}Starting cleanup...${NC}"
echo ""

# Note: Investigation Group is not deleted as it's shared across the region
# and may be used by other resources. To delete manually:
# aws aiops delete-investigation-group --name <group-name> --region $REGION
echo -e "${YELLOW}Note: Investigation Group is not deleted (shared resource)${NC}"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="cw-investigations-demo-${ACCOUNT_ID}-${REGION}"

# Stop any running load tests
echo -e "${YELLOW}Stopping any running load tests...${NC}"
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2InstanceId`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$INSTANCE_ID" ]; then
    aws ssm send-command \
        --instance-ids $INSTANCE_ID \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["pkill -f \"curl.*slow-query\" || true"]' \
        --region $REGION \
        --output text > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Stopped load tests${NC}"
fi

# Delete CloudFormation stack
echo -e "${YELLOW}Deleting CloudFormation stack...${NC}"
if aws cloudformation delete-stack \
    --stack-name $STACK_NAME \
    --region $REGION 2>/dev/null; then
    
    echo -e "${YELLOW}Waiting for stack deletion (this may take 5-10 minutes)...${NC}"
    if aws cloudformation wait stack-delete-complete \
        --stack-name $STACK_NAME \
        --region $REGION 2>/dev/null; then
        echo -e "${GREEN}✓ Stack deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Stack deletion may have failed or stack doesn't exist${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Stack not found or already deleted${NC}"
fi

# Delete S3 bucket
echo -e "${YELLOW}Deleting S3 bucket...${NC}"
if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 > /dev/null; then
    aws s3 rb "s3://${BUCKET_NAME}" --force --region $REGION
    echo -e "${GREEN}✓ S3 bucket deleted${NC}"
fi

# Clean up local temp files
rm -rf /tmp/lambda-packages

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}All demo resources have been deleted.${NC}"
