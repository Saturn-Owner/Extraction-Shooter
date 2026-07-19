## First-Person-Steuerung der Spielerfigur.
##
## Bewegungsgefühl bewusst "schwer und bedacht" (Tarkov/Arma), nicht flott:
## Die Figur beschleunigt und bremst spürbar, statt sofort auf Tempo zu sein.
## Jede Bewegung soll sich nach einer Entscheidung anfühlen, nicht nach einem
## Reflex — das trägt später das Survival-Gefühl.
##
## Drei Dinge bremsen den Spieler, und alle sollen sich unterscheidbar anfühlen:
##   1. Getragenes Gewicht (Inventar)
##   2. Erschöpfung (Ausdauer leer)
##   3. Haltung (geduckt)
##
## HINWEIS ZUM NETZWERK: Diese Klasse bewegt den lokalen Spieler und ist damit
## bewusst client-seitig. Sobald Multiplayer dazukommt, muss der Server jede
## Position gegenprüfen (Plausibilitätscheck gegen die hier definierten
## Höchstgeschwindigkeiten), sonst kann ein Client beliebig schnell laufen.
class_name PlayerController
extends CharacterBody3D

signal stamina_changed(current: float, maximum: float)
signal exhausted()

@export_group("Tempo (Meter pro Sekunde)")

## Normales Gehen. Bewusst langsam — das ist die Standardgeschwindigkeit,
## in der der Spieler die meiste Zeit unterwegs ist.
@export var walk_speed: float = 2.4

## Sprint. Kostet Ausdauer und macht laut.
@export var sprint_speed: float = 5.2

## Geduckt. Langsam, aber leise und schwerer zu treffen.
@export var crouch_speed: float = 1.2

@export_group("Trägheit")

## Wie schnell die Figur auf Tempo kommt. Niedrig = schwerfällig.
@export var acceleration: float = 8.0

## Wie schnell sie zum Stehen kommt.
@export var deceleration: float = 10.0

## Bewegungskontrolle in der Luft (0 = gar keine).
@export_range(0.0, 1.0) var air_control: float = 0.15

@export var jump_velocity: float = 4.0

@export_group("Kamera")

@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.15

## Wie weit hoch und runter geschaut werden darf (Grad).
@export var pitch_limit_degrees: float = 89.0

## Augenhöhe im Stehen und im Ducken.
@export var stand_eye_height: float = 1.65
@export var crouch_eye_height: float = 0.95

@export_group("Ausdauer")

@export var max_stamina: float = 100.0

## Verbrauch pro Sekunde beim Sprinten.
@export var stamina_drain_per_second: float = 14.0

## Erholung pro Sekunde, wenn nicht gesprintet wird.
@export var stamina_regen_per_second: float = 9.0

## Pause vor Beginn der Erholung. Verhindert Dauersprint mit Mikropausen.
@export var stamina_regen_delay: float = 1.4

@export_group("Traglast")

## Gewicht, ab dem der Spieler langsamer wird.
## Bewusst niedrig: Man soll schon eine halbe Ausrüstung spüren, nicht erst
## einen vollen Rucksack. Ein Gewehr allein wiegt bereits 3.1 kg.
@export var comfortable_weight_kg: float = 6.0

## Gewicht, ab dem kaum noch Bewegung möglich ist.
@export var max_weight_kg: float = 40.0

## Wie stark Überladung bremst (1.0 = bis zum Stillstand bei max_weight_kg).
@export_range(0.0, 1.0) var weight_slowdown: float = 0.55

## Tempo-Bonus mit komplett leerem Inventar.
## Ohne diesen Bonus gäbe es nur Strafe und nie Belohnung — leicht zu reisen
## soll sich aktiv gut anfühlen, nicht bloss "nicht schlecht".
@export_range(0.0, 0.5) var unencumbered_bonus: float = 0.18

## Wie früh die Bremse zubeisst. Kleiner als 1.0 = die ersten Kilos über der
## Komfortgrenze wirken schon deutlich, statt dass erst die letzten wehtun.
@export_range(0.3, 2.0) var weight_curve: float = 0.7

## Aktuell getragenes Gewicht. Wird später vom Inventar gesetzt:
##   player.carried_weight_kg = inventory.get_total_weight()
var carried_weight_kg: float = 0.0

var stamina: float = 100.0
var is_crouching: bool = false
var is_sprinting: bool = false

var _pitch: float = 0.0
var _time_since_sprint: float = 0.0
var _was_exhausted: bool = false

## Rückstoß, der noch auf die Kamera wirkt, und was davon zurückfedert.
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0

## Wie schnell die Waffe nach dem Rückstoß wieder ins Ziel kommt.
@export_group("Rückstoß")
@export var recoil_recovery_speed: float = 6.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var weapon: Weapon = $CameraPivot/Weapon


## Wird von der Levelszene gesetzt, damit die Waffe das Fadenkreuz
## ansteuern kann. Bleibt null, wenn kein HUD vorhanden ist.
var crosshair: Crosshair = null


func _ready() -> void:
	stamina = max_stamina
	_capture_mouse(true)
	if weapon != null:
		weapon.recoil_kick.connect(_on_recoil_kick)
		weapon.fired.connect(_on_weapon_fired)


## Das Fadenkreuz geht bei jedem Schuss auf — proportional zum Rückstoss.
## Dadurch sieht der Spieler, dass Dauerfeuer ungenau wird.
func _on_weapon_fired(_ammo: AmmoData, _rounds_left: int) -> void:
	if crosshair == null or weapon == null or weapon.data == null:
		return
	crosshair.add_bloom(weapon.data.recoil_vertical * 0.055)


## Rückstoß hebt die Kamera an. Der Aufschlag ist sofort, die Erholung
## langsam — dadurch muss der Spieler bei Dauerfeuer gegenhalten.
func _on_recoil_kick(vertical: float, horizontal: float) -> void:
	_recoil_pitch += vertical
	_recoil_yaw += horizontal


func _update_recoil(delta: float) -> void:
	if is_zero_approx(_recoil_pitch) and is_zero_approx(_recoil_yaw):
		return

	var recovered_pitch := move_toward(_recoil_pitch, 0.0, recoil_recovery_speed * delta * maxf(1.0, absf(_recoil_pitch)))
	var recovered_yaw := move_toward(_recoil_yaw, 0.0, recoil_recovery_speed * delta * maxf(1.0, absf(_recoil_yaw)))

	# Nur die Differenz anwenden, sonst driftet die Blickrichtung weg.
	_pitch += _recoil_pitch - recovered_pitch
	rotate_y(deg_to_rad(-(_recoil_yaw - recovered_yaw)))

	_recoil_pitch = recovered_pitch
	_recoil_yaw = recovered_yaw
	_pitch = clampf(_pitch, -pitch_limit_degrees, pitch_limit_degrees)
	_camera_pivot.rotation_degrees.x = _pitch


func _handle_weapon_input() -> void:
	if weapon == null:
		return

	if Input.is_action_just_pressed("fire_mode"):
		weapon.cycle_fire_mode()
	if Input.is_action_just_pressed("reload"):
		weapon.reload()
	if Input.is_action_just_released("fire"):
		weapon.release_trigger()

	# Sprinten und Schiessen schliessen sich aus — die Waffe ist weggeklappt.
	if is_sprinting:
		return

	weapon.try_fire(
		Input.is_action_pressed("fire"),
		Input.is_action_just_pressed("fire")
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# Waagerecht dreht die ganze Figur, senkrecht nur den Kopf.
		rotate_y(deg_to_rad(-motion.relative.x * mouse_sensitivity))
		_pitch = clampf(
			_pitch - motion.relative.y * mouse_sensitivity,
			-pitch_limit_degrees,
			pitch_limit_degrees
		)
		_camera_pivot.rotation_degrees.x = _pitch

	if event.is_action_pressed("toggle_mouse"):
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)


func _capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	_update_crouch(delta)
	_update_stamina(delta)
	_update_movement(delta)
	_update_recoil(delta)
	_handle_weapon_input()
	move_and_slide()


func _update_crouch(delta: float) -> void:
	is_crouching = Input.is_action_pressed("crouch") and is_on_floor()
	var target_height := crouch_eye_height if is_crouching else stand_eye_height
	# Weich statt sprunghaft — sonst wirkt das Ducken wie ein Teleport.
	_camera_pivot.position.y = move_toward(_camera_pivot.position.y, target_height, 6.0 * delta)

	var shape := _collision.shape as CapsuleShape3D
	if shape != null:
		var target_shape_height := 1.2 if is_crouching else 1.8
		shape.height = move_toward(shape.height, target_shape_height, 4.0 * delta)


func _update_stamina(delta: float) -> void:
	if is_sprinting:
		stamina = maxf(0.0, stamina - stamina_drain_per_second * delta)
		_time_since_sprint = 0.0
	else:
		_time_since_sprint += delta
		if _time_since_sprint >= stamina_regen_delay:
			stamina = minf(max_stamina, stamina + stamina_regen_per_second * delta)

	stamina_changed.emit(stamina, max_stamina)

	# Nur einmal melden, nicht in jedem Frame.
	if stamina <= 0.0 and not _was_exhausted:
		_was_exhausted = true
		exhausted.emit()
	elif stamina > max_stamina * 0.2:
		_was_exhausted = false


## Wie stark die Traglast das Tempo verändert.
##
##   ueber 1.0 = leicht unterwegs, schneller als normal
##   genau 1.0 = an der Komfortgrenze
##   unter 1.0 = überladen, langsamer
##
## Beispielwerte mit den Standardeinstellungen:
##   0 kg -> 1.18    6 kg -> 1.00    12 kg -> 0.84    24 kg -> 0.66    40 kg -> 0.45
func get_weight_factor() -> float:
	if carried_weight_kg <= comfortable_weight_kg:
		# Bonus läuft von voll (leeres Inventar) auf null (Komfortgrenze) aus.
		var light_ratio := carried_weight_kg / maxf(0.01, comfortable_weight_kg)
		return 1.0 + unencumbered_bonus * (1.0 - clampf(light_ratio, 0.0, 1.0))

	var over := carried_weight_kg - comfortable_weight_kg
	var span := maxf(1.0, max_weight_kg - comfortable_weight_kg)
	var ratio := clampf(over / span, 0.0, 1.0)
	# Kurve < 1.0 zieht kleine Werte nach oben: die ersten Kilos wirken stärker.
	var curved := pow(ratio, weight_curve)
	return 1.0 - curved * weight_slowdown


## Ob gerade gesprintet werden darf.
## Bewusst restriktiv: nicht rückwärts, nicht geduckt, nicht ohne Ausdauer,
## nicht hoffnungslos überladen.
func can_sprint(input_dir: Vector2) -> bool:
	if is_crouching or not is_on_floor():
		return false
	if stamina <= 0.0:
		return false
	if carried_weight_kg >= max_weight_kg:
		return false
	return input_dir.y < -0.1


func get_current_max_speed() -> float:
	var base := walk_speed
	if is_crouching:
		base = crouch_speed
	elif is_sprinting:
		base = sprint_speed
	return base * get_weight_factor()


func _update_movement(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_sprinting = Input.is_action_pressed("sprint") and can_sprint(input_dir)

	if Input.is_action_just_pressed("jump") and is_on_floor() and stamina > 10.0:
		velocity.y = jump_velocity
		stamina = maxf(0.0, stamina - 8.0)

	# Eingaberichtung in Weltkoordinaten umrechnen.
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := get_current_max_speed()
	var control := 1.0 if is_on_floor() else air_control

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() > 0.01:
		var target := direction * speed
		horizontal = horizontal.move_toward(target, acceleration * control * delta * speed)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, deceleration * control * delta * speed)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
