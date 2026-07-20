## Zieht einen Container aus dem grossen Modellpaket heraus.
##
##   godot --headless --path . --script res://tools/extract_containers.gd
##
## ---------------------------------------------------------------------------
## WARUM ES DAS BRAUCHT
##
## `container_pack.glb` ist 675 MB gross — und das sind fast ausschliesslich
## Texturen: 40 PNGs zu je rund 28 MB. Die Geometrie selbst ist winzig.
##
## So kann die Datei nicht ins Repo: GitHub weist jede Datei ueber 100 MB beim
## Push ab. Also wird herausgeschnitten, was wirklich gebraucht wird — eine
## Mesh und drei Texturen. Ziel: unter 10 MB.
##
## ---------------------------------------------------------------------------
## DER TRICK BEIM LADEN
##
## Alle vierzig Texturen zu dekodieren waeren mehrere Gigabyte im Speicher.
## `handle_binary_image = HANDLE_BINARY_DISCARD_TEXTURES` laesst Godot nur die
## Geometrie laden. Die drei gebrauchten Bilder werden getrennt aus dem
## Binaerblock geholt: JSON-Kopf lesen, die bufferView-Bereiche ausrechnen,
## genau diese Bytes herausschneiden.
##
## ---------------------------------------------------------------------------
## UND WARUM DIE FARBE RAUSKOMMT
##
## Die BaseColor hat die Containerfarbe eingebacken. Rot ueber einen bereits
## rostroten Container multipliziert gibt Matsch. Deshalb wird sie zu
## Graustufen entfaerbt — Rost, Dellen, Kratzer und Streifen bleiben, die Farbe
## verschwindet. Eingefaerbt wird erst im Material, und dann teilen sich ALLE
## Farben dieselbe Textur.
extends SceneTree

const SOURCE := "C:/Users/Anwender/Downloads/container_pack.glb"
const OUT_DIR := "res://assets/models/world"

## Welches Material die Geometrie und die gemeinsamen Karten liefert.
const WANTED := "20Ft_Generic_Old"

## Die Originalvarianten, die zusaetzlich herauskommen.
##
## DER GRUND, WARUM DAS BILLIG IST: `20Ft_Generic_Var2` und `Var3` zeigen im
## glTF auf DIESELBE Normalenkarte und dasselbe ORM wie `Generic_Old` — sie
## unterscheiden sich nur im Anstrich. Jede weitere Variante kostet damit eine
## einzige Textur statt drei, und sie passt garantiert auf dieselbe Mesh.
const VARIANTS := ["20Ft_Generic_Old", "20Ft_Generic_Var2", "20Ft_Generic_Var3"]

## Kantenlaenge der ausgegebenen Texturen. 2048 ist der Punkt, an dem die
## Wellblechrippen noch scharf sind und die Datei noch klein bleibt.
const TEXTURE_SIZE := 2048

## Ein echter 20-Fuss-Container. Danach wird geprueft, ob der Massstab stimmt.
const REAL_SIZE := Vector3(6.058, 2.591, 2.438)


func _initialize() -> void:
	_run()


func _run() -> void:
	if not FileAccess.file_exists(SOURCE):
		printerr("Nicht gefunden: ", SOURCE)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var meta := _read_gltf_json()
	if meta.is_empty():
		quit(1)
		return

	if not _extract_textures(meta):
		quit(1)
		return

	if not await _extract_mesh():
		quit(1)
		return

	print("\nFertig. Was jetzt in %s liegt, ersetzt den Quader." % OUT_DIR)
	quit(0)


# ---------------------------------------------------------------------------
# Den glTF-Kopf selbst lesen
# ---------------------------------------------------------------------------

## Liest den JSON-Block und merkt sich, wo der Binaerblock anfaengt.
##
## Eine .glb ist: 12 Byte Kopf, dann Bloecke aus je 8 Byte Kopf und Inhalt.
## Der erste Block ist JSON, der zweite die Rohdaten.
func _read_gltf_json() -> Dictionary:
	var file := FileAccess.open(SOURCE, FileAccess.READ)
	if file == null:
		printerr("Nicht lesbar: ", SOURCE)
		return {}

	if file.get_32() != 0x46546C67:  # "glTF"
		printerr("Keine gueltige .glb")
		return {}
	file.get_32()  # Version
	file.get_32()  # Gesamtlaenge

	var json_length := file.get_32()
	file.get_32()  # Blocktyp JSON
	var json_text := file.get_buffer(json_length).get_string_from_utf8()

	var binary_length := file.get_32()
	file.get_32()  # Blocktyp BIN
	var binary_start := file.get_position()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		printerr("JSON-Block nicht lesbar")
		return {}

	print("glTF gelesen: %d Meshes, %d Materialien, %d Bilder" % [
		(parsed.get("meshes", []) as Array).size(),
		(parsed.get("materials", []) as Array).size(),
		(parsed.get("images", []) as Array).size()])
	print("Binaerblock: %.0f MB ab Byte %d\n" % [binary_length / 1048576.0, binary_start])

	return {gltf = parsed, binary_start = binary_start}


# ---------------------------------------------------------------------------
# Texturen
# ---------------------------------------------------------------------------

func _extract_textures(meta: Dictionary) -> bool:
	var gltf: Dictionary = meta.gltf
	var material := _find_material(gltf, WANTED)
	if material.is_empty():
		printerr("Material '%s' nicht im Paket" % WANTED)
		return false

	var pbr: Dictionary = material.get("pbrMetallicRoughness", {})

	# Die gemeinsamen Karten: einmal, fuer alle Varianten.
	var shared := [
		{feld = "orm", texture = pbr.get("metallicRoughnessTexture", {})},
		{feld = "normal", texture = material.get("normalTexture", {})},
	]
	for job: Dictionary in shared:
		if not _save_texture(gltf, meta.binary_start, job.texture,
				"container_20ft_%s" % job.feld, false):
			return false

	# Die entfaerbte Fassung bleibt: Sie traegt jede beliebige Farbe, auch
	# solche, die im Paket gar nicht vorkommen.
	if not _save_texture(gltf, meta.binary_start, pbr.get("baseColorTexture", {}),
			"container_20ft_basecolor", true):
		return false

	# Und die Originalanstriche.
	print("")
	for index in range(VARIANTS.size()):
		var name: String = VARIANTS[index]
		var entry := _find_material(gltf, name)
		if entry.is_empty():
			printerr("Variante '%s' nicht im Paket" % name)
			return false
		var entry_pbr: Dictionary = entry.get("pbrMetallicRoughness", {})
		if not _save_texture(gltf, meta.binary_start,
				entry_pbr.get("baseColorTexture", {}),
				"container_20ft_lack%d" % index, false, name):
			return false

	return true


## Schneidet eine Textur heraus, bearbeitet sie und schreibt sie weg.
##
## Gibt beim Anstrich zusaetzlich die mittlere Farbe aus — sonst weiss niemand,
## welche Farben man sich da eigentlich geholt hat, ohne die Datei zu oeffnen.
func _save_texture(gltf: Dictionary, binary_start: int, texture: Dictionary,
		file_name: String, desaturate: bool, label: String = "") -> bool:
	if texture.is_empty():
		printerr("Textur '%s' fehlt im Material" % file_name)
		return false

	var image := _load_image(gltf, binary_start, int(texture.get("index", -1)))
	if image == null:
		return false

	var before := image.get_size()

	# Entfaerben: Luminanz nach Rec. 709, also so, wie das Auge Helligkeit
	# gewichtet. Ein einfacher Mittelwert wuerde Rot zu dunkel und Gruen zu
	# hell machen, und der Rost saehe danach falsch aus.
	if desaturate:
		_desaturate(image)

	if image.get_width() > TEXTURE_SIZE:
		image.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)

	var path := "%s/%s.webp" % [OUT_DIR, file_name]
	# WebP statt JPEG: Bei Normalenkarten sind JPEG-Artefakte als Griesel auf
	# der Oberflaeche sichtbar, weil die Kanaele Richtungen sind und kein Bild.
	if image.save_webp(ProjectSettings.globalize_path(path), true, 0.92) != OK:
		printerr("Konnte nicht speichern: ", path)
		return false

	var size_kb := FileAccess.open(path, FileAccess.READ).get_length() / 1024.0
	var note := "   (entfaerbt)" if desaturate else ""
	if label != "":
		var avg := _average_colour(image)
		note = "   %s  mittlere Farbe #%s" % [label, avg.to_html(false)]

	print("  %-24s %dx%d -> %dx%d   %.0f KB%s" % [
		file_name, before.x, before.y, image.get_width(), image.get_height(),
		size_kb, note])
	return true


## Die mittlere Farbe einer Textur, aus Stichproben.
func _average_colour(image: Image) -> Color:
	var total := Color(0, 0, 0)
	var samples := 400
	for i in range(samples):
		var x := (i * 137) % image.get_width()
		var y := (i * 271) % image.get_height()
		var c := image.get_pixel(x, y)
		total += Color(c.r, c.g, c.b)
	return Color(total.r / samples, total.g / samples, total.b / samples)


func _find_material(gltf: Dictionary, wanted: String) -> Dictionary:
	for entry in gltf.get("materials", []):
		if String((entry as Dictionary).get("name", "")) == wanted:
			return entry
	return {}


## Holt genau die Bytes eines Bildes aus dem Binaerblock.
func _load_image(gltf: Dictionary, binary_start: int, texture_index: int) -> Image:
	if texture_index < 0:
		return null

	var textures: Array = gltf.get("textures", [])
	if texture_index >= textures.size():
		return null
	var source := int((textures[texture_index] as Dictionary).get("source", -1))

	var images: Array = gltf.get("images", [])
	if source < 0 or source >= images.size():
		return null
	var entry: Dictionary = images[source]

	var views: Array = gltf.get("bufferViews", [])
	var view_index := int(entry.get("bufferView", -1))
	if view_index < 0 or view_index >= views.size():
		printerr("Bild '%s' liegt nicht im Binaerblock" % entry.get("name", "?"))
		return null
	var view: Dictionary = views[view_index]

	var file := FileAccess.open(SOURCE, FileAccess.READ)
	file.seek(binary_start + int(view.get("byteOffset", 0)))
	var raw := file.get_buffer(int(view.get("byteLength", 0)))
	file.close()

	var image := Image.new()
	var mime := String(entry.get("mimeType", "image/png"))
	var err := image.load_png_from_buffer(raw) if mime.ends_with("png") \
		else image.load_jpg_from_buffer(raw)
	if err != OK:
		printerr("Bild nicht dekodierbar: ", entry.get("name", "?"))
		return null
	return image


## Zieht die Farbe heraus und behaelt nur die Helligkeit.
func _desaturate(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y)
			var luma := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			image.set_pixel(x, y, Color(luma, luma, luma, c.a))


# ---------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------

## Laedt das Paket OHNE Texturen und speichert die eine gebrauchte Mesh.
func _extract_mesh() -> bool:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	# Ohne das dekodiert Godot vierzig Texturen und braucht Gigabyte.
	state.handle_binary_image = GLTFState.HANDLE_BINARY_DISCARD_TEXTURES

	print("\nLade Geometrie (ohne Texturen)...")
	if doc.append_from_file(SOURCE, state) != OK:
		printerr("Paket nicht ladbar")
		return false

	var scene := doc.generate_scene(state)
	if scene == null:
		printerr("Szene nicht erzeugbar")
		return false
	root.add_child(scene)
	await process_frame

	var found := _find_mesh_instance(scene, WANTED)
	if found == null:
		printerr("Mesh '%s' nicht gefunden" % WANTED)
		scene.free()
		return false

	var mesh := found.mesh
	var box := mesh.get_aabb()
	var world := found.global_transform.basis * box.size

	print("\nGefunden: %s" % found.name)
	print("  Rohmasse:   %.3f x %.3f x %.3f" % [box.size.x, box.size.y, box.size.z])
	print("  Mit Knoten: %.3f x %.3f x %.3f" % [absf(world.x), absf(world.y), absf(world.z)])
	print("  Soll:       %.3f x %.3f x %.3f" % [REAL_SIZE.x, REAL_SIZE.y, REAL_SIZE.z])
	print("  Ursprung:   %.3f %.3f %.3f" % [box.position.x, box.position.y, box.position.z])
	print("  Flaechen:   %d" % mesh.get_surface_count())

	var path := "%s/container_20ft.res" % OUT_DIR
	if ResourceSaver.save(mesh, path) != OK:
		printerr("Mesh nicht speicherbar")
		scene.free()
		return false

	var size_kb := FileAccess.open(path, FileAccess.READ).get_length() / 1024.0
	print("\nGeschrieben: %s   %.0f KB" % [path, size_kb])

	scene.free()
	return true


func _find_mesh_instance(node: Node, wanted: String) -> MeshInstance3D:
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		if instance.name.contains(wanted) or instance.mesh.resource_name.contains(wanted):
			return instance
		for i in range(instance.mesh.get_surface_count()):
			var mat := instance.mesh.surface_get_material(i)
			if mat != null and mat.resource_name.contains(wanted):
				return instance

	for child in node.get_children():
		var hit := _find_mesh_instance(child, wanted)
		if hit != null:
			return hit
	return null
