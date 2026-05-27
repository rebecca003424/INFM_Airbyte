# Campus Next-Gen Data-Hub – Airbyte Evaluation

**Informatik Master SoSe 2026** | Evaluierung von [Airbyte](https://airbyte.com/) als ETL/Integrations-Tool zur Ablösung von Talend in der Hochschul-IT. Alle Dienste laufen lokal in Docker Desktop.

---

## Architektur

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Desktop                        │
│                                                          │
│  ┌──────────────────┐        ┌───────────────────────┐  │
│  │  source-postgres  │        │       Airbyte         │  │
│  │  (Testdaten)      │◄──────►│  UI: localhost:8000   │  │
│  │  localhost:5433   │        │  API: localhost:8001  │  │
│  └──────────────────┘        └────────┬──────────────┘  │
│                                        │                  │
│  ┌──────────────────┐  ┌──────────────▼────────────┐    │
│  │   dest-mysql      │  │     dest-postgres          │   │
│  │   localhost:3306  │  │     localhost:5432         │   │
│  └──────────────────┘  └───────────────────────────┘    │
│                                                          │
│  Netzwerk: airbyte_net (alle Container verbunden)        │
└─────────────────────────────────────────────────────────┘
```

**Source** (`source-postgres`) ist vorgeladen mit anonymisierten Hochschuldaten:

| Tabelle | Inhalt |
|---------|--------|
| `hso_students` | Studierende (anonymisiert, ~1.500 Einträge) |
| `fm_gebaeude` | Gebäude der Hochschule Offenburg (27) |
| `fm_inst` | Institute & Organisationseinheiten |
| `fm_stamm` | Raumstammdaten (verknüpft Gebäude + Institut) |
| `k_plz` | PLZ-Verzeichnis Deutschland (~37.500) |

**6 Testszenarien** → [docs/testszenarien.md](docs/testszenarien.md):

| # | Szenario | Kern-Feature |
|---|----------|--------------|
| 1 | Testdaten einspielen | DB-Connector, File-Connector |
| 2 | Facility Management | Sync + Denormalisierung |
| 3 | Bilder als BLOB | BYTEA-Handling, Python-Scripts |
| 4 | Studenten/Personal Mapping | Account-Generator, dbt |
| 5 | IdM System (Incremental Sync) | Incremental + Dedup |
| 6 | Web APIs (REST + SOAP) | HTTP-Connector, PostgREST |

---

## Schnellstart

> Ausführliche Anleitung (inkl. Troubleshooting): **[docs/installation-guide.md](docs/installation-guide.md)**

### Schritt 1: Voraussetzungen installieren

| Tool | Download |
|------|----------|
| Docker Desktop | https://www.docker.com/products/docker-desktop/ |
| Git | https://git-scm.com/download/win |
| Python ≥ 3.11 | https://www.python.org/downloads/ |

### Schritt 2: Repo klonen

```powershell
git clone <repo-url>
cd INFM_Airbyte
```

### Schritt 3: Alles automatisch installieren

```powershell
.\scripts\install.ps1
```

Startet alle drei Datenbank-Container und lädt die Testdaten automatisch.

### Schritt 4: Airbyte einrichten

```powershell
.\scripts\setup-airbyte.ps1
```

Lädt Airbyte herunter, verbindet es mit dem gemeinsamen Netzwerk und startet die UI.  
**Airbyte UI:** http://localhost:8000 (Login: `airbyte` / `password`)

### Schritt 5: Testszenarien durchführen

→ **[docs/testszenarien.md](docs/testszenarien.md)**

---

## Projektstruktur

```
INFM_Airbyte/
├── docker-compose.yml          ← DB-Stack (source + dest)
├── .env.example                ← Vorlage für Umgebungsvariablen
├── .gitignore
│
├── sql/
│   └── source/
│       ├── 00_tables.sql       ← Tabellen-Schema für source-postgres
│       ├── 01_load_data.sql    ← COPY-Befehle (lädt CSV-Testdaten)
│       └── data/               ← CSV-Dateien (werden per COPY geladen)
│           ├── hso_students.csv
│           ├── fm_gebaeude.csv
│           ├── fm_inst.csv
│           └── k_plz.csv
│
├── data/
│   ├── csv/k_res/              ← k_res1–13 CSV-Dateien (für File-Connector)
│   └── json/                   ← JSON-Dateien (fm_rna, hso_personal)
│
├── docs/
│   ├── airbyte-setup.md        ← Airbyte installieren & konfigurieren
│   └── testszenarien.md        ← Konkrete Testfälle
│
└── scripts/
    ├── start.ps1               ← Stack starten
    └── stop.ps1                ← Stack stoppen (-v für vollständigen Reset)
```

---

## Verbindungsparameter

### Für DB-Tools (DBeaver, TablePlus, etc.)

| Service | Host | Port | DB | User | Password |
|---------|------|------|----|------|----------|
| Source PostgreSQL | `localhost` | `5433` | `sourcedb` | `sourceuser` | `sourcepassword` |
| Dest PostgreSQL | `localhost` | `5432` | `destdb` | `destuser` | `destpassword` |
| Dest MySQL | `localhost` | `3306` | `destdb` | `destuser` | `destpassword` |

### Für Airbyte (Container-zu-Container)

| Service | Host | Port |
|---------|------|------|
| Source PostgreSQL | `hso_source_postgres` | `5432` |
| Dest PostgreSQL | `hso_dest_postgres` | `5432` |
| Dest MySQL | `hso_dest_mysql` | `3306` |

---

## Nützliche Befehle

```powershell
# Stack-Status prüfen
docker compose ps

# Logs anzeigen
docker compose logs -f source-postgres

# In source-postgres einloggen
docker exec -it hso_source_postgres psql -U sourceuser -d sourcedb

# Vollständiger Reset (alle Daten löschen)
.\scripts\stop.ps1 -v
```
