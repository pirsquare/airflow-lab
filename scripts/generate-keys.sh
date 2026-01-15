#!/bin/bash
# Helper script to generate secure keys
# Usage: ./scripts/generate-keys.sh

set -e

echo "Generating Airflow security keys..."
echo ""

# Install cryptography if needed
pip install -q cryptography 2>/dev/null || true

# Generate Fernet key
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

# Generate WebServer secret key
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

echo "=== Generated Keys ===" 
echo "Copy these to .env file:"
echo ""
echo "AIRFLOW__CORE__FERNET_KEY=$FERNET_KEY"
echo "AIRFLOW__WEBSERVER__SECRET_KEY=$SECRET_KEY"
echo ""
