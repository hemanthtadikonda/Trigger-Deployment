# 🔐 Kubernetes Portal with User Authentication & Audit Logging

## 🚀 What's New

Your Kubernetes Portal now includes:

✅ **User Authentication System**
- Secure login/logout with password hashing
- User registration and session management
- Admin vs regular user privileges

✅ **Comprehensive Audit Logging**
- Track every action: who did what, when, where
- Monitor cluster connections and disconnections
- Log all kubectl commands and YAML applications
- Track failed operations and security events

✅ **Admin Dashboard**
- Real-time activity monitoring
- Advanced filtering and search
- Statistics and success rates
- User activity tracking

✅ **Security Features**
- PostgreSQL database for secure data storage
- Session management with secure secrets
- IP address and user agent tracking
- Failed login attempt monitoring

---

## 📋 Quick Setup (Same 2 Commands!)

The installation is still super simple:

```bash
# 1. Clone your repository
git clone https://github.com/your-username/kubernetes-portal.git
cd kubernetes-portal

# 2. Run the installation script
chmod +x deploy.sh && ./deploy.sh
```

---

## 🔧 First-Time Setup

After installation, you need to create your first admin user:

### Option 1: Interactive Setup (Recommended)
```bash
cd ~/kubernetes-portal
python3 setup_admin.py
```

This will give you a menu to:
- Create your first admin user
- Promote existing users to admin
- List all users

### Option 2: Manual Database Setup
```bash
cd ~/kubernetes-portal
python3 -c "
from app import app, db
from models import init_models
from werkzeug.security import generate_password_hash
from datetime import datetime

User, AuditLog, ClusterConnection = init_models(db)

with app.app_context():
    admin = User(
        username='admin',
        email='admin@example.com',
        password_hash=generate_password_hash('admin123'),
        is_admin=True,
        created_at=datetime.utcnow()
    )
    db.session.add(admin)
    db.session.commit()
    print('Admin user created: admin/admin123')
"
```

---

## 🎯 Using the Portal

### Login Process
1. Open `http://your-ec2-ip:5000`
2. Click "Register" to create an account (or use admin credentials)
3. Login with your credentials
4. Connect to your Kubernetes cluster
5. Start managing deployments!

### Admin Features
If you're an admin user, you'll see:
- **"Audit Dashboard"** button in the header
- **"Admin"** badge next to your username

### Audit Dashboard
Access comprehensive logging at `http://your-ec2-ip:5000/audit`

**What You Can Track:**
- User logins/logouts and failed attempts
- Cluster connections and disconnections
- Deployment creations and modifications
- Service creations and configurations
- Custom kubectl command executions
- YAML manifest applications
- All with timestamps, IP addresses, and outcomes

**Filtering Options:**
- Filter by user, action type, cluster name
- Date range filtering
- Status filtering (success/failed)
- Real-time search

---

## 🗄️ Database Information

### Database Tables Created:
- **users**: User accounts and admin status
- **audit_logs**: Complete activity tracking
- **cluster_connections**: Cluster connection history

### What Gets Logged:
```
✅ Authentication events (login/logout/failed attempts)
✅ Cluster operations (connect/disconnect)
✅ Resource management (create/delete deployments, services)
✅ Command execution (custom kubectl commands)
✅ YAML applications (manifest deployments)
✅ Security events (unauthorized access attempts)
```

### Log Details Include:
- **Who**: Username and user ID
- **What**: Action type and resource affected
- **When**: Precise timestamp
- **Where**: IP address and cluster name
- **How**: Exact command executed
- **Result**: Success/failure with output

---

## 🔐 Security Features

### Authentication Security:
- Passwords hashed with Werkzeug's secure methods
- Session management with secure random secrets
- Login attempt monitoring and logging
- User privilege separation (admin vs regular)

### Audit Security:
- Immutable audit log entries
- IP address tracking for all actions
- User agent logging for session tracking
- Failed operation logging for security monitoring

### Database Security:
- PostgreSQL with secure connection strings
- Environment variable-based configuration
- No hardcoded credentials

---

## 📊 Monitoring & Compliance

### For IT Administrators:
- **Compliance**: Meet security audit requirements
- **Monitoring**: Real-time activity tracking
- **Forensics**: Complete audit trail for investigations
- **Reporting**: Export capabilities for compliance reports

### For DevOps Teams:
- **Accountability**: Track who made what changes
- **Debugging**: See exact commands that were run
- **Security**: Monitor for unauthorized access
- **Training**: Review common mistakes and patterns

---

## 🛠️ Advanced Configuration

### Making a User Admin:
```bash
cd ~/kubernetes-portal
python3 setup_admin.py
# Select option 2 to promote existing user
```

### Viewing Audit Logs via CLI:
```bash
# Connect to your database and query audit logs
python3 -c "
from app import app, db
from models import init_models

User, AuditLog, ClusterConnection = init_models(db)

with app.app_context():
    logs = AuditLog.query.order_by(AuditLog.timestamp.desc()).limit(10).all()
    for log in logs:
        print(f'{log.timestamp}: {log.user.username if log.user else \"System\"} - {log.action} on {log.resource_name}')
"
```

### Database Backup:
```bash
# Backup your audit logs and user data
pg_dump $DATABASE_URL > kubernetes_portal_backup.sql
```

---

## 🆘 Troubleshooting

### If Login Doesn't Work:
```bash
# Check if database tables exist
python3 -c "from app import app, db; print(db.engine.table_names())"

# Reset admin password
python3 setup_admin.py
```

### If Audit Logs Aren't Appearing:
```bash
# Check database connectivity
python3 -c "from app import app, db; print('DB Connected:', db.engine.execute('SELECT 1').scalar())"

# Manually add a test log
python3 -c "
from app import app, db
from models import init_models
from datetime import datetime

User, AuditLog, ClusterConnection = init_models(db)

with app.app_context():
    log = AuditLog(user_id=1, action='test', resource_type='test', resource_name='test', 
                   namespace='default', cluster_name='test', status='success', 
                   timestamp=datetime.utcnow())
    db.session.add(log)
    db.session.commit()
    print('Test log added')
"
```

### Performance Issues:
- The portal automatically paginates audit logs (50 per page)
- Use date filters to reduce query load
- Consider archiving old logs for large deployments

---

## 🔮 What's Next?

Your portal now provides enterprise-grade security and monitoring. You can:

1. **Set up regular audit reviews** with your security team
2. **Configure backup procedures** for compliance
3. **Train your team** on the new audit features
4. **Monitor for security patterns** using the dashboard

The audit system captures everything needed for security compliance, forensics, and operational transparency!