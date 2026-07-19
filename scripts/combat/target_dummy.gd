## Zielscheibe zum Testen der Ballistik.
##
## Kann optional eine Schutzplatte tragen. Damit laesst sich im Spiel direkt
## vergleichen, was dieselbe Munition gegen ungeschuetzte und gepanzerte
## Ziele anrichtet — der Kern eures Ruestungssystems, zum Anfassen.
##
## Das ist ein Testobjekt, kein Gegner. Die richtige KI kommt spaeter.
class_name TargetDummy
extends StaticBody3D

signal was_hit(result: Ballistics.HitResult, total_hits: int)
signal destroyed()

@export var max_health: float = 100.0

## Leer lassen fuer eine ungeschuetzte Zielscheibe.
@export var plate_id: StringName = &""

## Beschriftung ueber der Scheibe.
@export var label_text: String = "Ziel"

var health: float
var plate: ArmorPlateData
var plate_durability: float = 0.0
var hit_count: int = 0

var _rng := RandomNumberGenerator.new()

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $Label3D


func _ready() -> void:
	health = max_health
	_rng.randomize()

	if plate_id != &"":
		ItemRegistry.ensure_loaded()
		var res := ItemRegistry.get_item(plate_id)
		if res is ArmorPlateData:
			plate = res as ArmorPlateData
			plate_durability = plate.max_durability
		else:
			push_warning("[TargetDummy] Unbekannte Platte: %s" % plate_id)

	_update_visuals()


## Wird vom Geschoss aufgerufen. Der Rueckgabewert beschreibt den Treffer.
func take_hit(ammo: AmmoData, distance: float, _point: Vector3, _direction: Vector3) -> Ballistics.HitResult:
	# Unterstrich im Parameternamen, weil Godot sonst warnt — die Position
	# brauchen wir aber für die Schadenszahl.
	var result := Ballistics.resolve_hit(ammo, distance, plate, plate_durability, _rng)

	plate_durability = maxf(0.0, plate_durability - result.damage_to_armor)
	health = maxf(0.0, health - result.damage_to_target)
	hit_count += 1

	_update_visuals()

	# Schadenszahl leicht versetzt, damit mehrere Treffer nicht übereinander
	# liegen und unlesbar werden.
	var offset := Vector3(randf_range(-0.15, 0.15), randf_range(0.0, 0.3), 0.0)
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if parent != null:
		DamageNumber.spawn(parent, _point + offset, result)

	was_hit.emit(result, hit_count)

	if health <= 0.0:
		destroyed.emit()

	return result


## Zuruecksetzen, damit man ohne Neustart weitertesten kann.
func reset() -> void:
	health = max_health
	hit_count = 0
	if plate != null:
		plate_durability = plate.max_durability
	_update_visuals()


func _update_visuals() -> void:
	if _label != null:
		var lines := [label_text, "HP %.0f/%.0f" % [health, max_health]]
		if plate != null:
			lines.append("Platte Kl.%d  %.0f/%.0f" % [
				plate.armor_class, plate_durability, plate.max_durability])
		else:
			lines.append("ohne Platte")
		_label.text = "\n".join(lines)

	if _mesh == null:
		return

	# Farbe zeigt den Zustand: gruen -> rot, grau wenn zerstoert.
	var material := _mesh.get_surface_override_material(0)
	if material == null:
		material = StandardMaterial3D.new()
		_mesh.set_surface_override_material(0, material)

	var standard := material as StandardMaterial3D
	if standard == null:
		return

	if health <= 0.0:
		standard.albedo_color = Color(0.25, 0.25, 0.27)
	else:
		var ratio := health / max_health
		standard.albedo_color = Color(1.0 - ratio, ratio * 0.75, 0.15)
