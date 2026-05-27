# start.ps1 – Startet alle Custom-Datenbanken
# Aufruf: .\scripts\start.ps1

$ErrorActionPreference = "Stop"
$ROOT = Split-Path $PSScriptRoot -Parent

Write-Host "==> Starte HSO Datenbank-Stack..." -ForegroundColor Cyan

# .env prüfen
if (-not (Test-Path "$ROOT\.env")) {
    Write-Host "Keine .env gefunden – erstelle aus .env.example" -ForegroundColor Yellow
    Copy-Item "$ROOT\.env.example" "$ROOT\.env"
}

# Docker prüfen
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker nicht gefunden. Bitte Docker Desktop installieren."
}

Set-Location $ROOT

# Stack starten
docker compose up -d --build

Write-Host ""
Write-Host "==> Stack laeuft. Verbindungsinfos:" -ForegroundColor Green
Write-Host "   Source  PostgreSQL : localhost:5433  (sourcedb / sourceuser)" -ForegroundColor White
Write-Host "   Dest    PostgreSQL : localhost:5432  (destdb   / destuser  )" -ForegroundColor White
Write-Host "   Dest    MySQL      : localhost:3306  (destdb   / destuser  )" -ForegroundColor White
Write-Host ""
Write-Host "==> Naechster Schritt: Airbyte starten (siehe docs\airbyte-setup.md)" -ForegroundColor Cyan
