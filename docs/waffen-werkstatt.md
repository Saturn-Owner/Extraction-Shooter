# Branch `feature/waffen-werkstatt`

Stand: 20.07.2026 · 30 Commits · 190 Dateien · rund 10.500 Zeilen

Dieser Branch macht aus der Waffe ein sichtbares, hörbares und anpassbares
Ding. Vorher war eine Waffe eine Zahl im Inventar, die beim Klicken einen
Zähler heruntersetzte.

---

## Was jetzt da ist

### 1. Waffen haben Modelle und Mechanik

Jede Waffe hat ihre eigene Datei unter `scripts/weapons/`, abgeleitet von
`WeaponViewmodel`. Verknüpft wird über das Feld `viewmodel` in der `.tres` —
datengetrieben, kein `match` über Waffennamen.

| Datei | Waffe | Herkunft |
| --- | --- | --- |
| `ar15_viewmodel.gd` | AR-15 | **`.glb` aus Blender** |
| `akm_viewmodel.gd` | AKM | im Code gebaut |
| `glock17_viewmodel.gd` | Glock 17 | im Code gebaut |
| `m870_viewmodel.gd` | M870 | im Code gebaut |
| `generic_viewmodel.gd` | Notnagel | im Code gebaut |

Die Arbeitsteilung aus `CLAUDE.md` steht:

- `scripts/combat/weapon_view.gd` — was für **jede** Waffe gleich ist:
  Haltung, Zielen, Nachschwingen, Laufwackeln, Rückstossfeder. Diese Datei
  kennt kein einziges Waffenteil beim Namen.
- `scripts/weapons/*.gd` — Geometrie und Mechanik **dieser einen** Waffe.
- `scripts/combat/viewmodel_parts.gd` — gemeinsame Bauteile (Quader,
  Zylinder, Schienen), damit nicht jede Waffe eigene Helfer schreibt.

`tools/render_viewmodel.gd` rendert jede Waffe aus neun Richtungen in PNGs,
auf Wunsch voll bestückt — man sieht sich ein Modell an, ohne das Spiel zu
starten. `tools/inspect_viewmodel.gd` misst statt zu zeigen: Es gibt
Positionen und Ausmasse einzelner Teile als Zahlen aus. Beide Werkzeuge sind
mehrfach der Grund gewesen, warum ein Fehler gefunden wurde, bevor du ihn
melden musstest.

### 2. Die AR-15 kommt aus Blender

Zehn `.glb`-Dateien unter `assets/models/weapons/ar15/`, ein Teil je Datei.
`scripts/combat/glb_parts.gd` ist die **einzige** Stelle, die von
Blender-Koordinaten nach Godot umrechnet (Blender: +X = Mündung, Godot:
−Z = Mündung, also +90° um Y).

Bewegliche Teile heissen exakt `Action`, `ChargingHandle`, `Trigger`,
`Selector`, `Magazine` — `WeaponViewmodel._collect_parts()` sucht nach diesen
Namen. Ein Tippfehler heisst: Das Teil sitzt richtig und bewegt sich nie.

**Zwei Fallen, die hier stecken und beim nächsten Modell wieder auftauchen:**

- Godot legt beim Import eine leere `AuxScene` über die Datei und schiebt die
  Wurzeltransformation aufs Kind. `scene.position` ist nach `instantiate()`
  deshalb **immer null**. Der Einbauort steht in
  `_first_node_3d(scene).position`. Wer das übersieht, bekommt zehn Teile am
  selben Punkt.
- Die Basisdatei enthält Schalldämpfer und einen zweiten Ladehebel mit. Die
  werden über die **Lage** herausgefiltert (`STRIP_FORWARD_OF_X`,
  `BUILT_IN_HANDLE`), nicht über den Namen — Godot vergibt je nach
  Exportreihenfolge „Mesh", „Mesh2", darauf ist kein Verlass.

Alle alten AR-15-Anbauteile aus Code-Geometrie sind entfernt. AKM, Glock und
M870 hängen weiter an Code-Modellen; `verify_weapon_handling` listet bei jedem
Lauf auf, welche Waffen noch am `GenericViewmodel` hängen.

### 3. Anbauteile und Werkbank

`scripts/data/attachment_data.gd` + `weapon_mount.gd` beschreiben Steckplätze
und Wirkung. Die Waffe rechnet ihre effektiven Werte aus Basis + Anbauteilen
(`weapon_build.gd`) — nichts davon steht in einem Skript fest.

Die Werkbank steht im Testgelände (`scripts/world/workbench_station.gd`,
Oberfläche in `scripts/ui/workbench_ui.gd`):

- vier Spalten: Waffe, Steckplätze, verfügbare Teile, Werte
- 3D-Vorschau mit Drehteller (`scripts/ui/weapon_preview.gd`, eigene
  `World3D` im `SubViewport`)
- Wertevergleich beim Überfahren eines Teils, bevor man es einbaut
- Instandsetzung gegen Zustandsverlust

**Warum die Station anfangs nicht reagierte** — steht hier, weil es sich
wiederholen wird: `Area3D.collision_mask` steht ab Werk auf `1`, der Spieler
liegt auf Ebene `2`. Jeder neue interaktive `Area3D` braucht
`collision_mask = PLAYER_LAYER`.

### 4. Ton

Echte Aufnahmen unter `assets/audio/weapons/ar15/` statt Synthese.
`weapon_audio.gd` sucht den Klang über den Waffen-Ordner und den Kurznamen;
unterhalb von `SUPPRESSED_BELOW = 0.6` greift die gedämpfte Aufnahme.

- Schuss ungedämpft, Schuss gedämpft, 20 Nachladegeräusche
- Nachladen ruft die Geräusche bei 8 %, 52 % und 88 % des Vorgangs ab
- **Sechs Stimmen** (`AUDIO_VOICES`), nicht eine. Bei 80 ms Schussabstand und
  2,6 s Aufnahme schneidet eine einzelne Stimme sich selbst ab — Dauerfeuer
  klang dadurch wie Klicken.

Beim Aufbereiten der Aufnahmen: **`loudnorm` verfälscht.** Deine Originale
lagen bei Spitze −0,0 dB, meine erste Fassung bei −5,9. Nur Spitzenpegel
anheben, führende Stille abschneiden, sonst nichts.

Ungenutzt liegen noch `schuss_innen.wav`, `schuss_fern.wav` und
`schuss_fenster_offen.wav` — die brauchen ein System, das Innen/Aussen und
Entfernung kennt.

### 5. Schiessen und Treffer

- Die **Kamera zielt, die Mündung schiesst.** Vorher startete die Kugel am
  Lauf und flog *parallel* zur Blickrichtung — 14 cm daneben, auf jede
  Entfernung.
- Der Zielpunkt eines Rotpunkts ist der **Leuchtpunkt**, nicht der Ursprung
  des Visiers (`ar15_glb_part.gd::aim_centre()` misst die Fläche mit dem
  Material `dot`). Die 6,8 mm Unterschied sind bei 0,16 m Zielabstand 2,4° —
  auf 25 m ein voller Meter zu tief.
- Einschusslöcher als `Decal` (`bullet_hole.gd`), höchstens 96 gleichzeitig.
- Ein an der Mündung verankerter Strich für 0,13 s. **Sichtbare Flugbahn gibt
  es bewusst nicht** — auf deinen Wunsch wieder entfernt.

### 6. Mündungsknall (3 von 4 Schritten)

`scripts/player/muzzle_blast.gd` führt einen Belastungswert, der pro Schuss
steigt und mit der Zeit fällt. Abstimmung komplett in
`assets/data/effects/muzzle_blast_default.tres`.

| Schritt | Inhalt | Zustand |
| --- | --- | --- |
| 1 | Belastungswert, Kamerawackeln | fertig |
| 2 | Blendung (`blast_overlay.gd`) | fertig |
| 3 | Pulverdampf (`powder_smoke.gd`) | fertig |
| 4 | **Gehör: Busse, Dämpfung, Tinnitus** | **offen** |

Zwei Entscheidungen, die kein Zufall sind:

- **Unterhalb `threshold` passiert exakt nichts.** Einzelschüsse bleiben
  folgenlos — das ist die Zusage, an der der ganze Effekt hängt.
- **Der Dampf bleibt in der Welt stehen** (`local_coords = false`) und hat
  eine **eigene Quelle** mit umgekehrtem Vorzeichen: Ein Schalldämpfer fängt
  die Gase ab und lässt sie langsam austreten, deshalb qualmt gedämpft
  *mehr*. Ungedämpft kommt weniger und ist zusätzlich gedeckelt.

Das Wackeln hat drei Anläufe gebraucht (zu schwach → zu stark → zu schnell).
Was hängengeblieben ist: **Langsam schlägt schnell.** Schnelle kleine
Ausschläge lesen sich als Wackelkontakt, langsames Schwanken als Wucht.
`shake_speed` steht deshalb auf 6,5, nicht auf 14.

---

## Tests

`tools/run_tests.ps1` führt zehn Suiten aus, alle grün.

| Suite | Prüfungen |
| --- | --- |
| `verify_attachments.gd` | 87 |
| `verify_weapon_handling.gd` | 82 |
| `verify_blast.gd` | 79 |
| `verify_feedback.gd` | 77 |
| `verify_workbench.gd` | 40 |

Dazu die bestehenden `verify_ballistics`, `verify_inventory`,
`verify_item_data`, `verify_loadout`, `verify_player`.

**Drei Lehren aus Tests, die grün waren und trotzdem nichts wert:**

1. Ein Test darf sich **nicht selbst den Zustand hinlegen**, den er prüfen
   soll. `verify_workbench` setzte `station.user = player` von Hand — genau
   der Schritt, der kaputt war. Läuft jetzt über die echte Physik.
2. Prüfungen brauchen **beide Schranken**. Das Wackeln war vierzigmal zu
   schwach und der Test bestand trotzdem, weil er nur nach oben prüfte —
   null besteht eine Obergrenze mühelos.
3. Warten auf ein **Ereignis**, nicht auf eine Framezahl. Das hat den
   flakigen Werkbank-Test behoben.

Bei allem Optischen ist die Rückkopplung ein Wegwerf-Skript, das schiesst und
ein Bild macht. Das hat die weissgewaschene Blendung (0,55 additiv auf
Schnee), die als Rauten sichtbaren Rauchpartikel und eine übersehene
Leuchtkapsel in `projectile.tscn` gefunden.

---

## Offen

**Als Nächstes:** Mündungsknall Schritt 4 — Gehör. Audio-Busse zur Laufzeit
über `AudioServer.add_bus()` (bewusst **kein** `project.godot`-Eintrag, die
Datei ist zwischen den Branches ohnehin auseinandergelaufen),
`AudioEffectLowPassFilter` auf einem Bus `Welt`, die sechs Waffenstimmen
dorthin routen, Tinnitus als geloopter Doppelsinus (4500/4508 Hz).

Dabei fällt ein vorhandener Fehler mit ab: **`loudness_multiplier` erreicht
die Lautstärke gar nicht.** Ein gedämpfter Schuss klingt bei jeder Waffe
ausser der AR-15 exakt so laut wie ein ungedämpfter — nur die AR-15 hat eine
eigene leise Aufnahme.

Ehrlich dazu: Der Gehör-Nachteil verpufft vorerst. Die Waffe ist die einzige
Tonquelle im Spiel; es gibt keine Schritte und keine Gegner, die man
überhören könnte. Heute ist es Stimmung.

Weiter offen:

- Glock, AKM und M870 laufen auf Code-Modellen und synthetischem Ton
- Glock-Sortiment an der Werkbank ist dünn — je ein Teil pro Steckplatz
- `assets/data/gear/backpack_small.tres` hat `category = 7` statt 6
- `PlayerInteraction._raycast_forward()` (Kollege) liefert nur
  `LootContainer` — braucht nach dem Merge eine gemeinsame Schnittstelle
- Innen/Aussen- und Entfernungston für die drei ungenutzten Aufnahmen
- Der Branch ist reif für einen PR

---

## Was ein Mensch testen muss

Nichts davon kann ein Test beantworten:

- Fühlt sich das Wackeln nach Wucht an oder nach kaputt?
- Ist die Blendung in einem **dunklen** Raum zu stark? Abgestimmt wurde auf
  Schnee, und additiv wirkt derselbe Wert dort viel kräftiger.
- Steht der Dampf im Weg, ohne zu nerven? Er soll ein Nachteil sein, den man
  durch Zurseitetreten löst.
- Ist die Schwelle richtig — bleiben Einzelschüsse wirklich folgenlos?
- Sitzt die AR-15 gut in der Hand, und bewegen sich alle fünf Teile?
- Reicht die Auswahl an der Werkbank, oder ist die Entscheidung trivial?
