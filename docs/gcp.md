# Google Cloud Platform (GCP) Deployment Guide

Deploy Apache Airflow on GCP using managed services and Google Kubernetes Engine (GKE).

## Recommended Services

| Component | GCP Service | Notes |
|-----------|-------------|-------|
| Kubernetes | GKE | Managed Kubernetes |
| Metadata DB | Cloud SQL (PostgreSQL) | Highly available |
| Message Broker | Memorystore for Redis | Automated failover |
| Logs Storage | Cloud Storage (GCS) | With lifecycle rules |
| Secrets | Secret Manager | IAM-integrated |
| Monitoring | Cloud Monitoring (Stackdriver) | Logs, metrics, alerting |
| Load Balancer | Cloud Load Balancing | HTTP(S) LB |

## Setup Steps

### 1. Create GCP Resources

#### Cloud SQL PostgreSQL

```bash
gcloud sql instances create airflow-db \
  --database-version POSTGRES_15 \
  --tier db-f1-micro \
  --region us-central1 \
  --availability-type REGIONAL

# Create database
gcloud sql databases create airflow --instance=airflow-db

# Create user
gcloud sql users create airflow --instance=airflow-db \
  --password=<strong-password>
```

Record the instance connection name: `PROJECT:REGION:INSTANCE`.

#### Memorystore for Redis

```bash
gcloud redis instances create airflow-redis \
  --size=1 \
  --region=us-central1 \
  --redis-version=7.0
```

Record the IP address.

#### Cloud Storage Bucket for Logs

```bash
gsutil mb -b on gs://airflow-logs-$(date +%s)

# Enable versioning
gsutil versioning set on gs://airflow-logs-xxxx

# Set lifecycle policy (delete after 90 days)
cat > lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF

gsutil lifecycle set lifecycle.json gs://airflow-logs-xxxx
```

#### GKE Cluster

```bash
gcloud container clusters create airflow-cluster \
  --region us-central1 \
  --num-nodes 3 \
  --machine-type n1-standard-1 \
  --enable-autoscaling \
  --min-nodes 2 \
  --max-nodes 10

# Get credentials
gcloud container clusters get-credentials airflow-cluster --region us-central1
```

### 2. Create Service Accounts

Create a Kubernetes service account with GCP permissions:

```bash
# Create GCP service account
gcloud iam service-accounts create airflow-sa \
  --display-name="Airflow Service Account"

# Grant permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:airflow-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/storage.objectViewer

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:airflow-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/storage.objectCreator

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:airflow-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor

# Create key
gcloud iam service-accounts keys create key.json \
  --iam-account=airflow-sa@PROJECT_ID.iam.gserviceaccount.com
```

### 3. Create Secrets in Secret Manager

```bash
# Store database connection string
gcloud secrets create airflow-db-connection \
  --replication-policy="automatic" \
  --data-file=- <<< "postgresql://airflow:password@127.0.0.1:5432/airflow"

# Store Fernet key
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
gcloud secrets create airflow-fernet-key \
  --replication-policy="automatic" \
  --data-file=- <<< "$FERNET_KEY"

# Store webserver secret key
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
gcloud secrets create airflow-webserver-secret-key \
  --replication-policy="automatic" \
  --data-file=- <<< "$SECRET_KEY"

# Grant service account access
gcloud secrets add-iam-policy-binding airflow-db-connection \
  --member=serviceAccount:airflow-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
```

### 4. Set Up Cloud SQL Proxy

Cloud SQL proxy allows pods to connect to Cloud SQL securely:

```bash
# Add sidecar to deployments (see Kubernetes manifests)
# Each deployment pod includes a Cloud SQL proxy container
```

Connection string (via proxy):
```
postgresql://airflow:password@127.0.0.1:5432/airflow
```

### 5. Deploy to GKE

Update Kubernetes manifests with GCP endpoints:

```bash
# Edit k8s/airflow-configmap.yaml with Cloud SQL & Memorystore endpoints
# Edit k8s/airflow-secret.yaml with values from Secret Manager
```

Deploy:
```bash
kubectl apply -f k8s/
```

### 6. Configure Remote Logging

Update `k8s/airflow-configmap.yaml`:

```yaml
AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "gs://airflow-logs-xxxx/airflow-logs"
AIRFLOW__LOGGING__GOOGLE_KEY_PATH: "/var/secrets/airflow-sa/key.json"
```

Mount service account key in deployment:
```yaml
volumes:
  - name: airflow-sa-key
    secret:
      secretName: airflow-sa-key
```

### 7. Set Up Load Balancer

Create an Ingress for the webserver:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: airflow-webserver-ingress
  namespace: airflow
spec:
  rules:
  - host: airflow.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: airflow-webserver
            port:
              number: 8080
```

Apply and get external IP:
```bash
kubectl apply -f ingress.yaml
kubectl get ingress -n airflow
```

### 8. Configure Cloud Monitoring

```bash
# Create log sink (automatic with provided manifests)
gcloud logging sinks create airflow-logs \
  logging.googleapis.com/projects/PROJECT_ID/logs/airflow \
  --log-filter='resource.type="k8s_container" AND resource.labels.namespace_name="airflow"'
```

---

## Scaling

### Auto-scale Workers

Deploy HPA (Horizontal Pod Autoscaler):

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
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Scale Cloud SQL

Increase CPU/memory:

```bash
gcloud sql instances patch airflow-db \
  --tier=db-n1-standard-1
```

---

## Cost Optimization

1. **Use Preemptible VMs** for worker nodes (fault-tolerant):
   ```bash
   gcloud container node-pools create preemptible-pool \
     --cluster=airflow-cluster \
     --preemptible \
     --num-nodes=3
   ```

2. **Enable Workload Identity** (instead of service account keys):
   ```bash
   gcloud container clusters update airflow-cluster \
     --workload-pool=PROJECT_ID.svc.id.goog
   ```

3. **Scale Down Off-Hours** (via Cloud Scheduler):
   - Create Cloud Function to scale deployments
   - Schedule via Cloud Scheduler

4. **Use Committed Use Discounts** for persistent components.

---

## Backup & Disaster Recovery

### Cloud SQL Backups

Automated daily backups:

```bash
gcloud sql instances patch airflow-db \
  --backup-start-time 03:00 \
  --retained-backups-count 7
```

### Cloud Storage Backups

Versioning enabled (see setup). For extra safety:

```bash
# Enable Cross-Region Replication
gsutil rsync -d -r gs://airflow-logs-primary/ gs://airflow-logs-backup/
```

### DAG Backups

Store DAGs in Cloud Source Repositories or GitHub, pull via CI/CD.

---

## Troubleshooting

### Can't Connect to Cloud SQL

1. Verify Cloud SQL proxy sidecar is running: `kubectl logs deployment/airflow-webserver -c cloud-sql-proxy`
2. Check Cloud SQL instance is running: `gcloud sql instances describe airflow-db`
3. Verify firewall allows connection (should be automatic with proxy)

### Can't Access Cloud Storage (Logs)

1. Verify service account has `roles/storage.objectCreator`
2. Check bucket path in AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER
3. Check service account key is mounted correctly

### Pod Evicted

Increase node pool size or set resource limits.

---

## References

- [Cloud SQL PostgreSQL](https://cloud.google.com/sql/docs/postgres)
- [Memorystore for Redis](https://cloud.google.com/memorystore/docs/redis)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Airflow Google Cloud Operators](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/)
