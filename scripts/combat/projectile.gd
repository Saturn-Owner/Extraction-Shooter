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

## Dicke der Leuchtspur in Metern. Bewusst duenn - eine dicke Spur sieht aus
## wie ein Laserstrahl, nicht wie eine Kugel.
const TRACER_WIDTH := 0.012

## Farbe der Leuchtspur. Blass und leicht warm, nicht signalrot.
const TRACER_COLOR := Color(1.0, 0.78, 0.42, 0.35)

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
	_build_tracer(speed)


## Leuchtspur. Sie zeigt, wohin die Kugel wirklich geht.
##
## ---------------------------------------------------------------------------
## WARUM SIE SO KURZ UND SCHWACH IST
##
## Eine helle, lange Spur an jedem Geschoss waere ein Verrat: Jeder Schuss
## wuerde die Stellung des Schuetzen quer ueber die Karte anzeigen. In einem
## Extraction-Shooter ist genau das eine Entscheidung, die der Spieler ueber
## seine Munition treffen soll - und nicht der Standard.
##
## Die Spur hier ist deshalb kurz und blass. Sie reicht, um die eigene
## Flugbahn und den Vorhalt auf Distanz zu sehen, taugt aber nicht dazu,
## einen Schuetzen auf 200 m zu orten.
##
## Die Laenge haengt an der Geschossgeschwindigkeit: Ein langsames
## Pistolengeschoss zieht einen kuerzeren Strich als ein schnelles
## Gewehrgeschoss, weil es pro Bild weniger Strecke macht.
func _build_tracer(speed: float) -> void:
	# Faktor so gewaehlt, dass ein Gewehrgeschoss (900 m/s) rund 1,6 m zieht
	# und ein Pistolengeschoss (350 m/s) gut ein halbes Meter. Mit dem
	# vorherigen Faktor lagen beide am oberen Anschlag und waren gleich lang -
	# der Unterschied zwischen den Kalibern war damit unsichtbar.
	var length := clampf(speed * 0.0018, 0.30, 1.80)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(TRACER_WIDTH, TRACER_WIDTH, length)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = TRACER_COLOR
	material.disable_receive_shadows = true
	# Nicht in den Tiefenpuffer schreiben, sonst schneidet die Spur sichtbare
	# Kanten in alles, was dahinter liegt.
	material.no_depth_test = false
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED

	var streak := MeshInstance3D.new()
	streak.name = "Leuchtspur"
	streak.mesh = mesh
	streak.material_override = material
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Nach hinten versetzt: Die Spur haengt der Kugel nach, sie laeuft ihr
	# nicht voraus.
	streak.position = Vector3(0.0, 0.0, length * 0.5)
	add_child(streak)


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
	var normal: Vector3 = hit.get("normal", -_velocity.normalized())
	var distance := _start_position.distance_to(point)

	var result := _apply_damage(collider, point, distance)
	_spawn_impact(point, normal, result)
	hit_something.emit(collider, point, result)
	queue_free()


## Der Einschlag zeigt auf einen Blick, was passiert ist:
##   gelbe Funken = Platte hat gehalten
##   orange       = Platte durchschlagen
##   rot          = ungeschuetzt getroffen
##   hell         = Wand oder Boden
func _spawn_impact(point: Vector3, normal: Vector3, result: Ballistics.HitResult) -> void:
	# Der Einschlag darf nicht an das Geschoss gehaengt werden — das wird
	# im selben Moment entfernt und nimmt den Effekt sonst mit.
	var scene: Node = get_parent()
	if scene == null:
		return

	var kind := ImpactEffect.Kind.WORLD
	if result.was_armored:
		kind = ImpactEffect.Kind.ARMOR_PENETRATED if result.penetrated else ImpactEffect.Kind.ARMOR_STOPPED
	elif result.damage_to_target > 0.0:
		kind = ImpactEffect.Kind.FLESH

	ImpactEffect.spawn(scene, point, normal, kind)

	# Ein Loch bleibt nur, wo etwas Festes getroffen wurde. In Fleisch waere
	# es falsch, und auf einer Platte hinterlaesst eine abgefangene Kugel
	# eine Delle, kein Durchschussloch - beides zeigen schon die Funken.
	if kind == ImpactEffect.Kind.WORLD:
		BulletHole.spawn(scene, point, normal)


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
