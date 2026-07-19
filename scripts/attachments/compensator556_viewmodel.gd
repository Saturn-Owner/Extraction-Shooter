## Kompensator 5,56.
##
## Kurz und kantig, mit seitlichen Schlitzen, durch die die Gase nach oben und
## zur Seite austreten. Genau die machen ihn so laut — die Druckwelle geht
## nicht mehr nach vorn weg, sondern zum Schuetzen hin.
class_name Compensator556Viewmodel
extends AttachmentViewmodel

const LENGTH := 0.058


func get_model_name() -> String:
	return "comp556"


func _build_parts() -> void:
	var black: Material = _mats["black"]
	var steel: Material = _mats["steel"]
	var recess: Material = _mats["recess"]

	add_child(ViewmodelParts.cylinder("Collar", 0.0155, 0.012, Vector3(0.0, 0.0, -0.006), steel))
	# Kantiger Koerper statt rund — daran unterscheidet man ihn auf einen
	# Blick von einem Daempfer.
	add_child(ViewmodelParts.box("Body", Vector3(0.026, 0.026, LENGTH - 0.016),
		Vector3(0.0, 0.0, -0.012 - (LENGTH - 0.016) * 0.5), black))
	add_child(ViewmodelParts.box("FrontFace", Vector3(0.028, 0.028, 0.008),
		Vector3(0.0, 0.0, -LENGTH + 0.004), black))

	# Gasschlitze oben und an beiden Seiten.
	for i in range(3):
		var z := -0.020 - float(i) * 0.012
		add_child(ViewmodelParts.box("PortTop%d" % i, Vector3(0.012, 0.004, 0.006),
			Vector3(0.0, 0.013, z), recess))
		for side in [-1.0, 1.0]:
			add_child(ViewmodelParts.box("PortSide%d%s" % [i, "L" if side < 0.0 else "R"],
				Vector3(0.004, 0.012, 0.006), Vector3(side * 0.013, 0.0, z), recess))

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, 0.0, -LENGTH - 0.004)))
