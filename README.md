# Airflow Local Development & Multi-Cloud Deployment

A simple, pragmatic Apache Airflow setup for local development on Windows (Docker Desktop) with guidance for multi-cloud production deployment.

- **Local Dev**: SQLite metadata DB, Redis broker, all in Docker Compose
- **Executor**: CeleryExecutor everywhere (local & cloud)
- **Airflow**: Latest stable image (no pinned versions)
- **Simplicity First**: Minimal setup, only essential services

---

## Quick Start (Windows)

### Prerequisites
- Docker Desktop (with Compose)
- PowerShell

### One-Command Startup

```powershell
.\scripts\dev-up.ps1
```

This script will:
1. Check Docker is running
2. Generate security keys if `.env` doesn't exist
3. Start all services (webserver, scheduler, worker, triggerer, Redis)
4. Wait for webserver to be healthy
5. Print credentials and next steps

### Access Airflow

Open http://localhost:8080

- **Username**: `admin` (or set `AIRFLOW_ADMIN_USER` in `.env`)
- **Password**: `admin` (or set `AIRFLOW_ADMIN_PASSWORD` in `.env`)

### Trigger a DAG

Two demo DAGs are included:

1. **`demo_simple`**: Single task that logs hostname/PID. Good for validation.
2. **`demo_celery_fanout`**: 5 parallel tasks + aggregator. Proves Celery distribution.

To trigger:
1. Go to DAGs view
2. Click the DAG name
3. Click "Trigger DAG" button
4. View task runs in the web UI or logs

### Verify Celery Distribution

When running `demo_celery_fanout`, each worker task should show a different hostname (if running multiple workers) or the same hostname with different PIDs.

Check logs:
```powershell
.\scripts\dev-logs.ps1 worker
```

---

## Local Development Setup

### Directory Structure

```
airflow-lab/
├── dags/                    # DAG definitions (auto-discovered)
├── plugins/                 # Custom Airflow plugins
├── logs/                    # Airflow task logs (mounted volume)
├── scripts/                 # Setup scripts (Windows .ps1 + Unix .sh)
├── docs/                    # Cloud deployment docs
├── k8s/                     # Kubernetes manifests
├── docker-compose.yml       # Docker Compose config
├── Dockerfile               # Airflow image
├── requirements.txt         # Python dependencies
├── .env.example            # Env variables template
└── README.md               # This file
```

### Service Ports

| Service | Port | Purpose |
|---------|------|---------|
| Webserver | 8080 | Airflow UI & API |
| Redis | 6379 | Celery broker & result backend |

### Database

**Local Development**: SQLite (`/opt/airflow/airflow.db`)
- Stored in Docker volume `airflow_data`
- Automatically created on first run
- **Note**: SQLite has limited concurrency; OK for dev, not for production

**Production**: Use PostgreSQL/MySQL (external managed service)

### Service Management (Windows)

```powershell
# Start
.\scripts\dev-up.ps1

# View logs
.\scripts\dev-logs.ps1
.\scripts\dev-logs.ps1 scheduler    # Specific service

# Stop (preserve data)
.\scripts\dev-down.ps1

# Stop and remove all data
.\scripts\dev-down.ps1 -RemoveVolumes

# Scale workers
docker-compose up -d --scale airflow-worker=3
```

### Service Management (macOS/Linux)

```bash
# Start
./scripts/dev-up.sh

# View logs
./scripts/dev-logs.sh
./scripts/dev-logs.sh scheduler

# Stop
./scripts/dev-down.sh

# Stop and remove all data
./scripts/dev-down.sh --remove-volumes

# Scale workers
docker-compose up -d --scale airflow-worker=3
```

---

## Configuration

### `.env` File

Copy `.env.example` to `.env` and customize:

```bash
# Security (auto-generated on first run)
AIRFLOW__CORE__FERNET_KEY=your-fernet-key-here
AIRFLOW__WEBSERVER__SECRET_KEY=your-webserver-secret-key-here

# Admin user
AIRFLOW_ADMIN_USER=admin
AIRFLOW_ADMIN_PASSWORD=admin
AIRFLOW_ADMIN_EMAIL=admin@example.com
```

To manually generate keys:

**Windows**:
```powershell
.\scripts\generate-keys.ps1
```

**macOS/Linux**:
```bash
./scripts/generate-keys.sh
```

### Environment Variables

Airflow uses environment variables for all config (no `airflow.cfg`):

Key variables (all set in `.env`):
- `AIRFLOW__CORE__EXECUTOR=CeleryExecutor`
- `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////opt/airflow/airflow.db`
- `AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0`
- `AIRFLOW__CELERY__RESULT_BACKEND=redis://redis:6379/1`
- `AIRFLOW__CORE__LOAD_EXAMPLES=False`
- `AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=False`

For other variables, see [Airflow docs](https://airflow.apache.org/docs/apache-airflow/stable/configurations-ref.html).

---

## Creating Custom DAGs

Place Python files in `dags/` folder. They're auto-discovered.

### Simple Example

```python
from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator

def my_task(**context):
    print("Hello from Airflow!")

with DAG(
    dag_id='my_dag',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
) as dag:
    task = PythonOperator(task_id='my_task', python_callable=my_task)
```

DAGs are auto-loaded within ~5 seconds. Refresh the web UI to see them.

---

## Troubleshooting

### WebUI Not Accessible (http://localhost:8080 times out)

1. Check containers are running:
   ```powershell
   docker-compose ps
   ```

2. View webserver logs:
   ```powershell
   .\scripts\dev-logs.ps1 webserver
   ```

3. Common issues:
   - Port 8080 already in use: `netstat -ano | findstr :8080` (Windows)
   - Docker Desktop not running
   - Insufficient disk space

### Scheduler Not Picking Up DAGs

1. Check scheduler is running:
   ```powershell
   docker-compose ps airflow-scheduler
   ```

2. View scheduler logs:
   ```powershell
   .\scripts\dev-logs.ps1 scheduler
   ```

3. Common issues:
   - DAG not properly formatted (syntax error)
   - DAG `dag_id` conflicts with existing DAG
   - File permissions (on Windows, usually not an issue)

4. Force DAG reload:
   - Delete `.airflow/` cache in container: `docker-compose exec webserver rm -rf .airflow/`
   - Or restart scheduler: `docker-compose restart airflow-scheduler`

### Tasks Not Executing (Stuck in Queued)

1. Check worker is running:
   ```powershell
   docker-compose ps airflow-worker
   ```

2. View worker logs:
   ```powershell
   .\scripts\dev-logs.ps1 worker
   ```

3. Common issues:
   - Worker crashed (check logs)
   - Redis unhealthy: `docker-compose exec redis redis-cli ping`
   - Task queue issue: Check Flower at http://localhost:5555 (if enabled)

### Slow DAG Parsing / File Watching on Windows

Windows file mounts in Docker can be slow. If parsing is sluggish:

1. Increase scan interval in `.env`:
   ```
   AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL=300
   ```

2. Use `.gitignore` to exclude large folders from Docker context:
   ```
   node_modules/
   venv/
   .git/
   ```

### "Line Endings" / CRLF Issues (Windows)

If DAG files have `CRLF` line endings, Python may fail to parse them:

1. **In VS Code**: Set end-of-line to `LF`:
   - Click "CRLF" in status bar → select "LF"

2. **In Git** (recommended for team):
   ```bash
   git config core.autocrlf input
   ```

3. **In Docker** (alternative): Pre-process with `dos2unix` in Dockerfile (not included for simplicity)

### Database Lock / "SQLite database is locked"

SQLite has limited concurrency. If you see lock errors:

1. **For dev**: Restart services:
   ```powershell
   docker-compose restart
   ```

2. **For production**: Migrate to PostgreSQL/MySQL (see [Production Setup](#production-setup))

### "Permission Denied" on Mounted Volumes (macOS/Linux)

Ensure Docker user can write to `logs/`:
```bash
chmod -R 777 logs/
```

---

## Scaling Workers

Run multiple Celery workers to parallelize task execution:

```powershell
# Scale to 3 workers
docker-compose up -d --scale airflow-worker=3

# View all workers
docker-compose ps | Select-String "airflow-worker"

# Back to 1
docker-compose up -d --scale airflow-worker=1
```

Each worker gets a unique container name: `airflow-worker_1`, `airflow-worker_2`, etc.

Verify distribution by running `demo_celery_fanout` and checking logs—each task should run on a different worker (different hostname or PID).

---

## Monitoring

### Airflow Web UI

Main dashboard: http://localhost:8080

- **DAGs**: View all DAGs, trigger manually
- **Graph View**: Visualize task dependencies
- **Task Logs**: Click a task run to see logs
- **Admin → Connections**: Manage external service credentials

### Log Files

Logs are mounted to `logs/` directory:
```
logs/
  dag_id=demo_celery_fanout/
    run_id=manual__2024-01-16T12_00_00+00_00/
      task_id=worker_task_0/
        attempt=1.log
```

---

## Production Setup

### Recommended Architecture

```
┌──────────────────┐
│  Airflow Web UI  │
│  (Webserver)     │
└────────┬─────────┘
         │
    ┌────┴────┐
    │          │
┌───▼────┐  ┌─▼─────────┐
│Scheduler│  │ Triggerer │
└───┬────┘  └─┬─────────┘
    │         │
    └────┬────┘
         │
   ┌─────▼──────┐
   │   Celery   │◄──────┐
   │  Workers   │       │
   │ (multiple) │       │
   └─────┬──────┘       │
         │              │
    ┌────┴────────────────┐
    │                     │
┌───▼──┐            ┌─────▼─┐
│PostgreSQL│        │ Redis │
│(managed) │        │(managed)
└──────────┘        └───────┘
```

**Key differences from local**:
- **Metadata DB**: PostgreSQL/MySQL (not SQLite)
- **Broker & Result Backend**: Redis (external managed service)
- **Multiple Workers**: Scale horizontally
- **Webserver/Scheduler**: Run on separate nodes
- **Logs**: Store in cloud storage (S3, GCS, Azure Blob)

### Cloud Deployment

See cloud-specific docs:
- [AWS Setup](docs/aws.md)
- [Google Cloud Setup](docs/gcp.md)
- [Azure Setup](docs/azure.md)

Minimal Kubernetes manifests:
- [k8s/](k8s/) folder

---

## Upgrading Airflow

The docker-compose uses the latest stable Airflow image. To upgrade:

```bash
docker-compose down
docker rmi apache/airflow:latest
docker-compose build --no-cache
./scripts/dev-up.ps1
```

---

## Adding Providers

To add new Airflow providers (e.g., AWS, GCP):

1. Add to `requirements.txt`:
   ```
   apache-airflow-providers-amazon>=14.0.0
   ```

2. Rebuild & restart:
   ```powershell
   docker-compose down -v
   docker-compose build --no-cache
   .\scripts\dev-up.ps1
   ```

---

## Useful Commands

### View All DAGs

```powershell
docker-compose exec webserver airflow dags list
```

### Trigger DAG from CLI

```powershell
docker-compose exec webserver airflow dags trigger demo_celery_fanout
```

### Clear DAG Runs

```powershell
docker-compose exec webserver airflow dags delete demo_celery_fanout
```

### View Task Status

```powershell
docker-compose exec webserver airflow tasks list demo_celery_fanout
```

### Execute Python in Scheduler

```powershell
docker-compose exec scheduler bash
# Inside container:
python -c "from airflow.models import Variable; print(Variable.get('my_var'))"
```

---

## FAQs

**Q: Can I use CeleryExecutor for production?**
A: Yes, it's recommended for most deployments. Scale workers horizontally. For very high throughput, consider KubernetesExecutor.

**Q: Why SQLite for local dev, not PostgreSQL?**
A: Simplicity. No separate database service to manage. For production, use PostgreSQL.

**Q: Can I access Flower (Celery monitoring)?**
A: Not exposed in this setup (no Flower service). You can add it if needed; see Docker Hub for `mher/flower` image.

**Q: What about GitSync / External DAG storage?**
A: Not included. Use CI/CD to push DAGs to the `dags/` folder, or mount from a shared volume.

**Q: How do I set Airflow Variables/Connections?**
A: Use the web UI (Admin → Variables/Connections) or the CLI:
```powershell
docker-compose exec webserver airflow variables set MY_VAR my_value
docker-compose exec webserver airflow connections add my_conn --conn-type http --conn-host https://api.example.com
```

**Q: Can I use a different database (e.g., MySQL)?**
A: Yes. Update `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` in `.env`. Requires installing driver in Dockerfile.

---

## Links

- [Airflow Docs](https://airflow.apache.org/docs/)
- [Airflow Providers](https://airflow.apache.org/docs/apache-airflow-providers/index.html)
- [CeleryExecutor Guide](https://airflow.apache.org/docs/apache-airflow/stable/executor/celery.html)
- [Airflow Security](https://airflow.apache.org/docs/apache-airflow/stable/security/)

---

## License

See LICENSE file.
