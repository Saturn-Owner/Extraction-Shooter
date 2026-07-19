## Schalldaempfer 5,56.
##
## Lang und dick — genau daran sieht man ihm seinen Nachteil an: Das Gewicht
## sitzt ganz vorn, die Waffe wird kopflastig und kommt traeger ans Auge.
##
## KOORDINATEN: Ursprung ist das Laufgewinde. Der Koerper baut nach vorn (-Z).
class_name Suppressor556Viewmodel
extends AttachmentViewmodel

const LENGTH := 0.175
const RADIUS := 0.0215


func get_model_name() -> String:
	return "suppressor556"


func _build_parts() -> void:
	var black: Material = _mats["black"]
	var steel: Material = _mats["steel"]

	# Ueberwurfmutter am Gewinde.
	add_child(ViewmodelParts.cylinder("Collar", 0.0175, 0.020, Vector3(0.0, 0.0, -0.010), steel))
	# Hauptrohr.
	add_child(ViewmodelParts.cylinder("Body", RADIUS, LENGTH - 0.030,
		Vector3(0.0, 0.0, -0.020 - (LENGTH - 0.030) * 0.5), black))
	# Vorderkappe, leicht verjuengt.
	add_child(ViewmodelParts.taper("FrontCap", 0.0195, RADIUS, 0.016,
		Vector3(0.0, 0.0, -LENGTH + 0.008), black))

	# Laengsrippen zur Kuehlung. Wiederholung als Detail, wie ueberall sonst.
	for i in range(8):
		var angle := deg_to_rad(float(i) * 45.0)
		add_child(ViewmodelParts.box(
			"Fin%d" % i,
			Vector3(0.004, 0.005, LENGTH - 0.055),
			Vector3(sin(angle) * RADIUS, cos(angle) * RADIUS, -0.020 - (LENGTH - 0.055) * 0.5),
			steel,
			Vector3(0.0, 0.0, -rad_to_deg(angle))
		))

	# Ab hier kommt das Feuer heraus — nicht mehr am Lauf der Waffe.
	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, 0.0, -LENGTH - 0.005)))
