# Herkunft der Spielergeräusche

Für **jede** Audiodatei in diesem Ordner ein Eintrag. Ohne Nachweis lässt
sich später nicht mehr belegen, dass wir sie benutzen dürfen — und
"weiß ich nicht mehr" heißt im Zweifel: rausnehmen und neu suchen.

## Schritte im Schnee

| Datei | Original | Autor | Quelle | Lizenz |
| --- | --- | --- | --- | --- |
| `schritt_schnee_01.wav` … `_11.wav` | `sfx_snow_footstep-01.wav` | bajko | [freesound.org/s/378056](https://freesound.org/s/378056/) | CC0 |

## Ausser Atem

| Datei | Original | Autor | Quelle | Lizenz |
| --- | --- | --- | --- | --- |
| `ausser_atem.wav` | `Man breathing regularly then faster` | exe2be | [freesound.org/s/512741](https://freesound.org/s/512741/) | CC0 |

CC0 heißt: kopieren, verändern, verbreiten, auch kommerziell, ohne
Namensnennung. Die Namen stehen hier trotzdem — weil es sich gehört und
weil man sonst nicht mehr nachvollziehen kann, wo etwas herkam.

## Nachbearbeitung

**Die Schritte** kamen als **eine** Aufnahme von 168 Sekunden, 48 kHz stereo
24 bit, 46 MB. So gehört sie nicht in ein Repo, und einen Schritt kann man
daraus auch nicht abspielen.

```
godot --headless --path . --script res://tools/split_sounds.gd -- <datei> <ordner>
```

Das Werkzeug fand **149 einzelne Geräusche**. Elf davon liegen jetzt hier.
Claude kann nicht hören — ausgewählt wurde deshalb nach **gemessenen**
Eigenschaften, nicht nach Gehör:

| Kriterium | Wert | Warum |
| --- | --- | --- |
| Dauer | 0,32 – 0,41 s | Ein einzelner Tritt. Kürzeres ist abgeschnitten, längeres sind zwei verschmolzene Schritte |
| Nulldurchgänge | 4760 – 5980 Hz | Alle aus demselben Band: derselbe Mensch, dieselbe Schneedecke. Ausreisser bis 7800 Hz klingen nach anderem Untergrund |
| Nachklang | kurz bis mittel | Schnee dämpft. Was lange nachschwingt, war nicht der Fuss |
| Vorlauf | unter 25 ms | Ein Schritt muss sofort anfangen, sonst kommt er später als der Fuss |

Herkunft in der Originalaufnahme (Sekunde): 5,49 · 25,18 · 30,27 · 46,69 ·
81,19 · 86,37 · 97,50 · 101,76 · 103,55 · 112,58 · 114,02

**Aussortiert:** Der Schnipsel bei 51,48 s war zuerst dabei und ist wieder
rausgeflogen — er hatte 126 ms Stille am Anfang. Aufgefallen ist das nicht
beim Hören, sondern in `verify_player_audio.gd`, das genau darauf prüft.

Jeder Schnipsel wurde auf Mono gemischt, auf Spitze 0,90 normalisiert und an
den Rändern aus- und eingeblendet. Abtastrate bleibt 48 kHz — Godot kommt
damit klar, und Umrechnen kostet nur Qualität.

**Das Atmen** war 16 Sekunden lang und ging von ruhig zu schnell. Gebraucht
wird nur der schnelle Teil:

```
godot --headless --path . --script res://tools/cut_range.gd -- <datei>
```

Die Übersicht zeigte den Umschlag deutlich — bis 10 s Spitzenpegel 0,015–0,054
und höchstens ein Atemzug je Sekunde, ab 11 s dann 0,088–0,178 und zwei. Also:

```
... -- <datei> assets/audio/player/ausser_atem.wav 11.05 15.95
```

4,9 Sekunden, normalisiert, mit längeren Blenden an den Rändern, weil die
Datei im Spiel als Schleife läuft.

## Was aus 46 MB wurde

| | vorher | jetzt |
| --- | --- | --- |
| Schritte | 46 MB, eine Datei | rund 400 KB, elf Dateien |
| Atmen | 1,4 MB | 422 KB |
