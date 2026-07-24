## Ein einzelner Blutstropfen, der sich von der letzten Stelle des Koerpers
## geloest hat (siehe WoundBleed._release_drop()) und zu Boden faellt. Landet
## er auf etwas Festem, bleibt dort ein kleiner Fleck zurueck (dieselbe
## Wunden-Textur wie WoundHole, nur kleiner).
##
## HAENGT ALS KIND AM SELBEN MESH WIE DER STREIFEN, DER IHN LOESTE — bewegt
## und dreht sich also mit dem Koerperteil mit, waehrend er GLEICHZEITIG
## jedes Bild ein Stueck in Weltraum-Richtung nach unten faellt (siehe
## _process()). So sieht es aus, als tropfe er am bewegten/fallenden Koerper
## herunter, statt an der Weltstelle haengenzubleiben, an der die Figur beim
## Ablösen gerade stand.
##
## KEIN RigidBody3D: Ein Tropfen soll nicht rollen, abprallen oder mit
## anderen Koerpern kollidieren — nur geradlinig fallen und beim ersten
## Kontakt verschwinden. Ein Strahl pro Bild reicht dafuer, genau wie
## Projectile._check_segment() die eigene Flugstrecke prueft.
class_name BloodDrop
extends Node3D

## Spanne fuer den Radius eines einzelnen Tropfens — JEDER Tropfen wuerfelt
## sich seine eigene Groesse in dieser Spanne aus (siehe _ready()), damit
## nicht jeder Tropfen derselben Wunde gleich aussieht. War 0.016/0.034.
const RADIUS_MIN := 0.02
const RADIUS_MAX := 0.045

## Fallbeschleunigung — dieselbe wie bei RigidBody3D-Standardschwerkraft,
## damit ein Tropfen nicht spuerbar anders faellt als die Ragdoll-Kaesten.
const GRAVITY := 9.8

## Gibt auf, wenn er so lange faellt, ohne etwas zu treffen (z. B. eine
## haengende Figur ohne Boden in Reichweite) — sonst faellt ein Tropfen ewig
## unsichtbar weiter und haeuft sich im Knotenbaum an.
const MAX_FALL_TIME := 3.0

## Faktor vom Tropfenradius zur Groesse seines Leflecks — ein grosser Tropfen
## soll auch einen entsprechend groesseren Fleck hinterlassen, kein fester
## Wert unabhaengig davon, wie gross der Tropfen selbst gerade ausgefallen ist.
## War 2.6 — deutlich hochgesetzt, der Fleck war kaum zu erkennen.
const LANDING_MARK_PER_RADIUS := 5.0

## Von aussen gesetzt (siehe WoundBleed._release_drop()) — Welt UND die
## Trefferzonen-Ebene der eigenen Figur, damit ein Tropfen auf einem
## darunterliegenden Koerperteil landen kann statt hindurchzufallen.
var collision_mask: int = 1

var _radius: float
var _fall_speed: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	_radius = randf_range(RADIUS_MIN, RADIUS_MAX)

	var sphere := SphereMesh.new()
	sphere.radius = _radius
	sphere.height = _radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4

	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = WoundBleed.liquid_material()
	add_child(mesh)


func _process(delta: float) -> void:
	_age += delta
	if _age > MAX_FALL_TIME:
		queue_free()
		return

	_fall_speed += GRAVITY * delta
	var step := _fall_speed * delta

	var space := get_world_3d().direct_space_state
	if space == null:
		queue_free()
		return

	var from := global_position
	var to := from + Vector3.DOWN * step
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	query.collide_with_areas = false

	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		_land(hit.position, hit.get("normal", Vector3.UP), hit.get("collider"))
		return

	global_position = to


## Setzt den Landefleck — auf ein anderes Koerperteil derselben Figur direkt
## dorthin gehaengt (folgt dann dessen Bewegung mit), sonst an die Szene.
func _land(point: Vector3, normal: Vector3, collider: Object) -> void:
	var parent: Node = get_tree().current_scene
	var owner_character: BlockyCharacter = null

	if collider is CharacterHitbox:
		var hitbox := collider as CharacterHitbox
		if hitbox.character != null:
			var meshes := hitbox.character.meshes_of(hitbox.part)
			if not meshes.is_empty():
				parent = meshes[0]
				owner_character = hitbox.character

	if parent != null:
		var mark := WoundHole.spawn(parent, point, normal)
		if mark != null:
			var mark_size := _radius * LANDING_MARK_PER_RADIUS
			mark.size = Vector3(mark_size, mark.size.y, mark_size)
			# Landet der Tropfen auf der EIGENEN Figur (nicht am Boden), muss
			# clear_blood() ihn beim Zuruecksetzen wiederfinden — sonst
			# bleibt genau dieser eine Fleck kleben.
			if owner_character != null:
				owner_character.remember_wound_mark(mark)

	queue_free()
