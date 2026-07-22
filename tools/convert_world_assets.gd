## Bereitet die Sketchfab-Modelle für den Karten-Generator auf (Häuser + Bäume).
##
##   godot --headless --path . --script res://tools/convert_world_assets.gd
##
## Alle Quellen: siehe assets/models/world/QUELLEN.md — CC BY 4.0, per
## Sketchfab-API geprüft.
##
## Wie beim AR-15 (tools/convert_ar15_sketchfab.gd), aber TABELLENGETRIEBEN
## statt eine Datei pro Skript: Die Sketchfab-Rohdateien kommen alle im selben
## Hüllen-Muster (Sketchfab_Scene > Sketchfab_model > Teile) und brauchen
## dieselbe Behandlung (Hülle abwerfen, Texturen verkleinern, exportieren) —
## nur MASSSTAB und ZIEL unterscheiden sich je Datei.
##
## MASSSTAB IST PRO DATEI VERSCHIEDEN, UND ZWAR KRASS
##
## Eine erste Vermessung (tools/_inspect_houses.gd, seither gelöscht) ergab:
## manche Dateien liefern schon plausible Meter (house_home, barn, watchtower,
## psx_abandoned_house), andere sind 100-fach (old_house) oder 1000-fach
## (windmill) zu groß. Das ist keine Codeaufgabe, sondern Messarbeit — SCALE
## unten ist das Ergebnis, keine Annahme.
##
## ---------------------------------------------------------------------------
## AUSNAHME: windmill.glb HAT _bounds() GETÄUSCHT
##
## Im Spiel sah die Windmühle wie ein Gartenzwerg aus, kaum 1,9 m hoch — obwohl
## _bounds() unten beim Konvertieren plausible 19 x 23 x 8 m gemeldet hatte
## (genau diese Zahl stand fälschlich als Grundfläche in WorldHouse.CATALOGUE).
## Grund: Die Datei enthält die Windmühle ZWEIMAL — einmal als normale Mesh
## (Cylinder011/012, Node3D-Skalierung 0,1) und einmal als SKINNED Mesh an
## einem Skeleton3D (Object_7/9, vermutlich fuer eine nie genutzte Flügel-
## Animation gedacht). `_bounds()` läuft nur die Node3D-Transformkette ab und
## kennt weder Skin noch Skeleton-Gelenke — bei der skinned Kopie hat es
## deshalb blanke Rohgrößen ohne jede Skalierung gemeldet, eine Zahl, die mit
## der tatsächlich gerenderten (durch Bind-Pose-Skalierung UND denselben
## uebersehenen 0,1-Faktor verkleinerten) Geometrie nichts zu tun hat.
##
## Behoben durch STRIP statt durch Messkorrektur: Die ungenutzte skinned
## Kopie (samt Skeleton3D) fliegt beim Konvertieren komplett raus — sie wird
## im Spiel ohnehin nie animiert, taugt also nur als Verwirrung UND als
## unnoetige, moeglicherweise falsch platzierte Kollisionsflaeche. Übrig
## bleibt die normale Mesh, deren SCALE (siehe unten) jetzt am tatsaechlich
## gerenderten Ergebnis nachgemessen ist (Kontrollrender neben einer 1,8-m-
## Referenzfigur), nicht an _bounds()' Fehlmessung.
##
## Die Sketchfab-Vorlage zeigt zudem ZWEI Windmuehlentuerme nebeneinander
## (Cylinder011 UND Cylinder012, rund 28 m auseinander) — im Spiel gesehen:
## Bei jeder Platzierung standen deshalb immer zwei Tuerme zusammen, nie nur
## einer. Da der Karten-Generator selbst genug Haeuser verteilt, bleibt hier
## nur EIN Turm (Cylinder012 fliegt mit raus) — wer zwei nebeneinander will,
## bekommt sie ohnehin durch zwei getrennte Platzierungen.
##
## FEHLT ABSICHTLICH: "Lake Hawea House" (Azimuth Design, CC BY 4.0). Auch
## texturverkleinert 80 MB gross (652.000 Dreiecke, Photogrammetrie-Scan) —
## reisst die 50-MB-Grenze aus verify_frachthafen.gd. Siehe QUELLEN.md.
extends SceneTree

## Kantenlänge, auf die grosse Texturen verkleinert werden — siehe Begruendung
## in convert_ar15_sketchfab.gd.
const MAX_TEXTURE := 1024

const SOURCE_DIR := "C:/Users/lappe/Desktop/3d models red snow/"
const TARGET_DIR := "res://assets/models/world/houses/"
const TREE_TARGET_DIR := "res://assets/models/world/trees/"

## source: Rohdatei im SOURCE_DIR. target: Zieldatei. scale: gemessener
## Korrekturfaktor (siehe Kopfkommentar). strip: optionale Liste von Pfaden
## (relativ zum neuen Wurzelknoten "Root"), die vor dem Schreiben entfernt
## werden — fuer Datenmuell, der die Messung verfaelscht oder im Spiel nur
## stoert (siehe windmill.glb im Kopfkommentar).
const ASSETS := [
	{source = "house_home_-_53mb.glb", target = TARGET_DIR + "house_home.glb", scale = 1.0},
	{source = "old_house.glb", target = TARGET_DIR + "old_house.glb", scale = 0.01},
	{source = "old_wooden_barn_house_4.glb", target = TARGET_DIR + "old_wooden_barn_house.glb", scale = 1.0},
	{source = "old_wooden_watchtower_house_3.glb", target = TARGET_DIR + "old_wooden_watchtower_house.glb", scale = 1.0},
	{source = "psx_abandoned_house.glb", target = TARGET_DIR + "psx_abandoned_house.glb", scale = 1.0},
	{source = "windmill.glb", target = TARGET_DIR + "windmill.glb", scale = 0.01,
		strip = ["Object_4/Skeleton3D", "Object_4/Cylinder012"]},
	{source = "snow_pine_tree_and_bush_pack_lowpoly.glb", target = TREE_TARGET_DIR + "snow_pine_pack.glb", scale = 1.0},
]


func _initialize() -> void:
	for entry: Dictionary in ASSETS:
		_convert(entry)
	quit(0)


func _convert(entry: Dictionary) -> void:
	var source_path: String = SOURCE_DIR + String(entry.source)
	var target_path: String = entry.target
	var scale: float = entry.scale

	print("=== %s -> %s (Massstab %.4f) ===" % [entry.source, target_path, scale])

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(source_path, state) != OK:
		print("  FEHLER: Quelle nicht lesbar")
		return

	var scene := document.generate_scene(state)

	var parts := _find_parts_parent(scene)
	if parts == null:
		print("  FEHLER: kein Teile-Wurzelknoten gefunden")
		scene.free()
		return

	var root := Node3D.new()
	root.name = "Root"
	var carry := _accumulated_transform(scene, parts)
	for child in parts.get_children().duplicate():
		parts.remove_child(child)
		child.owner = null
		root.add_child(child)
		if child is Node3D:
			(child as Node3D).transform = carry * (child as Node3D).transform
		_own_recursive(child, root)
	scene.free()

	for doomed_path: String in entry.get("strip", []):
		var doomed := root.get_node_or_null(NodePath(doomed_path))
		if doomed != null:
			doomed.free()
		else:
			print("  WARNUNG: strip-Pfad nicht gefunden: %s" % doomed_path)

	# Der Massstab sitzt auf dem NEUEN Wurzelknoten, nicht auf den Teilen
	# selbst — dieselbe Ueberlegung wie bei AR15Viewmodel.fit_transform(): eine
	# einzige Stelle, an der die Korrektur steht.
	if not is_equal_approx(scale, 1.0):
		root.transform = Transform3D(Basis().scaled(Vector3.ONE * scale), Vector3.ZERO) * root.transform

	var shrunk := _shrink_textures(root)

	var out_document := GLTFDocument.new()
	out_document.image_format = "Lossless WebP"
	var out_state := GLTFState.new()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(target_path.get_base_dir()))
	var error := out_document.append_from_scene(root, out_state)
	if error == OK:
		error = out_document.write_to_filesystem(out_state, target_path)
	if error != OK:
		print("  FEHLER beim Schreiben: %d" % error)
		root.free()
		return

	var written := FileAccess.get_file_as_bytes(target_path)
	# root.transform selbst muss hier als Startwert rein, nicht IDENTITY —
	# sonst fehlt genau die Korrektur aus SCALE im Diagnosetext, und "Groesse
	# nach Korrektur" zeigt in Wahrheit die Groesse VOR der Korrektur. Bei
	# windmill.glb hat genau das eine 10-fach zu kleine Windmuehle als
	# plausibel aussehen lassen (siehe Kopfkommentar).
	var bounds := _bounds(root, root.transform)
	print("  Geschrieben: %.1f MB, %d Texturen verkleinert" % [written.size() / 1048576.0, shrunk])
	print("  Groesse nach Korrektur: %.2f x %.2f x %.2f m"
		% [bounds.size.x, bounds.size.y, bounds.size.z])
	root.free()


## Findet den Knoten, unter dem die eigentlichen Bauteile haengen.
##
## Die uebliche Sketchfab-Huelle ist Sketchfab_Scene > Sketchfab_model >
## <hash>_fbx > RootNode — bei FBX-Reimporten. Direkt aus Blender exportierte
## Dateien (hier: Blenderust' Modelle) haben stattdessen nur einen Knoten
## namens "root" ohne weiteres "RootNode" darunter. Deshalb zwei Versuche:
## erst das FBX-typische "RootNode" suchen, sonst den einzigen Kindknoten von
## "Sketchfab_model" nehmen.
func _find_parts_parent(node: Node) -> Node:
	var root_node := _find_named(node, "RootNode")
	if root_node != null:
		return root_node

	var model := _find_named(node, "Sketchfab_model")
	if model != null and model.get_child_count() == 1:
		return model.get_child(0)

	return null


func _find_named(node: Node, target: String) -> Node:
	if String(node.name) == target:
		return node
	for child in node.get_children():
		var found := _find_named(child, target)
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
					var scale_factor := float(MAX_TEXTURE) / float(maxi(image.get_width(), image.get_height()))
					image.resize(int(image.get_width() * scale_factor), int(image.get_height() * scale_factor),
						Image.INTERPOLATE_LANCZOS)
					count += 1
				var replacement := ImageTexture.create_from_image(image)
				seen[key] = replacement
				material.set_texture(slot, replacement)
	return count


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
