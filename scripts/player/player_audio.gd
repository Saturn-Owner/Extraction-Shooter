## Lädt die Geräusche, die vom Spieler selbst kommen: Schritte und Atmen.
##
## Gleiches Muster wie WeaponAudio und SearchAudio — statisch, mit Cache, und
## wenn eine Datei fehlt, kommt `null` zurück statt eines Absturzes. Ein
## fehlendes Schrittgeräusch soll niemanden am Laufen hindern.
##
## Warum keine Synthese als Rückfall wie bei der Waffe: Ein Schritt im Schnee
## ist Rauschen mit Struktur — Knirschen, Nachrutschen, Andrücken. Das klingt
## synthetisch immer nach Zischen. Lieber still als falsch.
class_name PlayerAudio
extends RefCounted

const AUDIO_DIR := "res://assets/audio/player"

## Wie viele Schrittvarianten es höchstens gibt. Gesucht wird von 01 aufwärts,
## bei der ersten Lücke ist Schluss.
const MAX_FOOTSTEPS := 16

static var _footsteps: Array[AudioStream] = []
static var _breathing: AudioStream = null
static var _loaded := false

## Welche Variante zuletzt gespielt wurde. Zweimal dieselbe hintereinander
## fällt sofort als Wiederholung auf — bei acht Dateien passiert das rein
## zufällig aber in jedem achten Schritt.
static var _last_index := -1

static var _rng := RandomNumberGenerator.new()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_rng.randomize()

	for i in range(1, MAX_FOOTSTEPS + 1):
		var stream := _load("%s/schritt_schnee_%02d" % [AUDIO_DIR, i])
		if stream == null:
			break
		_footsteps.append(stream)

	_breathing = _load("%s/ausser_atem" % AUDIO_DIR)


## Ein Schritt — nie zweimal derselbe hintereinander.
static func get_footstep() -> AudioStream:
	ensure_loaded()
	if _footsteps.is_empty():
		return null
	if _footsteps.size() == 1:
		return _footsteps[0]

	var index := _rng.randi_range(0, _footsteps.size() - 1)
	if index == _last_index:
		index = (index + 1) % _footsteps.size()
	_last_index = index
	return _footsteps[index]


static func get_breathing() -> AudioStream:
	ensure_loaded()
	return _breathing


static func get_footstep_count() -> int:
	ensure_loaded()
	return _footsteps.size()


## Für Tests: die Auswahl zurücksetzen.
static func reset() -> void:
	_footsteps.clear()
	_breathing = null
	_loaded = false
	_last_index = -1


static func _load(base: String) -> AudioStream:
	for ext: String in [".ogg", ".wav", ".mp3"]:
		var path := base + ext
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is AudioStream:
				return res as AudioStream
	return null
