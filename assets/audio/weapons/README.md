# Waffensounds

Hier gehören echte Schuss-Aufnahmen rein. Solange der Ordner leer ist,
erzeugt das Spiel synthetische Ersatzgeräusche — die klingen brauchbar,
aber nicht realistisch. Synthese kann keine echte Explosion mit Raumhall
nachbilden.

## Wie die Dateien heißen müssen

Das Spiel sucht beim Laden einer Waffe in dieser Reihenfolge und nimmt
den ersten Treffer:

| Priorität | Dateiname | Beispiel |
| --- | --- | --- |
| 1 | `<weapon_id>.ogg` | `weapon_rifle_ak74m.ogg` |
| 2 | `<caliber>.ogg` | `7.62x39.ogg` |
| 3 | `default.ogg` | für alles Übrige |

`.wav` und `.mp3` funktionieren genauso. Die Waffen-IDs stehen in den
`.tres`-Dateien unter `assets/data/weapons/`.

**Empfehlung zum Anfangen:** Eine Datei pro Kaliber reicht völlig. Neun
Dateien decken damit alle zwölf Waffen ab:

```
9x19.ogg   .45 ACP.ogg   5.45x39.ogg   5.56x45.ogg   7.62x39.ogg
7.62x51.ogg   7.62x54R.ogg   .338 LM.ogg   12-70.ogg
```

## Woher nehmen

- **Sonniss GDC Game Audio Bundle** — erscheint jährlich, kostenlos,
  ausdrücklich auch kommerziell nutzbar. Enthält sehr gute Waffenaufnahmen.
  Die mit Abstand beste Quelle für dieses Projekt.
- **freesound.org** — riesige Auswahl, aber die Lizenz muss **pro Datei**
  geprüft werden. CC0 ist unproblematisch, CC-BY verlangt Namensnennung.

Finger weg von Sounds aus anderen Spielen oder von YouTube — das ist
Urheberrechtsverletzung, auch bei einem Hobbyprojekt.

## Worauf beim Auswählen achten

- **Kurz und trocken** ist besser als lang und hallig. Räumlichen Hall
  fügt Godot später selbst hinzu, je nach Umgebung (Höhle vs. Freifläche).
- **Mono** statt Stereo. Die Waffe ist eine Punktquelle im 3D-Raum; eine
  Stereodatei klingt bei `AudioStreamPlayer3D` falsch.
- Keine Aufnahmen mit Stimmen, Klicks oder Windgeräuschen am Anfang.

## Sind sie drin, passiert automatisch das Richtige

Kein Code muss geändert werden — Datei ablegen, Spiel starten, fertig.
Die Tonhöhe variiert bei jedem Schuss leicht, damit Dauerfeuer nicht wie
eine Maschine klingt.

Nachladegeräusche sind aktuell **stumm geschaltet**, weil die synthetische
Version schlecht klang. Sobald es echte Aufnahmen gibt, kann das in
`scripts/combat/weapon.gd` in `reload()` wieder eingehängt werden.
