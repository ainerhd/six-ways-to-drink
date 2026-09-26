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
- 150 Fragen in sechs Kategorien (Harmlos, Party, Zukunft, Freundeskreis, Peinlich, Spicy) plus Duelle. Kategorien lassen sich an- und abwählen.

Spieler werden **im Uhrzeigersinn** eingegeben. Links von dir sitzt, wer nach dir dran ist.

Über das Menü (☰ oben rechts):

- **Neues Spiel**: Spieler und Kategorien bleiben, Reihenfolge und Fragen starten neu
- **Spieler & Kategorien**: Spieler ändern, Kategorien an- und abwählen
- **Regeln**
- **Alles löschen**: Spieler und Spielstand entfernen
- unten: installierte Version

Wird im Container eine neue Version installiert, zeigt die offene App einen Hinweis „Neue Version verfügbar“ mit Button zum Neuladen. Der Spielstand bleibt dabei erhalten.

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
| Automatische Updates | `j` (stündlich) |

Danach zeigt er eine Zusammenfassung und legt erst nach Bestätigung an:

- unprivilegierter Debian-12-LXC mit Autostart
- nginx liefert die App auf Port 80 aus (`/var/www/six-ways-to-drink`)
- Befehl `update` im Container, optional mit stündlichem Auto-Update

Eine bereits vergebene ID wird nie überschrieben.

Ohne Rückfragen, z. B. mit fester IP:

```bash
YES=1 NET=192.168.1.50/24 GATEWAY=192.168.1.1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/ainerhd/six-ways-to-drink/main/install.sh)"
```

DNS-Eintrag und Reverse Proxy (z. B. Nginx Proxy Manager) werden nicht vom Installer angelegt. Proxy-Ziel ist `http://<container-ip>:80`.

## Update

Neue Fragen oder Code-Änderungen ins Repo pushen. Mit Auto-Update holt sich der Container den neuen Stand innerhalb einer Stunde selbst. Sofort geht es mit:

```bash
pct exec <CTID> -- update
```

Alle Befehle (im Container direkt, vom Proxmox-Host mit `pct exec <CTID> -- …`):

| Befehl | Wirkung |
|--------|---------|
| `update` | jetzt aktualisieren |
| `update --check` | nur prüfen, ob es eine neue Version gibt |
| `update --status` | installierte Version, Auto-Update an/aus, letzte Läufe |
| `update --enable-auto` | Auto-Update einschalten (systemd-Timer, stündlich) |
| `update --disable-auto` | Auto-Update ausschalten |

- `update` setzt das App-Verzeichnis hart auf den Stand von `origin/main` zurück. Lokale Änderungen im Container gehen dabei verloren.
- Der Updater aktualisiert sich selbst mit und schreibt `version.json` (Anzeige im Menü, Update-Hinweis in der App).
- Protokoll der automatischen Läufe: `journalctl -u six-ways-to-drink-update`
- Container, die vor dem Auto-Update installiert wurden: einmal `update` und danach `update --enable-auto` ausführen.

## Fragen bearbeiten

Alle Fragen stehen in `questions.json`:

```json
{ "id": 1, "type": "normal", "category": "harmlos", "text": "Wer im Raum ..." }
```

- `id`: eindeutige Zahl (Konvention: harmlos 1–99, peinlich 100–199, spicy 200–299, duell 300–399, party 400–499, zukunft 500–599, freundeskreis 600–699)
- `type`: `normal` oder `duel`
- `category`: `harmlos`, `party`, `zukunft`, `freundeskreis`, `peinlich`, `spicy` (bei Duell-Fragen `duell`). Eine neue Kategorie in `questions.json` taucht automatisch in der App auf.
- `text`: die Frage

## Lokal testen

`questions.json` wird per `fetch` geladen, deshalb braucht es einen Webserver:

```bash
python -m http.server 8080
# oder mit Node.js
npx http-server -p 8080 -c-1
```

Dann `http://localhost:8080` öffnen (am Handy im selben WLAN: `http://<pc-ip>:8080`). Lokal gibt es keine `version.json`, das Menü zeigt dann „Version: lokal“.
