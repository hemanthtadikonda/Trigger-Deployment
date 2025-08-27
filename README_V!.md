# k8s-portal (simple template)

Tiny, simple portal to create/apply Kubernetes resources via `kubectl`.

## What it does
- Lets you supply **API server + Bearer token once** (top of UI).
- Create Deployment, Service, apply Custom YAML, or Delete resources.
- Ensures `kubectl` is available; if missing, runs `install_kubectl.sh`.
- Builds a temporary kubeconfig (token auth) per request and runs `kubectl` with it.
- Shows the YAML you applied and `kubectl` stdout/stderr for easy debugging.

## Files
See project structure in repository root.

## How to run
1. Make script executable:
   ```bash
   chmod +x install_kubectl.sh
