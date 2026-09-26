# Six ways to drink

Würfel-Trinkspiel als Web-App fürs Handy. Eine einzelne HTML-Datei, kein Backend, kein Tracking – der Spielstand liegt nur im Browser (`localStorage`).

## Regeln

Reihum wird gewürfelt:

| Wurf | Regel |
|------|-------|
| 1 | Alle trinken |
| 2 | Person links trinkt |
| 3 | Person rechts trinkt |
| 4 | Du bestimmst, wer trinkt |
| 5 | Du trinkst selbst |
| 6 | Du bestimmst zwei Personen für ein Duell |

- Wer trinkt, beantwortet eine Frage („Wer im Raum würde am ehesten …?“).
- Bei einer 1 beantworten alle dieselbe Frage.
- Duell: Beide bekommen eine Duell-Frage, die Gruppe entscheidet, der Verlierer muss exen.
- Fragen wiederholen sich erst, wenn alle einmal dran waren.

Spieler werden **im Uhrzeigersinn** eingegeben. Links von dir sitzt, wer nach dir dran ist.

## Installation auf Proxmox VE

In der Shell des Proxmox-Hosts als root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ainerhd/six-ways-to-drink/main/install.sh)"
```

Der Installer fragt alle Einstellungen mit Defaults ab (Enter übernimmt):

| Einstellung | Default |
|-------------|---------|
| Container-ID | nächste freie ID |
| Hostname | `six-ways-to-drink` |
| Storage | `local-lvm` |
| Template-Storage | `local` |
| Bridge | `vmbr0` |
| IP | `dhcp` (oder `192.168.1.50/24` + Gateway) |
| CPU / RAM / Disk | 1 Kern / 512 MB / 2 GB |

Danach zeigt er eine Zusammenfassung und legt erst nach Bestätigung an:

- unprivilegierter Debian-12-LXC mit Autostart
- nginx liefert die App auf Port 80 aus (`/var/www/six-ways-to-drink`)
- Befehl `update` im Container

Eine bereits vergebene ID wird nie überschrieben.

Ohne Rückfragen, z. B. mit fester IP:

```bash
YES=1 NET=192.168.1.50/24 GATEWAY=192.168.1.1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/ainerhd/six-ways-to-drink/main/install.sh)"
```

DNS-Eintrag und Reverse Proxy (z. B. Nginx Proxy Manager) werden nicht vom Installer angelegt. Proxy-Ziel ist `http://<container-ip>:80`.

## Update

Neue Fragen oder Code-Änderungen ins Repo pushen, dann:

```bash
pct exec <CTID> -- update
```

`update` setzt das App-Verzeichnis im Container hart auf den Stand von `origin/main` zurück.

## Fragen bearbeiten

Alle Fragen stehen in `questions.json`:

```json
{ "id": 1, "type": "normal", "category": "harmlos", "text": "Wer im Raum ..." }
```

- `id`: eindeutige Zahl (Konvention: harmlos 1–99, peinlich 100–199, spicy 200–299, duell 300–399)
- `type`: `normal` oder `duel`
- `category`: `harmlos`, `peinlich`, `spicy` (bei Duell-Fragen `duell`)
- `text`: die Frage

## Lokal testen

`questions.json` wird per `fetch` geladen, deshalb braucht es einen Webserver:

```bash
python -m http.server 8080
```

Dann `http://localhost:8080` öffnen (am Handy im selben WLAN: `http://<pc-ip>:8080`).
