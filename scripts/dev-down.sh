#!/bin/bash
# macOS/Linux script to stop Airflow
# Usage: ./scripts/dev-down.sh [--remove-volumes]

REMOVE_VOLUMES=false

if [ "$1" = "--remove-volumes" ]; then
    REMOVE_VOLUMES=true
fi

echo "========================================"
echo "Airflow Local Development - Shutdown"
echo "========================================"
echo ""

if [ "$REMOVE_VOLUMES" = true ]; then
    echo "Stopping services and removing volumes..."
    docker-compose down -v
    echo "✓ Services stopped and volumes removed"
else
    echo "Stopping services..."
    docker-compose down
    echo "✓ Services stopped (volumes preserved)"
    echo "  Use --remove-volumes flag to also remove database and logs"
fi

echo ""
