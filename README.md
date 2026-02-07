# SkyPulse Infrastructure

Terraform конфігурація для деплою [SkyPulse](https://github.com/svasylenkiv/SkyPulse) на AWS Fargate з підтримкою **dev / stg / prd** середовищ.

## Архітектура

```
Internet → ALB (port 80) → ECS Fargate Service → Container (port 8080)
```

Кожне середовище (dev, stg, prd) розгортається як повністю ізольований стек зі своєю VPC, ALB, ECS кластером та сервісом. ECR реєстр **спільний** — створюється в dev і використовується всіма середовищами.

### Ресурси (на кожне середовище)

| Ресурс | Опис |
|--------|------|
| **VPC** | Окрема мережа з 2 публічними сабнетами в різних AZ |
| **ALB** | Application Load Balancer, приймає HTTP трафік |
| **ECS Cluster** | Fargate кластер |
| **ECS Service** | Сервіс з автоскейлінгом |
| **Task Definition** | Опис контейнера (CPU, RAM, порт, логи) |
| **ECR** | Container Registry для Docker образів (спільний) |
| **IAM** | Ролі для ECS execution та task |
| **CloudWatch** | Логи контейнерів (зберігаються 7 днів) |
| **Security Groups** | ALB: HTTP 80 з інтернету; ECS: порт 8080 тільки від ALB |
| **Auto Scaling** | Target Tracking за CPU utilization |

### Параметри по середовищах

| Параметр | dev | stg | prd |
|----------|-----|-----|-----|
| CPU | 256 | 256 | 512 |
| Memory | 512 | 512 | 1024 |
| Min tasks | 1 | 1 | 2 |
| Max tasks | 1 | 2 | 4 |
| CPU target | 70% | 70% | 60% |

## Структура файлів

```
SkyPulse-infra/
├── modules/
│   └── skypulse/              # shared module (вся інфра)
│       ├── main.tf            # ECS cluster, service, task definition, CloudWatch
│       ├── variables.tf       # input variables
│       ├── outputs.tf         # outputs
│       ├── vpc.tf             # VPC, subnets, IGW, routes
│       ├── alb.tf             # ALB, target group, listener
│       ├── ecr.tf             # ECR repo (conditional)
│       ├── iam.tf             # IAM roles
│       ├── security_groups.tf # Security Groups
│       └── autoscaling.tf     # App Auto Scaling
├── environments/
│   ├── dev/
│   │   ├── main.tf            # module call + provider
│   │   ├── terraform.tfvars   # dev values
│   │   └── outputs.tf
│   ├── stg/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── outputs.tf
│   └── prd/
│       ├── main.tf
│       ├── terraform.tfvars
│       └── outputs.tf
└── README.md
```

## Вимоги

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) з налаштованими credentials
- Docker (для збірки та пушу образу)

## Використання

### 1. Розгортання dev (створює ECR)

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

Збережи ECR URL з outputs:

```bash
terraform output ecr_repository_url
```

### 2. Розгортання stg / prd

Для stg та prd потрібно передати ECR URL з dev:

```bash
cd environments/stg
terraform init
terraform plan -var="ecr_repository_url=<ECR_URL_FROM_DEV>"
terraform apply -var="ecr_repository_url=<ECR_URL_FROM_DEV>"
```

Аналогічно для prd:

```bash
cd environments/prd
terraform init
terraform plan -var="ecr_repository_url=<ECR_URL_FROM_DEV>"
terraform apply -var="ecr_repository_url=<ECR_URL_FROM_DEV>"
```

### 3. Збірка та push Docker образу

```bash
# Отримай ECR URL
ECR_URL=$(terraform -chdir=environments/dev output -raw ecr_repository_url)
AWS_REGION="eu-central-1"

# Логін в ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL

# Збірка та push (з папки SkyPulse)
cd ../SkyPulse
docker build -t $ECR_URL:dev-latest .
docker push $ECR_URL:dev-latest

# Для інших середовищ:
# docker tag $ECR_URL:dev-latest $ECR_URL:stg-latest
# docker push $ECR_URL:stg-latest
```

### 4. Оновлення сервісу

```bash
# Dev
aws ecs update-service \
  --cluster skypulse-dev-cluster \
  --service skypulse-dev-service \
  --force-new-deployment

# Stg
aws ecs update-service \
  --cluster skypulse-stg-cluster \
  --service skypulse-stg-service \
  --force-new-deployment
```

### 5. Відкриття додатку

```bash
terraform -chdir=environments/dev output alb_dns_name
```

## Видалення

Видаляй у зворотному порядку:

```bash
terraform -chdir=environments/prd destroy
terraform -chdir=environments/stg destroy
terraform -chdir=environments/dev destroy   # останнім, бо має ECR
```
