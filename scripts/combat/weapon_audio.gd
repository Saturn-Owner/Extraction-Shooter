## Erzeugt Waffengeräusche synthetisch zur Laufzeit.
##
## WICHTIG — PLATZHALTER:
## Das sind KEINE echten Waffensounds. Claude kann keine Audiodateien
## erstellen, deshalb werden hier Rauschimpulse mit Hüllkurve berechnet.
## Sie klingen nicht nach echter Waffe, geben aber die richtige Rückmeldung
## im richtigen Moment — und genau das braucht man beim Abstimmen des
## Schiessgefühls.
##
## Zum Ersetzen: echte .wav/.ogg laden und statt make_gunshot() verwenden.
## Gute freie Quellen sind freesound.org (Lizenz beachten) und die
## Sonniss-GDC-Pakete.
##
## Vorteil des synthetischen Ansatzes: keine Dateien im Repo, und die
## Klangfarbe skaliert automatisch mit dem Kaliber.
class_name WeaponAudio
extends RefCounted

const SAMPLE_RATE := 22050


## Baut einen Schussknall.
##
##   power     0.3 (Pistole) bis 1.0 (Scharfschützengewehr)
##   duration  Länge in Sekunden
static func make_gunshot(power: float = 0.6, duration: float = 0.28) -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Tiefpass-Zustand: grosse Kaliber klingen dumpfer, kleine schärfer.
	var lowpass := 0.0
	var smoothing := lerpf(0.75, 0.35, clampf(power, 0.0, 1.0))

	# Nachhall-Anteil, damit es nicht wie ein Klick klingt.
	var tail_start := int(frames * 0.12)

	for i in range(frames):
		var t := float(i) / float(frames)

		# Hüllkurve: sehr harter Anschlag, dann exponentieller Abfall.
		var envelope: float
		if i < tail_start:
			envelope = 1.0 - (float(i) / float(tail_start)) * 0.35
		else:
			var tail_t := float(i - tail_start) / float(maxi(1, frames - tail_start))
			envelope = 0.65 * exp(-5.5 * tail_t)

		var noise := rng.randf_range(-1.0, 1.0)
		lowpass = lerpf(noise, lowpass, smoothing)

		# Tiefer Anteil für die Wucht grosser Kaliber.
		var thump := sin(TAU * lerpf(120.0, 55.0, power) * t * duration) * exp(-14.0 * t) * power * 0.55

		var sample := clampf((lowpass * 0.8 + thump) * envelope * lerpf(0.45, 0.95, power), -1.0, 1.0)
		var value := int(sample * 32767.0)

		# 16 Bit, little endian.
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Kurzer trockener Klick, wenn das Magazin leer ist.
static func make_dry_fire() -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * 0.06)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(frames):
		var t := float(i) / float(frames)
		var envelope := exp(-32.0 * t)
		var sample := clampf(rng.randf_range(-1.0, 1.0) * envelope * 0.35, -1.0, 1.0)
		var value := int(sample * 32767.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Metallisches Klacken beim Nachladen.
static func make_reload() -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * 0.22)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Zwei Klacks: Magazin raus, Magazin rein.
	for i in range(frames):
		var t := float(i) / float(frames)
		var envelope := exp(-40.0 * t) + 0.8 * exp(-40.0 * maxf(0.0, t - 0.45))
		var metallic := sin(TAU * 1800.0 * t * 0.22) * 0.4
		var sample := clampf((rng.randf_range(-1.0, 1.0) * 0.6 + metallic) * envelope * 0.3, -1.0, 1.0)
		var value := int(sample * 32767.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Wie "kräftig" eine Waffe klingen soll, abgeleitet aus ihren Daten.
## Ein schwerer Rückstoss und ein grosses Magazinkaliber ergeben einen
## wuchtigeren Knall — ohne dass jemand pro Waffe einen Wert pflegen muss.
static func get_power_for_weapon(weapon: WeaponData) -> float:
	if weapon == null:
		return 0.6
	return clampf(weapon.recoil_vertical / 260.0, 0.28, 1.0)
