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
