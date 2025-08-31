from datetime import datetime
from flask_login import UserMixin

def init_models(db):
    """Initialize models with database instance"""
    
    class User(UserMixin, db.Model):
        __tablename__ = 'users'
        
        id = db.Column(db.Integer, primary_key=True)
        username = db.Column(db.String(80), unique=True, nullable=False)
        email = db.Column(db.String(120), unique=True, nullable=False)
        password_hash = db.Column(db.String(256), nullable=False)
        is_admin = db.Column(db.Boolean, default=False)
        created_at = db.Column(db.DateTime, default=datetime.utcnow)
        last_login = db.Column(db.DateTime)
        
        # Relationship to audit logs
        audit_logs = db.relationship('AuditLog', backref='user', lazy=True)
        
        def __repr__(self):
            return f'<User {self.username}>'

    class AuditLog(db.Model):
        __tablename__ = 'audit_logs'
        
        id = db.Column(db.Integer, primary_key=True)
        user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
        action = db.Column(db.String(100), nullable=False)  # create_deployment, delete_pod, etc.
        resource_type = db.Column(db.String(50), nullable=False)  # deployment, service, pod, etc.
        resource_name = db.Column(db.String(200), nullable=False)
        namespace = db.Column(db.String(100), nullable=False, default='default')
        cluster_name = db.Column(db.String(100), nullable=False)
        command = db.Column(db.Text)  # The actual kubectl command executed
        status = db.Column(db.String(20), nullable=False)  # success, failed
        output = db.Column(db.Text)  # Command output or error message
        ip_address = db.Column(db.String(45))  # IPv4 or IPv6 address
        user_agent = db.Column(db.String(500))
        timestamp = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
        
        def __repr__(self):
            return f'<AuditLog {self.user.username}: {self.action} on {self.resource_name}>'

    class ClusterConnection(db.Model):
        __tablename__ = 'cluster_connections'
        
        id = db.Column(db.Integer, primary_key=True)
        user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
        cluster_name = db.Column(db.String(100), nullable=False)
        cluster_endpoint = db.Column(db.String(500), nullable=False)
        created_at = db.Column(db.DateTime, default=datetime.utcnow)
        last_used = db.Column(db.DateTime, default=datetime.utcnow)
        
        def __repr__(self):
            return f'<ClusterConnection {self.cluster_name}>'
    
    return User, AuditLog, ClusterConnection