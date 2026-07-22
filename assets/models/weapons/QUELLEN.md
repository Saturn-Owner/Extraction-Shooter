# Herkunft der Waffenmodelle

Nach dem Muster von `assets/audio/player/QUELLEN.md`: Wer etwas ins Repo legt,
schreibt dazu, woher es kommt.

## ar15/ar15.glb

| | |
| --- | --- |
| **Datei** | `ar15/ar15.glb` — komplette AR-15 mit beweglichen Teilen und Anbauteilen |
| **Herkunft** | "AR-15" von **wafla**, Sketchfab: <https://sketchfab.com/3d-models/ar-15-33e225811b404192b89dcd4096603fbe> |
| **Autor** | wafla — <https://sketchfab.com/wafla> |
| **Lizenz** | **CC BY 4.0** (Namensnennung; kommerzielle Nutzung erlaubt) |
| **Aufbereitet von** | `tools/convert_ar15_sketchfab.gd` (Texturen auf 1024 px, Hüllknoten entfernt, vermessen) |

**PFLICHT FÜR DIE CREDITS**: Sobald das Spiel einen Abspann/Credits-Bildschirm
hat, gehört dort die Zeile hinein:

> AR-15 model by wafla (sketchfab.com/wafla), licensed under CC BY 4.0

Bis dahin erfüllt diese Datei die Namensnennung im Quell-Repository.

## ar15/AR15_Red-Dot.glb und ar15/AR15_AngledForegrip.glb

| | |
| --- | --- |
| **Herkunft** | Eigenarbeit (Blender), Reste des alten AR-15-Modells |
| **Lizenz** | uneingeschränkt, Eigenarbeit |
| **Status** | Übergang — im Sketchfab-Modell gibt es kein Gegenstück; ein eigenes Modell darf sie ablösen (siehe ar15_red_dot.gd / ar15_foregrip_angled.gd) |

## akm/akm.glb

Siehe Kommentar in `scripts/weapons/akm_viewmodel.gd`: Lucas' Vorlage,
CC0 von Sketchfab.
