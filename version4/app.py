import os
import subprocess
import json
import logging
from datetime import datetime
from flask import Flask, request, render_template, session, flash, redirect, url_for, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.middleware.proxy_fix import ProxyFix
from sqlalchemy.orm import DeclarativeBase

# Configure logging
logging.basicConfig(level=logging.DEBUG)

class Base(DeclarativeBase):
    pass

app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "kubernetes-deployment-portal-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

# Database configuration
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL")
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_recycle": 300,
    "pool_pre_ping": True,
}

# Initialize database
db = SQLAlchemy(app, model_class=Base)

# Initialize login manager
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# Import and initialize models after db initialization
from models import init_models
User, AuditLog, ClusterConnection = init_models(db)

# Create tables
with app.app_context():
    db.create_all()

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

def log_audit_action(action, resource_type, resource_name, namespace, cluster_name, command, status, output):
    """Log user actions for audit trail"""
    if current_user.is_authenticated:
        audit_log = AuditLog(
            user_id=current_user.id,
            action=action,
            resource_type=resource_type,
            resource_name=resource_name,
            namespace=namespace,
            cluster_name=cluster_name,
            command=command,
            status=status,
            output=output,
            ip_address=request.remote_addr,
            user_agent=request.headers.get('User-Agent', ''),
            timestamp=datetime.utcnow()
        )
        db.session.add(audit_log)
        db.session.commit()
        logging.info(f"Audit log: {current_user.username} performed {action} on {resource_type}/{resource_name}")

def get_client_ip():
    """Get the real client IP address"""
    if request.headers.getlist("X-Forwarded-For"):
        return request.headers.getlist("X-Forwarded-For")[0]
    else:
        return request.remote_addr

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

# Authentication routes
@app.route('/login', methods=['GET', 'POST'])
def login():
    """User login"""
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        user = User.query.filter_by(username=username).first()
        
        if user and check_password_hash(user.password_hash, password):
            login_user(user)
            user.last_login = datetime.utcnow()
            db.session.commit()
            
            # Log successful login
            log_audit_action('login', 'authentication', 'user_session', 'system', 'system', 
                           f'User {username} logged in', 'success', 'Login successful')
            
            flash(f'Welcome back, {user.username}!', 'success')
            return redirect(url_for('index'))
        else:
            # Log failed login attempt
            audit_log = AuditLog(
                user_id=None,
                action='login_failed',
                resource_type='authentication',
                resource_name='user_session',
                namespace='system',
                cluster_name='system',
                command=f'Failed login attempt for username: {username}',
                status='failed',
                output='Invalid username or password',
                ip_address=get_client_ip(),
                user_agent=request.headers.get('User-Agent', ''),
                timestamp=datetime.utcnow()
            )
            db.session.add(audit_log)
            db.session.commit()
            
            flash('Invalid username or password', 'error')
    
    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    """User registration"""
    if request.method == 'POST':
        username = request.form.get('username')
        email = request.form.get('email')
        password = request.form.get('password')
        
        # Check if user already exists
        if User.query.filter_by(username=username).first():
            flash('Username already exists', 'error')
            return render_template('register.html')
        
        if User.query.filter_by(email=email).first():
            flash('Email already registered', 'error')
            return render_template('register.html')
        
        # Create new user
        user = User(
            username=username,
            email=email,
            password_hash=generate_password_hash(password),
            is_admin=False  # First user should be manually set as admin
        )
        
        db.session.add(user)
        db.session.commit()
        
        # Log user registration
        audit_log = AuditLog(
            user_id=user.id,
            action='register',
            resource_type='authentication',
            resource_name='user_account',
            namespace='system',
            cluster_name='system',
            command=f'User {username} registered',
            status='success',
            output='User account created successfully',
            ip_address=get_client_ip(),
            user_agent=request.headers.get('User-Agent', ''),
            timestamp=datetime.utcnow()
        )
        db.session.add(audit_log)
        db.session.commit()
        
        flash('Registration successful! Please login.', 'success')
        return redirect(url_for('login'))
    
    return render_template('register.html')

@app.route('/logout')
@login_required
def logout():
    """User logout"""
    # Log logout
    log_audit_action('logout', 'authentication', 'user_session', 'system', 'system', 
                   f'User {current_user.username} logged out', 'success', 'Logout successful')
    
    logout_user()
    flash('You have been logged out', 'info')
    return redirect(url_for('login'))

@app.route('/')
@login_required
def index():
    """Main page with tabbed interface"""
    return render_template('index.html')

@app.route('/audit')
@login_required
def audit_dashboard():
    """Audit dashboard showing user activity logs"""
    if not current_user.is_admin:
        flash('Access denied. Admin privileges required.', 'error')
        return redirect(url_for('index'))
    
    # Get filter parameters
    user_filter = request.args.get('user', '')
    action_filter = request.args.get('action', '')
    cluster_filter = request.args.get('cluster', '')
    start_date = request.args.get('start_date', '')
    end_date = request.args.get('end_date', '')
    
    # Build query
    query = AuditLog.query
    
    if user_filter:
        query = query.join(User).filter(User.username.contains(user_filter))
    if action_filter:
        query = query.filter(AuditLog.action.contains(action_filter))
    if cluster_filter:
        query = query.filter(AuditLog.cluster_name.contains(cluster_filter))
    if start_date:
        try:
            start_dt = datetime.strptime(start_date, '%Y-%m-%d')
            query = query.filter(AuditLog.timestamp >= start_dt)
        except ValueError:
            pass
    if end_date:
        try:
            end_dt = datetime.strptime(end_date, '%Y-%m-%d')
            query = query.filter(AuditLog.timestamp <= end_dt)
        except ValueError:
            pass
    
    # Get paginated results
    page = request.args.get('page', 1, type=int)
    per_page = 50
    audit_logs = query.order_by(AuditLog.timestamp.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    
    # Get summary statistics
    total_actions = AuditLog.query.count()
    failed_actions = AuditLog.query.filter_by(status='failed').count()
    unique_users = db.session.query(AuditLog.user_id).distinct().count()
    unique_clusters = db.session.query(AuditLog.cluster_name).distinct().count()
    
    stats = {
        'total_actions': total_actions,
        'failed_actions': failed_actions,
        'success_rate': round(((total_actions - failed_actions) / total_actions * 100) if total_actions > 0 else 0, 1),
        'unique_users': unique_users,
        'unique_clusters': unique_clusters
    }
    
    return render_template('audit.html', 
                         audit_logs=audit_logs, 
                         stats=stats,
                         user_filter=user_filter,
                         action_filter=action_filter,
                         cluster_filter=cluster_filter,
                         start_date=start_date,
                         end_date=end_date)

@app.route('/connect_cluster', methods=['POST'])
@login_required
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
        
        # Save cluster connection for user
        cluster_conn = ClusterConnection(
            user_id=current_user.id,
            cluster_name=cluster_name,
            cluster_endpoint=endpoint,
            last_used=datetime.utcnow()
        )
        db.session.add(cluster_conn)
        db.session.commit()
        
        # Log successful connection
        log_audit_action('connect_cluster', 'cluster', cluster_name, 'system', cluster_name, 
                       f'Connected to cluster {cluster_name} at {endpoint}', 'success', output)
        
        flash(f'Successfully connected to cluster: {cluster_name}', 'success')
    else:
        # Log failed connection
        log_audit_action('connect_cluster', 'cluster', cluster_name, 'system', cluster_name, 
                       f'Failed to connect to cluster {cluster_name} at {endpoint}', 'failed', output)
        
        flash(f'Failed to connect to cluster: {output}', 'error')
    
    return redirect(url_for('index'))

@app.route('/disconnect_cluster', methods=['POST'])
@login_required
def disconnect_cluster():
    """Disconnect from cluster"""
    cluster_name = session.get('cluster_name', 'unknown')
    
    # Log disconnection
    log_audit_action('disconnect_cluster', 'cluster', cluster_name, 'system', cluster_name, 
                   f'Disconnected from cluster {cluster_name}', 'success', 'Cluster disconnected')
    
    session.pop('cluster_connected', None)
    session.pop('cluster_endpoint', None)
    session.pop('cluster_name', None)
    session.pop('cluster_token', None)
    flash('Disconnected from cluster', 'info')
    return redirect(url_for('index'))

@app.route('/create_deployment', methods=['POST'])
@login_required
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
            # Log successful deployment creation
            log_audit_action('create_deployment', 'deployment', name, namespace, 
                           session.get('cluster_name', 'unknown'), 
                           f'kubectl apply deployment {name}', 'success', stdout)
            
            flash(f'Deployment {name} created successfully', 'success')
            session['last_output'] = stdout
        else:
            # Log failed deployment creation
            log_audit_action('create_deployment', 'deployment', name, namespace, 
                           session.get('cluster_name', 'unknown'), 
                           f'kubectl apply deployment {name}', 'failed', stderr)
            
            flash(f'Failed to create deployment: {stderr}', 'error')
            session['last_output'] = stderr
            
    except Exception as e:
        # Log exception
        log_audit_action('create_deployment', 'deployment', name, namespace, 
                       session.get('cluster_name', 'unknown'), 
                       f'kubectl apply deployment {name}', 'failed', str(e))
        
        flash(f'Error creating deployment: {str(e)}', 'error')
        session['last_output'] = str(e)
    
    return redirect(url_for('index'))

@app.route('/create_service', methods=['POST'])
@login_required
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
@login_required
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
            # Log successful command execution
            log_audit_action('execute_custom', 'command', 'custom_kubectl', 'system', 
                           session.get('cluster_name', 'unknown'), command, 'success', output)
            
            flash('Custom command executed successfully', 'success')
            session['last_output'] = output
        else:
            # Log failed command execution
            log_audit_action('execute_custom', 'command', 'custom_kubectl', 'system', 
                           session.get('cluster_name', 'unknown'), command, 'failed', output)
            
            flash(f'Command failed: {output}', 'error')
            session['last_output'] = output
            
    except Exception as e:
        # Log exception
        log_audit_action('execute_custom', 'command', 'custom_kubectl', 'system', 
                       session.get('cluster_name', 'unknown'), command, 'failed', str(e))
        
        flash(f'Error executing command: {str(e)}', 'error')
        session['last_output'] = str(e)
    
    return redirect(url_for('index'))

@app.route('/execute_yaml', methods=['POST'])
@login_required
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
                # Log successful YAML application
                log_audit_action('execute_yaml', 'manifest', 'custom_yaml', 
                               namespace_override or 'default', 
                               session.get('cluster_name', 'unknown'), 
                               'kubectl apply -f -', 'success', stdout)
                
                flash('YAML manifest applied successfully', 'success')
                session['last_output'] = stdout
            else:
                # Log failed YAML application
                log_audit_action('execute_yaml', 'manifest', 'custom_yaml', 
                               namespace_override or 'default', 
                               session.get('cluster_name', 'unknown'), 
                               'kubectl apply -f -', 'failed', stderr)
                
                flash(f'Failed to apply YAML manifest: {stderr}', 'error')
                session['last_output'] = stderr
                
        except subprocess.TimeoutExpired:
            process.kill()
            # Log timeout
            log_audit_action('execute_yaml', 'manifest', 'custom_yaml', 
                           namespace_override or 'default', 
                           session.get('cluster_name', 'unknown'), 
                           'kubectl apply -f -', 'failed', 'Command timed out')
            
            flash('YAML application timed out after 60 seconds', 'error')
            session['last_output'] = 'Command timed out'
    except Exception as e:
        # Log exception
        log_audit_action('execute_yaml', 'manifest', 'custom_yaml', 
                       namespace_override or 'default', 
                       session.get('cluster_name', 'unknown'), 
                       'kubectl apply -f -', 'failed', str(e))
        
        flash(f'Error applying YAML manifest: {str(e)}', 'error')
        session['last_output'] = str(e)
    
    return redirect(url_for('index'))

@app.route('/get_resources', methods=['POST'])
def get_resources():
    """Get Kubernetes resources"""
    if not session.get('cluster_connected'):
        return jsonify({'error': 'Not connected to cluster'}), 400
    
    resource_type = request.form.get('resource_type', 'pods')
    namespace = request.form.get('namespace', 'default')
    
    try:
        cmd = ['kubectl', 'get', resource_type, '-n', namespace, '-o', 'json']
        success, output = execute_kubectl_command(cmd)
        
        if success:
            return jsonify({'success': True, 'data': output})
        else:
            return jsonify({'error': output}), 400
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
