# Herkunft der Umgebungsmodelle

Nach dem Muster von `assets/audio/player/QUELLEN.md`: Wer etwas ins Repo legt,
schreibt dazu, woher es kommt.

## container.res

| | |
| --- | --- |
| **Datei** | `container.res` — eine ArrayMesh mit zwei Flächen (Anstrich, Rahmen) |
| **Herkunft** | **Lucas' eigener Entwurf**, in Godot nachgebaut |
| **Lizenz** | uneingeschränkt, es ist Eigenarbeit |
| **Erzeugt von** | `tools/build_container.gd` |

### Wie er entstand

Lucas hat den Container in einer three.js-Seite entworfen: geriffelte Wände
(42 Rippen an den Langseiten, 14 an den Stirnseiten), ein dunkler Stahlrahmen
mit acht Eckbeschlägen, kräftige Farbe (`#2f6b8f`).

`tools/build_container.gd` baut **genau diese Vorlage** in Godot nach —
dieselben Maße, dieselbe Rippenzahl, dieselben Farbrollen — und fügt die über
hundert Quader zu **einer** Mesh zusammen. Das ist wichtig: Als einzelne Knoten
wären das bei vierhundert Containern zehntausende, und das Spiel würde stehen.
So liegt der Container vierhundertmal als dieselbe Ressource vor.

Die Mesh hat zwei Flächen — Anstrich und Rahmen —, damit jeder Container seinen
Anstrich umfärben kann (rot, gelb, blau, grün, grau), während der Stahlrahmen
immer dunkel bleibt.

### Kein fremdes Modell mehr

Eine frühere Fassung nutzte ein heruntergeladenes Modell (`container_pack.glb`,
Generator „Sketchfab"), dessen Weitergaberecht ungeklärt war. Das ist
**vollständig entfernt** — Mesh und Texturen. Der Container ist jetzt reine
Eigenarbeit, und die Lizenzfrage stellt sich nicht mehr.

Die Maße sind auf **6,0 × 2,6 × 2,4 m** gerundet (statt der echten 6,058 ×
2,591 × 2,438), damit sich Container im Editor bündig aneinanderschieben
lassen — das geht restlos in einem 0,2-m-Raster auf.

## Snow006

| | |
| --- | --- |
| **Dateien** | `assets/textures/snow/snow_*.jpg` |
| **Quelle** | ambientCG, Set `Snow006`, 1K |
| **Lizenz** | **CC0** (gemeinfrei, keine Auflagen) |

Vollständiger PBR-Satz: Farbe, Normalenkarte (die OpenGL-Fassung, die Godot
erwartet), Rauigkeit, Ambient Occlusion. Liegt auf dem Boden — der größten
Fläche der Karte. Verdrahtet in `WorldParts.snow_material()` mit Triplanar in
Weltkoordinaten, weil die Landflächen bis zu 330 m lang sind.

Kam aus einem Zip, das Lucas selbst erstellt hat (eine three.js-Seite mit dem
Container-Entwurf oben); der Schneesatz stammt ursprünglich von ambientCG.

## houses/ — Sketchfab-Häuser für den Karten-Generator

Alle sechs **CC BY 4.0**, per Sketchfab-API geprüft (wie beim AR-15 in
`assets/models/weapons/QUELLEN.md`). Rohdateien lagen zunächst unter
`C:\Users\lappe\Desktop\3d models red snow\`, aufbereitet nach demselben
Muster wie `tools/convert_ar15_sketchfab.gd` (Texturen verkleinert, vermessen).

| Datei | Titel | Autor | Quelle |
| --- | --- | --- | --- |
| `house_home.glb` | House Home - 53MB | Mehdi Shahsavan (ahmagh2e) | <https://sketchfab.com/3d-models/house-home-53mb-4aa178e6c8b14dcf855de2fdee075f17> |
| `windmill.glb` | Windmill | Yury Misiyuk (Tim0) | <https://sketchfab.com/3d-models/windmill-0730705327e045bd8cb98a888bd0f954> |
| `old_wooden_watchtower_house.glb` | Old Wooden Watchtower (House 3) | Blenderust (narighillya) | <https://sketchfab.com/3d-models/old-wooden-watchtower-house-3-49b77f82b0944d5188c04c3fc205a499> |
| `psx_abandoned_house.glb` | PSX Abandoned House | Arimantos | <https://sketchfab.com/3d-models/psx-abandoned-house-f5d781d374f74eb099be2add7e7c4925> |
| `old_house.glb` | Old house | Yury Misiyuk (Tim0) | <https://sketchfab.com/3d-models/old-house-19a1121bab5a4aaaad4d973abe5b61cb> |
| `old_wooden_barn_house.glb` | Old Wooden Barn (House 4) | Blenderust (narighillya) | <https://sketchfab.com/3d-models/old-wooden-barn-house-4-3366ee69c2dd4908a99f386e07faa1d6> |
| `trees/snow_pine_pack.glb` | Snow Pine Tree and Bush Pack LOWPOLY | EFX (evan4129) | <https://sketchfab.com/3d-models/snow-pine-tree-and-bush-pack-lowpoly-7afc4ca23dd84adea90dc0ba8506c500> |

**Bewusst NICHT dabei**: "Lake Hawea House" (Azimuth Design, CC BY 4.0,
<https://sketchfab.com/3d-models/lake-hawea-house-1188937400694f1a899741fd49b8dda3>).
Auch nach Verkleinern der Texturen 80 MB gross (652.000 Dreiecke, ein
Photogrammetrie-Scan) — reisst die 50-MB-Testgrenze aus `verify_frachthafen.gd`
(schuetzt vor GitHubs harter 100-MB-Push-Grenze). Ohne verlaessliches Werkzeug
zur Netzvereinfachung bleibt sie aussen vor.

**PFLICHT FÜR DIE CREDITS**: Sobald es einen Abspann gibt, gehört für jede
Zeile oben eine Namensnennung hinein (Titel, Autor, CC BY 4.0). Bis dahin
erfüllt diese Tabelle die Namensnennung im Quell-Repository.
