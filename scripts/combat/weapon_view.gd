## Das sichtbare Modell der Waffe in der Hand des Spielers.
##
## Diese Klasse enthaelt KEINE Spiellogik. Sie liest den Zustand der Waffe
## und stellt ihn dar. Ob geschossen werden darf, entscheidet weapon.gd —
## hier wird nur gezeigt, was passiert ist. Das ist wichtig fuer den spaeteren
## Multiplayer: Die Darstellung darf nie zur Quelle der Wahrheit werden.
##
## AUFBAU DER KNOTEN — jede Animationsart bekommt einen eigenen Knoten,
## damit sie sich nicht gegenseitig ueberschreiben:
##
##   WeaponView
##    └ Pose     Huefte <-> Zielen, Sprint-Wegklappen
##       └ Sway  Nachschwingen bei Mausbewegung, Laufwackeln
##          └ Recoil  Rueckstossfeder
##             └ Model  die eigentlichen Teile
##
## WAS HIER FEHLT: Haende und Arme. Die Waffe schwebt frei. Das ist fuer ein
## Blockout normal — sichtbare Haende brauchen Rigging und handgemachte
## Animationen, das kann Claude nicht liefern (siehe CLAUDE.md).
class_name WeaponView
extends Node3D

@export_group("Haltung")

## Ruheposition an der Huefte, leicht nach rechts versetzt.
@export var hip_position: Vector3 = Vector3(0.115, -0.125, -0.22)
@export var hip_rotation_degrees: Vector3 = Vector3(0.0, -3.5, 0.0)

## Wie weit die Waffe beim Sprinten weggeklappt wird.
@export var sprint_position: Vector3 = Vector3(0.16, -0.20, -0.16)
@export var sprint_rotation_degrees: Vector3 = Vector3(-26.0, 24.0, -14.0)

## Wie schnell zwischen den Haltungen gewechselt wird.
@export var pose_speed: float = 11.0

@export_group("Nachladehaltung")

## Beim Nachladen kippt die Waffe schraeg nach oben und dreht sich zum
## Spieler. Sonst passiert der ganze Magazinwechsel unten ausserhalb des
## Bildes und man sieht von der Animation praktisch nichts.
@export var reload_position: Vector3 = Vector3(0.075, -0.150, -0.235)

## Nach oben kippen (X), zur Mitte drehen (Y), zum Spieler rollen (Z).
## Das Rollen ist der wichtigste Teil — erst dadurch zeigt der
## Magazinschacht in Richtung Kamera.
@export var reload_rotation_degrees: Vector3 = Vector3(24.0, 17.0, -34.0)

## Anteil der Nachladezeit, in dem die Waffe hoch- bzw. wieder zurueckwandert.
@export_range(0.05, 0.45) var reload_pose_blend: float = 0.16

@export_group("Zielen")

## Sekunden von der Huefte bis die Visierlinie steht.
## Wird mit der Ergonomie der Waffe verrechnet — eine handliche Waffe
## kommt schneller ans Auge.
@export var ads_base_time: float = 0.26

@export_group("Nachschwingen")

## Wie stark die Waffe der Mausbewegung hinterherhaengt (Grad).
@export var sway_amount: float = 2.6

## Wie schnell sie wieder mittig steht.
@export var sway_return_speed: float = 7.0

## Wieviel Nachschwingen beim Zielen uebrig bleibt.
@export_range(0.0, 1.0) var sway_ads_factor: float = 0.25

@export_group("Laufwackeln")

@export var bob_speed: float = 8.5
@export var bob_amount: float = 0.016
@export_range(0.0, 1.0) var bob_ads_factor: float = 0.3

@export_group("Rueckstoss (sichtbar)")

## Wie weit die Waffe pro Schuss nach hinten geht (Meter).
@export var recoil_kick_back: float = 0.055

## Wie weit die Muendung hochspringt (Grad).
@export var recoil_kick_up: float = 3.4

## Federhaerte — hoch = schnappt schneller zurueck.
@export var recoil_stiffness: float = 190.0

## Daempfung — niedrig = schwingt nach.
@export var recoil_damping: float = 17.0

@export_group("Mechanik")

## Wie lange der Verschluss fuer einen Zyklus braucht.
@export var bolt_cycle_time: float = 0.055

## Wie weit der Verschluss zurueckfaehrt (Meter).
@export var bolt_travel: float = 0.075

var _weapon: Weapon

# Knoten der Animationsebenen
var _pose: Node3D
var _sway: Node3D
var _recoil: Node3D
var _model: Node3D

# Bewegliche Teile
var _bolt: Node3D
var _magazine: Node3D
var _trigger: Node3D
var _selector: Node3D
var _charging_handle: Node3D
var _muzzle_point: Node3D

# Ruhelagen der beweglichen Teile, damit wir immer dorthin zurueckkehren
var _bolt_home: Vector3
var _magazine_home: Vector3
var _charging_handle_home: Vector3

# Zustand von aussen
var _aiming: bool = false
var _sprinting: bool = false
var _speed_ratio: float = 0.0

# Laufende Animationswerte
var _aim_progress: float = 0.0
var _look_delta: Vector2 = Vector2.ZERO
var _sway_offset: Vector2 = Vector2.ZERO
var _bob_time: float = 0.0

var _recoil_offset: Vector3 = Vector3.ZERO
var _recoil_velocity: Vector3 = Vector3.ZERO
var _recoil_angle: float = 0.0
var _recoil_angular_velocity: float = 0.0

var _bolt_timer: float = 0.0
var _bolt_locked_back: bool = false
var _trigger_pull: float = 0.0

# Nachladen und Ladehemmung laufen als Zeitleiste von 1.0 auf 0.0
var _sequence_time_left: float = 0.0
var _sequence_duration: float = 0.0
var _sequence_kind: StringName = &""


func _ready() -> void:
	_build_hierarchy()


func _build_hierarchy() -> void:
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)

	_sway = Node3D.new()
	_sway.name = "Sway"
	_pose.add_child(_sway)

	_recoil = Node3D.new()
	_recoil.name = "Recoil"
	_sway.add_child(_recoil)

	_model = ViewmodelBuilder.build_ar15()
	_recoil.add_child(_model)

	_bolt = _model.get_node_or_null("Bolt") as Node3D
	_magazine = _model.get_node_or_null("Magazine") as Node3D
	_trigger = _model.get_node_or_null("Trigger") as Node3D
	_selector = _model.get_node_or_null("Selector") as Node3D
	_charging_handle = _model.get_node_or_null("ChargingHandle") as Node3D
	_muzzle_point = _model.get_node_or_null("MuzzlePoint") as Node3D

	if _bolt != null:
		_bolt_home = _bolt.position
	if _magazine != null:
		_magazine_home = _magazine.position
	if _charging_handle != null:
		_charging_handle_home = _charging_handle.position

	_pose.position = hip_position
	_pose.rotation_degrees = hip_rotation_degrees


## Waffe anmelden. Ab hier reagiert die Darstellung auf ihre Signale.
func attach_weapon(weapon: Weapon) -> void:
	if _weapon == weapon:
		return
	_weapon = weapon
	if _weapon == null:
		return

	_weapon.fired.connect(_on_fired)
	_weapon.dry_fire.connect(_on_dry_fire)
	_weapon.reload_started.connect(_on_reload_started)
	_weapon.reload_finished.connect(_on_reload_finished)
	_weapon.reload_cancelled.connect(_on_sequence_cancelled)
	_weapon.jammed.connect(_on_jammed)
	_weapon.unjam_started.connect(_on_unjam_started)
	_weapon.unjammed.connect(_on_unjammed)
	_weapon.fire_mode_changed.connect(_on_fire_mode_changed)

	_on_fire_mode_changed(_weapon.current_fire_mode)


## Wohin das Muendungsfeuer gehoert. Wandert mit dem Modell mit, damit der
## Blitz beim Zielen nicht neben der Waffe in der Luft haengt.
func get_muzzle_point() -> Node3D:
	return _muzzle_point


## Bewegungszustand vom PlayerController. Treibt Laufwackeln und Sprinthaltung.
func set_movement(speed_ratio: float, sprinting: bool) -> void:
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	_sprinting = sprinting


## Beim Sprinten wird nicht gezielt — das entscheidet der Controller.
func set_aiming(aiming: bool) -> void:
	_aiming = aiming


## Mausbewegung fuer das Nachschwingen. Kommt aus _unhandled_input des Controllers.
func add_look_delta(delta: Vector2) -> void:
	_look_delta += delta


## 0.0 = Huefte, 1.0 = im Ziel. Der Controller zieht daran das Sichtfeld.
func get_aim_progress() -> float:
	return _aim_progress


func _process(delta: float) -> void:
	_update_sequence(delta)
	_update_aim(delta)
	_update_pose(delta)
	_update_sway(delta)
	_update_bob(delta)
	_update_recoil(delta)
	_update_bolt(delta)
	_update_trigger(delta)


## Zielen ist eine reine Zeitinterpolation. Die Ergonomie der Waffe bestimmt
## das Tempo: eine handliche Waffe kommt spuerbar schneller ans Auge.
func _update_aim(delta: float) -> void:
	var wants_aim := _aiming and not _sprinting and _sequence_kind == &""

	var ergonomics := 50.0
	if _weapon != null and _weapon.data != null:
		ergonomics = float(_weapon.data.ergonomics)
	# Ergonomie 0 -> 1.4x langsamer, 100 -> 0.7x schneller.
	var duration := ads_base_time * (1.4 - 0.7 * (ergonomics / 100.0))
	var step := delta / maxf(0.01, duration)

	_aim_progress = clampf(_aim_progress + (step if wants_aim else -step), 0.0, 1.0)


## Wie stark die Nachladehaltung gerade wirkt.
## Faehrt am Anfang hoch und am Ende wieder herunter, damit der Uebergang
## nicht springt.
func _get_reload_pose_weight() -> float:
	if _sequence_time_left <= 0.0 or _sequence_duration <= 0.0:
		return 0.0
	var progress := 1.0 - _sequence_time_left / _sequence_duration
	var blend := clampf(reload_pose_blend, 0.05, 0.45)
	var rise := _ramp(progress, 0.0, blend)
	var fall := 1.0 - _ramp(progress, 1.0 - blend, 1.0)
	# Weiche Kurve statt Gerade — sonst wirkt das Anheben mechanisch.
	return smoothstep(0.0, 1.0, minf(rise, fall))


func _update_pose(delta: float) -> void:
	var target_pos := hip_position
	var target_rot := hip_rotation_degrees

	var reload_weight := _get_reload_pose_weight()
	if reload_weight > 0.0:
		# Nachladen schlaegt alles andere: Wer nachlaedt, zielt nicht.
		target_pos = target_pos.lerp(reload_position, reload_weight)
		target_rot = target_rot.lerp(reload_rotation_degrees, reload_weight)
		var reload_step := clampf(pose_speed * delta, 0.0, 1.0)
		_pose.position = _pose.position.lerp(target_pos, reload_step)
		_pose.rotation_degrees = _pose.rotation_degrees.lerp(target_rot, reload_step)
		return

	if _sprinting:
		target_pos = sprint_position
		target_rot = sprint_rotation_degrees
	elif _aim_progress > 0.0:
		# Zielpose: Die Visierlinie muss exakt auf der Kameramitte landen.
		# Deshalb wird das Modell genau um seine Visierhoehe abgesenkt und
		# seitlich mittig gestellt — nicht nach Gefuehl geschoben.
		var ads_pos := Vector3(0.0, -ViewmodelBuilder.SIGHT_HEIGHT, -0.16)
		target_pos = target_pos.lerp(ads_pos, _aim_progress)
		target_rot = target_rot.lerp(Vector3.ZERO, _aim_progress)

	var weight := clampf(pose_speed * delta, 0.0, 1.0)
	_pose.position = _pose.position.lerp(target_pos, weight)
	_pose.rotation_degrees = _pose.rotation_degrees.lerp(target_rot, weight)


## Die Waffe haengt der Blickrichtung hinterher. Ohne das klebt sie starr
## im Bild und wirkt wie aufgemalt.
func _update_sway(delta: float) -> void:
	var factor := lerpf(1.0, sway_ads_factor, _aim_progress)
	var target := Vector2(
		clampf(-_look_delta.x * 0.35, -sway_amount, sway_amount),
		clampf(-_look_delta.y * 0.35, -sway_amount, sway_amount)
	) * factor

	_sway_offset = _sway_offset.lerp(target, clampf(sway_return_speed * delta, 0.0, 1.0))
	_look_delta = _look_delta.lerp(Vector2.ZERO, clampf(12.0 * delta, 0.0, 1.0))

	_sway.rotation_degrees.y = _sway_offset.x
	_sway.rotation_degrees.x = -_sway_offset.y
	# Leichtes Kippen um die Laengsachse macht die Bewegung organischer.
	_sway.rotation_degrees.z = _sway_offset.x * 0.4


func _update_bob(delta: float) -> void:
	var factor := lerpf(1.0, bob_ads_factor, _aim_progress)
	if _speed_ratio <= 0.01:
		# Im Stehen sauber auslaufen lassen statt mitten im Ausschlag einfrieren.
		_sway.position = _sway.position.lerp(Vector3.ZERO, clampf(6.0 * delta, 0.0, 1.0))
		return

	_bob_time += delta * bob_speed * _speed_ratio
	var amount := bob_amount * _speed_ratio * factor
	var target := Vector3(
		sin(_bob_time) * amount,
		-absf(cos(_bob_time)) * amount * 0.8,
		0.0
	)
	_sway.position = _sway.position.lerp(target, clampf(10.0 * delta, 0.0, 1.0))


## Rueckstoss als echte Feder statt als fester Rueckweg. Dadurch schwingt
## die Waffe bei Dauerfeuer auf, statt jedes Mal sauber zurueckzukommen —
## genau das soll Dauerfeuer auf Distanz unattraktiv machen.
func _update_recoil(delta: float) -> void:
	var accel := -_recoil_offset * recoil_stiffness - _recoil_velocity * recoil_damping
	_recoil_velocity += accel * delta
	_recoil_offset += _recoil_velocity * delta

	var angular_accel := -_recoil_angle * recoil_stiffness - _recoil_angular_velocity * recoil_damping
	_recoil_angular_velocity += angular_accel * delta
	_recoil_angle += _recoil_angular_velocity * delta

	_recoil.position = _recoil_offset
	_recoil.rotation_degrees.x = _recoil_angle


## Verschluss: faehrt zurueck und schnappt vor. Bei leerem Magazin bleibt er
## hinten stehen — das ist die sichtbare Ansage "du musst nachladen".
func _update_bolt(delta: float) -> void:
	if _bolt == null:
		return

	if _bolt_timer > 0.0:
		_bolt_timer = maxf(0.0, _bolt_timer - delta)

	var travel := 0.0
	if _bolt_locked_back:
		travel = 1.0
	elif _bolt_timer > 0.0:
		# Sinus: hinten in der Mitte des Zyklus, vorn an beiden Enden.
		travel = sin((1.0 - _bolt_timer / bolt_cycle_time) * PI)

	_bolt.position = _bolt_home + Vector3(0.0, 0.0, travel * bolt_travel)


func _update_trigger(delta: float) -> void:
	if _trigger == null:
		return
	_trigger_pull = maxf(0.0, _trigger_pull - delta * 9.0)
	_trigger.rotation_degrees.x = -_trigger_pull * 14.0


## Zeitleiste fuer Nachladen und Ladehemmung. Beides bewegt dieselben Teile,
## nur in unterschiedlicher Reihenfolge.
func _update_sequence(delta: float) -> void:
	if _sequence_time_left <= 0.0:
		return

	_sequence_time_left = maxf(0.0, _sequence_time_left - delta)
	var progress := 1.0 - _sequence_time_left / maxf(0.01, _sequence_duration)

	match _sequence_kind:
		&"reload_tactical":
			_animate_magazine_swap(progress)
		&"reload_empty":
			_animate_magazine_swap(progress)
			# Zum Schluss den Verschluss vorlassen.
			if progress > 0.85:
				_pull_charging_handle(_ramp(progress, 0.85, 1.0))
			else:
				_pull_charging_handle(0.0)
		&"unjam":
			# Ladehemmung: kraeftig am Ladehebel reissen.
			_pull_charging_handle(sin(progress * PI))

	if _sequence_time_left <= 0.0:
		_sequence_kind = &""
		_pull_charging_handle(0.0)
		if _magazine != null:
			_magazine.position = _magazine_home
			_magazine.rotation_degrees = Vector3.ZERO
			_magazine.visible = true


## Magazin faellt raus, Pause, neues kommt rein.
func _animate_magazine_swap(progress: float) -> void:
	if _magazine == null:
		return

	if progress < 0.30:
		# Rausfallen: nach unten und leicht nach vorn kippen.
		var t := _ramp(progress, 0.0, 0.30)
		_magazine.visible = true
		_magazine.position = _magazine_home + Vector3(0.0, -0.34 * t, 0.02 * t)
		_magazine.rotation_degrees = Vector3(18.0 * t, 0.0, 6.0 * t)
	elif progress < 0.45:
		# Kurz gar kein Magazin — das macht den Wechsel lesbar.
		_magazine.visible = false
	else:
		# Neues Magazin von unten einfuehren.
		var t := _ramp(progress, 0.45, 0.85)
		_magazine.visible = true
		_magazine.position = _magazine_home + Vector3(0.0, -0.30 * (1.0 - t), 0.0)
		_magazine.rotation_degrees = Vector3(12.0 * (1.0 - t), 0.0, 0.0)


func _pull_charging_handle(amount: float) -> void:
	if _charging_handle == null:
		return
	_charging_handle.position = _charging_handle_home + Vector3(0.0, 0.0, amount * 0.075)


## Rechnet einen Abschnitt einer Zeitleiste auf 0..1 um.
static func _ramp(value: float, from: float, to: float) -> float:
	if to <= from:
		return 1.0
	return clampf((value - from) / (to - from), 0.0, 1.0)


# --- Reaktionen auf die Waffe ---

func _on_fired(_ammo: AmmoData, rounds_left: int) -> void:
	# Rueckstoss als Impuls auf die Federgeschwindigkeit, nicht als
	# Positionssprung — sonst ruckelt es statt zu kicken.
	var strength := 1.0
	if _weapon != null and _weapon.data != null:
		# Schwere Waffen kicken staerker, gute Ergonomie daempft.
		strength = _weapon.data.recoil_vertical / 120.0
		strength *= 1.0 - float(_weapon.data.ergonomics) / 250.0
	# Beim Zielen liegt die Waffe ruhiger an der Schulter.
	strength *= lerpf(1.0, 0.72, _aim_progress)

	_recoil_velocity.z += recoil_kick_back * strength * 26.0
	_recoil_velocity.y += recoil_kick_back * strength * 5.0
	_recoil_angular_velocity += recoil_kick_up * strength * 26.0

	_bolt_timer = bolt_cycle_time
	_bolt_locked_back = rounds_left <= 0 and not _has_chambered_round()
	_trigger_pull = 1.0


func _on_dry_fire() -> void:
	_trigger_pull = 1.0


func _on_reload_started(duration: float, from_empty: bool) -> void:
	_sequence_kind = &"reload_empty" if from_empty else &"reload_tactical"
	_sequence_duration = duration
	_sequence_time_left = duration


func _on_reload_finished(_rounds: int) -> void:
	_bolt_locked_back = false


func _on_sequence_cancelled() -> void:
	_sequence_time_left = 0.0
	_sequence_kind = &""
	_pull_charging_handle(0.0)
	if _magazine != null:
		_magazine.position = _magazine_home
		_magazine.rotation_degrees = Vector3.ZERO
		_magazine.visible = true


func _on_jammed() -> void:
	# Verschluss klemmt sichtbar auf halbem Weg.
	_bolt_locked_back = true


func _on_unjam_started(duration: float) -> void:
	_sequence_kind = &"unjam"
	_sequence_duration = duration
	_sequence_time_left = duration


func _on_unjammed() -> void:
	_bolt_locked_back = false


## Feuerwahlhebel dreht sich sichtbar mit — kleine Sache, aber man sieht
## sofort, in welchem Modus man steht, ohne aufs HUD zu schauen.
func _on_fire_mode_changed(mode: WeaponData.FireMode) -> void:
	if _selector == null:
		return
	match mode:
		WeaponData.FireMode.BURST:
			_selector.rotation_degrees.x = -45.0
		WeaponData.FireMode.AUTO:
			_selector.rotation_degrees.x = -90.0
		_:
			_selector.rotation_degrees.x = 0.0


func _has_chambered_round() -> bool:
	return _weapon != null and _weapon.round_chambered
