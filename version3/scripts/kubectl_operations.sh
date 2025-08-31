#!/bin/bash

# Kubernetes Operations Script
# This script provides utility functions for Kubernetes operations

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        return 1
    fi
    
    log_info "kubectl is available"
    kubectl version --client --short 2>/dev/null || true
    return 0
}

# Function to test cluster connectivity
test_cluster_connection() {
    local cluster_name="${1:-}"
    
    if [[ -z "$cluster_name" ]]; then
        log_error "Cluster name is required"
        return 1
    fi
    
    log_info "Testing connection to cluster: $cluster_name"
    
    if kubectl cluster-info --context="$cluster_name" &>/dev/null; then
        log_success "Successfully connected to cluster: $cluster_name"
        return 0
    else
        log_error "Failed to connect to cluster: $cluster_name"
        return 1
    fi
}

# Function to setup kubectl context
setup_kubectl_context() {
    local endpoint="${1:-}"
    local token="${2:-}"
    local cluster_name="${3:-}"
    
    if [[ -z "$endpoint" || -z "$token" || -z "$cluster_name" ]]; then
        log_error "All parameters (endpoint, token, cluster_name) are required"
        return 1
    fi
    
    log_info "Setting up kubectl context for cluster: $cluster_name"
    
    # Set cluster
    if kubectl config set-cluster "$cluster_name" \
        --server="$endpoint" \
        --insecure-skip-tls-verify=true; then
        log_success "Cluster configuration set"
    else
        log_error "Failed to set cluster configuration"
        return 1
    fi
    
    # Set credentials
    if kubectl config set-credentials "${cluster_name}-user" \
        --token="$token"; then
        log_success "User credentials set"
    else
        log_error "Failed to set user credentials"
        return 1
    fi
    
    # Set context
    if kubectl config set-context "$cluster_name" \
        --cluster="$cluster_name" \
        --user="${cluster_name}-user"; then
        log_success "Context set"
    else
        log_error "Failed to set context"
        return 1
    fi
    
    # Use context
    if kubectl config use-context "$cluster_name"; then
        log_success "Context switched to: $cluster_name"
    else
        log_error "Failed to switch context"
        return 1
    fi
    
    return 0
}

# Function to create deployment
create_deployment() {
    local name="${1:-}"
    local image="${2:-}"
    local replicas="${3:-1}"
    local port="${4:-80}"
    local namespace="${5:-default}"
    
    if [[ -z "$name" || -z "$image" ]]; then
        log_error "Deployment name and image are required"
        return 1
    fi
    
    log_info "Creating deployment: $name"
    
    # Create deployment YAML
    local deployment_yaml="/tmp/deployment-${name}.yaml"
    cat > "$deployment_yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  namespace: $namespace
  labels:
    app: $name
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: $name
  template:
    metadata:
      labels:
        app: $name
    spec:
      containers:
      - name: $name
        image: $image
        ports:
        - containerPort: $port
        resources:
          limits:
            memory: "256Mi"
            cpu: "250m"
          requests:
            memory: "128Mi"
            cpu: "100m"
EOF
    
    # Apply deployment
    if kubectl apply -f "$deployment_yaml"; then
        log_success "Deployment $name created successfully"
        rm -f "$deployment_yaml"
        return 0
    else
        log_error "Failed to create deployment: $name"
        rm -f "$deployment_yaml"
        return 1
    fi
}

# Function to create service
create_service() {
    local name="${1:-}"
    local port="${2:-80}"
    local target_port="${3:-80}"
    local service_type="${4:-ClusterIP}"
    local namespace="${5:-default}"
    
    if [[ -z "$name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    log_info "Creating service: $name"
    
    # Create service YAML
    local service_yaml="/tmp/service-${name}.yaml"
    cat > "$service_yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: $name
  namespace: $namespace
  labels:
    app: $name
spec:
  selector:
    app: $name
  ports:
  - port: $port
    targetPort: $target_port
    protocol: TCP
  type: $service_type
EOF
    
    # Apply service
    if kubectl apply -f "$service_yaml"; then
        log_success "Service $name created successfully"
        rm -f "$service_yaml"
        return 0
    else
        log_error "Failed to create service: $name"
        rm -f "$service_yaml"
        return 1
    fi
}

# Function to get resource status
get_resource_status() {
    local resource_type="${1:-pods}"
    local namespace="${2:-default}"
    
    log_info "Getting $resource_type in namespace: $namespace"
    
    kubectl get "$resource_type" -n "$namespace" -o wide 2>/dev/null || {
        log_error "Failed to get $resource_type in namespace: $namespace"
        return 1
    }
}

# Function to describe resource
describe_resource() {
    local resource_type="${1:-}"
    local resource_name="${2:-}"
    local namespace="${3:-default}"
    
    if [[ -z "$resource_type" || -z "$resource_name" ]]; then
        log_error "Resource type and name are required"
        return 1
    fi
    
    log_info "Describing $resource_type/$resource_name in namespace: $namespace"
    
    kubectl describe "$resource_type" "$resource_name" -n "$namespace" 2>/dev/null || {
        log_error "Failed to describe $resource_type/$resource_name"
        return 1
    }
}

# Function to delete resource
delete_resource() {
    local resource_type="${1:-}"
    local resource_name="${2:-}"
    local namespace="${3:-default}"
    
    if [[ -z "$resource_type" || -z "$resource_name" ]]; then
        log_error "Resource type and name are required"
        return 1
    fi
    
    log_warning "Deleting $resource_type/$resource_name in namespace: $namespace"
    
    kubectl delete "$resource_type" "$resource_name" -n "$namespace" 2>/dev/null || {
        log_error "Failed to delete $resource_type/$resource_name"
        return 1
    }
    
    log_success "Successfully deleted $resource_type/$resource_name"
}

# Function to scale deployment
scale_deployment() {
    local deployment_name="${1:-}"
    local replicas="${2:-1}"
    local namespace="${3:-default}"
    
    if [[ -z "$deployment_name" ]]; then
        log_error "Deployment name is required"
        return 1
    fi
    
    log_info "Scaling deployment $deployment_name to $replicas replicas"
    
    kubectl scale deployment "$deployment_name" --replicas="$replicas" -n "$namespace" 2>/dev/null || {
        log_error "Failed to scale deployment: $deployment_name"
        return 1
    }
    
    log_success "Successfully scaled deployment $deployment_name to $replicas replicas"
}

# Function to get pod logs
get_pod_logs() {
    local pod_name="${1:-}"
    local namespace="${2:-default}"
    local lines="${3:-100}"
    
    if [[ -z "$pod_name" ]]; then
        log_error "Pod name is required"
        return 1
    fi
    
    log_info "Getting logs for pod: $pod_name (last $lines lines)"
    
    kubectl logs "$pod_name" -n "$namespace" --tail="$lines" 2>/dev/null || {
        log_error "Failed to get logs for pod: $pod_name"
        return 1
    }
}

# Function to execute command in pod
exec_pod_command() {
    local pod_name="${1:-}"
    local command="${2:-/bin/sh}"
    local namespace="${3:-default}"
    
    if [[ -z "$pod_name" ]]; then
        log_error "Pod name is required"
        return 1
    fi
    
    log_info "Executing command in pod: $pod_name"
    
    kubectl exec -it "$pod_name" -n "$namespace" -- $command 2>/dev/null || {
        log_error "Failed to execute command in pod: $pod_name"
        return 1
    }
}

# Function to port forward
port_forward() {
    local pod_name="${1:-}"
    local local_port="${2:-8080}"
    local pod_port="${3:-80}"
    local namespace="${4:-default}"
    
    if [[ -z "$pod_name" ]]; then
        log_error "Pod name is required"
        return 1
    fi
    
    log_info "Port forwarding $local_port:$pod_port to pod: $pod_name"
    
    kubectl port-forward "$pod_name" "$local_port:$pod_port" -n "$namespace" 2>/dev/null || {
        log_error "Failed to setup port forward to pod: $pod_name"
        return 1
    }
}

# Main function to handle script arguments
main() {
    local command="${1:-help}"
    
    case "$command" in
        "check")
            check_kubectl
            ;;
        "test-connection")
            test_cluster_connection "$2"
            ;;
        "setup-context")
            setup_kubectl_context "$2" "$3" "$4"
            ;;
        "create-deployment")
            create_deployment "$2" "$3" "$4" "$5" "$6"
            ;;
        "create-service")
            create_service "$2" "$3" "$4" "$5" "$6"
            ;;
        "get-status")
            get_resource_status "$2" "$3"
            ;;
        "describe")
            describe_resource "$2" "$3" "$4"
            ;;
        "delete")
            delete_resource "$2" "$3" "$4"
            ;;
        "scale")
            scale_deployment "$2" "$3" "$4"
            ;;
        "logs")
            get_pod_logs "$2" "$3" "$4"
            ;;
        "exec")
            exec_pod_command "$2" "$3" "$4"
            ;;
        "port-forward")
            port_forward "$2" "$3" "$4" "$5"
            ;;
        "help"|*)
            echo "Usage: $0 {check|test-connection|setup-context|create-deployment|create-service|get-status|describe|delete|scale|logs|exec|port-forward|help}"
            echo ""
            echo "Commands:"
            echo "  check                                           - Check if kubectl is available"
            echo "  test-connection <cluster-name>                  - Test cluster connectivity"
            echo "  setup-context <endpoint> <token> <cluster>     - Setup kubectl context"
            echo "  create-deployment <name> <image> [replicas] [port] [namespace] - Create deployment"
            echo "  create-service <name> [port] [target-port] [type] [namespace]  - Create service"
            echo "  get-status [resource-type] [namespace]          - Get resource status"
            echo "  describe <resource-type> <name> [namespace]     - Describe resource"
            echo "  delete <resource-type> <name> [namespace]       - Delete resource"
            echo "  scale <deployment> <replicas> [namespace]       - Scale deployment"
            echo "  logs <pod-name> [namespace] [lines]             - Get pod logs"
            echo "  exec <pod-name> [command] [namespace]           - Execute command in pod"
            echo "  port-forward <pod-name> [local-port] [pod-port] [namespace] - Port forward"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
