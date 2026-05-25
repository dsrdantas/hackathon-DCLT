# 🚀 SolidaryTech — Hackathon Fase 5

Bem-vindo ao repositório oficial da **SolidaryTech**.

Este monorepo contém os microsserviços que compõem a plataforma da ONG e servirá como base para os desafios do Hackathon Fase 5.

O objetivo principal deste projeto é aplicar conceitos modernos de:

- SRE (Site Reliability Engineering)
- FinOps
- Multicloud
- ITSM
- Observabilidade
- Resiliência
- Kubernetes & GitOps
- Infraestrutura como Código (IaC)

---

# 🏗️ Arquitetura dos Microsserviços

O ecossistema é composto por **3 microsserviços independentes**, desenvolvidos com tecnologias diferentes para simular um ambiente corporativo distribuído.

---

## 1️⃣ NGO Service — Cadastro de ONGs

| Item | Valor |
|---|---|
| Linguagem | Python 3.9+ |
| Framework | Flask |
| Banco de Dados | PostgreSQL |
| Porta Local | `8081` |

### 📌 Descrição
Responsável pelo gerenciamento e cadastro das ONGs parceiras da plataforma.

---

## 2️⃣ Donation Service — Processamento de Doações

| Item | Valor |
|---|---|
| Linguagem | Go 1.21+ |
| Banco de Dados | PostgreSQL |
| Mensageria | AWS SQS |
| Porta Local | `8082` |

### 📌 Descrição
Este é o **Hot Path** da aplicação.

Responsável pelo processamento das doações e publicação de eventos assíncronos em filas para processamento posterior.

---

## 3️⃣ Volunteer Service — Gestão de Voluntários

| Item | Valor |
|---|---|
| Linguagem | Python 3.9+ |
| Framework | Flask |
| Banco de Dados | AWS DynamoDB |
| Porta Local | `8083` |

### 📌 Descrição
Gerencia o cadastro e inscrição de voluntários interessados em apoiar as ONGs parceiras.

Utiliza armazenamento NoSQL nativo da AWS com foco em escalabilidade.

---

# 📁 Estrutura do Repositório

```text
.
├── ngo-service/          # Código Python e scripts SQL do serviço de ONGs
├── donation-service/     # Código Go e scripts SQL do serviço de doações
└── volunteer-service/    # Código Python do serviço de voluntários
```

---

# 🚀 Executando Localmente

Antes de realizar deploy em Kubernetes e automatizações CI/CD, recomenda-se validar todo o ambiente localmente.

Existem duas formas de executar o projeto: **via Docker Compose** (recomendado) ou **manualmente** em terminais separados.

---

# 🐳 Opção A — Docker Compose (Recomendado)

Sobe toda a stack com um único comando: bancos de dados, filas, serviços e infraestrutura AWS simulada.

## Estrutura de arquivos

```text
.
├── docker-compose.yml
├── scripts/
│   ├── postgres/
│   │   └── init.sh                        # Cria os bancos e executa os SQLs de init
│   └── localstack/
│       └── init-aws.sh                    # Cria tabela DynamoDB e fila SQS
├── ngo-service/
│   ├── Dockerfile                         # Multi-stage (Python/venv)
│   ├── app.py
│   ├── requirements.txt
│   └── db/init.sql                        # Schema da tabela ngos
├── donation-service/
│   ├── Dockerfile                         # Multi-stage (Go/distroless)
│   ├── main.go
│   ├── go.mod
│   └── db/init.sql                        # Schema da tabela donations
└── volunteer-service/
    ├── Dockerfile                         # Multi-stage (Python/venv)
    ├── app.py
    └── requirements.txt
```

---

## ✅ Pré-requisitos

| Ferramenta | Versão mínima | Verificar |
|---|---|---|
| Docker | 24+ | `docker --version` |
| Docker Compose | v2 | `docker compose version` |

> Não é necessário instalar Python, Go, PostgreSQL ou AWS CLI localmente.

---

## ▶️ Subindo a stack

```bash
# Construir as imagens e subir todos os containers
docker compose up --build

# Em background (modo detached)
docker compose up --build -d
```

Aguarde as mensagens de inicialização. A ordem de boot é controlada automaticamente via `depends_on` + `healthcheck`:

```
postgres  ──(healthy)──▶  ngo-service
                      ──▶  donation-service ◀──(healthy)── localstack
                                                        ──▶ volunteer-service
```

---

## 🌐 Serviços e portas

| Container | Serviço | URL | Tecnologia |
|---|---|---|---|
| `tc5-postgres` | PostgreSQL | `localhost:5432` | PostgreSQL 16 |
| `tc5-localstack` | AWS (DynamoDB + SQS) | `localhost:4566` | LocalStack 3 |
| `tc5-ngo-service` | NGO Service | http://localhost:8081 | Python / Flask |
| `tc5-donation-service` | Donation Service | http://localhost:8082 | Go |
| `tc5-volunteer-service` | Volunteer Service | http://localhost:8083 | Python / Flask |

---

## 🔌 Strings de conexão

| Recurso | Conexão |
|---|---|
| **PostgreSQL — ngo_db** | `postgres://tc5:supersenha@localhost:5432/ngo_db` |
| **PostgreSQL — donation_db** | `postgres://tc5:supersenha@localhost:5432/donation_db` |
| **DynamoDB (LocalStack)** | endpoint `http://localhost:4566` / região `us-east-1` |
| **SQS (LocalStack)** | `http://localhost:4566/000000000000/solidary-donations` |

> **Credenciais AWS para LocalStack:** `AWS_ACCESS_KEY_ID=test` / `AWS_SECRET_ACCESS_KEY=test`

---

## ⚙️ Variáveis de ambiente (Docker Compose)

As variáveis são definidas diretamente no `docker-compose.yml`, não é necessário criar arquivos `.env` para rodar com Docker.

### ngo-service

| Variável | Valor |
|---|---|
| `PORT` | `8081` |
| `DATABASE_URL` | `postgres://tc5:supersenha@postgres:5432/ngo_db` |

### donation-service

| Variável | Valor |
|---|---|
| `PORT` | `8082` |
| `DATABASE_URL` | `postgres://tc5:supersenha@postgres:5432/donation_db` |
| `AWS_REGION` | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | `test` |
| `AWS_SECRET_ACCESS_KEY` | `test` |
| `AWS_ENDPOINT_URL` | `http://localstack:4566` |
| `AWS_SQS_URL` | `http://localstack:4566/000000000000/solidary-donations` |

### volunteer-service

| Variável | Valor |
|---|---|
| `PORT` | `8083` |
| `AWS_REGION` | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | `test` |
| `AWS_SECRET_ACCESS_KEY` | `test` |
| `AWS_ENDPOINT_URL` | `http://localstack:4566` |
| `AWS_DYNAMODB_TABLE` | `SolidaryTechVolunteers` |

---

## 🗄️ Bancos de dados e recursos AWS

### PostgreSQL

| Banco | Tabela principal | Inicializado por |
|---|---|---|
| `ngo_db` | `ngos` | `ngo-service/db/init.sql` |
| `donation_db` | `donations` | `donation-service/db/init.sql` |

> Os scripts de init rodam **apenas na primeira vez** que o volume é criado.  
> Para reinicializar do zero: `docker compose down -v && docker compose up --build`

### DynamoDB (LocalStack)

| Tabela | Partition Key | Tipo |
|---|---|---|
| `SolidaryTechVolunteers` | `volunteer_id` | `String` |

### SQS (LocalStack)

| Fila | Tipo |
|---|---|
| `solidary-donations` | Standard Queue |

---

## ✅ Verificando os recursos

```bash
# Health checks dos serviços
curl http://localhost:8081/health
curl http://localhost:8082/health
curl http://localhost:8083/health

# Listar tabelas DynamoDB
aws --endpoint-url=http://localhost:4566 dynamodb list-tables --region us-east-1

# Listar filas SQS
aws --endpoint-url=http://localhost:4566 sqs list-queues --region us-east-1

# Conectar no PostgreSQL
psql -h localhost -U tc5 -d ngo_db
psql -h localhost -U tc5 -d donation_db
```

---

## 🧪 Testando os endpoints

### NGO Service — `POST /ngos`

```bash
curl -s -X POST http://localhost:8081/ngos \
  -H "Content-Type: application/json" \
  -d '{"name":"Instituto Esperança","email":"contato@esperanca.org","cause":"Educação","city":"São Paulo"}' \
  | jq .
```

### NGO Service — `GET /ngos`

```bash
curl -s http://localhost:8081/ngos | jq .
```

### Donation Service — `POST /donations`

```bash
curl -s -X POST http://localhost:8082/donations \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":150.00,"donor_name":"Maria Silva"}' \
  | jq .
```

### Donation Service — `GET /donations`

```bash
curl -s http://localhost:8082/donations | jq .
```

### Volunteer Service — `POST /volunteers`

```bash
curl -s -X POST http://localhost:8083/volunteers \
  -H "Content-Type: application/json" \
  -d '{"name":"João Souza","email":"joao@email.com","ngo_id":1}' \
  | jq .
```

### Volunteer Service — `GET /volunteers/{ngo_id}`

```bash
curl -s http://localhost:8083/volunteers/1 | jq .
```

---

## 🛠️ Comandos úteis

```bash
# Ver logs de todos os serviços em tempo real
docker compose logs -f

# Ver logs de um serviço específico
docker compose logs -f ngo-service
docker compose logs -f donation-service
docker compose logs -f volunteer-service
docker compose logs -f localstack

# Ver status dos containers
docker compose ps

# Parar a stack (mantém volumes/dados)
docker compose down

# Parar e apagar todos os dados
docker compose down -v

# Reconstruir apenas um serviço
docker compose build ngo-service
docker compose up -d --no-deps ngo-service

# Reiniciar um serviço sem rebuild
docker compose restart donation-service
```

---

## 🏗️ Dockerfiles — estratégia multi-stage

| Serviço | Builder | Runtime | Resultado |
|---|---|---|---|
| `ngo-service` | `python:3.11-slim` + venv | `python:3.11-slim` | Sem compiladores na imagem final |
| `donation-service` | `golang:1.21-alpine` | `distroless/static` | Binário estático ~5MB, sem shell |
| `volunteer-service` | `python:3.11-slim` + venv | `python:3.11-slim` | Sem compiladores na imagem final |

---

# 💻 Opção B — Execução Manual (sem Docker)

## ✅ Pré-requisitos

- Python 3.9+
- Go 1.21+
- PostgreSQL instalado e rodando
- AWS CLI configurado com credenciais válidas

## 🛠️ Passo 1 — Preparação da Infraestrutura

### PostgreSQL

Crie dois bancos de dados e execute os scripts:

```bash
# ngo_db
psql -U seu_usuario -c "CREATE DATABASE ngo_db;"
psql -U seu_usuario -d ngo_db -f ngo-service/db/init.sql

# donation_db
psql -U seu_usuario -c "CREATE DATABASE donation_db;"
psql -U seu_usuario -d donation_db -f donation-service/db/init.sql
```

### AWS DynamoDB

Crie a tabela:

| Configuração | Valor |
|---|---|
| Nome da Tabela | `SolidaryTechVolunteers` |
| Partition Key | `volunteer_id` (String) |

### AWS SQS

Crie uma fila do tipo **Standard Queue** e guarde a URL:

```text
https://sqs.us-east-1.amazonaws.com/<account-id>/solidary-donations
```

## ⚙️ Passo 2 — Variáveis de Ambiente

Crie um arquivo `.env` dentro de cada microsserviço.

### `ngo-service/.env`

```env
PORT=8081
DATABASE_URL="postgres://SEU_USUARIO:SUA_SENHA@localhost:5432/ngo_db"
```

### `donation-service/.env`

```env
PORT=8082
DATABASE_URL="postgres://SEU_USUARIO:SUA_SENHA@localhost:5432/donation_db"
AWS_REGION="us-east-1"
AWS_SQS_URL="SUA_URL_DA_FILA_SQS"
```

### `volunteer-service/.env`

```env
PORT=8083
AWS_REGION="us-east-1"
AWS_DYNAMODB_TABLE="SolidaryTechVolunteers"
```

## ▶️ Passo 3 — Inicializando os Serviços

Abra **3 terminais separados**.

### 🟣 Terminal 1 — NGO Service

```bash
cd ngo-service
pip install -r requirements.txt
gunicorn --bind 0.0.0.0:8081 app:app
```

### 🟠 Terminal 2 — Donation Service

```bash
cd donation-service
go mod tidy
go run .
```

### 🔵 Terminal 3 — Volunteer Service

```bash
cd volunteer-service
pip install -r requirements.txt
gunicorn --bind 0.0.0.0:8083 app:app
```

---

# 🌐 Portas Locais

| Serviço | URL |
|---|---|
| NGO Service | http://localhost:8081 |
| Donation Service | http://localhost:8082 |
| Volunteer Service | http://localhost:8083 |

---

# 🔧 Melhorias e Correções Efetuadas

Registro das correções aplicadas durante a conteinerização e execução local da stack.

---

## 1. `donation-service` — Entrada inválida no `go.mod`

**Arquivo:** `donation-service/go.mod`

**Problema:** `github.com/jackc/pgx/v4/stdlib` estava listado como dependência independente no bloco `require`, com versão `v4.18.3`. O Go rejeitou essa entrada porque `stdlib` é um sub-pacote do módulo `pgx/v4`, não um módulo separado — e um path sem `/v4` no nome não pode ter versão `v4.x`.

```
go.mod:19:2: require github.com/jackc/pgx/v4/stdlib: version "v4.18.3" invalid: should be v0 or v1, not v4
```

**Correção:** Remoção da linha inválida. O pacote `stdlib` já é coberto pela dependência `github.com/jackc/pgx/v4 v4.18.3`.

---

## 2. `donation-service` — Imports não utilizados

**Arquivo:** `donation-service/main.go`

**Problema:** Os pacotes `fmt` e `strconv` estavam importados mas não eram usados em nenhum ponto do código. Em Go, imports não utilizados são **erro de compilação** (não apenas aviso).

```
./main.go:6:2: "fmt" imported and not used
./main.go:10:2: "strconv" imported and not used
```

**Correção:** Remoção dos dois imports.

---

## 3. `donation-service` — `go.sum` ausente

**Arquivo:** `donation-service/go.sum`

**Problema:** O arquivo `go.sum` não existia no repositório. O Go exige esse arquivo para verificar a integridade criptográfica das dependências — sem ele, o `go build` recusa compilar.

```
missing go.sum entry for module providing package github.com/aws/aws-sdk-go/aws
```

**Correção:** Execução de `go mod tidy` localmente para gerar o `go.sum`. O arquivo deve sempre ser commitado junto com o `go.mod`.

---

## 4. `ngo-service` / `volunteer-service` — Incompatibilidade Flask + Werkzeug

**Arquivos:** `ngo-service/requirements.txt`, `volunteer-service/requirements.txt`

**Problema:** `Flask==2.2.2` depende internamente de `werkzeug.urls.url_quote`, que foi **removido no Werkzeug 3.0+**. O `pip`, sem versão fixada, instalava a versão mais recente (3.x), causando falha na inicialização do Gunicorn.

```
ImportError: cannot import name 'url_quote' from 'werkzeug.urls'
```

**Correção:** Pin explícito `Werkzeug==2.3.8` — última versão estável da linha 2.x, totalmente compatível com Flask 2.2.

---

## 5. `ngo-service` — Autenticação SCRAM não suportada pelo `psycopg2-binary`

**Arquivo:** `ngo-service/requirements.txt`

**Problema:** `psycopg2-binary==2.9.5` vinha bundlado com uma versão antiga do `libpq` que não suportava o método de autenticação **SCRAM-SHA-256**, padrão no PostgreSQL 14+.

```
CRITICAL - Erro ao conectar ao PostgreSQL: SCRAM authentication requires libpq version 10 or above
```

**Correção:** Atualização para `psycopg2-binary==2.9.9`, que inclui `libpq 16` e suporta SCRAM-SHA-256.

---

## 6. `volunteer-service` — `boto3` antigo sem suporte a `AWS_ENDPOINT_URL`

**Arquivo:** `volunteer-service/requirements.txt`

**Problema:** `boto3==1.26.50` não reconhece a variável de ambiente `AWS_ENDPOINT_URL`. O suporte nativo a essa variável foi adicionado apenas no **boto3 1.28.0**. Com isso, todas as chamadas ao DynamoDB eram direcionadas para a AWS real, resultando em erro de autenticação com as credenciais fictícias do LocalStack.

```
UnrecognizedClientException: The security token included in the request is invalid.
```

**Correção:** Atualização para `boto3==1.34.0`.

---

## 7. `donation-service` — `aws-sdk-go v1` ignora `AWS_ENDPOINT_URL`

**Arquivo:** `donation-service/main.go`

**Problema:** O `aws-sdk-go v1` **nunca** lê a variável `AWS_ENDPOINT_URL` automaticamente (diferente do SDK v2). Sem um endpoint explícito na sessão, o SDK enviava as requisições SQS para a AWS real, falhando com as credenciais fictícias do LocalStack.

```
InvalidClientTokenId: The security token included in the request is invalid.
```

**Correção:** Leitura manual da variável `AWS_ENDPOINT_URL` e injeção em `aws.Config` antes de criar a sessão:

```go
awsCfg := &aws.Config{Region: aws.String(region)}
if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
    awsCfg.Endpoint = aws.String(endpoint)
}
sess, _ := session.NewSession(awsCfg)
```

---

# 🎯 Objetivos do Hackathon

O código fornecido representa apenas a base do software.

O verdadeiro desafio está na engenharia, operação e resiliência da plataforma.

---

# 📦 Conteinerização

- Criar Dockerfiles
- Otimizar imagens
- Implementar estratégias multi-stage build
- Reduzir vulnerabilidades

---

# ☁️ Infraestrutura como Código (Terraform)

Provisionar:

- Amazon EKS
- Amazon RDS
- Amazon ElastiCache
- Amazon SQS
- Amazon DynamoDB
- VPC, Subnets e Security Groups

## 💰 FinOps

Implementar:

- Tags estruturadas
- Controle de custos
- Rightsizing
- Budgets e alertas financeiros

---

# 🔄 CI/CD & GitOps

Automatizar:

- Testes
- Security Scans
- Build de imagens
- Deploy em Kubernetes

Ferramentas sugeridas:

- GitHub Actions
- ArgoCD
- FluxCD

---

# 📊 Observabilidade

Instrumentar os serviços utilizando:

- OpenTelemetry
- Distributed Tracing
- Métricas
- Logs estruturados

Ferramentas sugeridas:

- Grafana
- Prometheus
- Datadog
- New Relic

---

# 🛡️ SRE & Resiliência

Definir:

- SLIs
- SLOs
- Error Budgets
- Estratégias de Disaster Recovery
- Alertas inteligentes
- Health Checks
- Auto Healing

## 🔥 Foco Principal

O `donation-service` deve ser tratado como componente crítico da plataforma.

---

# 📚 Tecnologias Envolvidas

- Python
- Flask
- Go
- PostgreSQL
- DynamoDB
- AWS SQS
- Docker
- Kubernetes
- Terraform
- GitOps
- OpenTelemetry

---

# 🔄 CI/CD & GitOps

## Visão Geral

O pipeline de automação é composto por dois planos:

| Plano | Ferramentas | Responsabilidade |
|---|---|---|
| **CI** (Integração Contínua) | GitHub Actions | Testes, security scan, build e push de imagem para ECR |
| **CD** (Entrega Contínua) | ArgoCD + Traefik | Sincronização automática dos manifestos no cluster EKS |

```
Push → GitHub Actions → ECR (imagem) → atualiza tag no gitops/ → ArgoCD detecta mudança → deploy no EKS
```

---

## 📁 Estrutura dos Arquivos

```
.github/
└── workflows/
    ├── ngo-service.yml        # Pipeline do ngo-service (Python)
    ├── donation-service.yml   # Pipeline do donation-service (Go)
    ├── volunteer-service.yml  # Pipeline do volunteer-service (Python)
    └── terraform.yml          # Validação e apply da infraestrutura

gitops/
├── argocd-apps.yaml           # AppProject + Applications do ArgoCD
├── ngo-service/
│   ├── namespace.yaml
│   ├── deployment.yaml        # ← image tag atualizada automaticamente pelo CI
│   ├── service.yaml
│   ├── hpa.yaml
│   └── ingressroute.yaml      # Traefik IngressRoute
├── donation-service/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml         # SQS_QUEUE_URL, AWS_REGION
│   ├── hpa.yaml
│   └── ingressroute.yaml
└── volunteer-service/
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml         # DYNAMODB_TABLE, AWS_REGION
    ├── serviceaccount.yaml    # Pronto para IRSA
    ├── hpa.yaml
    └── ingressroute.yaml
```

---

## ⚙️ GitHub Actions — Jobs por Serviço

Cada workflow segue a mesma estrutura de 4 jobs encadeados:

```
test → security-scan → build-push → update-manifest
```

### Job 1 — Test

| Serviço | Ferramenta | O que valida |
|---|---|---|
| ngo-service | pytest | Testes unitários + importação do módulo |
| donation-service | go test + go vet | Race conditions + erros de compilação |
| volunteer-service | pytest | Testes unitários + importação do módulo |

### Job 2 — Security Scan

| Ferramenta | Aplicada em | Tipo |
|---|---|---|
| **Bandit** | ngo-service, volunteer-service | SAST Python |
| **govulncheck** | donation-service | Vulnerabilidades em deps Go |
| **Trivy (fs)** | todos | Scan de dependências + Dockerfile |
| **Trivy (image)** | todos | Scan da imagem publicada no ECR |

Resultados do Trivy são publicados no GitHub Security → Code Scanning (formato SARIF).

### Job 3 — Build & Push ECR

- Plataforma: **linux/amd64** (sempre)
- Tag da imagem: `<run_number>-<short_sha>` (ex: `42-a3f9c12`)
- Também tageia como `latest`
- Cache de camadas via GitHub Actions cache

### Job 4 — Update Manifest

- Faz checkout do repo com `GIT_TOKEN`
- Substitui via `sed` a linha da imagem no `deployment.yaml`
- Commit com mensagem `[skip ci]` para evitar loop

---

## 🔐 Secrets Necessários no GitHub

Configure em **Settings → Secrets and variables → Actions**:

| Secret | Descrição |
|---|---|
| `AWS_ACCESS_KEY_ID` | Credencial temporária do AWS Academy |
| `AWS_SECRET_ACCESS_KEY` | Credencial temporária do AWS Academy |
| `AWS_SESSION_TOKEN` | **Token de sessão do AWS Academy** (obrigatório com credenciais temporárias) |
| `AWS_ACCOUNT_ID` | ID da conta AWS (12 dígitos, sem hifens) |
| `GIT_TOKEN` | PAT com escopo `repo` para push nos manifestos |
| `RDS_PASSWORD` | Senha do PostgreSQL (usada no terraform plan) |

> ⚠️ **AWS Academy — credenciais temporárias (~4h)**
>
> O AWS Academy emite `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`
> com validade de aproximadamente 4 horas. Sempre que iniciar uma nova sessão no Learner Lab,
> copie as três credenciais do painel **"AWS Details"** e atualize os secrets correspondentes.
>
> Como obter:
> 1. Abra o **AWS Academy Learner Lab**
> 2. Clique em **"AWS Details"**
> 3. Clique em **"Show"** ao lado de *AWS CLI*
> 4. Copie os valores de `aws_access_key_id`, `aws_secret_access_key` e `aws_session_token`
> 5. Atualize os três secrets no GitHub antes de disparar os workflows

---

## 🚢 ArgoCD — GitOps

O ArgoCD é instalado via Terraform (`module.gitops`) e monitorado o repositório:

```
https://github.com/dsrdantas/hackathon-DCLT (branch: main)
```

### AppProject: `solidarytech`

Define os limites de acesso das Applications:
- **sourceRepos**: apenas o repo acima
- **destinations**: namespaces `ngo`, `donation`, `volunteer`
- **syncPolicy**: automático com prune + selfHeal

### Applications

| Application | Namespace | Path no repo |
|---|---|---|
| `ngo-service` | `ngo` | `gitops/ngo-service/` |
| `donation-service` | `donation` | `gitops/donation-service/` |
| `volunteer-service` | `volunteer` | `gitops/volunteer-service/` |

### Comandos úteis do ArgoCD

```bash
# Obter senha do admin
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath='{.data.password}' | base64 -d

# Port-forward para acessar a UI
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Forçar sync manual
argocd app sync ngo-service --prune

# Verificar status
argocd app list
```

---

## 🌐 Traefik — Ingress Controller

O Traefik é instalado via Helm com um **LoadBalancer** AWS NLB. As rotas são:

| Serviço | Rota | Porta interna |
|---|---|---|
| ngo-service | `http://<lb>/ngo/` | 8081 |
| donation-service | `http://<lb>/donation/` | 8082 |
| volunteer-service | `http://<lb>/volunteer/` | 8083 |

Para obter o hostname do LoadBalancer:

```bash
kubectl get svc traefik -n traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 📦 Repositórios ECR

Criados automaticamente pelo Terraform (`module.gitops`):

| Repositório | Lifecycle Policy |
|---|---|
| `solidarytech-prod-ngo-service` | Últimas 10 imagens |
| `solidarytech-prod-donation-service` | Últimas 10 imagens |
| `solidarytech-prod-volunteer-service` | Últimas 10 imagens |

Scan automático de vulnerabilidades a cada push (`scan_on_push = true`).

---

## 🔁 Fluxo Completo de Deploy

```
1. Developer faz push para main (com mudança em <service>/)
        ↓
2. GitHub Actions dispara o workflow do serviço
        ↓
3. test → security-scan (Bandit/govulncheck + Trivy)
        ↓
4. build-push: imagem linux/amd64 → ECR
               tag: <run>-<sha>
        ↓
5. update-manifest: sed atualiza deployment.yaml
                    git commit + push [skip ci]
        ↓
6. ArgoCD detecta mudança no repo (polling 3min ou webhook)
        ↓
7. ArgoCD aplica o manifesto atualizado no EKS
        ↓
8. Kubernetes faz RollingUpdate (maxSurge=1, maxUnavailable=0)
        ↓
9. HPA monitora CPU/memória → escala de 1 a 3 réplicas
```

---

## 🛠️ Primeiro Deploy (Ambiente Novo)

```bash
# 1. Criar recursos base primeiro (cluster EKS)
cd terraform
terraform apply -target=module.vpc -target=module.eks

# 2. Aplicar toda a infraestrutura (ArgoCD, Traefik, ECR, etc.)
terraform apply

# 3. O bootstrap do ArgoCD aplica gitops/argocd-apps.yaml automaticamente

# 4. Configurar as Secrets no Kubernetes (valores reais pós terraform apply)
kubectl create secret generic ngo-service-secrets \
  --from-literal=database-url="postgres://tc5:<senha>@<rds-endpoint>:5432/ngo_db" \
  -n ngo

kubectl create secret generic donation-service-secrets \
  --from-literal=database-url="postgres://tc5:<senha>@<rds-endpoint>:5432/donation_db" \
  -n donation

# 5. Fazer o primeiro push para disparar os pipelines
git push origin main
```

---

# 🤝 Contribuição

Este projeto foi criado exclusivamente para fins educacionais e execução do Hackathon Fase 5.

Sinta-se livre para evoluir a arquitetura, melhorar a observabilidade e implementar boas práticas de engenharia de plataforma.

---

# 🏁 Boa sorte!

Bom Hackathon 🚀

Faça a diferença com a **SolidaryTech** 💙