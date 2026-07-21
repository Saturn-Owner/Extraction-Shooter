# CLAUDE.md — Extraction Shooter

Diese Datei gilt für alle, die mit Claude an diesem Projekt arbeiten (Tim + Kollege, gemeinsamer Claude-Account, jeder auf seinem eigenen Rechner).

## Projekt

- **Spiel:** Extraction-Shooter
- **Engine:** Godot 4.7.1 (Standard-Version, nicht .NET) — beide nutzen exakt dieselbe Version
- **Sprache im Chat und in Commits:** Deutsch. Code (Variablen, Funktionen, Klassen) auf Englisch.

## Wer arbeitet gerade?

Der Claude-Account wird geteilt, aber jeder arbeitet auf seinem eigenen Rechner.
Claude: Prüfe bei Git-Aktionen mit `git config user.name`, wessen Rechner das ist,
und sprich die Person entsprechend an. Falls keine Git-Identität gesetzt ist,
zuerst danach fragen und sie mit `git config user.name` / `user.email` setzen.

## Projektstruktur

| Ordner     | Inhalt                                                  |
| ---------- | ------------------------------------------------------- |
| `scenes/`  | Godot-Szenen (`.tscn`) — Level, Player, Gegner, UI      |
| `scripts/` | GDScript-Dateien (`.gd`)                                |
| `assets/`  | Grafiken, Sounds, 3D-Modelle, Fonts                     |

Regeln:
- Jede Szene bekommt ihr Script mit gleichem Namen daneben gelegt oder in `scripts/` mit gleichem Namen (z. B. `scenes/player.tscn` + `scripts/player.gd`).
- Dateinamen in `snake_case` (Godot-Konvention): `player_movement.gd`, `extraction_zone.tscn`.
- Klassennamen in `PascalCase` mit `class_name` (z. B. `class_name PlayerMovement`).

## Architektur — Grundsatzentscheidungen

Diese fünf Punkte wurden bewusst festgelegt und dürfen nicht beiläufig geändert werden.
Der vollständige Entwicklungsplan liegt außerhalb des Repos beim jeweiligen Entwickler.

### 1. Alles ist datengetrieben

Items, Munition, Waffen, Platten, Verletzungen, Händler und Bunker-Upgrades sind
`Resource`-Klassen unter `scripts/data/` mit `.tres`-Dateien unter `assets/data/`.

**Eine neue Munitionssorte ist eine neue Datei, kein neuer Code.** Wer anfängt,
Werte in Skripte zu schreiben, macht es falsch.

### 2. Server-autoritativ von Anfang an

Alle zustandsverändernden Aktionen laufen über dieses Muster — auch solange das
Spiel noch allein läuft:

```
Client fragt an  →  Server prüft  →  Server ändert Zustand  →  Server informiert Clients
```

Der Client entscheidet **nie** selbst, dass ein Item ins Inventar wandert, ein
Gegner stirbt oder Geld gutgeschrieben wird. Er fragt und wartet auf Antwort.
Ohne diese Disziplin wird der spätere Multiplayer-Umbau ein Rewrite.

### 3. Godot Standard-Build genügt

Karten bleiben unter ~4 km Abstand vom Weltursprung. Damit reichen 32-bit-Floats.
Kein `precision=double`, kein Floating Origin. Falls Karten je größer werden
sollen, muss diese Entscheidung neu bewertet werden.

### 4. Schaden und Durchschlag sind getrennt

`AmmoData.damage` = Wirkung im Fleisch. `AmmoData.penetration_power` = ob die
Kugel durch die Platte kommt. Rüstung hat **kein** Stufensystem: Platten decken
nur Flächen ab, nutzen sich ab, und starke Munition geht durch. Der Spieler soll
jederzeit sterblich bleiben.

### 5. Jede Waffe hat ihr eigenes Modell und ihre eigenen Animationen

Pro Waffe eine eigene Datei unter `scripts/weapons/`, abgeleitet von
`WeaponViewmodel`. Verknüpft wird über das Feld `viewmodel` in der `.tres`
der Waffe — datengetrieben, siehe Punkt 1.

**Es gibt bewusst keine Einheitswaffe mit ausgetauschten Werten.** Eine
Pistole hat einen Schlitten, eine Vorderschaftrepetierflinte eine Pumpe, ein
Sturmgewehr einen Verschluss. Das sind unterschiedliche Bewegungen, keine
Varianten derselben. Jede Waffe soll sich einzigartig anfühlen und aussehen.

Arbeitsteilung:
- `scripts/combat/weapon_view.gd` — was im Kameraraum für **jede** Waffe
  gleich ist: Haltung, Zielen, Nachschwingen, Laufwackeln, Rückstossfeder.
  Diese Datei kennt kein einziges Waffenteil beim Namen.
- `scripts/weapons/*.gd` — Geometrie und Mechanik **dieser einen** Waffe.
- `scripts/combat/viewmodel_parts.gd` — gemeinsame Bauteile (Quader,
  Zylinder, Schienen), damit nicht jede Waffe ihre eigenen Helfer schreibt.

`GenericViewmodel` ist nur eine Notlösung, damit eine Waffe ohne eigenes
Modell spielbar bleibt statt unsichtbar zu sein. Welche Waffen noch daran
hängen, listet `verify_weapon_handling` bei jedem Lauf auf — die Liste soll
irgendwann leer sein.

Modelle kommen als `.glb` aus Blender — **nie als `.tscn`**. Szenen lassen
sich bei Konflikten nicht mergen; bei zwölf Waffen und zwei Entwicklern wäre
das eine dauerhafte Konfliktquelle. Eine `.glb` ist dagegen eine Binärdatei
wie ein Sound oder eine Textur: Einer bearbeitet sie, sie wird als Ganzes
ersetzt, fertig. Wo noch kein Modell existiert, wird die Geometrie im Code
gebaut (`ViewmodelParts`) — das ist der Übergangszustand, nicht das Ziel.

Regeln für den Export:

- **Ein Teil, eine Datei.** Der Lauf ist keine Datei, das Magazin schon:
  Alles, was sich unabhängig bewegt oder abgenommen werden kann, kommt
  einzeln. Verschmolzene Teile können sich nicht bewegen.
- **Bewegliche Teile heißen exakt** `Action`, `ChargingHandle`, `Trigger`,
  `Selector`, `Magazine`. `WeaponViewmodel._collect_parts()` sucht nach
  diesen Namen. Ein Tippfehler heißt: Das Teil sitzt richtig und bewegt sich
  nie — und das merkt man beim Spielen kaum.
- **Der Ursprung einer Teildatei liegt an seiner Einbaustelle** an der Waffe,
  die Geometrie selbst um null. `GlbParts.mount_point()` liest das aus. So
  weiß das Teil, wohin es gehört, und ein Verschieben in Blender braucht
  keine Codeänderung.
- **Achsen:** Blender exportiert mit +X als Mündung, das Spiel erwartet -Z.
  Die Umrechnung macht `GlbParts` an genau einer Stelle.

`tools/render_viewmodel.gd` rendert die Modelle aus neun Richtungen in PNGs,
mit `bestueckt` auch voll ausgestattet — damit man sie ansehen kann, ohne das
Spiel zu starten.

## Was Claude testen kann — und was nicht

Claude **kann** Godot im Headless-Modus über die Kommandozeile ausführen und damit
selbstständig prüfen, ob Code funktioniert:

```
Godot_v4.7.1-stable_win64_console.exe --headless --path <projekt> --import --quit-after 60
Godot_v4.7.1-stable_win64_console.exe --headless --path <projekt> --script res://mein_test.gd
```

Damit lassen sich Ladefehler, Parserfehler, `.tres`-Formatfehler und Rechenlogik
(Ballistik, Plattenwerte, Inventar-Belegung) ohne Menschen verifizieren.
**Claude soll das nach jeder Änderung selbst tun**, statt Tests an euch abzuschieben.

Claude kann **nicht**:

- beurteilen, wie sich Bewegung, Schießen oder Trefferfeedback *anfühlt*
- sehen, wie etwas aussieht (Grafik, UI-Layout, Animationen)
- 3D-Modelle, Texturen, Animationen oder Sounds erstellen
- Balancing bewerten, ohne dass jemand gespielt hat
- den Server betreiben oder überwachen

**Alles, was mit Gefühl, Optik oder Spielspaß zu tun hat, muss ein Mensch testen.**

Hinweis: Ist die installierte Godot-Version neuer als die im Projekt eingetragene,
NICHT direkt im Repo testen — Godot konvertiert das Projekt sonst und der andere
Entwickler kann es nicht mehr öffnen. Stattdessen auf einer Kopie testen.

## Git-Workflow (WICHTIG)

### Goldene Regeln

1. **Vor jedem Arbeitsbeginn:** `git pull` auf `main`, damit du den aktuellen Stand hast.
2. **Für JEDES neue Feature einen eigenen Branch — niemals direkt auf `main` arbeiten.**
   `main` muss immer ein funktionierendes, spielbares Spiel enthalten. Neue Features
   werden isoliert in einem Branch gebaut und erst nach dem Testen gemerged. So kann
   ein kaputtes oder halbfertiges Feature das laufende Spiel auf `main` nicht zerschießen —
   und wenn doch mal was schiefgeht, wirft man einfach den Branch weg statt `main` zu reparieren.
   ```
   git checkout main
   git pull
   git checkout -b feature/kurzer-name
   ```
   Branch-Namen sprechend wählen: `feature/spielerbewegung`, `feature/loot-system`, `fix/extraction-timer`.

   **Claude macht das von selbst:** Sobald eine Aufgabe ein neues Feature ist,
   legt Claude den Branch an, ohne zu fragen — frisch von `main`, sprechender
   Name. Der Nutzer muss nicht daran denken. Was NICHT auf einen neuen Branch
   gehört: kleine Fehlerbehebungen und Nacharbeiten am Feature, an dem gerade
   gearbeitet wird — die bleiben auf dessen Branch. Faustregel: Neues Feature =
   neuer Branch; Weiterbauen am laufenden Feature = gleicher Branch. Im
   Zweifel kurz fragen, ob es ein eigenes Feature sein soll.
3. **Fertige Features als Pull Request** auf GitHub erstellen (`gh pr create`). Den Code-Review übernimmt Claude — ein Mensch muss nicht gegenlesen. Nach dem Review wird der PR gemerged, erst dann landet das Feature auf `main`.
4. **Regelmäßig committen und pushen** — lieber viele kleine Commits als ein riesiger am Ende des Tages.
5. **Erst mergen, wenn das Feature in Godot getestet wurde** und das Spiel startet. Kaputten Code nicht auf `main` schieben.

### Szenen-Konflikte vermeiden (Godot-spezifisch!)

- `.tscn`- und `.tres`-Dateien lassen sich bei Konflikten praktisch **nicht sinnvoll mergen**.
- Deshalb: **Nie gleichzeitig an derselben Szene arbeiten.** Vorher kurz absprechen (z. B. per Chat), wer welche Szene anfasst.
- Claude: Wenn eine Aufgabe eine Szene betrifft, die laut `git log` kürzlich vom anderen geändert wurde, den Nutzer darauf hinweisen, bevor du sie änderst.
- Große Szenen lieber in kleine Unterszenen aufteilen — dann kann jeder an seinem Teil arbeiten.

### Was NICHT ins Repo gehört

- `.godot/` (lokaler Cache — steht in der `.gitignore`, Godot generiert ihn neu)
- Exportierte Builds (`.exe`, `.pck`)
- `export_presets.cfg` (kann lokale Pfade enthalten)

### Commit-Nachrichten

- Deutsch, kurz, im Imperativ oder als Beschreibung: `Spielerbewegung mit Sprint hinzugefügt`, `Fix: Extraction-Timer lief im Menü weiter`.

## Arbeitsweise mit Claude

- Claude soll vor Änderungen an bestehendem Code die betroffenen Dateien lesen und sich an den vorhandenen Stil halten.
- Nach größeren Änderungen selbst per Headless-Godot prüfen, dass alles lädt und rechnet (siehe oben), und danach kurz zusammenfassen, was noch ein Mensch im Editor testen muss — nämlich alles, was Gefühl, Optik oder Spielspaß betrifft.
- Bei Architektur-Entscheidungen (z. B. neues System wie Inventar, Loot, Netzwerk) erst einen kurzen Plan vorschlagen, bevor viel Code geschrieben wird.
