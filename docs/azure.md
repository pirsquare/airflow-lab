# Microsoft Azure Deployment Guide

Deploy Apache Airflow on Microsoft Azure using managed services and Azure Kubernetes Service (AKS).

## Recommended Services

| Component | Azure Service | Notes |
|-----------|---------------|-------|
| Kubernetes | AKS | Managed Kubernetes |
| Metadata DB | Azure Database for PostgreSQL | Single or Flexible Server |
| Message Broker | Azure Cache for Redis | Premium tier for HA |
| Logs Storage | Azure Blob Storage | With lifecycle policies |
| Secrets | Azure Key Vault | IAM-integrated |
| Monitoring | Azure Monitor | Logs, metrics, alerts |
| Load Balancer | Application Gateway or ALB | Public access |

## Setup Steps

### 1. Create Azure Resources

#### Azure Database for PostgreSQL

```bash
# Create resource group
az group create --name airflow-rg --location eastus

# Create PostgreSQL server
az postgres server create \
  --name airflow-db \
  --resource-group airflow-rg \
  --location eastus \
  --admin-user airflow \
  --admin-password <strong-password> \
  --sku-name B_Gen5_1 \
  --storage-size 51200 \
  --backup-retention 7 \
  --geo-redundant-backup Enabled

# Create database
az postgres db create \
  --server-name airflow-db \
  --resource-group airflow-rg \
  --name airflow

# Get connection string
az postgres server show-connection-string \
  --server-name airflow-db \
  --admin-user airflow
```

#### Azure Cache for Redis

```bash
az redis create \
  --name airflow-redis \
  --resource-group airflow-rg \
  --location eastus \
  --sku Premium \
  --vm-size p1

# Get connection string
az redis show-connection-string \
  --name airflow-redis \
  --resource-group airflow-rg
```

#### Azure Blob Storage for Logs

```bash
# Create storage account
az storage account create \
  --name airflowlogs$(date +%s) \
  --resource-group airflow-rg \
  --location eastus

# Create container
az storage container create \
  --name airflow-logs \
  --account-name airflowlogsxxxx

# Set lifecycle policy (delete after 90 days)
cat > lifecycle.json <<EOF
{
  "rules": [
    {
      "name": "delete-old-logs",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "delete": {
              "daysAfterModificationGreaterThan": 90
            }
          }
        },
        "filters": {
          "blobTypes": ["appendBlob", "blockBlob"],
          "prefixMatch": ["airflow-logs/"]
        }
      }
    }
  ]
}
EOF

az storage account management-policy create \
  --account-name airflowlogsxxxx \
  --policy lifecycle.json \
  --resource-group airflow-rg
```

#### AKS Cluster

```bash
# Create AKS cluster
az aks create \
  --resource-group airflow-rg \
  --name airflow-cluster \
  --node-count 3 \
  --vm-set-type VirtualMachineScaleSets \
  --load-balancer-sku standard \
  --enable-managed-identity

# Get credentials
az aks get-credentials \
  --resource-group airflow-rg \
  --name airflow-cluster
```

### 2. Create Azure Key Vault and Secrets

```bash
# Create Key Vault
az keyvault create \
  --name airflow-kv \
  --resource-group airflow-rg \
  --location eastus

# Store database connection string
az keyvault secret set \
  --vault-name airflow-kv \
  --name db-connection \
  --value "postgresql://airflow:password@airflow-db.postgres.database.azure.com:5432/airflow"

# Store Fernet key
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
az keyvault secret set \
  --vault-name airflow-kv \
  --name fernet-key \
  --value "$FERNET_KEY"

# Store webserver secret key
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
az keyvault secret set \
  --vault-name airflow-kv \
  --name webserver-secret-key \
  --value "$SECRET_KEY"
```

### 3. Create Managed Identity

```bash
# Create managed identity for AKS
az identity create \
  --name airflow-identity \
  --resource-group airflow-rg

# Grant permissions
IDENTITY_ID=$(az identity show \
  --name airflow-identity \
  --resource-group airflow-rg \
  --query id -o tsv)

# Grant Key Vault access
az keyvault set-policy \
  --name airflow-kv \
  --object-id $(az identity show \
    --name airflow-identity \
    --resource-group airflow-rg \
    --query principalId -o tsv) \
  --secret-permissions get

# Grant Blob Storage access
az role assignment create \
  --assignee $(az identity show \
    --name airflow-identity \
    --resource-group airflow-rg \
    --query principalId -o tsv) \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/SUBSCRIPTION_ID/resourceGroups/airflow-rg/providers/Microsoft.Storage/storageAccounts/airflowlogsxxxx"
```

### 4. Deploy to AKS

Update Kubernetes manifests with Azure endpoints:

```bash
# Edit k8s/airflow-configmap.yaml with Azure Database & Cache endpoints
# Edit k8s/airflow-secret.yaml with Key Vault secrets
```

Link managed identity to Kubernetes service account:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: airflow
  namespace: airflow
  annotations:
    azure.workload.identity/client-id: "CLIENT_ID"
```

Deploy:
```bash
kubectl apply -f k8s/
```

### 5. Configure Remote Logging

Update `k8s/airflow-configmap.yaml`:

```yaml
AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "wasbs://airflow-logs@airflowlogsxxxx.blob.core.windows.net/airflow-logs"
```

Ensure pods have identity with Blob Storage permissions.

### 6. Set Up Application Gateway (Load Balancer)

```bash
# Create public IP
az network public-ip create \
  --name airflow-ip \
  --resource-group airflow-rg \
  --sku Standard

# Create Application Gateway
az network application-gateway create \
  --name airflow-gateway \
  --resource-group airflow-rg \
  --vnet-name airflow-vnet \
  --subnet gateway-subnet \
  --capacity 2 \
  --sku Standard_v2 \
  --http-settings-cookie-based-affinity Enabled
```

Or use Kubernetes Ingress (simpler):

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

### 7. Configure Azure Monitor

```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create \
  --resource-group airflow-rg \
  --workspace-name airflow-logs

# Configure diagnostics
az monitor diagnostic-settings create \
  --name airflow-diagnostics \
  --resource /subscriptions/SUBSCRIPTION_ID/resourceGroups/airflow-rg/providers/Microsoft.ContainerService/managedClusters/airflow-cluster \
  --logs '[{"category":"cluster-autoscaling","enabled":true}]' \
  --workspace /subscriptions/SUBSCRIPTION_ID/resourceGroups/airflow-rg/providers/Microsoft.OperationalInsights/workspaces/airflow-logs
```

---

## Scaling

### Auto-scale Workers

Deploy HPA:

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

### Scale Database

Increase tier:

```bash
az postgres server update \
  --name airflow-db \
  --resource-group airflow-rg \
  --sku-name B_Gen5_2
```

---

## Cost Optimization

1. **Use Spot VMs** for worker nodes:
   ```bash
   az aks nodepool add \
     --cluster-name airflow-cluster \
     --resource-group airflow-rg \
     --name spot-pool \
     --priority Spot \
     --eviction-policy Delete
   ```

2. **Scale Down Off-Hours** via Azure Automation or Logic Apps.

3. **Use Reserved Instances** for persistent components.

4. **Archive old logs to Archive Storage**:
   ```bash
   az storage blob tier set \
     --account-name airflowlogsxxxx \
     --container-name airflow-logs \
     --name "airflow-logs/old/*" \
     --tier Archive
   ```

---

## Backup & Disaster Recovery

### Database Backups

Automated daily backups (7-day retention configured in setup):

```bash
az postgres server update \
  --name airflow-db \
  --resource-group airflow-rg \
  --backup-retention 35
```

### Blob Storage Backups

Enable versioning:

```bash
az storage blob service-properties update \
  --account-name airflowlogsxxxx \
  --enable-change-feed true
```

### DAG Backups

Store in GitHub/Azure Repos, pull via CI/CD.

---

## Troubleshooting

### Can't Connect to Azure Database

1. Check PostgreSQL firewall rules:
   ```bash
   az postgres server firewall-rule list \
     --name airflow-db \
     --resource-group airflow-rg
   ```

2. Verify connection string: `kubectl get secret airflow-secrets -o jsonpath='{.data.db-connection}' | base64 -d`

3. Check managed identity permissions on Key Vault

### Can't Write to Blob Storage

1. Verify managed identity has "Storage Blob Data Contributor" role
2. Check storage account firewall allows AKS subnet
3. Verify connection string path

### Pod Evicted

Increase AKS node pool size or enable cluster autoscale:

```bash
az aks update \
  --resource-group airflow-rg \
  --name airflow-cluster \
  --enable-cluster-autoscaling \
  --min-count 2 \
  --max-count 10
```

---

## References

- [Azure Database for PostgreSQL](https://docs.microsoft.com/en-us/azure/postgresql/)
- [Azure Cache for Redis](https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/)
- [AKS Best Practices](https://docs.microsoft.com/en-us/azure/aks/best-practices)
- [Airflow Microsoft Azure Operators](https://airflow.apache.org/docs/apache-airflow-providers-microsoft-azure/stable/)
