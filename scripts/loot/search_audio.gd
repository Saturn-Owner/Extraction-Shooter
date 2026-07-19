## Klang beim Fund eines Gegenstands, gestaffelt nach Seltenheit.
##
## GESTALTUNGSREGEL: ernst bleiben. Das hier ist kein Belohnungsjingle wie
## in einem Mobile-Spiel — ein Fund im Raid ist eine Information, keine
## Feier. Deshalb tiefe, kurze, leise Klänge ohne Dur-Fanfare.
##
##   COMMON    nichts. Krimskrams verdient keine Aufmerksamkeit, und ein
##             Geräusch pro Patronenschachtel wäre nach zehn Minuten Terror.
##   UNCOMMON  ein einzelner tiefer Ton, kaum mehr als ein Impuls
##   RARE      zwei Töne, leicht steigend — man merkt auf, ohne dass es feiert
##   EPIC      tiefer Anschwellton plus Intervall; der einzige Klang, der
##             lang genug ist, um von weitem als "da war was" zu wirken
##
## Synthetisiert statt aus Dateien geladen: vier kurze Töne sind der
## Aufwand einer Beschaffung nicht wert, und sie lassen sich hier exakt
## aufeinander abstimmen. Bei den Waffensounds ist das anders — die müssen
## echt klingen und kommen deshalb aus Dateien.
class_name SearchAudio
extends RefCounted

const SAMPLE_RATE := 44100

## Einmal gebaut, dann wiederverwendet.
static var _cache: Dictionary = {}


## Der passende Klang zu einer Seltenheitsstufe. null = bewusst still.
static func get_stream(rarity: ItemData.Rarity) -> AudioStream:
	if rarity == ItemData.Rarity.COMMON:
		return null

	if _cache.has(rarity):
		return _cache[rarity]

	var stream: AudioStreamWAV = null
	match rarity:
		ItemData.Rarity.UNCOMMON:
			stream = _make_tone([146.8], 0.16, 0.16)
		ItemData.Rarity.RARE:
			stream = _make_tone([146.8, 196.0], 0.34, 0.22)
		ItemData.Rarity.EPIC:
			stream = _make_tone([98.0, 146.8, 220.0], 0.62, 0.28)

	_cache[rarity] = stream
	return stream


static func clear_cache() -> void:
	_cache.clear()


## Baut eine Folge tiefer Töne, die ineinander übergehen.
##
## Jeder Ton bekommt einen weichen Einsatz (kein Klicken) und einen langen
## Ausklang. Eine leise Oktave darüber gibt Körper, ohne hell zu werden —
## reine Sinustöne klingen sonst nach Testton, nicht nach Spiel.
static func _make_tone(frequencies: Array, duration: float, volume: float) -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var step := duration / float(maxi(1, frequencies.size()))

	for i in range(frames):
		var t := float(i) / float(SAMPLE_RATE)
		var sample := 0.0

		for n in frequencies.size():
			var start := float(n) * step
			if t < start:
				continue
			var local := t - start
			var freq: float = frequencies[n]

			# Weicher Einsatz über 12 ms, danach exponentiell aus.
			var attack := clampf(local / 0.012, 0.0, 1.0)
			var decay := exp(-4.5 * local)
			var envelope := attack * decay

			sample += sin(TAU * freq * local) * envelope
			sample += sin(TAU * freq * 2.0 * local) * envelope * 0.18

		# Weich begrenzen statt hart abschneiden, sonst zerrt es beim Überlappen.
		sample = tanh(sample * 0.9) * volume

		# Sauber ausblenden, sonst knackt das Ende.
		var progress := float(i) / float(frames)
		if progress > 0.85:
			sample *= (1.0 - progress) / 0.15

		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
