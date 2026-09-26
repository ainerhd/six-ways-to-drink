#!/usr/bin/env bash
# Six ways to drink – Updater im LXC
# Holt den aktuellen Stand aus dem Git-Repo. Wird vom Installer nach /usr/local/bin/update kopiert.
#
# Aufruf im Container (oder vom Proxmox-Host mit: pct exec <CTID> -- update [option]):
#   update                 jetzt aktualisieren
#   update --check         nur prüfen, ob es eine neue Version gibt
#   update --status        aktuelle Version, Auto-Update-Status, letzte Läufe
#   update --enable-auto   automatische Updates per systemd-Timer einschalten (stündlich)
#   update --disable-auto  automatische Updates ausschalten
#   update --auto          wird vom Timer aufgerufen (Ausgabe nur bei Änderungen)

set -euo pipefail

APP="six-ways-to-drink"
APP_DIR="${APP_DIR:-/var/www/${APP}}"
UNIT="${APP}-update"
UNIT_DIR="/etc/systemd/system"
LOCK_FILE="/run/${UNIT}.lock"

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }
log()   { [[ "$MODE" == "auto" ]] || echo "$*"; }
fail()  { echo "✘  $*" >&2; exit 1; }

short() { git -C "$APP_DIR" rev-parse --short "$1"; }

write_version() {
  # Für die Versionsanzeige und den Update-Hinweis in der App (von nginx ausgeliefert)
  local commit date tmp
  commit="$(short HEAD)"
  date="$(git -C "$APP_DIR" log -1 --format=%cI HEAD)"
  tmp="$(mktemp "${APP_DIR}/.version.XXXXXX")"
  printf '{ "commit": "%s", "date": "%s" }\n' "$commit" "$date" >"$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "${APP_DIR}/version.json"
}

fetch_remote() {
  BRANCH="$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD)"
  git -C "$APP_DIR" fetch --quiet --depth 1 origin "$BRANCH"
  LOCAL="$(git -C "$APP_DIR" rev-parse HEAD)"
  REMOTE="$(git -C "$APP_DIR" rev-parse FETCH_HEAD)"
}

do_update() {
  log "==> Suche Updates ..."
  fetch_remote
  if [[ "$LOCAL" == "$REMOTE" ]]; then
    write_version
    log "✔  Bereits aktuell ($(short HEAD))."
    return
  fi
  local before after subject
  before="$(short HEAD)"
  git -C "$APP_DIR" reset --quiet --hard "$REMOTE"
  git -C "$APP_DIR" clean --quiet -fd
  after="$(short HEAD)"
  subject="$(git -C "$APP_DIR" log -1 --format=%s HEAD)"
  write_version
  # Updater selbst aktuell halten (das laufende Skript liest nur noch aus dem Speicher, siehe main)
  install -m 0755 "${APP_DIR}/update.sh" /usr/local/bin/update
  echo "✔  Aktualisiert: ${before} -> ${after} (${subject})"
}

do_check() {
  fetch_remote
  if [[ "$LOCAL" == "$REMOTE" ]]; then
    echo "✔  Aktuell ($(short HEAD))."
  else
    echo "!  Neue Version verfügbar: $(short HEAD) -> $(short FETCH_HEAD). Mit 'update' installieren."
  fi
}

enable_auto() {
  command -v systemctl >/dev/null 2>&1 || fail "systemd nicht gefunden."
  cat >"${UNIT_DIR}/${UNIT}.service" <<EOF
[Unit]
Description=Six ways to drink: App aus Git aktualisieren
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update --auto
EOF
  cat >"${UNIT_DIR}/${UNIT}.timer" <<EOF
[Unit]
Description=Six ways to drink: stündliches Auto-Update

[Timer]
OnBootSec=5min
OnCalendar=hourly
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now "${UNIT}.timer" >/dev/null 2>&1
  echo "✔  Auto-Update eingeschaltet (stündlich). Status: update --status"
}

disable_auto() {
  if [[ -f "${UNIT_DIR}/${UNIT}.timer" ]]; then
    systemctl disable --now "${UNIT}.timer" >/dev/null 2>&1 || true
  fi
  echo "✔  Auto-Update ausgeschaltet. Die Unit-Dateien bleiben liegen, 'update --enable-auto' schaltet es wieder ein."
}

do_status() {
  echo "Version    : $(short HEAD) vom $(git -C "$APP_DIR" log -1 --format=%cd --date=format:'%d.%m.%Y %H:%M' HEAD)"
  echo "Branch     : $(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD) ($(git -C "$APP_DIR" remote get-url origin))"
  if systemctl is-enabled --quiet "${UNIT}.timer" 2>/dev/null; then
    local next
    next="$(systemctl show "${UNIT}.timer" --property=NextElapseUSecRealtime --value 2>/dev/null || true)"
    echo "Auto-Update: an${next:+, nächster Lauf ${next}}"
  else
    echo "Auto-Update: aus (einschalten mit: update --enable-auto)"
  fi
  if command -v journalctl >/dev/null 2>&1; then
    echo
    echo "Letzte Läufe:"
    journalctl -u "${UNIT}.service" -n 10 --no-pager -o short 2>/dev/null | sed 's/^/  /' || true
  fi
}

main() {
  MODE="update"
  case "${1:-}" in
    "")             MODE="update" ;;
    --auto)         MODE="auto" ;;
    --check)        MODE="check" ;;
    --status)       MODE="status" ;;
    --enable-auto)  MODE="enable" ;;
    --disable-auto) MODE="disable" ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; exit 2 ;;
  esac

  [[ $EUID -eq 0 ]] || fail "Bitte als root ausführen."
  [[ -d "${APP_DIR}/.git" ]] || fail "Kein Git-Repo unter ${APP_DIR} gefunden."

  case "$MODE" in
    status)  do_status; exit 0 ;;
    enable)  enable_auto; exit 0 ;;
    disable) disable_auto; exit 0 ;;
  esac

  # Nie zwei Läufe gleichzeitig (Timer + manueller Aufruf)
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "Ein Update läuft bereits."
    exit 0
  fi

  case "$MODE" in
    check)       do_check ;;
    update|auto) do_update ;;
  esac
}

# Alles steckt in main: bash liest die Funktion komplett ein, bevor sie läuft.
# So kann sich das Skript während des Updates gefahrlos selbst ersetzen.
main "$@"
exit $?
