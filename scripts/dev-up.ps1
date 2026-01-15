# Windows setup script for local Airflow development
# Usage: .\scripts\dev-up.ps1

Write-Host "========================================" -ForegroundColor Green
Write-Host "Airflow Local Development - Startup" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Check Docker
Write-Host "Checking Docker..." -ForegroundColor Yellow
$dockerCheck = docker ps 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Check .env file
if (-not (Test-Path ".env")) {
    Write-Host ".env file not found. Creating from .env.example..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
    
    # Generate keys if using placeholders
    Write-Host "Generating security keys..." -ForegroundColor Yellow
    pip install cryptography > $null 2>&1
    
    $fernet_key = python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    $secret_key = python -c "import secrets; print(secrets.token_hex(32))"
    
    # Update .env with generated keys
    $env_content = Get-Content ".env" -Raw
    $env_content = $env_content -replace "your-fernet-key-here", $fernet_key
    $env_content = $env_content -replace "your-webserver-secret-key-here", $secret_key
    Set-Content ".env" $env_content
    
    Write-Host "✓ .env created with generated keys" -ForegroundColor Green
}

# Load .env
Write-Host "Loading .env..." -ForegroundColor Yellow
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^([^=]+)=(.*)$") {
        $key = $matches[1]
        $value = $matches[2]
        if ($value -ne "your-fernet-key-here" -and $value -ne "your-webserver-secret-key-here") {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

# Start services
Write-Host ""
Write-Host "Starting Docker Compose services..." -ForegroundColor Yellow
docker-compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to start Docker Compose" -ForegroundColor Red
    exit 1
}

# Wait for webserver to be healthy
Write-Host ""
Write-Host "Waiting for Airflow webserver to be ready..." -ForegroundColor Yellow
$maxAttempts = 60
$attempt = 0
$healthy = $false

while ($attempt -lt $maxAttempts) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $healthy = $true
            break
        }
    } catch {
        # Still waiting
    }
    $attempt++
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 1
}

Write-Host ""

if ($healthy) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "✓ Airflow is ready!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "WebUI: http://localhost:8080" -ForegroundColor Cyan
    Write-Host "Username: $(if ($env:AIRFLOW_ADMIN_USER) { $env:AIRFLOW_ADMIN_USER } else { 'admin' })" -ForegroundColor Cyan
    Write-Host "Password: $(if ($env:AIRFLOW_ADMIN_PASSWORD) { $env:AIRFLOW_ADMIN_PASSWORD } else { 'admin' })" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Open http://localhost:8080 in your browser" -ForegroundColor Cyan
    Write-Host "  2. Trigger the demo_simple DAG to test" -ForegroundColor Cyan
    Write-Host "  3. Trigger demo_celery_fanout to see Celery distribution" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Useful commands:" -ForegroundColor Yellow
    Write-Host "  .\scripts\dev-logs.ps1           - View logs" -ForegroundColor Cyan
    Write-Host "  .\scripts\dev-down.ps1           - Stop services" -ForegroundColor Cyan
    Write-Host "  docker-compose scale airflow-worker=2  - Scale workers" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "ERROR: Webserver failed to become healthy after $maxAttempts attempts" -ForegroundColor Red
    Write-Host "Run '.\scripts\dev-logs.ps1' to check logs" -ForegroundColor Yellow
    exit 1
}
