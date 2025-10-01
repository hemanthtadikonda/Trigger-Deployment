# Kubernetes Deployment Portal

A Flask-based web portal for managing Kubernetes clusters with an intuitive interface.

## Features

- **Cluster Connection**: Connect to Kubernetes clusters using endpoint, name, and service account token
- **Deployment Management**: Create and manage Kubernetes deployments with custom configurations
- **Service Management**: Create various types of Kubernetes services (ClusterIP, NodePort, LoadBalancer)
- **Custom Commands**: Execute any kubectl command through the web interface
- **Custom YAML**: Apply your own YAML manifests with built-in templates
- **Dark Theme**: Modern Bootstrap dark theme with responsive design

## Prerequisites

- Python 3.11+
- kubectl installed and configured
- Access to a Kubernetes cluster

## Installation

### Local Installation

1. **Clone or download the project files**
2. **Install Python dependencies**:
   ```bash
   pip install flask gunicorn werkzeug
   ```

3. **Set environment variables** (optional):
   ```bash
   export SESSION_SECRET="your-secret-key-here"
   ```

4. **Run the application**:
   ```bash
   python main.py
   ```

5. **Access the portal**:
   Open your browser and go to `http://localhost:5000`

### AWS EC2 Installation

#### Step 1: Launch EC2 Instance

1. Launch an Amazon Linux 2 or Ubuntu EC2 instance
2. Configure security group to allow:
   - SSH (port 22) from your IP
   - HTTP (port 80) from anywhere (0.0.0.0/0)
   - HTTPS (port 443) from anywhere (0.0.0.0/0)
   - Custom port 5000 from anywhere (0.0.0.0/0)

#### Step 2: Connect to EC2 Instance

```bash
ssh -i your-key.pem ec2-user@your-ec2-public-ip
```

#### Step 3: Install Dependencies

**For Amazon Linux 2:**
```bash
# Update system
sudo yum update -y

# Install Python 3.11 and pip
sudo yum install -y python3.11 python3.11-pip

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install git (if you want to clone from a repository)
sudo yum install -y git
```

**For Ubuntu:**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python 3.11 and pip
sudo apt install -y python3.11 python3.11-pip

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install git
sudo apt install -y git
```

#### Step 4: Transfer Application Files

**Option A: Using SCP**
```bash
# From your local machine, copy all files to EC2
scp -i your-key.pem -r /path/to/your/project/* ec2-user@your-ec2-public-ip:~/kubernetes-portal/
```

**Option B: Create files manually**
```bash
# On EC2, create the project directory
mkdir -p ~/kubernetes-portal
cd ~/kubernetes-portal

# Create all the necessary files manually by copying the content
```

#### Step 5: Install Python Dependencies

```bash
cd ~/kubernetes-portal

# Install Flask dependencies
pip3.11 install flask gunicorn werkzeug
```

#### Step 6: Set Up as a Service (Recommended)

Create a systemd service file:

```bash
sudo nano /etc/systemd/system/k8s-portal.service
```

Add the following content:

```ini
[Unit]
Description=Kubernetes Deployment Portal
After=network.target

[Service]
Type=exec
User=ec2-user
WorkingDirectory=/home/ec2-user/kubernetes-portal
Environment=SESSION_SECRET=your-secure-secret-key-here
ExecStart=/usr/bin/python3.11 -m gunicorn --bind 0.0.0.0:5000 --workers 2 main:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable k8s-portal
sudo systemctl start k8s-portal
sudo systemctl status k8s-portal
```

#### Step 7: Set Up Nginx (Optional - for production)

Install and configure Nginx as a reverse proxy:

```bash
sudo yum install -y nginx  # Amazon Linux
# or
sudo apt install -y nginx  # Ubuntu

sudo nano /etc/nginx/conf.d/k8s-portal.conf
```

Add Nginx configuration:

```nginx
server {
    listen 80;
    server_name your-domain.com;  # Replace with your domain or EC2 public IP

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Start Nginx:

```bash
sudo systemctl enable nginx
sudo systemctl start nginx
```

#### Step 8: Configure Firewall (if applicable)

```bash
# For Amazon Linux with firewalld
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload

# For Ubuntu with ufw
sudo ufw allow 5000
sudo ufw allow 80
sudo ufw enable
```

## Usage

1. **Access the portal**: Visit `http://your-ec2-public-ip:5000` (or port 80 if using Nginx)

2. **Connect to your Kubernetes cluster**:
   - Enter your cluster endpoint (e.g., `https://your-cluster-api.amazonaws.com`)
   - Provide cluster name
   - Paste your service account token

3. **Use the tabs to manage resources**:
   - **Deployments**: Create new deployments
   - **Services**: Create various service types
   - **Custom Commands**: Execute kubectl commands
   - **Custom YAML**: Apply your own manifests

## File Structure

```
kubernetes-portal/
├── app.py                 # Main Flask application
├── main.py               # Application entry point
├── templates/
│   └── index.html        # Main web interface
├── static/
│   ├── css/
│   │   └── styles.css    # Custom styling
│   └── js/
│       └── app.js        # Frontend JavaScript
└── scripts/
    └── kubectl_operations.sh  # Shell script utilities
```

## Security Considerations

- Change the default `SESSION_SECRET` environment variable
- Use HTTPS in production (consider Let's Encrypt with Certbot)
- Restrict access using security groups or firewall rules
- Consider using IAM roles for EC2 instances instead of hardcoded credentials
- Regularly update dependencies and the operating system

## Troubleshooting

**Service not starting:**
```bash
sudo journalctl -u k8s-portal -f
```

**Check if kubectl is working:**
```bash
kubectl version --client
```

**Check application logs:**
```bash
sudo systemctl status k8s-portal
```

**Test the application manually:**
```bash
cd ~/kubernetes-portal
python3.11 main.py
```

## Contributing

This portal is built using Python, HTML, CSS, and shell scripting as requested. Feel free to modify and enhance according to your needs.