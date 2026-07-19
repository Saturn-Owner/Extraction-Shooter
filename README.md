# Extraction Shooter

Ein Extraction-Shooter, gebaut mit [Godot 4.5](https://godotengine.org/download/).

## Setup (für neue Teammitglieder)

1. **Godot 4.5** (Standard-Version, nicht .NET) herunterladen: https://godotengine.org/download/
2. Repo klonen:
   ```
   git clone https://github.com/Saturn-Owner/Extraction-Shooter.git
   ```
3. Godot starten → **Importieren** → die Datei `project.godot` im Repo-Ordner auswählen.

## Projektstruktur

| Ordner     | Inhalt                                        |
| ---------- | --------------------------------------------- |
| `scenes/`  | Godot-Szenen (`.tscn`) – Level, Player, UI    |
| `scripts/` | GDScript-Dateien (`.gd`)                      |
| `assets/`  | Grafiken, Sounds, Modelle, Fonts              |

## Git-Workflow

- **Nie direkt auf `main` arbeiten** – für jedes Feature einen Branch erstellen:
  ```
  git checkout -b feature/player-movement
  ```
- Fertige Features per Pull Request auf GitHub mergen, damit der andere kurz drüberschauen kann.
- Vor dem Arbeiten immer erst `git pull`, um Konflikte zu vermeiden.
- **Wichtig bei Godot:** Nicht gleichzeitig an derselben `.tscn`-Szene arbeiten – Szenen-Dateien lassen sich schlecht mergen. Lieber absprechen, wer welche Szene anfasst.
- Der Ordner `.godot/` wird nicht committet (steht in der `.gitignore`) – den generiert Godot lokal neu.
