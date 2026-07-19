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

---

## Ordner pro Waffe

Neben der einen Datei `<weapon_id>.wav` kann jede Waffe einen eigenen Ordner
haben, benannt nach dem letzten Teil ihrer ID (`weapon_rifle_ar15` → `ar15/`).
Darin liegen alle weiteren Geräusche:

| Datei | Wann |
| --- | --- |
| `schuss_gedaempft.wav` | sobald ein Schalldämpfer dranhängt |
| `nachladen_magazin_raus.wav` | 8 % des Nachladevorgangs |
| `nachladen_magazin_rein.wav` | 52 % |
| `nachladen_verschluss.wav` | 88 %, **nur bei leergeschossener Waffe** |

Die Nachladegeräusche hängen am Fortschritt, nicht an Sekunden — eine Waffe
mit langsamerem Nachladen dehnt sie mit. Fehlt eine Datei, bleibt es an der
Stelle still; das Nachladen läuft trotzdem.

**Gedämpft ist eine eigene Aufnahme, keine leisere.** Ein Schalldämpfer
verändert den Klang grundlegend — derselbe Knall leiser gedreht klingt nach
einem entfernten Schuss, nicht nach einem gedämpften.

## Aufnahmen zuschneiden

`ffmpeg` reicht dafür. Nach Ereignissen suchen:

```
ffmpeg -i roh.wav -af "silencedetect=noise=-45dB:d=0.12" -f null -
```

Ein Ereignis herausschneiden und auf Spielpegel bringen:

```
ffmpeg -ss 7.24 -to 8.30 -i roh.mp3 -map 0:a -ac 1 -ar 44100 \
       -af "loudnorm=I=-16:TP=-1.0:LRA=11" fertig.wav
```

`-map 0:a` ist wichtig: MP3s tragen oft ein Titelbild mit, das sonst als
zweiter Datenstrom mitkommt.
