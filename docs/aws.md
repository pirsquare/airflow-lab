# AWS Deployment Guide

Deploy Apache Airflow on AWS using managed services and Kubernetes (EKS).

## Recommended Services

| Component | AWS Service | Notes |
|-----------|-------------|-------|
| Kubernetes | EKS | Managed Kubernetes |
| Metadata DB | RDS (PostgreSQL) | Multi-AZ for HA |
| Message Broker | ElastiCache (Redis) | Replication enabled |
| Logs Storage | S3 | With lifecycle policies |
| Secrets | Secrets Manager | Or Systems Manager Parameter Store |
| Monitoring | CloudWatch | Logs, metrics, alarms |
| Load Balancer | ALB | For Airflow WebUI |

## Setup Steps

### 1. Create AWS Resources

#### RDS PostgreSQL

```bash
aws rds create-db-instance \
  --db-instance-identifier airflow-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username airflow \
  --master-user-password <strong-password> \
  --allocated-storage 20 \
  --db-name airflow \
  --backup-retention-period 7 \
  --multi-az \
  --publicly-accessible false
```

Record the endpoint (e.g., `airflow-db.xxxxx.us-east-1.rds.amazonaws.com`).

#### ElastiCache Redis

```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id airflow-redis \
  --cache-node-type cache.t3.micro \
  --engine redis \
  --num-cache-nodes 1
```

For production, use Multi-AZ cluster:
```bash
aws elasticache create-replication-group \
  --replication-group-description "Airflow Redis" \
  --engine redis \
  --cache-node-type cache.t3.micro \
  --num-cache-clusters 2 \
  --automatic-failover-enabled
```

Record the endpoint.

#### S3 Bucket for Logs

```bash
aws s3 mb s3://airflow-logs-$(date +%s)

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket airflow-logs-xxxx \
  --versioning-configuration Status=Enabled

# Add lifecycle policy to delete old logs
aws s3api put-bucket-lifecycle-configuration \
  --bucket airflow-logs-xxxx \
  --lifecycle-configuration file://lifecycle.json
```

File `lifecycle.json`:
```json
{
  "Rules": [
    {
      "Id": "delete-old-logs",
      "Status": "Enabled",
      "Expiration": {"Days": 90},
      "Prefix": "airflow-logs/"
    }
  ]
}
```

#### EKS Cluster

```bash
eksctl create cluster \
  --name airflow-cluster \
  --region us-east-1 \
  --nodegroup-name airflow-nodes \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5
```

### 2. Create IAM Roles

Create a role for Airflow workers to access S3 and Secrets Manager:

```bash
# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name airflow-worker-role \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name airflow-worker-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
  --role-name airflow-worker-role \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

### 3. Create Secrets

```bash
# Store database connection string
aws secretsmanager create-secret \
  --name airflow/db-connection \
  --secret-string "postgresql://airflow:password@airflow-db.xxxxx.us-east-1.rds.amazonaws.com:5432/airflow"

# Store Fernet key
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
aws secretsmanager create-secret \
  --name airflow/fernet-key \
  --secret-string "$FERNET_KEY"

# Store webserver secret key
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
aws secretsmanager create-secret \
  --name airflow/webserver-secret-key \
  --secret-string "$SECRET_KEY"
```

### 4. Deploy to EKS

Update Kubernetes manifests with AWS endpoints:

```bash
# Edit k8s/airflow-secret.yaml with values from Secrets Manager
# Edit k8s/airflow-configmap.yaml with RDS/ElastiCache endpoints
```

Then deploy:
```bash
kubectl apply -f k8s/
```

### 5. Configure Remote Logging

Update `k8s/airflow-configmap.yaml`:

```yaml
AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "s3://airflow-logs-xxxx/airflow-logs"
```

Ensure workers have S3 access via IAM role.

### 6. Set Up Load Balancer

Create an Application Load Balancer (ALB) in front of the webserver:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: airflow-webserver-alb
  namespace: airflow
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
spec:
  type: LoadBalancer
  selector:
    app: airflow-webserver
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
```

Get ALB endpoint:
```bash
kubectl get svc airflow-webserver-alb -n airflow
```

### 7. Configure CloudWatch Monitoring

```bash
# Create CloudWatch log group
aws logs create-log-group --log-group-name /aws/airflow

# Update Kubernetes deployment to send logs
# (Already configured in provided manifests)
```

---

## Scaling

### Auto-scale Workers

Deploy an HPA (Horizontal Pod Autoscaler):

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

### Scale RDS

For increased database load:

```bash
aws rds modify-db-instance \
  --db-instance-identifier airflow-db \
  --db-instance-class db.t3.small \
  --apply-immediately
```

---

## Cost Optimization

1. **Use Spot Instances** for worker nodes (fault-tolerant workload):
   ```bash
   eksctl create nodegroup \
     --cluster airflow-cluster \
     --instance-types t3.medium \
     --spot \
     --name airflow-workers
   ```

2. **Scale Down Off-Hours**:
   ```bash
   kubectl patch deployment airflow-scheduler -p '{"spec":{"replicas":0}}'
   # (via scheduled job or Kubernetes CronJob)
   ```

3. **Use Reserved Instances** for persistent components (webserver, scheduler, DB).

4. **Enable S3 Intelligent-Tiering** for logs:
   ```bash
   aws s3api put-bucket-intelligent-tiering-configuration \
     --bucket airflow-logs-xxxx \
     --id auto-tiering \
     --intelligent-tiering-configuration ...
   ```

---

## Backup & Disaster Recovery

### RDS Backups

Automated daily backups (set retention to 7+ days):

```bash
aws rds describe-db-instances \
  --db-instance-identifier airflow-db \
  --query 'DBInstances[0].BackupRetentionPeriod'
```

### DAG Backups

Store DAGs in S3 or GitHub, pull via CI/CD to EKS.

### Secrets Rotation

Rotate Secrets Manager credentials regularly:

```bash
aws secretsmanager rotate-secret \
  --secret-id airflow/db-connection \
  --rotation-lambda-arn arn:aws:lambda:region:account:function:MyRotationFunction \
  --rotation-rules AutomaticallyAfterDays=30
```

---

## Troubleshooting

### Workers Can't Access Database

1. Check RDS security group allows worker pod security group
2. Verify database connection string in Secrets Manager
3. Check worker logs: `kubectl logs deployment/airflow-worker`

### S3 Logs Not Written

1. Verify IAM role has S3 permissions
2. Check S3 bucket path in AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER
3. Ensure bucket exists: `aws s3 ls s3://airflow-logs-xxxx/`

### Pod Evicted (OOMKilled)

Increase worker node instance size or set resource requests:

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

---

## References

- [AWS RDS PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [AWS ElastiCache Redis](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/Redis3vs6.html)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Airflow AWS Operators](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/)
