#!/bin/bash
if ! command -v kubectl &> /dev/null
then
  echo "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
else
  echo "kubectl already installed"
fi
