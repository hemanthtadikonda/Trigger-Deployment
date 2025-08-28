# Kubernetes Deployment Portal

## Overview

This is a web-based Kubernetes cluster management portal built with Flask. The application provides a user-friendly interface for connecting to Kubernetes clusters, executing kubectl commands, and managing deployments through a web interface. It serves as a bridge between users and Kubernetes clusters, abstracting away complex command-line operations into an intuitive web portal.

## User Preferences

Preferred communication style: Simple, everyday language.
Technology stack preference: Python, HTML, CSS, and shell scripting only.

## Recent Changes

**August 28, 2025**
- Added "Execute Custom YAML" tab alongside the existing "Custom Commands" tab
- Users can now apply their own YAML manifests directly to the cluster
- Added YAML template buttons for common Kubernetes resources (Pod, Deployment, Service, ConfigMap, Secret)
- Enhanced the interface with monospace font styling for YAML editing
- Implemented proper timeout handling for YAML application commands

## System Architecture

### Frontend Architecture
The frontend uses a traditional server-rendered approach with Flask templates and Bootstrap for styling. The UI is built with:
- **Template Engine**: Jinja2 templates for server-side rendering
- **CSS Framework**: Bootstrap with dark theme for responsive design
- **JavaScript**: Vanilla JavaScript for client-side interactions and form validation
- **Icons**: Font Awesome for consistent iconography

### Backend Architecture
The backend follows a simple Flask application pattern:
- **Web Framework**: Flask with ProxyFix middleware for handling reverse proxy headers
- **Session Management**: Flask sessions with configurable secret key
- **Command Execution**: Direct subprocess calls to kubectl for Kubernetes operations
- **Logging**: Python's built-in logging module for debugging and monitoring

### Authentication & Authorization
The application uses a token-based approach for Kubernetes cluster authentication:
- **Cluster Connection**: Users provide cluster endpoint and authentication token
- **Context Management**: kubectl contexts are managed for different cluster connections
- **Session Persistence**: Connection status is maintained in Flask sessions

### Security Considerations
- **TLS Verification**: Configured to skip TLS verification for development/internal clusters
- **Token Handling**: Bearer tokens are used for cluster authentication
- **Session Security**: Configurable session secret key via environment variables

### Command Interface
The application provides two main interaction patterns:
- **Quick Commands**: Pre-defined kubectl commands accessible via buttons
- **Custom Commands**: Free-form kubectl command execution through text input
- **Real-time Feedback**: Command output is displayed immediately to users

## External Dependencies

### Core Dependencies
- **Flask**: Python web framework for the main application
- **Werkzeug**: WSGI utilities including ProxyFix middleware
- **kubectl**: Kubernetes command-line tool (must be installed on the host system)

### Frontend Dependencies
- **Bootstrap**: CSS framework loaded via CDN for responsive UI components
- **Font Awesome**: Icon library loaded via CDN for consistent iconography

### System Requirements
- **Python 3.x**: Runtime environment for the Flask application
- **kubectl**: Must be pre-installed and accessible in the system PATH
- **Kubernetes Cluster**: Target cluster with API endpoint and valid authentication token

### Environment Configuration
- **SESSION_SECRET**: Environment variable for Flask session encryption (falls back to default)
- **Host Configuration**: Application runs on all interfaces (0.0.0.0) port 5000 by default