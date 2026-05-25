// donation-service — Go + PostgreSQL + AWS SQS
// Instrumentado com OpenTelemetry (traces, métricas) e slog JSON (logs estruturados).
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

// ── Modelos ───────────────────────────────────────────────────

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// ── Aplicação ─────────────────────────────────────────────────

type App struct {
	DB               *sql.DB
	SqsSvc           *sqs.SQS
	SqsQueueURL      string
	tracer           trace.Tracer
	donationCounter  metric.Int64Counter
	donationErrCount metric.Int64Counter
}

// ── OpenTelemetry bootstrap ───────────────────────────────────

func setupTelemetry(ctx context.Context) (func(context.Context) error, error) {
	otlpEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if otlpEndpoint == "" {
		otlpEndpoint = "http://otel-collector.observability:4318"
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("donation-service"),
			semconv.ServiceVersion(envOrDefault("APP_VERSION", "1.0.0")),
			attribute.String("deployment.environment", envOrDefault("APP_ENV", "production")),
		),
	)
	if err != nil {
		return nil, err
	}

	// ── Traces ────────────────────────────────────────────────
	traceExporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(otlpEndpoint),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)
	otel.SetTracerProvider(tp)

	// ── Métricas ──────────────────────────────────────────────
	metricExporter, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(otlpEndpoint),
		otlpmetrichttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter,
			sdkmetric.WithInterval(30*time.Second))),
		sdkmetric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	// Função de shutdown para defer no main
	shutdown := func(ctx context.Context) error {
		_ = tp.Shutdown(ctx)
		return mp.Shutdown(ctx)
	}
	return shutdown, nil
}

// ── main ──────────────────────────────────────────────────────

func main() {
	// Logs estruturados JSON
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	_ = godotenv.Load()

	ctx := context.Background()
	shutdown, err := setupTelemetry(ctx)
	if err != nil {
		slog.Error("falha ao inicializar telemetria", "error", err)
		// Não aborta: serviço funciona sem OTel em ambientes locais
	} else {
		defer func() {
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := shutdown(shutdownCtx); err != nil {
				slog.Error("erro ao fechar telemetria", "error", err)
			}
		}()
	}

	port := envOrDefault("PORT", "8082")

	// ── PostgreSQL ────────────────────────────────────────────
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		slog.Error("DATABASE_URL é obrigatória")
		os.Exit(1)
	}
	db, err := sql.Open("pgx", dbURL)
	if err != nil || db.PingContext(ctx) != nil {
		slog.Error("falha ao conectar ao banco de dados", "error", err)
		os.Exit(1)
	}
	slog.Info("conectado ao PostgreSQL", "service", "donation-service")

	// ── SQS ───────────────────────────────────────────────────
	// FIX: variável correta conforme definida no deployment.yaml
	var sqsSvc *sqs.SQS
	queueURL := os.Getenv("SQS_QUEUE_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		awsCfg := &aws.Config{Region: aws.String(region)}
		if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
			awsCfg.Endpoint = aws.String(endpoint)
		}
		sess, _ := session.NewSession(awsCfg)
		sqsSvc = sqs.New(sess)
		slog.Info("integração com AWS SQS ativada", "queue_url", queueURL)
	}

	// ── Métricas de negócio ───────────────────────────────────
	meter := otel.Meter("donation-service")
	donationCounter, _ := meter.Int64Counter(
		"donation_created_total",
		metric.WithDescription("Doações criadas com sucesso"),
	)
	donationErrCounter, _ := meter.Int64Counter(
		"donation_errors_total",
		metric.WithDescription("Erros ao criar/buscar doações"),
	)

	application := &App{
		DB:               db,
		SqsSvc:           sqsSvc,
		SqsQueueURL:      queueURL,
		tracer:           otel.Tracer("donation-service"),
		donationCounter:  donationCounter,
		donationErrCount: donationErrCounter,
	}

	// ── HTTP server com OTel middleware ───────────────────────
	mux := http.NewServeMux()
	mux.HandleFunc("/health", application.HealthHandler)
	mux.HandleFunc("/donations", application.DonationHandler)

	// otelhttp instrumenta automaticamente todos os endpoints:
	// latência, contagem de requisições e status HTTP como spans/métricas
	handler := otelhttp.NewHandler(mux, "donation-service",
		otelhttp.WithMessageEvents(otelhttp.ReadEvents, otelhttp.WriteEvents),
	)

	slog.Info("donation-service iniciado", "port", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		slog.Error("servidor encerrado com erro", "error", err)
		os.Exit(1)
	}
}

// ── Handlers ──────────────────────────────────────────────────

func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	switch r.Method {
	case http.MethodPost:
		a.createDonation(w, r)
	case http.MethodGet:
		a.listDonations(w, r)
	default:
		http.Error(w, `{"error":"Método não permitido"}`, http.StatusMethodNotAllowed)
	}
}

func (a *App) createDonation(w http.ResponseWriter, r *http.Request) {
	ctx, span := a.tracer.Start(r.Context(), "donation.create")
	defer span.End()

	var d Donation
	if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
		a.donationErrCount.Add(ctx, 1, metric.WithAttributes(attribute.String("reason", "invalid_payload")))
		span.SetAttributes(attribute.Bool("error", true), attribute.String("error.type", "invalid_payload"))
		http.Error(w, `{"error":"Payload inválido"}`, http.StatusBadRequest)
		return
	}

	d.Status = "APPROVED" // Simulação de gateway de pagamento
	span.SetAttributes(
		attribute.Int("donation.ngo_id", d.NgoID),
		attribute.Float64("donation.amount", d.Amount),
		attribute.String("donation.status", d.Status),
	)

	err := a.DB.QueryRowContext(ctx,
		"INSERT INTO donations (ngo_id, amount, donor_name, status) "+
			"VALUES ($1, $2, $3, $4) RETURNING id, created_at",
		d.NgoID, d.Amount, d.DonorName, d.Status,
	).Scan(&d.ID, &d.CreatedAt)

	if err != nil {
		a.donationErrCount.Add(ctx, 1, metric.WithAttributes(attribute.String("reason", "db_insert")))
		span.RecordError(err)
		span.SetAttributes(attribute.Bool("error", true))
		slog.ErrorContext(ctx, "erro ao salvar doação", "error", err)
		http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
		return
	}

	span.SetAttributes(attribute.Int("donation.id", d.ID))
	a.donationCounter.Add(ctx, 1, metric.WithAttributes(attribute.Int("ngo_id", d.NgoID)))
	slog.InfoContext(ctx, "doação criada", "donation_id", d.ID, "ngo_id", d.NgoID, "amount", d.Amount)

	if a.SqsSvc != nil {
		go a.sendNotificationEvent(d)
	}

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(d)
}

func (a *App) listDonations(w http.ResponseWriter, r *http.Request) {
	ctx, span := a.tracer.Start(r.Context(), "donation.list")
	defer span.End()

	rows, err := a.DB.QueryContext(ctx,
		"SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC",
	)
	if err != nil {
		a.donationErrCount.Add(ctx, 1, metric.WithAttributes(attribute.String("reason", "db_query")))
		span.RecordError(err)
		span.SetAttributes(attribute.Bool("error", true))
		slog.ErrorContext(ctx, "erro ao listar doações", "error", err)
		http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	donations := []Donation{}
	for rows.Next() {
		var d Donation
		_ = rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt)
		donations = append(donations, d)
	}

	span.SetAttributes(attribute.Int("donation.count", len(donations)))
	slog.InfoContext(ctx, "doações listadas", "count", len(donations))
	_ = json.NewEncoder(w).Encode(donations)
}

func (a *App) sendNotificationEvent(d Donation) {
	body, _ := json.Marshal(d)
	_, err := a.SqsSvc.SendMessage(&sqs.SendMessageInput{
		MessageBody: aws.String(string(body)),
		QueueUrl:    aws.String(a.SqsQueueURL),
	})
	if err != nil {
		slog.Error("falha ao despachar evento SQS", "donation_id", d.ID, "error", err)
	} else {
		slog.Info("evento SQS despachado", "donation_id", d.ID)
	}
}

// ── Utilitários ───────────────────────────────────────────────

func envOrDefault(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}
