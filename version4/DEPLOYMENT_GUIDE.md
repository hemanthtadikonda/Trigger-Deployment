# Kubernetes Portal - EC2 Deployment Guide

## Quick Deployment Commands

After cloning your repository to your EC2 server, follow these simple steps:

### 1. Clone Repository
```bash
git clone https://github.com/your-username/kubernetes-portal.git
cd kubernetes-portal
```

### 2. Run Installation Script
```bash
chmod +x deploy.sh
./deploy.sh
```

**That's it!** The script handles everything automatically.

---

## Manual Step-by-Step (if needed)

If you prefer to run commands manually:

### 1. Update System & Install Dependencies
```bash
# For Amazon Linux 2
sudo yum update -y
sudo yum install -y python3 python3-pip git curl

# For Ubuntu
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip git curl
```

### 2. Install kubectl
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

### 3. Install Python Dependencies
```bash
pip3 install --user flask gunicorn werkzeug
```

### 4. Create Systemd Service
```bash
# Generate session secret
SESSION_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")

# Create service file
sudo tee /etc/systemd/system/k8s-portal.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Deployment Portal
After=network.target

[Service]
Type=exec
User=$USER
WorkingDirectory=$(pwd)
Environment=SESSION_SECRET=$SESSION_SECRET
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin
ExecStart=python3 -m gunicorn --bind 0.0.0.0:5000 --workers 2 main:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
```

### 5. Start Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable k8s-portal
sudo systemctl start k8s-portal
```

### 6. Check Status
```bash
sudo systemctl status k8s-portal
```

---

## Access Your Portal

- **Public URL**: `http://your-ec2-public-ip:5000`
- **Local URL**: `http://localhost:5000`

## Security Group Settings

Make sure your EC2 security group allows:
- **Port 22**: SSH access
- **Port 5000**: Web portal access

## Useful Commands

```bash
# Check service status
sudo systemctl status k8s-portal

# View real-time logs
sudo journalctl -u k8s-portal -f

# Restart service
sudo systemctl restart k8s-portal

# Stop service
sudo systemctl stop k8s-portal

# Check if kubectl is working
kubectl version --client
```

## Troubleshooting

If the service fails to start:
```bash
# Check detailed logs
sudo journalctl -u k8s-portal --no-pager -l

# Check if port 5000 is in use
sudo netstat -tulpn | grep :5000

# Test the app manually
cd /path/to/kubernetes-portal
python3 main.py
```

## File Structure
```
kubernetes-portal/
├── app.py              # Main Flask application
├── main.py             # Application entry point
├── deploy.sh           # Automated installation script
├── templates/
│   └── index.html      # Web interface
├── static/
│   ├── css/styles.css  # Styling
│   └── js/app.js       # JavaScript functionality
└── README.md           # Project documentation
```