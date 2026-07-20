# Änderungen

Was auf `main` gelandet ist, und warum. Neueste Einträge oben.

Diese Datei ist für den Menschen gedacht, der nach zwei Wochen Pause wissen
will, was sich geändert hat, ohne 37 Commit-Nachrichten zu lesen. Die
Begründungen im Einzelnen stehen weiterhin in den Commits.

---

## 20.07.2026 — Zweite Karte: Frachthafen

Branch `feature/karte-frachthafen`.

Die alte Karte war ein Platzhalter, und die Zahlen sagten es deutlich:
160 × 160 m Boden, aber der ganze Inhalt passte in 50 × 48 m — **9 % genutzt**.
Vier freistehende Wände ohne Dach, kein Innenraum, keine Höhenunterschiede.

Das Schlimmste war der Süd-Ausgang: **10 m vom Spawn**. Man konnte einen Raid
in zwölf Sekunden beenden, ohne eine Kiste anzufassen — es gab also nichts zu
entscheiden, und die Entscheidung *„gehe ich noch tiefer rein?"* ist der ganze
Sinn des Genres.

`raid_eisstadt.tscn` bleibt unangetastet und spielbar. Die neue Karte ist eine
eigene Szene daneben.

### Der Schauplatz

Ein eingefrorener **Frachthafen** — und das ist keine Geschmacksfrage, sondern
folgt aus dem Bestand: Es gibt **null Umgebungsmodelle** im Projekt, nur
AR-15-Teile. Jede Geometrie muss aus Quadern entstehen. Seecontainer *sind*
Quader; sie stapeln sich zu Gassen, Dächern und Sackgassen. Graubox sieht hier
nicht nach fehlendem Asset aus, sondern nach Hafen.

Von Süd nach Nord: **Kai** (Spawn, Wohnungsloot, Rucksack) → **Containerfeld**
(sieben Reihen, Werkstattloot, begehbare Dächer) → **Kranbrücke** auf 6 m mit
zwei 18-m-Türmen → **Lagerhalle** 34 × 22 m mit drei Zugängen und dem
Militärloot.

Bespielt: rund **110 × 125 m**, gut fünfmal so viel wie vorher. 114 Festkörper,
13 Kisten, 3 Ausgänge.

### Die Entscheidung, um die es geht

Das beste Zeug liegt **101 m vom Spawn** in der Lagerhalle. Zurück kommt man

- über den **Eisbrecher** — mit 38 m der nächste Ausgang, aber **15 Sekunden
  stillstehen**, tief in der Karte, oder
- den ganzen Weg zurück zum **Fischerkai**: sicher, aber 110 m beladen.

Der dritte, **Kranhaus**, liegt oben auf der Brücke: kurzer Timer, mitten auf
der Karte — man steht dabei sechs Meter hoch und für jeden sichtbar.

Der nächste Ausgang liegt jetzt **52 m vom Spawn** statt 10. Der schnellste
mögliche Raid dauert **33 Sekunden** statt zwölf.

### Gebaut im Code, Layout als Daten

Eine Karte mit hundert Quadern wäre eine riesige `.tscn` — und die lassen sich
bei Konflikten nicht mergen. Die Szene bleibt deshalb dünn (Himmel, Sonne,
Boden, Player, HUD); die Welt baut `scripts/levels/frachthafen_layout.gd`,
genau wie `workbench_station.gd` es für die Werkbank vormacht.

Damit die Karte trotzdem anfassbar bleibt, steht das **Layout als Daten oben in
der Datei**. Eine Gasse aufmachen heisst: eine Zahl aus einer Reihe streichen.

Neu dazu `scripts/world/world_parts.gd` — das Gegenstück zu `ViewmodelParts`,
das es für Waffen längst gab und für die Welt fehlte: `solid()` (Mesh **und**
Kollision in einem, sonst baut man Kulissen), `ramp()`, `container_stack()` und
`building()` mit echten Wandöffnungen.

### Höhe nur über Rampen

Der Spieler springt knapp **0,8 m** — ein Container ist 2,59 m hoch. Es gibt
keine Stufenbehandlung im `PlayerController`. Also drei Rampen zwischen 19° und
20°, weit unter Godots 45°-Grenze, und keine einzige Stufe.

### Was die Tests an einer Karte prüfen können

Mehr als man denkt — 73 Prüfungen in `tests/verify_frachthafen.gd`. Die zwei
interessantesten sind keine Geometrieprüfungen, sondern **Design-Prüfungen**:

- **„Gutes Zeug liegt weit weg"** ist eine Behauptung über Koordinaten: Jede
  Militärkiste liegt tiefer drin als jede Wohnungskiste (101 m gegen 30 m), und
  der nächste Ausgang beim Militärloot hat mindestens 12 Sekunden Timer. Wer
  die Halle später verschiebt, bekommt es hier gesagt statt im Spiel.
- **Die Brücke muss frei bleiben.** Der Laufsteg beginnt bei 5,60 m, ein
  Zweierstapel endet bei 5,18 m — vier Zentimeter mehr als eine Handbreit. Wer
  in `CONTAINER_ROWS` bei z = 6 eine Höhe von 2 auf 3 setzt, schiebt einen
  Container mitten durch die Brücke.

Dazu: Rampenwinkel, keine Kiste in einer Wand, Spawn im Freien, Loot-Tabellen
gültig, alles unter 4 km vom Ursprung, alle Festkörper auf Ebene 1.

### Nebenbei: ein toter Ausgang auf der alten Karte

`AusgangKlippe` verlangte `backpack_small` — **ein Item, das es nicht gibt**.
Der Ausgang war damit dauerhaft unbenutzbar und zeigte nur „benoetigt:
backpack_small". Ist auf `backpack_wander` korrigiert; der neue Test fängt
diese Sorte Fehler künftig ab.

### Starten

`project.godot` bleibt unangetastet — `raid_eisstadt` ist weiterhin die
Startszene. Die neue Karte öffnet man in Godot und drückt **F6**.

---

## 20.07.2026 — Der Rucksack

Merge von `feature/rucksack` nach `main`.

Die Taschen fassen zwölf Felder, und ein Sturmgewehr belegt zehn davon. Es gab
bis dahin keinen Weg, daran etwas zu ändern — man konnte Ausrüstung finden,
aber nichts, was mehr Platz schafft.

### Das Item

- **Wanderrucksack** (`assets/data/gear/rucksack_wander.tres`) — reine Daten,
  kein neuer Item-Code. Innen **6x4 = 24 Felder**, doppelt so viel wie die
  eigenen Taschen.
- Zusammengelegt ist er selbst **4x2 gross** und passt damit noch in die
  Taschen. Das ist Absicht: Ein Fund, den man nicht aufheben kann, weil er
  nirgends hineinpasst, wäre schlimmer als gar keiner.
- 1,4 kg leer. Was drin liegt, **wiegt mit** und bremst.

### Die Kiste vor dem Einstieg

- Neue **Ausruestungskiste** 2,5 m vor dem Spawn, eigene Loot-Tabelle
  (`assets/data/loot/ausruestung.tres`) mit `empty_weight = 0`: Sie enthält
  **immer genau einen Rucksack**, nie nichts. Der Test würfelt 50 Mal und
  prüft das.
- Durchsuchzeit auf 0,6 gekürzt — direkt beim Start soll man nicht drei
  Sekunden stehen.

### Rechtsklick → Öffnen → schwebendes Fenster

- **Rechtsklick auf einen Rucksack** öffnet ein kleines Menü mit dem Eintrag
  **"Oeffnen"**. Der Inhalt erscheint in einem eigenen Fenster, das man an der
  **Titelleiste verschieben** und mit dem **X schliessen** kann.
- Der Rechtsklick funktioniert **überall**, wo ein Behälter liegt: auf dem
  Ausrüstungsplatz, auf einem Rucksack in den Taschen und auf einem in der
  Loot-Kiste. Damit kann man in eine gefundene Tasche hineinsehen, **bevor**
  man sie mitnimmt — genau die Entscheidung, um die es beim Looten geht.
- **Nicht auf einem unaufgedeckten Umriss.** Ein Menü mit "Oeffnen" würde
  verraten, dass dort ein Behälter liegt, und die Frage "warte ich das ab?"
  wäre entwertet.
- Zweiter Eintrag darunter: **"Ausruesten"**, aber nur, solange der Gegenstand
  **nicht** schon am Körper hängt. Damit geht ein gefundener Rucksack in zwei
  Klicks an den Mann, statt über ins-Raster-ziehen → Tab → auf den Platz
  ziehen. Gilt für **jedes** Ausrüstungsteil, nicht nur für Rucksäcke — eine
  Sonderregel wäre willkürlich gewesen.
- Aus der Kiste heraus funktioniert das auch: Der Gegenstand wird entnommen,
  ohne je durch ein Raster zu wandern. Scheitert das Anlegen, geht er
  unverändert auf seinen Platz in der Kiste zurück.
- Zwei neue, bewusst allgemein gehaltene Bausteine: `ContextMenu` (Einträge
  kommen von aussen — "Ablegen" und "Aufteilen" sind absehbar) und
  `ContainerWindow`. Beide gab es im Projekt vorher nicht: **kein `PopupMenu`,
  kein `Window`, kein verschiebbares Panel und kein einziger Rechtsklick.**

### Die Falle beim Tauschen

Wer einen zweiten Rucksack anzieht, verdrängt den ersten. Der muss irgendwohin —
und die naheliegende Reihenfolge (neuen anlegen, dann den alten wegräumen)
hätte den alten **in den neuen gelegt**, samt allem, was darin lag. Ein
Rucksack im Rucksack, unbemerkt, bis man ihn ablegt und alles weg ist.

`equip_item()` nimmt deshalb erst ab, sucht dann Platz, und legt erst zuletzt
an. Geht etwas schief, wird alles zurückgedreht. Der Test legt einen gefüllten
Rucksack an, tauscht ihn gegen einen zweiten und prüft danach, dass der erste
in den Taschen liegt, **nicht** im neuen, und seine 20 Patronen noch hat.
- Das Fenster lässt sich **nicht aus dem Bild schieben** — es bleibt immer ein
  Streifen Titelleiste greifbar. Sonst bekäme man es nie wieder zu fassen und
  auch nicht mehr zu.
- Es gehört seinem Wirtfenster und geht mit ihm zu. Ein Rucksackfenster, das
  offen bleibt, während man weiterläuft, wäre ein zweiter Bildschirm mitten im
  Raid.
- Das linke Raster heisst jetzt **"Taschen"** statt "Ausruestung". Es zeigte
  noch nie die Ausrüstung, und der Name war schon vorher irreführend.

### Drei stille Verluste, die dabei aufgefallen sind

Ein zweites Raster bricht jede Stelle, die selbstverständlich von einem
einzigen ausging. Jeder dieser Fehler fällt im Spiel erst auf, wenn schon
etwas weg ist:

- **Munition im Rucksack war beim Nachladen unsichtbar.** Man hätte mit vollem
  Rucksack vor einer leeren Waffe gestanden. `count_ammo`, `take_ammo` und
  `get_compatible_ammo` durchsuchen jetzt beide Raster.
- **Eine Waffe aus dem Rucksack in die Hand hätte sie verdoppelt.**
  `equip_weapon` und `assign_weapon` suchten sie nur in den Taschen und
  entfernten sie dort — also nirgends. Sie hätte danach zweimal existiert.
- **Der Rucksack hätte in sich selbst wandern können**, samt Inhalt.
  `PlayerController._contains_grid()` sperrt das, rekursiv — auch über eine
  Tasche im Rucksack hinweg.

### Verifikation

Zwei neue Suiten: `tests/verify_backpack.gd` (**35 Prüfungen**) und
`tests/verify_container_window.gd` (**34 Prüfungen**). Alle 15 Suiten grün,
zusammen 1.143 Prüfungen.

**Von einem Menschen zu prüfen:** ob sich das Fenster gut anfassen und
verschieben lässt, ob das Menü an der richtigen Stelle aufgeht, ob 24 Felder
die richtige Grösse sind und ob die Kiste an der richtigen Stelle steht.

---

## 20.07.2026 — Schritte im Schnee und Keuchen beim Sprinten

Merge von `feature/schrittgeraeusche` nach `main`. **3 Commits.**

Die Waffe war bis dahin die einzige Tonquelle im Spiel — man lief lautlos
durch eine Schneelandschaft.

### Schritte

- Elf Varianten, geschnitten aus einer **168 Sekunden langen Aufnahme**
  (CC0, bajko, Freesound 378056). Aus 46 MB wurden 400 KB.
- Ausgewählt nach **Messwerten statt Gehör**: Dauer 0,32–0,41 s (ein einzelner
  Tritt, keine zwei verschmolzenen), gleiches Frequenzband, kurzer Nachklang,
  kein Vorlauf.
- Der Takt hängt an der **zurückgelegten Strecke**, nicht an einem Timer. Alle
  0,90 m ein Tritt beim Gehen, 0,75 m geduckt, 1,25 m im Sprint. Dadurch stimmt
  die Trittfrequenz von selbst — auch wenn Gewicht oder ein zerschossenes Bein
  bremsen.
- **Geduckt ist 8 dB leiser als gehen.** Schleichen soll sich lohnen,
  spätestens wenn es Gegner gibt.

### Ausser Atem

Setzt nur ein, wenn **5 Sekunden am Stück gesprintet** wurde **und** die
Ausdauer unter 15 liegt. Aufgehört wird erst über 35 — mit nur einer Schwelle
ginge es an der Grenze im Sekundentakt an und aus.

### Neues Werkzeug

`tools/cut_range.gd` schneidet einen Bereich aus einer durchgehenden Aufnahme.
Ohne Bereich zeigt es Pegel und Ereignisdichte je Sekunde — damit liess sich
im Atemgeräusch der Umschlag von ruhig zu schnell bei 11 s finden, ohne es zu
hören.

### Von den Tests gefunden

- Ein Schnipsel hatte **126 ms Stille am Anfang** — der Schritt wäre spürbar
  nach dem Fuss gekommen. Ersetzt.
- Die erste Messung meldete **0,08 s für einen 0,4-Sekunden-Schritt**: Godot
  importiert Tondateien komprimiert (QOA), in `AudioStreamWAV.data` stehen dann
  keine Samples mehr. Gemessen wird jetzt die Datei auf der Platte.

---

## 20.07.2026 — Waffenwerkstatt: Modelle, Anbauteile, Werkbank, Ton

Merge von `feature/waffen-werkstatt` nach `main`.
**32 Commits, 193 Dateien.**

Aus der Waffe wird ein sichtbares, hörbares und anpassbares Ding. Vorher war
sie eine Zahl im Inventar, die beim Klicken einen Zähler heruntersetzte.

### Waffenmodelle

- **Jede Waffe hat ihr eigenes Modell und ihre eigene Mechanik.** Eine Pistole
  hat einen Schlitten, eine Flinte eine Pumpe, ein Sturmgewehr einen
  Verschluss — das sind verschiedene Bewegungen, keine Varianten derselben.
  Verknüpft über das Feld `viewmodel` in der `.tres`.
- Die **AR-15 kommt als zehn `.glb`-Dateien aus Blender**, ein Teil je Datei.
  Verschluss, Ladehebel, Abzug, Feuerwahlhebel und Magazin bewegen sich.
- AKM, Glock und M870 laufen weiter auf Geometrie aus dem Code.
  `verify_weapon_handling` listet bei jedem Lauf auf, welche Waffen noch am
  Platzhalter hängen.

### Anbauteile und Werkbank

- Steckplätze für Visier, Mündung, Vorderschaft und Griff. Ein Teil passt nur,
  wenn die Waffe den Platz **und** dieselbe Schnittstelle hat — ein
  9-mm-Dämpfer geht nicht auf ein 5,56er Gewehr.
- **Werkbank im Testgelände**: 3D-Vorschau mit Drehteller, Wertevergleich beim
  Überfahren, Instandsetzung gegen Zustandsverlust.
- Bestückung und Verschleiss gehören zum **Exemplar**, nicht zum Waffentyp.
  Zwei AR-15 im selben Rucksack können verschieden bestückt und verschieden
  abgenutzt sein.

### Ton

- Echte AR-15-Aufnahmen statt Synthese, dazu 20 Nachladegeräusche.
- **Sechs Stimmen statt einer.** Mit einer klang Dauerfeuer wie Klicken: Bei
  750 Schuss/min liegen 80 ms zwischen den Schüssen, die Aufnahme ist 2,6 s
  lang — zu hören war immer nur der Anschlag.
- **Zwei Audio-Busse**, zur Laufzeit angelegt statt in `project.godot`, damit
  die Projekteinstellungen keine Konfliktquelle werden.

### Mündungsknall

Dauerfeuer ohne Schalldämpfer blendet, vernebelt, rüttelt und lässt die Ohren
pfeifen. **Einzelschüsse bleiben folgenlos** — unterhalb der Schwelle passiert
exakt nichts.

- Vier Effekte aus einer Quelle, aber mit verschiedenem Gedächtnis: Blendung
  vergeht in gut einer Sekunde, ein Pfeifen im Ohr bleibt zwölf.
- Der **Pulverdampf bleibt in der Welt stehen**, nicht an der Kamera. Er steht
  in der Ziellinie, solange man draufhält — tritt man zur Seite, sieht man
  wieder.
- **Gedämpft qualmt es mehr**, nicht weniger. Ein Dämpfer fängt die Gase ab und
  lässt sie langsam austreten, statt sie in einem Schlag auszublasen. Damit hat
  er zwei Seiten: Er nimmt Knall und Blendung und handelt sich eine Wolke vor
  dem eigenen Lauf ein.
- Einschusslöcher bleiben stehen, höchstens 96 gleichzeitig.

### Beim Mergen gefunden

Drei Fehler, die **keiner der beiden Branches allein hatte** — sie entstanden
erst durch die Kombination. Die Patrone im Lauf ging bei jedem Waffenwechsel
und bei jeder Extraction verloren, und die Laufgeschwindigkeit kannte je Seite
nur die eigenen Bremsen.

Der ganze Merge ist in `docs/merge-waffen-werkstatt.md` aufgeschrieben:
sieben Konflikte, jede Entscheidung mit Begründung, und was ein Mensch
trotzdem noch prüfen muss.

### Bewusst nicht dabei

- Innen-/Aussen- und Entfernungston. Drei Aufnahmen liegen ungenutzt unter
  `assets/audio/weapons/ar15/` — dafür braucht es ein System, das Räume kennt.
- Blender-Modelle für Glock, AKM und M870.
- Der Gehör-Nachteil **verpufft vorerst**: Die Waffe ist die einzige Tonquelle
  im Spiel, es gibt keine Schritte und keine Gegner, die man überhören könnte.
  Heute ist es Stimmung.

---

## 20.07.2026 — Extraction-Schleife, Inventar, Charakterfenster

Merge von `feature/extraction-schleife` (PR #4) nach `main`.
**37 Commits, 129 Dateien, +9.764 / −127 Zeilen.**

Damit ist die Kernschleife des Genres zum ersten Mal vollständig spielbar:
rein, durchsuchen, mitnehmen, raus — oder sterben und alles verlieren.

### Raid-Schleife

- **Loot-Container** mit eigener Durchsuchzeit pro Gegenstand. Durchsucht wird
  automatisch in Lesereihenfolge (links nach rechts, dann zeilenweise nach
  unten); ein Klick auf einen anderen Gegenstand zieht diesen vor.
- Unentdeckte Gegenstände sind **schwarz und schraffiert**, bis sie gefunden
  sind. Seltene leuchten beim Aufdecken kurz auf.
- **Extraction-Zonen** mit Timer, manche mit Bedingung (ein Ausgang verlangt
  Ausrüstung, die man erst finden muss).
- **Tod = alles Mitgeführte weg**, Extraction = alles ins Lager. Das gilt auch
  für die Ausrüstung am Körper und für die Patronen im Magazin.
- Man **startet unbewaffnet**. Eine Waffe muss man sich suchen.

### Inventar

- Rasterinventar im Tarkov-Stil: Ziehen mit der Maus, **R** dreht den
  Gegenstand am Zeiger, **Strg + Ziehen** teilt einen Stapel, Doppelklick
  schickt hinüber.
- Die nackten Taschen fassen **6x2 = 12 Felder**. Mehr gibt es nur über
  Ausrüstung — die Entscheidung, was man mitnimmt, soll wehtun.
- **Zwei Waffenplätze** auf den Tasten **1** und **2**. Waffen liegen am
  Körper statt im Raster, zählen aber zum Gewicht. Das Magazin bleibt beim
  Wechseln erhalten und überlebt auch den Weg in den Rucksack.
- Gegenstände zeigen ihre **Seltenheit über die ganze Fläche** (grau, grün,
  blau, gold, rot) und beim Überfahren eine Infoanzeige mit Schaden,
  Durchschlag und Munitionsart.

### Charakterfenster (Tab)

- Ein Fenster für **Ausrüstung, Gesundheit und Inventar**. Wer nachsieht, was
  er dabeihat, will meist auch wissen, wie es ihm geht.
- **Trefferpunkte pro Körperteil** (Kopf 35, Brust 85, Bauch 70, Arme 60,
  Beine 65). Kopf oder Brust leer bedeutet sofort tot; Arme, Beine und Bauch
  fallen aus, ohne zu töten — werden aber zur Last.
- Ein zerschossenes **Bein bremst**, ein **Arm** stört das Zielen, ein
  **Bauch** lässt Hunger und Durst schneller steigen.
- **Hunger, Durst und Körperwärme** laufen mit. Kälte hängt an der Kleidung,
  nicht an der Zeit.
- Ausrüstungsplätze für Helm, Brustpanzer, Oberteil, Gürtel, Hose, Schuhe,
  Rucksack und die beiden Waffen.

### Waffen und Ballistik

- Echte Projektile mit Flugzeit und Fallkurve.
- **Schaden und Durchschlag sind getrennt**: `damage` wirkt im Fleisch,
  `penetration_power` entscheidet, ob die Kugel durch die Platte kommt.
- 29 Munitionssorten, 12 Waffen — alles als `.tres`-Dateien, keine Werte im
  Code.
- Echte Waffenaufnahmen (CC0) statt synthetischer Klänge, zugeschnitten auf
  den ersten Schuss.

### Werkzeug

- `tools/run_tests.ps1` — 8 Testsuiten, **482 Prüfungen**. Meldet auch
  Skriptfehler als Fehlschlag, selbst wenn alle Prüfungen grün sind: Genau so
  blieb einmal ein Parserfehler unbemerkt.
- `tools/capture_ui.gd` — startet den Raid, öffnet die Fenster und legt
  Bildschirmfotos ab. Damit lässt sich prüfen, **ob** etwas zu sehen ist. Ob
  es **gut** aussieht, muss weiterhin ein Mensch beurteilen.
- Generatoren für Arsenal, Loot-Tabellen und Kleidung.

### Bewusst zurückgenommen

- **Verletzungen, Blut und Medizin** wurden gebaut und auf Wunsch wieder
  entfernt. Der Code liegt unter dem Tag `verletzungssystem` und lässt sich
  mit `git cherry-pick verletzungssystem` zurückholen.
- **Alle Gegenstände außer Waffen und Munition** sind gelöscht (Verpflegung,
  Medizin, Werkzeug, Kleidung, Schutzplatte, Rucksack). Die Generatoren unter
  `tools/` können sie jederzeit neu erzeugen. Solange sie fehlen, stehen die
  Ausrüstungsplätze leer und Wärme lässt sich nicht beeinflussen.
- **Fundgeräusche sind stumm geschaltet** (`LootWindow.FIND_SOUNDS_ENABLED`).
  Die Dateien liegen im Repo.

### Drei Fehler, die dabei gefunden wurden

Alle drei hätten stillen Ausrüstungsverlust bedeutet — die schlimmste Sorte
Fehler in einem Spiel, in dem Beute alles ist:

1. **Die Sekundärwaffe kam bei der Extraction nie im Lager an.** Gesichert
   wurde nur, was im Raster lag, plus die Waffe *in der Hand*.
2. **Nach dem Tod blieb alles am Körper erhalten.** Geleert wurden Raster und
   Hand, nicht die Ausrüstungsplätze — ausgerechnet Waffen und Rüstung
   überlebten den Tod.
3. **Die Pistole aus der Startausrüstung verschwand**, als die Taschen auf
   zwölf Felder schrumpften. Sie lief über das Raster, in dem das Gewehr schon
   zehn Felder belegte.

Für jeden gibt es jetzt eine eigene Prüfung.

### Was noch offen ist

- **Es gibt keine Gegner.** Ein Raid besteht aus Kisten durchsuchen und
  rausgehen; das Risiko fehlt.
- Die Fenster sind unten leer, seit die Taschen auf zwölf Felder geschrumpft
  sind — die Höhen stammen noch aus der Zeit davor.
- In `assets/audio/loot/QUELLEN.md` stehen bei acht Sounddateien noch
  Fragezeichen bei Quelle und Lizenz. Das muss vor einer Veröffentlichung
  geklärt sein.
- Balancing ist ungeprüft: Durst-Tempo, Fundchancen für die erste Waffe,
  Durchsuchzeiten.

### Für den Kollegen

Vor dem nächsten Arbeitsbeginn:

```
git checkout main
git pull
```

Ohne das baut ihr auf einem Stand auf, der die halbe Raid-Schleife nicht
kennt — und `.tscn`-Dateien lassen sich bei Konflikten praktisch nicht
zusammenführen.
