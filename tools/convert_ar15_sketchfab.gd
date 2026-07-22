## Bereitet das Sketchfab-AR-15-Modell fürs Spiel auf.
##
##   godot --headless --path . --script res://tools/convert_ar15_sketchfab.gd
##
## Quelle: "AR-15" von wafla, https://sketchfab.com/3d-models/ar-15-33e225811b404192b89dcd4096603fbe
## Lizenz: CC BY 4.0 (Namensnennung, kommerziell erlaubt) — siehe QUELLEN.md.
##
## Was das Skript tut:
##   1. lädt die Rohdatei aus dem Downloads-Ordner (124 MB — zu groß fürs Repo)
##   2. wirft die Sketchfab-Hüllknoten ab und hebt den eigentlichen Teilebaum an
##   3. verkleinert alle Texturen auf höchstens MAX_TEXTURE Pixel Kantenlänge
##   4. schreibt assets/models/weapons/ar15/ar15.glb
##   5. VERMISST das Modell und druckt die Konstanten, die ar15_viewmodel.gd
##      braucht (Hülle, Mitte, Lauf, Schiene, Teil-Positionen) — messen statt
##      schätzen, wie bei der AKM.
##
## Nach einem Modell-Update von wafla: neue Datei herunterladen, SOURCE
## anpassen, Skript laufen lassen, Konstanten im Viewmodel nachziehen.
extends SceneTree

const SOURCE := "C:/Users/lappe/Downloads/ar-15 (1).glb"
const TARGET := "res://assets/models/weapons/ar15/ar15.glb"

## Kantenlänge, auf die große Texturen verkleinert werden.
##
## Die Quelle bringt ~46 Texturen mit je 2048 px mit — jedes Bauteil hat sein
## eigenes Set. In Summe wären das >120 MB. Da jedes einzelne Teil auf dem
## Bildschirm klein ist, reichen 1024 px pro Teil völlig; nur wer mit der Nase
## am Handschutz klebt, könnte einen Unterschied sehen.
const MAX_TEXTURE := 1024

## Diese Knoten interessieren uns besonders — ihre Lage wird ausgedruckt.
const REPORT_NODES := [
	"Barrel", "Muzzle brake", "GEMTECH ABYSS 5_56", "EOtech EXPS-2",
	"Magpul PMAG 30", "Bullets", "Bolt carrier", "Bolt", "Charging handle",
	"Trigger", "SSL", "Grip", "BCM VFG", "Handguard", "Ejection port cover",
	"CQB STOCK", "Upper receiver", "Lower receiver", "Surefire EDC1",
	"mount flashlight", "Magazine catch button",
]


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(SOURCE, state) != OK:
		print("FEHLER: Quelle nicht lesbar: ", SOURCE)
		quit(1)
		return

	var scene := document.generate_scene(state)

	# Sketchfab verpackt das Modell in vier Hüllknoten (Sketchfab_Scene >
	# Sketchfab_model > *_fbx > RootNode). Wir heben die eigentlichen Teile
	# unter eine flache Wurzel — die Hüllen tragen aber Transformationen
	# (FBX-Skalierung!), die dabei eingerechnet werden müssen.
	var root := Node3D.new()
	root.name = "AR15"
	var parts := _find_parts_parent(scene)
	if parts == null:
		print("FEHLER: RootNode im Sketchfab-Baum nicht gefunden")
		quit(1)
		return
	var carry := _accumulated_transform(scene, parts)
	for child in parts.get_children().duplicate():
		parts.remove_child(child)
		child.owner = null
		root.add_child(child)
		if child is Node3D:
			(child as Node3D).transform = carry * (child as Node3D).transform
		_own_recursive(child, root)

	var shrunk := _shrink_textures(root)

	# Export über einen frischen GLTFDocument — der alte state gehört der Quelle.
	var out_document := GLTFDocument.new()
	# Verlustfreies WebP statt PNG: gleiche Qualität, rund ein Drittel kleiner.
	out_document.image_format = "Lossless WebP"
	var out_state := GLTFState.new()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(TARGET.get_base_dir()))
	var error := out_document.append_from_scene(root, out_state)
	if error == OK:
		error = out_document.write_to_filesystem(out_state, TARGET)
	if error != OK:
		print("FEHLER beim Schreiben: ", error)
		quit(1)
		return

	var written := FileAccess.get_file_as_bytes(TARGET)
	print("Geschrieben: %s (%.1f MB, %d Texturen verkleinert)" % [
		TARGET, written.size() / 1048576.0, shrunk])
	print("")
	_report(root)
	quit(0)


## Findet den Knoten, unter dem die eigentlichen Waffenteile hängen.
func _find_parts_parent(node: Node) -> Node:
	if node.name == "RootNode":
		return node
	for child in node.get_children():
		var found := _find_parts_parent(child)
		if found != null:
			return found
	return null


## Transform von der Szenenwurzel bis EINSCHLIESSLICH des Knotens selbst.
func _accumulated_transform(root_node: Node, target: Node) -> Transform3D:
	var chain: Array[Transform3D] = []
	var walker := target
	while walker != null and walker != root_node:
		if walker is Node3D:
			chain.append((walker as Node3D).transform)
		walker = walker.get_parent()
	if root_node is Node3D:
		chain.append((root_node as Node3D).transform)
	var result := Transform3D.IDENTITY
	for i in range(chain.size() - 1, -1, -1):
		result = result * chain[i]
	return result


func _own_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		_own_recursive(child, new_owner)


## Verkleinert jede Textur einmal, egal in wie vielen Material-Slots sie steckt.
func _shrink_textures(node: Node) -> int:
	var seen := {}
	var count := 0
	for mesh_instance in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mesh_instance as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null:
				continue
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_METALLIC,
					BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_NORMAL,
					BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
				var texture := material.get_texture(slot)
				if texture == null:
					continue
				var key := texture.get_instance_id()
				if seen.has(key):
					material.set_texture(slot, seen[key])
					continue
				var image := texture.get_image()
				if image == null:
					continue
				if image.is_compressed():
					image.decompress()
				if image.get_width() > MAX_TEXTURE or image.get_height() > MAX_TEXTURE:
					var scale := float(MAX_TEXTURE) / float(maxi(image.get_width(), image.get_height()))
					image.resize(int(image.get_width() * scale), int(image.get_height() * scale),
						Image.INTERPOLATE_LANCZOS)
					count += 1
				var replacement := ImageTexture.create_from_image(image)
				seen[key] = replacement
				material.set_texture(slot, replacement)
	return count


## Druckt alles, was ar15_viewmodel.gd an Zahlen braucht — im MODELLRAUM der
## exportierten Datei (derselbe Raum, in dem die Datei später instanziert wird).
func _report(root: Node3D) -> void:
	var hull := _bounds(root, Transform3D.IDENTITY)
	print("=== GESAMTHUELLE (Modellraum) ===")
	print("  MODEL_SIZE   = Vector3(%.4f, %.4f, %.4f)" % [hull.size.x, hull.size.y, hull.size.z])
	var centre := hull.get_center()
	print("  MODEL_CENTRE = Vector3(%.4f, %.4f, %.4f)" % [centre.x, centre.y, centre.z])
	print("")
	print("=== TEILE (AABB im Modellraum) ===")
	for wanted in REPORT_NODES:
		var node := _find_named(root, wanted)
		if node == null:
			print("  %-24s FEHLT" % wanted)
			continue
		var transform := _accumulated_transform(root, node)
		var bounds := _bounds(node, transform)
		var mid := bounds.get_center()
		print("  %-24s Mitte (%.4f, %.4f, %.4f)  Groesse (%.4f, %.4f, %.4f)  von (%.4f, %.4f, %.4f) bis (%.4f, %.4f, %.4f)" % [
			node.name, mid.x, mid.y, mid.z,
			bounds.size.x, bounds.size.y, bounds.size.z,
			bounds.position.x, bounds.position.y, bounds.position.z,
			bounds.end.x, bounds.end.y, bounds.end.z])
		# Materialnamen — die Anbauteil-Skripte suchen Leuchtpunkt und Glas
		# über den Materialnamen, deshalb müssen wir wissen, wie sie heißen.
		var names := {}
		for mesh_instance in node.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mesh_instance as MeshInstance3D).mesh
			if mesh == null:
				continue
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				if material != null and material.resource_name != "":
					names[material.resource_name] = true
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			for surface in ((node as MeshInstance3D).mesh as Mesh).get_surface_count():
				var material := ((node as MeshInstance3D).mesh as Mesh).surface_get_material(surface)
				if material != null and material.resource_name != "":
					names[material.resource_name] = true
		if not names.is_empty():
			print("        Materialien: %s" % ", ".join(names.keys()))


func _find_named(node: Node, target: String) -> Node:
	if String(node.name) == target:
		return node
	for child in node.get_children():
		var found := _find_named(child, target)
		if found != null:
			return found
	return null


func _bounds(node: Node, transform: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result = transform * (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var sub := _bounds(child, transform * (child as Node3D).transform)
		if sub.size == Vector3.ZERO and not found:
			continue
		result = sub if not found else result.merge(sub)
		found = true
	return result
