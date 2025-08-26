#!/bin/bash
IMAGE=$1
CLUSTER_ENDPOINT=$2
TOKEN=$3

set -e

# Install kubectl if not exists
if ! command -v kubectl &> /dev/null
then
  echo "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/
fi

# Create temporary kubeconfig
KUBECONFIG_FILE=$(mktemp)
export KUBECONFIG=$KUBECONFIG_FILE

kubectl config set-cluster custom-cluster --server=$CLUSTER_ENDPOINT --insecure-skip-tls-verify=true
kubectl config set-credentials custom-user --token=$TOKEN
kubectl config set-context custom-context --cluster=custom-cluster --user=custom-user
kubectl config use-context custom-context

# Verify cluster connectivity
echo "Testing cluster connectivity..."
kubectl get ns || { echo "Cluster authentication failed!"; exit 1; }

# Deploy workload
echo "Applying deployment with image: $IMAGE"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: custom-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: custom-app
  template:
    metadata:
      labels:
        app: custom-app
    spec:
      containers:
      - name: custom-container
        image: $IMAGE
        ports:
        - containerPort: 80
EOF

echo "Deployment successful on cluster: $CLUSTER_ENDPOINT with image: $IMAGE"
