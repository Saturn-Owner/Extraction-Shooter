## Zielgriff fuer das AR-15-Griffstueck.
##
## Steiler als das Original und mit ausgeformter Handauflage oben. Der steile
## Winkel legt das Handgelenk gerader hinter die Waffe — dadurch kommt sie
## schneller hoch und liegt ruhiger.
class_name TargetGripViewmodel
extends AttachmentViewmodel

## Deutlich steiler als die 17 Grad des Seriengriffs. Genau daran sieht man
## den Unterschied auf einen Blick.
const TILT := -8.0


func get_model_name() -> String:
	return "grip_target"


func _build_parts() -> void:
	var polymer: Material = _mats["polymer"]
	var black: Material = _mats["black"]

	var grip := ViewmodelParts.pivot("Grip", Vector3.ZERO)
	grip.rotation_degrees = Vector3(TILT, 0.0, 0.0)

	grip.add_child(ViewmodelParts.box("Core", Vector3(0.032, 0.078, 0.040), Vector3.ZERO, polymer))
	# Handauflage: der Wulst oben, auf dem der Daumenballen liegt.
	grip.add_child(ViewmodelParts.box("Shelf", Vector3(0.038, 0.012, 0.030),
		Vector3(0.0, 0.040, 0.008), polymer, Vector3(-12.0, 0.0, 0.0)))
	grip.add_child(ViewmodelParts.box("Flare", Vector3(0.035, 0.009, 0.044), Vector3(0.0, -0.041, 0.004), black))

	# Fingerrillen vorn statt durchgehender Riffelung — daran erkennt man
	# einen Zielgriff.
	for i in range(3):
		grip.add_child(ViewmodelParts.cylinder("FingerGroove%d" % i, 0.006, 0.030,
			Vector3(0.0, -0.026 + float(i) * 0.020, -0.020), black, Vector3(0.0, 0.0, 90.0)))

	grip.add_child(ViewmodelParts.ribs("BackRibs", 8, Vector3(0.028, 0.0035, 0.0022),
		Vector3(0.0, -0.030, 0.0205), Vector3(0.0, 0.0082, 0.0), polymer))

	add_child(grip)
