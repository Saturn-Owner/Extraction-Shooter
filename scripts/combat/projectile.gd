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

## Wie weit das Geschoss sichtbar bleibt, in Metern.
##
## ---------------------------------------------------------------------------
## WARUM MAN EINE KUGEL NICHT DEN LAUF VERLASSEN SIEHT
##
## Ein Gewehrgeschoss fliegt 900 m/s. Bei 60 Bildern je Sekunde sind das
## 15 METER PRO BILD. Im ersten Bild, das die Grafikkarte ueberhaupt zeichnet,
## ist es also laengst 15 m entfernt — und dort liegt die Ziellinie praktisch
## auf der Bildmitte. Genau deshalb sah es vorher so aus, als kaeme die Kugel
## mitten aus dem Bildschirm: Am Lauf war sie nur in einem Moment, den niemand
## je zu sehen bekommt.
##
## Deshalb wird nicht das Geschoss gezeichnet, sondern die STRECKE zwischen
## Muendung und aktueller Position. Damit beginnt der Strich sichtbar am Lauf.
##
## Der Strich verblasst ueber ZEIT, nicht ueber Strecke.
##
## Erster Versuch war eine Hoechstentfernung von 22 m. Das war rechnerisch
## richtig und praktisch unsichtbar: 22 m sind bei 900 m/s ganze 24
## Millisekunden, also EIN Bild. Man sah nichts.
##
## Ueber Zeit gerechnet bleibt der Strich ein paar Bilder stehen und blendet
## aus — lang genug, um den Abgang zu sehen, kurz genug, um keine Leuchtspur
## quer ueber die Karte zu ziehen.
const STREAK_SECONDS := 0.13

## Wie lang der Strich hoechstens wird.
##
## Ohne Deckel spannte er bis zum Geschoss, und das ist nach einem Bild
## fuenfzehn Meter weit weg — dann zeigt er die Flugbahn statt des Abgangs.
const STREAK_MAX_LENGTH := 7.0

## Dicke des Strichs. Duenn, sonst sieht es nach Laserstrahl aus.
const STREAK_WIDTH := 0.05

const STREAK_COLOR := Color(1.0, 0.84, 0.45)

var _streak: MeshInstance3D
var _streak_material: StandardMaterial3D
var _streak_age: float = 0.0

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
	_build_streak()


## Der sichtbare Strich. Ein Quader der Laenge eins, damit sich die Streckung
## spaeter direkt aus der Entfernung ergibt.
func _build_streak() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(STREAK_WIDTH, STREAK_WIDTH, 1.0)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(STREAK_COLOR.r, STREAK_COLOR.g, STREAK_COLOR.b, 0.9)
	mesh.material = material
	_streak_material = material

	_streak = MeshInstance3D.new()
	_streak.name = "Abgang"
	_streak.mesh = mesh
	_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# NICHT als Kind haengen lassen: Der Strich spannt zwischen zwei Punkten in
	# der WELT auf. Als Kind wuerde er sich mit dem Geschoss mitbewegen und
	# muesste jedes Bild zurueckgerechnet werden.
	_streak.top_level = true
	add_child(_streak)


## Spannt den Strich von der Muendung nach vorn und blendet ihn aus.
##
## Verankert an der MUENDUNG, nicht am Geschoss: Genau darum ging es — man
## soll sehen, dass der Schuss dort herauskommt.
func _update_streak(delta: float) -> void:
	if _streak == null:
		return

	_streak_age += delta
	if _streak_age >= STREAK_SECONDS:
		_streak.visible = false
		return

	var direction := _velocity.normalized()
	var length := minf(_distance_travelled, STREAK_MAX_LENGTH)
	if length < 0.05 or direction.length_squared() < 0.01:
		_streak.visible = false
		return

	_streak.visible = true
	_streak.global_position = _start_position + direction * length * 0.5

	# look_at bricht ab, wenn die Richtung parallel zur Hochachse liegt —
	# beim Schuss senkrecht nach oben.
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	_streak.look_at(_start_position + direction * length, up)
	_streak.scale = Vector3(1.0, 1.0, length)

	# Ausblenden statt schlagartig verschwinden.
	var fade := 1.0 - _streak_age / STREAK_SECONDS
	_streak_material.albedo_color.a = 0.9 * fade * fade


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
	_update_streak(delta)

	# Bewusst KEINE Ausrichtung an der Flugrichtung mehr: Das Geschoss ist
	# unsichtbar, seit die Leuchtspur raus ist. Ein look_at pro Geschoss und
	# Bild fuer nichts summiert sich, sobald mehrere Waffen feuern. Kommt
	# spaeter ein sichtbares Geschossmodell dazu, gehoert es wieder her.


## Alle Koerper, die zum Schuetzen gehoeren — er selbst UND seine Trefferzonen.
##
## ---------------------------------------------------------------------------
## WARUM NICHT NUR DER SCHUETZE
##
## Hier stand `query.exclude = [shooter.get_rid()]`, also genau EIN Koerper.
## Solange der Spieler nur eine Kollisionskapsel ohne sichtbaren Leib hatte,
## genuegte das.
##
## Mit einem Koerper genuegt es nicht mehr: Die Trefferzonen sind eigene
## `CharacterHitbox`-Knoten und damit eigene Koerper. Der Lauf sitzt zwischen
## den Haenden, also VOR der Brust — jeder Schuss haette zuerst den eigenen
## Arm oder die eigene Brust getroffen. Das Spiel waere unspielbar gewesen,
## und zwar sofort beim ersten Schuss.
##
## Die Warnung dazu stand seit dem Bau der Figur in blocky_character.gd. Hier
## wird sie eingeloest.
func _shooter_bodies() -> Array[RID]:
	var bodies: Array[RID] = []
	if shooter == null:
		return bodies
	if shooter is CollisionObject3D:
		bodies.append((shooter as CollisionObject3D).get_rid())
	for node in _descendants(shooter):
		if node is CollisionObject3D:
			bodies.append((node as CollisionObject3D).get_rid())
	return bodies


static func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


## Prueft die gesamte Flugstrecke dieses Frames, nicht nur den Endpunkt.
func _check_segment(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _collision_mask
	query.collide_with_areas = false
	query.exclude = _shooter_bodies()

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
