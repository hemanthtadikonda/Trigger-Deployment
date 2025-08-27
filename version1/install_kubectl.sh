#!/usr/bin/env bash
set -euo pipefail

# Simple installer for kubectl (Linux x86_64)
# If you are on macOS or other arch, edit this script accordingly.

ARCH="amd64"
OS="linux"

echo "Installing kubectl..."

STABLE=$(curl -s https://dl.k8s.io/release/stable.txt)
if [ -z "$STABLE" ]; then
  echo "Failed to fetch stable kubectl version"
  exit 1
fi

URL="https://dl.k8s.io/release/${STABLE}/bin/${OS}/${ARCH}/kubectl"
TMP="/tmp/kubectl"
curl -fsSL "$URL" -o "$TMP"
chmod +x "$TMP"

# try to move to /usr/local/bin if writable, else leave in /tmp
if [ -w /usr/local/bin ]; then
  sudo mv "$TMP" /usr/local/bin/kubectl
  echo "kubectl installed to /usr/local/bin/kubectl"
else
  mv "$TMP" /tmp/kubectl
  echo "kubectl installed to /tmp/kubectl (not moved to /usr/local/bin — not writable)"
  echo "Add /tmp to PATH or move the binary to a location in PATH."
fi

kubectl version --client --short || true
