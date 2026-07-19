## Mini-Rotpunkt fuer den Pistolenschlitten.
##
## Winzig und offen statt als Rohr: Ein geschlossenes Rohr auf einer Pistole
## waere so hoch, dass man die Waffe nicht mehr aus dem Holster bekaeme.
## Deshalb nur ein Rahmen mit einer schraeg stehenden Scheibe.
class_name MicroDotViewmodel
extends AttachmentViewmodel

## Sehr flach — die kurze Visierlinie der Pistole ist ihr groesster Nachteil,
## und ein hoch aufbauendes Visier macht das nur schlimmer.
const GLASS_Y := 0.014


func get_model_name() -> String:
	return "microdot"


func _build_parts() -> void:
	var black: Material = _mats["black"]
	var recess: Material = _mats["recess"]

	add_child(ViewmodelParts.box("Base", Vector3(0.020, 0.005, 0.026), Vector3(0.0, 0.003, 0.0), black))
	# Zwei Seitenwangen, dazwischen die Scheibe. Oben offen.
	for side in [-1.0, 1.0]:
		add_child(ViewmodelParts.box("Wall%s" % ("L" if side < 0.0 else "R"),
			Vector3(0.004, 0.020, 0.024), Vector3(side * 0.008, 0.012, 0.0), black))
	# Scheibe leicht nach hinten geneigt, so wie sie wirklich steht.
	add_child(ViewmodelParts.box("Glass", Vector3(0.013, 0.017, 0.002),
		Vector3(0.0, GLASS_Y, -0.006), recess, Vector3(-8.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("Hood", Vector3(0.020, 0.004, 0.008), Vector3(0.0, 0.022, -0.008), black))

	add_child(ViewmodelParts.pivot("AimPoint", Vector3(0.0, GLASS_Y, 0.0)))
