## Schalldaempfer fuer die AR-15.
##
## Verlaengert den Lauf deutlich und verlagert Gewicht nach vorn. Leiser,
## traeger, und die Muendung sitzt danach woanders — deshalb wandert der
## Muendungspunkt mit.
class_name Ar15Suppressor
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_suppressor"


func _configure() -> void:
	file = "AR15_Muendung-Schalldaempfer"


func _build_parts() -> void:
	super()
	# Aus der Geometrie gemessen, nicht als Laenge gepflegt: Aendert der
	# Modellierer den Daempfer, wandert das Muendungsfeuer von selbst mit.
	add_child(GlbParts.pivot("MuzzlePoint", Vector3(0.0, 0.0, forward_tip())))
