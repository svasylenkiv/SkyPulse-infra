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
├── .github/
│   └── workflows/
│       ├── bootstrap.yml           # Створення S3 + DynamoDB для state
│       └── terraform-deploy.yml    # Terraform plan / apply / destroy
├── bootstrap/
│   └── main.tf                     # Terraform: S3 bucket + DynamoDB (local state)
├── modules/
│   └── skypulse/                 # shared module (вся інфра)
│       ├── main.tf               # ECS cluster, service, task definition, CloudWatch
│       ├── variables.tf          # input variables
│       ├── outputs.tf            # outputs
│       ├── vpc.tf                # VPC, subnets, IGW, routes
│       ├── alb.tf                # ALB, target group, listener
│       ├── ecr.tf                # ECR repo (conditional)
│       ├── iam.tf                # IAM roles
│       ├── security_groups.tf    # Security Groups
│       └── autoscaling.tf        # App Auto Scaling
├── environments/
│   ├── dev/
│   │   ├── main.tf               # module call + provider
│   │   ├── terraform.tfvars      # dev values
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

## CI/CD (GitHub Actions)

Два окремі workflow:

| Workflow | Файл | Призначення |
|----------|-------|-------------|
| **Bootstrap State Backend** | `bootstrap.yml` | Створює S3 bucket + DynamoDB для Terraform state |
| **Terraform Deploy** | `terraform-deploy.yml` | Plan / Apply / Destroy інфраструктури |

### Налаштування секретів

Додай ці секрети в GitHub репозиторій (`Settings → Secrets and variables → Actions`):

| Секрет | Опис |
|--------|------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Key |

### Порядок першого деплою

```
1. Bootstrap State Backend  — один раз, створює S3 + DynamoDB
2. Terraform Deploy: dev  (apply)  — створює ECR + всю інфраструктуру
3. Terraform Deploy: stg  (apply)  — використовує ECR з dev
4. Terraform Deploy: prd  (apply)  — використовує ECR з dev
```

### Bootstrap State Backend

Запускається **один раз** перед першим деплоєм. Створює:
- S3 bucket `skypulse-tf-state` (versioning, encryption, block public access)
- DynamoDB таблиця `skypulse-tf-lock` (state locking)

Запуск: **Actions** → **Bootstrap State Backend** → **Run workflow**

### Terraform Deploy

Запуск: **Actions** → **Terraform Deploy** → **Run workflow**

Інпути:
- **environment**: `dev` / `stg` / `prd`
- **action**: `plan` / `apply` / `destroy`

## Локальне використання

### Розгортання dev

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### Розгортання stg / prd

```bash
cd environments/stg
terraform init
terraform plan -var="ecr_repository_url=<ECR_URL_FROM_DEV>"
terraform apply -var="ecr_repository_url=<ECR_URL_FROM_DEV>"
```

### Збірка та push Docker образу

```bash
ECR_URL=$(terraform -chdir=environments/dev output -raw ecr_repository_url)
AWS_REGION="us-east-1"

# Логін в ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL

# Збірка та push
cd ../SkyPulse
docker build -t $ECR_URL:dev-latest .
docker push $ECR_URL:dev-latest
```

### Оновлення сервісу

```bash
aws ecs update-service \
  --cluster SkyPulse-dev-ecs \
  --service SkyPulse-dev-svc \
  --force-new-deployment
```

## Видалення

Видаляй у зворотному порядку:

```bash
# Через GitHub Actions:  Destroy prd → stg → dev

# Або локально:
terraform -chdir=environments/prd destroy
terraform -chdir=environments/stg destroy
terraform -chdir=environments/dev destroy   # останнім, бо має ECR
```
