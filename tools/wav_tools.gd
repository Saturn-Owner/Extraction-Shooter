## Gemeinsame WAV-Verarbeitung für die Werkzeuge in diesem Ordner.
##
## Godot kann WAV-Dateien zwar abspielen, aber nicht bearbeiten. Zum
## Zuschneiden, Mischen und Aufteilen heruntergeladener Aufnahmen brauchen
## wir Zugriff auf die einzelnen Samples — also lesen wir die Dateien
## selbst.
##
## Wird von trim_gunshots.gd und split_sounds.gd benutzt. Beide brauchen
## exakt dasselbe Lesen und Schreiben; getrennte Kopien würden früher oder
## später auseinanderlaufen.
class_name WavTools
extends RefCounted


## Liest die Kopfdaten. Chunks stehen NICHT immer an festen Positionen —
## viele Aufnahmen haben Zusatzchunks (LIST, INFO) vor den Audiodaten.
## Gibt {} zurück, wenn die Datei nicht verarbeitbar ist.
static func parse(raw: PackedByteArray) -> Dictionary:
	if raw.size() < 44:
		return {}
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
			info["format"] = raw.decode_u16(body)
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

	# Aufnahmen von Freesound und aus Profibibliotheken sind haeufig 24 bit
	# oder 32 bit Float, nicht 16 bit. Wer das nicht abdeckt, bekommt beim
	# Einbauen jedes Mal eine Fehlermeldung und weiss nicht, warum.
	var bits: int = info.get("bits", 0)
	var format: int = info.get("format", 1)
	if not (bits in [16, 24, 32]):
		printerr("  Bittiefe wird nicht unterstuetzt: ", bits)
		return {}
	if format not in [1, 3, 0xFFFE]:
		printerr("  Format wird nicht unterstuetzt (kein PCM/Float): ", format)
		return {}

	return info


## Länge in Sekunden.
static func duration_of(info: Dictionary) -> float:
	var bytes_per_frame: int = int(info.channels) * (int(info.bits) / 8)
	if bytes_per_frame <= 0 or int(info.rate) <= 0:
		return 0.0
	return float(info.data_size) / float(int(info.rate) * bytes_per_frame)


## Kanäle zusammenmischen und auf -1..1 bringen.
static func to_mono(raw: PackedByteArray, info: Dictionary) -> PackedFloat32Array:
	var channels: int = info.channels
	var start: int = info.data_start
	var size: int = info.data_size
	var bits: int = info.bits
	var is_float: bool = info.get("format", 1) == 3
	var bytes_per_sample := bits / 8
	var frames := size / (bytes_per_sample * channels)

	var out := PackedFloat32Array()
	out.resize(frames)

	for f in range(frames):
		var sum := 0.0
		for c in range(channels):
			var offset := start + (f * channels + c) * bytes_per_sample
			sum += read_sample(raw, offset, bits, is_float)
		out[f] = sum / float(channels)

	return out


## Ein einzelnes Sample, unabhängig von der Bittiefe, als -1..1.
static func read_sample(raw: PackedByteArray, offset: int, bits: int, is_float: bool) -> float:
	match bits:
		16:
			return float(raw.decode_s16(offset)) / 32768.0
		24:
			# 24 bit hat keine fertige Decodierfunktion: drei Bytes von
			# niedrig nach hoch, danach das Vorzeichen selbst herstellen.
			var value := raw[offset] | (raw[offset + 1] << 8) | (raw[offset + 2] << 16)
			if value >= 0x800000:
				value -= 0x1000000
			return float(value) / 8388608.0
		32:
			if is_float:
				return raw.decode_float(offset)
			return float(raw.decode_s32(offset)) / 2147483648.0
	return 0.0


## Der größte Ausschlag, 0 bis 1.
static func peak_of(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	return peak


## Die letzten Millisekunden ausblenden, sonst knackt ein harter Schnitt.
static func fade_out(samples: PackedFloat32Array, rate: int, seconds: float = 0.025) -> void:
	var fade := mini(int(seconds * rate), samples.size())
	if fade <= 0:
		return
	var first := samples.size() - fade
	for i in range(fade):
		samples[first + i] *= 1.0 - (float(i) / float(fade))


## Ganz kurz einblenden, damit ein Schnitt mitten im Signal nicht knackt.
static func fade_in(samples: PackedFloat32Array, rate: int, seconds: float = 0.003) -> void:
	var fade := mini(int(seconds * rate), samples.size())
	if fade <= 0:
		return
	for i in range(fade):
		samples[i] *= float(i) / float(fade)


## Schreibt Mono, 16 bit.
static func write(path: String, samples: PackedFloat32Array, rate: int) -> bool:
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
		return false
	file.store_buffer(out)
	file.close()
	return true


static func _u32(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, value)
	return b


static func _u16(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, value)
	return b
