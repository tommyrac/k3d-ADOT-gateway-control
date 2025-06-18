# main.tf

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }
}

provider "kubernetes" {
  alias = "control"
  config_path    = "~/.kube/config"
  config_context = "k3d-con-otest"
}

provider "kubernetes" {
  alias = "worker"
  config_path    = "~/.kube/config"
  config_context = "k3d-otest"
}

provider "helm" {
  alias = "control"
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "k3d-con-otest"
  }
}

provider "helm" {
  alias = "worker"
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "k3d-otest"
  }
}

resource "null_resource" "create_control_cluster" {
  provisioner "local-exec" {
    command = "k3d cluster create con-otest --agents 1 --config k3d-control-config.yaml"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "create_k3d_cluster" {
  provisioner "local-exec" {
    command = "k3d cluster create otest --agents 4 --config k3d-config.yaml"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "helm_release" "cert_manager_control" {
  provider = helm.control
  depends_on = [null_resource.create_control_cluster]

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.2"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "helm_release" "cert_manager" {
  provider = helm.worker
  depends_on = [null_resource.create_k3d_cluster]

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.2"

  set {
    name  = "installCRDs"
    value = "true"
  }

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "null_resource" "datadog_env_configmap" {
  depends_on = [null_resource.create_k3d_cluster, null_resource.create_control_cluster]
  provisioner "local-exec" {
    command = "./create-env-configmap.sh"
  }
}
resource "helm_release" "otel_operator" {
  depends_on = [null_resource.create_k3d_cluster, null_resource.create_control_cluster, null_resource.datadog_env_configmap, helm_release.cert_manager]

  provider         = helm.worker
  name             = "opentelemetry-operator"
  namespace        = "opentelemetry-operator-system"
  create_namespace = true

  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  # Using latest version as specific version had connectivity issues
  # version    = "0.90.3"

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "null_resource" "apply_workload_manifests" {
  depends_on = [null_resource.create_k3d_cluster]
  provisioner "local-exec" {
    command = <<EOT
      kubectl --context k3d-otest apply -f manifests/worker/apps/
      kubectl --context k3d-otest apply -f manifests/worker/exporters/
    EOT
  }
}

resource "helm_release" "otel_operator_control" {
  depends_on = [null_resource.create_k3d_cluster, null_resource.create_control_cluster, null_resource.datadog_env_configmap, helm_release.cert_manager, helm_release.cert_manager_control]
  provider         = helm.control
  name             = "opentelemetry-operator"
  namespace        = "opentelemetry-operator-system"
  create_namespace = true

  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  # version    = "0.90.3"
}

resource "null_resource" "apply_control_plane_manifests" {
  depends_on = [null_resource.datadog_env_configmap, null_resource.create_control_cluster, helm_release.otel_operator_control]
  provisioner "local-exec" {
    command = <<EOT
      kubectl --context k3d-con-otest apply -f manifests/control_plane/otel-gateway.yaml
    EOT
  }
}


resource "null_resource" "wait_for_crds" {
  depends_on = [helm_release.otel_operator]

  provisioner "local-exec" {
    command = "sleep 5" # Wait for CRDs to be installed
  }
}

# resource "null_resource" "prometheus_config" {
#   depends_on = [null_resource.create_k3d_cluster]
#
#   provisioner "local-exec" {
#     command = <<EOT
#       kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
#       kubectl apply -f manifests/prometheus-config.yaml
#     EOT
#   }
# }

resource "null_resource" "apply_worker_collector" {
  depends_on = [null_resource.wait_for_crds, null_resource.datadog_env_configmap, helm_release.otel_operator]
  provisioner "local-exec" {
    command = "kubectl --context k3d-otest apply -f manifests/worker/otel-collector.yaml"
  }
}
# resource "helm_release" "prometheus" {
#   depends_on       = [null_resource.create_k3d_cluster, null_resource.prometheus_config]
#   name             = "prometheus"
#   namespace        = "monitoring"
#
#   repository = "https://prometheus-community.github.io/helm-charts"
#   chart      = "prometheus"
#   version    = "27.20.0"
#
#   set {
#     name  = "server.persistentVolume.enabled"
#     value = "false"
#   }
#
#   set {
#     name  = "alertmanager.enabled"
#     value = "false"
#   }
#   
#   values = [
#     <<-EOT
#     server:
#       configPath: /etc/prometheus/prometheus.yml
#       extraConfigmapMounts:
#         - name: prometheus-config
#           mountPath: /etc/prometheus
#           configMap: prometheus-config
#           readOnly: true
#     EOT
#   ]
# }
#


resource "null_resource" "delete_k3d_cluster" {
  depends_on = [helm_release.otel_operator, helm_release.cert_manager]
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete otest"
  }
}