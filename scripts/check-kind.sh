#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER:-skycanary}"
NS="${NAMESPACE:-skycanary}"

exists=$(kind get clusters | grep -E "^${CLUSTER_NAME}$" || true)
if [[ -z "$exists" ]]; then
  echo "Kind cluster ${CLUSTER_NAME} not found. Creating..."
  make kind-create
fi

echo "Ensuring namespace '$NS' exists and is labeled for Istio injection..."
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"
kubectl label ns "$NS" istio-injection=enabled --overwrite

echo "Checking Istio ingressgateway..."
if ! kubectl -n istio-system get deploy istio-ingressgateway >/dev/null 2>&1; then
  echo "Istio not found. Installing demo profile..."
  istioctl install --set profile=demo -y
fi

kubectl -n istio-system rollout status deploy/istio-ingressgateway --timeout=180s
kubectl -n "$NS" get all
echo "Cluster verification complete."
