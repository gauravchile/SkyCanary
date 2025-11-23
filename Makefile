SHELL := /usr/bin/env bash

# ==== CONFIG ====
DOCKER_USER ?= ${REGISTRY}
APP_NAME ?= skycanary
IMG_TAG ?= local
IMG ?= $(DOCKER_USER)/$(APP_NAME):$(IMG_TAG)

KIND_CLUSTER ?= skycanary
NAMESPACE ?= skycanary
COMPOSE_FILE ?= docker-compose.yml

# ==== KIND SETUP ====
.PHONY: kind-create
kind-create:
	@echo "☸️ Creating Kind cluster $(KIND_CLUSTER)..."
	kind create cluster --name $(KIND_CLUSTER) --config kubernetes/kind-config.yaml || true
	kubectl cluster-info
	kubectl get nodes
	kubectl create ns $(NAMESPACE) 2>/dev/null || true
	kubectl label ns $(NAMESPACE) istio-injection=enabled --overwrite
	@if ! kubectl -n istio-system get deploy istio-ingressgateway >/dev/null 2>&1; then \
		echo "📦 Installing Istio default profile..."; \
		istioctl install --set profile=default -y; \
	fi
	kubectl -n istio-system rollout status deploy/istio-ingressgateway --timeout=180s
	@echo "✅ Kind + Istio ready!"

# ==== KIND DELETE ====
.PHONY: kind-delete
kind-delete:
	@echo "🧹 Deleting Kind cluster $(KIND_CLUSTER)..."
	kind delete cluster --name $(KIND_CLUSTER)

# ==== KIND LOAD ====
.PHONY: kind-load
kind-load:
	@echo "📦 Loading images into Kind cluster..."
	kind load docker-image $(DOCKER_USER)/$(APP_NAME):stable --name $(KIND_CLUSTER)
	kind load docker-image $(DOCKER_USER)/$(APP_NAME):canary --name $(KIND_CLUSTER)

# ==== DEPLOYMENT ====
.PHONY: deploy
deploy:
	@echo "🚀 Deploying SkyCanary to Kubernetes..."
	kubectl get ns $(NAMESPACE) >/dev/null 2>&1 || kubectl create ns $(NAMESPACE)
	kubectl label ns $(NAMESPACE) istio-injection=enabled --overwrite
	kubectl apply -f kubernetes/base/
	@echo "⏳ Waiting for deployments..."
	kubectl -n $(NAMESPACE) rollout status deploy/skycanary-stable --timeout=180s
	kubectl -n $(NAMESPACE) rollout status deploy/skycanary-canary --timeout=180s
	@$(MAKE) access

# ==== CLEANUP ====
.PHONY: destroy
destroy:
	@echo "🧹 Destroying SkyCanary namespace and all resources..."
	-kubectl delete namespace $(NAMESPACE) --ignore-not-found
	@echo "✅ Namespace '$(NAMESPACE)' deleted."

# ==== ACCESS (background port-forward + clickable URL) ====
.PHONY: access
access:
	@echo "🌐 Setting up background port-forward on port 8090..."
	@PID=$$(lsof -t -i:8090 2>/dev/null); \
	if [ -n "$$PID" ]; then \
		echo "⚠️  Port 8090 already in use. Stopping previous process..."; \
		kill $$PID || true; \
	fi
	nohup kubectl port-forward --address 0.0.0.0 -n istio-system svc/istio-ingressgateway 8090:80 >/dev/null 2>&1 &
	sleep 3
	echo "✅ SkyCanary running in background!"; \
	echo "🌍 Access it at:"; \
	echo "   → http://localhost:8090   (from Windows browser)"; \
	echo "💡 To stop it: make stop"

# ==== STOP PORT-FORWARD ====
.PHONY: stop
stop:
	@echo "🛑 Stopping background port-forward on port 8090..."
	-kill $$(lsof -t -i:8090 2>/dev/null) >/dev/null 2>&1 || true
	@echo "✅ Port-forward stopped."

# ==== ROLLOUT (manual percentage control) ====
.PHONY: rollout
rollout:
	@if [ -z "$(PERCENT)" ]; then \
	  echo "❌ Please specify the canary percentage."; \
	  echo "👉 Example: make rollout PERCENT=25"; \
	  exit 1; \
	fi
	@echo "⚙️ Setting canary rollout to $(PERCENT)%..."
	kubectl -n $(NAMESPACE) patch virtualservice skycanary-vs --type='json' \
	  -p="[{\"op\":\"replace\",\"path\":\"/spec/http/0/route/0/weight\",\"value\":$$((100-$(PERCENT)))}]"
	kubectl -n $(NAMESPACE) patch virtualservice skycanary-vs --type='json' \
	  -p="[{\"op\":\"replace\",\"path\":\"/spec/http/0/route/1/weight\",\"value\":$(PERCENT)}]"
	kubectl -n $(NAMESPACE) get virtualservice skycanary-vs -o=jsonpath='{.spec.http[0].route[*].weight}'; echo
	@echo "✅ Canary traffic shifted → $(PERCENT)% canary, $$((100-$(PERCENT)))% stable"

# ==== PROMOTE (100% Canary) ====
.PHONY: promote
promote:
	@echo "🚀 Promoting Canary to 100%..."
	kubectl -n $(NAMESPACE) patch virtualservice skycanary-vs --type='json' \
	  -p='[{"op":"replace","path":"/spec/http/0/route/0/weight","value":0}]'
	kubectl -n $(NAMESPACE) patch virtualservice skycanary-vs --type='json' \
	  -p='[{"op":"replace","path":"/spec/http/0/route/1/weight","value":100}]'
	@echo "✅ Canary promoted → 100% traffic to canary!"

# ==== ROLLBACK (100% Stable) ====
.PHONY: rollback
rollback:
	@echo "↩️ Rolling back to Stable (0% Canary)..."
	kubectl -n $(NAMESPACE) patch virtualservice skycanary-vs --type='json' \
	  -p='[{"op":"replace","path":"/spec/http/0/route/0/weight","value":100}]'
	kubectl -n $(NAMESPACE) patch virtualservice skycanary-vs --type='json' \
	  -p='[{"op":"replace","path":"/spec/http/0/route/1/weight","value":0}]'
	@echo "✅ Rollback complete → 100% traffic to stable!"
