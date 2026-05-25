# ─────────────────────────────────────────────
# Stage 1 — builder
# Compila o binário Go estático
# ─────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copia manifests primeiro (cache de dependências)
COPY go.mod go.sum* ./
RUN go mod download

# Copia o código e compila binário estático
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /donation-service .

# ─────────────────────────────────────────────
# Stage 2 — runtime
# Imagem mínima — só o binário compilado
# ─────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12 AS runtime

COPY --from=builder /donation-service /donation-service

EXPOSE 8082

ENTRYPOINT ["/donation-service"]
