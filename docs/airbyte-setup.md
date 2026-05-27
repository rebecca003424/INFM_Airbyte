# Airbyte lokal aufsetzen

Offizielle Doku: https://docs.airbyte.com/platform/using-airbyte/getting-started/oss-quickstart

## Voraussetzungen

| Anforderung | Minimum | Empfohlen |
|-------------|---------|-----------|
| Docker Desktop | laufend | laufend |
| CPUs | 2 | 4+ |
| RAM | 8 GB | 8 GB+ |

> Der DB-Stack muss bereits laufen (`.\scripts\install.ps1`).

---

## 1. abctl installieren

`abctl` ist Airbybes offizielles CLI-Tool. Es installiert und verwaltet Airbyte in einem
lokalen Kubernetes-Cluster (Kind), der automatisch in Docker Desktop laeuft.

### Automatisch (empfohlen)

```powershell
.\scripts\setup-airbyte.ps1
```

Das Skript laedt `abctl` herunter, fuegt es zum PATH hinzu und startet die Installation.

### Manuell (Windows)

1. Prozessorarchitektur pruefen: Win+I -> System -> Info -> Prozessor
2. Passende Version von https://github.com/airbytehq/abctl/releases/latest laden
   - AMD/Intel: `abctl_Windows_amd64.zip`
   - ARM: `abctl_Windows_arm64.zip`
3. ZIP entpacken, `abctl.exe` nach `C:\tools\airbyte\` kopieren
4. Verzeichnis zum PATH hinzufuegen (Systemsteuerung -> Umgebungsvariablen)
5. Neues Terminal oeffnen, pruefen: `abctl version`

---

## 2. Airbyte installieren

```powershell
abctl local install
```

Bei wenig RAM (unter 6 GB frei):

```powershell
abctl local install --low-resource-mode
```

Das Kommando fragt nach:
- **E-Mail-Adresse** (fuer den Admin-Account)
- **Organisations-Name** (z. B. `HSO`)

Die Installation dauert **5-10 Minuten** (Container-Downloads).

---

## 3. Airbyte UI oeffnen

**http://localhost:8000**

---

## 4. Login-Credentials

### Aktuelle Credentials anzeigen

```powershell
abctl local credentials
```

Ausgabe:
```
Email:         deine@email.de
Password:      <generiertes-passwort>
Client-ID:     ...
Client-Secret: ...
```

### Passwort aendern

```powershell
abctl local credentials --password MeinNeuesPasswort123
```

---

## 5. Sources konfigurieren

### Source: PostgreSQL (Testdaten)

In der Airbyte UI: **Sources** -> **New Source** -> **PostgreSQL**

| Feld | Wert |
|------|------|
| Source name | `HSO Source PostgreSQL` |
| Host | `host.docker.internal` |
| Port | `5433` |
| Database | `sourcedb` |
| Username | `sourceuser` |
| Password | `sourcepassword` |
| SSL mode | `disable` |

> **Warum `host.docker.internal`?** Airbyte lauft in einem Kind-Cluster innerhalb
> von Docker Desktop. Die Connector-Container erreichen den Host-Rechner (und damit
> unsere DB-Container auf ihren exponierten Ports) ueber `host.docker.internal`.

**Test connection** klicken -> sollte gruen werden -> **Set up source**

---

## 6. Destinations konfigurieren

### Destination: PostgreSQL

**Destinations** -> **New Destination** -> **PostgreSQL**

| Feld | Wert |
|------|------|
| Destination name | `HSO Dest PostgreSQL` |
| Host | `host.docker.internal` |
| Port | `5432` |
| Database | `destdb` |
| Username | `destuser` |
| Password | `destpassword` |

### Destination: MySQL

**Destinations** -> **New Destination** -> **MySQL**

| Feld | Wert |
|------|------|
| Destination name | `HSO Dest MySQL` |
| Host | `host.docker.internal` |
| Port | `3306` |
| Database | `destdb` |
| Username | `destuser` |
| Password | `destpassword` |

---

## 7. Connection anlegen und Sync starten

1. **Connections** -> **New Connection**
2. Source und Destination auswaehlen
3. **Streams** auswaehlen (z. B. `fm_gebaeude`, `hso_students`, `k_plz`)
4. **Sync Mode** pro Stream waehlen (siehe Tabelle unten)
5. **Save and sync now**

### Sync-Modi

| Modus | Liest | Schreibt | Wann verwenden |
|-------|-------|---------|----------------|
| Full Refresh Overwrite | Alles | Ersetzt Ziel komplett | Erster Test, kleine Tabellen |
| Full Refresh Append | Alles | Haengt an Ziel an | Historisierung ganzer Snapshots |
| Full Refresh Overwrite + Deduped | Alles | Ersetzt + dedupliziert | Frischer Stand ohne Duplikate |
| Incremental Append | Nur neue Zeilen | Haengt neue Zeilen an | Wachsende Logs, kein Cursor noetig |
| Incremental Append + Deduped | Nur neue Zeilen | Haengt an + dedupliziert | IdM-Sync (Szenario 5), Cursor: `updatedat` |

---

## 8. Nuetzliche abctl-Befehle

```powershell
# Status pruefen
abctl local status

# Logs anzeigen
abctl local logs

# Airbyte stoppen (Daten bleiben erhalten)
abctl local uninstall

# Alles loeschen (inkl. Daten)
abctl local uninstall --persisted
Remove-Item -Recurse "$env:USERPROFILE\.airbyte\abctl"
```

---

## Verbindungsuebersicht

| Service | Fuer DB-Tools (lokal) | Fuer Airbyte (in der UI) |
|---------|----------------------|--------------------------|
| Source PostgreSQL | `localhost:5433` | `host.docker.internal:5433` |
| Dest PostgreSQL | `localhost:5432` | `host.docker.internal:5432` |
| Dest MySQL | `localhost:3306` | `host.docker.internal:3306` |
| Airbyte UI | http://localhost:8000 | - |
