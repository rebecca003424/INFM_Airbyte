# install.ps1 – Vollständiges Setup für alle Projektmitglieder
# Aufruf: .\scripts\install.ps1
#
# Was dieses Skript tut:
#   1. Voraussetzungen prüfen (Docker, Git, Python)
#   2. .env aus .env.example erstellen (wenn nicht vorhanden)
#   3. Docker-Images laden
#   4. Datenbank-Stack starten
#   5. Warten bis alle Container healthy sind
#   6. Verbindungsinfos ausgeben

$ErrorActionPreference = "Stop"
$ROOT = Split-Path $PSScriptRoot -Parent

# ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "    [!]  $msg" -ForegroundColor Yellow
}

function Write-Fail([string]$msg) {
    Write-Host "    [X]  $msg" -ForegroundColor Red
}

function Assert-Command([string]$cmd, [string]$hint) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Fail "$cmd nicht gefunden."
        Write-Host "         $hint" -ForegroundColor Gray
        exit 1
    }
    Write-Ok "$cmd gefunden."
}

# ─── Banner ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Campus Next-Gen Data-Hub – Installations-Skript" -ForegroundColor White
Write-Host "  =================================================" -ForegroundColor DarkGray
Write-Host ""

# ─── 1. Voraussetzungen prüfen ────────────────────────────────────────────────

Write-Step "Voraussetzungen prüfen"

Assert-Command "git"    "Installieren: https://git-scm.com/download/win"
Assert-Command "docker" "Installieren: https://www.docker.com/products/docker-desktop/"

# Docker läuft?
$dockerRunning = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker Desktop ist nicht gestartet."
    Write-Host "         Bitte Docker Desktop starten und erneut versuchen." -ForegroundColor Gray
    exit 1
}
Write-Ok "Docker Desktop läuft."

# Docker Compose verfügbar?
$composeVersion = docker compose version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "docker compose nicht verfügbar."
    Write-Host "         Docker Desktop auf Version >=4.x aktualisieren." -ForegroundColor Gray
    exit 1
}
Write-Ok "docker compose verfügbar ($($composeVersion -replace 'Docker Compose version ',''))."

# Python (optional, aber nötig für Szenarien 3 & 4)
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVer = python --version 2>&1
    Write-Ok "Python gefunden ($pyVer)."
} else {
    Write-Warn "Python nicht gefunden – für Szenarien 3 & 4 erforderlich."
    Write-Warn "Installieren: https://www.python.org/downloads/ (>= 3.11, 'Add to PATH' aktivieren)"
}

# ─── 2. .env erstellen ────────────────────────────────────────────────────────

Write-Step ".env Konfigurationsdatei"

Set-Location $ROOT

if (Test-Path ".env") {
    Write-Ok ".env existiert bereits – wird nicht überschrieben."
} else {
    Copy-Item ".env.example" ".env"
    Write-Ok ".env aus .env.example erstellt."
    Write-Warn "Passwörter bei Bedarf in .env anpassen (aktuell: Standardwerte)."
}

# ─── 3. Docker-Images laden ───────────────────────────────────────────────────

Write-Step "Docker-Images herunterladen (dauert beim ersten Mal ~2 Minuten)"

docker compose pull
if ($LASTEXITCODE -ne 0) {
    Write-Fail "docker compose pull fehlgeschlagen."
    exit 1
}
Write-Ok "Images bereit."

# ─── 4. Stack starten ─────────────────────────────────────────────────────────

Write-Step "Datenbank-Stack starten"

docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Fail "docker compose up fehlgeschlagen."
    Write-Host "         Tipp: Sind die Ports 5432, 5433 oder 3306 schon belegt?" -ForegroundColor Gray
    exit 1
}
Write-Ok "Container gestartet."

# ─── 5. Auf healthy warten ────────────────────────────────────────────────────

Write-Step "Warte bis alle Container healthy sind..."

$services  = @("hso_source_postgres", "hso_dest_postgres", "hso_dest_mysql")
$maxWaitSec = 120
$interval   = 5
$elapsed    = 0

while ($elapsed -lt $maxWaitSec) {
    $allHealthy = $true
    foreach ($svc in $services) {
        $status = docker inspect --format "{{.State.Health.Status}}" $svc 2>$null
        if ($status -ne "healthy") {
            $allHealthy = $false
        }
    }
    if ($allHealthy) { break }

    Write-Host "    Warte... ($elapsed/$maxWaitSec s)" -ForegroundColor DarkGray
    Start-Sleep -Seconds $interval
    $elapsed += $interval
}

if ($elapsed -ge $maxWaitSec) {
    Write-Warn "Timeout – nicht alle Container sind healthy. Status:"
    docker compose ps
    Write-Warn "Logs prüfen: docker logs hso_source_postgres --tail 30"
} else {
    foreach ($svc in $services) {
        Write-Ok "$svc ist healthy."
    }
}

# ─── 6. Ergebnis & nächste Schritte ──────────────────────────────────────────

Write-Host ""
Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  Stack läuft. Verbindungsparameter:" -ForegroundColor Green
Write-Host ""
Write-Host "    Source  PostgreSQL  ->  localhost:5433  (sourcedb / sourceuser)" -ForegroundColor White
Write-Host "    Dest    PostgreSQL  ->  localhost:5432  (destdb   / destuser  )" -ForegroundColor White
Write-Host "    Dest    MySQL       ->  localhost:3306  (destdb   / destuser  )" -ForegroundColor White
Write-Host ""
Write-Host "  Nächster Schritt: Airbyte starten" -ForegroundColor Cyan
Write-Host "    .\scripts\setup-airbyte.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Oder direkt zum Installations-Guide:" -ForegroundColor Cyan
Write-Host "    docs\installation-guide.md" -ForegroundColor White
Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
