## Die Waffe in der Hand des Spielers.
##
## Verbindet WeaponData (wie geschossen wird) mit AmmoData (was der Treffer
## anrichtet). Dieselbe Waffe fuehlt sich mit anderer Munition deutlich
## anders an — das ist beabsichtigt.
##
## NETZWERK: Der Client darf hier abdruecken, aber die Trefferentscheidung
## faellt spaeter auf dem Server. Diese Klasse erzeugt nur die Anfrage
## "ich schiesse in diese Richtung" plus die sichtbare Rueckmeldung.
class_name Weapon
extends Node3D

signal fired(ammo: AmmoData, rounds_left: int)
signal reloaded(rounds: int)
signal dry_fire()
signal recoil_kick(vertical: float, horizontal: float)

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

@export var weapon_id: StringName = &"weapon_rifle_ar15"
@export var ammo_id: StringName = &"ammo_556x45_m855a1"

## Auf welchen Ebenen Geschosse einschlagen (1 = Welt, 2 = Spieler, 4 = Gegner).
@export_flags_3d_physics var projectile_mask: int = 1 | 2 | 4

var data: WeaponData
var loaded_ammo: AmmoData
var rounds_in_magazine: int = 0
var current_fire_mode: WeaponData.FireMode = WeaponData.FireMode.SINGLE

var _cooldown: float = 0.0
var _burst_remaining: int = 0
var _shots_since_release: int = 0

## Synthetische Platzhalter-Sounds, einmal pro Waffe berechnet.
var _shot_sound: AudioStreamWAV
var _dry_sound: AudioStreamWAV
var _reload_sound: AudioStreamWAV

@onready var _muzzle: Node3D = $Muzzle
@onready var _audio: AudioStreamPlayer3D = $Muzzle/AudioStreamPlayer3D


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	setup(weapon_id, ammo_id)
	_dry_sound = WeaponAudio.make_dry_fire()
	_reload_sound = WeaponAudio.make_reload()


## Waffe und Munition setzen. Laedt gleich ein volles Magazin.
func setup(p_weapon_id: StringName, p_ammo_id: StringName) -> bool:
	var w := ItemRegistry.get_item(p_weapon_id)
	var a := ItemRegistry.get_item(p_ammo_id)

	if not (w is WeaponData):
		push_error("[Weapon] Unbekannte Waffe: %s" % p_weapon_id)
		return false
	if not (a is AmmoData):
		push_error("[Weapon] Unbekannte Munition: %s" % p_ammo_id)
		return false

	data = w as WeaponData
	if not data.accepts_ammo(a as AmmoData):
		push_error("[Weapon] %s passt nicht in %s" % [a.display_name, data.display_name])
		return false

	loaded_ammo = a as AmmoData
	weapon_id = p_weapon_id
	ammo_id = p_ammo_id
	rounds_in_magazine = data.magazine_size
	current_fire_mode = data.fire_modes[0] if not data.fire_modes.is_empty() else WeaponData.FireMode.SINGLE

	# Klangfarbe passt sich der Waffe an — eine Pistole knallt anders als
	# ein Scharfschützengewehr, ohne dass jemand Werte pflegen muss.
	_shot_sound = WeaponAudio.make_gunshot(WeaponAudio.get_power_for_weapon(data))
	return true


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

	# Feuerstoss weiterschiessen, ohne dass der Spieler nachdrueckt.
	if _burst_remaining > 0 and _cooldown <= 0.0:
		_burst_remaining -= 1
		_shoot()


## Naechsten Feuermodus waehlen.
func cycle_fire_mode() -> WeaponData.FireMode:
	if data == null or data.fire_modes.size() <= 1:
		return current_fire_mode
	var index := data.fire_modes.find(current_fire_mode)
	current_fire_mode = data.fire_modes[(index + 1) % data.fire_modes.size()]
	return current_fire_mode


## Abzug gedrueckt halten. Ruft je nach Modus einen oder mehrere Schuesse aus.
func try_fire(trigger_held: bool, trigger_just_pressed: bool) -> bool:
	if data == null or _cooldown > 0.0 or _burst_remaining > 0:
		return false

	match current_fire_mode:
		WeaponData.FireMode.AUTO:
			if not trigger_held:
				return false
		WeaponData.FireMode.BURST:
			if not trigger_just_pressed:
				return false
			_burst_remaining = data.burst_count - 1
		_:
			if not trigger_just_pressed:
				return false

	return _shoot()


func _shoot() -> bool:
	if rounds_in_magazine <= 0:
		_burst_remaining = 0
		_play(_dry_sound, 1.0)
		dry_fire.emit()
		return false

	rounds_in_magazine -= 1
	_cooldown = data.get_shot_interval()
	_shots_since_release += 1

	var speed := data.get_muzzle_velocity(loaded_ammo)
	var origin := _muzzle.global_position if _muzzle != null else global_position
	var base_dir := -(_muzzle.global_basis.z if _muzzle != null else global_basis.z)

	# Schrot verschiesst mehrere Projektile mit Streuung.
	for i in range(maxi(1, loaded_ammo.pellet_count)):
		var dir := _apply_spread(base_dir, i)
		_spawn_projectile(origin, dir, speed)

	_play_shot_feedback()
	_emit_recoil()
	fired.emit(loaded_ammo, rounds_in_magazine)
	return true


## Mündungsfeuer und Knall. Beides muss exakt im selben Frame kommen wie
## das Geschoss, sonst fühlt sich der Schuss "abgekoppelt" an.
func _play_shot_feedback() -> void:
	if _muzzle != null:
		var power := WeaponAudio.get_power_for_weapon(data)
		MuzzleFlash.spawn(get_spawn_parent(), _muzzle.global_transform, 0.6 + power)

	# Tonhöhe leicht variieren, damit Dauerfeuer nicht wie eine Maschine klingt.
	_play(_shot_sound, randf_range(0.94, 1.06))


func _play(stream: AudioStreamWAV, pitch: float) -> void:
	if _audio == null or stream == null:
		return
	_audio.stream = stream
	_audio.pitch_scale = pitch
	_audio.play()


## Streuung aus Waffenpraezision (MOA) und Munitionsstreuung (Schrot).
func _apply_spread(direction: Vector3, pellet_index: int) -> Vector3:
	# 1 MOA entspricht rund 1/60 Grad.
	var spread_deg := data.accuracy_moa / 60.0
	if loaded_ammo.pellet_count > 1 and pellet_index > 0:
		spread_deg += loaded_ammo.pellet_spread_degrees

	if spread_deg <= 0.0:
		return direction

	var angle := deg_to_rad(spread_deg)
	# Zufaellige Abweichung in einem Kegel um die Zielrichtung.
	var perpendicular := direction.cross(Vector3.UP)
	if perpendicular.length_squared() < 0.001:
		perpendicular = direction.cross(Vector3.RIGHT)
	perpendicular = perpendicular.normalized()

	var roll := randf() * TAU
	var axis := perpendicular.rotated(direction.normalized(), roll)
	return direction.rotated(axis, randf() * angle).normalized()


func _spawn_projectile(origin: Vector3, direction: Vector3, speed: float) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	# An den Baum haengen, nicht an die Waffe — sonst fliegt das Geschoss
	# mit, wenn sich der Spieler dreht.
	get_spawn_parent().add_child(projectile)
	projectile.launch(loaded_ammo, origin, direction, speed, owner, projectile_mask)


## Wohin Geschosse und Effekte gehaengt werden.
##
## current_scene ist null, sobald die Szene nicht als Hauptszene laeuft —
## etwa waehrend eines Szenenwechsels, im Test oder wenn spaeter mehrere
## Level gleichzeitig geladen sind. Deshalb mit Rueckfallebene statt blind
## darauf zu vertrauen.
func get_spawn_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return self
	if tree.current_scene != null:
		return tree.current_scene
	# Oberster Vorfahr unterhalb der Baumwurzel.
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != tree.root:
		node = node.get_parent()
	return node


## Rueckstoss. Waechst innerhalb einer Salve an, damit Dauerfeuer auf
## Distanz sinnlos wird und kurze Feuerstoesse belohnt werden.
func _emit_recoil() -> void:
	var ergonomics_factor := 1.0 - (float(data.ergonomics) / 200.0)
	var ramp := 1.0 + minf(float(_shots_since_release) * 0.06, 0.8)

	var vertical := data.recoil_vertical * ergonomics_factor * ramp * 0.01
	var horizontal := data.recoil_horizontal * ergonomics_factor * ramp * 0.01
	horizontal *= (1.0 if randf() < 0.5 else -1.0)

	recoil_kick.emit(vertical, horizontal)


## Abzug losgelassen — Rueckstossaufbau zuruecksetzen.
func release_trigger() -> void:
	_shots_since_release = 0


func reload() -> void:
	if data == null:
		return
	rounds_in_magazine = data.magazine_size
	_shots_since_release = 0
	_play(_reload_sound, 1.0)
	reloaded.emit(rounds_in_magazine)


func get_status_text() -> String:
	if data == null or loaded_ammo == null:
		return "keine Waffe"
	var mode_names := {
		WeaponData.FireMode.SINGLE: "Einzel",
		WeaponData.FireMode.BURST: "Stoss",
		WeaponData.FireMode.AUTO: "Auto",
	}
	return "%s  [%s]  %d/%d  %s" % [
		data.display_name,
		mode_names.get(current_fire_mode, "?"),
		rounds_in_magazine,
		data.magazine_size,
		loaded_ammo.display_name,
	]
