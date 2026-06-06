#!/usr/bin/env bash
# uninstall.sh - Entfernt Airbyte (abctl) und den Docker-Stack (Linux/macOS)
# Gegenstueck zu install.sh + setup-airbyte.sh.
#
# Aufruf:
#   bash scripts/uninstall.sh                 # vollstaendig (mit Rueckfrage)
#   bash scripts/uninstall.sh --keep-data     # Container/Airbyte entfernen, DB-Daten behalten
#   bash scripts/uninstall.sh --remove-abctl  # zusaetzlich abctl-Binary entfernen
#   bash scripts/uninstall.sh --force         # ohne Rueckfrage

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

KEEP_DATA=0; REMOVE_ABCTL=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --keep-data)    KEEP_DATA=1 ;;
    --remove-abctl) REMOVE_ABCTL=1 ;;
    --force|-f)     FORCE=1 ;;
    *) echo "Unbekanntes Argument: $arg"; exit 2 ;;
  esac
done

cyan() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    [OK] %s\n' "$1"; }
warn() { printf '    [!]  %s\n' "$1"; }
fail() { printf '    [X]  %s\n' "$1"; }

echo
echo "  Campus Next-Gen Data-Hub - Deinstallation"
echo "  ========================================="
if [ "$KEEP_DATA" -eq 1 ]; then
  echo "  Modus: DB-Daten und Airbyte-Daten BLEIBEN erhalten."
else
  echo "  Modus: VOLLSTAENDIG - Container, Volumes und Airbyte-Daten werden GELOESCHT."
fi
[ "$REMOVE_ABCTL" -eq 1 ] && echo "  Zusaetzlich: abctl-Binary wird entfernt."
echo

if [ "$FORCE" -ne 1 ]; then
  printf "  Fortfahren? (j/N) "
  read -r confirm || confirm=""
  case "$confirm" in
    j|J|y|Y) ;;
    *) warn "Abgebrochen - keine Aenderungen vorgenommen."; exit 0 ;;
  esac
fi

dockerUp=0
if docker info >/dev/null 2>&1; then dockerUp=1; else warn "Docker laeuft nicht - Container/Volumes werden nicht entfernt."; fi

# --- 1. Airbyte (abctl) deinstallieren ---------------------------------------
cyan "Airbyte (abctl) deinstallieren"
if command -v abctl >/dev/null 2>&1 && [ "$dockerUp" -eq 1 ]; then
  if [ "$KEEP_DATA" -eq 1 ]; then
    abctl local uninstall            && ok "Airbyte deinstalliert." || warn "abctl local uninstall meldete einen Fehler."
  else
    abctl local uninstall --persisted && ok "Airbyte deinstalliert (inkl. Daten)." || warn "abctl local uninstall meldete einen Fehler."
  fi
elif ! command -v abctl >/dev/null 2>&1; then
  warn "abctl nicht gefunden - Airbyte-Deinstallation uebersprungen."
else
  warn "Docker aus - Airbyte-Deinstallation uebersprungen."
fi

# --- 2. Docker-Stack entfernen -----------------------------------------------
cyan "Datenbank-Stack (docker compose) entfernen"
if [ "$dockerUp" -eq 1 ]; then
  cd "$ROOT"
  if [ "$KEEP_DATA" -eq 1 ]; then
    docker compose down    && ok "Container entfernt - Volumes (DB-Daten) bleiben erhalten."
  else
    docker compose down -v && ok "Container und compose-Volumes entfernt."
  fi
else
  warn "Uebersprungen (Docker laeuft nicht)."
fi

# --- 3. Externes Volume oss_local_root ---------------------------------------
# Wird von install.sh als 'external' angelegt und von 'compose down -v' NICHT erfasst.
if [ "$KEEP_DATA" -ne 1 ] && [ "$dockerUp" -eq 1 ]; then
  cyan "Volume oss_local_root entfernen"
  if docker volume ls --format '{{.Name}}' | grep -qx oss_local_root; then
    docker volume rm oss_local_root >/dev/null 2>&1 && ok "oss_local_root geloescht." || warn "oss_local_root konnte nicht geloescht werden (evtl. noch in Benutzung)."
  else
    ok "oss_local_root existiert nicht (mehr)."
  fi
fi

# --- 4. abctl-Binary (optional) ----------------------------------------------
if [ "$REMOVE_ABCTL" -eq 1 ]; then
  cyan "abctl-Binary entfernen"
  removed=0
  for p in "$HOME/.airbyte/abctl" "/usr/local/bin/abctl" "$HOME/.local/bin/abctl"; do
    if [ -e "$p" ]; then rm -rf "$p" && ok "$p entfernt." && removed=1; fi
  done
  [ "$removed" -eq 0 ] && warn "Keine bekannte abctl-Installation gefunden (PATH ggf. manuell bereinigen)."
fi

# --- Ergebnis ----------------------------------------------------------------
echo
echo "  ==========================================================="
echo "  Deinstallation abgeschlossen."
[ "$KEEP_DATA" -ne 1 ] && echo "  Neu aufsetzen: bash scripts/install.sh + bash scripts/setup-airbyte.sh"
echo "  ==========================================================="
