## Ein fliegendes Geschoss mit echter Flugzeit, Fallkurve und Luftwiderstand.
##
## WARUM KEIN HITSCAN:
## Bei Hitscan trifft man sofort, wo man hinzielt. Auf 300 m Entfernung ist
## das unrealistisch und macht Kaliberunterschiede bedeutungslos. Mit echten
## Projektilen muss der Spieler auf Distanz vorhalten, langsame Munition ist
## spuerbar traeger, und Durchschlagskraft nimmt mit der Entfernung ab.
##
## WARUM KEIN COLLISION-BODY:
## Ein Geschoss mit 900 m/s legt bei 60 Bildern pro Sekunde 15 Meter pro
## Frame zurueck. Ein normaler Kollisionskoerper wuerde durch jede Wand
## springen ("Tunneling"). Deshalb prueft dieses Geschoss stattdessen jeden
## Frame die STRECKE zwischen alter und neuer Position per Raycast.
##
## NETZWERK: Geschosse werden spaeter auf dem Server berechnet. Der Client
## sieht nur eine Spur zur Rueckmeldung — ueber Treffer entscheidet er nie.
class_name Projectile
extends Node3D

signal hit_something(collider: Node, point: Vector3, result: Ballistics.HitResult)
signal expired()

## Nach dieser Zeit verschwindet das Geschoss, damit nichts ewig weiterfliegt.
const MAX_LIFETIME := 8.0

## Ab dieser Geschwindigkeit ist das Geschoss wirkungslos.
const MIN_VELOCITY := 40.0

var ammo: AmmoData
var shooter: Node = null

var _velocity: Vector3 = Vector3.ZERO
var _start_position: Vector3 = Vector3.ZERO
var _distance_travelled: float = 0.0
var _lifetime: float = 0.0
var _collision_mask: int = 1


## Startet das Geschoss. Muss direkt nach dem Einfuegen in den Baum
## aufgerufen werden.
func launch(p_ammo: AmmoData, from: Vector3, direction: Vector3, speed: float,
		p_shooter: Node = null, p_mask: int = 1) -> void:
	ammo = p_ammo
	shooter = p_shooter
	_collision_mask = p_mask
	global_position = from
	_start_position = from
	_velocity = direction.normalized() * speed


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME or _velocity.length() < MIN_VELOCITY:
		expired.emit()
		queue_free()
		return

	var from := global_position

	# Schwerkraft sorgt fuer die Fallkurve — auf Distanz muss vorgehalten werden.
	_velocity += Vector3(0, -9.81, 0) * delta

	# Luftwiderstand. Ein hoher ballistischer Koeffizient bremst weniger.
	if ammo != null:
		var drag := 0.0012 / maxf(0.05, ammo.ballistic_coefficient)
		_velocity *= exp(-drag * _velocity.length() * delta)

	var to := from + _velocity * delta
	_check_segment(from, to)

	global_position = to
	_distance_travelled = _start_position.distance_to(to)

	# Ausrichtung an der Flugrichtung — fuer Leuchtspuren und Modelle.
	if _velocity.length_squared() > 0.01:
		look_at(to + _velocity, Vector3.UP)


## Prueft die gesamte Flugstrecke dieses Frames, nicht nur den Endpunkt.
func _check_segment(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _collision_mask
	query.collide_with_areas = false
	if shooter is CollisionObject3D:
		query.exclude = [(shooter as CollisionObject3D).get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	var collider: Node = hit.get("collider")
	var point: Vector3 = hit.get("position", to)
	var distance := _start_position.distance_to(point)

	var result := _apply_damage(collider, point, distance)
	hit_something.emit(collider, point, result)
	queue_free()


## Reicht den Treffer an das Ziel weiter, falls es Schaden nehmen kann.
func _apply_damage(collider: Node, point: Vector3, distance: float) -> Ballistics.HitResult:
	if collider != null and collider.has_method("take_hit"):
		return collider.take_hit(ammo, distance, point, global_position.direction_to(point))

	# Wand, Boden oder sonst etwas Unbelebtes.
	var result := Ballistics.HitResult.new()
	result.damage_to_target = 0.0
	return result


func get_distance_travelled() -> float:
	return _distance_travelled


func get_current_speed() -> float:
	return _velocity.length()
