## Findet, womit der Spieler gerade interagieren kann.
##
## Ein Strahl aus der Kameramitte sucht nach Objekten in Reichweite.
## Bewusst kurz gehalten: Wer looten will, muss wirklich hingehen und sich
## damit angreifbar machen.
##
## Diese Klasse ENTSCHEIDET nichts — sie meldet nur, was anvisiert wird.
## Das Öffnen und Durchsuchen läuft über das Loot-Fenster, damit die
## Interaktion nicht wissen muss, wie Kisten funktionieren.
class_name PlayerInteraction
extends Node3D

signal target_changed(target: Node)

## Reichweite in Metern.
@export var reach: float = 2.4

## Welche Kollisionsebenen durchsucht werden (1 = Welt, 8 = Interaktion).
@export_flags_3d_physics var interaction_mask: int = 1 | 8

var current_target: Node = null

@onready var _camera: Camera3D = get_parent().get_node_or_null("Camera3D")


func _physics_process(_delta: float) -> void:
	var found := _raycast_forward()
	if found == current_target:
		return
	current_target = found
	target_changed.emit(current_target)


func _raycast_forward() -> Node:
	if _camera == null:
		return null

	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var to := from - _camera.global_basis.z * reach

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = interaction_mask
	query.collide_with_areas = false

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null

	var collider: Node = hit.get("collider")
	if collider is LootContainer:
		return collider
	return null


## Text für die Anzeige in der Bildschirmmitte.
func get_prompt() -> String:
	if current_target is LootContainer:
		var container := current_target as LootContainer
		if container.is_fully_searched:
			return "%s  [F] oeffnen" % container.display_name
		if container.is_open:
			return "%s  [F] weiter durchsuchen" % container.display_name
		return "%s  [F] durchsuchen" % container.display_name
	return ""
