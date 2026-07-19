# CLAUDE.md — Extraction Shooter

Diese Datei gilt für alle, die mit Claude an diesem Projekt arbeiten (Tim + Kollege, gemeinsamer Claude-Account, jeder auf seinem eigenen Rechner).

## Projekt

- **Spiel:** Extraction-Shooter
- **Engine:** Godot 4.5 (Standard-Version, nicht .NET) — beide nutzen exakt dieselbe Version
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

## Git-Workflow (WICHTIG)

### Goldene Regeln

1. **Vor jedem Arbeitsbeginn:** `git pull` auf `main`, damit du den aktuellen Stand hast.
2. **Nie direkt auf `main` committen.** Immer einen Feature-Branch erstellen:
   ```
   git checkout main
   git pull
   git checkout -b feature/kurzer-name
   ```
3. **Fertige Features als Pull Request** auf GitHub erstellen (`gh pr create`), der andere schaut kurz drüber und merged.
4. **Regelmäßig committen und pushen** — lieber viele kleine Commits als ein riesiger am Ende des Tages.

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
- Nach größeren Änderungen kurz zusammenfassen, was getestet werden muss — Godot-Szenen kann Claude nicht selbst starten, das Testen im Editor übernimmt der Mensch.
- Bei Architektur-Entscheidungen (z. B. neues System wie Inventar, Loot, Netzwerk) erst einen kurzen Plan vorschlagen, bevor viel Code geschrieben wird.
