## Gemeinsame Grundlage für AR-15-Anbauteile.
##
## Seit dem Sketchfab-Modell (siehe ar15_viewmodel.gd) gibt es ZWEI Sorten:
##
##   1. TEILE AUS DEM WAFFENMODELL SELBST (extract_node): EOtech, GEMTECH-
##      Dämpfer und Frontgriff stecken bereits in ar15.glb — der Grundkörper
##      wirft sie beim Laden raus, und dieses Skript holt genau denselben
##      Knoten zurück, wenn das Item angebaut ist. Eine Quelle, kein doppelt
##      gepflegtes Modell, und das Teil sitzt zwangsläufig exakt dort, wo der
##      Modellierer es hingebaut hat.
##
##   2. ALTE EINZELDATEIEN (file + place): Rotpunkt und Winkelgriff haben im
##      neuen Modell kein Gegenstück. Ihre alten Dateien bleiben, aber ihre
##      eingebaute Einbaustelle stammt vom ALTEN Modell — deshalb wird sie
##      verworfen und das Teil an einen gemessenen Punkt der neuen Schiene
##      gesetzt (place). Übergangslösung, bis Blender-Ersatz existiert.
##
## Diese Klasse baut kein Teil — sie nimmt jedem Teil nur die immer gleiche
## Arbeit ab, wie es Grundsatz 5 verlangt.
class_name Ar15GlbPart
extends AttachmentViewmodel

## Knotenname in ar15.glb — Sorte 1. Hat Vorrang vor `file`.
var extract_node: String = ""

## Dateiname ohne Endung unter assets/models/weapons/ar15/ — Sorte 2.
var file: String = ""

## Sitz für Sorte 2, in Viewmodel-Achsen (gemessen an der neuen Schiene).
var place: Vector3 = Vector3.ZERO


func _build_parts() -> void:
	if extract_node != "":
		_build_from_weapon_model()
	elif file != "":
		_build_from_own_file()
	else:
		push_error("[%s] weder extract_node noch file angegeben" % get_model_name())


## Sorte 1: den Knoten aus dem Waffenmodell herauslösen.
func _build_from_weapon_model() -> void:
	var scene := load(AR15Viewmodel.MODEL) as PackedScene
	if scene == null:
		push_warning("[%s] Waffenmodell fehlt" % get_model_name())
		return

	var instance := scene.instantiate()
	var part := AR15Viewmodel.find_model_node(instance, extract_node)
	if part == null:
		push_warning("[%s] Knoten '%s' nicht im Waffenmodell" % [get_model_name(), extract_node])
		instance.free()
		return

	# Dieselbe Einpassung wie der Waffenkörper — nur so landet das Teil exakt
	# an seiner modellierten Stelle.
	var fit := AR15Viewmodel.fit_transform_for(AR15Viewmodel.MUZZLE_Z)
	var full := fit * _accumulate(instance, part)

	part.get_parent().remove_child(part)
	part.owner = null
	add_child(part)
	# Position auf den Anbauteil-Knoten, Drehung/Skalierung auf das Mesh —
	# gleiche Aufteilung wie bei den beweglichen Teilen, gleiche Begründung
	# (siehe akm_viewmodel.gd).
	position = full.origin
	(part as Node3D).transform = Transform3D(full.basis, Vector3.ZERO)

	# Der Rest des instanzierten Modells wird nicht mehr gebraucht.
	instance.free()


## Sorte 2: alte Einzeldatei laden und an die gemessene Stelle setzen.
func _build_from_own_file() -> void:
	var packed := load("res://assets/models/weapons/ar15/" + file + ".glb") as PackedScene
	if packed == null:
		push_warning("[%s] Modell fehlt: %s" % [get_model_name(), file])
		return

	var instance := packed.instantiate()
	# Der Trägerknoten der Datei bleibt UNANGETASTET: Sein Versatz ist genau
	# das, was die Geometrie um den Ursprung zentriert (gemessen: mit Träger
	# liegt die Hülle symmetrisch um null, ohne ihn läge sie irgendwo im
	# Raum). Die Einbaustelle des alten Modells steckt NICHT hier, sondern
	# war im alten GlbParts.mount_point verrechnet — das wird nicht mehr
	# benutzt, `place` übernimmt.
	var holder := Node3D.new()
	holder.name = "Modell"
	# Blender-Achsen (+X Mündung) auf Spielachsen (-Z Mündung).
	holder.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	holder.add_child(instance)
	add_child(holder)
	position = place


static func _accumulate(root_node: Node, target: Node) -> Transform3D:
	var chain: Array[Node3D] = []
	var walker := target
	while walker != root_node and walker != null:
		if walker is Node3D:
			chain.append(walker)
		walker = walker.get_parent()
	var result := Transform3D.IDENTITY
	for i in range(chain.size() - 1, -1, -1):
		result = result * (chain[i] as Node3D).transform
	return result


## Mitte des Leuchtpunkts, in Viewmodel-Achsen relativ zum Teil. Gesucht wird
## die Fläche mit dem Material "dot", ersatzweise "glass" — funktioniert für
## die alten Einzeldateien. Das Sketchfab-EOtech hat nur ein Sammelmaterial;
## sein Zielpunkt steht deshalb als gemessene Konstante in ar15_holo.gd.
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


## Vorderste Spitze des Teils, in Viewmodel-Achsen relativ zum Teil.
## Aus der Geometrie gemessen statt als Zahl gepflegt.
func forward_tip() -> float:
	var bounds := _model_bounds(self, Transform3D.IDENTITY)
	if bounds.size == Vector3.ZERO:
		return 0.0
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
