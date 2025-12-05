#!/bin/bash
set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CloudWatch Investigations Demo Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account: ${ACCOUNT_ID}${NC}"
echo -e "${GREEN}✓ Region: ${REGION}${NC}"
echo ""

# Check if stack already exists
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
    echo -e "${YELLOW}Stack already exists. Updating...${NC}"
    OPERATION="update-stack"
else
    echo -e "${YELLOW}Creating new stack...${NC}"
    OPERATION="create-stack"
fi

# Package Lambda functions
echo -e "${YELLOW}Packaging Lambda functions...${NC}"
mkdir -p /tmp/lambda-packages

# Package API Lambda with dependencies
cd /tmp
mkdir -p lambda-api-package
cd lambda-api-package
pip3 install pymysql aws-xray-sdk -t . -q 2>/dev/null
cp "$SCRIPT_DIR/app/lambda-api.py" index.py
zip -qr /tmp/lambda-packages/lambda-api.zip .
cd /tmp && rm -rf lambda-api-package
echo -e "${GREEN}✓ Packaged lambda-api with dependencies${NC}"

# Package Fault Injector Lambda
cd "$SCRIPT_DIR/app"
cp fault-injector.py index.py
zip -q /tmp/lambda-packages/fault-injector.zip index.py
rm index.py
echo -e "${GREEN}✓ Packaged fault-injector${NC}"
cd "$SCRIPT_DIR"

# Create S3 bucket for Lambda code (if needed)
BUCKET_NAME="cw-investigations-demo-${ACCOUNT_ID}-${REGION}"
if ! aws s3 ls "s3://${BUCKET_NAME}" > /dev/null 2>&1; then
    echo -e "${YELLOW}Creating S3 bucket for Lambda code...${NC}"
    if [ "$REGION" == "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}" --region $REGION
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region $REGION --create-bucket-configuration LocationConstraint=$REGION
    fi
    echo -e "${GREEN}✓ Created S3 bucket${NC}"
else
    echo -e "${GREEN}✓ S3 bucket already exists${NC}"
fi

# Upload Lambda packages
echo -e "${YELLOW}Uploading Lambda packages to S3...${NC}"
aws s3 cp /tmp/lambda-packages/lambda-api.zip "s3://${BUCKET_NAME}/lambda-api.zip"
aws s3 cp /tmp/lambda-packages/fault-injector.zip "s3://${BUCKET_NAME}/fault-injector.zip"
echo -e "${GREEN}✓ Uploaded Lambda packages${NC}"

# Upload EC2 application code
echo -e "${YELLOW}Uploading EC2 application code to S3...${NC}"
aws s3 cp "$SCRIPT_DIR/app/ec2-app.py" "s3://${BUCKET_NAME}/ec2-app.py"
echo -e "${GREEN}✓ Uploaded EC2 application code${NC}"
echo ""

# Deploy CloudFormation stack
echo -e "${YELLOW}Deploying CloudFormation stack (this will take ~15 minutes)...${NC}"
aws cloudformation deploy \
    --template-file "$SCRIPT_DIR/cloudformation/demo-stack.yaml" \
    --stack-name $STACK_NAME \
    --region $REGION \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides \
        DBPassword="DemoPassword123!" \
        LambdaCodeBucket="${BUCKET_NAME}" \
        AppCodeBucket="${BUCKET_NAME}" \
        AppCodeKey="ec2-app.py" \
    --no-fail-on-empty-changeset

echo -e "${GREEN}✓ Stack deployed${NC}"
echo ""

# Wait for stack to be complete
echo -e "${YELLOW}Waiting for stack to be ready...${NC}"
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $REGION 2>/dev/null || \
aws cloudformation wait stack-update-complete --stack-name $STACK_NAME --region $REGION 2>/dev/null || true

# Get outputs
echo -e "${YELLOW}Retrieving stack outputs...${NC}"
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs' \
    --output json)

EC2_INSTANCE_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="EC2InstanceId") | .OutputValue')
EC2_PUBLIC_IP=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="EC2PublicIP") | .OutputValue')
API_ENDPOINT=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="ApiEndpoint") | .OutputValue')
RDS_ENDPOINT=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="RDSEndpoint") | .OutputValue')
INVESTIGATION_ROLE_ARN=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="InvestigationGroupRoleArn") | .OutputValue')
INVESTIGATION_CONSOLE=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="InvestigationGroupConsole") | .OutputValue')
FAULT_INJECTOR=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="FaultInjectorFunctionName") | .OutputValue')

# Update Lambda function code
echo -e "${YELLOW}Updating Lambda function code...${NC}"
aws lambda update-function-code \
    --function-name cw-investigations-demo-api \
    --s3-bucket $BUCKET_NAME \
    --s3-key lambda-api.zip \
    --region $REGION > /dev/null

aws lambda update-function-code \
    --function-name $FAULT_INJECTOR \
    --s3-bucket $BUCKET_NAME \
    --s3-key fault-injector.zip \
    --region $REGION > /dev/null

echo -e "${GREEN}✓ Lambda functions updated${NC}"
echo ""

# Wait for EC2 to be ready
echo -e "${YELLOW}Waiting for EC2 instance to be ready (this may take a few minutes)...${NC}"
aws ec2 wait instance-status-ok --instance-ids $EC2_INSTANCE_ID --region $REGION
echo -e "${GREEN}✓ EC2 instance is ready${NC}"
echo ""

# Test deployment
echo -e "${YELLOW}Testing deployment...${NC}"
sleep 30  # Wait for app to start

if curl -s -f "http://${EC2_PUBLIC_IP}:5000/health" > /dev/null; then
    echo -e "${GREEN}✓ EC2 app is responding${NC}"
else
    echo -e "${YELLOW}⚠ EC2 app not responding yet (may need more time)${NC}"
fi

if curl -s -f "${API_ENDPOINT}" > /dev/null; then
    echo -e "${GREEN}✓ Lambda API is responding${NC}"
else
    echo -e "${YELLOW}⚠ Lambda API not responding yet (may need more time)${NC}"
fi

echo ""
echo -e "${YELLOW}Verifying database initialization...${NC}"
sleep 5  # Give Lambda a moment to be ready

DB_CHECK=$(curl -s "${API_ENDPOINT}/api/users" 2>/dev/null)
if echo "$DB_CHECK" | grep -q '"success":true'; then
    USER_COUNT=$(echo "$DB_CHECK" | jq -r '.count' 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Database initialized successfully ($USER_COUNT users found)${NC}"
else
    echo -e "${YELLOW}⚠ Database not initialized, running init-database.sh...${NC}"
    if ./init-database.sh; then
        echo -e "${GREEN}✓ Database initialized via init-database.sh${NC}"
    else
        echo -e "${RED}✗ Database initialization failed${NC}"
        echo -e "${YELLOW}  You can manually run: ./init-database.sh${NC}"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}📊 Resources:${NC}"
echo -e "  EC2 Instance ID: ${EC2_INSTANCE_ID}"
echo -e "  EC2 Public IP: ${EC2_PUBLIC_IP}"
echo -e "  API Endpoint: ${API_ENDPOINT}"
echo -e "  RDS Endpoint: ${RDS_ENDPOINT}"
echo ""
echo -e "${YELLOW}🔍 Investigation Group:${NC}"
echo -e "  Console: ${INVESTIGATION_CONSOLE}"
echo ""
echo -e "${RED}⚠️  IMPORTANT - Next Step:${NC}"
echo -e "  Run: ${GREEN}./setup-investigation.sh${NC}"
echo -e "  This configures Scenario 1 alarm to auto-trigger Investigation"
echo ""
echo -e "${YELLOW}🎯 Test Commands:${NC}"
echo -e "  EC2 App: curl http://${EC2_PUBLIC_IP}:5000/health"
echo -e "  Lambda API: curl ${API_ENDPOINT}/api/users"
echo ""
echo -e "${YELLOW}🚀 Run Demo Scenarios:${NC}"
echo -e "  Scenario 1 (RDS Connections): ./scenarios/scenario-1.sh"
echo -e "  Scenario 2 (Lambda): ./scenarios/scenario-2.sh"
echo ""
echo -e "${YELLOW}🧹 Cleanup:${NC}"
echo -e "  ./cleanup.sh"
echo ""
