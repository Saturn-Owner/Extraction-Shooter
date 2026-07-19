## Schalldaempfer 9 mm fuer die Pistole.
##
## Kuerzer und schlanker als der Gewehrdaempfer, aber im Verhaeltnis zur
## Waffe riesig: An einer Pistole macht er fast die halbe Laenge aus.
class_name Suppressor9mmViewmodel
extends AttachmentViewmodel

const LENGTH := 0.115
const RADIUS := 0.0165


func get_model_name() -> String:
	return "suppressor9mm"


func _build_parts() -> void:
	var black: Material = _mats["black"]
	var steel: Material = _mats["steel"]

	add_child(ViewmodelParts.cylinder("Collar", 0.0140, 0.016, Vector3(0.0, 0.0, -0.008), steel))
	add_child(ViewmodelParts.cylinder("Body", RADIUS, LENGTH - 0.024,
		Vector3(0.0, 0.0, -0.016 - (LENGTH - 0.024) * 0.5), black))
	add_child(ViewmodelParts.taper("FrontCap", 0.0150, RADIUS, 0.012,
		Vector3(0.0, 0.0, -LENGTH + 0.006), black))

	# Nur zwei Griffkerben statt umlaufender Rippen — an einer Pistole waere
	# mehr Struktur zu unruhig fuer die Groesse.
	for offset in [-0.035, -0.075]:
		add_child(ViewmodelParts.cylinder("Groove%d" % int(-offset * 1000), RADIUS + 0.001, 0.005,
			Vector3(0.0, 0.0, offset), steel))

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, 0.0, -LENGTH - 0.004)))
