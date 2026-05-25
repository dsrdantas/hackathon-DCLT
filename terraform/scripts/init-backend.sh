#!/bin/bash
# =============================================================
# init-backend.sh
# Valida e cria o bucket S3 e a tabela DynamoDB do backend
# antes de executar o terraform init.
# =============================================================
set -e

BUCKET="tc4-tm"
TABLE="tc4-terraform-lock"
REGION="us-east-1"

echo "────────────────────────────────────────────────"
echo " SolidaryTech — Validação do Backend Terraform  "
echo "────────────────────────────────────────────────"

# ── S3 Bucket ────────────────────────────────────────────────
echo "[S3] Verificando bucket: $BUCKET ..."

if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
  echo "[S3] Bucket já existe. OK."
else
  echo "[S3] Bucket não encontrado. Criando..."
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || \
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION"

  echo "[S3] Habilitando versionamento..."
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled \
    --region "$REGION"

  echo "[S3] Habilitando criptografia SSE-S3..."
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }' \
    --region "$REGION"

  echo "[S3] Bloqueando acesso público..."
  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --region "$REGION"

  echo "[S3] Bucket criado com sucesso."
fi

# ── DynamoDB Table ────────────────────────────────────────────
echo "[DynamoDB] Verificando tabela: $TABLE ..."

if aws dynamodb describe-table \
    --table-name "$TABLE" \
    --region "$REGION" \
    --output text 2>/dev/null | grep -q ACTIVE; then
  echo "[DynamoDB] Tabela já existe. OK."
else
  echo "[DynamoDB] Tabela não encontrada. Criando..."
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  echo "[DynamoDB] Aguardando tabela ficar ACTIVE..."
  aws dynamodb wait table-exists \
    --table-name "$TABLE" \
    --region "$REGION"

  echo "[DynamoDB] Tabela criada com sucesso."
fi

echo "────────────────────────────────────────────────"
echo " Backend validado! Executando terraform init... "
echo "────────────────────────────────────────────────"

terraform init
