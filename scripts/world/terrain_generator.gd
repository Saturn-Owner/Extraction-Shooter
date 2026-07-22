## Prozedurales Gelaende: ein Hoehenfeld aus Rauschen, als Mesh UND als
## begehbare Kollision in einem Aufruf.
##
## Das Gegenstueck zu WorldParts, nur fuer die grosse Flaeche darunter statt
## einzelne Bausteine — dieselbe Begruendung wie dort: Code statt .tscn, weil
## sich eine grosse Szenendatei bei zwei Entwicklern nicht mergen liesse.
##
## ---------------------------------------------------------------------------
## MESH UND KOLLISION TEILEN SICH DIESELBEN HOEHENWERTE
##
## Ein Gelaende, bei dem die sichtbare Form nicht zur begehbaren Form passt,
## fuehrt zu Spielern, die ueber unsichtbare Huegel stolpern oder durch
## sichtbaren Boden fallen. Deshalb wird das Hoehenfeld genau EINMAL berechnet
## (`heights_grid()`) und danach fuer Mesh UND `HeightMapShape3D` verwendet.
##
## ---------------------------------------------------------------------------
## KEINE UV-KOORDINATEN NOETIG
##
## `WorldParts.snow_material()` projiziert triplanar in WELTKOORDINATEN
## (`uv1_world_triplanar`) — das Mesh braucht deshalb gar keine eigenen UVs,
## genau wie die Quader in WorldParts. Ein Huegel ist damit vom Feld daneben
## nicht zu unterscheiden, ohne dass irgendwo eine Naht sichtbar waere.
class_name TerrainGenerator
extends RefCounted

## Kollisionsebene der Welt — muss zu WorldParts.WORLD_LAYER passen, sonst
## faellt der Spieler durch den Boden, den er sieht.
const WORLD_LAYER := 1


## Baut das Gelaende. `size` ist Breite/Tiefe in Metern, `resolution` die
## Anzahl Hoehenpunkte je Achse (Mesh und Kollision bekommen dasselbe Raster —
## mehr Punkte heisst feinere Huegel, aber auch mehr Dreiecke).
##
## `amplitude` ist der Hoehenunterschied von tiefstem zu hoechstem Punkt in
## Metern. Bewusst zurueckhaltend im Vorgabewert: Das ist eine begehbare
## Schneekarte mit Haeusern darauf, keine Gebirgskarte — zu steile Huegel
## reissen Godots 45-Grad-Grenze fuer begehbaren Boden (siehe WorldParts.ramp)
## und werden zu unsichtbaren Waenden.
##
## `terrain_seed` macht dieselbe Karte reproduzierbar — zwei Entwickler, die
## denselben Seed eintragen, sehen dasselbe Gelaende, ohne dass irgendwo eine
## Datei mit Hoehenwerten im Repo liegen muesste.
static func generate(size: Vector2, resolution: int, terrain_seed: int,
		amplitude: float, mat: Material) -> StaticBody3D:
	var samples := maxi(2, resolution)
	var heights := heights_grid(samples, terrain_seed, amplitude)

	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _build_mesh(samples, size, heights)
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	var shape := HeightMapShape3D.new()
	shape.map_width = samples
	shape.map_depth = samples
	shape.map_data = heights

	var collider := CollisionShape3D.new()
	collider.name = "Kollision"
	collider.shape = shape
	# HeightMapShape3D ist immer QUADRATISCH GERASTERT ueber map_width x
	# map_depth Punkte, aber der WELTRAUM, den es einnimmt, haengt vom Scale
	# des Kollisionsknotens ab — die Rohwerte selbst sind nur Punktabstaende
	# von 1 Meter. Deshalb hier auf die gewuenschte Kartengroesse skalieren,
	# nicht die Hoehenwerte selbst verzerren (das wuerde die Steigung
	# verfaelschen, mit der der Spieler tatsaechlich rechnen muss).
	collider.scale = Vector3(size.x / float(samples - 1), 1.0, size.y / float(samples - 1))
	body.add_child(collider)

	return body


## Ein Hoehenwert je Rasterpunkt, `samples * samples` gross, Reihe fuer Reihe
## (dieselbe Reihenfolge, die HeightMapShape3D.map_data erwartet).
##
## Zwei Rauschschichten uebereinander: eine LANGWELLIGE fuer sanfte, grosse
## Kuppen (das Gelaende als Ganzes) und eine KURZWELLIGE, schwaechere fuer
## kleine Unebenheiten obendrauf — reines Einzelrauschen sieht auf einer
## grossen Flaeche wie ein einziger Huegel aus, reine Detailschicht wie
## Waschbrett ohne grosse Form.
##
## OEFFENTLICH UND SEPARAT VON generate(): Der Karten-Generator braucht
## dieselben Hoehenwerte oft (ein Aufruf pro Haus und Baum, um sie aufs
## Gelaende zu setzen) — das Feld einmal berechnen und an sample() weiterreichen
## ist etwas anderes, als es bei jeder Platzierung neu auszurechnen.
static func heights_grid(samples: int, terrain_seed: int, amplitude: float) -> PackedFloat32Array:
	var base := FastNoiseLite.new()
	base.seed = terrain_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.01
	base.fractal_octaves = 3
	base.fractal_gain = 0.5

	var detail := FastNoiseLite.new()
	detail.seed = terrain_seed + 1
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.06
	detail.fractal_octaves = 2

	var heights := PackedFloat32Array()
	heights.resize(samples * samples)

	for z in range(samples):
		for x in range(samples):
			var combined := base.get_noise_2d(x, z) * 0.75 + detail.get_noise_2d(x, z) * 0.25
			heights[z * samples + x] = combined * amplitude

	return heights


## Baut die sichtbare Mesh aus denselben Hoehenwerten — Dreiecke, keine Naht,
## Normalen aus den Nachbarwerten berechnet (nicht nur nach oben gesetzt, sonst
## sehen Haenge aus wie flach angemalte Steigungen statt geformtes Gelaende).
static func _build_mesh(samples: int, size: Vector2, heights: PackedFloat32Array) -> ArrayMesh:
	var step_x := size.x / float(samples - 1)
	var step_z := size.y / float(samples - 1)
	var half := Vector3(size.x * 0.5, 0.0, size.y * 0.5)

	var vertices := PackedVector3Array()
	vertices.resize(samples * samples)
	for z in range(samples):
		for x in range(samples):
			vertices[z * samples + x] = Vector3(
				float(x) * step_x, heights[z * samples + x], float(z) * step_z) - half

	var normals := PackedVector3Array()
	normals.resize(samples * samples)
	for z in range(samples):
		for x in range(samples):
			# Zentrale Differenz zu den Nachbarn — am Rand faellt sie auf den
			# einseitigen Nachbarn zurueck, statt aus dem Feld zu greifen.
			var left := heights[z * samples + maxi(0, x - 1)]
			var right := heights[z * samples + mini(samples - 1, x + 1)]
			var down := heights[maxi(0, z - 1) * samples + x]
			var up := heights[mini(samples - 1, z + 1) * samples + x]
			var slope_x := (right - left) / (2.0 * step_x)
			var slope_z := (up - down) / (2.0 * step_z)
			normals[z * samples + x] = Vector3(-slope_x, 1.0, -slope_z).normalized()

	var indices := PackedInt32Array()
	indices.resize((samples - 1) * (samples - 1) * 6)
	var cursor := 0
	for z in range(samples - 1):
		for x in range(samples - 1):
			var a := z * samples + x
			var b := a + 1
			var c := a + samples
			var d := c + 1
			indices[cursor] = a; indices[cursor + 1] = c; indices[cursor + 2] = b
			indices[cursor + 3] = b; indices[cursor + 4] = c; indices[cursor + 5] = d
			cursor += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Hoehe des Gelaendes an einer Weltposition (x, z) — fuer den Karten-
## Generator, der Haeuser und Baeume nicht in der Luft oder im Boden absetzen
## will. Bilinear zwischen den vier umliegenden Rasterpunkten interpoliert,
## damit ein Haus nicht sichtbar auf einer Rasterstufe "einrastet".
##
## Nimmt das FERTIGE Hoehenfeld entgegen (siehe heights_grid()), statt es
## selbst zu berechnen — wer das fuer hundert Baeume aufruft, soll das
## Rauschen einmal auswerten, nicht hundertmal.
static func sample(heights: PackedFloat32Array, samples: int, size: Vector2,
		local_pos: Vector2) -> float:
	var u := clampf((local_pos.x + size.x * 0.5) / size.x, 0.0, 1.0) * float(samples - 1)
	var v := clampf((local_pos.y + size.y * 0.5) / size.y, 0.0, 1.0) * float(samples - 1)

	var x0 := int(floor(u))
	var z0 := int(floor(v))
	var x1 := mini(samples - 1, x0 + 1)
	var z1 := mini(samples - 1, z0 + 1)
	var fx := u - float(x0)
	var fz := v - float(z0)

	var h00 := heights[z0 * samples + x0]
	var h10 := heights[z0 * samples + x1]
	var h01 := heights[z1 * samples + x0]
	var h11 := heights[z1 * samples + x1]

	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
