# ─────────────────────────────────────────────
# Stage 1 — builder
# Instala dependências em um venv isolado
# ─────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Cria o virtualenv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copia só o requirements primeiro (cache layer)
COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# ─────────────────────────────────────────────
# Stage 2 — runtime
# Imagem final enxuta, sem ferramentas de build
# ─────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Usuário não-root por segurança
RUN addgroup --system app && adduser --system --ingroup app app

WORKDIR /app

# Copia o venv já pronto do stage anterior
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copia o código da aplicação
COPY --chown=app:app . .

USER app

EXPOSE 8081

CMD ["gunicorn", "--bind", "0.0.0.0:8081", "--workers", "2", "--threads", "2", "app:app"]
