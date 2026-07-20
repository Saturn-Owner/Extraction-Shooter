# Merge: Waffenwerkstatt nach `main`

Wie `feature/waffen-werkstatt` mit `main` zusammengeführt wurde, und warum an
jeder Konfliktstelle so entschieden wurde.

Diese Datei ist für den Fall gedacht, dass später jemand fragt „warum steht das
so da?" — bei einem Merge ist die Antwort in der Versionsgeschichte besonders
schwer zu finden, weil ein Merge-Commit keinen eigenen Diff hat.

---

## Ausgangslage

Zwei Branches, zwölf Tage parallel, **kein einziges Gespräch dazwischen**:

| | Waffenwerkstatt (Tim) | main (Kollege, PR #4) |
| --- | --- | --- |
| Thema | Waffenmodelle, Anbauteile, Werkbank, Ton, Mündungsknall | Raid-Schleife, Inventar, Charakterfenster, Gesundheit |
| Umfang | 32 Commits | 37 Commits |

**12 Dateien wurden von beiden angefasst, 7 davon mit echtem Konflikt.**

Das ist genau der Fall, vor dem `CLAUDE.md` warnt: Wer gleichzeitig an
denselben Dateien arbeitet, zahlt später dafür. Die Rechnung war noch bezahlbar,
weil sich die Themen kaum überschnitten — bei zwei Leuten am selben System wäre
es anders ausgegangen.

**Richtung: `main` in den Feature-Branch**, nicht umgekehrt. Wenn beim
Zusammenführen etwas kaputtgeht, geht es im Branch kaputt und nicht im
spielbaren Stand.

---

## Die sieben Konflikte

### 1. `scenes/player/player.tscn` — der gefürchtete

Der Grund, warum in `CLAUDE.md` steht, dass man Szenen nicht gleichzeitig
anfassen soll. Hier ging es gut aus: Beide hatten nur **oben** Ressourcen
eingetragen, die Knoten selbst hat Git sauber zusammengeführt.

Kollidiert sind nur die IDs — bei ihm `4_interaction`, bei mir `4_weaponview`.
Meine ist auf `8_weaponview` gewandert, `load_steps` auf 10 (8 Ressourcen +
1 Unterressource + 1).

Dass das gutging, war **Glück und kein Verdienst.** Hätte einer von uns einen
Knoten verschoben, wäre die Datei von Hand nachzubauen gewesen.

### 2. `player_controller.gd` — die eigentliche Arbeit

Sechs Konfliktbereiche. Er hat `equip_from_inventory` durch eine ganze Kette
ersetzt: zwei Waffenplätze, Verdrängung ins Raster, Magazingedächtnis.

Meine Bestückung und der Verschleiss mussten da hinein — und zwar in
**`_put_in_hand()`**, nicht in `assign_weapon()`. Der Unterschied ist wichtig:
`_put_in_hand()` läuft auch beim Wechsel über Taste 1/2. Hätte ich es in
`assign_weapon()` gelassen, trüge die zweite Waffe beim Zurückwechseln die
Anbauteile der ersten.

Sein Zweig für „Waffe ohne passende Munition" setzte `weapon.data` von Hand.
Ersetzt durch `weapon.equip_without_ammo()`: Die Funktion baut auch das Modell
auf und lädt den Schussklang. Direkt zuzuweisen liesse die Waffe unsichtbar und
stumm in der Hand — was auf seinem Branch nicht auffiel, weil es dort noch
keine sichtbaren Waffenmodelle gab.

### 3. `get_current_max_speed()` — beide Seiten bremsten

Er hatte `get_condition_factor()` (zerschossenes Bein), ich das Bremsen beim
Zielen. Beide Fassungen kannten nur ihre eigene Bremse.

Jetzt wirken sie **multiplikativ**: Wer schwer beladen mit kaputtem Bein im
Anschlag geht, spürt alle drei. Hätte man eine Seite genommen, wäre die andere
Mechanik still verschwunden — und niemand hätte es gemerkt, weil beide für sich
weiter funktionieren.

### 4. `weapon_audio.gd` — beides nötig

Er hat Kaliber mit Schrägstrich behandelt (`12/70` wurde sonst zu einem Ordner
`12/` mit der Datei `70.wav`), ich die gedämpften Aufnahmen. Beide Teile stehen
jetzt hintereinander in derselben Funktion.

### 5. `weapon_data.gd`, `verify_loadout.gd` — nur Nachbarschaft

Beide hatten an derselben Stelle verschiedene Funktionen angehängt. Beides
behalten, nichts zu entscheiden.

### 6. `tools/run_tests.ps1` — Suiten zusammengelegt

Seine `verify_raid` und `verify_health`, meine vier. Zusammen 12.

### 7. `backpack_small.tres` — gelöscht, und das bleibt so

Der einzige Konflikt, bei dem eine Seite ganz weichen musste. Er hat auf
ausdrücklichen Wunsch **alle 28 Nicht-Waffen-Gegenstände gelöscht** (Commit
`6cb7a61`) — Verpflegung, Medizin, Kleidung, Platten, Rucksack. Die Generatoren
unter `tools/` können sie jederzeit neu erzeugen.

Ich hatte an genau dieser Datei kurz vorher `category` von 7 (MEDICAL) auf 6
(BACKPACK) korrigiert. Der Fix ist damit gegenstandslos: **Eine bewusste
menschliche Entscheidung schlägt einen technisch richtigen Fix an einer Datei,
die es nicht mehr geben soll.** Die Datei ist weg, mein Commit `1465c53` liegt
wirkungslos in der Geschichte.

Sollten die Gegenstände zurückkommen, muss `category = 6` mit zurück.

---

## Was kein Konfliktmarker angezeigt hat

Hier lag die eigentliche Gefahr. Git meldet nur Stellen, an denen **dieselben
Zeilen** geändert wurden. Es meldet nicht, wenn zwei für sich richtige
Änderungen zusammen etwas kaputt machen.

Nach dem Auflösen aller sieben Konflikte waren **drei Suiten rot** — an Stellen,
die kein Marker berührt hatte.

### Die Patrone im Lauf ging bei jedem Waffenwechsel verloren

Mein Branch hat `round_chambered`: die Patrone im Lauf, getrennt vom Magazin.
Das ist der Unterschied zwischen 30+1 und 30.

Sein Magazingedächtnis speichert beim Wechsel `rounds_in_magazine` — und nur
das. Beim Zurückwechseln lief `load_rounds()`, das **nachkammert**: Es nimmt
eine Patrone aus dem Magazin und legt sie in den Lauf. Ergebnis: nach jedem
Wechsel eine Patrone weniger im Magazin. Nach zehn Wechseln fehlen zehn Schuss,
ohne dass jemand geschossen hätte.

Beide Seiten waren für sich völlig richtig. Erst zusammen entstand der Fehler.

Behoben mit `Weapon.restore_magazine(rounds, chambered)`. Bewusst eine eigene
Funktion, statt `load_rounds()` anzupassen: Letzteres ist zum **Nachladen** da
und tut deshalb zweierlei zuviel — es kammert nach und spielt das
Nachladegeräusch. Beim Griff an die Schulter ist beides falsch.

### Und bei jeder Extraction blieb sie liegen

Derselbe Fehler eine Ebene tiefer: `unload_weapon()` zählte nur
`rounds_in_magazine`. Die Patrone im Lauf fiel bei jeder Extraction unter den
Tisch — genau der stille Verlust, vor dem sein eigener Kommentar an dieser
Funktion warnt („bei M995 wären das über 20.000 Spielwährung pro Raid"). Jetzt
über `get_total_rounds()`.

---

## Ergebnis

**Alle 12 Suiten grün, 969 Prüfungen.**

| Suite | | Suite | |
| --- | --- | --- | --- |
| `verify_attachments` | 155 | `verify_health` | 105 |
| `verify_weapon_handling` | 147 | `verify_raid` | 97 |
| `verify_blast` | 106 | `verify_inventory` | 91 |
| `verify_loadout` | 76 | `verify_feedback` | 67 |
| `verify_player` | 55 | `verify_ballistics` | 36 |
| `verify_workbench` | 34 | `verify_item_data` | alle `.tres` |

Zusätzlich starten `raid_eisstadt` und `testgelaende` headless ohne
Skriptfehler. Die einzige Meldung ist eine `push_warning` der Zielscheiben, dass
es die Panzerplatte nicht mehr gibt — von ihm so vorgesehen und im Code als
Normalfall kommentiert.

---

## Was ein Mensch trotzdem prüfen muss

Tests sagen nichts darüber, ob die beiden Systeme sich **gemeinsam** richtig
anfühlen. Das hier hat noch nie jemand zusammen gespielt:

- **Waffenwechsel mit Taste 1/2** — behält die zweite Waffe ihre eigenen
  Anbauteile, ihren eigenen Zustand und ihr eigenes Magazin?
- **Waffe in den Rucksack und zurück** — bleibt alles erhalten?
- **Werkbank im Testgelände** — er hat `PlayerInteraction` gebaut, meine
  Werkbank hat ihren eigenen Auslösebereich. **Beide hören auf dieselbe Taste.**
  Das ist die wahrscheinlichste offene Baustelle: Steht man vor Werkbank und
  Loot-Kiste zugleich, ist unklar, wer gewinnt.
- **Laufgeschwindigkeit** — drei Bremsen multiplikativ. Ist man mit kaputtem
  Bein, vollem Rucksack und im Anschlag noch spielbar schnell?
- **Mündungsknall im Raid** statt im Testgelände: Die Blendung ist auf Schnee
  abgestimmt und wird in einem dunklen Innenraum stärker wirken.

---

## Was daraus zu lernen ist

**Zwölf Tage ohne Absprache waren zu lang.** Sieben Konflikte liessen sich
auflösen, weil die Themen weit auseinanderlagen. Bei zwei Leuten am
Inventarsystem wäre das anders gelaufen.

**Ein grüner Testlauf nach dem Auflösen der Konfliktmarker ist kein Beweis.**
Die drei Regressionen standen an Stellen, die Git nie als Konflikt gemeldet
hat. Ohne die Suiten des jeweils anderen wären sie durchgerutscht — und die
verlorene Patrone hätte man im Spiel für Zufall gehalten.

**Häufiger mergen kostet weniger.** Die Empfehlung für das nächste Mal:
`main` einmal pro Woche in den laufenden Branch holen, nicht am Ende.
