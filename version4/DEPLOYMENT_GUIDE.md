# 🚀 Kubernetes Deployment Portal – Production Setup Guide

**This document explains how to deploy a Flask-based Kubernetes Deployment Portal in a production-ready way using:**

* Python + Flask

* PostgreSQL (on separate DB server)

* Gunicorn (Python WSGI server)

* Nginx (reverse proxy + TLS termination)

* systemd (service management)

* Certbot (Let’s Encrypt) (TLS certificates)
---
## 1. Update System Packages
Always keep the system updated for security patches and stability.

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

## 2. Install Dependencies
We need Python, virtual environments, Git (for code), and essential build tools.
```bash
sudo apt-get install -y python3 python3-venv python3-pip git curl build-essential
```
## 3. Install kubectl
The app may trigger Kubernetes deployments, so we install the latest stable `kubectl.`
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```
✅ Best practice: Install kubectl on app server only if the app needs direct Kubernetes API interaction.

---
<!-- ROLLBACK Section -->


<summary><h2>4.Configure PostgreSQL on Separate Server</h2></summary>

<details>
<br/>

On DB server:
```bash
sudo apt install -y postgresql postgresql-contrib
sudo -i -u postgres
psql
```
Create user and database:
```sql
CREATE USER kubeuser WITH PASSWORD 'Password123';
CREATE DATABASE kubeportal OWNER kubeuser;
GRANT ALL PRIVILEGES ON DATABASE kubeportal TO kubeuser;
\q
```
Update configs:
`/etc/postgresql/16/main/postgresql.conf`

```conf
listen_addresses = '*'
```

`/etc/postgresql/16/main/pg_hba.conf`

```conf
hostssl    kubeportal    kubeuser    <App_Server_Private_IP>/32    md5
```
Restart DB:
```bash
sudo systemctl restart postgresql
sudo systemctl enable postgresql
```

### Connect Flask App to PostgreSQL
On app server:
```bash
export DATABASE_URL="postgresql://kubeuser:StrongPassword123@<DB_Server_Private_IP>:5432/kubeportal"
```
---

## Verify Database & User Activity
On DB server:
```bash
sudo -i -u postgres
psql -d kubeportal 
```
Useful queries:
### 1.Check the **users** table — it should contain all registered users:
```sql
SELECT id, username, email, created_at
FROM users
ORDER BY created_at DESC
LIMIT 20;
```

</details>


## 5. Clone Application Repository
Fetch application code from GitHub.
```bash
cd /home/ubuntu
git clone https://github.com/hemanthtadikonda/Trigger-Deployment.git
cd Trigger-Deployment/version4
```
## 6. Set Up Python Virtual Environment
Create and activate a virtual environment to isolate dependencies.
```bash 
python3 -m venv venv
source venv/bin/activate
```
## 7. Install Python Dependencies
requirements.txt contains all necessary libraries.
```bash
pip install -r requirements.txt
```
## 8. Configure Environment Variables
Use strong secrets for session management and secure database connections.
```bash
export SESSION_SECRET="$(openssl rand -hex 32)"
export DATABASE_URL="postgresql://kubeuser:Password123@localhost:5432/kubeportal"
```
✅ Best practice: Store secrets in .env files or a secret manager (AWS Secrets Manager, HashiCorp Vault).

## 9. Initialize Database Schema
Create required tables.
```bash
python3
```
from app import db, app

with app.app_context():
db.create_all()
```
Exit the Python shell:
```bash
exit()
```
Run initial setup (admin user, etc.):
```bash
python3 initial_setup.py
```
## 10. Test Application Locally
```
python3 app.py
```
If it runs successfully, stop it (CTRL+C) and continue with production setup.

## 11. Set Up Gunicorn
Gunicorn will serve the Flask app in production.
```bash
pip install gunicorn
gunicorn --bind 0.0.0.0:5000 app:app
```
Test Gunicorn by visiting `http://your_server_ip:5000`. If it works, stop it (CTRL+C).

---

## 12. Create systemd Service for Gunicorn
Install Nginx:
```bash
sudo apt-get install -y nginx
```
Create site config:
`/etc/nginx/sites-available/kubeportal`
```nginx
server {
    listen 80;
    server_name YOUR_DOMAIN_OR_IP;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/kubeportal /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```
## 13. Create systemd Service
This ensures app auto-starts on reboot and is managed properly.
Create `/etc/systemd/system/kubeportal.service`:
```ini
[Unit]
Description=Kubernetes Deployment Portal Flask App
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/Trigger-Deployment/version4
Environment="DATABASE_URL=postgresql://kubeuser:StrongPassword123@<DB_Server_Private_IP>:5432/kubeportal"
Environment="SESSION_SECRET=your_secret_value"
ExecStart=/home/ubuntu/Trigger-Deployment/version4/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```
Enable & start service:
```bash
sudo systemctl daemon-reload
sudo systemctl start kubeportal
sudo systemctl enable kubeportal
```
✅ Best practice: Run with at least --workers 3 for concurrency.

## 14. Secure with TLS (HTTPS)
Install Certbot:
```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx
```
Certificates auto-renew via systemd timer.

---

