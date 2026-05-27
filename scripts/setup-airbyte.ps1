# setup-airbyte.ps1 – Airbyte herunterladen, konfigurieren und starten
# Aufruf: .\scripts\setup-airbyte.ps1
#
# Was dieses Skript tut:
#   1. Prüft ob das airbyte_net-Netzwerk existiert
#   2. Lädt die offizielle Airbyte docker-compose.yaml herunter
#   3. Ergänzt das airbyte_net-Netzwerk in der Compose-Datei
#   4. Startet Airbyte
#   5. Wartet bis die UI erreichbar ist

$ErrorActionPreference = "Stop"

$AIRBYTE_DIR  = "C:\tools\airbyte"
$AIRBYTE_VER  = "1.3.1"   # Aktuelle stabile Version – ggf. auf https://github.com/airbytehq/airbyte/releases prüfen
$COMPOSE_URL  = "https://raw.githubusercontent.com/airbytehq/airbyte/v$AIRBYTE_VER/docker-compose.yaml"
$COMPOSE_FILE = "$AIRBYTE_DIR\docker-compose.yaml"
$ENV_FILE     = "$AIRBYTE_DIR\.env"

# ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "    [X]  $msg" -ForegroundColor Red }

# ─── Banner ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Airbyte Setup – Campus Next-Gen Data-Hub" -ForegroundColor White
Write-Host "  ==========================================" -ForegroundColor DarkGray
Write-Host ""

# ─── 1. Netzwerk prüfen ──────────────────────────────────────────────────────

Write-Step "Prüfe airbyte_net Netzwerk"

$netExists = docker network ls --filter "name=airbyte_net" --format "{{.Name}}" 2>$null
if ($netExists -ne "airbyte_net") {
    Write-Warn "airbyte_net existiert noch nicht – wird durch 'docker compose up' erstellt."
    Write-Warn "Bitte zuerst .\scripts\install.ps1 ausführen!"
    $answer = Read-Host "Trotzdem fortfahren? (j/N)"
    if ($answer -notin @("j","J","y","Y")) { exit 0 }
} else {
    Write-Ok "airbyte_net Netzwerk gefunden."
}

# ─── 2. Airbyte-Verzeichnis ──────────────────────────────────────────────────

Write-Step "Airbyte-Verzeichnis vorbereiten: $AIRBYTE_DIR"

if (-not (Test-Path $AIRBYTE_DIR)) {
    New-Item -ItemType Directory -Path $AIRBYTE_DIR | Out-Null
    Write-Ok "Verzeichnis erstellt."
} else {
    Write-Ok "Verzeichnis existiert bereits."
}

# ─── 3. docker-compose.yaml herunterladen ────────────────────────────────────

Write-Step "Lade Airbyte docker-compose.yaml (v$AIRBYTE_VER)"

if (Test-Path $COMPOSE_FILE) {
    Write-Warn "docker-compose.yaml existiert bereits. Überspringe Download."
    Write-Warn "Zum Neustart löschen: Remove-Item '$COMPOSE_FILE'"
} else {
    try {
        Invoke-WebRequest -Uri $COMPOSE_URL -OutFile $COMPOSE_FILE -UseBasicParsing
        Write-Ok "docker-compose.yaml heruntergeladen."
    } catch {
        Write-Fail "Download fehlgeschlagen: $_"
        Write-Host ""
        Write-Host "  Manuell herunterladen:" -ForegroundColor Yellow
        Write-Host "  1. https://github.com/airbytehq/airbyte/releases/tag/v$AIRBYTE_VER" -ForegroundColor Gray
        Write-Host "  2. Source code (zip) herunterladen und entpacken" -ForegroundColor Gray
        Write-Host "  3. docker-compose.yaml nach $AIRBYTE_DIR kopieren" -ForegroundColor Gray
        exit 1
    }
}

# ─── 4. airbyte_net in docker-compose.yaml eintragen ─────────────────────────

Write-Step "Konfiguriere airbyte_net Netzwerk in Airbyte-Compose"

$content = Get-Content $COMPOSE_FILE -Raw

# Prüfen ob airbyte_net schon eingetragen ist
if ($content -match "airbyte_net") {
    Write-Ok "airbyte_net bereits eingetragen – überspringe."
} else {
    # Netzwerk-Deklaration am Ende der networks-Sektion hinzufügen
    $networkBlock = @"

  airbyte_net:
    external: true
"@

    # Am Ende der Datei unter 'networks:' eintragen
    if ($content -match "(?s)(^networks:.*?)(\n\w|\z)") {
        $content = $content -replace "(^networks:[\s\S]*?)(\n[a-z]|\z)", "`$1$networkBlock`$2"
        Set-Content -Path $COMPOSE_FILE -Value $content -NoNewline
        Write-Ok "airbyte_net zur networks-Sektion hinzugefügt."
    } else {
        # Einfach ans Ende anhängen
        Add-Content -Path $COMPOSE_FILE -Value "`nnetworks:`n  airbyte_net:`n    external: true"
        Write-Ok "airbyte_net ans Ende der Datei hinzugefügt."
    }
}

# ─── 5. Airbyte .env erstellen ───────────────────────────────────────────────

Write-Step "Airbyte .env prüfen"

if (-not (Test-Path $ENV_FILE)) {
    # Minimale .env für Airbyte erstellen
    @"
# Airbyte Konfiguration
AIRBYTE_VERSION=$AIRBYTE_VER
API_URL=/api/v1/
TRACKING_STRATEGY=logging
AIRBYTE_ROLE=
"@ | Set-Content -Path $ENV_FILE
    Write-Ok ".env erstellt."
} else {
    Write-Ok ".env existiert bereits."
}

# ─── 6. Airbyte starten ──────────────────────────────────────────────────────

Write-Step "Airbyte starten (dauert ~3-5 Minuten)"

Push-Location $AIRBYTE_DIR
try {
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "docker compose up fehlgeschlagen."
        exit 1
    }
    Write-Ok "Airbyte-Container gestartet."
} finally {
    Pop-Location
}

# ─── 7. Auf UI warten ────────────────────────────────────────────────────────

Write-Step "Warte bis Airbyte UI erreichbar ist (http://localhost:8000)"

$maxWaitSec = 300
$interval   = 10
$elapsed    = 0

while ($elapsed -lt $maxWaitSec) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8000" -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -lt 500) { break }
    } catch { }

    Write-Host "    Warte... ($elapsed/$maxWaitSec s)" -ForegroundColor DarkGray
    Start-Sleep -Seconds $interval
    $elapsed += $interval
}

if ($elapsed -ge $maxWaitSec) {
    Write-Warn "Timeout – Airbyte UI noch nicht erreichbar."
    Write-Warn "Manuell prüfen: http://localhost:8000 (ggf. noch etwas warten)"
    Write-Warn "Logs: docker logs airbyte-webapp --tail 30"
} else {
    Write-Ok "Airbyte UI ist erreichbar!"
}

# ─── 8. Ergebnis ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ═══════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  Airbyte läuft!" -ForegroundColor Green
Write-Host ""
Write-Host "    UI:  http://localhost:8000" -ForegroundColor White
Write-Host "    API: http://localhost:8001/api/v1/" -ForegroundColor White
Write-Host "    Login: airbyte / password" -ForegroundColor White
Write-Host ""
Write-Host "  Nächste Schritte:" -ForegroundColor Cyan
Write-Host "    -> Sources konfigurieren (Host: hso_source_postgres, Port: 5432)" -ForegroundColor White
Write-Host "    -> Details: docs\installation-guide.md (Abschnitt 6)" -ForegroundColor White
Write-Host "  ═══════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
