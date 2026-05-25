#!/bin/bash
set -e

echo "──────────────────────────────────────────"
echo " Inicializando bancos PostgreSQL"
echo "──────────────────────────────────────────"

# Cria o segundo banco (ngo_db já existe via POSTGRES_DB)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE donation_db;
    GRANT ALL PRIVILEGES ON DATABASE donation_db TO $POSTGRES_USER;
EOSQL

echo "[ngo_db] Executando ngo-service/db/init.sql..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "ngo_db" \
    -f /docker-entrypoint-initdb.d/ngo-init.sql

echo "[donation_db] Executando donation-service/db/init.sql..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "donation_db" \
    -f /docker-entrypoint-initdb.d/donation-init.sql

echo "──────────────────────────────────────────"
echo " Bancos inicializados com sucesso!"
echo "──────────────────────────────────────────"
