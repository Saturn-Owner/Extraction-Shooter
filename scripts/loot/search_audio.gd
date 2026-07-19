## Klang beim Fund eines Gegenstands.
##
## GRUNDIDEE: Man hört den GEGENSTAND, nicht eine Belohnung.
##
## Ein Schlüsselbund klimpert, eine Waffe setzt sich schwer und metallisch,
## Patronen klicken hell gegeneinander, eine Platte macht einen dumpfen
## Schlag. Kein Ton, keine Melodie, kein Dur-Akkord — das wäre ein
## Handyspiel, und der Fund würde albern statt bedrohlich wirken.
##
## Die Seltenheit steuert nur, WIE DEUTLICH man es hört, nicht was:
##   COMMON    still. Krimskrams verdient keine Aufmerksamkeit, und ein
##             Geräusch pro Patronenschachtel wäre nach zehn Minuten Terror.
##   UNCOMMON  leise, knapp
##   RARE      deutlich
##   EPIC      deutlich, plus ein tiefer Unterton, der Gewicht gibt
##
## TECHNIK: Metall klingt metallisch, weil seine Obertöne NICHT ganzzahlig
## übereinander liegen. Deshalb sind die Frequenzen hier bewusst krumm
## (190/268/402/610 statt 200/400/600) — ganzzahlige Vielfache klängen wie
## eine Orgel. Dazu ein kurzer Rauschanteil für den Anschlag.
##
## Synthetisiert statt aus Dateien: Es sind kurze Geräusche, die exakt
## aufeinander abgestimmt sein sollen. Bei Waffenschüssen ist das anders —
## die müssen echt klingen und kommen deshalb aus Dateien.
class_name SearchAudio
extends RefCounted

const SAMPLE_RATE := 44100

## Fester Startwert: Das Rauschen soll bei jedem Spielstart gleich klingen.
const NOISE_SEED := 20260719

## Einmal gebaut, dann wiederverwendet. Schluessel: Kategorie + Seltenheit.
static var _cache: Dictionary = {}


## Wo echte Aufnahmen liegen. Was hier gefunden wird, schlaegt die Synthese.
const AUDIO_DIR := "res://assets/audio/loot"


## Der passende Klang zu einem Gegenstand. null = bewusst still.
##
## ECHTE DATEIEN GEHEN VOR. Die Synthese unten ist nur der Platzhalter,
## bis jemand richtige Aufnahmen abgelegt hat — synthetisches Metall
## klingt nie ganz echt, egal wie sorgfaeltig man dreht.
static func get_stream(data: ItemData) -> AudioStream:
	if data == null:
		return null

	var rarity := data.get_rarity()
	if rarity == ItemData.Rarity.COMMON:
		return null

	var key := "%d:%d" % [data.category, rarity]
	if _cache.has(key):
		return _cache[key]

	var stream := _load_file_for(data)
	if stream == null:
		stream = _build(data.category, rarity)

	_cache[key] = stream
	return stream


## Sucht eine echte Aufnahme, von speziell nach allgemein:
##   1. genau dieser Gegenstand   loot/ammo_556x45_m995.wav
##   2. seine Kategorie           loot/weapon.wav
##   3. Notnagel fuer alles       loot/default.wav
##
## Dadurch kann man mit einer einzigen Datei je Kategorie anfangen und
## spaeter einzelne Gegenstaende gezielt herausheben.
static func _load_file_for(data: ItemData) -> AudioStream:
	var category_name: String = String(ItemData.Category.keys()[data.category]).to_lower()
	var candidates := [
		"%s/%s" % [AUDIO_DIR, data.id],
		"%s/%s" % [AUDIO_DIR, category_name],
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


static func clear_cache() -> void:
	_cache.clear()


## Wie laut die Stufe ist. Der Unterschied muss hörbar sein, ohne dass
## Episch aus den Boxen springt.
static func _volume_for(rarity: ItemData.Rarity) -> float:
	match rarity:
		ItemData.Rarity.EPIC: return 0.62
		ItemData.Rarity.RARE: return 0.50
	return 0.34


static func _build(category: ItemData.Category, rarity: ItemData.Rarity) -> AudioStreamWAV:
	var strikes: Array = []
	var duration := 0.5

	match category:
		ItemData.Category.KEY:
			# Schlüsselbund: mehrere kleine Metallteile, die gegeneinander
			# schlagen. Hoch, hart, unregelmässig — das erkennt man sofort.
			duration = 0.62
			strikes = [
				{at = 0.000, partials = [2410.0, 3170.0, 4310.0, 5590.0], decay = 24.0, amp = 0.95, noise = 0.30},
				{at = 0.068, partials = [2180.0, 2960.0, 4020.0], decay = 27.0, amp = 0.72, noise = 0.22},
				{at = 0.132, partials = [2620.0, 3480.0, 4740.0], decay = 30.0, amp = 0.55, noise = 0.18},
				{at = 0.215, partials = [2290.0, 3060.0], decay = 34.0, amp = 0.34, noise = 0.12},
			]

		ItemData.Category.WEAPON:
			# Eine Waffe, die sich in der Kiste setzt: schwerer Metallschlag,
			# danach klappert ein loses Teil nach.
			duration = 0.70
			strikes = [
				{at = 0.000, partials = [188.0, 268.0, 402.0, 611.0], decay = 13.0, amp = 1.00, noise = 0.42},
				{at = 0.105, partials = [232.0, 341.0, 523.0], decay = 19.0, amp = 0.48, noise = 0.26},
				{at = 0.178, partials = [880.0, 1240.0], decay = 32.0, amp = 0.22, noise = 0.14},
			]

		ItemData.Category.AMMO:
			# Patronen: helles Messing, zwei schnelle Klicks.
			duration = 0.38
			strikes = [
				{at = 0.000, partials = [1150.0, 1620.0, 2210.0], decay = 30.0, amp = 0.85, noise = 0.28},
				{at = 0.055, partials = [1290.0, 1810.0], decay = 34.0, amp = 0.52, noise = 0.20},
			]

		ItemData.Category.ARMOR_PLATE, ItemData.Category.ARMOR_RIG:
			# Keramik und Stahl: dumpf, schwer, kein Nachklingen.
			duration = 0.52
			strikes = [
				{at = 0.000, partials = [94.0, 143.0, 207.0], decay = 21.0, amp = 1.00, noise = 0.55},
				{at = 0.070, partials = [118.0, 176.0], decay = 28.0, amp = 0.38, noise = 0.30},
			]

		ItemData.Category.MEDICAL, ItemData.Category.FOOD:
			# Folie und Papier: nur Rauschen, kein Ton.
			duration = 0.46
			strikes = [
				{at = 0.000, partials = [], decay = 11.0, amp = 0.75, noise = 1.00},
				{at = 0.120, partials = [], decay = 15.0, amp = 0.45, noise = 1.00},
			]

		ItemData.Category.BACKPACK, ItemData.Category.CLOTHING:
			# Stoff: weiches, tiefes Rascheln.
			duration = 0.52
			strikes = [
				{at = 0.000, partials = [], decay = 7.5, amp = 0.70, noise = 1.00},
			]

		_:
			# Werkzeug, Krimskrams: ein trockenes Klopfen.
			duration = 0.40
			strikes = [
				{at = 0.000, partials = [418.0, 703.0, 985.0], decay = 26.0, amp = 0.80, noise = 0.34},
			]

	# Episch bekommt einen tiefen Unterton. Der macht den Fund schwer,
	# ohne ihn festlich zu machen — genau der Unterschied zum Jingle.
	if rarity == ItemData.Rarity.EPIC:
		strikes.append({at = 0.0, partials = [52.0, 78.0], decay = 6.0, amp = 0.55, noise = 0.0})
		duration = maxf(duration, 0.68)

	return _render(strikes, duration, _volume_for(rarity))


## Mischt alle Anschläge in einen Puffer und schreibt daraus 16-bit-PCM.
static func _render(strikes: Array, duration: float, volume: float) -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * duration)
	var buffer := PackedFloat32Array()
	buffer.resize(frames)

	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED

	for strike in strikes:
		var start := int(float(strike.at) * SAMPLE_RATE)
		var partials: Array = strike.partials
		var decay: float = strike.decay
		var amp: float = strike.amp
		var noise: float = strike.get("noise", 0.0)

		# Tiefpass-Zustand fürs Rauschen: unbehandeltes Weissrauschen
		# zischt, gefiltertes klingt nach Material.
		var lp := 0.0

		for i in range(start, frames):
			var t := float(i - start) / float(SAMPLE_RATE)
			var envelope := exp(-decay * t)
			if envelope < 0.0005:
				break

			var sample := 0.0
			if not partials.is_empty():
				for p in partials:
					sample += sin(TAU * float(p) * t)
				sample /= float(partials.size())

			if noise > 0.0:
				lp = lerpf(rng.randf_range(-1.0, 1.0), lp, 0.62)
				# Der Rauschanteil verschwindet schneller als der Ton —
				# das ist der Anschlag, nicht der Nachklang.
				sample += lp * noise * exp(-decay * 2.5 * t)

			buffer[i] += sample * envelope * amp

	var data := PackedByteArray()
	data.resize(frames * 2)

	for i in range(frames):
		# Weich begrenzen statt hart abschneiden, sonst zerrt es dort,
		# wo sich zwei Anschläge überlagern.
		var sample: float = tanh(buffer[i] * 1.1) * volume

		# Sauber ausblenden, sonst knackt das Ende.
		var progress := float(i) / float(frames)
		if progress > 0.88:
			sample *= (1.0 - progress) / 0.12

		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
