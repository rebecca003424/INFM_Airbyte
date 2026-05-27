# Testszenarien – Campus Next-Gen Data-Hub (SoSe 2026)

Ziel: Evaluierung von Airbyte als ETL-Tool für die Hochschul-IT (Ersatz für Talend).

---

## Übersicht der Testdaten

| Datei / Tabelle | Format | Inhalt | Zeilen |
|-----------------|--------|--------|--------|
| `hso_students` | Pipe-CSV | Studierende (anonym.) | ~1.500 |
| `fm_gebaeude` | CSV | Gebäude der Hochschule | 27 |
| `fm_inst` | Semikolon-CSV | Institute / Org-Einheiten | ~120 |
| `fm_stamm` | SQL/CSV | Raumstammdaten (geb+inst) | variabel |
| `k_plz` | CSV | PLZ-Verzeichnis Deutschland | ~37.500 |
| `fm_rna.json` | JSON | Raumnutzungsarten | ~50 |
| `k_res*.csv` | Semikolon-CSV | Klassifikations-Lookups | je ~5–20 |
| `hso_accountgenerator.js` | JavaScript | Account-Name-Logik | – |

---

## Airbyte Sync-Modi

| Modus | Liest | Schreibt | Wann verwenden |
|-------|-------|----------|----------------|
| Full Refresh \| Overwrite | Alles | Ersetzt Ziel komplett | Erster Test, kleine Tabellen |
| Full Refresh \| Append | Alles | Haengt an Ziel an | Historisierung ganzer Snapshots |
| Full Refresh \| Overwrite + Deduped | Alles | Ersetzt + dedupliziert | Frischer Stand ohne Duplikate |
| Incremental \| Append | Nur neue Zeilen | Haengt neue Zeilen an | Wachsende Logs, kein Cursor noetig |
| Incremental \| Append + Deduped | Nur neue Zeilen | Haengt an + dedupliziert | IdM-Sync (Szenario 5), Cursor: `updatedat` |

---

## Szenario 1: Einspielen der Testdaten

**Ziel:** Vertrautmachen mit Airbyte, grundlegende Datenbankanbindungen testen.

**Aufgaben:**
- Bestehende Testdaten (k_res*.csv, k_plz, k_abstgv) in MySQL und PostgreSQL laden
- Verschiedene Source-Typen testen: Postgres-Source, File-Connector

**Airbyte-Konfiguration:**

| Parameter | Wert |
|-----------|------|
| Source | `source-postgres` (alle Streams) |
| Destination 1 | `dest-postgres` |
| Destination 2 | `dest-mysql` |
| Sync-Modus | Full Refresh \| Overwrite |

**Prüfung:**
```sql
-- In dest-postgres:
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables ORDER BY n_live_tup DESC;

-- In dest-mysql:
SHOW TABLES;
SELECT COUNT(*) FROM hso_students;
```

---

## Szenario 2: Facility Management

**Ziel:** PostgreSQL-DB mit FM-Tabellen aufbauen; denormalisierte MySQL-Tabelle für Räume erstellen.

**Teilaufgabe A – PostgreSQL FM-DB:**

Tabellen `fm_inst`, `fm_gebaeude`, `fm_stamm` sind in `source-postgres` vorgeladen.

Nach dem Sync nach `dest-postgres` prüfen:
```sql
-- Raumübersicht (Gebäude + Institut + Raum joined)
SELECT s.geb_nr, s.raumnr, g.geb AS gebaeude_name,
       s.flaeche, s.rna_nr, s.kost_nr
FROM fm_stamm s
JOIN fm_gebaeude g ON s.geb_nr = g.geb_nr
ORDER BY s.geb_nr, s.raumnr;
```

**Teilaufgabe B – MySQL Raumtabelle (denormalisiert):**

In Airbyte eine Transformation konfigurieren, die folgende Tabelle in `dest-mysql` erzeugt:

```sql
CREATE TABLE fm_raeume (
    raum_id      VARCHAR(30) PRIMARY KEY,
    raumnr       VARCHAR(20),
    gebaeude     VARCHAR(60),   -- aus fm_gebaeude.geb
    gebaeude_nr  VARCHAR(10),
    institut     VARCHAR(60),   -- aus fm_inst.dname
    flaeche      DECIMAL(14,2),
    kostenstelle VARCHAR(20)
);
```

> **Hinweis:** Airbyte kann Joins nicht direkt ausführen. Optionen:
> - dbt-Transformation nach dem Sync
> - Custom SQL-View in source-postgres, dann syncen
> - Python/SQL-Skript nach dem Sync

---

## Szenario 3: Testdaten für Bilder generieren

**Ziel:** >1.000 Bilder per API abrufen, als BLOB in DB speichern; danach aus DB exportieren.

**API:** https://picsum.photos/200 (liefert zufällige Bilder als JPEG)

**Teilaufgabe A – Bilder in DB laden:**

```python
# scripts/images/load_images.py
import requests, psycopg2, uuid

conn = psycopg2.connect(
    host="localhost", port=5433,
    dbname="sourcedb", user="sourceuser", password="sourcepassword"
)
cur = conn.cursor()
cur.execute("""
    CREATE TABLE IF NOT EXISTS hso_images (
        image_id   SERIAL PRIMARY KEY,
        ext_id     VARCHAR(50),
        data       BYTEA,
        created_at TIMESTAMP DEFAULT NOW()
    )
""")

for i in range(1, 1001):
    resp = requests.get(f"https://picsum.photos/id/{i}/200/200", timeout=10)
    if resp.status_code == 200:
        cur.execute(
            "INSERT INTO hso_images (ext_id, data) VALUES (%s, %s)",
            (str(i), psycopg2.Binary(resp.content))
        )
    if i % 50 == 0:
        conn.commit()
        print(f"{i} Bilder geladen...")

conn.commit()
cur.close()
conn.close()
```

**Teilaufgabe B – Bilder aus DB exportieren:**

```python
# scripts/images/export_images.py
import psycopg2, os

conn = psycopg2.connect(
    host="localhost", port=5433,
    dbname="sourcedb", user="sourceuser", password="sourcepassword"
)
cur = conn.cursor()
cur.execute("SELECT image_id, ext_id, data FROM hso_images")

os.makedirs("data/images", exist_ok=True)
for image_id, ext_id, data in cur.fetchall():
    with open(f"data/images/{ext_id}.png", "wb") as f:
        f.write(bytes(data))

print("Export abgeschlossen.")
conn.close()
```

**Airbyte-Evaluation:** Kann Airbyte BLOB-Felder synchronisieren?
- Source: `source-postgres` Tabelle `hso_images`
- Destination: `dest-mysql`
- Beobachten: Wie werden BYTEA-Felder in MySQL gemappt?

---

## Szenario 4: Mapping von Studenten / Personal

**Ziel:** Anonymisierte Daten mit realistischen Werten befüllen; Account-IDs generieren; in neue Tabellen schreiben.

**Account-Generierungs-Logik** (`data/hso_accountgenerator.js`):
```
account = (Vorname[0] + Nachname).toLowerCase()[0:8]
          (Umlaute ersetzen: ä→ae, ö→oe, ü→ue, ß→ss)
```

**Python-Implementierung der Account-Logik:**

```python
# scripts/mapping/generate_accounts.py
import re, unicodedata

UMLAUT_MAP = str.maketrans({'ä':'ae','ö':'oe','ü':'ue','ß':'ss',
                             'Ä':'ae','Ö':'oe','Ü':'ue'})

def generate_account(firstname: str, surname: str) -> str:
    raw = (firstname[:1] + surname).lower()
    raw = raw.translate(UMLAUT_MAP)
    # Akzentzeichen normalisieren
    raw = unicodedata.normalize('NFD', raw)
    raw = ''.join(c for c in raw if unicodedata.category(c) != 'Mn')
    raw = re.sub(r'[^a-z]', '', raw)
    return raw[:8]
```

**Airbyte Custom Transformation:**
In Airbyte kann die Account-Logik als dbt-Modell oder über einen Custom Python Connector implementiert werden.

**Ziel-Tabelle** (`dest-postgres`):
```sql
CREATE TABLE hso_students_mapped (
    mtknr      INTEGER,
    firstname  VARCHAR(100),
    surname    VARCHAR(100),
    user_id    VARCHAR(8),   -- generierter Account
    email      VARCHAR(255),
    stg        VARCHAR(20),
    fakult     VARCHAR(100)
);
```

---

## Szenario 5: IdM-System

**Ziel:** `hso_personal` + `hso_students` → gemeinsame `hso_user`-Tabelle in MySQL synchronisieren; bei Änderungen in Quelltabellen automatisch nachziehen.

**Ziel-Tabelle** `hso_user` in `dest-mysql`:
```sql
CREATE TABLE hso_user (
    user_id      VARCHAR(20) PRIMARY KEY,
    nachname     VARCHAR(100),
    vorname      VARCHAR(100),
    email        VARCHAR(255),
    rolle        VARCHAR(50),   -- 'student' oder 'personal'
    status       VARCHAR(20),
    image_id     INTEGER        -- FK zu hso_images (Szenario 3)
);
```

**Sync-Strategie:**
- Airbyte Connection: `source-postgres.hso_students` → `dest-mysql.hso_user` (Incremental | Append+Dedup)
- Cursor-Feld: `updatedat`
- Primary Key: `mtknr` / `sva_persid`

**Änderungs-Test:**
```sql
-- Neue Zeile in source-postgres einfügen
INSERT INTO hso_students (mtknr, firstname, surname, updatedat)
VALUES (999001, 'Test', 'Nutzer', NOW());

-- Sync starten → hso_user in MySQL sollte neue Zeile enthalten
```

---

## Szenario 6: Web APIs

**Ziel:** REST-Schnittstellen für Datenzugriff; SOAP-Abfrage von HISinOne.

**6a – REST API via Airbyte:**
Airbyte kann REST-APIs als Source einbinden (HTTP-Source-Connector).

Für das Bereitstellen einer REST-API eignet sich ein separater Dienst:
- **PostgREST**: Generiert automatisch REST-API aus PostgreSQL-Schema
- In `docker-compose.yml` ergänzen:

```yaml
postgrest:
  image: postgrest/postgrest
  container_name: hso_postgrest
  environment:
    PGRST_DB_URI: postgres://destuser:destpassword@dest-postgres:5432/destdb
    PGRST_DB_SCHEMA: public
    PGRST_DB_ANON_ROLE: destuser
  ports:
    - "3000:3000"
  networks:
    - airbyte_net
```

Dann erreichbar:
- `GET http://localhost:3000/hso_students` → alle Studierenden
- `POST http://localhost:3000/hso_students` → neuen Eintrag anlegen

**6b – SOAP-Webservice (HISinOne):**
- Zugang zu `https://hisinone.hs-offenburg.de/qisserver/services2/` wird separat bereitgestellt
- Airbyte HTTP-Connector konfigurieren mit Security-Header
- Response (XML) in DB schreiben

---

## Bewertungsmatrix

| Szenario | Machbarkeit | Aufwand | Airbyte-Feature |
|----------|-------------|---------|-----------------|
| 1 Testdaten | ✅ einfach | niedrig | DB-Connector, File-Connector |
| 2 FM | ✅ möglich | mittel | Sync + dbt-Transformation |
| 3 Bilder/BLOB | ⚠️ eingeschränkt | hoch | BYTEA-Handling prüfen |
| 4 Mapping | ✅ möglich | mittel | Custom Transformation / dbt |
| 5 IdM Sync | ✅ gut | mittel | Incremental + Dedup |
| 6a REST | ⚠️ indirekt | mittel | PostgREST als Zusatzdienst |
| 6b SOAP | ⚠️ komplex | hoch | HTTP-Connector + XML-Parsing |
