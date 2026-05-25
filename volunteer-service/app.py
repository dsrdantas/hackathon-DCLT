"""
volunteer-service — Flask + DynamoDB
Instrumentado com OpenTelemetry (traces, métricas, logs estruturados JSON).
"""
import os
import sys
import uuid
import time
import logging
import boto3
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
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor


# ── Logging estruturado JSON ──────────────────────────────────
def setup_logging() -> logging.Logger:
    """Configura handler JSON com injeção automática de trace/span ID."""
    root = logging.getLogger()
    root.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
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

    # Auto-instrumentação (Flask + boto3/DynamoDB + logging)
    LoggingInstrumentor().instrument(set_logging_format=True)
    FlaskInstrumentor().instrument()
    BotocoreInstrumentor().instrument()


# ── Inicialização ─────────────────────────────────────────────
load_dotenv()
log = setup_logging()
setup_telemetry("volunteer-service")

tracer = trace.get_tracer("volunteer-service")
meter  = metrics.get_meter("volunteer-service")

# Métricas de negócio
volunteer_registered_counter = meter.create_counter(
    name="volunteer_registered_total",
    description="Voluntários registrados com sucesso",
    unit="1",
)
volunteer_error_counter = meter.create_counter(
    name="volunteer_errors_total",
    description="Erros ao registrar/buscar voluntários",
    unit="1",
)

app = Flask(__name__)

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
# FIX: variável de ambiente correta conforme definida no deployment.yaml
DYNAMODB_TABLE = os.getenv("DYNAMODB_TABLE")

if not DYNAMODB_TABLE:
    log.critical("DYNAMODB_TABLE não definida — encerrando.")
    sys.exit(1)

try:
    dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
    table = dynamodb.Table(DYNAMODB_TABLE)
    log.info(
        "Conectado ao DynamoDB",
        extra={"table": DYNAMODB_TABLE, "region": AWS_REGION},
    )
except Exception as exc:
    log.critical("Falha ao conectar no DynamoDB", extra={"error": str(exc)})
    sys.exit(1)


# ── Rotas ─────────────────────────────────────────────────────
@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"}), 200


@app.route("/volunteers", methods=["POST"])
def register_volunteer():
    with tracer.start_as_current_span("volunteer.register") as span:
        data = request.get_json()
        if not data or not all(k in data for k in ("name", "email", "ngo_id")):
            span.set_attribute("error", True)
            span.set_attribute("error.type", "validation")
            volunteer_error_counter.add(1, {"reason": "validation"})
            return jsonify({"error": "Campos obrigatórios ausentes"}), 400

        volunteer_id = str(uuid.uuid4())
        item = {
            "volunteer_id": volunteer_id,
            "name": data["name"],
            "email": data["email"],
            "ngo_id": int(data["ngo_id"]),
            "registered_at": str(int(time.time())),
        }

        span.set_attribute("volunteer.id", volunteer_id)
        span.set_attribute("volunteer.ngo_id", int(data["ngo_id"]))

        try:
            table.put_item(Item=item)
            volunteer_registered_counter.add(1, {"ngo_id": str(data["ngo_id"])})
            log.info(
                "Voluntário registrado",
                extra={"volunteer_id": volunteer_id, "ngo_id": data["ngo_id"]},
            )
            return jsonify(item), 201

        except Exception as exc:
            volunteer_error_counter.add(1, {"reason": "dynamodb"})
            log.error("Erro ao salvar voluntário no DynamoDB", extra={"error": str(exc)})
            span.record_exception(exc)
            span.set_attribute("error", True)
            return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route("/volunteers/<int:ngo_id>", methods=["GET"])
def get_volunteers_by_ngo(ngo_id: int):
    with tracer.start_as_current_span("volunteer.list_by_ngo") as span:
        span.set_attribute("ngo.id", ngo_id)
        try:
            # Nota: Scan simplificado para desenvolvimento.
            # Em produção com alto volume, use um GSI em ngo_id.
            response = table.scan(
                FilterExpression=boto3.dynamodb.conditions.Attr("ngo_id").eq(ngo_id)
            )
            items = response.get("Items", [])
            span.set_attribute("volunteer.count", len(items))
            log.info(
                "Voluntários buscados",
                extra={"ngo_id": ngo_id, "count": len(items)},
            )
            return jsonify(items), 200

        except Exception as exc:
            volunteer_error_counter.add(1, {"reason": "dynamodb"})
            log.error("Erro ao buscar dados no DynamoDB", extra={"error": str(exc)})
            span.record_exception(exc)
            span.set_attribute("error", True)
            return jsonify({"error": "Erro interno"}), 500


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8083))
    app.run(host="0.0.0.0", port=port)
