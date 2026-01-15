# Helper script to generate secure keys
# Usage: .\scripts\generate-keys.ps1

Write-Host "Generating Airflow security keys..." -ForegroundColor Green

# Install cryptography if needed
pip install cryptography > $null 2>&1

# Generate Fernet key
$fernet_key = python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Generate WebServer secret key (32 random bytes in hex)
$secret_key = python -c "import secrets; print(secrets.token_hex(32))"

Write-Host ""
Write-Host "=== Generated Keys ===" -ForegroundColor Yellow
Write-Host "Copy these to .env file:" -ForegroundColor Yellow
Write-Host ""
Write-Host "AIRFLOW__CORE__FERNET_KEY=$fernet_key" -ForegroundColor Cyan
Write-Host "AIRFLOW__WEBSERVER__SECRET_KEY=$secret_key" -ForegroundColor Cyan
Write-Host ""
