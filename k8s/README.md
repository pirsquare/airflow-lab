# Kubernetes Deployment - Quick Start Guide

## Prerequisites

- Kubernetes cluster (EKS, GKE, AKS, or local minikube)
- `kubectl` configured
- External PostgreSQL database (RDS, Cloud SQL, Azure Database, etc.)
- External Redis (ElastiCache, Memorystore, Azure Cache, etc.)

## Quick Deploy

### 1. Update Configuration

Edit `airflow-configmap.yaml` and `airflow-secret.yaml`:

```bash
# Set your database and Redis endpoints
# Database format: postgresql://user:password@host:5432/airflow
# Redis format: redis://host:6379/0
```

### 2. Apply Manifests

```bash
# Create namespace and secrets
kubectl apply -f namespace.yaml
kubectl apply -f service-account.yaml
kubectl apply -f rbac.yaml

# Create config and secrets
kubectl apply -f airflow-configmap.yaml
kubectl apply -f airflow-secret.yaml

# Initialize database (runs once)
kubectl apply -f airflow-init-job.yaml

# Wait for init to complete
kubectl wait --for=condition=complete job/airflow-init -n airflow --timeout=300s

# Deploy components
kubectl apply -f webserver-deployment.yaml
kubectl apply -f scheduler-deployment.yaml
kubectl apply -f worker-deployment.yaml
kubectl apply -f triggerer-deployment.yaml
```

### 3. Access WebUI

```bash
# Port-forward to local
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow
```

Open http://localhost:8080

### 4. Scale Workers

```bash
# View HPA status
kubectl get hpa -n airflow

# Manually scale
kubectl scale deployment airflow-worker --replicas=5 -n airflow
```

## Monitoring

```bash
# View logs
kubectl logs deployment/airflow-scheduler -n airflow -f
kubectl logs deployment/airflow-worker -n airflow -f
kubectl logs deployment/airflow-webserver -n airflow -f

# Check pod status
kubectl get pods -n airflow

# Describe pod (for debugging)
kubectl describe pod <pod-name> -n airflow
```

## Cleanup

```bash
kubectl delete namespace airflow
```

## Cloud-Specific Notes

See cloud deployment guides:
- [AWS Setup](../docs/aws.md)
- [GCP Setup](../docs/gcp.md)
- [Azure Setup](../docs/azure.md)
