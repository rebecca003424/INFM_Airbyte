# Airbyte lokal aufsetzen (Docker Desktop)

## Voraussetzungen

- Docker Desktop läuft
- Custom-DB-Stack ist gestartet (`.\scripts\start.ps1`)
- Netzwerk `airbyte_net` existiert (`docker network ls | findstr airbyte_net`)

---

## 1. Airbyte herunterladen

```powershell
# Arbeitsverzeichnis ausserhalb des Repos wählen (z. B. C:\tools\airbyte)
mkdir C:\tools\airbyte
cd C:\tools\airbyte

# Offizielles Run-Skript herunterladen
curl -O https://raw.githubusercontent.com/airbytehq/airbyte/master/run-ab-platform.sh
```

Alternativ: ZIP direkt von [github.com/airbytehq/airbyte/releases](https://github.com/airbytehq/airbyte/releases) → `Source code (zip)`.

---

## 2. Airbyte ins gleiche Netzwerk einbinden

In der heruntergeladenen `docker-compose.yaml` von Airbyte am Ende ergänzen:

```yaml
# Externe Netzwerk-Referenz hinzufügen
networks:
  airbyte_internal:
  airbyte_public:
  airbyte_net:          # <-- NEU
    external: true      # <-- NEU

# Bei jedem Service, der auf die DBs zugreifen muss (airbyte-worker, airbyte-server),
# das Netzwerk airbyte_net in der networks-Liste ergänzen:
#   networks:
#     - airbyte_internal
#     - airbyte_net
```

---

## 3. Airbyte starten

```powershell
cd C:\tools\airbyte
docker compose up -d
```

Warten bis alle Container `healthy` sind (~2-3 Minuten):

```powershell
docker compose ps
```

UI öffnen: **http://localhost:8000**  
Standard-Login: `airbyte / password`

---

## 4. Sources in Airbyte konfigurieren

### 4.1 Source: PostgreSQL (Testdaten)

| Feld | Wert |
|------|------|
| Host | `host.docker.internal` |
| Port | `5433` |
| Database | `sourcedb` |
| Username | `sourceuser` |
| Password | `sourcepassword` |
| SSL | Disabled |

> **Warum `host.docker.internal`?** Airbyte spawnt Connector-Container dynamisch. Diese können nicht direkt auf Container-Namen im `airbyte_net` zugreifen, aber `host.docker.internal` löst immer zur Host-IP auf. Die DBs sind auf Host-Ports exponiert (5433/5432/3306).

---

## 5. Destinations konfigurieren

### 5.1 Destination: PostgreSQL

| Feld | Wert |
|------|------|
| Host | `host.docker.internal` |
| Port | `5432` |
| Database | `destdb` |
| Username | `destuser` |
| Password | `destpassword` |

### 5.2 Destination: MySQL

| Feld | Wert |
|------|------|
| Host | `host.docker.internal` |
| Port | `3306` |
| Database | `destdb` |
| Username | `destuser` |
| Password | `destpassword` |

---

## 6. Connection anlegen & Sync starten

1. **Sources** → `+ New Source` → Typ wählen → Verbindung testen
2. **Destinations** → `+ New Destination` → Typ wählen → Verbindung testen
3. **Connections** → `+ New Connection` → Source & Destination auswählen
4. Streams auswählen (z. B. `fm_gebaeude`, `hso_students`, `k_plz`)
5. Sync-Modus wählen:
   - `Full Refresh | Overwrite` – Tabelle komplett neu schreiben
   - `Incremental | Append` – nur neue Zeilen anhängen
6. **Save & Sync** → Sync-Status im Dashboard beobachten

---

## 7. Verfügbare Testszenarien

| Szenario | Source | Destination | Tabellen |
|----------|--------|-------------|----------|
| PG → PG  | source-postgres | dest-postgres | alle |
| PG → MySQL | source-postgres | dest-mysql | alle |
| CSV → PG | Local File / S3 | dest-postgres | k_res*.csv |
| CSV → MySQL | Local File / S3 | dest-mysql | k_res*.csv |

CSV-Dateien für File-Connector: `data/csv/k_res/`

---

## Nützliche Befehle

```powershell
# Alle laufenden Container anzeigen
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Logs eines Containers
docker logs hso_source_postgres --tail 50

# Direkt in source-postgres verbinden
docker exec -it hso_source_postgres psql -U sourceuser -d sourcedb

# Datensätze prüfen
# \dt             -- alle Tabellen
# SELECT COUNT(*) FROM hso_students;
# SELECT COUNT(*) FROM k_plz;
```
