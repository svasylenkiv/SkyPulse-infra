# Canary Deployment — SkyPulse

## Огляд

Canary deployment дозволяє направити невеликий відсоток трафіку (наприклад 10%) на нову версію додатка, перш ніж розкатити її на всіх користувачів. Це зменшує ризик деплою — якщо нова версія зламана, постраждає тільки 10% запитів.

## Архітектура

```
ALB
├── Listener Rule (weighted)
│   ├── 90% → Target Group: stable (v1)  ←  ECS Service: stable
│   └── 10% → Target Group: canary (v2)  ←  ECS Service: canary
```

Два ECS Service працюють паралельно в одному кластері:
- **Stable** — основна версія (image tag: `<env>-latest`)
- **Canary** — нова версія для тестування (image tag: `<env>-canary`)

ALB Listener розподіляє трафік між двома Target Groups з налаштовуваними вагами.

## Terraform-змінні

| Змінна | Тип | Default | Опис |
|--------|-----|---------|------|
| `canary_enabled` | bool | `false` | Увімкнути canary інфраструктуру (TG + ECS service) |
| `canary_weight` | number | `0` | Відсоток трафіку на canary (0-100) |
| `canary_image_tag` | string | `""` | Docker image tag для canary (default: `<env>-canary`) |

### Приклад: увімкнути canary з 10% трафіку

```hcl
module "skypulse" {
  source = "../../modules/skypulse"
  # ... інші параметри ...

  canary_enabled = true
  canary_weight  = 10
}
```

### Вимкнути canary

```hcl
module "skypulse" {
  # ...
  canary_enabled = false
  canary_weight  = 0
}
```

## GitHub Actions Workflow

Workflow **Canary Deploy** (`canary-deploy.yml`) підтримує 4 дії:

### 1. `deploy` — задеплоїти canary

Будує Docker-образ, реєструє нову task definition, оновлює canary ECS service та встановлює ваги трафіку.

**Параметри:**
- `environment` — dev / stg
- `canary_weight` — відсоток трафіку (default: 10)
- `image_tag` — кастомний тег (опціонально)

### 2. `set-weight` — змінити розподіл трафіку

Оновлює ваги ALB listener без перебілду образу.

### 3. `promote` — промоутнути canary на stable

Перетегує canary-образ як `<env>-latest`, перезапускає stable service, скидає ваги на 100/0.

### 4. `rollback` — відкатити canary

Повертає 100% трафіку на stable service.

## Процес Canary Deployment (покроково)

```
1. Запустити workflow: action=deploy, canary_weight=10
   └─ Будується новий образ з тегом dev-canary
   └─ Canary service оновлюється
   └─ ALB: 90% stable / 10% canary

2. Моніторинг (5-15 хв)
   └─ CloudWatch: CPU, Memory, 5xx errors
   └─ Перевірити /health на canary
   └─ Порівняти latency stable vs canary

3a. Якщо ОК → Promote
    └─ action=promote
    └─ Canary image → stable
    └─ 100% трафіку → stable

3b. Якщо ПОМИЛКИ → Rollback
    └─ action=rollback
    └─ 100% трафіку → stable
    └─ Canary залишається, але не отримує трафік
```

## Тестування weighted target groups

### Перевірка конфігурації ALB

```bash
# Отримати ARN ALB
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "skypulse-dev-alb" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# Перевірити listener rules та ваги
aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[].DefaultActions[].ForwardConfig.TargetGroups[].[TargetGroupArn,Weight]' \
  --output table
```

### Перевірка розподілу трафіку з hey

Для перевірки, що трафік розподіляється ~90/10, надішліть 200 запитів і порівняйте відповіді:

```bash
ALB_URL="http://skypulse-dev-alb-xxxx.us-east-1.elb.amazonaws.com"

# Надіслати 200 запитів
hey -n 200 -c 10 "$ALB_URL/health"
```

### Перевірка через response headers / логи

Canary service має змінну середовища `CANARY=true`. Якщо додаток повертає цю інформацію у відповіді (наприклад, у health endpoint), можна порахувати розподіл:

```bash
# Надіслати 100 запитів і порахувати canary vs stable
for i in $(seq 1 100); do
  curl -s "$ALB_URL/health"
  echo
done | sort | uniq -c
```

### Перевірка target group health

```bash
# Stable target group
aws elbv2 describe-target-health \
  --target-group-arn "$(aws elbv2 describe-target-groups \
    --names skypulse-dev-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)"

# Canary target group
aws elbv2 describe-target-health \
  --target-group-arn "$(aws elbv2 describe-target-groups \
    --names skypulse-dev-canary-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)"
```

### Перевірка в CloudWatch

Метрики для порівняння stable vs canary:
- `RequestCount` per target group
- `TargetResponseTime` per target group
- `HTTPCode_Target_5XX_Count` per target group

```bash
# Порівняти кількість запитів за останні 10 хвилин
for TG_NAME in "skypulse-dev-tg" "skypulse-dev-canary-tg"; do
  TG_ARN_SUFFIX=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --query 'TargetGroups[0].TargetGroupArn' --output text | \
    sed 's|.*:targetgroup/|targetgroup/|')

  echo "=== $TG_NAME ==="
  aws cloudwatch get-metric-statistics \
    --namespace AWS/ApplicationELB \
    --metric-name RequestCount \
    --dimensions "Name=TargetGroup,Value=$TG_ARN_SUFFIX" \
                 "Name=LoadBalancer,Value=$(aws elbv2 describe-load-balancers \
                   --names skypulse-dev-alb \
                   --query 'LoadBalancers[0].LoadBalancerArn' --output text | \
                   sed 's|.*:loadbalancer/||')" \
    --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 600 \
    --statistics Sum \
    --output table
done
```

Очікуваний результат при 90/10 split і ~200 запитах:
- Stable TG: ~180 запитів
- Canary TG: ~20 запитів

## Ресурси створені Terraform

Коли `canary_enabled = true`:

| Ресурс | Назва | Опис |
|--------|-------|------|
| Target Group | `skypulse-<env>-canary-tg` | Canary target group |
| Task Definition | `skypulse-<env>-canary-task` | Canary task definition |
| ECS Service | `skypulse-<env>-canary-svc` | Canary service (desired_count: 1) |

Коли `canary_enabled = false`:
- Canary ресурси не створюються
- ALB listener використовує простий forward без ваг
