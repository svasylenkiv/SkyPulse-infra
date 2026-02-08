#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# test-canary-weights.sh — Перевірка розподілу трафіку між
# stable та canary target groups
#
# Використання:
#   ./scripts/test-canary-weights.sh [environment] [num_requests]
#
# Приклади:
#   ./scripts/test-canary-weights.sh dev 200
#   ./scripts/test-canary-weights.sh stg 100
# ──────────────────────────────────────────────────────────────
set -euo pipefail

ENV="${1:-dev}"
NUM_REQUESTS="${2:-200}"
REGION="${AWS_REGION:-us-east-1}"
APP_NAME="skypulse"

echo "═══════════════════════════════════════════════════"
echo " Canary Weight Test — ${APP_NAME}-${ENV}"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Get ALB DNS name ──
echo "▸ Looking up ALB..."
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names "${APP_NAME}-${ENV}-alb" \
  --region "$REGION" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${APP_NAME}-${ENV}-alb" \
  --region "$REGION" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "  ALB: $ALB_DNS"
echo ""

# ── 2. Show current listener weights ──
echo "▸ Current listener configuration:"
aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --region "$REGION" \
  --query 'Listeners[].{Port:Port,Actions:DefaultActions[].ForwardConfig.TargetGroups[].{ARN:TargetGroupArn,Weight:Weight}}' \
  --output json | jq '.'
echo ""

# ── 3. Check target group health ──
echo "▸ Target group health:"
for TG_NAME in "${APP_NAME}-${ENV}-tg" "${APP_NAME}-${ENV}-canary-tg"; do
  TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region "$REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "$TG_ARN" = "NOT_FOUND" ] || [ "$TG_ARN" = "None" ]; then
    echo "  $TG_NAME: NOT FOUND (canary may not be enabled)"
    continue
  fi

  HEALTH=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$REGION" \
    --query 'TargetHealthDescriptions[].TargetHealth.State' \
    --output text)

  echo "  $TG_NAME: $HEALTH"
done
echo ""

# ── 4. Send test requests ──
ALB_URL="http://${ALB_DNS}"

echo "▸ Sending $NUM_REQUESTS requests to $ALB_URL/health ..."
echo ""

if command -v hey &>/dev/null; then
  hey -n "$NUM_REQUESTS" -c 10 "$ALB_URL/health"
else
  echo "  (hey not found, using curl)"
  SUCCESS=0
  FAIL=0
  for i in $(seq 1 "$NUM_REQUESTS"); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ALB_URL/health" 2>/dev/null || echo "000")
    if [ "$STATUS" = "200" ]; then
      SUCCESS=$((SUCCESS + 1))
    else
      FAIL=$((FAIL + 1))
    fi
    # Progress every 50 requests
    if [ $((i % 50)) -eq 0 ]; then
      echo "  ... $i / $NUM_REQUESTS requests sent"
    fi
  done
  echo ""
  echo "  Results: $SUCCESS OK, $FAIL failed (out of $NUM_REQUESTS)"
fi
echo ""

# ── 5. Compare RequestCount per target group ──
echo "▸ Checking CloudWatch RequestCount per target group (last 5 min)..."
echo ""

ALB_SUFFIX=$(echo "$ALB_ARN" | sed 's|.*:loadbalancer/||')
START_TIME=$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-5M +%Y-%m-%dT%H:%M:%S)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

for TG_NAME in "${APP_NAME}-${ENV}-tg" "${APP_NAME}-${ENV}-canary-tg"; do
  TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --region "$REGION" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "$TG_ARN" = "NOT_FOUND" ] || [ "$TG_ARN" = "None" ]; then
    continue
  fi

  TG_SUFFIX=$(echo "$TG_ARN" | sed 's|.*:targetgroup/|targetgroup/|')

  COUNT=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ApplicationELB \
    --metric-name RequestCount \
    --dimensions "Name=TargetGroup,Value=$TG_SUFFIX" "Name=LoadBalancer,Value=$ALB_SUFFIX" \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --period 300 \
    --statistics Sum \
    --region "$REGION" \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "N/A")

  echo "  $TG_NAME: $COUNT requests"
done

echo ""
echo "═══════════════════════════════════════════════════"
echo " Done! Compare request counts to verify weight split."
echo "═══════════════════════════════════════════════════"
