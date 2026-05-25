#!/bin/bash
set -e

echo "──────────────────────────────────────────"
echo " Inicializando recursos AWS (LocalStack)"
echo "──────────────────────────────────────────"

# ── DynamoDB ──────────────────────────────────
echo "[DynamoDB] Criando tabela SolidaryTechVolunteers..."
awslocal dynamodb create-table \
  --table-name SolidaryTechVolunteers \
  --attribute-definitions \
      AttributeName=volunteer_id,AttributeType=S \
  --key-schema \
      AttributeName=volunteer_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

echo "[DynamoDB] Tabela SolidaryTechVolunteers criada com sucesso."

# ── SQS ───────────────────────────────────────
echo "[SQS] Criando fila solidary-donations (Standard)..."
awslocal sqs create-queue \
  --queue-name solidary-donations \
  --region us-east-1

echo "[SQS] Fila solidary-donations criada com sucesso."

echo "──────────────────────────────────────────"
echo " Recursos AWS inicializados!"
echo "──────────────────────────────────────────"
