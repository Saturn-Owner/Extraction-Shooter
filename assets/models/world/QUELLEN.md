# Herkunft der Umgebungsmodelle

Nach dem Muster von `assets/audio/player/QUELLEN.md`: Wer etwas ins Repo legt,
schreibt dazu, woher es kommt und was damit gemacht wurde. Sonst rät ein Jahr
später niemand mehr, ob man es weitergeben darf.

## container_20ft

| | |
| --- | --- |
| **Datei im Repo** | `container_20ft.res` + drei `.webp` |
| **Quelle** | `container_pack.glb`, laut Lucas selbst erstellt |
| **Lizenz** | **noch zu klären — siehe unten** |
| **Material im Paket** | `20Ft_Generic_Old` |

### Offene Frage zur Lizenz

Im Kopf der Originaldatei steht:

```
"generator": "Sketchfab-14.68.0"
```

Die Datei wurde also von **Sketchfab** exportiert. Das muss kein Widerspruch
sein — es kann sein, dass der Weg über Sketchfab lief. Aber solange nicht
geklärt ist, ob und unter welcher Lizenz das Modell weitergegeben werden darf,
**gehört es nicht in ein öffentliches Repository.**

Zu klären, bevor gepusht wird: Wer ist der Urheber, und unter welcher Lizenz?

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

In `Weathered Shipping Container Model.zip` lag ein Schnee-Texturensatz von
**ambientCG** (`Snow006`, 1K JPG, CC0) — Color, Normal, Roughness, Ambient
Occlusion, sogar mit fertiger `.tres`. Ein Containermodell war **nicht** darin.

Bisher nicht eingebaut: Der Schnee läuft über prozedurales Rauschen mit
Triplanar (`WorldParts._surface()`). Wäre der nächste Kandidat, wenn der Boden
zu gleichförmig wirkt.
