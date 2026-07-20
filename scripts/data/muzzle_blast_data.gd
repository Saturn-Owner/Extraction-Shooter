## Abstimmungswerte für die Mündungsknall-Belastung.
##
## Dauerfeuer ohne Schalldämpfer blendet, raucht, pfeift und rüttelt. Wie stark
## und wie lange, steht hier — damit es sich einstellen lässt, ohne Code
## anzufassen.
##
## WARUM DAS EINE RESSOURCE IST UND KEINE KONSTANTEN:
## Ob sich der Effekt gut anfühlt oder nur nervt, kann kein Test beantworten —
## das muss ein Mensch beim Spielen entscheiden. Dann muss dieser Mensch die
## Werte auch ändern können, ohne in GDScript zu greifen.
##
## Was NICHT hierher gehört, sondern Spielregel im Code bleibt:
##   - dass die Belastung pro Schuss steigt und mit der Zeit fällt
##   - dass die Lautstärke quadratisch eingeht (macht den Dämpfer wertvoll)
##   - dass unterhalb der Schwelle exakt null herauskommt
##
## HINWEIS: ItemRegistry liest jede .tres unter assets/data/ ein, übergeht aber
## alles, was keine ItemData ist. Diese Datei wird also mitgeladen und
## stillschweigend ignoriert — das ist kein Fehler in der Registry.
class_name MuzzleBlastData
extends Resource

@export_group("Aufbau und Erholung")

## Wieviel Belastung ein Schuss bei voller Lautstärke hinzufügt.
##
## Bei der AR-15 ohne Dämpfer sind das rund 0,13 je Schuss — die Schwelle fällt
## damit etwa auf den dritten Schuss einer Salve.
@export_range(0.01, 1.0) var rise_per_shot: float = 0.28

## Darunter passiert GAR NICHTS. Kein bisschen Rauch, kein leichtes Wackeln.
##
## Der Wert ist der Kern des Versprechens "Einzelschüsse bleiben folgenlos".
@export_range(0.0, 0.9) var threshold: float = 0.35

## Von voller Belastung auf null, in Sekunden.
##
## Zusammen mit `hold_seconds` entscheidet dieser Wert, ab welcher Feuerrate
## sich Schüsse überhaupt aufsummieren. Bei 2,5 s liegt die Grenze bei rund
## zwei Schuss pro Sekunde: Gezieltes Einzelfeuer bleibt folgenlos, hektisches
## Klicken und Dauerfeuer nicht.
@export_range(0.5, 30.0) var recovery_seconds: float = 2.5

## So lange nach dem letzten Schuss klingt noch gar nichts ab.
##
## Muss über dem Schussabstand liegen (bei 750 Schuss/min sind das 80 ms),
## sonst erholt sich die Waffe mitten in der eigenen Salve.
@export_range(0.0, 1.0) var hold_seconds: float = 0.15

@export_group("Abklingzeiten je Effekt")

## Die vier Effekte teilen sich EINE Quelle, haben aber verschiedenes Gedächtnis.
##
## Ohne das erholen sie sich im Gleichschritt, und das liest sich, als hätte
## jemand einen Regler zurückgedreht — nicht wie vier körperliche Vorgänge.
## Blendung vergeht schnell, ein Pfeifen im Ohr bleibt.
@export_range(0.1, 10.0) var flash_fall: float = 1.2
@export_range(0.1, 15.0) var smoke_fall: float = 2.5
@export_range(0.1, 5.0) var shake_fall: float = 0.5
@export_range(0.1, 60.0) var tinnitus_fall: float = 12.0

@export_group("Stärke bei voller Belastung")

## Deckkraft des hellen Schleiers.
@export_range(0.0, 1.0) var flash_alpha: float = 0.55

## Wackeln um die Blickachse. DARF GROSS SEIN: Rollen dreht das Bild, aber
## nicht die Blickrichtung — es kostet keine Präzision.
@export_range(0.0, 6.0) var shake_roll_deg: float = 1.2

## Wackeln nach oben/unten und zur Seite.
##
## BEWUSST KLEIN UND GEDECKELT. Die Kamera ist die Zielquelle der Waffe
## (player_controller.gd: weapon.set_aim_source), diese beiden Achsen
## verschieben also wirklich den Treffpunkt. 0,35 Grad sind rund 60 cm auf
## 100 m — spürbar, aber nicht zufällig. Wer hier 5 Grad einträgt, macht
## Dauerfeuer unbrauchbar, ohne dass jemand den Zusammenhang sieht.
@export_range(0.0, 1.0) var shake_pitch_deg: float = 0.18
@export_range(0.0, 1.0) var shake_yaw_deg: float = 0.18

## Seitliches Versetzen der Kamera in Metern. Verschiebt nur den Ursprung des
## Zielstrahls, nicht seine Richtung — praktisch kostenlos.
@export_range(0.0, 0.1) var shake_offset_m: float = 0.008

## Wie schnell gezittert wird.
@export_range(1.0, 40.0) var shake_speed: float = 14.0

@export_group("Gehör")

## Grenzfrequenz des Tiefpasses bei voller Belastung. Tiefer = dumpfer.
@export_range(200.0, 20000.0) var muffle_cutoff_hz: float = 600.0

## Wieviel leiser die Welt bei voller Belastung wird.
@export_range(-40.0, 0.0) var muffle_volume_db: float = -9.0

## Die beiden Tinnitus-Frequenzen.
##
## ZWEI, NICHT EINE: Ein reiner Sinus klingt nach Messgerät. Zwei dicht
## beieinanderliegende Töne ergeben eine langsame Schwebung — hier 8 Hz — und
## das klingt organisch statt technisch.
@export_range(500.0, 12000.0) var tinnitus_hz: float = 4500.0
@export_range(500.0, 12000.0) var tinnitus_beat_hz: float = 4508.0

@export_range(-60.0, 0.0) var tinnitus_volume_db: float = -14.0


## Prüft die Werte auf Widersprüche. Gibt leere Liste zurück, wenn alles passt.
func validate() -> Array[String]:
	var problems: Array[String] = []

	if threshold >= 1.0:
		problems.append("threshold von %.2f wird nie erreicht" % threshold)
	if rise_per_shot <= 0.0:
		problems.append("rise_per_shot ist null — es passiert nie etwas")
	if recovery_seconds <= 0.0:
		problems.append("recovery_seconds muss über null liegen")

	# Ein Schuss allein darf die Schwelle nicht reissen, sonst ist die Zusage
	# "Einzelschüsse bleiben folgenlos" gebrochen.
	if rise_per_shot > threshold:
		problems.append("rise_per_shot (%.2f) über threshold (%.2f): schon ein einzelner Schuss löst aus"
			% [rise_per_shot, threshold])

	if tinnitus_hz >= tinnitus_beat_hz:
		problems.append("tinnitus_beat_hz muss über tinnitus_hz liegen, sonst gibt es keine Schwebung")

	return problems
