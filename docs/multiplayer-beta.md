# Multiplayer-Beta — Anleitung

Branch: `feature/multiplayer-beta`. Läuft NICHT auf `main`, bis der Beta-Test
durch ist.

## Was das ist

Ein dedizierter Server (VPS oder lokal) + beliebig viele Clients über ENet.
Gespielt wird in der Arena (`scenes/levels/arena_beta.tscn`): Paintball-Feld
50×70 m, begehbares Gebäude in der Mitte, vier Spawn-Ecken mit Werkbank.
Endlos, jeder gegen jeden — Tod heißt 5 Sekunden warten, dann Respawn an der
eigenen Ecke mit frischer Gesundheit. Kills zählt die Anzeige oben links.

Geschossen wird mit dem ECHTEN Schadenssystem: Körperteile, Durchschlag,
Ballistik mit Flugzeit. Der Server entscheidet jeden Treffer — der Client
zeigt nur Leuchtspur und Effekte (Grundsatz 2, jetzt wirklich übers Netz).

## Schnellstart am eigenen Rechner (ohne VPS)

1. Spiel starten → Startmenü.
2. F9 → `host` → dieses Fenster ist jetzt Server.
3. Zweites Spielfenster starten → Adresse `127.0.0.1` → „Mit Server verbinden".

Oder für einen unsichtbaren Server in der Konsole:

    Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --server --port 24567

## Konsole (F9)

| Befehl | Wirkung |
| --- | --- |
| `connect <ip[:port]>` | Mit Server verbinden (Standardport 24567) |
| `disconnect` | Verbindung trennen |
| `status` | Modus, Peer-Liste, Kills |
| `name <spielername>` | Anzeigename setzen |
| `host [port]` | Dieses Fenster wird reiner Server |
| `die` | Testtod — prüft Todesbildschirm und Respawn |
| `help` / `clear` / `quit` | das Übliche |

Neue Befehle registriert jedes System selbst über
`DevConsole.instance.register_command(...)` — die Konsole kennt keine
Spiellogik.

## Export (Client-.exe und Server-Build)

Einmalig: Im Editor unter *Editor → Exportvorlagen verwalten* die Vorlagen
für **4.7.1** herunterladen. `export_presets.cfg` liegt nicht im Repo — die
eingecheckte Vorlage `export_presets.example.cfg` wird beim ersten Lauf des
Export-Skripts automatisch kopiert.

    .\tools\export_beta.ps1 -Godot "<Pfad zur Godot-Console-Exe>"

Ergebnis:

- `build/windows/extraction_shooter.exe` — **an die Tester verteilen**
  (pck ist eingebettet, eine Datei genügt)
- `build/linux/extraction_server.x86_64` — für den VPS

## VPS einrichten (Ubuntu/Debian, einmalig)

Alle Befehle führt Tim/Lucas per SSH selbst aus.

```bash
# 1. Benutzer und Verzeichnis
sudo useradd -r -m -d /opt/extraction extraction
sudo mkdir -p /opt/extraction
sudo chown extraction:extraction /opt/extraction

# 2. Firewall: Spielport freigeben (ENet = UDP!)
sudo ufw allow 24567/udp

# 3. systemd-Dienst
sudo cp extraction-server.service /etc/systemd/system/   # aus docs/
sudo systemctl daemon-reload
sudo systemctl enable extraction-server
```

Empfehlung: SSH-Schlüssel statt Passwort (`ssh-keygen` auf dem eigenen
Rechner, dann `ssh-copy-id benutzer@vps`). Danach fragt kein Skript mehr
nach einem Passwort.

## Neuen Stand ausrollen

```bash
./tools/deploy_server.sh benutzer@vps-adresse    # in der Git Bash
```

Kopiert den Build, tauscht ihn aus, startet den Dienst neu. Log ansehen:

```bash
ssh benutzer@vps 'journalctl -u extraction-server -f'
```

Tester verbinden sich dann im Startmenü mit `<vps-adresse>` (Port 24567 ist
vorbelegt).

## Was der Server prüft (und was noch nicht)

Geprüft: Absender lebt, Munition existiert und passt zum Kaliber der
getragenen Waffe, Kadenz nicht schneller als die Waffe kann, Abschusspunkt
in Avatar-Nähe. Die Streuung würfelt der Server selbst.

**Noch nicht geprüft** (bewusst nach der Beta): Bewegungsgeschwindigkeit
(Clients sind für ihre Position autoritativ), Munitionsvorrat serverseitig,
Lag-Kompensation. Steht als TODO in `player_controller.gd` und
`net_manager.gd`.

## Technische Landkarte

| Datei | Aufgabe |
| --- | --- |
| `scripts/net/net_manager.gd` | Autoload `Net`: Transport, Roster, Spawns, Treffer-RPCs |
| `scripts/net/net_bootstrap.gd` + `scenes/main.tscn` | Einstieg: Server/Menü/Solo |
| `scripts/net/remote_avatar.gd` | Mitspieler-Figur; trägt auf dem Server die Trefferzonen |
| `scripts/net/player_net_sync.gd` | Brücke Spieler → Avatar + Schussmeldung |
| `scripts/net/net_shot.gd` | Autoritativer Serverschuss (echte Projektile) |
| `scripts/ui/dev_console.gd` | F9-Konsole mit Befehlsregister |
| `scripts/ui/main_menu.gd` | Startmenü |
| `scripts/levels/arena_level.gd` | Arena: Spawnen, Startausrüstung, Tod/Respawn-Anzeige |
| `tests/verify_net.gd` | Testsuite mit echtem Server-Prozess |

Der Solo-Weg (Raid Eisstadt, Testgelände) ist unverändert — ohne Verbindung
merkt kein System, dass es das Netzwerk gibt.
