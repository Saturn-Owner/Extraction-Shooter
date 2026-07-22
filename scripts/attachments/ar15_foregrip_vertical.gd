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
