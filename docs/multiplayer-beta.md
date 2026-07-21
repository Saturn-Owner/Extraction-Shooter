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

## Launcher (der Weg für Tester)

Tester bekommen **eine** Datei: `ExtractionLauncher.exe` (eigenes
Mini-Godot-Projekt unter `launcher/`). Der Launcher

1. **meldet über Steam an** (Web-Login im Browser; Steam bestätigt die ID,
   unser Server prüft die Antwort gegen — wir speichern keine Passwörter).
   Anmelden ist optional, Gast geht weiterhin.
2. **hält das Spiel aktuell**: vergleicht `version.json` vom VPS mit der
   installierten Version, lädt bei Bedarf das ZIP und entpackt es.
3. **startet das Spiel** mit `--name`/`--token`; das Menü übernimmt beides.

Neuen Spielstand veröffentlichen (beides nötig, sonst weist der Server
alte Clients ab — `Net.PROTOCOL_VERSION` bei Protokolländerungen erhöhen!):

    .\tools\publish_client.ps1 -Godot "<Godot-Console-Exe>" -Key "<SSH-Schlüssel>"
    ./tools/deploy_server.sh root@193.23.160.41 <SSH-Schlüssel>     # Git Bash

Launcher selbst exportieren (nur nötig, wenn sich der Launcher ändert):
`launcher/export_presets.example.cfg` nach `export_presets.cfg` kopieren,
dann im Launcher-Ordner `--export-release "Windows Launcher"`.

Dienste auf dem VPS: `extraction-server` (Spiel, UDP 24567 + Auth TCP 24568)
und `extraction-downloads` (Updates, TCP 24569).

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

## Der VPS (bereits eingerichtet, Stand 21.07.2026)

Läuft auf **193.23.160.41** (ZAP-Hosting, Ubuntu 24.04). Aufbau:

- `/opt/extraction/godot/` — offizielle Godot-4.7.1-Linux-Binary. **Kein
  Export-Build nötig**: Der Server läuft mit der normalen Binary direkt auf
  dem Projektquellcode. Exakt 4.7.1, damit nichts konvertiert wird.
- `/opt/extraction/projekt/` — der Projektstand (aus `git archive HEAD`)
- systemd-Dienst `extraction-server` (läuft als Benutzer `extraction`,
  startet nach Absturz neu, UDP-Port 24567)

Tester verbinden sich im Startmenü mit `193.23.160.41` (Port ist vorbelegt).

## Neuen Stand ausrollen

```bash
./tools/deploy_server.sh root@193.23.160.41 /pfad/zum/ssh-schluessel   # Git Bash
```

Packt HEAD, kopiert, importiert, startet den Dienst neu. Log ansehen:

```bash
ssh -i <schluessel> root@193.23.160.41 'journalctl -u extraction-server -f'
```

Falls der VPS je neu aufgesetzt werden muss: Benutzer `extraction` anlegen,
Godot-Binary nach `/opt/extraction/godot`, `docs/extraction-server.service`
nach `/etc/systemd/system/`, `ufw allow 24567/udp` — dann normal ausrollen.

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
