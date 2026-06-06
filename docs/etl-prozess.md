# Erster ETL-Prozess (Runbook)

Ziel: der **einfachste vollständige ETL-Lauf** als Meilenstein-Nachweis — eine
Tabelle aus der Source-PostgreSQL über Airbyte in die Ziel-PostgreSQL kopieren
(Full Refresh | Overwrite). Mit 📸-Markierungen für die Screenshots, die in den
Zwischenbericht gehören.

Detaillierte Feld-Tabellen siehe [airbyte-setup.md](airbyte-setup.md); hier der
kompakte, reproduzierbare Ablauf.

---

## Voraussetzungen

**Windows (PowerShell):**
```powershell
.\scripts\install.ps1        # DB-Stack + Testdaten (einmalig)
.\scripts\setup-airbyte.ps1  # Airbyte via abctl (einmalig, laeuft selbststaendig)
```
**Linux / macOS:**
```bash
bash scripts/install.sh
bash scripts/setup-airbyte.sh
```

Airbyte-UI erreichbar unter **http://localhost:8000** (Login: `abctl local credentials`).

---

## Schritt 1 — Source anlegen (PostgreSQL)

**Sources → + New Source → Postgres**

| Feld | Wert |
|---|---|
| Source name | `HSO Source PostgreSQL` |
| Host | `host.docker.internal` |
| Port | `5433` |
| Database | `sourcedb` |
| Username | `sourceuser` |
| Password | `sourcepassword` |
| SSL mode | `disable` |

**Advanced → Update Method:** **`Scan Changes with User Defined Cursor`** wählen.
> ⚠️ Standard ist **CDC** (Read Changes using Change Data Capture) — das **scheitert** bei uns,
> weil die Source-DB kein `wal_level = logical`/Replication Slot hat. Darum auf
> *User Defined Cursor* umstellen (passt auch zur `updatedat`-Spalte für Szenario 5).

> ⚠️ **Browser-Autofill aufpassen:** Chrome füllt die Felder **Username/Password** gern
> automatisch mit deinen **Airbyte-Login-Daten** vor. Vor dem Speichern prüfen, dass dort
> wirklich `sourceuser` / `sourcepassword` steht (nicht deine Login-E-Mail).

→ **Set up source** → Verbindungstest grün. 📸 **Screenshot 1:** erfolgreich angelegte Source.
> Der **erste** Connector-Test dauert ~1 Min (Airbyte startet dafür einen Connector-Pod im Cluster).

## Schritt 2 — Destination anlegen (PostgreSQL)

**Destinations → + New Destination → Postgres**

| Feld | Wert |
|---|---|
| Destination name | `HSO Dest PostgreSQL` |
| Host | `host.docker.internal` |
| Port | `5434` |
| Database | `destdb` |
| Username | `destuser` |
| Password | `destpassword` |
| SSL mode | `disable` |

> Das **Passwort-Feld** liegt beim Postgres-Destination unter **„Optional fields"** (aufklappen).
> Auch hier ggf. den Browser-Autofill überschreiben (`destuser` / `destpassword`).

→ **Set up destination** → Verbindungstest grün. 📸 **Screenshot 2:** erfolgreich angelegte Destination.

## Schritt 3 — Connection & Stream-Auswahl

**Connections → + New Connection** → Source `HSO Source PostgreSQL`, Destination `HSO Dest PostgreSQL`.
Airbyte führt automatisch eine **Schema-Discovery** aus (zeigt die 7 Streams).

- Streams auswählen: für den ersten Lauf **`fm_gebaeude`** (25 Zeilen) und **`k_plz`** (~34.000) — klein + groß.
- **Sync mode pro Stream auf `Full refresh | Overwrite` stellen.**
  > ⚠️ „Replicate Source" setzt die Streams automatisch auf **Incremental | Append + Deduped**.
  > Da unsere Tabellen weder einen passenden **Cursor** noch einen **Primary Key** definiert
  > haben, erscheint dann „Primary key / cursor missing" und *Next* bleibt gesperrt. Den
  > Sync-Modus jeder Zeile per Dropdown auf **Full refresh | Overwrite** ändern → Fehler weg.
- Schedule type: **Scheduled / Every 24 hours** (Default) oder **Manual** — für den Test egal,
  „Finish & Sync" startet ohnehin sofort einen Lauf.

📸 **Screenshot 3:** Stream-Auswahl mit Sync-Modus `Full refresh | Overwrite`.

## Schritt 4 — Sync ausführen

Im letzten Wizard-Schritt **„Finish & Sync"** klicken — das legt die Connection an und
startet sofort den ersten Lauf. Auf der **Status**-Seite die Streams beobachten, bis sie
von *Syncing* auf **Synced** (grüner Haken) springen.

> Der erste Sync braucht ~1 Min Vorlauf (Sync-Pod-Start), danach geht's schnell.
> Verifizierter Lauf: **fm_gebaeude 25 loaded**, **k_plz 34.172 loaded** (= Source-Zeilen).

📸 **Screenshot 4:** Status-Seite mit beiden Streams **Synced** + Record-Zahlen.

## Schritt 5 — Ergebnis verifizieren (Ziel-DB)

```bash
# funktioniert auf allen Plattformen (Docker)
docker exec -it hso_dest_postgres psql -U destuser -d destdb -c "\dt"
docker exec -it hso_dest_postgres psql -U destuser -d destdb -c "SELECT count(*) FROM fm_gebaeude;"
docker exec -it hso_dest_postgres psql -U destuser -d destdb -c "SELECT count(*) FROM k_plz;"
```

Erwartet: `fm_gebaeude` = 25, `k_plz` = 34.172 (entspricht der Source).
📸 **Screenshot 5:** Zeilenzahlen in der Ziel-DB (Nachweis, dass Daten angekommen sind).

---

## Stolpersteine (live verifiziert)

| Symptom | Ursache | Lösung |
|---|---|---|
| Connector-Test/Sync hängt ewig, Pod bleibt `Pending` mit `persistentvolumeclaim "airbyte-local-pvc" not found` | Lokales File-Volume ist aktiviert (`JOB_KUBE_LOCAL_VOLUME_ENABLED=true`), aber das PVC `airbyte-local-pvc` fehlt → betrifft **alle** Connectoren | `setup-airbyte.ps1`/`.sh` legen PV+PVC jetzt automatisch an. Prüfen: `kubectl get pvc -n airbyte-abctl` muss `airbyte-local-pvc` als **Bound** zeigen. |
| Source-Test scheitert mit CDC/Replication-Fehler | Update Method steht auf **CDC** (Default) | Source → Advanced → **User Defined Cursor** |
| *Next* im Connection-Wizard gesperrt, „Primary key / cursor missing" | Streams stehen auf **Incremental + Deduped** | Pro Stream Sync-Modus auf **Full refresh \| Overwrite** |
| DB-Felder zeigen E-Mail/falsches Passwort | Browser-Autofill | Username/Password manuell auf `*user`/`*password` überschreiben |

> Pod-Status im Cluster prüfen:
> `docker exec airbyte-abctl-control-plane kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -n airbyte-abctl`

## Screenshot-Checkliste für den Bericht

- [ ] Source erfolgreich angelegt
- [ ] Destination erfolgreich angelegt
- [ ] Connection mit Streams + Sync-Modus
- [ ] Erfolgreicher Sync (Status „Succeeded" + Record-Zahlen)
- [ ] Verifikation in der Ziel-DB

---

## Optional: zweites Ziel (MySQL)

Zum Vergleich kann dieselbe Source zusätzlich nach MySQL synchronisiert werden
(`host.docker.internal:3306`, SSL **aus**, JDBC-Param `allowPublicKeyRetrieval=true`,
Raw table database `destdb`) — Details in [airbyte-setup.md](airbyte-setup.md), Kap. 6.

## Optional: File-Connector (Flatfile-ETL)

Studierendendaten (`hso_students`) liegen wegen der defekten CSV nur als Flatfile vor
und werden über den **File-Connector** (`/local/hso_students.csv`, Trennzeichen `|`)
eingebunden — siehe [airbyte-setup.md](airbyte-setup.md), Kap. 7.
