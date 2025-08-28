import os
import subprocess
import json
import logging
from flask import Flask, request, render_template, session, flash, redirect, url_for, jsonify
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
