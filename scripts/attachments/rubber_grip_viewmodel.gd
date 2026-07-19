## Gummigriff fuer das AR-15-Griffstueck.
##
## Ersetzt den eingebauten Griff komplett. Etwas dicker als das Original und
## mit weicher Auflage — dafuer liegt er ruhiger in der Hand.
##
## KOORDINATEN: Ursprung ist die Griffaufnahme am Gehaeuse. Die Neigung bringt
## das Teil selbst mit, damit die Aufnahme ein schlichter Punkt bleiben kann.
class_name RubberGripViewmodel
extends AttachmentViewmodel

const TILT := -17.0


func get_model_name() -> String:
	return "grip_rubber"


func _build_parts() -> void:
	var polymer: Material = _mats["polymer"]
	var furniture: Material = _mats["furniture"]

	var grip := ViewmodelParts.pivot("Grip", Vector3.ZERO)
	grip.rotation_degrees = Vector3(TILT, 0.0, 0.0)

	grip.add_child(ViewmodelParts.box("Core", Vector3(0.034, 0.076, 0.044), Vector3.ZERO, polymer))
	grip.add_child(ViewmodelParts.box("Flare", Vector3(0.037, 0.010, 0.048), Vector3(0.0, -0.039, 0.006), polymer))

	# Gummiauflagen vorn und hinten, in einem anderen Ton als das Griffstueck
	# darunter — sonst sieht man von der Auflage nichts.
	grip.add_child(ViewmodelParts.box("PadFront", Vector3(0.030, 0.056, 0.005),
		Vector3(0.0, -0.002, -0.0235), furniture))
	grip.add_child(ViewmodelParts.box("PadBack", Vector3(0.030, 0.056, 0.005),
		Vector3(0.0, -0.002, 0.0235), furniture))
	grip.add_child(ViewmodelParts.ribs("PadRibs", 7, Vector3(0.028, 0.004, 0.0022),
		Vector3(0.0, -0.026, -0.0265), Vector3(0.0, 0.0085, 0.0), polymer))

	add_child(grip)
