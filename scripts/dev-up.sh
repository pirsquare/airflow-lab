#!/bin/bash
# macOS/Linux setup script for local Airflow development
# Usage: ./scripts/dev-up.sh

set -e

echo "========================================"
echo "Airflow Local Development - Startup"
echo "========================================"
echo ""

# Check Docker
echo "Checking Docker..."
if ! docker ps > /dev/null 2>&1; then
    echo "ERROR: Docker is not running. Please start Docker."
    exit 1
fi

# Check .env file
if [ ! -f ".env" ]; then
    echo ".env file not found. Creating from .env.example..."
    cp .env.example .env
    
    # Generate keys if using placeholders
    echo "Generating security keys..."
    pip install -q cryptography 2>/dev/null || true
    
    FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    
    # Update .env with generated keys (cross-platform)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|your-fernet-key-here|$FERNET_KEY|g" .env
        sed -i '' "s|your-webserver-secret-key-here|$SECRET_KEY|g" .env
    else
        sed -i "s|your-fernet-key-here|$FERNET_KEY|g" .env
        sed -i "s|your-webserver-secret-key-here|$SECRET_KEY|g" .env
    fi
    
    echo "✓ .env created with generated keys"
fi

# Load .env
echo "Loading .env..."
set -a
source .env
set +a

# Start services
echo ""
echo "Starting Docker Compose services..."
docker-compose up -d

# Wait for webserver to be healthy
echo ""
echo "Waiting for Airflow webserver to be ready..."
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "."
    sleep 1
done

echo ""

if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    echo ""
    echo "========================================"
    echo "✓ Airflow is ready!"
    echo "========================================"
    echo ""
    echo "WebUI: http://localhost:8080"
    echo "Username: ${AIRFLOW_ADMIN_USER:-admin}"
    echo "Password: ${AIRFLOW_ADMIN_PASSWORD:-admin}"
    echo ""
    echo "Next steps:"
    echo "  1. Open http://localhost:8080 in your browser"
    echo "  2. Trigger the demo_simple DAG to test"
    echo "  3. Trigger demo_celery_fanout to see Celery distribution"
    echo ""
    echo "Useful commands:"
    echo "  ./scripts/dev-logs.sh                - View logs"
    echo "  ./scripts/dev-down.sh                - Stop services"
    echo "  docker-compose scale airflow-worker=2 - Scale workers"
    echo ""
else
    echo "ERROR: Webserver failed to become healthy after $MAX_ATTEMPTS attempts"
    echo "Run './scripts/dev-logs.sh' to check logs"
    exit 1
fi
