# stop.ps1 – Stoppt alle Container (Daten bleiben in Volumes erhalten)
# Mit -v Flag werden auch Volumes gelöscht (kompletter Reset):
#   .\scripts\stop.ps1 -v

param(
    [switch]$v
)

$ROOT = Split-Path $PSScriptRoot -Parent
Set-Location $ROOT

if ($v) {
    Write-Host "==> Stoppe Stack und lösche alle Volumes (Reset)..." -ForegroundColor Yellow
    docker compose down -v
    Write-Host "Alle Daten gelöscht. Beim nächsten Start werden Testdaten neu geladen." -ForegroundColor Yellow
} else {
    Write-Host "==> Stoppe Stack (Daten bleiben erhalten)..." -ForegroundColor Cyan
    docker compose down
    Write-Host "Stack gestoppt. Volumes sind noch vorhanden." -ForegroundColor Green
}
