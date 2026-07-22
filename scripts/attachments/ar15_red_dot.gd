## Rotpunktvisier fuer die AR-15.
##
## Kleines geschlossenes Visier auf der Schiene. Beide Augen offen, kein
## Vergroesserungsfaktor — schnell auf kurze Distanz, nutzlos auf lange.
##
## UEBERGANG: Im Sketchfab-Modell gibt es kein Rotpunkt-Gegenstueck, deshalb
## bleibt die alte Blender-Datei — gesetzt auf die GEMESSENE Schiene des neuen
## Modells (ar15_glb_part.gd, Sorte 2). Ein eigenes Modell darf sie abloesen.
class_name Ar15RedDot
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_red_dot"


func _configure() -> void:
	file = "AR15_Red-Dot"
	# Schienenoberkante des Gehaeuses (Modell: y 0.5424, Gehaeusemitte x 0.15),
	# plus die halbe Gehaeusehoehe des Visiers (gemessen 0.0193): Die Datei
	# ist um ihren Mittelpunkt zentriert, der Fuss soll auf der Schiene stehen.
	place = AR15Viewmodel.fit_transform_for(AR15Viewmodel.MUZZLE_Z) \
		* Vector3(0.15, AR15Viewmodel.RAIL_TOP_MODEL, 0.0) \
		+ Vector3(0.0, 0.0193, 0.0)


func _build_parts() -> void:
	super()
	# Gemessen am Leuchtpunkt selbst, nicht am Ursprung des Visiers. Genau
	# hier entscheidet sich, ob die Waffe dorthin schiesst, wo der Punkt steht.
	add_child(ViewmodelParts.pivot("AimPoint", aim_centre()))
