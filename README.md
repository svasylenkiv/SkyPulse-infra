# SkyPulse Infrastructure

Terraform конфігурація для деплою [SkyPulse](https://github.com/svasylenkiv/SkyPulse) на AWS Fargate.

## Архітектура

```
Internet → ALB (port 80) → ECS Fargate Service → Container (port 8080)
```

### Ресурси

| Ресурс | Опис |
|--------|------|
| **VPC** | Окрема мережа з 2 публічними сабнетами в різних AZ |
| **ALB** | Application Load Balancer, приймає HTTP трафік |
| **ECS Cluster** | Fargate кластер |
| **ECS Service** | Сервіс з бажаною кількістю задач |
| **Task Definition** | Опис контейнера (CPU, RAM, порт, логи) |
| **ECR** | Container Registry для Docker образів |
| **IAM** | Ролі для ECS execution та task |
| **CloudWatch** | Логи контейнерів (зберігаються 7 днів) |
| **Security Groups** | ALB: HTTP 80 з інтернету; ECS: порт 8080 тільки від ALB |

## Вимоги

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) з налаштованими credentials
- Docker (для збірки та пушу образу)

## Використання

### 1. Налаштування

```bash
cp terraform.tfvars.example terraform.tfvars
# Відредагуй terraform.tfvars під свої потреби
```

### 2. Розгортання інфраструктури

```bash
terraform init
terraform plan
terraform apply
```

### 3. Збірка та push Docker образу

```bash
# Отримай ECR URL з outputs
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "eu-central-1")

# Логін в ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL

# Збірка та push (з папки SkyPulse)
cd ../SkyPulse
docker build -t $ECR_URL:latest .
docker push $ECR_URL:latest
```

### 4. Оновлення сервісу

```bash
aws ecs update-service \
  --cluster skypulse-cluster \
  --service skypulse-service \
  --force-new-deployment
```

### 5. Відкриття додатку

```bash
terraform output alb_dns_name
# Відкрий URL в браузері
```

## Видалення

```bash
terraform destroy
```

## Структура файлів

```
SkyPulse-infra/
├── providers.tf          # Terraform та AWS провайдер
├── variables.tf          # Змінні
├── vpc.tf                # VPC, сабнети, маршрутизація
├── security_groups.tf    # Security groups для ALB та ECS
├── ecr.tf                # Container Registry
├── iam.tf                # IAM ролі для ECS
├── alb.tf                # Load Balancer + Target Group
├── ecs.tf                # ECS Cluster, Task Definition, Service
├── outputs.tf            # Виходні значення
└── terraform.tfvars.example
```
