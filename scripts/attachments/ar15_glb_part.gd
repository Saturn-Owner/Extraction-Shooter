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


## Mitte des Leuchtpunkts, in Viewmodel-Achsen. Das ist die optische Achse.
##
## ---------------------------------------------------------------------------
## WARUM GEMESSEN UND NICHT DER URSPRUNG DES TEILS
##
## Der Zielpunkt lag vorher im Ursprung des Visiers. Der Leuchtpunkt sitzt aber
## nicht dort: beim Rotpunkt 6,8 mm darueber, beim Holovisier 2,7 mm.
##
## Beim Zielen senkt weapon_view.gd die Waffe um sight_height ab, damit die
## Visierlinie in der Bildmitte landet. War der Wert 6,8 mm zu klein, stand der
## Punkt um denselben Betrag ueber der Mitte — und die Kugel ging in die Mitte,
## also unter den Punkt. Auf 0,24 m Zielabstand sind das 1,6 Grad: auf 25 m
## rund 70 cm zu tief. Man zielt sauber und trifft nichts.
##
## Gesucht wird die Flaeche mit dem Material "dot", ersatzweise "glass". Damit
## stimmt die Visierlinie automatisch, auch wenn der Modellierer das Absehen
## verschiebt.
func aim_centre() -> Vector3:
	var found: Variant = _surface_centre(self, Transform3D.IDENTITY, "dot")
	if found == null:
		found = _surface_centre(self, Transform3D.IDENTITY, "glass")
	if found == null:
		push_warning("[%s] kein Absehen gefunden — Zielpunkt liegt im Ursprung"
			% get_model_name())
		return Vector3.ZERO
	return found


func _surface_centre(node: Node, transform: Transform3D, material_name: String) -> Variant:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(i)
				if material == null or material.resource_name != material_name:
					continue
				var vertices: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				if vertices.is_empty():
					continue
				var low := Vector3.INF
				var high := -Vector3.INF
				for vertex in vertices:
					var point: Vector3 = transform * vertex
					low = low.min(point)
					high = high.max(point)
				return (low + high) * 0.5

	for child in node.get_children():
		if not (child is Node3D):
			continue
		var found: Variant = _surface_centre(child, transform * (child as Node3D).transform, material_name)
		if found != null:
			return found
	return null


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
