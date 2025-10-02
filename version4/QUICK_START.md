# 🚀 Quick Start - 2 Commands Only!

## Super Simple Deployment

Connect to your EC2 server and run these 2 commands:

```bash
# 1. Clone your repository
git clone https://github.com/your-username/kubernetes-portal.git
cd kubernetes-portal

# 2. Run the installation script
chmod +x deploy.sh && ./deploy.sh
```

**Done!** Your portal is now running at `http://your-ec2-ip:5000`

---

## What the Script Does Automatically

✅ **Installs everything**: Python, kubectl, dependencies  
✅ **Creates all files**: Flask app, HTML, CSS, JavaScript  
✅ **Sets up service**: Auto-start on boot, restart on failure  
✅ **Configures security**: Session secrets, permissions  
✅ **Starts portal**: Ready to use immediately  

---

## Quick Commands After Installation

```bash
# Check if portal is running
sudo systemctl status k8s-portal

# View logs
sudo journalctl -u k8s-portal -f

# Restart portal
sudo systemctl restart k8s-portal
```

---

## Security Group Requirements

Make sure your EC2 allows:
- **Port 22**: SSH access
- **Port 5000**: Portal access

---

## First Time Usage

1. Open `http://your-ec2-public-ip:5000`
2. Enter your Kubernetes cluster details:
   - **Cluster Endpoint**: `https://your-cluster-api.com`
   - **Cluster Name**: `production-cluster`
   - **Service Account Token**: Your cluster token
3. Click "Connect to Cluster"
4. Start managing deployments!

## Need Help?

If something goes wrong:
```bash
# Check installation logs
./deploy.sh

# Check service logs
sudo journalctl -u k8s-portal --no-pager -l

# Test manual start
cd ~/kubernetes-portal
python3 main.py
```