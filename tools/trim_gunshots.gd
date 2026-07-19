## Schneidet aus einer Aufnahme mit mehreren Schüssen den ersten heraus.
##
##   godot --headless --path . --script res://tools/trim_gunshots.gd -- <ordner>
##
## Warum das nötig ist: Frei verfügbare Waffenaufnahmen sind meist ganze
## Schießstand-Sessions — 15 Sekunden, mehrere Schüsse, Stereo, mit Pausen
## dazwischen. Im Spiel brauchen wir das Gegenteil: einen Schuss, Mono,
## unter einer Sekunde, ohne Vorlauf.
##
## Mono ist keine Sparmaßnahme: Ein Schuss soll aus der Richtung kommen, in
## die der Spieler zielt. Eine Stereodatei bringt ihre eigene Richtung mit
## und lässt sich im 3D-Raum nicht mehr sauber platzieren.
##
## Die Datei wird ÜBERSCHRIEBEN. Das Original liegt im Download-Ordner.
extends SceneTree

## Ab welchem Anteil des lautesten Werts der Schuss als begonnen gilt.
const ONSET_THRESHOLD := 0.30

## Etwas Vorlauf, damit der Anschlag nicht abgeschnitten wirkt.
const PRE_ROLL := 0.006

## Wenn es so lange so leise ist, ist der Schuss vorbei.
const SILENCE_LEVEL := 0.02
const SILENCE_DURATION := 0.12

## Bewusst kurz: Bei schnellen Schussfolgen (SKS, Maschinenpistole) liegt
## der nächste Schuss schon nach 0,4 s. Ein höherer Mindestwert würde
## genau darüber hinwegsehen und ihn mit in die Datei nehmen.
const MIN_LENGTH := 0.28
const MAX_LENGTH := 1.60

## Auf diesen Spitzenwert normalisieren — alle Schüsse gleich laut,
## damit das Balancing der Lautstärke im Spiel passiert, nicht in den Dateien.
const TARGET_PEAK := 0.92


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Ordner angeben: --script ... -- <ordner>")
		quit(1)
		return

	var dir_path := args[0].strip_edges()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("Ordner nicht lesbar: ", dir_path)
		quit(1)
		return

	print("=== Schüsse zuschneiden ===\n")
	var count := 0
	for file_name in dir.get_files():
		if not file_name.to_lower().ends_with(".wav"):
			continue
		if _process_file(dir_path.path_join(file_name)):
			count += 1

	print("\n%d Dateien zugeschnitten." % count)
	quit(0)


func _process_file(path: String) -> bool:
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() < 44:
		printerr("  zu klein: ", path)
		return false

	var info := WavTools.parse(raw)
	if info.is_empty():
		printerr("  kein lesbares WAV: ", path)
		return false

	# Schon fertig? Mono und kurz heisst: lief hier bereits durch. Ein
	# zweiter Durchlauf wuerde erneut kuerzen und den Anschlag abschneiden.
	if info.channels == 1 and WavTools.duration_of(info) <= MAX_LENGTH + 0.05:
		print("  %-16s bereits zugeschnitten, uebersprungen" % path.get_file())
		return false

	var samples := WavTools.to_mono(raw, info)
	if samples.is_empty():
		printerr("  keine Daten: ", path)
		return false

	var rate: int = info.rate
	var peak := WavTools.peak_of(samples)
	if peak <= 0.0:
		printerr("  nur Stille: ", path)
		return false

	var start := _find_onset(samples, peak, rate)
	var length := _find_length(samples, start, peak, rate)

	var cut := PackedFloat32Array()
	cut.resize(length)
	var gain := TARGET_PEAK / peak
	for i in range(length):
		cut[i] = samples[start + i] * gain

	WavTools.fade_out(cut, rate)
	WavTools.write(path, cut, rate)

	print("  %-16s %5.2f s -> %.2f s Mono" % [
		path.get_file(),
		float(samples.size()) / float(rate),
		float(length) / float(rate),
	])
	return true


## Wo der Schuss anfängt.
##
## NICHT der erste laute Ausschlag: Vor dem Knall liegen oft leisere
## Geräusche (Abzug, Wind, ein entfernter Schuss). Wer darauf triggert,
## schneidet zu früh und der Schuss kommt im Spiel verzögert.
##
## Stattdessen vom lautesten Punkt RÜCKWÄRTS suchen, bis es wirklich still
## ist. Das ist der tatsächliche Anschlag.
func _find_onset(samples: PackedFloat32Array, peak: float, rate: int) -> int:
	var loudest := 0
	for i in range(samples.size()):
		if absf(samples[i]) >= peak:
			loudest = i
			break

	var quiet := peak * 0.02
	var quiet_needed := int(0.003 * rate)
	var limit := maxi(0, loudest - int(0.15 * rate))

	var quiet_run := 0
	var onset := limit
	var i := loudest
	while i > limit:
		if absf(samples[i]) < quiet:
			quiet_run += 1
			if quiet_run >= quiet_needed:
				onset = i + quiet_run
				break
		else:
			quiet_run = 0
		i -= 1

	return maxi(0, onset - int(PRE_ROLL * rate))


## Wie lang der Schuss ist.
##
## Zwei Abbruchgründe, und der zweite ist der wichtige:
##   1. es bleibt lange genug leise  -> der Schuss ist ausgeklungen
##   2. der Pegel STEIGT wieder an   -> der nächste Schuss beginnt
##
## Ohne (2) landet bei einer Schießstand-Aufnahme der zweite Schuss mit in
## der Datei, und im Spiel feuert jeder Schuss doppelt.
func _find_length(samples: PackedFloat32Array, start: int, peak: float, rate: int) -> int:
	var quiet := peak * SILENCE_LEVEL
	var needed := int(SILENCE_DURATION * rate)
	var min_len := int(MIN_LENGTH * rate)
	var max_len := mini(int(MAX_LENGTH * rate), samples.size() - start)

	# Blockweise Hüllkurve: einzelne Ausschläge sollen nicht als neuer
	# Schuss gelten, ein ganzer lauter Block schon.
	var block := maxi(1, int(0.025 * rate))
	var decayed := false
	var quiet_run := 0
	var previous := peak

	var pos := min_len
	while pos < max_len:
		var block_end := mini(pos + block, max_len)
		var block_peak := 0.0
		for i in range(pos, block_end):
			block_peak = maxf(block_peak, absf(samples[start + i]))

		# Ein Nachhall wird immer nur leiser. Springt der Pegel deutlich
		# nach oben, ist das ein NEUER Anschlag — auch wenn der vorige noch
		# nachklingt und nie richtig leise wurde. Genau so klingt eine
		# schnelle Schussfolge, und ohne diese Prüfung landet der zweite
		# Schuss mit in der Datei.
		if block_peak > previous * 1.6 and block_peak > peak * 0.35:
			return maxi(min_len, pos - block)

		if block_peak < peak * 0.25:
			decayed = true
		elif decayed and block_peak > peak * 0.30:
			return maxi(min_len, pos - block)

		previous = maxf(block_peak, previous * 0.75)

		if block_peak < quiet:
			quiet_run += block_end - pos
			if quiet_run >= needed:
				return maxi(min_len, pos - needed)
		else:
			quiet_run = 0

		pos = block_end

	return max_len
