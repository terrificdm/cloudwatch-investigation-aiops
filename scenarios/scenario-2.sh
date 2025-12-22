#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Scenario 2: Lambda Slow Query + X-Ray Tracing${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get resources
echo -e "${YELLOW}Getting resource information...${NC}"
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

INVESTIGATION_CONSOLE=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`InvestigationGroupConsole`].OutputValue' \
    --output text)

LAMBDA_CONSOLE="https://console.aws.amazon.com/lambda/home?region=${REGION}#/functions/cw-investigations-demo-api"

echo -e "${GREEN}✓ Resources found${NC}"
echo ""

# Trigger Lambda slow query
echo -e "${YELLOW}Triggering Lambda slow query (calling slow endpoint)...${NC}"
echo ""

for i in {1..5}; do
    echo -e "  Request $i/5..."
    curl -s -f "${API_ENDPOINT}/api/slow?delay=25" > /dev/null 2>&1 || echo -e "    ${GREEN}✓ Slow query executed (expected)${NC}"
    sleep 2
done

echo ""
echo -e "${GREEN}✓ Lambda slow query triggered${NC}"
echo ""

# Instructions
echo -e "${YELLOW}📋 Demo Steps:${NC}"
echo ""
echo -e "1. ${YELLOW}Wait 2-3 minutes${NC}"
echo -e "   Let metrics populate to CloudWatch"
echo ""
echo -e "2. ${YELLOW}Open Lambda Console:${NC}"
echo -e "   ${LAMBDA_CONSOLE}"
echo ""
echo -e "3. ${YELLOW}Start Investigation Manually:${NC}"
echo -e "   ✓ Click 'Monitor' tab"
echo -e "   ✓ View 'Errors' or 'Duration' metric spike"
echo -e "   ✓ Click 'Investigate' button"
echo -e "   ✓ Select time range (last 15 minutes)"
echo -e "   ✓ Enter title and start"
echo ""
echo -e "4. ${YELLOW}View X-Ray Traces:${NC}"
echo -e "   ✓ Click X-Ray trace link"
echo -e "   ✓ View service map: API Gateway → Lambda → RDS"
echo -e "   ✓ View trace details: RDS query takes ~25 seconds"
echo ""
echo -e "5. ${YELLOW}Review AI Analysis:${NC}"
echo -e "   ✓ Root Cause: Database query taking too long"
echo -e "   ✓ Suggestions: Optimize query, increase timeout, async processing"
echo ""
echo -e "6. ${YELLOW}(Optional) Use Amazon Q Chat:${NC}"
echo -e "   ✓ Click Amazon Q icon in AWS Console (bottom-right)"
echo -e "   ✓ Ask: 'Why is my Lambda function slow?'"
echo -e "   ✓ Or: 'Why is cw-investigations-demo-api slow?'"
echo -e "   ✓ Amazon Q will analyze and suggest starting Investigation"
echo ""
echo -e "${YELLOW}🔍 Key Observations:${NC}"
echo -e "   • Lambda timeout setting: 30 seconds"
echo -e "   • Database query delay: 25 seconds (triggers high duration alarm)"
echo -e "   • X-Ray shows end-to-end latency"
echo -e "   • Investigation correlates all signals"
echo ""
echo -e "${YELLOW}📊 Investigation Console:${NC}"
echo -e "   ${INVESTIGATION_CONSOLE}"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Scenario 2 Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
