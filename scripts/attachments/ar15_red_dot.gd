## Rotpunktvisier fuer die AR-15.
##
## Kleines geschlossenes Visier auf der Schiene. Beide Augen offen, kein
## Vergroesserungsfaktor — schnell auf kurze Distanz, nutzlos auf lange.
class_name Ar15RedDot
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_red_dot"


func _configure() -> void:
	file = "AR15_Red-Dot"


func _build_parts() -> void:
	super()
	# Gemessen am Leuchtpunkt selbst, nicht am Ursprung des Visiers. Genau
	# hier entscheidet sich, ob die Waffe dorthin schiesst, wo der Punkt steht.
	add_child(GlbParts.pivot("AimPoint", aim_centre()))
