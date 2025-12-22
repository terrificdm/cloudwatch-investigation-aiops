#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Scenario 1: EC2 Application Slow Query Load${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get resources
echo -e "${YELLOW}Getting resource information...${NC}"
FAULT_INJECTOR=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`FaultInjectorFunctionName`].OutputValue' \
    --output text)

INVESTIGATION_CONSOLE=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`InvestigationGroupConsole`].OutputValue' \
    --output text)

echo -e "${GREEN}✓ Resources found${NC}"
echo ""

# Trigger slow query load
echo -e "${YELLOW}Triggering slow query load (150 concurrent requests)...${NC}"
aws lambda invoke \
    --function-name $FAULT_INJECTOR \
    --region $REGION \
    --cli-binary-format raw-in-base64-out \
    --payload '{"scenario":"slow-query-load","duration":1800,"concurrent":150}' \
    /tmp/fault-injector-response.json > /dev/null

RESPONSE=$(cat /tmp/fault-injector-response.json)
echo -e "${GREEN}✓ Slow query load started (150 concurrent requests, 30 minutes duration)${NC}"
echo ""

# Instructions
echo -e "${YELLOW}📋 Demo Steps:${NC}"
echo ""
echo -e "1. ${YELLOW}Wait 2-3 minutes${NC} for RDS connections to spike and alarm to trigger"
echo ""
echo -e "2. ${YELLOW}Open Investigation Console:${NC}"
echo -e "   ${INVESTIGATION_CONSOLE}"
echo ""
echo -e "3. ${YELLOW}Investigation will show:${NC}"
echo -e "   ✓ New investigation automatically created by RDS alarm"
echo -e "   ✓ AI analyzing RDS DatabaseConnections metrics"
echo -e "   ✓ Cross-service correlation (EC2 → RDS)"
echo -e "   ✓ Root cause hypothesis: Database slow queries causing connection buildup"
echo -e "   ✓ Suggested actions (may include SSM Runbook)"
echo ""
echo -e "4. ${YELLOW}Manual Remediation:${NC}"
echo -e "   ${GREEN}Run: ./scenarios/stop-load.sh${NC}"
echo -e "   - This will stop all slow query load processes"
echo -e "   - RDS connections will drop back to normal"
echo ""
echo -e "5. ${YELLOW}Verify and Report:${NC}"
echo -e "   ✓ Watch RDS connections return to normal"
echo -e "   ✓ Accept the hypothesis in Investigation"
echo -e "   ✓ Generate incident report"
echo ""
echo -e "${YELLOW}⏱️  Timeline:${NC}"
echo -e "   0-2 min: Slow query load building up"
echo -e "   2-3 min: RDS connections spike, alarm triggers, Investigation auto-starts"
echo -e "   3-5 min: AI analysis and suggestions appear"
echo -e "   5-8 min: Execute remediation and verify"
echo ""
echo -e "${YELLOW}🛑 To stop load manually:${NC}"
echo -e "   ./scenarios/stop-load.sh"
echo ""
echo -e "${GREEN}Scenario 1 is running! Slow query load will continue for 30 minutes unless stopped.${NC}"
