# ════════════════════════════════════════════════════════════════
# modules/gitops/main.tf
#
# Responsabilidades:
#   1. ECR — um repositório por microserviço (com lifecycle policy)
#   2. ArgoCD — instalado via Helm no cluster EKS
#   3. Traefik — Ingress Controller via Helm
#   4. metrics-server — necessário para HPA funcionar
#   5. Bootstrap — aplica gitops/argocd-apps.yaml no cluster
#
# Pré-requisito: o cluster EKS já deve existir antes deste módulo.
# Use `terraform apply -target=module.eks` na primeira execução.
# ════════════════════════════════════════════════════════════════

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── ECR — um repositório por serviço ──────────────────────────
resource "aws_ecr_repository" "services" {
  for_each             = toset(var.services)
  name                 = "${local.name_prefix}-${each.key}"
  image_tag_mutability = "IMMUTABLE" # Tags versionadas (run-sha); :latest removido dos workflows

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-${each.key}"
    Service = each.key
  })
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter últimas ${var.ecr_image_retention_count} imagens"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_image_retention_count
      }
      action = { type = "expire" }
    }]
  })
}

# ── Namespace: argocd ─────────────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = var.project_name
    }
  }
}

# ── ArgoCD via Helm ───────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [<<-YAML
    server:
      service:
        type: ClusterIP
      extraArgs:
        - --insecure
        - --rootpath=/argocd
    configs:
      params:
        server.insecure: "true"
        server.rootpath: "/argocd"
    global:
      networkPolicy:
        create: false
    notifications:
      enabled: false
    applicationSet:
      enabled: true
  YAML
  ]
}

# ── Namespace: traefik ────────────────────────────────────────
resource "kubernetes_namespace" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = var.project_name
    }
  }
}

# ── Traefik Ingress Controller via Helm ───────────────────────
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = kubernetes_namespace.traefik.metadata[0].name
  repository       = "https://helm.traefik.io/traefik"
  chart            = "traefik"
  version          = var.traefik_chart_version
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [<<-YAML
    service:
      type: LoadBalancer
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
        service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    ingressClass:
      enabled: true
      isDefaultClass: true
    providers:
      kubernetesCRD:
        enabled: true
        allowCrossNamespace: true   # permite IngressRoute referenciar servicos em outros namespaces
      kubernetesIngress:
        enabled: true
    # Ping endpoint — usado pelo NLB health-check em /ping
    ping:
      entryPoint: "web"
    # API interna desabilitada (sem dashboard exposto)
    api:
      dashboard: false
      insecure: false
    logs:
      access:
        enabled: true
    metrics:
      prometheus:
        enabled: true
  YAML
  ]

  depends_on = [helm_release.argocd]
}

# ── External Secrets Operator via Helm ───────────────────────
# Lê os secrets do AWS Secrets Manager e os sincroniza como
# Kubernetes Secrets via ExternalSecret CRDs.
resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = var.project_name
    }
  }
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = kubernetes_namespace.external_secrets.metadata[0].name
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.eso_chart_version
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [<<-YAML
    installCRDs: true
    webhook:
      create: true
    certController:
      create: true
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi
  YAML
  ]

  depends_on = [helm_release.argocd]
}

# ── Stakater Reloader ─────────────────────────────────────────
# Monitora K8s Secrets e ConfigMaps. Quando o ESO atualiza um
# Secret (ex: após renovação das credenciais AWS Academy), o
# Reloader dispara um rolling restart nos Deployments anotados.
resource "helm_release" "reloader" {
  name             = "reloader"
  namespace        = "kube-system"
  repository       = "https://stakater.github.io/stakater-charts"
  chart            = "reloader"
  version          = var.reloader_chart_version
  create_namespace = false
  wait             = true
  timeout          = 180

  values = [<<-YAML
    reloader:
      watchGlobally: false   # respeita apenas Deployments com a anotação
      ignoreSecrets: false
      ignoreConfigMaps: false
      logFormat: json
    resources:
      requests:
        cpu: 20m
        memory: 32Mi
      limits:
        cpu: 100m
        memory: 128Mi
  YAML
  ]
}

# ── metrics-server (necessário para HPA) ─────────────────────
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = "kube-system"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_chart_version
  create_namespace = false
  wait             = true
  timeout          = 180

  values = [<<-YAML
    args:
      - --kubelet-insecure-tls
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 128Mi
  YAML
  ]
}

# ── kube-prometheus-stack (Prometheus + Grafana + AlertManager) ────────
# Instalado antes do ArgoCD bootstrap para que os ServiceMonitors dos
# microserviços já tenham o CRD disponível no primeiro sync.
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = var.project_name
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_chart_version
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [<<-YAML
    prometheusOperator:
      resources:
        requests: { cpu: 100m, memory: 128Mi }
        limits:   { cpu: 200m, memory: 256Mi }
    prometheus:
      prometheusSpec:
        # Serve a UI em /prometheus (--web.route-prefix)
        routePrefix: /prometheus
        retention: 7d
        resources:
          requests: { cpu: 200m, memory: 512Mi }
          limits:   { cpu: 500m, memory: 1Gi }
        # Descobre todos os ServiceMonitors do cluster (nao so os do Helm)
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false
        serviceMonitorNamespaceSelector:
          matchLabels: {}   # todos os namespaces
    grafana:
      enabled: true
      adminPassword: "${var.project_name}-grafana"
      # Serve a UI em /grafana — Traefik passa o path inteiro, Grafana trata
      grafana.ini:
        server:
          root_url: "%(protocol)s://%(domain)s/grafana/"
          serve_from_sub_path: true
      resources:
        requests: { cpu: 100m, memory: 128Mi }
        limits:   { cpu: 200m, memory: 256Mi }
      sidecar:
        dashboards:
          enabled: true
          searchNamespace: ALL   # importa ConfigMaps com label grafana_dashboard=1
      service:
        type: ClusterIP
    alertmanager:
      enabled: true
      alertmanagerSpec:
        resources:
          requests: { cpu: 50m, memory: 64Mi }
          limits:   { cpu: 100m, memory: 128Mi }
  YAML
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# ── OpenTelemetry Collector ────────────────────────────────────
# Centraliza telemetria: OTLP → Prometheus (scrape) + New Relic (OTLP HTTP)
resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = var.project_name
    }
  }
}

resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  namespace        = kubernetes_namespace.observability.metadata[0].name
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = var.otel_collector_chart_version
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [<<-YAML
    mode: deployment
    replicaCount: 1
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits:   { cpu: 300m, memory: 256Mi }

    # Porta OTLP exposta como ClusterIP (os serviços enviam telemetria para cá)
    service:
      type: ClusterIP

    ports:
      otlp:
        enabled: true
        containerPort: 4317
        servicePort: 4317
        protocol: TCP
      otlp-http:
        enabled: true
        containerPort: 4318
        servicePort: 4318
        protocol: TCP
      prometheus:
        enabled: true
        containerPort: 8889
        servicePort: 8889
        protocol: TCP

    config:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"
            http:
              endpoint: "0.0.0.0:4318"

      processors:
        batch:
          timeout: 5s
          send_batch_size: 1024
        memory_limiter:
          check_interval: 5s
          limit_mib: 200
          spike_limit_mib: 50
        resource:
          attributes:
            - action: upsert
              key: deployment.environment
              value: "${var.environment}"
            - action: upsert
              key: project
              value: "${var.project_name}"

      exporters:
        # Expõe métricas para o Prometheus scrape (Grafana lê via Prometheus)
        prometheus:
          endpoint: "0.0.0.0:8889"
          namespace: solidarytech
          resource_to_telemetry_conversion:
            enabled: true
        # Envia traces + métricas + logs para o New Relic via OTLP HTTP
        otlphttp/newrelic:
          endpoint: "${var.new_relic_endpoint}:4318"
          headers:
            api-key: "$${env:NEW_RELIC_LICENSE_KEY}"
          tls:
            insecure: false
        debug:
          verbosity: basic

      service:
        pipelines:
          traces:
            receivers:  [otlp]
            processors: [memory_limiter, batch, resource]
            exporters:  [otlphttp/newrelic, debug]
          metrics:
            receivers:  [otlp]
            processors: [memory_limiter, batch, resource]
            exporters:  [prometheus, otlphttp/newrelic]
          logs:
            receivers:  [otlp]
            processors: [memory_limiter, batch, resource]
            exporters:  [otlphttp/newrelic, debug]

    # NEW_RELIC_LICENSE_KEY vem do K8s Secret "new-relic-credentials"
    # criado/atualizado pelo workflow update-aws-credentials.yml
    extraEnvs:
      - name: NEW_RELIC_LICENSE_KEY
        valueFrom:
          secretKeyRef:
            name: new-relic-credentials
            key: license-key
            optional: true   # não bloqueia startup se ainda não existir
  YAML
  ]

  depends_on = [kubernetes_namespace.observability, helm_release.kube_prometheus_stack]
}

# ── Bootstrap ArgoCD: aplica o AppProject + Applications ──────
# Aguarda o ArgoCD estar pronto e aplica gitops/argocd-apps.yaml
resource "null_resource" "argocd_bootstrap" {
  triggers = {
    argocd_version = var.argocd_chart_version
    gitops_repo    = var.gitops_repo_url
    gitops_branch  = var.gitops_repo_branch
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      echo "==> Atualizando kubeconfig para ${var.cluster_name}"
      aws eks update-kubeconfig \
        --name ${var.cluster_name} \
        --region ${var.aws_region}

      echo "==> Aguardando argocd-server ficar disponível..."
      kubectl rollout status deployment/argocd-server \
        -n argocd --timeout=300s

      echo "==> Aplicando AppProject + Applications do ArgoCD"
      kubectl apply -f ${path.root}/../gitops/argocd-apps.yaml

      echo "==> Bootstrap concluído"
    EOT
  }

  depends_on = [
    helm_release.argocd,
    helm_release.traefik,
  ]
}
