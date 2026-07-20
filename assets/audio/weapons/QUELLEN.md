# Herkunft der Waffensounds

| Datei | Original | Aufnahme von | Quelle | Lizenz |
| --- | --- | --- | --- | --- |
| `7.62x54R.wav` | `mosin.wav` | Tabasco | [Gunshot Sounds](https://opengameart.org/content/gunshot-sounds) | CC0 |
| `7.62x39.wav` | `sks.wav` | Tabasco | dieselbe Sammlung | CC0 |
| `12_70.wav` | `shotty.wav` | Tabasco | dieselbe Sammlung | CC0 |
| `9x19.wav` | `cz.wav` | Tabasco | dieselbe Sammlung | CC0 |

Echte Aufnahmen vom Schießstand, CC0 (Public Domain).

## Nachbearbeitung

Die Originale sind 6 bis 16 Sekunden lang, Stereo, und enthalten **mehrere
Schüsse hintereinander**. Unbearbeitet würde im Spiel bei jedem Schuss die
ganze Serie abgespielt.

Zugeschnitten mit `tools/trim_gunshots.gd`:

- auf den ersten Schuss gekürzt (0,4 bis 1,4 s)
- nach Mono gemischt — ein Schuss soll aus der Richtung kommen, in die der
  Spieler zielt; Stereo bringt seine eigene Richtung mit und lässt sich im
  3D-Raum nicht mehr platzieren
- auf gleichen Spitzenpegel normalisiert, damit die Lautstärke im Spiel
  geregelt wird und nicht in den Dateien
- am Ende ausgeblendet, sonst knackt der Schnitt

## Zuordnung

Drei Kaliber passen **exakt**: Mosin Nagant ist 7.62x54R, SKS ist 7.62x39,
die Schrotflinte ist 12/70.

`9x19.wav` ist eine **Näherung**: Aufgenommen wurde eine CZ-52 in 7.62x25.
Als Pistolenschuss passt der Charakter, die Patrone ist aber eine andere.
Bei Gelegenheit durch eine echte 9-mm-Aufnahme ersetzen.

## Fehlt noch

Diese Kaliber haben keine Aufnahme und klingen deshalb weiterhin
synthetisch — das fällt im direkten Vergleich auf:

- **5.56x45** (AR-15)
- **5.45x39** (AK-74M)
- **7.62x51** (M14, SCAR-H)
