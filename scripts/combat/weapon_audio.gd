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

	# Die Lautstaerke gehoert in den Schluessel: Dieselbe Waffe klingt mit
	# Schalldaempfer anders. Nur nach der Waffen-ID zu cachen wuerde je nach
	# Reihenfolge mal den gedaempften, mal den lauten Klang ausliefern.
	var key := "%s@%.2f" % [weapon.id, weapon.loudness_multiplier]
	if _cache.has(key):
		return _cache[key]

	var stream := _load_file_for(weapon)
	if stream == null:
		stream = make_gunshot(get_power_for_weapon(weapon))

	_cache[key] = stream
	return stream


## Ab dieser Lautstärke gilt eine Waffe als gedämpft und bekommt, falls
## vorhanden, ihre eigene Aufnahme.
##
## Der Schalldämpfer der AR-15 liegt bei 0.32, ein Kompensator über 1.0 —
## die Grenze trennt beides deutlich und ist kein Zufallswert.
const SUPPRESSED_BELOW := 0.6


## Sucht eine echte Audiodatei für diese Waffe.
##
## Die gedämpfte Aufnahme steht vorn: Ein Schalldämpfer verändert den Klang so
## grundlegend, dass die laute Aufnahme leiser gedreht nicht dasselbe ist. Sie
## bleibt ein Knall, nur ein leiserer — statt des dumpfen Schlags, den man
## erwartet.
static func _load_file_for(weapon: WeaponData) -> AudioStream:
	var candidates: Array[String] = []
	if weapon.loudness_multiplier < SUPPRESSED_BELOW:
		candidates.append("%s/%s/schuss_gedaempft" % [AUDIO_DIR, _short_name(weapon)])
		candidates.append("%s/%s_gedaempft" % [AUDIO_DIR, weapon.id])

	candidates.append_array([
		"%s/%s" % [AUDIO_DIR, weapon.id],
		"%s/%s" % [AUDIO_DIR, weapon.caliber],
		"%s/default" % AUDIO_DIR,
	])
	return _first_existing(candidates)


## Ein Geräusch aus dem Ordner dieser Waffe, z.B. "nachladen_magazin_raus".
##
## Fehlt die Datei, kommt null zurück und der Aufrufer bleibt still. Das ist
## Absicht: Ein fehlendes Nachladegeräusch soll das Nachladen nicht verhindern.
static func get_sound(weapon: WeaponData, sound_name: String) -> AudioStream:
	if weapon == null:
		return null

	var key := "%s/%s" % [weapon.id, sound_name]
	if _cache.has(key):
		return _cache[key]

	var stream := _first_existing([
		"%s/%s/%s" % [AUDIO_DIR, _short_name(weapon), sound_name],
		"%s/%s" % [AUDIO_DIR, sound_name],
	])
	_cache[key] = stream
	return stream


## Ordnername einer Waffe: "weapon_rifle_ar15" wird zu "ar15".
##
## Damit liegen die vielen Geräusche einer Waffe beieinander, statt den
## Hauptordner mit Dateinamen wie weapon_rifle_ar15_nachladen_magazin_raus
## zuzupflastern.
static func _short_name(weapon: WeaponData) -> String:
	var parts := String(weapon.id).split("_")
	return parts[parts.size() - 1] if parts.size() > 0 else String(weapon.id)


static func _first_existing(candidates: Array) -> AudioStream:
	for base in candidates:
		for ext in [".ogg", ".wav", ".mp3"]:
			var path: String = String(base) + ext
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
##
## Der Rückstoß gibt die Grundlautstärke vor, der Dämpfungsfaktor zieht sie
## herunter. Beides getrennt, weil ein Schalldämpfer die Waffe zwar auch etwas
## ruhiger macht, vor allem aber leiser — über den Rückstoß allein käme man
## nie auf den Unterschied zwischen gedämpft und ungedämpft.
static func get_power_for_weapon(weapon: WeaponData) -> float:
	if weapon == null:
		return 0.6
	var power := weapon.recoil_vertical / 260.0 * weapon.loudness_multiplier
	return clampf(power, 0.10, 1.0)


## Wie laut ein Schuss dieser Waffe abgespielt wird, in Dezibel.
##
## ---------------------------------------------------------------------------
## DAS HAT VORHER GEFEHLT, UND ZWAR VOLLSTAENDIG
##
## `loudness_multiplier` steuerte die Sample-Auswahl, die Synthese und die
## Knall-Belastung — aber nie die tatsaechliche Abspiellautstaerke. Ein
## Schalldaempfer machte damit bei Glock, AKM und M870 gar nichts hoerbar
## leiser. Nur die AR-15 klang gedaempft, und auch das nur, weil sie eine
## eigene Aufnahme mit anderem Charakter hat.
##
## Die eigene Aufnahme ersetzt diese Rechnung uebrigens NICHT: Alle Aufnahmen
## sind auf denselben Spitzenpegel normalisiert, `schuss_gedaempft.wav` ist
## also nicht leiser, sondern nur anders. Charakter kommt aus der Datei,
## Lautstaerke von hier.
##
## Bei 0,32 (Schalldaempfer der AR-15) sind das rund -10 dB, also etwa halb so
## laut empfunden. Realistisch waeren eher -25 dB, aber dann hoerte man den
## eigenen Schuss praktisch nicht mehr, und das fuehlt sich kaputt an statt
## leise.
static func volume_db_for(weapon: WeaponData) -> float:
	if weapon == null:
		return 0.0
	return linear_to_db(clampf(weapon.loudness_multiplier, 0.05, 2.0))
