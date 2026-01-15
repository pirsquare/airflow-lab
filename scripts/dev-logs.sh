#!/bin/bash
# macOS/Linux script to view logs
# Usage: ./scripts/dev-logs.sh [service]
# Service: webserver, scheduler, worker, triggerer, redis, or all (default)

SERVICE=${1:-all}

VALID_SERVICES=("all" "webserver" "scheduler" "worker" "triggerer" "redis")

if [[ ! " ${VALID_SERVICES[@]} " =~ " ${SERVICE} " ]]; then
    echo "ERROR: Invalid service. Choose from: all, webserver, scheduler, worker, triggerer, redis"
    exit 1
fi

echo "Tailing logs..."
echo "(Press Ctrl+C to exit)"
echo ""

if [ "$SERVICE" = "all" ]; then
    docker-compose logs -f --tail=50
else
    docker-compose logs -f --tail=50 "airflow-$SERVICE"
fi
