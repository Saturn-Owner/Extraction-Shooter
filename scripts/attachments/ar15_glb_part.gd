## Gemeinsame Grundlage für AR-15-Anbauteile, die als .glb aus Blender kommen.
##
## Diese Klasse baut KEIN Teil. Sie nimmt jedem Teil nur die immer gleiche
## Arbeit ab: Datei laden, Achsen drehen, an die Einbaustelle setzen. Was ein
## Teil ausmacht — wo man hindurchschaut, wie lang es den Lauf macht — steht
## weiterhin in seiner eigenen Datei, wie Grundsatz 5 es verlangt.
##
## Ohne sie stünde dieselbe Umrechnung fünfmal da, und beim sechsten Teil
## stünde sie einmal falsch.
class_name Ar15GlbPart
extends AttachmentViewmodel

## Dateiname ohne Endung. Muss die Unterklasse setzen.
var file: String = ""


func _build_parts() -> void:
	if file == "":
		push_error("[%s] kein Modell angegeben" % get_model_name())
		return

	var model := GlbParts.load_part(file, "Modell")
	if model == null:
		return
	add_child(model)

	# Die Aufnahme liegt im Ursprung, das Teil bringt seine Stelle selbst mit —
	# siehe AR15Viewmodel._build_mounts().
	position = GlbParts.mount_point(file)


## Vorderste Spitze des Teils, in Viewmodel-Achsen.
##
## Wird aus der Geometrie gemessen statt als Zahl gepflegt: Ein Wert, der
## neben dem Modell steht, passt irgendwann nicht mehr zu ihm.
func forward_tip() -> float:
	var bounds := _model_bounds(self, Transform3D.IDENTITY)
	if bounds.size == Vector3.ZERO:
		return 0.0
	# -Z ist vorne, also die kleinste Z-Koordinate.
	return bounds.position.z


func _model_bounds(node: Node, transform: Transform3D) -> AABB:
	var result := AABB()
	var found := false

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			result = transform * mesh_instance.mesh.get_aabb()
			found = true

	for child in node.get_children():
		if not (child is Node3D):
			continue
		var sub := _model_bounds(child, transform * (child as Node3D).transform)
		if sub.size == Vector3.ZERO:
			continue
		result = sub if not found else result.merge(sub)
		found = true

	return result
