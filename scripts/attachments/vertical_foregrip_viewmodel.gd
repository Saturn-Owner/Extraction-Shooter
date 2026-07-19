## Senkrechter Vordergriff am Handschutz.
##
## Ragt gerade nach unten. Damit kann man die Waffe kraeftig nach unten ziehen
## und den Hochschlag wegdruecken — dafuer steht er ueberall im Weg und macht
## die Waffe sperrig.
##
## KOORDINATEN: Ursprung ist die Aufnahme an der Unterseite des Handschutzes.
class_name VerticalForegripViewmodel
extends AttachmentViewmodel

const LENGTH := 0.082


func get_model_name() -> String:
	return "foregrip_vertical"


func _build_parts() -> void:
	var polymer: Material = _mats["polymer"]
	var black: Material = _mats["black"]

	# Klemme am Handschutz.
	add_child(ViewmodelParts.box("Clamp", Vector3(0.026, 0.010, 0.034), Vector3(0.0, -0.005, 0.0), black))
	# Schaft, leicht nach vorn geneigt — senkrecht heisst nicht lotrecht.
	var shaft := ViewmodelParts.pivot("Shaft", Vector3(0.0, -0.010, 0.0))
	shaft.rotation_degrees = Vector3(6.0, 0.0, 0.0)
	shaft.add_child(ViewmodelParts.cylinder("Body", 0.0125, LENGTH,
		Vector3(0.0, -LENGTH * 0.5, 0.0), polymer, Vector3(0.0, 0.0, 0.0)))
	shaft.add_child(ViewmodelParts.cylinder("Cap", 0.0145, 0.010,
		Vector3(0.0, -LENGTH + 0.004, 0.0), black, Vector3(0.0, 0.0, 0.0)))

	# Umlaufende Griffrillen.
	for i in range(6):
		shaft.add_child(ViewmodelParts.cylinder("Groove%d" % i, 0.0132, 0.004,
			Vector3(0.0, -0.016 - float(i) * 0.011, 0.0), black, Vector3(0.0, 0.0, 0.0)))

	add_child(shaft)
