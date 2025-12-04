#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="cw-investigations-demo"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Scenario 1: EC2 CPU Stress + SSM Auto-Remediation${NC}"
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

# Trigger CPU stress
echo -e "${YELLOW}Triggering CPU stress test (持续运行，需手动停止)...${NC}"
aws lambda invoke \
    --function-name $FAULT_INJECTOR \
    --region $REGION \
    --cli-binary-format raw-in-base64-out \
    --payload '{"scenario":"cpu-stress","duration":1800,"cpu_workers":0}' \
    /tmp/fault-injector-response.json > /dev/null

RESPONSE=$(cat /tmp/fault-injector-response.json)
echo -e "${GREEN}✓ CPU stress test started (will run for 30 minutes)${NC}"
echo ""

# Instructions
echo -e "${YELLOW}📋 Demo Steps:${NC}"
echo ""
echo -e "1. ${YELLOW}Wait 2-3 minutes${NC} for CPU to spike and alarm to trigger"
echo ""
echo -e "2. ${YELLOW}Open Investigation Console:${NC}"
echo -e "   ${INVESTIGATION_CONSOLE}"
echo ""
echo -e "3. ${YELLOW}Investigation will show:${NC}"
echo -e "   ✓ New investigation automatically created by alarm"
echo -e "   ✓ AI analyzing EC2 CPU metrics"
echo -e "   ✓ Root cause hypothesis: High CPU usage"
echo -e "   ✓ Suggested actions (may include SSM Runbook)"
echo ""
echo -e "4. ${YELLOW}Manual Remediation Options:${NC}"
echo -e "   ${GREEN}Option A: Use SSM Runbook (if suggested by Investigation)${NC}"
echo -e "   - Click on SSM Automation suggestion"
echo -e "   - Execute the runbook to stop stress process"
echo ""
echo -e "   ${GREEN}Option B: Use stop-stress.sh script${NC}"
echo -e "   - Run: ./scenarios/stop-stress.sh"
echo -e "   - This will stop the CPU stress test"
echo ""
echo -e "5. ${YELLOW}Verify and Report:${NC}"
echo -e "   ✓ Watch CPU return to normal"
echo -e "   ✓ Accept the hypothesis in Investigation"
echo -e "   ✓ Generate incident report"
echo ""
echo -e "${YELLOW}⏱️  Timeline:${NC}"
echo -e "   0-2 min: CPU stress building up"
echo -e "   2-3 min: Alarm triggers, Investigation auto-starts"
echo -e "   3-5 min: AI analysis and suggestions appear"
echo -e "   5-8 min: Execute remediation and verify"
echo ""
echo -e "${YELLOW}🛑 To stop stress test manually:${NC}"
echo -e "   ./scenarios/stop-stress.sh"
echo ""
echo -e "${GREEN}Scenario 1 is running! CPU stress will continue for 30 minutes unless stopped.${NC}"
