"""
ngo-service — Flask + PostgreSQL
Instrumentado com OpenTelemetry (traces, métricas, logs estruturados JSON).
"""
import os
import sys
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from pythonjsonlogger import jsonlogger

# ── OpenTelemetry ─────────────────────────────────────────────
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor


# ── Logging estruturado JSON ──────────────────────────────────
def setup_logging() -> logging.Logger:
    """Configura handler JSON com injeção automática de trace/span ID."""
    root = logging.getLogger()
    root.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    # %(otelTraceID)s e %(otelSpanID)s são injetados pelo LoggingInstrumentor
    formatter = jsonlogger.JsonFormatter(
        fmt="%(asctime)s %(name)s %(levelname)s %(message)s "
            "%(otelTraceID)s %(otelSpanID)s %(otelTraceSampled)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
        rename_fields={"asctime": "timestamp", "levelname": "level"},
    )
    handler.setFormatter(formatter)
    root.addHandler(handler)
    root.setLevel(logging.INFO)
    return logging.getLogger(__name__)


# ── OpenTelemetry bootstrap ───────────────────────────────────
def setup_telemetry(service_name: str) -> None:
    """Inicializa TracerProvider, MeterProvider e auto-instrumentação."""
    resource = Resource.create({
        SERVICE_NAME: service_name,
        SERVICE_VERSION: os.getenv("APP_VERSION", "1.0.0"),
        "deployment.environment": os.getenv("FLASK_ENV", "production"),
    })

    otlp_endpoint = os.getenv(
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "http://otel-collector.observability:4318",
    )

    # Traces
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(
        BatchSpanProcessor(
            OTLPSpanExporter(endpoint=f"{otlp_endpoint}/v1/traces")
        )
    )
    trace.set_tracer_provider(tracer_provider)

    # Métricas
    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=f"{otlp_endpoint}/v1/metrics"),
        export_interval_millis=30_000,
    )
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)

    # Auto-instrumentação
    LoggingInstrumentor().instrument(set_logging_format=True)
    FlaskInstrumentor().instrument()
    Psycopg2Instrumentor().instrument(enable_commenter=True)


# ── Inicialização ─────────────────────────────────────────────
load_dotenv()
log = setup_logging()
setup_telemetry("ngo-service")

tracer = trace.get_tracer("ngo-service")
meter  = metrics.get_meter("ngo-service")

# Métricas de negócio
ngo_created_counter = meter.create_counter(
    name="ngo_created_total",
    description="Número de ONGs criadas com sucesso",
    unit="1",
)
ngo_error_counter = meter.create_counter(
    name="ngo_errors_total",
    description="Erros ao criar/buscar ONGs",
    unit="1",
)

app = Flask(__name__)

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    log.critical("DATABASE_URL não definida — encerrando.")
    sys.exit(1)

try:
    pool = SimpleConnectionPool(1, 10, dsn=DATABASE_URL)
    log.info("Pool de conexões PostgreSQL inicializado", extra={"service": "ngo-service"})
except Exception as exc:
    log.critical("Falha ao criar pool PostgreSQL", extra={"error": str(exc)})
    sys.exit(1)


# ── Rotas ─────────────────────────────────────────────────────
@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "ngo-service"}), 200


@app.route("/ngos", methods=["POST"])
def create_ngo():
    with tracer.start_as_current_span("ngo.create") as span:
        data = request.get_json()
        if not data or not all(k in data for k in ("name", "email", "cause", "city")):
            span.set_attribute("error", True)
            span.set_attribute("error.type", "validation")
            ngo_error_counter.add(1, {"reason": "validation"})
            return jsonify({"error": "Campos obrigatórios ausentes"}), 400

        span.set_attribute("ngo.name", data.get("name", ""))
        span.set_attribute("ngo.city", data.get("city", ""))

        conn = pool.getconn()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "INSERT INTO ngos (name, email, cause, city) "
                    "VALUES (%s, %s, %s, %s) RETURNING *",
                    (data["name"], data["email"], data["cause"], data["city"]),
                )
                new_ngo = cur.fetchone()
                conn.commit()

            ngo_created_counter.add(1, {"city": data["city"]})
            log.info("ONG criada", extra={"ngo_id": new_ngo["id"], "city": data["city"]})
            span.set_attribute("ngo.id", new_ngo["id"])
            return jsonify(new_ngo), 201

        except psycopg2.IntegrityError:
            conn.rollback()
            ngo_error_counter.add(1, {"reason": "duplicate_email"})
            span.set_attribute("error", True)
            span.set_attribute("error.type", "duplicate_email")
            return jsonify({"error": "E-mail já cadastrado"}), 409

        except Exception as exc:
            conn.rollback()
            ngo_error_counter.add(1, {"reason": "internal"})
            log.error("Erro ao criar ONG", extra={"error": str(exc)})
            span.record_exception(exc)
            span.set_attribute("error", True)
            return jsonify({"error": "Erro interno"}), 500

        finally:
            pool.putconn(conn)


@app.route("/ngos", methods=["GET"])
def get_ngos():
    with tracer.start_as_current_span("ngo.list") as span:
        conn = pool.getconn()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT * FROM ngos ORDER BY id DESC")
                result = cur.fetchall()

            span.set_attribute("ngo.count", len(result))
            log.info("ONGs listadas", extra={"count": len(result)})
            return jsonify(result), 200

        except Exception as exc:
            ngo_error_counter.add(1, {"reason": "internal"})
            log.error("Erro ao buscar ONGs", extra={"error": str(exc)})
            span.record_exception(exc)
            span.set_attribute("error", True)
            return jsonify({"error": "Erro interno"}), 500

        finally:
            pool.putconn(conn)


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8081))
    app.run(host="0.0.0.0", port=port)
