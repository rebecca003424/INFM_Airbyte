# Anforderungen & Umsetzungsstand

Diese Übersicht fasst alle Anforderungen aus dem Kickoff (`moodle/Kickoff.md`) und den
sechs Szenarien (`moodle/Projektszenarieren.md`, ausführlich in [testszenarien.md](testszenarien.md))
zusammen und bewertet, **was Airbyte kann** und **wie weit wir sind**.

Stand: 2026-06-06. Legende: ✅ erledigt · ◑ teilweise/in Arbeit · ○ offen · ⚠️ Einschränkung/Risiko.

---

## 1. System-Anforderungen (aus dem Kickoff)

| # | Anforderung | Airbyte-Fähigkeit | Status im Projekt |
|---|---|---|---|
| A1 | **Open Source** + aktive Community | Airbyte OSS (MIT/ELv2), sehr aktive Community | ✅ erfüllt (Auswahlkriterium) |
| A2 | **DB-Anbindungen** (min. Informix, MySQL, PostgreSQL) | Postgres + MySQL als Source/Destination vorhanden; **Informix nur als Enterprise/Db2-nah, kein OSS-Connector** | ◑ PG+MySQL ✅, **Informix ⚠️ Lücke** |
| A3 | **Datei-basiert**: CSV, Excel, JSON, XML | File-Connector: CSV/JSON/Excel/Feather/Parquet ✅; **XML nativ nicht** | ◑ CSV/JSON/Excel ✅, **XML ⚠️** |
| A4 | **SOAP- und REST-APIs** abfragen | REST: Connector-Builder (Low-Code) / HTTP; SOAP: nicht nativ, nur als HTTP-POST mit XML-Parsing | ○ (Szenario 6) |
| A5 | **Daten-Mapping/Transformation** über eigenen Code | Transformationen via **dbt** (SQL) bzw. Custom Connector; **kein freies Code-Mapping pro Feld wie in Talend** | ◑ Konzept steht, ⚠️ Paradigmenwechsel zu dbt/SQL |
| A6 | **Low-Code REST-API bereitstellen** | Airbyte stellt selbst keine Daten-API bereit → externer Dienst **PostgREST** | ○ (Szenario 6a, PostgREST vorgesehen) |
| A7 | **Code-Snippets** ausführen (Python/JS/Groovy/Selenium) | Airbyte führt **keine** freien Skripte aus; nur dbt-SQL oder eigener Connector (Python-CDK/Low-Code) | ⚠️ **Lücke ggü. Talend** (zentraler Evaluationsbefund) |
| A8 | **Logging & Monitoring** von Jobs | Job-Historie, Status-UI, Logs pro Sync/Attempt, Timeline | ✅ vorhanden |
| A9 | **Usability / einfache Konfiguration** | Web-UI, Connector-Kataloge, geführte Setups | ✅ (mit abctl-spezifischen Stolpersteinen, s. installation-guide) |
| A10 | **Integration in die Hochschul-IT** | Läuft lokal/on-prem via abctl (kind); API/Terraform-Anbindung möglich | ◑ lokal evaluiert; Produktiv-Integration offen |

---

## 2. Szenarien-Status

| Szenario | Inhalt | Airbyte-Eignung | Status | Nächster Schritt |
|---|---|---|---|---|
| **1 Testdaten einspielen** | Daten in MySQL **und** PostgreSQL; Postgres- + File-Connector testen | ✅ gut | ◑ **Postgres-ETL live verifiziert** (fm_gebaeude 25, k_plz 34.172 in `destdb`); **alle 5 Sources + 2 Destinations angelegt**, File-Connector-Tests grün | Sync auch nach MySQL + File→DB-Sync zeigen |
| **2 Facility Management** | PG-Tabellen inst/geb/stamm; **1 denormalisierte** Raum-Tabelle in MySQL | ◑ Sync ok, Joins nur via dbt/View | ◑ `fm_inst`/`fm_gebaeude` geladen; `fm_stamm` ohne Quelle | View/dbt für `fm_raeume`, dann nach MySQL |
| **3 Bilder als BLOB** | >1000 Bilder per API → BYTEA/Blob in DB; später als Datei exportieren | ⚠️ eingeschränkt (BYTEA-Handling) | ○ Skripte `scripts/images/*.py` vorhanden, nicht ausgeführt | Bilder laden, BYTEA→MySQL-Sync prüfen |
| **4 Mapping Studenten/Personal** | Random-Daten, Account-Generator, in neue Tabellen schreiben | ◑ via dbt/Custom | ○ `scripts/mapping/generate_accounts.py` vorhanden; **blockiert durch defekte `hso_students.csv`** | Soll-Struktur von Betreuern klären |
| **5 IdM-System** | `hso_personal`+`hso_students` → `hso_user` (MySQL), Sync bei Änderung; Bild-Verknüpfung | ✅ gut (Incremental + Dedup) | ○ | Cursor `updatedat` + PK setzen, Incremental-Connection |
| **6 Web APIs** | 6a REST (insert/update), 6b SOAP HISinOne | ⚠️ REST via PostgREST/Builder; SOAP komplex | ○ | PostgREST-Dienst; SOAP-Zugang von Betreuern abwarten |

---

## 3. Offene Punkte / Fragen an die Betreuer

(siehe auch [zwischenbericht.md](zwischenbericht.md), Kap. 6)

1. **`hso_students.csv`** strukturell defekt (mehr Datenspalten als Header) → blockiert Szenario 4. Korrigierte Datei / Soll-Struktur?
2. **`fm_stamm`** (Raumstammdaten): keine Quelldatei vorhanden — woher kommen die Daten?
3. **Informix**-Anbindung: kein OSS-Airbyte-Connector. Ist Informix zwingend, oder reicht PG/MySQL für die Evaluation?
4. **Code-Snippet-Ausführung** (A7) ist Airbytes größte Lücke ggü. Talend. Wie wichtig ist dieses Kriterium für die Bewertung?
5. **SOAP/HISinOne**-Zugang (Szenario 6b) wird testweise bereitgestellt — wann?
6. **Sync-Strategie** Cursor (`updatedat`) statt CDC — für die Evaluation ausreichend?
7. **Szenario-Priorisierung** für die Bewertung?

---

## 4. Bereits umgesetzte Airbyte-Objekte (Stand 2026-06-06)

**Sources:** `HSO Source PostgreSQL` (Postgres, User-Defined-Cursor) · `HSO CSV hso_students` · `HSO CSV k_plz` · `HSO CSV fm_gebaeude` · `HSO CSV fm_inst` (alle File/`local`, `/local/*.csv`).
**Destinations:** `HSO Dest PostgreSQL` (5434) · `HSO Dest MySQL` (3306, SSL aus, `allowPublicKeyRetrieval=true`).
**Connection:** `HSO Source PostgreSQL → HSO Dest PostgreSQL`, Full Refresh | Overwrite, **erfolgreich gesynct**.
