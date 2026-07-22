## Schalldaempfer fuer die AR-15 — der GEMTECH ABYSS aus dem Waffenmodell
## (siehe ar15_glb_part.gd, Sorte 1). Er ist dafuer gebaut, UEBER der
## Muendungsbremse zu sitzen — die Bremse bleibt deshalb am Grundkoerper.
##
## Verlaengert den Lauf deutlich und verlagert Gewicht nach vorn. Leiser,
## traeger, und die Muendung sitzt danach woanders — deshalb wandert der
## Muendungspunkt mit.
class_name Ar15Suppressor
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_suppressor"


func _configure() -> void:
	extract_node = "GEMTECH ABYSS 5_56"


func _build_parts() -> void:
	super()
	# Aus der Geometrie gemessen, nicht als Laenge gepflegt: Aendert sich der
	# Daempfer, wandert das Muendungsfeuer von selbst mit.
	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, 0.0, forward_tip())))
