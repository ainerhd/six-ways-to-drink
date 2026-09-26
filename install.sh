#!/usr/bin/env bash
# Six ways to drink – Installer für Proxmox VE
# Legt einen unprivilegierten Debian-LXC an, installiert nginx und liefert die App aus.
#
# Aufruf in der Proxmox-Hostshell (als root):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ainerhd/six-ways-to-drink/main/install.sh)"
#
# Alle Abfragen haben Defaults. Mit YES=1 werden die Defaults ohne Rückfrage übernommen.
# Überschreibbar per Umgebungsvariable: CTID, CT_HOSTNAME, STORAGE, TEMPLATE_STORAGE,
# BRIDGE, CORES, MEMORY, DISK, NET (dhcp oder IP/CIDR), GATEWAY, REPO_URL, BRANCH

set -euo pipefail

APP="six-ways-to-drink"
REPO_URL="${REPO_URL:-https://github.com/ainerhd/six-ways-to-drink.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="/var/www/${APP}"

# ---------- Ausgabe ----------
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_BLUE=$'\e[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi
info() { echo "${C_BLUE}==>${C_RESET} $*"; }
ok()   { echo "${C_GREEN}✔${C_RESET}  $*"; }
warn() { echo "${C_YELLOW}!${C_RESET}  $*"; }
die()  { echo "${C_RED}✘  $*${C_RESET}" >&2; exit 1; }

ask() {
  # ask VAR "Frage" "Default"
  local __var="$1" __prompt="$2" __default="$3" __answer=""
  if [[ "${YES:-0}" == "1" ]]; then
    printf -v "$__var" '%s' "$__default"
    return
  fi
  read -r -p "${C_BOLD}${__prompt}${C_RESET} [${__default}]: " __answer </dev/tty || true
  printf -v "$__var" '%s' "${__answer:-$__default}"
}

# ---------- Vorprüfungen ----------
[[ $EUID -eq 0 ]] || die "Bitte als root ausführen."
for cmd in pct pveam pvesh pvesm; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' nicht gefunden – läuft das Skript auf einem Proxmox-VE-Host?"
done

echo
echo "${C_BOLD}Six ways to drink – Proxmox-LXC-Installer${C_RESET}"
echo "Repo: ${REPO_URL} (${BRANCH})"
echo

# ---------- Defaults ermitteln ----------
default_ctid="$(pvesh get /cluster/nextid 2>/dev/null || echo 100)"

rootdir_storages="$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')"
if grep -qx "local-lvm" <<<"$rootdir_storages"; then
  default_storage="local-lvm"
else
  default_storage="$(head -n1 <<<"$rootdir_storages")"
fi
[[ -n "$default_storage" ]] || die "Kein aktiver Storage mit Inhalt 'rootdir' gefunden."

tmpl_storages="$(pvesm status -content vztmpl 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')"
if grep -qx "local" <<<"$tmpl_storages"; then
  default_tmpl_storage="local"
else
  default_tmpl_storage="$(head -n1 <<<"$tmpl_storages")"
fi
[[ -n "$default_tmpl_storage" ]] || die "Kein aktiver Storage mit Inhalt 'vztmpl' gefunden."

# ---------- Abfragen ----------
ask CTID             "Container-ID"                         "${CTID:-$default_ctid}"
ask CT_HOSTNAME      "Hostname"                             "${CT_HOSTNAME:-$APP}"
ask STORAGE          "Storage für die Disk (${rootdir_storages//$'\n'/, })" "${STORAGE:-$default_storage}"
ask TEMPLATE_STORAGE "Storage für das Template (${tmpl_storages//$'\n'/, })" "${TEMPLATE_STORAGE:-$default_tmpl_storage}"
ask BRIDGE           "Netzwerk-Bridge"                      "${BRIDGE:-vmbr0}"
ask NET              "IP (dhcp oder z. B. 192.168.1.50/24)" "${NET:-dhcp}"
if [[ "$NET" != "dhcp" ]]; then
  ask GATEWAY        "Gateway"                              "${GATEWAY:-}"
else
  GATEWAY=""
fi
ask CORES            "CPU-Kerne"                            "${CORES:-1}"
ask MEMORY           "RAM in MB"                            "${MEMORY:-512}"
ask DISK             "Disk in GB"                           "${DISK:-2}"

# ---------- Validierung ----------
[[ "$CTID" =~ ^[0-9]+$ && "$CTID" -ge 100 ]] || die "Ungültige Container-ID: $CTID"
if compgen -G "/etc/pve/nodes/*/lxc/${CTID}.conf" >/dev/null || compgen -G "/etc/pve/nodes/*/qemu-server/${CTID}.conf" >/dev/null; then
  die "ID ${CTID} ist bereits vergeben. Es wird nichts überschrieben."
fi
[[ "$CT_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die "Ungültiger Hostname: $CT_HOSTNAME"
grep -qx "$STORAGE" <<<"$rootdir_storages" || die "Storage '$STORAGE' unterstützt keine Container-Disks."
grep -qx "$TEMPLATE_STORAGE" <<<"$tmpl_storages" || die "Storage '$TEMPLATE_STORAGE' unterstützt keine Templates."
[[ -d "/sys/class/net/${BRIDGE}" ]] || die "Bridge '$BRIDGE' existiert nicht."
[[ "$CORES" =~ ^[0-9]+$ && "$CORES" -ge 1 ]] || die "Ungültige CPU-Anzahl: $CORES"
[[ "$MEMORY" =~ ^[0-9]+$ && "$MEMORY" -ge 128 ]] || die "Ungültiger RAM-Wert: $MEMORY"
[[ "$DISK" =~ ^[0-9]+$ && "$DISK" -ge 1 ]] || die "Ungültige Disk-Größe: $DISK"
if [[ "$NET" == "dhcp" ]]; then
  NET_CONF="name=eth0,bridge=${BRIDGE},ip=dhcp"
else
  [[ "$NET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || die "IP bitte mit CIDR angeben, z. B. 192.168.1.50/24"
  [[ "$GATEWAY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Ungültiges Gateway: $GATEWAY"
  NET_CONF="name=eth0,bridge=${BRIDGE},ip=${NET},gw=${GATEWAY}"
fi

# ---------- Template ----------
info "Suche aktuelles Debian-12-Template ..."
pveam update >/dev/null 2>&1 || warn "pveam update fehlgeschlagen, nutze vorhandene Liste."
TEMPLATE="$(pveam available --section system 2>/dev/null | awk '{print $2}' | grep -E '^debian-12-standard_.*_amd64\.tar\.(zst|gz|xz)$' | sort -V | tail -n1 || true)"
if [[ -z "$TEMPLATE" ]]; then
  TEMPLATE="$(pveam list "$TEMPLATE_STORAGE" 2>/dev/null | awk '{print $1}' | sed 's#.*/##' | grep -E '^debian-12-standard_' | sort -V | tail -n1 || true)"
fi
[[ -n "$TEMPLATE" ]] || die "Kein Debian-12-Template gefunden."

# ---------- Zusammenfassung ----------
echo
echo "${C_BOLD}Zusammenfassung${C_RESET}"
echo "  Container-ID : ${CTID}"
echo "  Hostname     : ${CT_HOSTNAME}"
echo "  Template     : ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
echo "  Disk         : ${STORAGE}, ${DISK} GB"
echo "  CPU / RAM    : ${CORES} Kern(e), ${MEMORY} MB"
echo "  Netzwerk     : ${BRIDGE}, ${NET}${GATEWAY:+, GW ${GATEWAY}}"
echo "  Typ          : unprivilegiert, nesting=1, Autostart an"
echo "  App          : ${REPO_URL} (${BRANCH}) -> ${APP_DIR}"
echo
if [[ "${YES:-0}" != "1" ]]; then
  read -r -p "${C_BOLD}Container jetzt anlegen? [j/N]${C_RESET} " confirm </dev/tty || true
  [[ "$confirm" =~ ^[jJyY]$ ]] || die "Abgebrochen, es wurde nichts angelegt."
fi

# ---------- Template laden ----------
if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "vztmpl/${TEMPLATE}"; then
  info "Lade Template ${TEMPLATE} ..."
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null
fi
ok "Template vorhanden"

# ---------- Container anlegen ----------
info "Lege Container ${CTID} an ..."
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$CT_HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap 256 \
  --rootfs "${STORAGE}:${DISK}" \
  --net0 "$NET_CONF" \
  --unprivileged 1 \
  --features nesting=1 \
  --onboot 1 \
  --ostype debian \
  --tags "$APP" \
  --description "Six ways to drink – ${REPO_URL}" >/dev/null
ok "Container ${CTID} angelegt"

info "Starte Container ..."
pct start "$CTID"

info "Warte auf Netzwerk ..."
for i in $(seq 1 60); do
  if pct exec "$CTID" -- getent hosts deb.debian.org >/dev/null 2>&1; then break; fi
  [[ $i -eq 60 ]] && die "Container ${CTID} hat nach 60 s kein Netzwerk. Container bleibt zur Prüfung bestehen."
  sleep 1
done
ok "Netzwerk bereit"

# ---------- App im Container einrichten ----------
info "Installiere nginx und die App (dauert etwas) ..."
SETUP_SCRIPT="$(cat <<'SETUP'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq >/dev/null
apt-get install -y -qq --no-install-recommends nginx git ca-certificates >/dev/null

rm -rf "$APP_DIR"
git clone --quiet --depth 1 --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
git config --system --add safe.directory "$APP_DIR"

cat > "/etc/nginx/sites-available/${APP}" <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root ${APP_DIR};
    index index.html;

    server_tokens off;
    add_header Cache-Control "no-cache" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    add_header X-Frame-Options SAMEORIGIN always;

    # Nur die App ausliefern, keine Repo-Interna
    location ~ /\. { return 404; }
    location ~* \.(sh|md)\$ { return 404; }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf "/etc/nginx/sites-available/${APP}" "/etc/nginx/sites-enabled/${APP}"
nginx -t -q
systemctl enable --now nginx >/dev/null 2>&1
systemctl reload nginx

install -m 0755 "${APP_DIR}/update.sh" /usr/local/bin/update
apt-get clean
SETUP
)"
pct exec "$CTID" -- env APP="$APP" APP_DIR="$APP_DIR" REPO_URL="$REPO_URL" BRANCH="$BRANCH" bash -c "$SETUP_SCRIPT"
ok "App installiert"

# ---------- Ergebnis ----------
IP="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "${C_GREEN}${C_BOLD}Fertig!${C_RESET}"
echo "  Container : ${CTID} (${CT_HOSTNAME})"
echo "  IP        : ${IP:-unbekannt}"
echo "  URL       : http://${IP:-<ip>}/"
echo
echo "  Update    : pct exec ${CTID} -- update"
echo "  Konsole   : pct enter ${CTID}"
echo
echo "  Nächster Schritt: DNS-Eintrag und NPMplus-Proxy-Host auf http://${IP:-<ip>}:80 anlegen."
