-- Cria o segundo banco de dados (ngo_db já é criado pela variável POSTGRES_DB)
CREATE DATABASE donation_db;

-- Garante que o usuário tc5 tem acesso total a ambos
GRANT ALL PRIVILEGES ON DATABASE ngo_db     TO tc5;
GRANT ALL PRIVILEGES ON DATABASE donation_db TO tc5;
