# Herkunft der Fundgeräusche

Für **jede** Audiodatei in diesem Ordner ein Eintrag. Ohne Nachweis lässt
sich später nicht mehr belegen, dass wir sie benutzen dürfen — und
"weiß ich nicht mehr" heißt im Zweifel: rausnehmen und neu suchen.

## Von Lucas herausgesucht

Quelle und Lizenz **bitte nachtragen** — ohne Nachweis müssen diese
Dateien vor einer Veröffentlichung wieder raus.

| Datei | Original | Quelle | Lizenz |
| --- | --- | --- | --- |
| `food.wav` | `essen finden variante 1.wav` | ? | ? |
| `food_canned_meat.wav` | `essen finden variante 2 plastic verpackung.wav` | ? | ? |
| `misc.wav` | `misc item finden zb schrauben.wav` | ? | ? |
| `medical.wav` | Sammel-MP3, Ereignis bei 9,39 s | ? | ? |
| `med_painkillers.wav` | Sammel-MP3, Ereignis bei 0,66 s | ? | ? |
| `tool.wav` | `eisen item finden ZB nahkampf waffe.mp3` | ? | ? |

### Wie ausgewählt wurde

Claude kann nicht hören. Die Auswahl stützt sich deshalb auf **gemessene
Eigenschaften** der zerlegten Aufnahmen, nicht auf Gehör:

| Datei | Messwerte | Begründung |
| --- | --- | --- |
| `tool.wav` | 816 Hz, Nachklang 0,22 s | tief mit echtem Nachschwingen — schweres Eisen |
| `medical.wav` | 9323 Hz, 0,11 s | sehr hell und kurz — Blister, Folie |
| `med_painkillers.wav` | 8441 Hz, 0,80 s | hell und rauschig — Tablettendose |

Ob es *richtig klingt*, muss ein Mensch entscheiden. Alle 26 zerlegten
Ereignisse liegen in `Klangproben/sammlung` zum Nachhören; tauschen heißt
nur, eine andere Datei unter demselben Namen abzulegen.

## OpenGameArt (CC0)

| Datei | Original | Autor | Quelle | Lizenz |
| --- | --- | --- | --- | --- |
| `key.ogg` | `keys_03.ogg` | rubberduck | [100 CC0 metal and wood SFX](https://opengameart.org/content/100-cc0-metal-and-wood-sfx) | CC0 |
| `weapon.ogg` | `metal_slam_01.ogg` | rubberduck | dieselbe Sammlung | CC0 |
| `ammo.ogg` | `metal_hit_05.ogg` | rubberduck | dieselbe Sammlung | CC0 |
| `armor_plate.ogg` | `metal_falling_01.ogg` | rubberduck | dieselbe Sammlung | CC0 |
| `default.ogg` | `wood_hit_03.ogg` | rubberduck | dieselbe Sammlung | CC0 |

CC0 heißt Public Domain: Nutzung, Änderung und kommerzieller Vertrieb sind
erlaubt, eine Namensnennung ist nicht erforderlich. Wir führen sie trotzdem,
weil wir sonst irgendwann nicht mehr wissen, woher eine Datei stammt.

## Wie die Namen wirken

`food.wav` gilt für **alle** Verpflegung, `food_canned_meat.wav` nur für
die Fleischkonserve — der genauere Name gewinnt. So lässt sich ein
einzelner Gegenstand herausheben, ohne den Rest anzufassen.

## Noch ohne eigene Aufnahme

Diese Kategorien greifen auf `default.ogg` zurück — ein Holzklopfen:

- `backpack` / `clothing` — bräuchte Stoff. In keiner der vorhandenen
  Aufnahmen ist etwas Stoffartiges: Alle Ausschnitte sind entweder hell
  und rauschig (Folie) oder metallisch, nichts davon klingt weich.

## Warum die OpenGameArt-Dateien bleiben

`key`, `weapon`, `armor_plate`, `ammo` und `default` stammen weiterhin von
rubberduck. Diese Aufnahmen sind **benannt aufgenommen** — eine Datei
heißt `keys_03`, weil dort Schlüssel klimpern.

Die Ausschnitte aus der Sammel-MP3 sind dagegen unbeschriftet. Sie durch
Fragmente zu ersetzen, von denen ich nur die Frequenz kenne, wäre ein
Rückschritt: Ich könnte nicht begründen, dass ein Metallgeräusch bei
5476 Hz nach Schlüsseln klingt und nicht nach einer Gabel.

Wenn beim Anhören eine Stelle besser passt, sag welche Nummer — dann
tausche ich.
