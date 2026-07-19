## Winkelgriff am Handschutz.
##
## Flach nach vorn angeschraegt statt senkrecht. Man zieht die Waffe damit
## nach hinten in die Schulter statt nach unten — das haelt sie seitlich
## ruhig, ohne dass etwas absteht.
class_name AngledForegripViewmodel
extends AttachmentViewmodel

const LENGTH := 0.058
const TILT := 38.0


func get_model_name() -> String:
	return "foregrip_angled"


func _build_parts() -> void:
	var polymer: Material = _mats["polymer"]
	var black: Material = _mats["black"]

	add_child(ViewmodelParts.box("Clamp", Vector3(0.026, 0.010, 0.040), Vector3(0.0, -0.005, 0.0), black))

	# Der schraege Steg. Die Neigung ist das ganze Bauteil — steht er
	# senkrecht, ist es ein anderer Griff.
	var wedge := ViewmodelParts.pivot("Wedge", Vector3(0.0, -0.010, -0.004))
	wedge.rotation_degrees = Vector3(TILT, 0.0, 0.0)
	wedge.add_child(ViewmodelParts.box("Body", Vector3(0.024, LENGTH, 0.026),
		Vector3(0.0, -LENGTH * 0.5, 0.0), polymer))
	wedge.add_child(ViewmodelParts.box("Toe", Vector3(0.027, 0.010, 0.030),
		Vector3(0.0, -LENGTH + 0.004, 0.0), black))
	wedge.add_child(ViewmodelParts.ribs("Ribs", 5, Vector3(0.022, 0.004, 0.0025),
		Vector3(0.0, -0.014, -0.0135), Vector3(0.0, -0.009, 0.0), black))

	add_child(wedge)
