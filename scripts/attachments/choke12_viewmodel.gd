## Wuergebohrung fuer die Flinte.
##
## Sitzt zum groessten Teil IM Lauf — von aussen sieht man nur einen kurzen
## geriffelten Ring. Genau deshalb ist es das unauffaelligste Teil im ganzen
## Sortiment, obwohl es die Schrotgarbe deutlich veraendert.
class_name Choke12Viewmodel
extends AttachmentViewmodel

const LENGTH := 0.032


func get_model_name() -> String:
	return "choke12"


func _build_parts() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]

	add_child(ViewmodelParts.cylinder("Body", 0.0155, LENGTH,
		Vector3(0.0, 0.0, -LENGTH * 0.5), black))
	add_child(ViewmodelParts.cylinder("Rim", 0.0165, 0.008, Vector3(0.0, 0.0, -LENGTH + 0.004), steel))

	# Griffkerben zum Wechseln von Hand.
	for i in range(6):
		var angle := deg_to_rad(float(i) * 60.0)
		add_child(ViewmodelParts.box(
			"Notch%d" % i,
			Vector3(0.004, 0.004, 0.012),
			Vector3(sin(angle) * 0.0165, cos(angle) * 0.0165, -LENGTH + 0.006),
			steel,
			Vector3(0.0, 0.0, -rad_to_deg(angle))
		))

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, 0.0, -LENGTH - 0.003)))
