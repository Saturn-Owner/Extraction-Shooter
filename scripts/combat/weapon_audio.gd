## Waffengeräusche: echte Dateien wenn vorhanden, sonst Synthese.
##
## ---------------------------------------------------------------------------
## EHRLICHE EINORDNUNG
##
## Synthetisch erzeugte Schüsse klingen NICHT realistisch und werden es auch
## nie. Ein echter Schuss ist eine Explosion mit Raumhall — das lässt sich
## nicht aus Rauschen und Hüllkurven zusammenbauen.
##
## Deshalb ist der bevorzugte Weg: echte Aufnahmen unter
##
##     assets/audio/weapons/
##
## ablegen. Diese Klasse findet sie automatisch. Gesucht wird in dieser
## Reihenfolge:
##
##   1. assets/audio/weapons/<weapon_id>.ogg      z.B. weapon_rifle_ak74m.ogg
##   2. assets/audio/weapons/<caliber>.ogg        z.B. 7.62x39.ogg
##   3. assets/audio/weapons/default.ogg
##   4. Synthese als Notbehelf
##
## .wav funktioniert genauso. Freie Quellen mit brauchbarer Lizenz:
##   - Sonniss "GDC Game Audio Bundle" (jährlich, kostenlos, kommerziell nutzbar)
##   - freesound.org (Lizenz pro Datei prüfen, oft CC0)
##
## Die Synthese bleibt als Rückfallebene drin, damit das Spiel ohne
## Audiodateien nicht stumm ist.
class_name WeaponAudio
extends RefCounted

const SAMPLE_RATE := 44100
const AUDIO_DIR := "res://assets/audio/weapons"

## Einmal geladene bzw. berechnete Streams, damit nicht bei jedem Schuss
## neu gerechnet wird.
static var _cache: Dictionary = {}


## Liefert den Schuss-Sound für eine Waffe.
static func get_gunshot(weapon: WeaponData) -> AudioStream:
	if weapon == null:
		return null

	var key := String(weapon.id)
	if _cache.has(key):
		return _cache[key]

	var stream := _load_file_for(weapon)
	if stream == null:
		stream = make_gunshot(get_power_for_weapon(weapon))

	_cache[key] = stream
	return stream


## Sucht eine echte Audiodatei für diese Waffe.
static func _load_file_for(weapon: WeaponData) -> AudioStream:
	# Kaliber wie "12/70" enthalten einen Schraegstrich. Unbehandelt wuerde
	# daraus ein Unterordner "12/" mit der Datei "70.wav" — ein Dateiname,
	# auf den niemand von selbst kommt. Deshalb ersetzen.
	var caliber_name := String(weapon.caliber).replace("/", "_")

	var candidates := [
		"%s/%s" % [AUDIO_DIR, weapon.id],
		"%s/%s" % [AUDIO_DIR, caliber_name],
		"%s/default" % AUDIO_DIR,
	]
	for base in candidates:
		for ext in [".ogg", ".wav", ".mp3"]:
			var path: String = base + ext
			if ResourceLoader.exists(path):
				var res := load(path)
				if res is AudioStream:
					return res as AudioStream
	return null


## Verwirft den Zwischenspeicher — nötig, wenn zur Laufzeit Dateien
## dazukommen oder Waffenwerte geändert werden.
static func clear_cache() -> void:
	_cache.clear()


# ---------------------------------------------------------------------------
# Synthese (Notbehelf)
# ---------------------------------------------------------------------------

## Baut einen Schussknall aus drei Teilen, weil ein einzelner Rauschimpuls
## nach Zischen klingt statt nach Waffe:
##
##   1. KNALL    Sehr kurzer, harter Transient. Das ist, was das Ohr als
##               "Schuss" erkennt.
##   2. KÖRPER   Tiefer, resonanter Anteil. Gibt die Wucht.
##   3. NACHHALL Langsam ausklingendes, dumpfes Rauschen. Ohne das klingt
##               es wie im schalltoten Raum.
##
##   power  0.3 (Pistole) bis 1.0 (Scharfschützengewehr)
static func make_gunshot(power: float = 0.6) -> AudioStreamWAV:
	power = clampf(power, 0.0, 1.0)

	# Grosse Kaliber klingen länger nach.
	var duration := lerpf(0.30, 0.75, power)
	var frames := int(SAMPLE_RATE * duration)

	var data := PackedByteArray()
	data.resize(frames * 2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Zwei Tiefpassstufen ergeben eine steilere Filterkurve und damit einen
	# volleren Klang als ein einzelner Filter.
	var lp1 := 0.0
	var lp2 := 0.0
	var tail_lp := 0.0

	# Resonanzfrequenz des Laufs: grosse Kaliber tiefer.
	var body_freq := lerpf(210.0, 78.0, power)
	var crack_frames := int(SAMPLE_RATE * 0.0035)

	for i in range(frames):
		var t := float(i) / float(SAMPLE_RATE)
		var progress := float(i) / float(frames)
		var noise := rng.randf_range(-1.0, 1.0)

		# --- 1. Knall: extrem kurz, kaum gefiltert, sehr laut -------------
		var crack := 0.0
		if i < crack_frames:
			var c := 1.0 - float(i) / float(crack_frames)
			crack = noise * c * c * 1.4

		# --- 2. Körper: gefiltertes Rauschen plus Resonanz ----------------
		var smoothing := lerpf(0.62, 0.30, power)
		lp1 = lerpf(noise, lp1, smoothing)
		lp2 = lerpf(lp1, lp2, smoothing)

		var body_env := exp(-26.0 * t)
		var resonance := sin(TAU * body_freq * t) * exp(-19.0 * t) * (0.5 + 0.45 * power)
		var body := (lp2 * 1.5 + resonance) * body_env

		# --- 3. Nachhall: stark gedämpft, klingt langsam aus --------------
		tail_lp = lerpf(noise, tail_lp, 0.93)
		var tail_env := exp(-lerpf(11.0, 4.5, power) * t)
		var tail := tail_lp * tail_env * (0.20 + 0.30 * power)

		var sample := crack + body + tail

		# Sättigung: begrenzt weich statt hart abzuschneiden. Das erzeugt
		# die Obertöne, die einen Knall "laut" wirken lassen.
		sample = tanh(sample * 1.9) * 0.82

		# Ganz am Ende sauber ausblenden, sonst knackt es beim Abbruch.
		if progress > 0.9:
			sample *= (1.0 - progress) / 0.1

		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Trockener Klick bei leerem Magazin. Sehr kurz und leise — das soll
## auffallen, ohne zu nerven.
static func make_dry_fire() -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * 0.045)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var lp := 0.0
	for i in range(frames):
		var t := float(i) / float(SAMPLE_RATE)
		lp = lerpf(rng.randf_range(-1.0, 1.0), lp, 0.45)
		var envelope := exp(-190.0 * t)
		var value := int(clampf(lp * envelope * 0.5, -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Wie "kräftig" eine Waffe klingen soll, abgeleitet aus ihren Daten.
## So muss niemand pro Waffe einen Wert pflegen.
static func get_power_for_weapon(weapon: WeaponData) -> float:
	if weapon == null:
		return 0.6
	return clampf(weapon.recoil_vertical / 260.0, 0.28, 1.0)
