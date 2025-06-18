#!/bin/bash

# Create the namespace if it doesn't exist
# Create namespace and ConfigMap in both clusters
for CONTEXT in k3d-otest k3d-con-otest; do
  kubectl --context $CONTEXT create namespace opentelemetry-operator-system --dry-run=client -o yaml | kubectl apply --context $CONTEXT -f -
  kubectl --context $CONTEXT create configmap datadog-env --from-env-file=.env -n opentelemetry-operator-system --dry-run=client -o yaml | kubectl apply --context $CONTEXT -f -
done

echo "ConfigMap 'datadog-env' created in namespace 'opentelemetry-operator-system'"
