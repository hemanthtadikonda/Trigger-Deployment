#!/usr/bin/env python3
"""
Setup script to create the first admin user for the Kubernetes Portal
Run this after installing the application to create your first admin account.
"""

import os
import sys
from werkzeug.security import generate_password_hash
from datetime import datetime

# Add the current directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import app, db
from models import init_models

def create_admin_user():
    """Create the first admin user"""
    User, AuditLog, ClusterConnection = init_models(db)
    
    with app.app_context():
        # Check if any admin users exist
        admin_exists = User.query.filter_by(is_admin=True).first()
        if admin_exists:
            print(f"Admin user '{admin_exists.username}' already exists!")
            return
        
        print("Creating first admin user for Kubernetes Portal")
        print("=" * 50)
        
        username = input("Enter admin username: ").strip()
        if not username:
            print("Username cannot be empty!")
            return
        
        # Check if username exists
        if User.query.filter_by(username=username).first():
            print(f"Username '{username}' already exists!")
            return
        
        email = input("Enter admin email: ").strip()
        if not email:
            print("Email cannot be empty!")
            return
        
        # Check if email exists
        if User.query.filter_by(email=email).first():
            print(f"Email '{email}' already exists!")
            return
        
        password = input("Enter admin password: ").strip()
        if len(password) < 6:
            print("Password must be at least 6 characters!")
            return
        
        # Create admin user
        admin_user = User(
            username=username,
            email=email,
            password_hash=generate_password_hash(password),
            is_admin=True,
            created_at=datetime.utcnow()
        )
        
        db.session.add(admin_user)
        db.session.commit()
        
        print(f"\nAdmin user '{username}' created successfully!")
        print("You can now login to the portal with admin privileges.")
        print("\nAdmin features:")
        print("- Access to audit dashboard")
        print("- View all user activities")
        print("- Monitor cluster operations")
        print("- Track security events")

def promote_user_to_admin():
    """Promote an existing user to admin"""
    User, AuditLog, ClusterConnection = init_models(db)
    
    with app.app_context():
        username = input("Enter username to promote to admin: ").strip()
        user = User.query.filter_by(username=username).first()
        
        if not user:
            print(f"User '{username}' not found!")
            return
        
        if user.is_admin:
            print(f"User '{username}' is already an admin!")
            return
        
        user.is_admin = True
        db.session.commit()
        
        print(f"User '{username}' has been promoted to admin!")

def list_users():
    """List all users"""
    User, AuditLog, ClusterConnection = init_models(db)
    
    with app.app_context():
        users = User.query.all()
        if not users:
            print("No users found.")
            return
        
        print("\nCurrent users:")
        print("-" * 50)
        for user in users:
            admin_status = " (Admin)" if user.is_admin else ""
            last_login = user.last_login.strftime('%Y-%m-%d %H:%M') if user.last_login else "Never"
            print(f"Username: {user.username}{admin_status}")
            print(f"Email: {user.email}")
            print(f"Last Login: {last_login}")
            print(f"Created: {user.created_at.strftime('%Y-%m-%d %H:%M')}")
            print("-" * 30)

def main():
    """Main menu"""
    while True:
        print("\nKubernetes Portal - Admin Setup")
        print("=" * 40)
        print("1. Create first admin user")
        print("2. Promote existing user to admin")
        print("3. List all users")
        print("4. Exit")
        
        choice = input("\nSelect option (1-4): ").strip()
        
        if choice == '1':
            create_admin_user()
        elif choice == '2':
            promote_user_to_admin()
        elif choice == '3':
            list_users()
        elif choice == '4':
            print("Goodbye!")
            break
        else:
            print("Invalid choice. Please try again.")

if __name__ == '__main__':
    main()