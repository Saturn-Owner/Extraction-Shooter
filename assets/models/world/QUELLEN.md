# Herkunft der Umgebungsmodelle

Nach dem Muster von `assets/audio/player/QUELLEN.md`: Wer etwas ins Repo legt,
schreibt dazu, woher es kommt und was damit gemacht wurde. Sonst rät ein Jahr
später niemand mehr, ob man es weitergeben darf.

## container_20ft

| | |
| --- | --- |
| **Datei im Repo** | `container_20ft.res` + drei `.webp` |
| **Quelle** | `container_pack.glb` — **fremdes Modell**, nicht selbst erstellt |
| **Generator laut Datei** | `Sketchfab-14.68.0` |
| **Nutzungsrecht** | Lucas gibt an, es benutzen zu dürfen |
| **Weitergaberecht** | **ungeklärt — siehe unten** |
| **Material im Paket** | `20Ft_Generic_Old` |

### Warum das noch nicht gepusht werden darf

Benutzen und weitergeben sind zwei verschiedene Rechte. Ein öffentliches
Repository ist **Weitergabe**: Jeder, der es klont, bekommt `container_20ft.res`
und die Texturen und kann sie herausziehen.

Die meisten Asset-Lizenzen (Sketchfab Standard, die üblichen Store-Lizenzen)
erlauben den Einsatz im fertigen Spiel, verbieten aber genau das — die Datei so
abzulegen, dass sie sich wieder entnehmen lässt.

**Zu klären, bevor dieser Ordner gepusht wird:**

1. Woher stammt `container_pack.glb` genau (Seite, Autor, Titel)?
2. Erlaubt die Lizenz die Weitergabe der Quelldatei in einem Repository?

Falls nein, gibt es einen sauberen Ausweg: Die Dateien bleiben lokal und
kommen in die `.gitignore`. `WorldParts.has_container_model()` prüft das
bereits — ohne die Modelldateien baut die Karte wieder Quader statt roter
Fehler. Der Kollege sähe dann Kisten, wo Lucas Container sieht; unschön, aber
lauffähig.

### Nachbearbeitung

Das Original ist **675 MB** groß — fast ausschließlich Texturen: 40 PNGs zu je
rund 28 MB bei 4096 × 4096. GitHub weist jede Datei über 100 MB beim Push ab,
also war ein Auszug nötig.

`tools/extract_containers.gd` macht daraus:

| Datei | Was | Größe |
| --- | --- | --- |
| `container_20ft.res` | nur die eine Mesh, ohne Texturen | 111 KB |
| `container_20ft_basecolor.webp` | **entfärbt**, 4096 → 2048 | 692 KB |
| `container_20ft_orm.webp` | Occlusion/Roughness/Metallic, 4096 → 2048 | 1077 KB |
| `container_20ft_normal.webp` | Normalenkarte, 4096 → 2048 | 1340 KB |

**Zusammen 3,2 MB statt 675 MB.**

Zwei Entscheidungen dabei:

- **Die BaseColor ist entfärbt** (Luminanz nach Rec. 709). Die Containerfarbe
  war in der Textur eingebacken; Rot über einen bereits rostroten Container
  multipliziert gibt Matsch. Jetzt trägt eine einzige Textur alle Farben —
  Rost, Dellen und Streifen bleiben, die Farbe kommt aus dem Material.
- **WebP statt JPEG.** Bei Normalenkarten sind JPEG-Artefakte als Griesel auf
  der Oberfläche sichtbar, weil die Kanäle Richtungen sind und kein Bild.

### Maße

Das Modell ist roh **6,405 × 2,924 × 2,416 m** — ein High-Cube, und lauter
krumme Zahlen. Im Spiel wird es auf **6,0 × 2,6 × 2,4** normiert
(`WorldParts.CONTAINER_SIZE`). Das geht restlos in einem 0,2-m-Raster auf,
damit sich Container im Editor bündig aneinanderschieben lassen. Die Rechnung
dafür steht in `WorldParts.container_mesh_transform()` und passt sich an, wenn
jemand eine andere Variante extrahiert.

## Snow006 (noch nicht eingebaut)

In `Weathered Shipping Container Model.zip` — **von Lucas selbst erstellt**,
eine three.js-Seite, die einen Container aus 16 Quadern zeichnet — lag ein
Schnee-Texturensatz von **ambientCG** (`Snow006`, 1K JPG, **CC0**): Color,
NormalGL, NormalDX, Roughness, Ambient Occlusion, dazu eine fertige `.tres`.

Ein Containermodell war in dem Zip **nicht** enthalten; die Geometrie dort ist
three.js-Code, keine Mesh.

Die mitgelieferte `.tres` ist nicht direkt verwendbar: Sie verweist auf eine
`Displacement`-Karte, die im Zip fehlt, und sie hat kein Triplanar — auf der
330 m langen Bodenplatte würde die Textur zu Matsch gezogen.

Bisher nicht eingebaut: Der Schnee läuft über prozedurales Rauschen mit
Triplanar (`WorldParts._surface()`). Wäre der nächste Kandidat, wenn der Boden
zu gleichförmig wirkt.
