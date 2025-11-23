#!/usr/bin/env bash
# SkyCanary/bootstrap.sh
# Bootstraps SkyCanary stack with system-wide Jenkins (systemd), Docker, Kind, kubectl, helm, and Istio
# Works on Ubuntu 22.04+ (Cloud VMs or WSL2 with systemd enabled)

set -euo pipefail

# === Argument check ===
if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <DockerHub-Username>"
    exit 1
fi


USER_NAME=${USER}
INSTALL_DIR="/usr/local/bin"

echo "🚀 SkyCanary Bootstrap starting as user: $USER_NAME"
echo

# === System prerequisites ===
echo "📦 Updating system packages..."
sudo apt-get update -qq
sudo apt-get install -y ca-certificates curl gnupg make lsb-release apt-transport-https \
  software-properties-common openjdk-17-jdk unzip

# === Docker ===
if ! command -v docker >/dev/null 2>&1; then
  echo "🐋 Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER_NAME"
  echo "✅ Docker installed. Log out and back in to activate docker group."
else
  echo "✅ Docker already installed: $(docker --version)"
fi

# === kubectl ===
if ! command -v kubectl >/dev/null 2>&1; then
  echo "📦 Installing kubectl..."
  LATEST_KUBECTL=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
  sudo curl -fsSLo "$INSTALL_DIR/kubectl" "https://storage.googleapis.com/kubernetes-release/release/${LATEST_KUBECTL}/bin/linux/amd64/kubectl"
  sudo chmod +x "$INSTALL_DIR/kubectl"
else
  echo "✅ kubectl already installed."
fi

# === kind ===
if ! command -v kind >/dev/null 2>&1; then
  echo "📦 Installing kind..."
  sudo curl -fsSLo "$INSTALL_DIR/kind" https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
  sudo chmod +x "$INSTALL_DIR/kind"
else
  echo "✅ kind already installed."
fi

# === sync project ===

sync_project() {
    local DIR="${HOME}/SkyCanary"
    local REGISTRY="$1"

    echo "[info] REGISTRY = ${REGISTRY}"

    # --- Validate registry argument ---
    if [[ -z "$REGISTRY" ]]; then
        echo "❌ REGISTRY not provided for sync_project"
        exit 1
    fi

    # --- Validate directory existence ---
    if [[ -d "${DIR}" ]]; then
        echo "[info] Updating files in ${DIR} with REGISTRY=${REGISTRY}"

        # Recursive find with proper parentheses & file filters
        find "${DIR}" -type f \( \
            -name "*.yaml" -o \
            -name "*.yml" -o \
            -name "Makefile" -o \
            -name "*.sh" -o \
            -name "Jenkinsfile" \
        \) -print0 | \
        xargs -0 sed -i "s|\${REGISTRY}|${REGISTRY}|g"

        echo "✅ sync_project completed successfully"
    else
        echo "[warn] Directory not found: ${DIR}; skipping file updates"
    fi
}

sync_project

# === helm ===
if ! command -v helm >/dev/null 2>&1; then
  echo "📦 Installing helm..."
  curl -fsSL https://get.helm.sh/helm-v3.16.3-linux-amd64.tar.gz | tar -xz
  sudo mv linux-amd64/helm "$INSTALL_DIR/helm"
  sudo chmod +x "$INSTALL_DIR/helm"
  rm -rf linux-amd64
else
  echo "✅ helm already installed."
fi

# === istioctl ===
if ! command -v istioctl >/dev/null 2>&1; then
  echo "📦 Installing istioctl..."
  ISTIO_VER="1.23.2"
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VER} TARGET_ARCH=x86_64 sh -
  sudo mv istio-${ISTIO_VER}/bin/istioctl "$INSTALL_DIR/istioctl"
  sudo chmod +x "$INSTALL_DIR/istioctl"
  rm -rf istio-${ISTIO_VER}
else
  echo "✅ istioctl already installed."
fi

# === Jenkins Installation (systemd only) ===
echo "⚙️  Installing Jenkins (Systemd service via APT repo)..."
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y jenkins

sudo usermod -aG docker jenkins
sudo systemctl enable --now jenkins

echo "✅ Jenkins installed and started as a systemd service."
echo "🔑 To unlock Jenkins, run:"
echo "   sudo cat /var/lib/jenkins/secrets/initialAdminPassword"

# === Kind + Istio Setup ===
echo "☸️  Setting up Kind cluster..."
sudo kind create cluster --name skycanary --config kubernetes/kind-config.yaml || true
kubectl cluster-info
kubectl create ns skycanary 2>/dev/null || true
kubectl label ns skycanary istio-injection=enabled --overwrite

# Copy kubeconfig to non-root user
echo "🔧 Setting up kubeconfig for ${USER_NAME}..."
sudo mkdir -p /home/"${USER_NAME}"/.kube
sudo cp /root/.kube/config /home/"${USER_NAME}"/.kube/config
sudo chown -R "${USER_NAME}":"${USER_NAME}" /home/"${USER_NAME}"/.kube

echo "🚀 Installing Istio (default profile)..."
istioctl install --set profile=default -y
kubectl -n istio-system rollout status deploy/istio-ingressgateway --timeout=180s
kubectl -n istio-system patch svc istio-ingressgateway -p '{"spec": {"type": "NodePort"}}' || true
echo "✅ Istio ingressgateway is now NodePort-enabled."
echo
echo "✅ SkyCanary setup complete!"
echo "🌐 Jenkins (systemd): http://<EC2-PUBLIC-IP>:8080"
echo "🧰 Kind cluster: skycanary"
echo "💡 Next steps:"
echo "   sudo systemctl restart jenkins"
echo "   make prereqs"
echo "   make build"
echo "   make deploy"
