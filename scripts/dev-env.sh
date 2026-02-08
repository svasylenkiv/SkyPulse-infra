#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# dev-env.sh — Піднімання/опускання dev середовища для економії
#
# Використання:
#   ./scripts/dev-env.sh sleep          # Зупинити таски (ECS → 0)
#   ./scripts/dev-env.sh wake  [count]  # Піднять таски (default: 2)
#   ./scripts/dev-env.sh status         # Поточний стан
#   ./scripts/dev-env.sh nap            # Зупинити таски + NAT Gateway
#   ./scripts/dev-env.sh rise [count]   # Піднять таски + NAT Gateway
#
# Режими:
#   sleep/wake — швидкий (секунди). Зупиняє Fargate-таски,
#                NAT та ALB продовжують працювати (~$48/міс).
#   nap/rise   — глибокий (хвилини). Додатково видаляє NAT Gateway,
#                економить ще ~$32/міс. ALB залишається (~$16/міс).
#
# Приклади:
#   ./scripts/dev-env.sh sleep          # Зупинити на ніч
#   ./scripts/dev-env.sh wake 1         # Піднять 1 таск (замість 2)
#   ./scripts/dev-env.sh nap            # Глибокий сон (макс. економія)
#   ./scripts/dev-env.sh rise           # Повне відновлення
#   ./scripts/dev-env.sh status         # Подивитися, що працює
# ──────────────────────────────────────────────────────────────
set -euo pipefail

ACTION="${1:-status}"
REGION="${AWS_REGION:-us-east-1}"
APP_NAME="skypulsenew"
ENV="dev"
PREFIX="${APP_NAME}-${ENV}"
CLUSTER="${PREFIX}-ecs"
SERVICE="${PREFIX}-svc"
DEFAULT_DESIRED=2
DEFAULT_MIN=2
DEFAULT_MAX=4

# ── Кольори ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

header() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${CYAN} SkyPulse Dev Environment — ${1}${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo ""
}

# ──────────────────────────────────────────────────────────────
# STATUS — показати поточний стан всіх ресурсів
# ──────────────────────────────────────────────────────────────
cmd_status() {
  header "Статус"

  # ECS
  echo -e "${YELLOW}▸ ECS Service:${NC}"
  SVC_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}' \
    --output json 2>/dev/null || echo '{"error": "not found"}')
  echo "  $SVC_INFO"
  echo ""

  # Auto Scaling
  echo -e "${YELLOW}▸ Auto Scaling:${NC}"
  SCALING=$(aws application-autoscaling describe-scalable-targets \
    --service-namespace ecs \
    --resource-ids "service/${CLUSTER}/${SERVICE}" \
    --region "$REGION" \
    --query 'ScalableTargets[0].{Min:minCapacity,Max:maxCapacity,Suspended:suspendedState}' \
    --output json 2>/dev/null || echo '{"error": "not found"}')
  echo "  $SCALING"
  echo ""

  # NAT Gateway
  echo -e "${YELLOW}▸ NAT Gateway:${NC}"
  NAT_COUNT=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=${PREFIX}-nat" "Name=state,Values=available" \
    --region "$REGION" \
    --query 'length(NatGateways)' \
    --output text 2>/dev/null || echo "0")

  if [ "$NAT_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}Active${NC} ($NAT_COUNT)"
  else
    echo -e "  ${RED}Не знайдено / Видалено${NC}"
  fi
  echo ""

  # ALB
  echo -e "${YELLOW}▸ ALB:${NC}"
  ALB_STATE=$(aws elbv2 describe-load-balancers \
    --names "${PREFIX}-alb" \
    --region "$REGION" \
    --query 'LoadBalancers[0].State.Code' \
    --output text 2>/dev/null || echo "not found")
  echo "  State: $ALB_STATE"
  echo ""

  # Приблизні кости
  echo -e "${YELLOW}▸ Приблизна вартість ($/міс):${NC}"
  RUNNING=$(echo "$SVC_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Running',0))" 2>/dev/null || echo "0")
  FARGATE_COST=$(echo "$RUNNING * 29" | bc 2>/dev/null || echo "?")
  NAT_COST=$( [ "$NAT_COUNT" -gt 0 ] && echo "32" || echo "0")
  ALB_COST=$( [ "$ALB_STATE" = "active" ] && echo "16" || echo "0")

  echo "  ECS Fargate:  ~\$${FARGATE_COST} ($RUNNING tasks × \$29)"
  echo "  NAT Gateway:  ~\$${NAT_COST}"
  echo "  ALB:          ~\$${ALB_COST}"
  TOTAL=$(echo "${FARGATE_COST:-0} + ${NAT_COST} + ${ALB_COST}" | bc 2>/dev/null || echo "?")
  echo -e "  ${CYAN}Разом:       ~\$${TOTAL}/міс${NC}"
}

# ──────────────────────────────────────────────────────────────
# SLEEP — зупинити ECS таски (швидко)
# ──────────────────────────────────────────────────────────────
cmd_sleep() {
  header "Sleep (зупинка тасків)"

  echo -e "${YELLOW}▸ Призупинення autoscaling...${NC}"
  aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id "service/${CLUSTER}/${SERVICE}" \
    --scalable-dimension "ecs:service:DesiredCount" \
    --min-capacity 0 \
    --max-capacity 0 \
    --region "$REGION" >/dev/null
  echo -e "  ${GREEN}✓${NC} Autoscaling min/max = 0"

  echo -e "${YELLOW}▸ Зупинка ECS service (desired_count → 0)...${NC}"
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --desired-count 0 \
    --region "$REGION" >/dev/null
  echo -e "  ${GREEN}✓${NC} desired_count = 0"

  echo ""
  echo -e "${GREEN}Dev середовище засинає.${NC}"
  echo -e "Економія: ~\$58/міс (Fargate). NAT+ALB ще працюють (~\$48/міс)."
  echo -e "Для повного сну використайте: ${CYAN}$0 nap${NC}"
}

# ──────────────────────────────────────────────────────────────
# WAKE — піднятии ECS таски (швидко)
# ──────────────────────────────────────────────────────────────
cmd_wake() {
  local COUNT="${2:-$DEFAULT_DESIRED}"
  header "Wake (підняття тасків: ${COUNT})"

  echo -e "${YELLOW}▸ Відновлення autoscaling...${NC}"
  aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id "service/${CLUSTER}/${SERVICE}" \
    --scalable-dimension "ecs:service:DesiredCount" \
    --min-capacity "$DEFAULT_MIN" \
    --max-capacity "$DEFAULT_MAX" \
    --region "$REGION" >/dev/null
  echo -e "  ${GREEN}✓${NC} Autoscaling min=${DEFAULT_MIN}, max=${DEFAULT_MAX}"

  echo -e "${YELLOW}▸ Запуск ECS service (desired_count → ${COUNT})...${NC}"
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --desired-count "$COUNT" \
    --region "$REGION" >/dev/null
  echo -e "  ${GREEN}✓${NC} desired_count = ${COUNT}"

  echo ""
  echo -e "${GREEN}Dev середовище прокидається!${NC}"
  echo "Таски запустяться протягом 1-2 хвилин."
}

# ──────────────────────────────────────────────────────────────
# NAP — глибокий сон: ECS → 0 + видалити NAT Gateway
# ──────────────────────────────────────────────────────────────
cmd_nap() {
  header "Nap (глибокий сон: ECS + NAT)"

  # Спочатку зупинити таски
  cmd_sleep

  echo ""
  echo -e "${YELLOW}▸ Пошук NAT Gateway...${NC}"
  NAT_ID=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=${PREFIX}-nat" "Name=state,Values=available" \
    --region "$REGION" \
    --query 'NatGateways[0].NatGatewayId' \
    --output text 2>/dev/null || echo "None")

  if [ "$NAT_ID" = "None" ] || [ -z "$NAT_ID" ]; then
    echo -e "  ${YELLOW}NAT Gateway вже видалено або не знайдено${NC}"
  else
    echo -e "${YELLOW}▸ Видалення NAT Gateway ${NAT_ID}...${NC}"
    aws ec2 delete-nat-gateway \
      --nat-gateway-id "$NAT_ID" \
      --region "$REGION" >/dev/null
    echo -e "  ${GREEN}✓${NC} NAT Gateway видаляється (займе ~1-2 хв)"
  fi

  # Зберігаємо EIP allocation ID у тезі для відновлення
  EIP_ALLOC=$(aws ec2 describe-addresses \
    --filters "Name=tag:Name,Values=${PREFIX}-nat-eip" \
    --region "$REGION" \
    --query 'Addresses[0].AllocationId' \
    --output text 2>/dev/null || echo "None")

  echo ""
  echo -e "${GREEN}Глибокий сон активовано.${NC}"
  echo -e "Економія: ~\$90/міс (Fargate + NAT). ALB ще працює (~\$16/міс)."
  echo ""
  echo -e "${YELLOW}⚠  Для відновлення використайте: ${CYAN}$0 rise${NC}"
  echo -e "${YELLOW}⚠  Або перезапустіть terraform apply щоб відтворити NAT.${NC}"

  if [ "$EIP_ALLOC" != "None" ] && [ -n "$EIP_ALLOC" ]; then
    echo -e "${YELLOW}⚠  EIP збережено (${EIP_ALLOC}). При rise буде створено новий NAT з цим EIP.${NC}"
  fi
}

# ──────────────────────────────────────────────────────────────
# RISE — повне відновлення: NAT Gateway + ECS таски
# ──────────────────────────────────────────────────────────────
cmd_rise() {
  local COUNT="${2:-$DEFAULT_DESIRED}"
  header "Rise (повне відновлення)"

  # Перевірити чи NAT вже є
  NAT_ID=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=${PREFIX}-nat" "Name=state,Values=available" \
    --region "$REGION" \
    --query 'NatGateways[0].NatGatewayId' \
    --output text 2>/dev/null || echo "None")

  if [ "$NAT_ID" != "None" ] && [ -n "$NAT_ID" ]; then
    echo -e "  ${GREEN}NAT Gateway вже активний (${NAT_ID})${NC}"
  else
    echo -e "${YELLOW}▸ Відновлення NAT Gateway...${NC}"

    # Знайти EIP
    EIP_ALLOC=$(aws ec2 describe-addresses \
      --filters "Name=tag:Name,Values=${PREFIX}-nat-eip" \
      --region "$REGION" \
      --query 'Addresses[0].AllocationId' \
      --output text 2>/dev/null || echo "None")

    if [ "$EIP_ALLOC" = "None" ] || [ -z "$EIP_ALLOC" ]; then
      echo -e "  ${RED}✗ EIP не знайдено. Запустіть terraform apply для повного відновлення.${NC}"
      echo ""
    else
      # Знайти перший public subnet
      SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=${PREFIX}-pub-1" \
        --region "$REGION" \
        --query 'Subnets[0].SubnetId' \
        --output text 2>/dev/null || echo "None")

      if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
        echo -e "  ${RED}✗ Public subnet не знайдено. Запустіть terraform apply.${NC}"
      else
        NEW_NAT_ID=$(aws ec2 create-nat-gateway \
          --allocation-id "$EIP_ALLOC" \
          --subnet-id "$SUBNET_ID" \
          --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${PREFIX}-nat}]" \
          --region "$REGION" \
          --query 'NatGateway.NatGatewayId' \
          --output text)
        echo -e "  ${GREEN}✓${NC} NAT Gateway створюється: ${NEW_NAT_ID}"
        echo -e "  Очікуємо доступність (до 2 хв)..."

        aws ec2 wait nat-gateway-available \
          --nat-gateway-ids "$NEW_NAT_ID" \
          --region "$REGION" 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} NAT Gateway доступний!"

        # Оновити private route table
        RT_ID=$(aws ec2 describe-route-tables \
          --filters "Name=tag:Name,Values=${PREFIX}-priv-rt" \
          --region "$REGION" \
          --query 'RouteTables[0].RouteTableId' \
          --output text 2>/dev/null || echo "None")

        if [ "$RT_ID" != "None" ] && [ -n "$RT_ID" ]; then
          aws ec2 replace-route \
            --route-table-id "$RT_ID" \
            --destination-cidr-block "0.0.0.0/0" \
            --nat-gateway-id "$NEW_NAT_ID" \
            --region "$REGION" >/dev/null
          echo -e "  ${GREEN}✓${NC} Private route table оновлено"
        fi
      fi
    fi
  fi

  echo ""
  # Піднімаємо ECS
  cmd_wake "$@"
}

# ──────────────────────────────────────────────────────────────
# HELP
# ──────────────────────────────────────────────────────────────
cmd_help() {
  header "Допомога"
  echo "Використання: $0 <command> [options]"
  echo ""
  echo "Команди:"
  echo "  status          Показати поточний стан і приблизні кости"
  echo "  sleep           Зупинити ECS таски (швидко, ~секунди)"
  echo "  wake  [count]   Піднятии ECS таски (default: ${DEFAULT_DESIRED})"
  echo "  nap             Глибокий сон: ECS + видалити NAT Gateway"
  echo "  rise [count]    Повне відновлення: NAT + ECS"
  echo "  help            Ця допомога"
  echo ""
  echo "Приклади:"
  echo "  $0 sleep          # Зупинити на ніч (Fargate = \$0)"
  echo "  $0 wake 1         # Піднятии 1 таск замість 2"
  echo "  $0 nap            # Макс. економія (NAT + Fargate = \$0)"
  echo "  $0 rise           # Повне відновлення"
}

# ── Dispatch ──
case "$ACTION" in
  status) cmd_status ;;
  sleep)  cmd_sleep ;;
  wake)   cmd_wake "$@" ;;
  nap)    cmd_nap ;;
  rise)   cmd_rise "$@" ;;
  help|--help|-h) cmd_help ;;
  *)
    echo -e "${RED}Невідома команда: ${ACTION}${NC}"
    cmd_help
    exit 1
    ;;
esac
