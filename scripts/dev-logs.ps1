# Windows script to view logs
# Usage: .\scripts\dev-logs.ps1 [service]
# Service: webserver, scheduler, worker, triggerer, redis, or all (default)

param(
    [string]$Service = "all"
)

Write-Host "Tailing logs..." -ForegroundColor Yellow
Write-Host "(Press Ctrl+C to exit)" -ForegroundColor Yellow
Write-Host ""

if ($Service -eq "all") {
    docker-compose logs -f --tail=50
} else {
    $validServices = @("webserver", "scheduler", "worker", "triggerer", "redis")
    if ($Service -notin $validServices) {
        Write-Host "ERROR: Invalid service. Choose from: all, webserver, scheduler, worker, triggerer, redis" -ForegroundColor Red
        exit 1
    }
    docker-compose logs -f --tail=50 "airflow-$Service"
}
