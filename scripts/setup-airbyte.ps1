# setup-airbyte.ps1 - Airbyte herunterladen, konfigurieren und starten
# Aufruf: .\scripts\setup-airbyte.ps1
#
# Was dieses Skript tut:
#   1. Prueft ob das airbyte_net-Netzwerk existiert (install.ps1 muss zuerst laufen)
#   2. Laedt docker-compose.yaml UND .env von Airbyte GitHub herunter
#   3. Erstellt docker-compose.override.yaml fuer die airbyte_net-Einbindung
#   4. Startet Airbyte
#   5. Wartet bis die UI erreichbar ist

$ErrorActionPreference = "Stop"

$AIRBYTE_DIR   = "C:\tools\airbyte"
$COMPOSE_FILE  = "$AIRBYTE_DIR\docker-compose.yaml"
$OVERRIDE_FILE = "$AIRBYTE_DIR\docker-compose.override.yaml"
$ENV_FILE      = "$AIRBYTE_DIR\.env"

# Airbyte hat docker-compose ins Repo airbyte-platform ausgelagert und
# bei v0.63.13 eingefroren (docker-compose wird durch abctl abgeloest).
# Quelle: run-ab-platform.sh in airbytehq/airbyte
$AIRBYTE_VER = "0.63.13"
$BASE_URL    = "https://raw.githubusercontent.com/airbytehq/airbyte-platform/v$AIRBYTE_VER"

# --- Hilfsfunktionen ---------------------------------------------------------

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "    [X]  $msg" -ForegroundColor Red }

function Download-File([string]$url, [string]$dest) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        return $true
    } catch {
        Write-Fail "Download fehlgeschlagen ($url): $_"
        return $false
    }
}

# --- Banner ------------------------------------------------------------------

Write-Host ""
Write-Host "  Airbyte Setup - Campus Next-Gen Data-Hub" -ForegroundColor White
Write-Host "  ==========================================" -ForegroundColor DarkGray
Write-Host ""

# --- 1. Netzwerk pruefen -----------------------------------------------------

Write-Step "Pruefe airbyte_net Netzwerk"

# docker network ls --filter macht Substring-Matching, daher exakt in der Ausgabe pruefen
$networks = docker network ls --format "{{.Name}}" 2>$null
if ($networks -notcontains "airbyte_net") {
    Write-Warn "airbyte_net existiert noch nicht."
    Write-Warn "Bitte zuerst .\scripts\install.ps1 ausfuehren, dann dieses Skript erneut starten."
    $answer = Read-Host "Trotzdem fortfahren? (j/N)"
    if ($answer -notin @("j","J","y","Y")) { exit 0 }
} else {
    Write-Ok "airbyte_net Netzwerk gefunden."
}

# --- 2. Airbyte-Verzeichnis --------------------------------------------------

Write-Step "Airbyte-Verzeichnis vorbereiten: $AIRBYTE_DIR"

if (-not (Test-Path $AIRBYTE_DIR)) {
    New-Item -ItemType Directory -Path $AIRBYTE_DIR | Out-Null
    Write-Ok "Verzeichnis erstellt."
} else {
    Write-Ok "Verzeichnis existiert bereits."
}

# --- 3. Alle Airbyte-Dateien herunterladen -----------------------------------
# Airbyte benoetigt neben docker-compose.yaml noch .env, flags.yml und
# die Temporal-Konfiguration. Ohne diese Dateien schlaegt der Start fehl.

Write-Step "Lade Airbyte-Dateien herunter (v$AIRBYTE_VER)"

$filesToDownload = @(
    @{ Src = "docker-compose.yaml";                        Dst = "$AIRBYTE_DIR\docker-compose.yaml" },
    @{ Src = ".env";                                       Dst = "$AIRBYTE_DIR\.env"                },
    @{ Src = "flags.yml";                                  Dst = "$AIRBYTE_DIR\flags.yml"           },
    @{ Src = "temporal/dynamicconfig/development.yaml";    Dst = "$AIRBYTE_DIR\temporal\dynamicconfig\development.yaml" }
)

if (Test-Path $COMPOSE_FILE) {
    Write-Warn "docker-compose.yaml existiert bereits - ueberspringe alle Downloads."
    Write-Warn "Neu herunterladen: Remove-Item -Recurse '$AIRBYTE_DIR' und Skript erneut starten."
} else {
    $anyFailed = $false
    foreach ($file in $filesToDownload) {
        $dir = Split-Path $file.Dst -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

        $ok = Download-File "$BASE_URL/$($file.Src)" $file.Dst
        if ($ok) {
            Write-Ok "$($file.Src)"
        } else {
            $anyFailed = $true
        }
    }
    if ($anyFailed) {
        Write-Host ""
        Write-Host "  Manueller Download:" -ForegroundColor Yellow
        Write-Host "  1. https://github.com/airbytehq/airbyte-platform/releases/tag/v$AIRBYTE_VER" -ForegroundColor Gray
        Write-Host "  2. Source code (zip) herunterladen und nach $AIRBYTE_DIR entpacken" -ForegroundColor Gray
        exit 1
    }
}

# --- 5. Override-Datei fuer airbyte_net erstellen ----------------------------
# Statt die heruntergeladene docker-compose.yaml zu patchen, verwenden wir
# docker-compose.override.yaml. Docker Compose liest diese automatisch ein
# und merged sie mit der Haupt-Datei - so bleibt docker-compose.yaml sauber.

Write-Step "Erstelle docker-compose.override.yaml fuer airbyte_net"

$overrideContent = @"
# Airbyte connector containers greifen auf die Custom-DBs ueber
# host.docker.internal zu (nicht ueber Container-Namen), weil die
# Connector-Container dynamisch gespawnt werden und nicht automatisch
# im airbyte_net landen. host.docker.internal loest auf Windows
# Docker Desktop immer zur Host-IP auf.
#
# DB-Verbindung in Airbyte daher mit:
#   Host: host.docker.internal
#   Port: 5433 (Source PG) / 5432 (Dest PG) / 3306 (Dest MySQL)
"@

Set-Content -Path $OVERRIDE_FILE -Value $overrideContent
Write-Ok "docker-compose.override.yaml erstellt."

# --- 5b. Login-Credentials setzen --------------------------------------------
# BASIC_AUTH_USERNAME und BASIC_AUTH_PASSWORD stehen in C:\tools\airbyte\.env.
# Standard: airbyte / password - das sollte fuer lokale Entwicklung geaendert werden.

Write-Step "Airbyte Login-Credentials konfigurieren"

$envContent = Get-Content $ENV_FILE -Raw

$currentUser = if ($envContent -match 'BASIC_AUTH_USERNAME=(.+)') { $Matches[1].Trim() } else { "airbyte" }
$currentPass = if ($envContent -match 'BASIC_AUTH_PASSWORD=(.+)') { $Matches[1].Trim() } else { "password" }

Write-Host "    Aktuell: $currentUser / $currentPass" -ForegroundColor DarkGray
Write-Host "    Eingabe leer lassen = Standardwert behalten." -ForegroundColor DarkGray
Write-Host ""

$newUser = Read-Host "    Benutzername [$currentUser]"
$newPass = Read-Host "    Passwort    [$currentPass]"

if ([string]::IsNullOrWhiteSpace($newUser)) { $newUser = $currentUser }
if ([string]::IsNullOrWhiteSpace($newPass)) { $newPass = $currentPass }

$envContent = $envContent -replace 'BASIC_AUTH_USERNAME=.+', "BASIC_AUTH_USERNAME=$newUser"
$envContent = $envContent -replace 'BASIC_AUTH_PASSWORD=.+', "BASIC_AUTH_PASSWORD=$newPass"
Set-Content -Path $ENV_FILE -Value $envContent -NoNewline
Write-Ok "Credentials gesetzt: $newUser / $('*' * $newPass.Length)"

# --- 6. Airbyte starten ------------------------------------------------------

Write-Step "Airbyte starten (dauert ca. 3-5 Minuten beim ersten Mal)"

Push-Location $AIRBYTE_DIR
try {
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "docker compose up fehlgeschlagen."
        Write-Warn "Logs pruefen: docker compose logs --tail 30"
        exit 1
    }
    Write-Ok "Airbyte-Container gestartet."
} finally {
    Pop-Location
}

# --- 7. Auf UI warten --------------------------------------------------------

Write-Step "Warte bis Airbyte UI erreichbar ist (http://localhost:8000)"

$maxWaitSec = 300
$interval   = 10
$elapsed    = 0

while ($elapsed -lt $maxWaitSec) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8000" -TimeoutSec 5 `
            -UseBasicParsing -ErrorAction SilentlyContinue
        if ($null -ne $response -and $response.StatusCode -lt 500) { break }
    } catch { }

    Start-Sleep -Seconds $interval
    $elapsed += $interval
    Write-Host "    Warte... ($elapsed/$maxWaitSec s)" -ForegroundColor DarkGray
}

if ($elapsed -ge $maxWaitSec) {
    Write-Warn "Timeout - Airbyte UI noch nicht erreichbar."
    Write-Warn "Manuell pruefen: http://localhost:8000 (ggf. noch 1-2 Minuten warten)"
    Write-Warn "Logs: docker compose -f $AIRBYTE_DIR\docker-compose.yaml logs --tail 30"
} else {
    Write-Ok "Airbyte UI ist erreichbar!"
}

# --- 8. Ergebnis -------------------------------------------------------------

Write-Host ""
Write-Host "  ===========================================================" -ForegroundColor DarkGray
Write-Host "  Airbyte laeuft!" -ForegroundColor Green
Write-Host ""
Write-Host "    UI:    http://localhost:8000" -ForegroundColor White
Write-Host "    API:   http://localhost:8001/api/v1/" -ForegroundColor White
Write-Host "    Login: $newUser / (dein Passwort)" -ForegroundColor White
Write-Host ""
Write-Host "  DB-Verbindung in Airbyte (host.docker.internal verwenden!):" -ForegroundColor Cyan
Write-Host "    Source PG  ->  Host: host.docker.internal  Port: 5433" -ForegroundColor White
Write-Host "    Dest   PG  ->  Host: host.docker.internal  Port: 5432" -ForegroundColor White
Write-Host "    Dest MySQL ->  Host: host.docker.internal  Port: 3306" -ForegroundColor White
Write-Host ""
Write-Host "  Details: docs\installation-guide.md (Abschnitt 6)" -ForegroundColor Cyan
Write-Host "  ===========================================================" -ForegroundColor DarkGray
Write-Host ""
