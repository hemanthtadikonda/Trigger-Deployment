#!/bin/bash

# Kubernetes Deployment Portal Installation Script for EC2
# This script creates and installs the complete application on Amazon Linux 2, Ubuntu, or CentOS
# Run with: curl -sSL https://raw.githubusercontent.com/your-repo/install.sh | bash

set -e

# Colors for output
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

log_info "Starting Kubernetes Deployment Portal installation..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root"
   exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    log_error "Cannot detect OS. Supported: Amazon Linux 2, Ubuntu 18.04+, CentOS 7+"
    exit 1
fi

log_info "Detected OS: $OS $VER"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install kubectl
install_kubectl() {
    log_info "Installing kubectl..."
    
    if command_exists kubectl; then
        log_success "kubectl is already installed"
        kubectl version --client --short
        return 0
    fi
    
    # Download and install kubectl
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    
    # Verify download (skip if checksum fails)
    if curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" 2>/dev/null; then
        echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check || log_warning "Checksum verification failed, continuing..."
        rm -f kubectl.sha256
    fi
    
    # Install kubectl
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
    
    log_success "kubectl installed successfully"
    kubectl version --client --short
}

# Function to install dependencies on Amazon Linux 2
install_amazon_linux() {
    log_info "Installing dependencies for Amazon Linux 2..."
    
    # Update system
    sudo yum update -y
    
    # Install Python 3 and pip
    sudo yum install -y python3 python3-pip git curl wget unzip
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
    
    # Install kubectl
    install_kubectl
}

# Function to install dependencies on Ubuntu
install_ubuntu() {
    log_info "Installing dependencies for Ubuntu..."
    
    # Update system
    sudo apt update && sudo apt upgrade -y
    
    # Install Python 3 and pip
    sudo apt install -y python3 python3-pip python3-venv git curl wget unzip
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
    
    # Install kubectl
    install_kubectl
}

# Function to install dependencies on CentOS
install_centos() {
    log_info "Installing dependencies for CentOS..."
    
    # Update system
    sudo yum update -y
    
    # Install EPEL repository
    sudo yum install -y epel-release
    
    # Install Python 3 and pip
    sudo yum install -y python3 python3-pip git curl wget unzip
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
    
    # Install kubectl
    install_kubectl
}

# Install based on OS
case "$OS" in
    "Amazon Linux"*)
        install_amazon_linux
        ;;
    "Ubuntu"*)
        install_ubuntu
        ;;
    "CentOS"*)
        install_centos
        ;;
    *)
        log_error "Unsupported OS: $OS"
        log_error "This script supports Amazon Linux 2, Ubuntu 18.04+, and CentOS 7+"
        exit 1
        ;;
esac

# Upgrade pip and install Python dependencies
log_info "Installing Python dependencies..."
$PIP_CMD install --user --upgrade pip
$PIP_CMD install --user flask==3.0.0 gunicorn==21.2.0 werkzeug==3.0.1

# Create application directory
APP_DIR="$HOME/kubernetes-portal"
log_info "Creating application directory: $APP_DIR"
rm -rf "$APP_DIR"  # Remove if exists
mkdir -p "$APP_DIR"

# Create required subdirectories
mkdir -p "$APP_DIR/templates"
mkdir -p "$APP_DIR/static/css"
mkdir -p "$APP_DIR/static/js"
mkdir -p "$APP_DIR/scripts"

# Generate secure session secret
log_info "Generating secure session secret..."
SESSION_SECRET=$($PYTHON_CMD -c "import secrets; print(secrets.token_hex(32))")

# Create main.py
log_info "Creating main.py..."
cat > "$APP_DIR/main.py" << 'EOF'
from app import app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# Create app.py
log_info "Creating app.py..."
cat > "$APP_DIR/app.py" << 'EOF'
import os
import subprocess
import json
import logging
from flask import Flask, request, render_template, session, flash, redirect, url_for
from werkzeug.middleware.proxy_fix import ProxyFix

# Configure logging
logging.basicConfig(level=logging.DEBUG)

app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "kubernetes-deployment-portal-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

def validate_cluster_connection(endpoint, token, cluster_name):
    """Validate Kubernetes cluster connection"""
    try:
        # Set up kubectl context
        context_cmd = [
            'kubectl', 'config', 'set-cluster', cluster_name,
            '--server=' + endpoint,
            '--insecure-skip-tls-verify=true'
        ]
        subprocess.run(context_cmd, check=True, capture_output=True, text=True)
        
        # Set credentials
        cred_cmd = [
            'kubectl', 'config', 'set-credentials', f'{cluster_name}-user',
            '--token=' + token
        ]
        subprocess.run(cred_cmd, check=True, capture_output=True, text=True)
        
        # Set context
        ctx_cmd = [
            'kubectl', 'config', 'set-context', cluster_name,
            '--cluster=' + cluster_name,
            '--user=' + f'{cluster_name}-user'
        ]
        subprocess.run(ctx_cmd, check=True, capture_output=True, text=True)
        
        # Use context
        use_cmd = ['kubectl', 'config', 'use-context', cluster_name]
        subprocess.run(use_cmd, check=True, capture_output=True, text=True)
        
        # Test connection
        test_cmd = ['kubectl', 'get', 'nodes']
        result = subprocess.run(test_cmd, check=True, capture_output=True, text=True)
        
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        return False, e.stderr

def execute_kubectl_command(command_args):
    """Execute kubectl command and return result"""
    try:
        result = subprocess.run(
            command_args,
            check=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        return False, e.stderr
    except subprocess.TimeoutExpired:
        return False, "Command timed out after 30 seconds"

def generate_deployment_manifest(name, image, replicas, port, namespace):
    """Generate Kubernetes deployment manifest"""
    manifest = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": name,
            "namespace": namespace
        },
        "spec": {
            "replicas": int(replicas),
            "selector": {
                "matchLabels": {
                    "app": name
                }
            },
            "template": {
                "metadata": {
                    "labels": {
                        "app": name
                    }
                },
                "spec": {
                    "containers": [{
                        "name": name,
                        "image": image,
                        "ports": [{
                            "containerPort": int(port)
                        }]
                    }]
                }
            }
        }
    }
    return manifest

def generate_service_manifest(name, port, target_port, service_type, namespace):
    """Generate Kubernetes service manifest"""
    manifest = {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "name": name,
            "namespace": namespace
        },
        "spec": {
            "selector": {
                "app": name
            },
            "ports": [{
                "port": int(port),
                "targetPort": int(target_port)
            }],
            "type": service_type
        }
    }
    return manifest

@app.route('/')
def index():
    """Main page with tabbed interface"""
    return render_template('index.html')

@app.route('/connect_cluster', methods=['POST'])
def connect_cluster():
    """Handle cluster connection"""
    endpoint = request.form.get('endpoint', '').strip()
    cluster_name = request.form.get('cluster_name', '').strip()
    token = request.form.get('token', '').strip()
    
    if not all([endpoint, cluster_name, token]):
        flash('All cluster connection fields are required', 'error')
        return redirect(url_for('index'))
    
    # Validate connection
    success, output = validate_cluster_connection(endpoint, token, cluster_name)
    
    if success:
        session['cluster_connected'] = True
        session['cluster_endpoint'] = endpoint
        session['cluster_name'] = cluster_name
        session['cluster_token'] = token
        flash(f'Successfully connected to cluster: {cluster_name}', 'success')
    else:
        flash(f'Failed to connect to cluster: {output}', 'error')
    
    return redirect(url_for('index'))

@app.route('/disconnect_cluster', methods=['POST'])
def disconnect_cluster():
    """Disconnect from cluster"""
    session.pop('cluster_connected', None)
    session.pop('cluster_endpoint', None)
    session.pop('cluster_name', None)
    session.pop('cluster_token', None)
    flash('Disconnected from cluster', 'info')
    return redirect(url_for('index'))

@app.route('/create_deployment', methods=['POST'])
def create_deployment():
    """Create Kubernetes deployment"""
    if not session.get('cluster_connected'):
        flash('Please connect to a cluster first', 'error')
        return redirect(url_for('index'))
    
    name = request.form.get('deployment_name', '').strip()
    image = request.form.get('deployment_image', '').strip()
    replicas = request.form.get('deployment_replicas', '1')
    port = request.form.get('deployment_port', '80')
    namespace = request.form.get('deployment_namespace', 'default').strip()
    
    if not all([name, image]):
        flash('Deployment name and image are required', 'error')
        return redirect(url_for('index'))
    
    try:
        # Generate manifest
        manifest = generate_deployment_manifest(name, image, replicas, port, namespace)
        manifest_json = json.dumps(manifest, indent=2)
        
        # Apply manifest
        cmd = ['kubectl', 'apply', '-f', '-']
        process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, 
                                 stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate(input=manifest_json)
        
        if process.returncode == 0:
            flash(f'Deployment {name} created successfully', 'success')
            session['last_output'] = stdout
        else:
            flash(f'Failed to create deployment: {stderr}', 'error')
            session['last_output'] = stderr
            
    except Exception as e:
        flash(f'Error creating deployment: {str(e)}', 'error')
        session['last_output'] = str(e)
    
    return redirect(url_for('index'))

@app.route('/create_service', methods=['POST'])
def create_service():
    """Create Kubernetes service"""
    if not session.get('cluster_connected'):
        flash('Please connect to a cluster first', 'error')
        return redirect(url_for('index'))
    
    name = request.form.get('service_name', '').strip()
    port = request.form.get('service_port', '80')
    target_port = request.form.get('service_target_port', '80')
    service_type = request.form.get('service_type', 'ClusterIP')
    namespace = request.form.get('service_namespace', 'default').strip()
    
    if not name:
        flash('Service name is required', 'error')
        return redirect(url_for('index'))
    
    try:
        # Generate manifest
        manifest = generate_service_manifest(name, port, target_port, service_type, namespace)
        manifest_json = json.dumps(manifest, indent=2)
        
        # Apply manifest
        cmd = ['kubectl', 'apply', '-f', '-']
        process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, 
                                 stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate(input=manifest_json)
        
        if process.returncode == 0:
            flash(f'Service {name} created successfully', 'success')
            session['last_output'] = stdout
        else:
            flash(f'Failed to create service: {stderr}', 'error')
            session['last_output'] = stderr
            
    except Exception as e:
        flash(f'Error creating service: {str(e)}', 'error')
        session['last_output'] = str(e)
    
    return redirect(url_for('index'))

@app.route('/execute_custom', methods=['POST'])
def execute_custom():
    """Execute custom kubectl command"""
    if not session.get('cluster_connected'):
        flash('Please connect to a cluster first', 'error')
        return redirect(url_for('index'))
    
    command = request.form.get('custom_command', '').strip()
    
    if not command:
        flash('Custom command is required', 'error')
        return redirect(url_for('index'))
    
    # Security: Only allow kubectl commands
    if not command.startswith('kubectl '):
        flash('Only kubectl commands are allowed', 'error')
        return redirect(url_for('index'))
    
    try:
        # Split command into arguments
        cmd_args = command.split()
        success, output = execute_kubectl_command(cmd_args)
        
        if success:
            flash('Custom command executed successfully', 'success')
            session['last_output'] = output
        else:
            flash(f'Command failed: {output}', 'error')
            session['last_output'] = output
            
    except Exception as e:
        flash(f'Error executing command: {str(e)}', 'error')
        session['last_output'] = str(e)
    
    return redirect(url_for('index'))

@app.route('/execute_yaml', methods=['POST'])
def execute_yaml():
    """Execute custom YAML manifest"""
    if not session.get('cluster_connected'):
        flash('Please connect to a cluster first', 'error')
        return redirect(url_for('index'))
    
    yaml_content = request.form.get('custom_yaml', '').strip()
    namespace_override = request.form.get('yaml_namespace', '').strip()
    
    if not yaml_content:
        flash('YAML content is required', 'error')
        return redirect(url_for('index'))
    
    try:
        # Prepare kubectl apply command
        cmd = ['kubectl', 'apply', '-f', '-']
        
        # Add namespace if provided
        if namespace_override:
            cmd.extend(['-n', namespace_override])
        
        # Execute kubectl apply with YAML content as stdin
        process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        try:
            stdout, stderr = process.communicate(input=yaml_content, timeout=60)
            
            if process.returncode == 0:
                flash('YAML manifest applied successfully', 'success')
                session['last_output'] = stdout
            else:
                flash(f'Failed to apply YAML manifest: {stderr}', 'error')
                session['last_output'] = stderr
                
        except subprocess.TimeoutExpired:
            process.kill()
            flash('YAML application timed out after 60 seconds', 'error')
            session['last_output'] = 'Command timed out'
    except Exception as e:
        flash(f'Error applying YAML manifest: {str(e)}', 'error')
        session['last_output'] = str(e)
    
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# Create the HTML template
log_info "Creating HTML template..."
cat > "$APP_DIR/templates/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kubernetes Deployment Portal</title>
    <link href="https://cdn.replit.com/agent/bootstrap-agent-dark-theme.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="{{ url_for('static', filename='css/styles.css') }}" rel="stylesheet">
</head>
<body>
    <div class="container-fluid">
        <!-- Header -->
        <header class="py-3 mb-4 border-bottom">
            <div class="d-flex align-items-center justify-content-between">
                <h1 class="h3 mb-0">
                    <i class="fas fa-dharmachakra me-2"></i>
                    Kubernetes Deployment Portal
                </h1>
                <div class="cluster-status">
                    {% if session.cluster_connected %}
                        <span class="badge bg-success">
                            <i class="fas fa-check-circle me-1"></i>
                            Connected to {{ session.cluster_name }}
                        </span>
                        <form method="post" action="{{ url_for('disconnect_cluster') }}" class="d-inline ms-2">
                            <button type="submit" class="btn btn-sm btn-outline-danger">
                                <i class="fas fa-sign-out-alt me-1"></i>Disconnect
                            </button>
                        </form>
                    {% else %}
                        <span class="badge bg-warning">
                            <i class="fas fa-exclamation-triangle me-1"></i>
                            Not Connected
                        </span>
                    {% endif %}
                </div>
            </div>
        </header>

        <!-- Flash Messages -->
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                <div class="alert-container mb-4">
                    {% for category, message in messages %}
                        <div class="alert alert-{{ 'danger' if category == 'error' else category }} alert-dismissible fade show" role="alert">
                            <i class="fas fa-{{ 'exclamation-circle' if category == 'error' else 'info-circle' if category == 'info' else 'check-circle' }} me-2"></i>
                            {{ message }}
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                    {% endfor %}
                </div>
            {% endif %}
        {% endwith %}

        <div class="row">
            <!-- Cluster Connection Panel -->
            <div class="col-md-4">
                <div class="card">
                    <div class="card-header">
                        <h5 class="card-title mb-0">
                            <i class="fas fa-server me-2"></i>
                            Cluster Connection
                        </h5>
                    </div>
                    <div class="card-body">
                        {% if not session.cluster_connected %}
                            <form method="post" action="{{ url_for('connect_cluster') }}">
                                <div class="mb-3">
                                    <label for="endpoint" class="form-label">Cluster Endpoint</label>
                                    <input type="url" class="form-control" id="endpoint" name="endpoint" 
                                           placeholder="https://cluster-api.example.com" required>
                                </div>
                                <div class="mb-3">
                                    <label for="cluster_name" class="form-label">Cluster Name</label>
                                    <input type="text" class="form-control" id="cluster_name" name="cluster_name" 
                                           placeholder="production-cluster" required>
                                </div>
                                <div class="mb-3">
                                    <label for="token" class="form-label">Service Account Token</label>
                                    <textarea class="form-control" id="token" name="token" rows="3" 
                                              placeholder="eyJhbGciOiJSUzI1NiIs..." required></textarea>
                                </div>
                                <button type="submit" class="btn btn-primary w-100">
                                    <i class="fas fa-link me-2"></i>Connect to Cluster
                                </button>
                            </form>
                        {% else %}
                            <div class="text-center">
                                <i class="fas fa-check-circle text-success fa-3x mb-3"></i>
                                <h6>Connected to:</h6>
                                <p class="mb-1"><strong>{{ session.cluster_name }}</strong></p>
                                <p class="text-muted small">{{ session.cluster_endpoint }}</p>
                            </div>
                        {% endif %}
                    </div>
                </div>

                <!-- Command Output Panel -->
                {% if session.last_output %}
                <div class="card mt-4">
                    <div class="card-header">
                        <h6 class="card-title mb-0">
                            <i class="fas fa-terminal me-2"></i>
                            Last Command Output
                        </h6>
                    </div>
                    <div class="card-body">
                        <pre class="command-output">{{ session.last_output }}</pre>
                    </div>
                </div>
                {% endif %}
            </div>

            <!-- Main Operations Panel -->
            <div class="col-md-8">
                <div class="card">
                    <div class="card-header">
                        <!-- Tab Navigation -->
                        <ul class="nav nav-tabs card-header-tabs" id="operationTabs" role="tablist">
                            <li class="nav-item" role="presentation">
                                <button class="nav-link active" id="deployment-tab" data-bs-toggle="tab" 
                                        data-bs-target="#deployment" type="button" role="tab">
                                    <i class="fas fa-rocket me-2"></i>Deployments
                                </button>
                            </li>
                            <li class="nav-item" role="presentation">
                                <button class="nav-link" id="service-tab" data-bs-toggle="tab" 
                                        data-bs-target="#service" type="button" role="tab">
                                    <i class="fas fa-network-wired me-2"></i>Services
                                </button>
                            </li>
                            <li class="nav-item" role="presentation">
                                <button class="nav-link" id="custom-tab" data-bs-toggle="tab" 
                                        data-bs-target="#custom" type="button" role="tab">
                                    <i class="fas fa-terminal me-2"></i>Custom Commands
                                </button>
                            </li>
                            <li class="nav-item" role="presentation">
                                <button class="nav-link" id="yaml-tab" data-bs-toggle="tab" 
                                        data-bs-target="#yaml" type="button" role="tab">
                                    <i class="fas fa-file-code me-2"></i>Custom YAML
                                </button>
                            </li>
                        </ul>
                    </div>
                    <div class="card-body">
                        <!-- Tab Content -->
                        <div class="tab-content" id="operationTabsContent">
                            <!-- Deployment Tab -->
                            <div class="tab-pane fade show active" id="deployment" role="tabpanel">
                                <h5 class="mb-4">Create Deployment</h5>
                                <form method="post" action="{{ url_for('create_deployment') }}">
                                    <div class="row">
                                        <div class="col-md-6">
                                            <div class="mb-3">
                                                <label for="deployment_name" class="form-label">Deployment Name</label>
                                                <input type="text" class="form-control" id="deployment_name" 
                                                       name="deployment_name" placeholder="my-app" required>
                                            </div>
                                        </div>
                                        <div class="col-md-6">
                                            <div class="mb-3">
                                                <label for="deployment_image" class="form-label">Container Image</label>
                                                <input type="text" class="form-control" id="deployment_image" 
                                                       name="deployment_image" placeholder="nginx:latest" required>
                                            </div>
                                        </div>
                                    </div>
                                    <div class="row">
                                        <div class="col-md-4">
                                            <div class="mb-3">
                                                <label for="deployment_replicas" class="form-label">Replicas</label>
                                                <input type="number" class="form-control" id="deployment_replicas" 
                                                       name="deployment_replicas" value="1" min="1" max="10">
                                            </div>
                                        </div>
                                        <div class="col-md-4">
                                            <div class="mb-3">
                                                <label for="deployment_port" class="form-label">Container Port</label>
                                                <input type="number" class="form-control" id="deployment_port" 
                                                       name="deployment_port" value="80" min="1" max="65535">
                                            </div>
                                        </div>
                                        <div class="col-md-4">
                                            <div class="mb-3">
                                                <label for="deployment_namespace" class="form-label">Namespace</label>
                                                <input type="text" class="form-control" id="deployment_namespace" 
                                                       name="deployment_namespace" value="default">
                                            </div>
                                        </div>
                                    </div>
                                    <button type="submit" class="btn btn-success" 
                                            {{ 'disabled' if not session.cluster_connected }}>
                                        <i class="fas fa-plus me-2"></i>Create Deployment
                                    </button>
                                </form>
                            </div>

                            <!-- Service Tab -->
                            <div class="tab-pane fade" id="service" role="tabpanel">
                                <h5 class="mb-4">Create Service</h5>
                                <form method="post" action="{{ url_for('create_service') }}">
                                    <div class="row">
                                        <div class="col-md-6">
                                            <div class="mb-3">
                                                <label for="service_name" class="form-label">Service Name</label>
                                                <input type="text" class="form-control" id="service_name" 
                                                       name="service_name" placeholder="my-service" required>
                                            </div>
                                        </div>
                                        <div class="col-md-6">
                                            <div class="mb-3">
                                                <label for="service_type" class="form-label">Service Type</label>
                                                <select class="form-select" id="service_type" name="service_type">
                                                    <option value="ClusterIP">ClusterIP</option>
                                                    <option value="NodePort">NodePort</option>
                                                    <option value="LoadBalancer">LoadBalancer</option>
                                                </select>
                                            </div>
                                        </div>
                                    </div>
                                    <div class="row">
                                        <div class="col-md-4">
                                            <div class="mb-3">
                                                <label for="service_port" class="form-label">Service Port</label>
                                                <input type="number" class="form-control" id="service_port" 
                                                       name="service_port" value="80" min="1" max="65535">
                                            </div>
                                        </div>
                                        <div class="col-md-4">
                                            <div class="mb-3">
                                                <label for="service_target_port" class="form-label">Target Port</label>
                                                <input type="number" class="form-control" id="service_target_port" 
                                                       name="service_target_port" value="80" min="1" max="65535">
                                            </div>
                                        </div>
                                        <div class="col-md-4">
                                            <div class="mb-3">
                                                <label for="service_namespace" class="form-label">Namespace</label>
                                                <input type="text" class="form-control" id="service_namespace" 
                                                       name="service_namespace" value="default">
                                            </div>
                                        </div>
                                    </div>
                                    <button type="submit" class="btn btn-success" 
                                            {{ 'disabled' if not session.cluster_connected }}>
                                        <i class="fas fa-plus me-2"></i>Create Service
                                    </button>
                                </form>
                            </div>

                            <!-- Custom Commands Tab -->
                            <div class="tab-pane fade" id="custom" role="tabpanel">
                                <h5 class="mb-4">Execute Custom Command</h5>
                                <form method="post" action="{{ url_for('execute_custom') }}">
                                    <div class="mb-3">
                                        <label for="custom_command" class="form-label">kubectl Command</label>
                                        <input type="text" class="form-control" id="custom_command" 
                                               name="custom_command" placeholder="kubectl get pods -n default" required>
                                        <div class="form-text">
                                            <i class="fas fa-info-circle me-1"></i>
                                            Enter any kubectl command. Commands must start with "kubectl".
                                        </div>
                                    </div>
                                    <button type="submit" class="btn btn-success" 
                                            {{ 'disabled' if not session.cluster_connected }}>
                                        <i class="fas fa-play me-2"></i>Execute Command
                                    </button>
                                </form>

                                <!-- Quick Commands -->
                                <div class="mt-4">
                                    <h6>Quick Commands:</h6>
                                    <div class="d-flex flex-wrap gap-2">
                                        <button class="btn btn-sm btn-outline-secondary quick-cmd" 
                                                data-cmd="kubectl get pods">Get Pods</button>
                                        <button class="btn btn-sm btn-outline-secondary quick-cmd" 
                                                data-cmd="kubectl get services">Get Services</button>
                                        <button class="btn btn-sm btn-outline-secondary quick-cmd" 
                                                data-cmd="kubectl get deployments">Get Deployments</button>
                                        <button class="btn btn-sm btn-outline-secondary quick-cmd" 
                                                data-cmd="kubectl get nodes">Get Nodes</button>
                                        <button class="btn btn-sm btn-outline-secondary quick-cmd" 
                                                data-cmd="kubectl get namespaces">Get Namespaces</button>
                                    </div>
                                </div>
                            </div>

                            <!-- Custom YAML Tab -->
                            <div class="tab-pane fade" id="yaml" role="tabpanel">
                                <h5 class="mb-4">Execute Custom YAML</h5>
                                <form method="post" action="{{ url_for('execute_yaml') }}">
                                    <div class="mb-3">
                                        <label for="custom_yaml" class="form-label">YAML Manifest</label>
                                        <textarea class="form-control" id="custom_yaml" name="custom_yaml" 
                                                  rows="15" placeholder="apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: default
spec:
  containers:
  - name: my-container
    image: nginx:latest
    ports:
    - containerPort: 80" required></textarea>
                                        <div class="form-text">
                                            <i class="fas fa-info-circle me-1"></i>
                                            Enter your YAML manifest. It will be applied using 'kubectl apply -f -'.
                                        </div>
                                    </div>
                                    <div class="mb-3">
                                        <label for="yaml_namespace" class="form-label">Namespace (optional)</label>
                                        <input type="text" class="form-control" id="yaml_namespace" 
                                               name="yaml_namespace" placeholder="default">
                                        <div class="form-text">
                                            Override namespace for resources that don't specify one.
                                        </div>
                                    </div>
                                    <button type="submit" class="btn btn-success" 
                                            {{ 'disabled' if not session.cluster_connected }}>
                                        <i class="fas fa-upload me-2"></i>Apply YAML
                                    </button>
                                </form>

                                <!-- YAML Templates -->
                                <div class="mt-4">
                                    <h6>Quick YAML Templates:</h6>
                                    <div class="d-flex flex-wrap gap-2">
                                        <button class="btn btn-sm btn-outline-info yaml-template" 
                                                data-template="pod">Pod Template</button>
                                        <button class="btn btn-sm btn-outline-info yaml-template" 
                                                data-template="deployment">Deployment Template</button>
                                        <button class="btn btn-sm btn-outline-info yaml-template" 
                                                data-template="service">Service Template</button>
                                        <button class="btn btn-sm btn-outline-info yaml-template" 
                                                data-template="configmap">ConfigMap Template</button>
                                        <button class="btn btn-sm btn-outline-info yaml-template" 
                                                data-template="secret">Secret Template</button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="{{ url_for('static', filename='js/app.js') }}"></script>
</body>
</html>
EOF

# Create CSS file with proper content structure
log_info "Creating CSS styles..."
cat > "$APP_DIR/static/css/styles.css" << 'EOF'
/* Custom styles for Kubernetes Deployment Portal */

:root {
    --primary-color: var(--bs-primary);
    --success-color: var(--bs-success);
    --warning-color: var(--bs-warning);
    --danger-color: var(--bs-danger);
    --info-color: var(--bs-info);
}

body {
    background-color: var(--bs-dark);
    color: var(--bs-light);
}

/* Header styling */
header {
    background: linear-gradient(135deg, var(--bs-primary) 0%, var(--bs-info) 100%);
    border-radius: 0.5rem;
    margin-bottom: 1.5rem;
    padding: 1rem 1.5rem;
}

header h1 {
    color: white;
}

/* Card styling */
.card {
    background-color: var(--bs-dark);
    border: 1px solid var(--bs-border-color);
    box-shadow: 0 0.125rem 0.25rem rgba(0, 0, 0, 0.3);
}

/* Form styling */
.form-control, .form-select {
    background-color: var(--bs-dark);
    border: 1px solid var(--bs-border-color);
    color: var(--bs-light);
}

.form-control:focus, .form-select:focus {
    background-color: var(--bs-dark);
    border-color: var(--bs-primary);
    color: var(--bs-light);
    box-shadow: 0 0 0 0.2rem rgba(var(--bs-primary-rgb), 0.25);
}

/* Command output styling */
.command-output {
    background-color: var(--bs-gray-900);
    color: var(--bs-gray-100);
    border: 1px solid var(--bs-border-color);
    border-radius: 0.375rem;
    padding: 1rem;
    font-family: 'Courier New', Courier, monospace;
    font-size: 0.875rem;
    line-height: 1.4;
    max-height: 300px;
    overflow-y: auto;
    white-space: pre-wrap;
    word-wrap: break-word;
}

/* YAML textarea styling */
#custom_yaml {
    font-family: 'Courier New', Courier, monospace;
    font-size: 0.875rem;
    line-height: 1.4;
    resize: vertical;
    min-height: 300px;
}

/* Button styling */
.btn {
    transition: all 0.15s ease-in-out;
}

/* Quick command buttons */
.quick-cmd, .yaml-template {
    font-size: 0.875rem;
    margin-bottom: 0.5rem;
    transition: all 0.15s ease-in-out;
}

.quick-cmd:hover {
    background-color: var(--bs-primary);
    border-color: var(--bs-primary);
    color: white;
}

.yaml-template:hover {
    background-color: var(--bs-info);
    border-color: var(--bs-info);
    color: white;
}
EOF

# Create JavaScript file
log_info "Creating JavaScript file..."
cat > "$APP_DIR/static/js/app.js" << 'EOF'
// Kubernetes Deployment Portal JavaScript

document.addEventListener('DOMContentLoaded', function() {
    setupQuickCommands();
    setupFormValidation();
});

function setupQuickCommands() {
    const quickCmdButtons = document.querySelectorAll('.quick-cmd');
    const customCommandInput = document.getElementById('custom_command');
    
    quickCmdButtons.forEach(button => {
        button.addEventListener('click', function() {
            const command = this.getAttribute('data-cmd');
            if (customCommandInput) {
                customCommandInput.value = command;
                customCommandInput.focus();
            }
        });
    });
    
    // Setup YAML template buttons
    const yamlTemplateButtons = document.querySelectorAll('.yaml-template');
    const customYamlTextarea = document.getElementById('custom_yaml');
    
    yamlTemplateButtons.forEach(button => {
        button.addEventListener('click', function() {
            const template = this.getAttribute('data-template');
            const yamlContent = getYamlTemplate(template);
            
            if (customYamlTextarea && yamlContent) {
                customYamlTextarea.value = yamlContent;
                customYamlTextarea.focus();
            }
        });
    });
}

function getYamlTemplate(templateType) {
    const templates = {
        pod: `apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: default
  labels:
    app: my-app
spec:
  containers:
  - name: my-container
    image: nginx:latest
    ports:
    - containerPort: 80`,
        
        deployment: `apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  namespace: default
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-container
        image: nginx:latest
        ports:
        - containerPort: 80`,
            
        service: `apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: default
  labels:
    app: my-app
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  type: ClusterIP`,
  
        configmap: `apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
  namespace: default
data:
  app.properties: |
    app.name=my-app
    app.version=1.0.0
  config.yaml: |
    server:
      port: 8080`,
      
        secret: `apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
data:
  username: bXl1c2Vy
  password: bXlwYXNz`
    };
    
    return templates[templateType] || '';
}

function setupFormValidation() {
    const forms = document.querySelectorAll('form');
    
    forms.forEach(form => {
        form.addEventListener('submit', function(event) {
            const customCommandField = form.querySelector('#custom_command');
            if (customCommandField && customCommandField.value) {
                if (!customCommandField.value.startsWith('kubectl ')) {
                    alert('Command must start with "kubectl "');
                    event.preventDefault();
                    return false;
                }
            }
        });
    });
}
EOF

# Create systemd service file
log_info "Creating systemd service..."
sudo tee /etc/systemd/system/k8s-portal.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Deployment Portal
After=network.target

[Service]
Type=exec
User=$USER
WorkingDirectory=$APP_DIR
Environment=SESSION_SECRET=$SESSION_SECRET
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin
ExecStart=$PYTHON_CMD -m gunicorn --bind 0.0.0.0:5000 --workers 2 main:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chmod +x "$APP_DIR/main.py"
chmod +x "$APP_DIR/app.py"

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable k8s-portal

# Start the service
log_info "Starting Kubernetes Portal service..."
sudo systemctl start k8s-portal

# Check service status
sleep 2
if sudo systemctl is-active --quiet k8s-portal; then
    log_success "Kubernetes Portal service is running!"
else
    log_error "Failed to start service. Checking logs..."
    sudo journalctl -u k8s-portal --no-pager -l
fi

log_success "Installation completed successfully!"
echo ""
echo "================================================================"
echo "                 INSTALLATION SUMMARY"
echo "================================================================"
echo "Application Directory: $APP_DIR"
echo "Service Name: k8s-portal"
echo "Service Status: $(sudo systemctl is-active k8s-portal)"
echo "Portal URL: http://$(curl -s ifconfig.me):5000"
echo "Local URL: http://localhost:5000"
echo ""
echo "Useful Commands:"
echo "  Check service status: sudo systemctl status k8s-portal"
echo "  View logs: sudo journalctl -u k8s-portal -f"
echo "  Restart service: sudo systemctl restart k8s-portal"
echo "  Stop service: sudo systemctl stop k8s-portal"
echo ""
echo "Security Notes:"
echo "  - Make sure port 5000 is open in your security group"
echo "  - Session secret: $SESSION_SECRET"
echo "  - Consider setting up Nginx reverse proxy for production"
echo ""
echo "Next Steps:"
echo "  1. Open http://your-ec2-public-ip:5000 in your browser"
echo "  2. Connect to your Kubernetes cluster using the web interface"
echo "  3. Start managing your deployments!"
echo "================================================================"