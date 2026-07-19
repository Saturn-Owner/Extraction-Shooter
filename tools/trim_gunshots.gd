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

	var info := _parse_wav(raw)
	if info.is_empty():
		printerr("  kein lesbares WAV: ", path)
		return false

	var samples := _to_mono(raw, info)
	if samples.is_empty():
		printerr("  keine Daten: ", path)
		return false

	var rate: int = info.rate
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
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

	_fade_out(cut, rate)
	_write_wav(path, cut, rate)

	print("  %-16s %5.2f s -> %.2f s Mono" % [
		path.get_file(),
		float(samples.size()) / float(rate),
		float(length) / float(rate),
	])
	return true


## Liest die WAV-Kopfdaten. Chunks stehen NICHT immer an festen Positionen —
## viele Aufnahmen haben Zusatzchunks (LIST, INFO) vor den Audiodaten.
func _parse_wav(raw: PackedByteArray) -> Dictionary:
	if raw.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	if raw.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}

	var info := {}
	var pos := 12

	while pos + 8 <= raw.size():
		var chunk_id := raw.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := raw.decode_u32(pos + 4)
		var body := pos + 8

		if chunk_id == "fmt ":
			info["channels"] = raw.decode_u16(body + 2)
			info["rate"] = int(raw.decode_u32(body + 4))
			info["bits"] = raw.decode_u16(body + 14)
		elif chunk_id == "data":
			info["data_start"] = body
			info["data_size"] = mini(int(chunk_size), raw.size() - body)

		# Chunks sind auf gerade Byte-Grenzen ausgerichtet.
		pos = body + int(chunk_size) + (int(chunk_size) & 1)

	if not (info.has("channels") and info.has("data_start")):
		return {}
	if info.get("bits", 0) != 16:
		printerr("  nur 16 bit unterstuetzt, ist aber ", info.get("bits", 0))
		return {}
	return info


## Kanäle zusammenmischen und auf -1..1 bringen.
func _to_mono(raw: PackedByteArray, info: Dictionary) -> PackedFloat32Array:
	var channels: int = info.channels
	var start: int = info.data_start
	var size: int = info.data_size
	var frames := size / (2 * channels)

	var out := PackedFloat32Array()
	out.resize(frames)

	for f in range(frames):
		var sum := 0.0
		for c in range(channels):
			var offset := start + (f * channels + c) * 2
			var value := raw.decode_s16(offset)
			sum += float(value) / 32768.0
		out[f] = sum / float(channels)

	return out


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


## Die letzten 25 ms ausblenden, sonst knackt der harte Schnitt.
func _fade_out(samples: PackedFloat32Array, rate: int) -> void:
	var fade := mini(int(0.025 * rate), samples.size())
	var first := samples.size() - fade
	for i in range(fade):
		samples[first + i] *= 1.0 - (float(i) / float(fade))


func _write_wav(path: String, samples: PackedFloat32Array, rate: int) -> void:
	var data_size := samples.size() * 2

	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_u32(36 + data_size))
	out.append_array("WAVE".to_ascii_buffer())

	out.append_array("fmt ".to_ascii_buffer())
	out.append_array(_u32(16))
	out.append_array(_u16(1))           # PCM
	out.append_array(_u16(1))           # Mono
	out.append_array(_u32(rate))
	out.append_array(_u32(rate * 2))    # Bytes pro Sekunde
	out.append_array(_u16(2))           # Bytes pro Frame
	out.append_array(_u16(16))          # Bits

	out.append_array("data".to_ascii_buffer())
	out.append_array(_u32(data_size))

	for s in samples:
		var value := int(clampf(s, -1.0, 1.0) * 32767.0)
		out.append(value & 0xFF)
		out.append((value >> 8) & 0xFF)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("  nicht schreibbar: ", path)
		return
	file.store_buffer(out)
	file.close()


func _u32(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, value)
	return b


func _u16(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, value)
	return b
