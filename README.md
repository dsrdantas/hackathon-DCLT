# 🚀 SolidaryTech — Hackathon FIAP TC5

Plataforma de doações e voluntariado desenvolvida como projeto do **Hackathon Fase 5 (TC5)** da FIAP.

Aplica conceitos de **SRE, FinOps, Kubernetes, GitOps, IaC e Observabilidade** em um ambiente AWS real.

---

## 📋 Índice

- [Arquitetura](#-arquitetura)
- [Estrutura do Repositório](#-estrutura-do-repositório)
- [Microsserviços](#-microsserviços)
- [Infraestrutura AWS (Terraform)](#-infraestrutura-aws-terraform)
- [GitOps — ArgoCD](#-gitops--argocd)
- [CI/CD — GitHub Actions](#-cicd--github-actions)
- [Observabilidade](#-observabilidade)
- [Secrets e Variáveis do GitHub](#-secrets-e-variáveis-do-github)
- [Credenciais AWS Academy](#-credenciais-aws-academy)
- [Executando Localmente](#-executando-localmente)
- [Primeiro Deploy em Produção](#-primeiro-deploy-em-produção)

---

## 🏗️ Arquitetura

```
Internet
    │
    ▼
AWS NLB (LoadBalancer)
    │
    ▼
Traefik Ingress Controller (EKS)
    │
    ├── /ngo        ──▶  ngo-service      (Python/Flask + PostgreSQL/RDS)
    ├── /donation   ──▶  donation-service (Go + PostgreSQL/RDS + SQS)
    └── /volunteer  ──▶  volunteer-service (Python/Flask + DynamoDB)

Observabilidade:
    Services ──OTLP──▶ OTel Collector ──▶ Prometheus / Grafana
                                      ──▶ New Relic (OTLP HTTP)

Secrets:
    AWS Secrets Manager ◀──── Terraform cria
    ESO ClusterSecretStore ──▶ K8s Secrets ──▶ Deployments
    Stakater Reloader ──▶ RollingUpdate automático ao atualizar Secret
```

---

## 📁 Estrutura do Repositório

```
hackathon-DCLT/
│
├── .github/
│   └── workflows/
│       ├── ngo-service.yml          # CI/CD: test → scan → build → deploy
│       ├── donation-service.yml     # CI/CD: test → scan → build → deploy
│       ├── volunteer-service.yml    # CI/CD: test → scan → build → deploy
│       ├── terraform.yml            # Terraform: validate → plan → apply
│       └── update-aws-credentials.yml  # Injeta credenciais AWS Academy no EKS
│
├── ngo-service/                     # Python 3.11 / Flask
│   ├── Dockerfile                   # Multi-stage: python:3.11-slim → slim
│   ├── app.py                       # API + OTel traces/metrics/logs
│   ├── requirements.txt             # Flask, psycopg2, opentelemetry-*
│   └── db/init.sql                  # Schema da tabela ngos
│
├── donation-service/                # Go 1.25
│   ├── Dockerfile                   # Multi-stage: golang:1.25-alpine → distroless
│   ├── main.go                      # API + OTel traces/metrics + slog JSON
│   ├── go.mod / go.sum              # Deps: otel v1.43.0, grpc v1.80.0
│   └── db/init.sql                  # Schema da tabela donations
│
├── volunteer-service/               # Python 3.11 / Flask
│   ├── Dockerfile                   # Multi-stage: python:3.11-slim → slim
│   ├── app.py                       # API + OTel traces/metrics/logs
│   ├── requirements.txt             # Flask, boto3, opentelemetry-*
│   └── (sem banco relacional — usa DynamoDB)
│
├── gitops/                          # Manifestos Kubernetes (monitorados pelo ArgoCD)
│   ├── argocd-apps.yaml             # AppProject + 6 Applications
│   ├── traefik/
│   │   ├── ingressroutes.yaml       # Rotas centralizadas: /ngo /donation /volunteer
│   │   └── middlewares.yaml         # StripPrefix + SecureHeaders
│   ├── external-secrets/
│   │   └── cluster-secret-store.yaml # ClusterSecretStore → AWS Secrets Manager
│   ├── ngo-service/
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml          # ← image tag atualizada automaticamente pelo CI
│   │   ├── service.yaml
│   │   ├── hpa.yaml
│   │   └── external-secret.yaml     # ExternalSecret → K8s Secret
│   ├── donation-service/
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── hpa.yaml
│   │   └── external-secret.yaml
│   ├── volunteer-service/
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── hpa.yaml
│   │   └── external-secret.yaml
│   └── observability/
│       ├── servicemonitors.yaml     # Prometheus ServiceMonitors (OTel + serviços)
│       └── grafana-dashboard.yaml   # Dashboard SolidaryTech (importado automaticamente)
│
├── terraform/                       # Infraestrutura como Código
│   ├── main.tf                      # Orquestração dos módulos
│   ├── variables.tf / terraform.tfvars
│   ├── providers.tf                 # AWS + Helm + Kubernetes providers
│   ├── backend.tf                   # S3 backend + DynamoDB lock
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/                     # VPC + subnets públicas/privadas
│       ├── eks/                     # Cluster EKS + node group
│       ├── rds/                     # PostgreSQL (ngo_db, donation_db)
│       ├── elasticache/             # Redis
│       ├── sqs/                     # Fila solidary-donations
│       ├── dynamodb/                # Tabela SolidaryTechVolunteers
│       ├── secrets/                 # AWS Secrets Manager (um secret por serviço)
│       ├── gitops/                  # ArgoCD, Traefik, ESO, Reloader, Prometheus, OTel
│       └── finops/                  # Budgets, alertas e anomaly detection
│
├── scripts/
│   ├── postgres/init.sql            # Schema local para desenvolvimento
│   └── localstack/init-aws.sh       # Cria DynamoDB + SQS no LocalStack
│
└── docker-compose.yml               # Stack completa para desenvolvimento local
```

---

## 🔧 Microsserviços

### 1️⃣ NGO Service — Cadastro de ONGs

| Item | Valor |
|---|---|
| Linguagem | Python 3.11 |
| Framework | Flask 2.2 |
| Banco | PostgreSQL (RDS) |
| Porta | `8081` |
| Rota pública | `http://<lb>/ngo/ngos` |
| Secret K8s | `ngo-service-secrets` → `database-url` |

**Endpoints:**
```
GET  /health      → status do serviço
GET  /ngos        → lista todas as ONGs
POST /ngos        → cria nova ONG (name, email, cause, city)
```

**Observabilidade:** traces automáticos via `FlaskInstrumentor` + `Psycopg2Instrumentor`, métricas `ngo_created_total` / `ngo_errors_total`, logs JSON com `trace_id`.

---

### 2️⃣ Donation Service — Processamento de Doações

| Item | Valor |
|---|---|
| Linguagem | Go 1.25 |
| Banco | PostgreSQL (RDS) |
| Mensageria | AWS SQS |
| Porta | `8082` |
| Rota pública | `http://<lb>/donation/donations` |
| Secret K8s | `donation-service-secrets` → `database-url`, `sqs-queue-url` |

**Endpoints:**
```
GET  /health     → status do serviço
GET  /donations  → lista todas as doações
POST /donations  → processa doação (ngo_id, amount, donor_name)
```

**Observabilidade:** traces via `otelhttp` middleware, métricas `donation_created_total` / `donation_errors_total`, logs JSON via `slog.NewJSONHandler`.

---

### 3️⃣ Volunteer Service — Gestão de Voluntários

| Item | Valor |
|---|---|
| Linguagem | Python 3.11 |
| Framework | Flask 2.2 |
| Banco | AWS DynamoDB |
| Porta | `8083` |
| Rota pública | `http://<lb>/volunteer/volunteers` |
| Secret K8s | `volunteer-service-secrets` → `dynamodb-table`, `aws-region` |

**Endpoints:**
```
GET  /health                 → status do serviço
GET  /volunteers/<ngo_id>    → voluntários de uma ONG
POST /volunteers             → registra voluntário (name, email, ngo_id)
```

**Observabilidade:** traces via `FlaskInstrumentor` + `BotocoreInstrumentor`, métricas `volunteer_registered_total` / `volunteer_errors_total`, logs JSON com `trace_id`.

---

## ☁️ Infraestrutura AWS (Terraform)

### Módulos e recursos criados

| Módulo | Recursos AWS |
|---|---|
| `vpc` | VPC + 4 tipos de subnet (public, eks, rds, elasticache) + NAT Gateway |
| `eks` | Cluster EKS 1.33 + Node Group (t3.medium, 2–4 nós) |
| `rds` | 2× RDS PostgreSQL 16 (ngo_db, donation_db) via `for_each` |
| `elasticache` | Redis 7.1 (1 nó cache.t3.micro) |
| `sqs` | Fila Standard `solidary-donations` |
| `dynamodb` | Tabela `SolidaryTechVolunteers` (PAY_PER_REQUEST) |
| `secrets` | 3× AWS Secrets Manager (um por serviço) com valores dos outputs |
| `gitops` | ECR ×3, ArgoCD, Traefik, ESO, Reloader, Prometheus Stack, OTel Collector |
| `finops` | AWS Budgets + Anomaly Detection + tags estruturadas |

### Helm releases gerenciadas pelo módulo `gitops`

| Release | Chart | Namespace | Finalidade |
|---|---|---|---|
| ArgoCD | `argo-cd` 7.6.8 | `argocd` | GitOps controller |
| Traefik | `traefik` 32.1.0 | `traefik` | Ingress + NLB |
| ESO | `external-secrets` 0.10.3 | `external-secrets` | Sync SM → K8s Secrets |
| Reloader | `reloader` 1.0.72 | `kube-system` | Restart automático ao atualizar Secret |
| metrics-server | `metrics-server` 3.12.1 | `kube-system` | Necessário para HPA |
| kube-prometheus-stack | 65.1.1 | `monitoring` | Prometheus + Grafana + AlertManager |
| OTel Collector | 0.108.0 | `observability` | Pipeline OTLP → Prometheus + New Relic |

### Comandos Terraform

```bash
cd terraform

# Primeira execução: criar VPC e EKS antes dos demais módulos
terraform apply -target=module.vpc -target=module.eks

# Aplicar tudo (segunda execução)
terraform apply

# Apenas validar sem criar recursos
terraform plan
```

> **Backend:** Estado armazenado em S3 com lock via DynamoDB.  
> Configure os recursos do backend executando `terraform/scripts/init-backend.sh` antes do primeiro `terraform init`.

---

## 🔄 GitOps — ArgoCD

O ArgoCD monitora este repositório (`branch: main`) e sincroniza automaticamente as Applications.

### AppProject `solidarytech` — Applications e sync-waves

| Application | Wave | Path no repo | Namespace destino |
|---|---|---|---|
| `external-secrets-config` | `-1` | `gitops/external-secrets/` | `external-secrets` |
| `traefik-routes` | `-1` | `gitops/traefik/` | `traefik` |
| `observability` | `-1` | `gitops/observability/` | `observability` |
| `ngo-service` | `0` | `gitops/ngo-service/` | `ngo` |
| `donation-service` | `0` | `gitops/donation-service/` | `donation` |
| `volunteer-service` | `0` | `gitops/volunteer-service/` | `volunteer` |

> Wave `-1` garante que ESO, Traefik e Prometheus ServiceMonitors existam antes dos microserviços.

### Fluxo de Secrets (sem IRSA)

> **⚠️ Restrição AWS Academy:** a `LabRole` não permite criar IAM roles ou OIDC providers.  
> Todos os secrets são injetados via credenciais estáticas — nunca via IRSA.

```
GitHub Secrets (AWS_ACCESS_KEY_ID / SECRET / TOKEN)
        │
        ▼ (workflow: update-aws-credentials)
K8s Secret "aws-academy-credentials" (namespace: external-secrets)
        │
        ▼ ESO ClusterSecretStore
AWS Secrets Manager
  solidarytech/prod/ngo-service
  solidarytech/prod/donation-service
  solidarytech/prod/volunteer-service
        │
        ▼ ExternalSecret (por namespace de serviço)
K8s Secret "<service>-secrets"
        │
        ▼ Deployment (env.valueFrom.secretKeyRef)
        │
        ▼ Stakater Reloader → RollingUpdate automático
```

### Comandos ArgoCD úteis

```bash
# Senha do admin ArgoCD
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath='{.data.password}' | base64 -d

# Interface web (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Acesse: http://localhost:8080  (admin / senha acima)

# Sync manual de uma application
argocd app sync ngo-service --prune

# Status de todas as applications
argocd app list
```

### Traefik — Rotas e LoadBalancer

```bash
# Obter hostname do NLB
kubectl get svc traefik -n traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

| Rota | Serviço interno | Porta |
|---|---|---|
| `http://<lb>/ngo/*` | `ngo-service.ngo` | 8081 |
| `http://<lb>/donation/*` | `donation-service.donation` | 8082 |
| `http://<lb>/volunteer/*` | `volunteer-service.volunteer` | 8083 |

---

## ⚙️ CI/CD — GitHub Actions

### Pipeline por serviço

```
push (path filter) → test → security-scan → build-push → update-manifest
                                                ↑
                                        apenas branch main
```

### Job 1 — Test

| Serviço | Ferramenta | O que valida |
|---|---|---|
| ngo-service | pytest / importação | Importação do módulo + testes unitários |
| donation-service | `go test` + `go vet` | Race conditions + erros de compilação |
| volunteer-service | pytest / importação | Importação do módulo + testes unitários |

### Job 2 — Security Scan

| Ferramenta | Serviço | Comportamento |
|---|---|---|
| **Bandit** (HIGH+) | Python | **Bloqueante** — falha em HIGH/CRITICAL |
| **govulncheck** | Go | Informativo — reporta mesmo CVEs sem fix disponível |
| **Trivy fs** (`exit-code: 1`) | Todos | **Bloqueante** — falha em CRITICAL/HIGH com fix disponível |
| **Trivy image** (`exit-code: 1`) | Todos (build-push) | **Bloqueante** — gate final antes do ECR |

> `ignore-unfixed: true` no Trivy evita bloqueio por CVEs sem versão corrigida.

### Job 3 — Build & Push ECR

- Plataforma: **`linux/amd64`** (sempre — obrigatório para EKS x86)
- Tag: `<run_number>-<short_sha>` (ex: `42-a3f9c12`)
- Também tageia como `latest`
- Cache de camadas via GitHub Actions cache

### Job 4 — Update Manifest

- Checkout com `GIT_TOKEN`
- `sed` substitui a linha `image:` no `deployment.yaml`
- Commit com `[skip ci]` para evitar loop infinito

### Workflow especial: `update-aws-credentials`

Executado **manualmente** sempre que renovar as credenciais no AWS Academy:

1. Valida credenciais com `aws sts get-caller-identity`
2. Atualiza kubeconfig do EKS
3. Cria/atualiza K8s Secret `aws-academy-credentials` (namespace `external-secrets`)
4. Cria/atualiza K8s Secret `new-relic-credentials` (namespace `observability`)
5. Força re-sync de todos os `ExternalSecrets`

```bash
# Executar via GitHub CLI
gh workflow run update-aws-credentials.yml

# Ou via interface: Actions → "Update AWS Academy Credentials" → Run workflow
```

---

## 📊 Observabilidade

### Stack de observabilidade

```
Serviços (ngo, donation, volunteer)
    │  OpenTelemetry SDK
    │  OTLP HTTP → http://otel-collector.observability:4318
    ▼
OTel Collector (namespace: observability)
    │
    ├──▶ Prometheus exporter (:8889)
    │         │
    │         ▼ (ServiceMonitor)
    │    Prometheus (namespace: monitoring)
    │         │
    │         ▼
    │    Grafana (namespace: monitoring)
    │    Dashboard: "SolidaryTech — Visão Geral"
    │
    └──▶ OTLP HTTP → New Relic
              endpoint: https://otlp.nr-data.net:4318
              auth: NEW_RELIC_LICENSE_KEY
```

### Acessar Grafana

```bash
# Port-forward
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Acesse: http://localhost:3000  (admin / solidarytech-grafana)

# Senha configurada no Terraform (terraform.tfvars ou variável)
```

### Métricas de negócio por serviço

| Métrica | Serviço | Descrição |
|---|---|---|
| `solidarytech_ngo_created_total` | ngo-service | ONGs criadas com sucesso |
| `solidarytech_ngo_errors_total` | ngo-service | Erros ao criar/buscar ONGs |
| `solidarytech_donation_created_total` | donation-service | Doações processadas |
| `solidarytech_donation_errors_total` | donation-service | Erros no processamento |
| `solidarytech_volunteer_registered_total` | volunteer-service | Voluntários registrados |
| `solidarytech_volunteer_errors_total` | volunteer-service | Erros no registro |

### Variáveis de ambiente OTel (injetadas via deployment.yaml)

| Variável | Valor |
|---|---|
| `OTEL_SERVICE_NAME` | `<nome-do-serviço>` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector.observability:4318` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment=production,project=solidarytech` |

---

## 🔐 Secrets e Variáveis do GitHub

Configure em: **repositório → Settings → Secrets and variables → Actions**

### 🔑 Repository Secrets (Settings → Secrets → Actions → New repository secret)

Valores sensíveis que nunca aparecem em logs.

#### Credenciais AWS Academy (renovar a cada ~4h)

| Secret | Exemplo | Obter em |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `ASIA...` | AWS Academy → AWS Details → Show |
| `AWS_SECRET_ACCESS_KEY` | `wJalr...` | AWS Academy → AWS Details → Show |
| `AWS_SESSION_TOKEN` | `IQoJb3Jp...` (longo) | AWS Academy → AWS Details → Show |

#### Credenciais AWS permanentes

| Secret | Exemplo | Descrição |
|---|---|---|
| `AWS_ACCOUNT_ID` | `123456789012` | ID da conta AWS (12 dígitos, sem hifens) |

#### GitHub

| Secret | Como criar | Descrição |
|---|---|---|
| `GIT_TOKEN` | GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens | PAT com permissão **Contents: Read and write** neste repositório. Necessário para o job `update-manifest` fazer push no `deployment.yaml`. |

#### Infraestrutura

| Secret | Exemplo | Descrição |
|---|---|---|
| `RDS_PASSWORD` | `MinhaS3nha!Segura` | Senha do usuário `tc5` no PostgreSQL. Usada pelo Terraform para criar o RDS e popular o Secrets Manager. Escolha uma senha forte. |

#### Observabilidade (opcional)

| Secret | Como obter | Descrição |
|---|---|---|
| `NEW_RELIC_LICENSE_KEY` | New Relic → API Keys → Create key (tipo **INGEST - LICENSE**) | Chave de ingestão do New Relic. Sem ela, o OTel Collector funciona apenas com Prometheus/Grafana local. |

---

### 📋 Checklist de criação dos secrets

```
GitHub → Settings → Secrets and variables → Actions → Secrets

□ AWS_ACCESS_KEY_ID       (temporário — atualizar a cada sessão Academy)
□ AWS_SECRET_ACCESS_KEY   (temporário — atualizar a cada sessão Academy)
□ AWS_SESSION_TOKEN       (temporário — atualizar a cada sessão Academy)
□ AWS_ACCOUNT_ID          (permanente — ID da sua conta AWS)
□ GIT_TOKEN               (permanente — PAT com Contents: write)
□ RDS_PASSWORD            (permanente — senha do PostgreSQL)
□ NEW_RELIC_LICENSE_KEY   (opcional  — chave de ingestão New Relic)
```

> **Dica:** use o [GitHub CLI](https://cli.github.com/) para criar todos de uma vez:
> ```bash
> gh secret set AWS_ACCESS_KEY_ID     --body "ASIA..."
> gh secret set AWS_SECRET_ACCESS_KEY --body "wJalr..."
> gh secret set AWS_SESSION_TOKEN     --body "IQoJb3Jp..."
> gh secret set AWS_ACCOUNT_ID        --body "123456789012"
> gh secret set GIT_TOKEN             --body "github_pat_..."
> gh secret set RDS_PASSWORD          --body "MinhaS3nha!"
> gh secret set NEW_RELIC_LICENSE_KEY --body "eu01xx..."  # opcional
> ```

---

## 🔑 Credenciais AWS Academy

> ⚠️ O AWS Academy emite credenciais **temporárias com validade de ~4 horas**.  
> Sempre que a sessão expirar, repita o processo abaixo.

### Como obter as credenciais

1. Acesse o **AWS Academy Learner Lab**
2. Clique em **Start Lab** (aguarde ficar verde)
3. Clique em **AWS Details**
4. Clique em **Show** ao lado de *AWS CLI*
5. Copie os valores de:
   - `aws_access_key_id`
   - `aws_secret_access_key`
   - `aws_session_token`

### Como atualizar

**Passo 1 — Atualizar os 3 secrets no GitHub:**

```bash
gh secret set AWS_ACCESS_KEY_ID     --body "<valor copiado>"
gh secret set AWS_SECRET_ACCESS_KEY --body "<valor copiado>"
gh secret set AWS_SESSION_TOKEN     --body "<valor copiado>"
```

**Passo 2 — Executar o workflow de atualização:**

```bash
gh workflow run update-aws-credentials.yml
# ou: GitHub → Actions → "Update AWS Academy Credentials" → Run workflow
```

Esse workflow:
- Valida as credenciais
- Atualiza o K8s Secret `aws-academy-credentials` no cluster
- Força o ESO a re-sincronizar todos os ExternalSecrets
- O Stakater Reloader detecta a mudança e reinicia os Deployments automaticamente

---

## 🐳 Executando Localmente

### Pré-requisitos

| Ferramenta | Versão mínima |
|---|---|
| Docker | 24+ |
| Docker Compose v2 | qualquer |

### Subir a stack completa

```bash
# Construir imagens e subir todos os containers
docker compose up --build

# Em background
docker compose up --build -d
```

### Serviços e portas locais

| Container | URL | Tecnologia |
|---|---|---|
| `tc5-postgres` | `localhost:5432` | PostgreSQL 16 |
| `tc5-localstack` | `localhost:4566` | AWS DynamoDB + SQS simulados |
| `tc5-ngo-service` | http://localhost:8081 | Python / Flask |
| `tc5-donation-service` | http://localhost:8082 | Go |
| `tc5-volunteer-service` | http://localhost:8083 | Python / Flask |

> Em ambiente local, o OTel Collector não está disponível.  
> Os serviços tentam conectar ao endpoint OTel configurado e falham silenciosamente — o serviço continua funcionando normalmente.

### Variáveis de ambiente locais (Docker Compose)

#### donation-service
> ⚠️ A variável de ambiente correta é `SQS_QUEUE_URL` (não `AWS_SQS_URL`).

| Variável | Valor local |
|---|---|
| `PORT` | `8082` |
| `DATABASE_URL` | `postgres://tc5:supersenha@postgres:5432/donation_db` |
| `AWS_REGION` | `us-east-1` |
| `SQS_QUEUE_URL` | `http://localstack:4566/000000000000/solidary-donations` |
| `AWS_ENDPOINT_URL` | `http://localstack:4566` |

#### volunteer-service
> ⚠️ A variável de ambiente correta é `DYNAMODB_TABLE` (não `AWS_DYNAMODB_TABLE`).

| Variável | Valor local |
|---|---|
| `PORT` | `8083` |
| `AWS_REGION` | `us-east-1` |
| `DYNAMODB_TABLE` | `SolidaryTechVolunteers` |
| `AWS_ENDPOINT_URL` | `http://localstack:4566` |

### Testando os endpoints

```bash
# Health checks
curl http://localhost:8081/health
curl http://localhost:8082/health
curl http://localhost:8083/health

# Criar ONG
curl -s -X POST http://localhost:8081/ngos \
  -H "Content-Type: application/json" \
  -d '{"name":"Instituto Esperança","email":"contato@esperanca.org","cause":"Educação","city":"São Paulo"}' | jq .

# Criar doação
curl -s -X POST http://localhost:8082/donations \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":150.00,"donor_name":"Maria Silva"}' | jq .

# Registrar voluntário
curl -s -X POST http://localhost:8083/volunteers \
  -H "Content-Type: application/json" \
  -d '{"name":"João Souza","email":"joao@email.com","ngo_id":1}' | jq .

# Buscar voluntários de uma ONG
curl -s http://localhost:8083/volunteers/1 | jq .
```

### Comandos úteis

```bash
docker compose logs -f                        # todos os serviços
docker compose logs -f donation-service       # serviço específico
docker compose ps                             # status dos containers
docker compose down -v                        # parar e apagar dados
docker compose build ngo-service              # reconstruir imagem específica
```

---

## 🚀 Primeiro Deploy em Produção

### Pré-requisitos

- [ ] Todos os [Secrets do GitHub](#-secrets-e-variáveis-do-github) configurados
- [ ] AWS Academy com sessão ativa e credenciais no GitHub
- [ ] Terraform instalado (>= 1.5)
- [ ] AWS CLI configurado localmente com as credenciais Academy
- [ ] kubectl instalado

### Passo 1 — Inicializar backend do Terraform

```bash
cd terraform

# Criar S3 bucket e tabela DynamoDB para o estado
bash scripts/init-backend.sh

terraform init
```

### Passo 2 — Criar VPC e EKS primeiro

```bash
terraform apply -target=module.vpc -target=module.eks
# Aguarde ~15 minutos para o cluster EKS ficar pronto
```

### Passo 3 — Aplicar toda a infraestrutura

```bash
terraform apply
# Cria RDS, ElastiCache, SQS, DynamoDB, Secrets Manager,
# ECR, ArgoCD, Traefik, ESO, Reloader, Prometheus, OTel Collector
# e executa o bootstrap do ArgoCD (aplica gitops/argocd-apps.yaml)
```

### Passo 4 — Injetar credenciais AWS no cluster

```bash
gh workflow run update-aws-credentials.yml
# Aguarde o workflow finalizar (cria aws-academy-credentials + new-relic-credentials)
```

### Passo 5 — Aguardar ESO sincronizar os Secrets

```bash
kubectl get externalsecret -A   # deve mostrar "SecretSynced"
kubectl get secret ngo-service-secrets -n ngo
kubectl get secret donation-service-secrets -n donation
kubectl get secret volunteer-service-secrets -n volunteer
```

### Passo 6 — Primeiro push para disparar os pipelines CI/CD

```bash
# Qualquer mudança em um serviço dispara o pipeline
git commit --allow-empty -m "ci: trigger initial deploy"
git push origin main
```

### Passo 7 — Verificar deploy

```bash
# Obter endpoint do LoadBalancer
kubectl get svc traefik -n traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Testar health check via Traefik
LB="<hostname acima>"
curl http://$LB/ngo/health
curl http://$LB/donation/health
curl http://$LB/volunteer/health
```

---

## 📦 Repositórios ECR

Criados automaticamente pelo Terraform:

| Repositório | Retenção |
|---|---|
| `solidarytech-prod-ngo-service` | Últimas 10 imagens |
| `solidarytech-prod-donation-service` | Últimas 10 imagens |
| `solidarytech-prod-volunteer-service` | Últimas 10 imagens |

Scan automático de vulnerabilidades a cada push (`scan_on_push = true`).

---

## 🔧 Correções e Ajustes Realizados

### Variáveis de ambiente corrigidas

| Serviço | Variável antiga (incorreta) | Variável correta |
|---|---|---|
| `volunteer-service` | `AWS_DYNAMODB_TABLE` | `DYNAMODB_TABLE` |
| `donation-service` | `AWS_SQS_URL` | `SQS_QUEUE_URL` |

### Dependências do donation-service atualizadas (CVEs)

| Pacote | Versão anterior | Versão atual | CVEs corrigidos |
|---|---|---|---|
| `go.opentelemetry.io/otel/sdk` | v1.28.0 | **v1.43.0** | CVE-2026-24051, CVE-2026-39883 (HIGH) |
| `golang.org/x/crypto` | v0.24.0 | **v0.49.0** | CVE-2024-45337 (CRITICAL), CVE-2025-22869 (HIGH) |
| `google.golang.org/grpc` | v1.64.0 | **v1.80.0** | CVE-2026-33186 (CRITICAL) |
| `golang.org/x/net` | v0.26.0 | **v0.52.0** | CVE-2026-4918 (HIGH) |
| Go runtime | 1.21 | **1.25** | CVEs do stdlib (x509, crypto/tls, net/url, database/sql) |

### Security scan — comportamento por tipo de scan

| Scan | exit-code | Comportamento |
|---|---|---|
| Trivy `fs` (source) | `1` | Bloqueia pipeline se encontrar CRITICAL/HIGH **com fix disponível** |
| Trivy `image` (ECR) | `1` | Bloqueia pipeline se imagem publicada tiver CRITICAL/HIGH com fix |
| govulncheck | informativo | Reporta tudo incluindo CVEs sem fix — não bloqueia (ex: pgproto3/v2) |
| Bandit (Python) | `1` para HIGH | Bloqueia em findings de alta severidade e alta confiança |

---

## 🤝 Contribuição

Projeto criado para fins educacionais — Hackathon FIAP TC5.

---

## 🏁 Boa sorte!

Bom Hackathon 🚀 — Faça a diferença com a **SolidaryTech** 💙
