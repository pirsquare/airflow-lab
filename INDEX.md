# Getting Started with Airflow

## 📋 Quick Navigation

### Local Development (Recommended First)
1. **Start Here**: [README.md](README.md) - Complete local dev setup
2. **One Command Setup**: `.\scripts\dev-up.ps1` (Windows) or `./scripts/dev-up.sh` (Mac/Linux)
3. **Demo DAGs**: 
   - `dags/demo_simple.py` - Basic single task
   - `dags/demo_celery_fanout.py` - Parallel task execution (proves Celery)

### Production Deployment
1. **Architecture Overview**: [docs/cloud-overview.md](docs/cloud-overview.md)
2. **Cloud-Specific Guides**:
   - [AWS Deployment](docs/aws.md)
   - [Google Cloud Deployment](docs/gcp.md)
   - [Azure Deployment](docs/azure.md)
3. **Kubernetes Manifests**: [k8s/](k8s/) folder with minimal, portable manifests

## 🚀 Quick Start (60 seconds)

**Windows (PowerShell)**:
```powershell
.\scripts\dev-up.ps1
```

**macOS/Linux (Bash)**:
```bash
./scripts/dev-up.sh
```

Then open http://localhost:8080

## 📂 Directory Structure

```
airflow-lab/
├── README.md                    ← Start here for local dev
├── docker-compose.yml           ← Local dev services
├── Dockerfile                   ← Airflow image
├── requirements.txt             ← Python dependencies
├── .env.example                ← Copy to .env and customize
│
├── dags/                        ← DAG definitions (auto-discovered)
│   ├── demo_simple.py
│   └── demo_celery_fanout.py
│
├── plugins/                     ← Custom Airflow plugins
├── logs/                        ← Task logs (mounted volume)
│
├── scripts/                     ← Setup automation
│   ├── dev-up.ps1              ← Start (Windows)
│   ├── dev-up.sh               ← Start (Mac/Linux)
│   ├── dev-down.ps1            ← Stop (Windows)
│   ├── dev-down.sh             ← Stop (Mac/Linux)
│   ├── dev-logs.ps1            ← View logs (Windows)
│   ├── dev-logs.sh             ← View logs (Mac/Linux)
│   ├── generate-keys.ps1       ← Generate secrets (Windows)
│   └── generate-keys.sh        ← Generate secrets (Mac/Linux)
│
├── docs/                        ← Production deployment
│   ├── cloud-overview.md        ← Architecture & common setup
│   ├── aws.md                   ← AWS-specific guide
│   ├── gcp.md                   ← GCP-specific guide
│   └── azure.md                 ← Azure-specific guide
│
└── k8s/                         ← Kubernetes manifests
    ├── README.md                ← Deployment instructions
    ├── namespace.yaml
    ├── airflow-configmap.yaml
    ├── airflow-secret.yaml
    ├── webserver-deployment.yaml
    ├── scheduler-deployment.yaml
    ├── worker-deployment.yaml
    └── triggerer-deployment.yaml
```

## ❓ Common Tasks

### Start Local Dev
```powershell
.\scripts\dev-up.ps1
```

### Stop Local Dev
```powershell
.\scripts\dev-down.ps1
```

### View Logs
```powershell
.\scripts\dev-logs.ps1 scheduler
.\scripts\dev-logs.ps1 worker
```

### Scale Workers
```bash
docker-compose up -d --scale airflow-worker=3
```

### Access Airflow WebUI
http://localhost:8080 (admin/admin by default)

### Trigger Demo DAG
1. Open WebUI
2. Click "demo_celery_fanout"
3. Click "Trigger DAG"
4. View task execution

### Create Custom DAG
1. Create `.py` file in `dags/`
2. Define DAG using Airflow SDK
3. DAG auto-loads within ~5 seconds

### Deploy to Production
1. Update `docs/cloud-overview.md` for your cloud
2. Follow cloud-specific guide (AWS/GCP/Azure)
3. Use manifests in `k8s/` folder

## 🔧 Key Features

✅ **Local Dev**: SQLite database, Redis broker, all in Docker Compose  
✅ **CeleryExecutor**: Used everywhere (local & cloud)  
✅ **Latest Airflow**: No pinned versions; easy to upgrade  
✅ **Simplicity First**: Minimal setup, no unnecessary complexity  
✅ **Multi-Cloud Ready**: Pre-configured for AWS, GCP, Azure  
✅ **Kubernetes Ready**: Minimal manifests for cloud deployment  
✅ **Windows-First**: Scripts for Windows PowerShell + Unix bash  

## 📖 Documentation

- **Local Development**: [README.md](README.md)
- **Architecture & Setup**: [docs/cloud-overview.md](docs/cloud-overview.md)
- **AWS**: [docs/aws.md](docs/aws.md)
- **GCP**: [docs/gcp.md](docs/gcp.md)
- **Azure**: [docs/azure.md](docs/azure.md)
- **Kubernetes**: [k8s/README.md](k8s/README.md)

## 🐳 Docker Compose Services

| Service | Purpose | Port |
|---------|---------|------|
| **airflow-webserver** | Airflow UI & API | 8080 |
| **airflow-scheduler** | DAG scheduling | - |
| **airflow-worker** | Celery task execution | - |
| **airflow-triggerer** | Event-based DAG triggering | - |
| **redis** | Celery broker & result backend | 6379 |

## ✨ Configuration

All config via environment variables in `.env`:

```bash
# Security (auto-generated on first run)
AIRFLOW__CORE__FERNET_KEY=...
AIRFLOW__WEBSERVER__SECRET_KEY=...

# Admin credentials
AIRFLOW_ADMIN_USER=admin
AIRFLOW_ADMIN_PASSWORD=admin
AIRFLOW_ADMIN_EMAIL=admin@example.com
```

See [.env.example](.env.example) for all options.

## 🆘 Troubleshooting

**WebUI won't load?**
```powershell
.\scripts\dev-logs.ps1 webserver
```

**DAGs not loading?**
```powershell
.\scripts\dev-logs.ps1 scheduler
```

**Tasks not executing?**
```powershell
.\scripts\dev-logs.ps1 worker
```

See [README.md#troubleshooting](README.md#troubleshooting) for detailed troubleshooting.

## 📝 License

See LICENSE file.
