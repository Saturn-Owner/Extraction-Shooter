## Findet, womit der Spieler gerade interagieren kann, und führt es aus.
##
## Ein Strahl aus der Kameramitte sucht nach Objekten in Reichweite.
## Bewusst kurz gehalten: Wer looten will, muss wirklich hingehen und sich
## damit angreifbar machen.
##
## Das Durchsuchen bricht ab, sobald sich der Spieler zu weit entfernt.
## Sonst könnte man eine Kiste anfangen zu durchsuchen und währenddessen
## in Deckung rennen — das würde den Preis des Lootens aushebeln.
class_name PlayerInteraction
extends Node3D

signal target_changed(target: Node)
signal search_progress(ratio: float)

## Reichweite in Metern.
@export var reach: float = 2.2

## Ab dieser Entfernung bricht ein laufendes Durchsuchen ab.
@export var break_distance: float = 3.0

## Welche Kollisionsebenen durchsucht werden (1 = Welt, 8 = Interaktion).
@export_flags_3d_physics var interaction_mask: int = 1 | 8

var current_target: Node = null
var searching_container: LootContainer = null

@onready var _camera: Camera3D = get_parent().get_node_or_null("Camera3D")


func _physics_process(_delta: float) -> void:
	_update_target()
	_update_search()


func _update_target() -> void:
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


## Bricht ab, wenn der Spieler zu weit weg ist.
func _update_search() -> void:
	if searching_container == null:
		return

	if global_position.distance_to(searching_container.global_position) > break_distance:
		stop_search()
		return

	search_progress.emit(searching_container.get_search_progress())

	if not searching_container.is_being_searched:
		# Fertig durchsucht.
		search_progress.emit(1.0)
		searching_container = null


## Wird beim Druck auf die Interaktionstaste aufgerufen.
func interact() -> bool:
	if current_target is LootContainer:
		var container := current_target as LootContainer
		if container.is_searched:
			return true
		if container.begin_search():
			searching_container = container
			return true
	return false


func stop_search() -> void:
	if searching_container != null:
		searching_container.cancel_search()
		searching_container = null
		search_progress.emit(0.0)


## Text für die Anzeige am Bildschirmrand.
func get_prompt() -> String:
	if current_target is LootContainer:
		var container := current_target as LootContainer
		if container.is_searched:
			return "%s  [F] oeffnen" % container.display_name
		return "%s  [F] durchsuchen" % container.display_name
	return ""
