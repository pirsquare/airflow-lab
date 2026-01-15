# Windows script to stop Airflow
# Usage: .\scripts\dev-down.ps1 [-RemoveVolumes]

param(
    [switch]$RemoveVolumes = $false
)

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Airflow Local Development - Shutdown" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

if ($RemoveVolumes) {
    Write-Host "Stopping services and removing volumes..." -ForegroundColor Yellow
    docker-compose down -v
    Write-Host "✓ Services stopped and volumes removed" -ForegroundColor Green
} else {
    Write-Host "Stopping services..." -ForegroundColor Yellow
    docker-compose down
    Write-Host "✓ Services stopped (volumes preserved)" -ForegroundColor Green
    Write-Host "  Use -RemoveVolumes flag to also remove database and logs" -ForegroundColor Yellow
}

Write-Host ""
