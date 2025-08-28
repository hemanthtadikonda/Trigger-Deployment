#!/bin/bash

# Kubernetes Deployment Portal Installation Script for EC2
# This script automates the complete installation process on Amazon Linux 2 or Ubuntu
# Run with: curl -sSL https://your-script-url/install.sh | bash

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

# Function to install dependencies on Amazon Linux 2
install_amazon_linux() {
    log_info "Installing dependencies for Amazon Linux 2..."
    
    # Update system
    sudo yum update -y
    
    # Install EPEL repository for additional packages
    sudo yum install -y epel-release
    
    # Install Python 3.11 or fallback to available version
    if sudo yum install -y python3.11 python3.11-pip; then
        PYTHON_CMD="python3.11"
        PIP_CMD="pip3.11"
    elif sudo yum install -y python3.9 python3.9-pip; then
        PYTHON_CMD="python3.9"
        PIP_CMD="pip3.9"
        log_warning "Python 3.11 not available, using Python 3.9"
    else
        sudo yum install -y python3 python3-pip
        PYTHON_CMD="python3"
        PIP_CMD="pip3"
        log_warning "Using default Python 3"
    fi
    
    # Install git and curl
    sudo yum install -y git curl wget unzip
    
    # Install kubectl
    install_kubectl
}

# Function to install dependencies on Ubuntu
install_ubuntu() {
    log_info "Installing dependencies for Ubuntu..."
    
    # Update system
    sudo apt update && sudo apt upgrade -y
    
    # Install prerequisites
    sudo apt install -y software-properties-common curl wget git unzip
    
    # Add deadsnakes PPA for Python 3.11
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt update
    
    # Install Python 3.11 or fallback
    if sudo apt install -y python3.11 python3.11-pip python3.11-venv; then
        PYTHON_CMD="python3.11"
        PIP_CMD="pip3.11"
    elif sudo apt install -y python3.9 python3.9-pip python3.9-venv; then
        PYTHON_CMD="python3.9"
        PIP_CMD="pip3.9"
        log_warning "Python 3.11 not available, using Python 3.9"
    else
        sudo apt install -y python3 python3-pip python3-venv
        PYTHON_CMD="python3"
        PIP_CMD="pip3"
        log_warning "Using default Python 3"
    fi
    
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
    
    # Verify download
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    
    # Install kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl kubectl.sha256
    
    log_success "kubectl installed successfully"
    kubectl version --client --short
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
$PIP_CMD install --upgrade pip
$PIP_CMD install flask==3.0.0 gunicorn==21.2.0 werkzeug==3.0.1

# Create application directory
APP_DIR="$HOME/kubernetes-portal"
log_info "Creating application directory: $APP_DIR"
mkdir -p "$APP_DIR"

# Create required subdirectories
mkdir -p "$APP_DIR/templates"
mkdir -p "$APP_DIR/static/css"
mkdir -p "$APP_DIR/static/js"
mkdir -p "$APP_DIR/scripts"

# Generate secure session secret
log_info "Generating secure session secret..."
SESSION_SECRET=$($PYTHON_CMD -c "import secrets; print(secrets.token_hex(32))")

# Download application files from this repository
log_info "Creating application files..."

# Create main.py
cat > "$APP_DIR/main.py" << 'EOF'
from app import app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF
[Unit]
Description=Kubernetes Deployment Portal
After=network.target

[Service]
Type=exec
User=$USER
WorkingDirectory=$APP_DIR
Environment=SESSION_SECRET=$SESSION_SECRET
ExecStart=/usr/bin/python3.11 -m gunicorn --bind 0.0.0.0:5000 --workers 2 main:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Installation completed!"
echo ""
echo "📋 Next steps:"
echo "1. Copy your application files to: $APP_DIR"
echo "2. Make sure all Python files (app.py, main.py) are in the directory"
echo "3. Copy the templates/ and static/ directories"
echo "4. Start the service with: sudo systemctl start k8s-portal"
echo "5. Enable auto-start: sudo systemctl enable k8s-portal"
echo "6. Check status: sudo systemctl status k8s-portal"
echo ""
echo "🌐 Your portal will be available at: http://your-ec2-public-ip:5000"
echo "🔑 Generated session secret: $SESSION_SECRET"
echo ""
echo "💡 Optional: Install Nginx as reverse proxy for production use"
echo "💡 Configure security groups to allow port 5000 access"