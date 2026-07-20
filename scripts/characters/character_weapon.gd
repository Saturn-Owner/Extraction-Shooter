## Eine Waffe in der Hand einer Figur.
##
## ---------------------------------------------------------------------------
## DASSELBE MODELL WIE IM KAMERARAUM
##
## `WeaponViewmodel` ist nicht an die Kamera gebunden — es ist Geometrie mit
## beweglichen Teilen und einer Handvoll `notify_*`-Aufrufen. Was `WeaponView`
## vor der Kamera tut, tut diese Klasse an einer Figur. Damit gibt es die
## AR-15 genau EINMAL im Projekt, und wer sie in Blender ändert, ändert sie
## für Spieler und Gegner zugleich.
##
## ---------------------------------------------------------------------------
## SIE HÄNGT AN DER HAND, NICHT AN DER FIGUR
##
## Aufgehängt wird am unteren Ende des rechten Unterarms. Dadurch folgt die
## Waffe der Armhaltung von selbst — wer die Haltung in `CharacterAnimation`
## ändert, muss hier nichts nachziehen. Die Alternative wäre, Waffe und Arme
## getrennt auszurichten, und dann läuft beides über kurz oder lang
## auseinander.
##
## ---------------------------------------------------------------------------
## KEIN ECHTES SCHIESSEN
##
## Diese Klasse erzeugt Mündungsfeuer, Knall und Bewegung — aber KEINE
## Geschosse. Sie ist Vorführung, kein Gegner. Wer wirklich schiessen soll,
## bekommt eine `Weapon`, und die entscheidet dann server-autoritativ über
## Treffer. Hier wäre das nur eine zweite, halbgare Kopie derselben Logik.
class_name CharacterWeapon
extends Node3D

## Was die Figur mit der Waffe tut.
enum Behaviour {
	HOLD,     ## nur halten
	RELOAD,   ## immer wieder nachladen
	SHOOT,    ## feuern, bis leer, dann nachladen
}

@export var weapon_id: StringName = &"weapon_rifle_ar15"

## Anbauteile, als IDs. Der Schalldämpfer ist `ar15_muzzle_suppressor`.
@export var attachment_ids: Array[StringName] = []

@export var behaviour: Behaviour = Behaviour.HOLD

## Wie viele Schuss, bevor nachgeladen wird.
@export var magazine_size: int = 12

## Pause zwischen zwei Schüssen, in Sekunden.
@export var shot_interval: float = 0.16

## Wie lange ein Nachladen dauert.
@export var reload_seconds: float = 2.4

## Pause nach dem Nachladen, bevor es weitergeht.
@export var rest_seconds: float = 1.2

var data: WeaponData
var viewmodel: WeaponViewmodel

var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _shot_sound: AudioStream

## Wie viele Stimmen gleichzeitig klingen dürfen. Weniger als beim Spieler:
## Diese Figur feuert nicht in Dauerfeuer, und es können mehrere im Level
## stehen.
const VOICES := 3

var _timer: float = 0.0
var _rounds: int = 0
var _reloading: bool = false
var _reload_left: float = 0.0
var _resting: float = 0.0


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	_build()


func _build() -> void:
	var base := ItemRegistry.get_item(weapon_id)
	if not (base is WeaponData):
		push_error("[CharacterWeapon] Unbekannte Waffe: %s" % weapon_id)
		return

	# Anbauteile über denselben Weg wie beim Spieler, damit ein Schalldämpfer
	# hier genauso wirkt: leiser Klang, eigene Aufnahme, weniger Rückstoss.
	var build := WeaponBuild.new()
	for id in attachment_ids:
		var part := ItemRegistry.get_item(id)
		if part is AttachmentData:
			build.set_attachment((part as AttachmentData).slot, id)
		else:
			push_warning("[CharacterWeapon] Unbekanntes Anbauteil: %s" % id)

	data = WeaponBuild.apply(base as WeaponData, build)

	viewmodel = data.create_viewmodel()
	viewmodel.name = "Modell"
	viewmodel.weapon_data = data
	viewmodel.attachments = build.attachments.duplicate()
	add_child(viewmodel)

	_shot_sound = WeaponAudio.get_gunshot(data)
	_build_voices()
	_rounds = magazine_size


func _build_voices() -> void:
	GameAudio.ensure_buses()
	for i in range(VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Stimme%d" % (i + 1)
		voice.bus = GameAudio.WORLD_BUS
		voice.unit_size = 45.0
		voice.max_distance = 900.0
		add_child(voice)
		_voices.append(voice)


func _process(delta: float) -> void:
	if viewmodel == null:
		return

	# Ohne diesen Aufruf steht der Verschluss still und das Magazin klebt
	# fest — die Mechanik läuft nicht von allein.
	viewmodel.update_mechanics(delta)

	match behaviour:
		Behaviour.HOLD:
			pass
		Behaviour.RELOAD:
			_tick_reload_loop(delta)
		Behaviour.SHOOT:
			_tick_shooting(delta)


## Lädt endlos nach, mit Pause dazwischen.
func _tick_reload_loop(delta: float) -> void:
	if _reloading:
		_advance_reload(delta)
		return
	_resting -= delta
	if _resting <= 0.0:
		_start_reload()


## Feuert, bis das Magazin leer ist, lädt nach, wartet, von vorn.
func _tick_shooting(delta: float) -> void:
	if _reloading:
		_advance_reload(delta)
		return

	if _rounds <= 0:
		_resting -= delta
		if _resting <= 0.0:
			_start_reload()
		return

	_timer -= delta
	if _timer <= 0.0:
		_fire()
		_timer = shot_interval


func _fire() -> void:
	_rounds -= 1
	viewmodel.notify_shot()

	var muzzle := viewmodel.muzzle_point
	if muzzle != null:
		var power := WeaponAudio.get_power_for_weapon(data)
		MuzzleFlash.spawn(_spawn_parent(), muzzle.global_transform, 0.6 + power)

	_play(_shot_sound, randf_range(0.94, 1.06), WeaponAudio.volume_db_for(data))

	if _rounds <= 0:
		_resting = rest_seconds


func _start_reload() -> void:
	_reloading = true
	_reload_left = reload_seconds
	viewmodel.notify_reload(0.0, true)


func _advance_reload(delta: float) -> void:
	_reload_left -= delta
	var progress := 1.0 - clampf(_reload_left / maxf(0.01, reload_seconds), 0.0, 1.0)
	viewmodel.notify_reload(progress, true)

	if _reload_left > 0.0:
		return

	_reloading = false
	_rounds = magazine_size
	_resting = rest_seconds
	viewmodel.notify_sequence_ended()


## Wohin das Mündungsfeuer gehängt wird.
##
## NICHT EINFACH `get_tree().current_scene`: Im Testlauf über `--script` gibt
## es keine Hauptszene, der Wert ist dann null, und `add_child` darauf wirft
## einen Fehler. Aufgefallen ist das nicht in den Prüfungen — die blieben grün
## —, sondern weil `run_tests.ps1` auch Skriptfehler als Fehlschlag wertet.
## Genau dafür hat Lucas diese Prüfung eingebaut.
##
## Dieselbe Überlegung steht schon in `Weapon.get_spawn_parent()`.
func _spawn_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return self
	if tree.current_scene != null:
		return tree.current_scene
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != tree.root:
		node = node.get_parent()
	return node


func _play(stream: AudioStream, pitch: float, volume_db: float) -> void:
	if stream == null or _voices.is_empty():
		return
	var voice: AudioStreamPlayer3D = null
	for candidate in _voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		voice = _voices[_next_voice]
		_next_voice = (_next_voice + 1) % _voices.size()

	voice.stream = stream
	voice.pitch_scale = pitch
	voice.volume_db = volume_db
	voice.play()


## Setzt Magazin und Ablauf zurück.
func reset() -> void:
	_rounds = magazine_size
	_reloading = false
	_reload_left = 0.0
	_resting = 0.0
	_timer = 0.0
	if viewmodel != null:
		viewmodel.notify_sequence_ended()
