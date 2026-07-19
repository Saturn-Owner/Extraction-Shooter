## Zielfernrohr 4x auf Picatinny-Schiene.
##
## Deutlich groesser und hoeher als der Rotpunkt — genau das ist sein
## Nachteil: Der Kopf muss weiter hoch, die Waffe wird kopflastig, und auf
## kurze Distanz sieht man nur noch einen Ausschnitt.
##
## KOORDINATEN: Ursprung ist die Aufnahme, also die Oberkante der Schiene.
class_name Scope4xViewmodel
extends AttachmentViewmodel

## Hoeher als beim Rotpunkt, weil das Rohr dicker ist und ueber die
## Kimme passen muss.
const TUBE_Y := 0.033


func get_model_name() -> String:
	return "scope4x"


func _build_parts() -> void:
	var black: Material = _mats["black"]
	var steel: Material = _mats["steel"]
	var recess: Material = _mats["recess"]

	# Zwei Montageringe statt eines durchgehenden Sockels.
	for offset in [-0.030, 0.034]:
		var tag := "Front" if offset < 0.0 else "Rear"
		add_child(ViewmodelParts.box("Ring%sBase" % tag, Vector3(0.022, 0.020, 0.018),
			Vector3(0.0, 0.010, offset), black))
		add_child(ViewmodelParts.cylinder("Ring%sCollar" % tag, 0.0195, 0.016,
			Vector3(0.0, TUBE_Y, offset), steel))
		add_child(ViewmodelParts.screw("Ring%sScrew" % tag, 0.004, 0.005,
			Vector3(0.013, 0.014, offset), steel))

	# Rohr mit dickerem Objektiv vorn — das ist die Silhouette, an der man
	# ein Zielfernrohr auf Anhieb erkennt.
	add_child(ViewmodelParts.cylinder("Tube", 0.0165, 0.130, Vector3(0.0, TUBE_Y, 0.000), black))
	add_child(ViewmodelParts.taper("ObjectiveCone", 0.0225, 0.0170, 0.026,
		Vector3(0.0, TUBE_Y, -0.052), black))
	add_child(ViewmodelParts.cylinder("ObjectiveBell", 0.0235, 0.020, Vector3(0.0, TUBE_Y, -0.072), black))
	add_child(ViewmodelParts.cylinder("Ocular", 0.0200, 0.024, Vector3(0.0, TUBE_Y, 0.058), black))

	add_child(ViewmodelParts.cylinder("LensFront", 0.0215, 0.003, Vector3(0.0, TUBE_Y, -0.081), recess))
	add_child(ViewmodelParts.cylinder("LensRear", 0.0180, 0.003, Vector3(0.0, TUBE_Y, 0.069), recess))

	# Verstelltuerme oben und seitlich.
	add_child(ViewmodelParts.cylinder("TurretTop", 0.0095, 0.014, Vector3(0.0, TUBE_Y + 0.021, 0.006), steel))
	add_child(ViewmodelParts.cylinder("TurretSide", 0.0095, 0.014, Vector3(0.021, TUBE_Y, 0.006), steel,
		Vector3(0.0, 0.0, 90.0)))
	# Vergroesserungsring am Okular, mit Griffrippen.
	add_child(ViewmodelParts.ribs("ZoomRing", 6, Vector3(0.042, 0.004, 0.003),
		Vector3(0.0, TUBE_Y + 0.020, 0.040), Vector3(0.0, 0.0, 0.005), steel))

	add_child(ViewmodelParts.pivot("AimPoint", Vector3(0.0, TUBE_Y, 0.0)))
