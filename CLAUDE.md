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

Diese vier Punkte wurden bewusst festgelegt und dürfen nicht beiläufig geändert werden.
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

### 3. Godot 4.5 Standard-Build

Karten bleiben unter ~4 km Abstand vom Weltursprung. Damit reichen 32-bit-Floats.
Kein `precision=double`, kein Floating Origin. Falls Karten je größer werden
sollen, muss diese Entscheidung neu bewertet werden.

### 4. Schaden und Durchschlag sind getrennt

`AmmoData.damage` = Wirkung im Fleisch. `AmmoData.penetration_power` = ob die
Kugel durch die Platte kommt. Rüstung hat **kein** Stufensystem: Platten decken
nur Flächen ab, nutzen sich ab, und starke Munition geht durch. Der Spieler soll
jederzeit sterblich bleiben.

## Grenzen von Claude in diesem Projekt

Damit keine falschen Erwartungen entstehen — Claude kann in diesem Projekt **nicht**:

- Godot starten, Szenen testen oder beurteilen, wie sich etwas anfühlt
- 3D-Modelle, Texturen, Animationen oder Sounds erstellen
- Balancing bewerten, ohne dass jemand gespielt hat
- den Server betreiben oder überwachen

**Nach jeder Änderung muss ein Mensch im Editor testen.** Claude schreibt Code
und erklärt ihn; ob es Spaß macht, entscheidet ihr.

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
3. **Fertige Features als Pull Request** auf GitHub erstellen (`gh pr create`), der andere schaut kurz drüber und merged. Erst dann landet das Feature auf `main`.
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
- Nach größeren Änderungen kurz zusammenfassen, was getestet werden muss — Godot-Szenen kann Claude nicht selbst starten, das Testen im Editor übernimmt der Mensch.
- Bei Architektur-Entscheidungen (z. B. neues System wie Inventar, Loot, Netzwerk) erst einen kurzen Plan vorschlagen, bevor viel Code geschrieben wird.
