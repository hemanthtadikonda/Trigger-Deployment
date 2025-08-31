// Kubernetes Deployment Portal JavaScript

document.addEventListener('DOMContentLoaded', function() {
    initializeApp();
});

function initializeApp() {
    setupQuickCommands();
    setupFormValidation();
    setupTooltips();
    setupAutoRefresh();
}

function setupQuickCommands() {
    const quickCmdButtons = document.querySelectorAll('.quick-cmd');
    const customCommandInput = document.getElementById('custom_command');
    
    quickCmdButtons.forEach(button => {
        button.addEventListener('click', function() {
            const command = this.getAttribute('data-cmd');
            if (customCommandInput) {
                customCommandInput.value = command;
                customCommandInput.focus();
                
                // Add visual feedback
                this.classList.add('btn-primary');
                this.classList.remove('btn-outline-secondary');
                
                setTimeout(() => {
                    this.classList.remove('btn-primary');
                    this.classList.add('btn-outline-secondary');
                }, 200);
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
                
                // Add visual feedback
                this.classList.add('btn-info');
                this.classList.remove('btn-outline-info');
                
                setTimeout(() => {
                    this.classList.remove('btn-info');
                    this.classList.add('btn-outline-info');
                }, 200);
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
    - containerPort: 80
    resources:
      limits:
        memory: "256Mi"
        cpu: "250m"
      requests:
        memory: "128Mi"
        cpu: "100m"`,
        
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
        - containerPort: 80
        resources:
          limits:
            memory: "256Mi"
            cpu: "250m"
          requests:
            memory: "128Mi"
            cpu: "100m"`,
            
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
    # Application configuration
    app.name=my-app
    app.version=1.0.0
    app.debug=false
  config.yaml: |
    server:
      port: 8080
      host: 0.0.0.0`,
      
        secret: `apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
data:
  # Note: Values must be base64 encoded
  username: bXl1c2Vy  # myuser
  password: bXlwYXNz  # mypass
stringData:
  # Note: Values in stringData are automatically base64 encoded
  api-key: "your-api-key-here"
  database-url: "postgres://user:pass@localhost/db"`
    };
    
    return templates[templateType] || '';
}

function setupFormValidation() {
    const forms = document.querySelectorAll('form');
    
    forms.forEach(form => {
        form.addEventListener('submit', function(event) {
            if (!validateForm(this)) {
                event.preventDefault();
                event.stopPropagation();
            } else {
                showLoading(this);
            }
            
            this.classList.add('was-validated');
        });
    });
}

function validateForm(form) {
    const requiredFields = form.querySelectorAll('[required]');
    let isValid = true;
    
    requiredFields.forEach(field => {
        if (!field.value.trim()) {
            isValid = false;
            field.classList.add('is-invalid');
            showFieldError(field, 'This field is required');
        } else {
            field.classList.remove('is-invalid');
            hideFieldError(field);
        }
    });
    
    // Custom validation for specific fields
    const endpointField = form.querySelector('#endpoint');
    if (endpointField && endpointField.value) {
        if (!isValidUrl(endpointField.value)) {
            isValid = false;
            endpointField.classList.add('is-invalid');
            showFieldError(endpointField, 'Please enter a valid URL');
        }
    }
    
    const portFields = form.querySelectorAll('input[type="number"]');
    portFields.forEach(field => {
        if (field.value && (field.value < 1 || field.value > 65535)) {
            isValid = false;
            field.classList.add('is-invalid');
            showFieldError(field, 'Port must be between 1 and 65535');
        }
    });
    
    const customCommandField = form.querySelector('#custom_command');
    if (customCommandField && customCommandField.value) {
        if (!customCommandField.value.startsWith('kubectl ')) {
            isValid = false;
            customCommandField.classList.add('is-invalid');
            showFieldError(customCommandField, 'Command must start with "kubectl "');
        }
    }
    
    return isValid;
}

function showFieldError(field, message) {
    let errorDiv = field.parentNode.querySelector('.invalid-feedback');
    if (!errorDiv) {
        errorDiv = document.createElement('div');
        errorDiv.className = 'invalid-feedback';
        field.parentNode.appendChild(errorDiv);
    }
    errorDiv.textContent = message;
}

function hideFieldError(field) {
    const errorDiv = field.parentNode.querySelector('.invalid-feedback');
    if (errorDiv) {
        errorDiv.remove();
    }
}

function isValidUrl(string) {
    try {
        new URL(string);
        return true;
    } catch (_) {
        return false;
    }
}

function showLoading(form) {
    const submitButton = form.querySelector('button[type="submit"]');
    if (submitButton) {
        submitButton.disabled = true;
        const originalText = submitButton.innerHTML;
        submitButton.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>Processing...';
        
        // Store original text for restoration
        submitButton.setAttribute('data-original-text', originalText);
    }
    
    form.classList.add('loading');
}

function hideLoading(form) {
    const submitButton = form.querySelector('button[type="submit"]');
    if (submitButton) {
        submitButton.disabled = false;
        const originalText = submitButton.getAttribute('data-original-text');
        if (originalText) {
            submitButton.innerHTML = originalText;
        }
    }
    
    form.classList.remove('loading');
}

function setupTooltips() {
    // Initialize Bootstrap tooltips
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
}

function setupAutoRefresh() {
    // Auto-refresh cluster status every 30 seconds if connected
    const clusterStatus = document.querySelector('.cluster-status .badge');
    if (clusterStatus && clusterStatus.textContent.includes('Connected')) {
        setInterval(checkClusterHealth, 30000);
    }
}

function checkClusterHealth() {
    // This could be expanded to make an AJAX call to check cluster health
    console.log('Checking cluster health...');
}

// Utility functions
function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(function() {
        showNotification('Copied to clipboard', 'success');
    }).catch(function(err) {
        showNotification('Failed to copy to clipboard', 'error');
    });
}

function showNotification(message, type = 'info') {
    const alertContainer = document.querySelector('.alert-container') || document.body;
    const alertDiv = document.createElement('div');
    alertDiv.className = `alert alert-${type === 'error' ? 'danger' : type} alert-dismissible fade show`;
    alertDiv.innerHTML = `
        <i class="fas fa-${type === 'error' ? 'exclamation-circle' : 'info-circle'} me-2"></i>
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    
    alertContainer.appendChild(alertDiv);
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
        if (alertDiv.parentNode) {
            alertDiv.remove();
        }
    }, 5000);
}

// Tab persistence
function saveActiveTab() {
    const activeTab = document.querySelector('.nav-tabs .nav-link.active');
    if (activeTab) {
        localStorage.setItem('activeTab', activeTab.getAttribute('data-bs-target'));
    }
}

function restoreActiveTab() {
    const savedTab = localStorage.getItem('activeTab');
    if (savedTab) {
        const tabButton = document.querySelector(`[data-bs-target="${savedTab}"]`);
        if (tabButton) {
            const tab = new bootstrap.Tab(tabButton);
            tab.show();
        }
    }
}

// Event listeners for tab changes
document.addEventListener('shown.bs.tab', function (event) {
    saveActiveTab();
});

// Restore active tab on page load
document.addEventListener('DOMContentLoaded', function() {
    restoreActiveTab();
});

// Keyboard shortcuts
document.addEventListener('keydown', function(event) {
    // Ctrl/Cmd + Enter to submit forms
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
        const activeForm = document.querySelector('.tab-pane.active form');
        if (activeForm) {
            activeForm.submit();
        }
    }
    
    // Escape to clear forms
    if (event.key === 'Escape') {
        const activeForm = document.querySelector('.tab-pane.active form');
        if (activeForm) {
            activeForm.reset();
            activeForm.classList.remove('was-validated');
        }
    }
});

// Form auto-save to localStorage
function setupAutoSave() {
    const forms = document.querySelectorAll('form');
    
    forms.forEach(form => {
        const formId = form.action.split('/').pop();
        const inputs = form.querySelectorAll('input, select, textarea');
        
        // Load saved values
        inputs.forEach(input => {
            const savedValue = localStorage.getItem(`${formId}_${input.name}`);
            if (savedValue && input.type !== 'password') {
                input.value = savedValue;
            }
        });
        
        // Save values on change
        inputs.forEach(input => {
            input.addEventListener('input', function() {
                if (this.type !== 'password') {
                    localStorage.setItem(`${formId}_${this.name}`, this.value);
                }
            });
        });
    });
}

// Initialize auto-save on page load
document.addEventListener('DOMContentLoaded', function() {
    setupAutoSave();
});
