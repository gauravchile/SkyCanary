#!/usr/bin/env bash
set -euo pipefail

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "✗ Missing: $1"
    return 1
  else
    echo "✓ $1: $(command -v "$1")"
  fi
}

echo "Checking required tools..."
need docker
need kind
need kubectl
need helm
need istioctl

# kustomize may be builtin via kubectl kustomize; accept either
if command -v kustomize >/dev/null 2>&1; then
  echo "✓ kustomize: $(command -v kustomize)"
else
  if kubectl kustomize --help >/dev/null 2>&1; then
    echo "✓ kubectl kustomize (builtin)"
  else
    echo "✗ Missing: kustomize (or kubectl with kustomize)"
    exit 1
  fi
fi

echo "All prereqs present."
