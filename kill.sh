#!/bin/bash
k3d cluster delete otest
k3d cluster delete con-otest
# Remove all k3d-related containers (including tools nodes)
docker ps -a --filter 'name=k3d-' --format '{{.Names}}' | grep -v '^k3d-local-registry$' | xargs -r docker rm -f
# Clean up any lingering k3d Docker networks and volumes
docker network rm k3d-con-otest 2>/dev/null || true
docker network prune -f
docker volume prune -f
terraform state rm \
  helm_release.otel_operator \
  helm_release.cert_manager \
  null_resource.create_k3d_cluster \
  null_resource.delete_k3d_cluster \
  null_resource.otel_collector \
  null_resource.apply_manifests \
  helm_release.prometheus \
  null_resource.prometheus_config \
  null_resource.wait_for_crds \
  helm_release.cert_manager_control \
  helm_release.otel_operator_control \
  null_resource.apply_control_plane_manifests \
  null_resource.apply_worker_collector \
  null_resource.apply_workload_manifests \
  null_resource.create_control_cluster \
  null_resource.datadog_env_configmap
terraform destroy -auto-approve