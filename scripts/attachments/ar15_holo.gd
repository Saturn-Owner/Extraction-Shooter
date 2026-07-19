## Holografisches Visier fuer die AR-15.
##
## Groesseres Fenster als der Rotpunkt, dafuer schwerer und sperriger. Das
## breite Sichtfeld ist der Grund, warum man es trotzdem nimmt.
class_name Ar15Holo
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_holo"


func _configure() -> void:
	file = "AR15_Holo-Visier"


func _build_parts() -> void:
	super()
	# Gemessen am Leuchtpunkt selbst, nicht am Ursprung des Visiers.
	add_child(GlbParts.pivot("AimPoint", aim_centre()))
