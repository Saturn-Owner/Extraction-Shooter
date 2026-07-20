# Fundgeräusche

Echte Aufnahmen für das Durchsuchen von Kisten. Was hier liegt, **ersetzt
automatisch die synthetischen Platzhalter** aus `scripts/loot/search_audio.gd` —
es muss dafür keine Zeile Code geändert werden.

## Benennung

Gesucht wird von speziell nach allgemein:

| Datei | greift bei |
| --- | --- |
| `ammo_556x45_m995.wav` | genau diesem Gegenstand |
| `weapon.wav` | allen Waffen |
| `ammo.wav` | aller Munition |
| `armor_plate.wav` | allen Schutzplatten |
| `key.wav` | allen Schlüsseln |
| `medical.wav` | allem medizinischen |
| `food.wav` | Verpflegung |
| `backpack.wav` / `clothing.wav` | Rucksäcke, Kleidung |
| `default.wav` | allem Übrigen |

Der Kategoriename entspricht dem Eintrag in `ItemData.Category`, kleingeschrieben.
Endungen: `.ogg`, `.wav` oder `.mp3`.

Mit **einer Datei je Kategorie** ist man fertig. Einzelne Gegenstände lassen
sich später gezielt herausheben, ohne den Rest anzufassen.

## Anforderungen

- **Mono**, nicht Stereo. Das Geräusch kommt aus der Kiste vor einem, nicht
  von links oder rechts.
- **Kurz**: 0,3 bis 0,8 Sekunden. Länger blockiert den nächsten Fund akustisch.
- **Trocken**, ohne Hall. Der Raum kommt später aus der Engine — Hall in der
  Datei lässt sich nicht mehr entfernen.
- **Ohne Stille am Anfang.** Ein Vorlauf von 200 ms wirkt im Spiel wie
  Verzögerung, nicht wie Klang.

## Lizenz — bitte ernst nehmen

Nur **CC0** (Public Domain) oder ausdrücklich kommerziell freie Quellen.

Kein Audio aus YouTube-Videos, Spielen oder Filmen, auch nicht "nur zum
Testen". Solche Dateien überleben jeden Prototyp, landen im Release und
fallen genau dann auf, wenn es teuer wird.

**Für jede Datei die Herkunft in `QUELLEN.md` eintragen** — Titel, Autor,
URL, Lizenz. Ohne diesen Nachweis lässt sich später nicht mehr belegen,
dass wir sie benutzen dürfen.

## MP3 zerlegen

Die Werkzeuge unter `tools/` lesen nur WAV. Für MP3 gibt es aber bereits
ein `ffmpeg` auf dem Rechner, das CapCut mitbringt:

```
C:\Users\<Benutzer>\AppData\Local\CapCut\Apps\<Version>\ffmpeg.exe
```

Umwandeln und dabei gleich auf Mono bringen:

```
ffmpeg -i eingabe.mp3 -ac 1 -ar 44100 -c:a pcm_s16le ausgabe.wav
```

Einen Ausschnitt herausschneiden (`-ss` Startzeit, `-t` Dauer):

```
ffmpeg -ss 0.48 -t 0.30 -i ganz.wav -c:a pcm_s16le stueck.wav
```

Danach normalisieren — leise Ausschnitte sind sonst im Spiel unhörbar.
Erst den Pegel messen, dann die Differenz als Verstärkung anwenden:

```
ffmpeg -i stueck.wav -af volumedetect -f null NUL
ffmpeg -i stueck.wav -af "volume=+12dB" -c:a pcm_s16le fertig.wav
```

**Vorsicht bei sehr leisen Stellen:** Wer +17 dB draufgibt, hebt das
Rauschen genauso mit an. Wenn es zischt, lieber eine lautere Stelle in
der Aufnahme suchen.

## Brauchbare Quellen

- **freesound.org** — riesig, Filter auf CC0 stellen. Download braucht ein
  kostenloses Konto.
- **pixabay.com/sound-effects** — kleiner, dafür Download ohne Konto.
- **Sonniss GDC Game Audio Bundle** — jährlich, mehrere hundert GB, für
  kommerzielle Spiele freigegeben.
- **opengameart.org** — auf die Lizenz je Datei achten, dort ist nicht
  alles CC0.
