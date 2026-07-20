# Änderungen

Was auf `main` gelandet ist, und warum. Neueste Einträge oben.

Diese Datei ist für den Menschen gedacht, der nach zwei Wochen Pause wissen
will, was sich geändert hat, ohne 37 Commit-Nachrichten zu lesen. Die
Begründungen im Einzelnen stehen weiterhin in den Commits.

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

### Zweites Raster im Inventar

- Sowohl das **Charakterfenster** als auch das **Loot-Fenster** zeigen unter
  den Taschen das Innenraster des angelegten Rucksacks. Ziehen funktioniert
  zwischen allen Rastern, mit Strg auch geteilt.
- Ohne angelegten Rucksack ist beides **ausgeblendet** — ein leeres Feld mit
  der Aufschrift "Rucksack" sähe aus wie ein Fehler.
- Das linke Raster heisst jetzt **"Taschen"** statt "Ausruestung". Es zeigte
  noch nie die Ausrüstung, und mit dem Rucksack daneben wäre der Name endgültig
  irreführend.

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

Neue Suite `tests/verify_backpack.gd`, **25 Prüfungen**. Alle 14 Suiten grün,
zusammen 1.099 Prüfungen.

**Von einem Menschen zu prüfen:** ob das zweite Raster im Fenster gut
aussieht, ob 24 Felder die richtige Grösse sind und ob die Kiste an der
richtigen Stelle steht.

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
