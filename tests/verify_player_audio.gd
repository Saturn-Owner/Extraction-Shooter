## Prüft Schrittgeräusche und das Ausser-Atem-Geräusch.
##
##   godot --headless --path . --script res://tests/verify_player_audio.gd
##
## Was hier NICHT geprüft werden kann: ob die Trittfrequenz sich richtig
## anfühlt und ob acht Varianten nach genug klingen. Das muss ein Mensch
## laufen hören.
##
## Was geprüft werden KANN: dass die Dateien da sind, sofort anfangen, einen
## brauchbaren Pegel haben, sich nicht wiederholen — und dass die Rechnung
## hinter Trittfrequenz und Atem stimmt.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	print("=== Schritte und Atem pruefen ===\n")
	_run_all()


## Getrennt von _initialize(), weil _test_wiring() auf einen Frame wartet.
## Ohne dieses await stuende die Zusammenfassung vor dem letzten Test — und
## ein Fehlschlag dort waere im Ergebnis gar nicht mitgezaehlt.
func _run_all() -> void:
	_test_files()
	_test_no_lead_in()
	_test_levels()
	_test_no_repeats()
	_test_stride()
	_test_breathing_rule()
	await _test_wiring()

	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


# ---------------------------------------------------------------------------

func _test_files() -> void:
	_section("Dateien")

	var count := PlayerAudio.get_footstep_count()
	_check(count >= 8, "mindestens acht Schrittvarianten (%d)" % count)
	_check(PlayerAudio.get_breathing() != null, "Atemgeraeusch vorhanden")

	# Ein Schritt darf nicht laenger sein als ein Schritt. Wer hier eine
	# Sekunde findet, hat zwei verschmolzene Tritte erwischt — dann laeuft die
	# Figur haerter, als sie klingt.
	for path in _footstep_paths():
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		var seconds := stream.get_length()
		_check(seconds > 0.15 and seconds < 1.5,
			"%s dauert %.2f s" % [path.get_file(), seconds])


## Ein Schritt muss SOFORT anfangen.
##
## Liegt Stille am Anfang der Datei, kommt das Geraeusch spaeter als der Fuss.
## Bei 60 ms merkt man das noch nicht, bei 200 ms laeuft die Figur gefuehlt
## neben sich her.
func _test_no_lead_in() -> void:
	_section("Kein Vorlauf")

	for path in _footstep_paths():
		var samples := _samples_of(path)
		if samples.is_empty():
			_check(false, "%s lesbar" % path.get_file())
			continue
		var start := _first_loud_second(samples, _rate_of(path))
		_check(start < 0.06, "%s faengt sofort an (%.3f s)" % [path.get_file(), start])


func _test_levels() -> void:
	_section("Pegel")

	for path in _footstep_paths():
		var samples := _samples_of(path)
		if samples.is_empty():
			continue
		var peak := WavTools.peak_of(samples)
		# Nicht uebersteuert und nicht unhoerbar. Alle wurden beim Zuschneiden
		# auf 0.90 normalisiert — weicht einer ab, ist beim Kopieren etwas
		# schiefgegangen.
		_check(peak > 0.5 and peak < 1.0, "%s Pegel %.2f" % [path.get_file(), peak])


## Zweimal derselbe Schritt hintereinander faellt sofort als Wiederholung auf.
func _test_no_repeats() -> void:
	_section("Keine Wiederholung")

	# Ohne Dateien wuerde dieser Test bestehen, ohne etwas zu pruefen —
	# genau die Sorte gruener Test, die nichts wert ist.
	if PlayerAudio.get_footstep_count() < 2:
		_check(false, "mindestens zwei Varianten noetig, um das zu pruefen")
		return

	var last: AudioStream = null
	var repeats := 0
	for i in range(50):
		var stream := PlayerAudio.get_footstep()
		if stream != null and stream == last:
			repeats += 1
		last = stream

	_check(repeats == 0, "in 50 Ziehungen nie zweimal dieselbe (%d)" % repeats)


func _test_stride() -> void:
	_section("Trittfrequenz")

	var walk := PlayerSounds.steps_for_distance(10.0, PlayerSounds.STRIDE_WALK)
	var sprint := PlayerSounds.steps_for_distance(10.0, PlayerSounds.STRIDE_SPRINT)
	var crouch := PlayerSounds.steps_for_distance(10.0, PlayerSounds.STRIDE_CROUCH)

	_check(walk == 11, "10 m gehen ergibt %d Schritte" % walk)
	_check(sprint == 8, "10 m sprinten ergibt %d Schritte" % sprint)
	_check(crouch == 13, "10 m geduckt ergibt %d Schritte" % crouch)

	# Sprinten macht LAENGERE Schritte, also weniger auf gleicher Strecke —
	# aber in der Zeit trotzdem mehr, weil man schneller ist. Wer die Werte
	# verdreht, bekommt trippelnde Sprinter.
	_check(sprint < walk and walk < crouch,
		"geduckt am dichtesten, sprintend am weitesten auseinander")

	_check(PlayerSounds.steps_for_distance(0.0, PlayerSounds.STRIDE_WALK) == 0,
		"wer steht, macht keine Schritte")

	# Schleichen muss leiser sein als Gehen, Sprinten lauter. Sonst lohnt
	# sich Ducken nicht, sobald es Gegner gibt.
	_check(PlayerSounds.VOLUME_CROUCH_DB < PlayerSounds.VOLUME_WALK_DB,
		"geduckt ist leiser als gehen")
	_check(PlayerSounds.VOLUME_WALK_DB < PlayerSounds.VOLUME_SPRINT_DB,
		"sprinten ist lauter als gehen")


## Lucas' Bedingung: erst ab 5 Sekunden Sprint UND Ausdauer unter 15.
func _test_breathing_rule() -> void:
	_section("Atem-Bedingung")

	_check(not PlayerSounds.should_start_breathing(0.0, 100.0),
		"bei voller Ausdauer kein Keuchen")
	_check(not PlayerSounds.should_start_breathing(3.0, 10.0),
		"nach 3 Sekunden Sprint noch nicht, auch bei wenig Ausdauer")
	_check(not PlayerSounds.should_start_breathing(20.0, 40.0),
		"langes Sprinten allein reicht nicht, solange Ausdauer da ist")
	_check(PlayerSounds.should_start_breathing(5.0, 14.0),
		"ab 5 Sekunden mit Ausdauer 14 setzt es ein")
	_check(PlayerSounds.should_start_breathing(9.0, 2.0),
		"und bleibt, solange beides gilt")

	# Zwei verschiedene Schwellen, sonst flackert es an der Grenze.
	_check(PlayerSounds.BREATHING_STOPS_ABOVE > PlayerSounds.BREATHING_BELOW_STAMINA,
		"Ausschaltschwelle liegt ueber der Einschaltschwelle (%.0f > %.0f)" % [
			PlayerSounds.BREATHING_STOPS_ABOVE, PlayerSounds.BREATHING_BELOW_STAMINA])


## Die Tonquellen muessen am Bus "Welt" haengen.
##
## Am Master vorbei hoert man sie auch nach einem Muendungsknall unveraendert
## laut — als kaeme das Geraeusch nicht aus der Welt, sondern aus dem Kopf.
func _test_wiring() -> void:
	_section("Verkabelung")

	GameAudio.ensure_buses()

	var sounds := PlayerSounds.new()
	root.add_child(sounds)
	await process_frame

	var steps := sounds.get_node_or_null("Schritte") as AudioStreamPlayer3D
	var breath := sounds.get_node_or_null("Atem") as AudioStreamPlayer3D

	_check(steps != null, "Schritt-Tonquelle angelegt")
	_check(breath != null, "Atem-Tonquelle angelegt")
	if steps != null:
		_check(steps.bus == GameAudio.WORLD_BUS, "Schritte haengen am Bus 'Welt'")
	if breath != null:
		_check(breath.bus == GameAudio.WORLD_BUS, "Atem haengt am Bus 'Welt'")

	# Ohne Spieler darf gar nichts passieren, statt mit einem Nullzugriff
	# abzustuerzen.
	sounds._physics_process(0.016)
	_check(true, "ohne Spieler laeuft es ins Leere statt abzustuerzen")

	sounds.free()


# ---------------------------------------------------------------------------
# Messhelfer
#
# Gemessen wird die DATEI auf der Platte, nicht der geladene Stream.
#
# Godot importiert Tondateien komprimiert (QOA). In `AudioStreamWAV.data`
# stehen danach keine Samples mehr, sondern QOA-Blöcke — wer die als 16-Bit-
# Werte liest, misst Rauschen und bekommt Zahlen wie "0.08 s" für einen
# 0,4-Sekunden-Schritt. Genau das ist hier zuerst passiert.
#
# WavTools liest das Original. Das geht nur im Projektordner, nicht in einem
# fertigen Export — für einen Testlauf ist das genau richtig.
# ---------------------------------------------------------------------------

func _footstep_paths() -> Array[String]:
	var paths: Array[String] = []
	for i in range(1, PlayerAudio.MAX_FOOTSTEPS + 1):
		var path := "%s/schritt_schnee_%02d.wav" % [PlayerAudio.AUDIO_DIR, i]
		if not FileAccess.file_exists(path):
			break
		paths.append(path)
	return paths


func _samples_of(path: String) -> PackedFloat32Array:
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		return PackedFloat32Array()
	var info := WavTools.parse(raw)
	if info.is_empty():
		return PackedFloat32Array()
	return WavTools.to_mono(raw, info)


func _rate_of(path: String) -> int:
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		return 44100
	var info := WavTools.parse(raw)
	return int(info.get("rate", 44100))


## Wann das erste hoerbare Sample kommt, in Sekunden.
func _first_loud_second(samples: PackedFloat32Array, rate: int) -> float:
	if samples.is_empty() or rate <= 0:
		return 0.0
	for i in range(samples.size()):
		if absf(samples[i]) >= 0.05:
			return float(i) / float(rate)
	return float(samples.size()) / float(rate)
