# Installationsanleitung – Campus Next-Gen Data-Hub

> **Für wen:** Alle Projektmitglieder (Timo + Kommilitonen)  
> **Zeitaufwand:** ca. 15–20 Minuten  
> **Betriebssystem:** Windows 10/11

---

## Inhaltsverzeichnis

1. [Voraussetzungen installieren](#1-voraussetzungen-installieren)
2. [Repo klonen](#2-repo-klonen)
3. [Automatische Installation (empfohlen)](#3-automatische-installation-empfohlen)
4. [Manuelle Installation](#4-manuelle-installation)
5. [Airbyte aufsetzen](#5-airbyte-aufsetzen)
6. [Erster Airbyte-Test](#6-erster-airbyte-test)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Voraussetzungen installieren

### 1.1 Docker Desktop

1. Download: https://www.docker.com/products/docker-desktop/
2. Installieren und **Docker Desktop starten**
3. Prüfen: Rechte Maustaste auf Docker-Icon in der Taskleiste → "Docker Desktop is running"

> **Wichtig:** Docker Desktop muss laufen, bevor die Skripte ausgeführt werden.

### 1.2 Git

1. Download: https://git-scm.com/download/win
2. Installer ausführen (alle Standardoptionen belassen)
3. Prüfen in PowerShell: `git --version`

### 1.3 Python (für Szenarien 3 & 4)

1. Download: https://www.python.org/downloads/ (≥ 3.11)
2. Installer ausführen → **"Add Python to PATH" aktivieren!**
3. Prüfen: `python --version`

---

## 2. Repo klonen

PowerShell öffnen (Win+X → "Windows PowerShell" oder "Terminal"):

```powershell
git clone <repo-url>
cd INFM_Airbyte
```

---

## 3. Automatische Installation (empfohlen)

Das Installations-Skript übernimmt alles automatisch:

```powershell
.\scripts\install.ps1
```

Das Skript:
- prüft alle Voraussetzungen (Docker, Git, Python)
- erstellt `.env` aus `.env.example`
- lädt Docker-Images herunter
- startet die drei Datenbank-Container
- wartet bis alle Container gesund sind
- zeigt Verbindungsinfos an

**Erfolgreich, wenn die Ausgabe endet mit:**
```
✓ Stack läuft. Alle Container sind healthy.
```

Danach weiter mit [Schritt 5: Airbyte aufsetzen](#5-airbyte-aufsetzen).

---

## 4. Manuelle Installation

Falls das automatische Skript nicht funktioniert:

```powershell
# 1. Konfigurationsdatei anlegen
Copy-Item .env.example .env
# Passwörter nach Bedarf in .env anpassen

# 2. Docker-Images vorab laden (spart Zeit)
docker compose pull

# 3. Stack starten
docker compose up -d

# 4. Status prüfen (warten bis alle "healthy" sind)
docker compose ps
```

---

## 5. Airbyte aufsetzen

Airbyte laeuft ueber `abctl` (offizielles Airbyte CLI) in einem lokalen Kubernetes-Cluster (Kind) innerhalb von Docker Desktop.

```powershell
.\scripts\setup-airbyte.ps1
```

Das Skript:
- laedt `abctl.exe` nach `C:\tools\airbyte\` und fuegt es zum PATH hinzu
- fragt nach Low-Resource-Mode (empfohlen bei weniger als 6 GB freiem RAM)
- startet `abctl local install` (interaktiv: E-Mail + Organisations-Name eingeben)
- zeigt die Login-Credentials an

Die Installation dauert **5–10 Minuten** (Container-Downloads).

**Status pruefen:**

```powershell
abctl local status
```

**Airbyte UI oeffnen:** http://localhost:8000

**Login-Credentials anzeigen:**

```powershell
abctl local credentials
```

> Ausgabe zeigt E-Mail, generiertes Passwort, Client-ID und Client-Secret.

Weitere Details: [docs/airbyte-setup.md](airbyte-setup.md)

---

## 6. Erster Airbyte-Test

### Source anlegen (PostgreSQL mit Testdaten)

1. Airbyte UI → **Sources** → `+ New Source`
2. Typ: **PostgreSQL**
3. Felder ausfuellen:

| Feld | Wert |
|------|------|
| Source name | `HSO Source PostgreSQL` |
| Host | `host.docker.internal` |
| Port | `5433` |
| Database | `sourcedb` |
| Username | `sourceuser` |
| Password | `sourcepassword` |
| SSL mode | `disable` |

4. **Test connection** → sollte gruen werden
5. **Set up source**

> **Warum `host.docker.internal`?** Airbybes Connector-Container laufen in Kind (Kubernetes in Docker) und erreichen den Host-Rechner ueber diesen DNS-Namen.

### Destination anlegen (PostgreSQL Ziel)

1. **Destinations** → `+ New Destination`
2. Typ: **PostgreSQL**

| Feld | Wert |
|------|------|
| Destination name | `HSO Dest PostgreSQL` |
| Host | `host.docker.internal` |
| Port | `5432` |
| Database | `destdb` |
| Username | `destuser` |
| Password | `destpassword` |

### Connection anlegen & syncen

1. **Connections** → `+ New Connection`
2. Source: `HSO Source PostgreSQL`
3. Destination: `HSO Dest PostgreSQL`
4. Streams auswaehlen: `fm_gebaeude`, `hso_students`, `k_plz`
5. Sync mode: **Full Refresh | Overwrite**
6. **Save and sync now** → Ergebnis im Dashboard beobachten

---

## 7. Troubleshooting

### Container startet nicht / bleibt unhealthy

```powershell
# Logs des betroffenen Containers anzeigen
docker logs hso_source_postgres --tail 50
docker logs hso_dest_mysql --tail 50
```

Haeufige Ursachen:
- **Port belegt:** Ein anderer Dienst nutzt Port 5433, 5434 oder 3306. In `.env` und `docker-compose.yml` anderen Port eintragen.
- **Volumes aus altem Start:** `.\scripts\stop.ps1 -v` → dann neu starten

### Airbyte laeuft nicht / UI nicht erreichbar

```powershell
# Status pruefen
abctl local status

# Logs anzeigen
abctl local logs

# Neustart (bei haengenden Kind-Containern)
abctl local uninstall
abctl local install
```

### Airbyte-Connector kann DBs nicht erreichen

Airbyte-Connector-Container kommunizieren ueber `host.docker.internal` mit den Datenbanken. Pruefen:

```powershell
# DNS-Aufloesung testen (muss 192.168.65.x liefern)
docker run --rm alpine nslookup host.docker.internal

# DB-Port vom Host aus pruefen
Test-NetConnection -ComputerName localhost -Port 5433  # Source PG
Test-NetConnection -ComputerName localhost -Port 5434  # Dest PG
Test-NetConnection -ComputerName localhost -Port 3306  # Dest MySQL
```

Falls die Ports nicht erreichbar sind: DB-Stack laeuft nicht → `.\scripts\start.ps1`

### Airbyte: Passwortfehler bei Dest PostgreSQL (password authentication failed)

Ursache: Auf Port 5432 laeuft bereits ein nativer Windows-PostgreSQL-Dienst (`postgres.exe`).
Externe Verbindungen via `host.docker.internal:5432` landen dort statt bei `hso_dest_postgres`.

Pruefen ob ein zweiter Prozess auf Port 5432 lauscht:

```powershell
netstat -ano | findstr :5432
# Wenn zwei verschiedene PIDs erscheinen:
tasklist /fi "PID eq <pid>"   # postgres.exe = nativer Windows-Dienst
```

**Loesung:** Dest PostgreSQL laeuft deshalb auf Port **5434** (statt 5432).
In der Airbyte UI immer Port `5434` verwenden.

---

### Testdaten wurden nicht geladen (source-postgres ist leer)

Die COPY-Befehle laufen nur beim **ersten** Container-Start. Falls der Container bereits existiert, laufen die Init-Scripts nicht erneut.

```powershell
# Volume löschen und neu starten (Daten gehen verloren!)
docker compose down -v
docker compose up -d
```

### Python-Pakete fehlen

```powershell
pip install requests psycopg2-binary
```

---

## Verbindungsübersicht (Spickzettel)

| Service | Für DB-Tools (lokal) | Für Airbyte (in der UI eintragen) |
|---------|----------------------|-----------------------------------|
| Source PostgreSQL | `localhost:5433` | `host.docker.internal:5433` |
| Dest PostgreSQL | `localhost:5434` | `host.docker.internal:5434` |
| Dest MySQL | `localhost:3306` | `host.docker.internal:3306` |
| Airbyte UI | http://localhost:8000 | – |
| PostgREST (Szenario 6) | http://localhost:3000 | – |

**Datenbank-Credentials** (Standard, änderbar in `.env`):

| DB | User | Passwort | Datenbank |
|----|------|----------|-----------|
| Source PG | `sourceuser` | `sourcepassword` | `sourcedb` |
| Dest PG | `destuser` | `destpassword` | `destdb` |
| Dest MySQL | `destuser` | `destpassword` | `destdb` |
