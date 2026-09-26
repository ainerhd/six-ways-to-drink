#!/usr/bin/env bash
# Six ways to drink – Update im LXC
# Holt den aktuellen Stand aus dem Git-Repo. Wird vom Installer nach /usr/local/bin/update kopiert.
#
# Im Container:      update
# Vom Proxmox-Host:  pct exec <CTID> -- update

set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/six-ways-to-drink}"

[[ $EUID -eq 0 ]] || { echo "Bitte als root ausführen." >&2; exit 1; }
[[ -d "${APP_DIR}/.git" ]] || { echo "Kein Git-Repo unter ${APP_DIR} gefunden." >&2; exit 1; }

branch="$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD)"
before="$(git -C "$APP_DIR" rev-parse --short HEAD)"

echo "==> Hole Updates (${branch}) ..."
git -C "$APP_DIR" fetch --quiet --depth 1 origin "$branch"
git -C "$APP_DIR" reset --quiet --hard "origin/${branch}"
after="$(git -C "$APP_DIR" rev-parse --short HEAD)"

# Update-Skript selbst aktuell halten
install -m 0755 "${APP_DIR}/update.sh" /usr/local/bin/update

if [[ "$before" == "$after" ]]; then
  echo "✔  Bereits aktuell (${after})."
else
  echo "✔  Aktualisiert: ${before} -> ${after}"
fi
