## Senkrechter Vordergriff fuer die AR-15 — der BCM VFG aus dem Waffenmodell
## (siehe ar15_glb_part.gd, Sorte 1).
##
## Man zieht die Waffe in die Schulter statt sie nur zu halten. Das drueckt
## den Hochschlag, kostet aber Beweglichkeit beim Schwenken.
class_name Ar15ForegripVertical
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_foregrip_vertical"


func _configure() -> void:
	extract_node = "BCM VFG"


## Mitte der Griffschale, relativ zum Teil gemessen (tools/_measure_foregrip.gd:
## AABB x -0.0133..0.0133, y -0.0544..0.0100, z -0.2721..-0.2261 — Mittelpunkt
## dieser drei Spannen). weapon_viewmodel.gd zieht die Stützhand hierher, statt
## sie am Handschutz stehen zu lassen, wenn dieser Griff angebaut ist.
func _build_parts() -> void:
	super()
	add_child(ViewmodelParts.pivot("GripPoint", Vector3(0.0, -0.022, -0.249)))
