# Multi-Cloud Airflow Deployment Overview

This document outlines the recommended architecture for deploying Airflow on AWS, Google Cloud Platform (GCP), and Microsoft Azure.

## Common Architecture

All clouds follow the same logical architecture:

```
┌──────────────────────────────────────────────────────┐
│ Kubernetes Cluster (or EC2/Compute instances)         │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌─────────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  Webserver  │  │Scheduler │  │  Triggerer   │  │
│  │   (1 pod)   │  │ (1 pod)  │  │   (1 pod)    │  │
│  └─────────────┘  └──────────┘  └──────────────┘  │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │    Celery Workers (scaled horizontally)      │    │
│  │  ┌────────────┐ ┌────────────┐ ...          │    │
│  │  │  Worker 1  │ │  Worker 2  │              │    │
│  │  └────────────┘ └────────────┘              │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
└──────────────────────────────────────────────────────┘
           │                           │
           │                           │
    ┌──────▼────────┐          ┌──────▼─────────┐
    │  PostgreSQL   │          │     Redis      │
    │  (RDS/SQL)    │          │  (Cache/      │
    │  (managed)    │          │   Memorystore) │
    └───────────────┘          │   (managed)    │
                               └────────────────┘
           │
    ┌──────▼──────────┐
    │  Cloud Storage  │
    │  (Logs/DAGs)    │
    │  (S3/GCS/Blob)  │
    └─────────────────┘
```

## Key Principles

### 1. Use Managed Services
- **Database**: Use cloud-provided PostgreSQL (RDS, Cloud SQL, Azure Database)
- **Cache/Broker**: Use cloud-provided Redis (ElastiCache, Memorystore, Azure Cache for Redis)
- **Storage**: Use cloud object storage for logs and DAG backups

### 2. Stateless Components
- Webserver, Scheduler, Workers should be stateless and horizontally scalable
- Use Kubernetes for easy scaling and self-healing

### 3. Security
- Use cloud secret managers (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault)
- Connections/variables stored in database; encrypt with Fernet key
- Network policies to limit access between components

### 4. Monitoring & Logging
- Use cloud-native monitoring (CloudWatch, Stackdriver, Azure Monitor)
- Send Airflow logs to cloud storage for long-term retention
- Set up alerts for failed DAGs and unhealthy components

---

## Configuration for Each Cloud

### Environment Variables

All Airflow configuration is done via environment variables (no `airflow.cfg`).

**Essential for all clouds**:
```bash
AIRFLOW__CORE__EXECUTOR=CeleryExecutor
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql://user:password@db-host:5432/airflow
AIRFLOW__CELERY__BROKER_URL=redis://redis-host:6379/0
AIRFLOW__CELERY__RESULT_BACKEND=redis://redis-host:6379/1
AIRFLOW__CORE__FERNET_KEY=<generated-key>
AIRFLOW__WEBSERVER__SECRET_KEY=<generated-key>
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=False
AIRFLOW__WEBSERVER__EXPOSE_CONFIG=False
AIRFLOW__LOGGING__REMOTE_LOGGING=True
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER=<cloud-storage-path>
```

**Cloud-specific**: See [AWS](aws.md), [GCP](gcp.md), [Azure](azure.md) docs.

### Kubernetes Secrets & ConfigMaps

Kubernetes manifests provided in [k8s/](../k8s/) folder:
- `airflow-configmap.yaml`: Non-sensitive config
- `airflow-secret.yaml`: Sensitive credentials (fill from Secret Manager)

Example usage in deployment:
```yaml
containers:
  - name: airflow-webserver
    env:
    - name: AIRFLOW__CORE__FERNET_KEY
      valueFrom:
        secretKeyRef:
          name: airflow-secrets
          key: fernet-key
    - name: AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
      valueFrom:
        secretKeyRef:
          name: airflow-secrets
          key: sql-alchemy-conn
```

---

## Deployment Steps (Common)

### 1. Create Cloud Resources

1. **Managed Database** (PostgreSQL)
   - Choose high-availability option
   - Create database `airflow`
   - Create user with permissions for `airflow` DB

2. **Managed Redis**
   - Single node or cluster (depending on scale)
   - Enable persistence
   - Record endpoint

3. **Cloud Storage** (for logs)
   - Create bucket/container
   - Enable versioning (optional)
   - Record path

### 2. Generate Secrets

```bash
# Generate Fernet key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Generate webserver secret
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Store in cloud Secret Manager.

### 3. Deploy to Kubernetes

(See cloud-specific docs)

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/airflow-secret.yaml
kubectl apply -f k8s/airflow-configmap.yaml
kubectl apply -f k8s/webserver-deployment.yaml
kubectl apply -f k8s/scheduler-deployment.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/triggerer-deployment.yaml
```

### 4. Initialize Database

```bash
kubectl exec -it deployment/airflow-webserver -c webserver -- \
  airflow db migrate
kubectl exec -it deployment/airflow-webserver -c webserver -- \
  airflow users create --username admin --password admin --role Admin --email admin@example.com
```

### 5. Access WebUI

- Port-forward: `kubectl port-forward svc/airflow-webserver 8080:8080`
- Or create Ingress (see cloud docs)

---

## Scaling Workers

Kubernetes HPA (Horizontal Pod Autoscaler) can scale workers based on queue depth:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: airflow-worker-hpa
  namespace: airflow
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: airflow-worker
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

## Monitoring & Logging

### Airflow Logs

Configure remote logging in environment:

```bash
AIRFLOW__LOGGING__REMOTE_LOGGING=True
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER=s3://my-bucket/airflow-logs  # AWS
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER=gs://my-bucket/airflow-logs  # GCP
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER=wasbs://container@account.blob.core.windows.net/logs  # Azure
```

Logs automatically pushed to cloud storage after task execution.

### Monitoring Dashboards

- **AWS**: CloudWatch → Dashboards
- **GCP**: Cloud Monitoring (Stackdriver)
- **Azure**: Azure Monitor

Create custom dashboards to track:
- Task success/failure rates
- DAG run duration
- Worker CPU/memory
- Database connections
- Redis memory usage

### Alerting

Set up alerts for:
- DAG failures (SNS, Pub/Sub, Event Hub)
- SLA misses (built-in Airflow SLA feature)
- Database connection failures
- Worker pod crashes

---

## Troubleshooting

### DAGs Not Loading
- Check scheduler pod logs: `kubectl logs deployment/airflow-scheduler`
- Verify DAG storage mount is correct
- Ensure DAG files have no syntax errors

### Tasks Failing
- Check worker logs: `kubectl logs deployment/airflow-worker`
- Verify database connectivity
- Verify Redis connectivity

### Webserver Unreachable
- Check webserver pod status: `kubectl get pods -l app=airflow-webserver`
- Check service: `kubectl get svc airflow-webserver`
- View webserver logs

### Database Lock
- Increase `max_connections` in managed database
- Scale up webserver/scheduler connections
- Monitor connection pool

---

## Next Steps

- [AWS-specific setup](aws.md)
- [GCP-specific setup](gcp.md)
- [Azure-specific setup](azure.md)
- [Kubernetes manifests](../k8s/)

---

## References

- [Airflow Production Guide](https://airflow.apache.org/docs/apache-airflow/stable/production-deployment.html)
- [CeleryExecutor Configuration](https://airflow.apache.org/docs/apache-airflow/stable/executor/celery.html)
- [Airflow Security & Secrets](https://airflow.apache.org/docs/apache-airflow/stable/security/)
