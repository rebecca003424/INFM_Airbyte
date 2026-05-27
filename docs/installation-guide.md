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

Airbyte wird **außerhalb des Repos** in einem eigenen Verzeichnis betrieben:

```powershell
.\scripts\setup-airbyte.ps1
```

Das Skript:
- erstellt `C:\tools\airbyte\`
- lädt die offizielle Airbyte `docker-compose.yaml` herunter
- hängt das gemeinsame Netzwerk `airbyte_net` ein
- startet den Airbyte-Stack

Warten bis alle Airbyte-Container healthy sind (~3–5 Minuten):

```powershell
docker ps --filter "name=airbyte" --format "table {{.Names}}\t{{.Status}}"
```

**Airbyte UI öffnen:** http://localhost:8000  
**Login:** `airbyte` / `password`

---

## 6. Erster Airbyte-Test

### Source anlegen (PostgreSQL mit Testdaten)

1. Airbyte UI → **Sources** → `+ New Source`
2. Typ: **PostgreSQL**
3. Felder ausfüllen:

| Feld | Wert |
|------|------|
| Source name | `HSO Source PostgreSQL` |
| Host | `hso_source_postgres` |
| Port | `5432` |
| Database | `sourcedb` |
| Username | `sourceuser` |
| Password | `sourcepassword` |
| SSL mode | `disable` |

4. **Test connection** → sollte grün werden
5. **Set up source**

### Destination anlegen (PostgreSQL Ziel)

1. **Destinations** → `+ New Destination`
2. Typ: **PostgreSQL**

| Feld | Wert |
|------|------|
| Destination name | `HSO Dest PostgreSQL` |
| Host | `hso_dest_postgres` |
| Port | `5432` |
| Database | `destdb` |
| Username | `destuser` |
| Password | `destpassword` |

### Connection anlegen & syncen

1. **Connections** → `+ New Connection`
2. Source: `HSO Source PostgreSQL`
3. Destination: `HSO Dest PostgreSQL`
4. Streams auswählen: `fm_gebaeude`, `hso_students`, `k_plz`
5. Sync mode: **Full refresh | Overwrite**
6. **Save and sync** → Ergebnis im Dashboard beobachten

---

## 7. Troubleshooting

### Container startet nicht / bleibt unhealthy

```powershell
# Logs des betroffenen Containers anzeigen
docker logs hso_source_postgres --tail 50
docker logs hso_dest_mysql --tail 50
```

Häufige Ursachen:
- **Port belegt:** Ein anderer Dienst nutzt Port 5432, 5433 oder 3306. In `.env` und `docker-compose.yml` anderen Port eintragen.
- **Volumes aus altem Start:** `.\scripts\stop.ps1 -v` → dann neu starten

### Airbyte-Container können DBs nicht erreichen

```powershell
# Prüfen ob alle im gleichen Netzwerk sind
docker network inspect airbyte_net
```

Alle drei DB-Container (`hso_source_postgres`, `hso_dest_postgres`, `hso_dest_mysql`) und die Airbyte-Worker müssen in der Liste erscheinen.

Falls Airbyte-Container fehlen → `setup-airbyte.ps1` erneut ausführen.

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

| Service | Für DB-Tools (lokal) | Für Airbyte (Container-intern) |
|---------|----------------------|---------------------------------|
| Source PostgreSQL | `localhost:5433` | `hso_source_postgres:5432` |
| Dest PostgreSQL | `localhost:5432` | `hso_dest_postgres:5432` |
| Dest MySQL | `localhost:3306` | `hso_dest_mysql:3306` |
| Airbyte UI | http://localhost:8000 | – |
| PostgREST (Szenario 6) | http://localhost:3000 | – |

**Datenbank-Credentials** (Standard, änderbar in `.env`):

| DB | User | Passwort | Datenbank |
|----|------|----------|-----------|
| Source PG | `sourceuser` | `sourcepassword` | `sourcedb` |
| Dest PG | `destuser` | `destpassword` | `destdb` |
| Dest MySQL | `destuser` | `destpassword` | `destdb` |
