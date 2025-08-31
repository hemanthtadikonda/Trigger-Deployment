# Kubernetes Deployment Portal

## Overview

This is a web-based Kubernetes cluster management portal built with Flask. The application provides a user-friendly interface for connecting to Kubernetes clusters, executing kubectl commands, and managing deployments through a web interface. It serves as a bridge between users and Kubernetes clusters, abstracting away complex command-line operations into an intuitive web portal.

## User Preferences

Preferred communication style: Simple, everyday language.
Technology stack preference: Python, HTML, CSS, and shell scripting only.

## Recent Changes

**August 31, 2025 - Major Security & Audit Update**
- **Added User Authentication System**: Secure login/registration with password hashing
- **Implemented Comprehensive Audit Logging**: Track all user actions with PostgreSQL database
- **Created Admin Dashboard**: Real-time monitoring with filtering and statistics
- **Enhanced Security**: Session management, IP tracking, failed login monitoring
- **Added User Management**: Admin vs regular user privileges, user promotion capabilities
- **Database Integration**: PostgreSQL with audit_logs, users, and cluster_connections tables

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
The backend follows a Flask application pattern with comprehensive security:
- **Web Framework**: Flask with ProxyFix middleware for handling reverse proxy headers
- **Authentication**: Flask-Login with password hashing and session management
- **Database**: PostgreSQL with SQLAlchemy ORM for secure data persistence
- **Audit System**: Comprehensive logging of all user actions and system events
- **Command Execution**: Direct subprocess calls to kubectl for Kubernetes operations
- **Session Management**: Secure session handling with environment-based secrets

### Authentication & Authorization
The application implements multi-layered authentication:
- **User Authentication**: Secure login system with password hashing using Werkzeug
- **Session Management**: Flask-Login for user session handling and protection
- **Authorization Levels**: Admin vs regular user privileges with role-based access
- **Cluster Authentication**: Token-based Kubernetes cluster connections
- **Context Management**: kubectl contexts are managed for different cluster connections
- **Audit Logging**: Complete tracking of authentication events and user actions

### Security Considerations
- **Password Security**: Secure password hashing with Werkzeug's generate_password_hash
- **Session Security**: Environment-based session secrets with secure random generation
- **Audit Trail**: Immutable audit logs with IP address and user agent tracking
- **Authentication Monitoring**: Failed login attempt logging and security event tracking
- **Database Security**: PostgreSQL with parameterized queries and secure connections
- **TLS Verification**: Configured to skip TLS verification for development/internal clusters
- **Token Handling**: Bearer tokens are used for cluster authentication

### Command Interface
The application provides two main interaction patterns:
- **Quick Commands**: Pre-defined kubectl commands accessible via buttons
- **Custom Commands**: Free-form kubectl command execution through text input
- **Real-time Feedback**: Command output is displayed immediately to users

## External Dependencies

### Core Dependencies
- **Flask**: Python web framework for the main application
- **Flask-Login**: User authentication and session management
- **Flask-SQLAlchemy**: Database ORM for PostgreSQL integration
- **Werkzeug**: WSGI utilities including ProxyFix middleware and password hashing
- **psycopg2-binary**: PostgreSQL database adapter for Python
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
- **DATABASE_URL**: PostgreSQL connection string for audit logging and user management
- **Host Configuration**: Application runs on all interfaces (0.0.0.0) port 5000 by default

### Database Schema
- **users**: User accounts with authentication credentials and admin status
- **audit_logs**: Comprehensive audit trail of all user actions and system events
- **cluster_connections**: History of cluster connections per user