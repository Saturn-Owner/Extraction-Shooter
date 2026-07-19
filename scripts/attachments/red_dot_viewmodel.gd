## Rotpunktvisier auf Picatinny-Schiene.
##
## Kurzes Rohr auf einem Sockel. Man schaut hindurch, nicht darauf — deshalb
## ist der Zielpunkt die Mitte des Rohres, nicht seine Oberkante.
##
## KOORDINATEN: Ursprung ist die Aufnahme, also die Oberkante der Schiene.
## Alles baut von dort nach oben.
class_name RedDotViewmodel
extends AttachmentViewmodel

## Höhe der Rohrmitte über der Schiene. Bei einem Rotpunkt bewusst niedrig —
## je tiefer das Visier sitzt, desto weniger muss der Kopf wandern.
const TUBE_Y := 0.023


func get_model_name() -> String:
	return "reddot"


func _build_parts() -> void:
	var black: Material = _mats["black"]
	var steel: Material = _mats["steel"]
	var recess: Material = _mats["recess"]

	# Sockel mit Klemmschraube an der Schiene.
	add_child(ViewmodelParts.box("Base", Vector3(0.026, 0.012, 0.042), Vector3(0.0, 0.006, 0.0), black))
	add_child(ViewmodelParts.box("Clamp", Vector3(0.030, 0.008, 0.016), Vector3(0.0, 0.004, 0.012), steel))
	add_child(ViewmodelParts.screw("ClampScrew", 0.005, 0.006, Vector3(0.016, 0.004, 0.012), steel))

	# Rohr. Zwei Ringe vorn und hinten, dazwischen dünner — so liest es sich
	# als Optik und nicht als Klotz.
	add_child(ViewmodelParts.cylinder("Tube", 0.0135, 0.052, Vector3(0.0, TUBE_Y, -0.004), black))
	add_child(ViewmodelParts.cylinder("RingFront", 0.0165, 0.008, Vector3(0.0, TUBE_Y, -0.028), black))
	add_child(ViewmodelParts.cylinder("RingRear", 0.0165, 0.008, Vector3(0.0, TUBE_Y, 0.020), black))

	# Die Linsen als dunkle Scheiben knapp innerhalb der Ringe. Ohne sie
	# schaut man durch ein offenes Rohr auf die Waffe dahinter.
	add_child(ViewmodelParts.cylinder("LensFront", 0.0125, 0.003, Vector3(0.0, TUBE_Y, -0.026), recess))
	add_child(ViewmodelParts.cylinder("LensRear", 0.0125, 0.003, Vector3(0.0, TUBE_Y, 0.018), recess))

	# Verstellturm oben.
	add_child(ViewmodelParts.cylinder("Turret", 0.007, 0.010, Vector3(0.0, TUBE_Y + 0.016, 0.0), steel,
		Vector3(0.0, 0.0, 0.0)))

	# Hier schaut der Spieler hindurch.
	add_child(ViewmodelParts.pivot("AimPoint", Vector3(0.0, TUBE_Y, 0.0)))
