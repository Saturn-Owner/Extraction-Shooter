# Änderungen

Was auf `main` gelandet ist, und warum. Neueste Einträge oben.

Diese Datei ist für den Menschen gedacht, der nach zwei Wochen Pause wissen
will, was sich geändert hat, ohne 37 Commit-Nachrichten zu lesen. Die
Begründungen im Einzelnen stehen weiterhin in den Commits.

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
