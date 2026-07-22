## Prueft TerrainGenerator: Hoehenfeld, Mesh, begehbare Kollision.
##
##   godot --headless --path . --script res://tests/verify_terrain.gd
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	print("=== Gelaende pruefen ===\n")

	_test_heights_grid()
	_test_sample_matches_grid()
	await _test_generate_builds_mesh_and_collision()
	await _test_body_rests_on_terrain()

	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


func _test_heights_grid() -> void:
	_section("Hoehenfeld")

	var samples := 9
	var amplitude := 4.0
	var heights := TerrainGenerator.heights_grid(samples, 1234, amplitude)

	_check(heights.size() == samples * samples,
		"liefert samples*samples Werte (%d von %d)" % [heights.size(), samples * samples])

	var lowest := INF
	var highest := -INF
	for h in heights:
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	_check(highest - lowest <= amplitude * 2.0 + 0.01,
		"bleibt innerhalb der eingestellten Amplitude (Spanne %.2f von hoechstens %.2f)"
			% [highest - lowest, amplitude * 2.0])

	# Derselbe Seed muss dieselbe Karte geben — sonst waere terrain_seed
	# wirkungslos und zwei Entwickler saehen unterschiedliches Gelaende.
	var repeat := TerrainGenerator.heights_grid(samples, 1234, amplitude)
	var identical := true
	for i in range(heights.size()):
		if not is_equal_approx(heights[i], repeat[i]):
			identical = false
			break
	_check(identical, "derselbe Seed ergibt dieselbe Karte")

	var different_seed := TerrainGenerator.heights_grid(samples, 5678, amplitude)
	var all_same := true
	for i in range(heights.size()):
		if not is_equal_approx(heights[i], different_seed[i]):
			all_same = false
			break
	_check(not all_same, "ein anderer Seed ergibt eine andere Karte")


func _test_sample_matches_grid() -> void:
	_section("Bilineares Abtasten")

	var samples := 5
	var size := Vector2(40.0, 40.0)
	var heights := TerrainGenerator.heights_grid(samples, 42, 3.0)

	# An einem Rasterpunkt selbst muss sample() exakt den gespeicherten Wert
	# treffen, nicht nur ungefaehr — sonst waere die Interpolation falsch
	# aufgehaengt (z.B. an der falschen Zelle verankert).
	var corner_local := Vector2(-size.x * 0.5, -size.y * 0.5)
	var corner_value := TerrainGenerator.sample(heights, samples, size, corner_local)
	_check(is_equal_approx(corner_value, heights[0]),
		"trifft die Ecke exakt (%.4f gegen %.4f)" % [corner_value, heights[0]])

	var centre_value := TerrainGenerator.sample(heights, samples, size, Vector2.ZERO)
	var middle_index := (samples / 2) * samples + samples / 2
	_check(is_equal_approx(centre_value, heights[middle_index]),
		"trifft die Mitte exakt (%.4f gegen %.4f)" % [centre_value, heights[middle_index]])

	# Ausserhalb der Karte wird geklemmt, nicht extrapoliert — ein Baum, der
	# knapp jenseits des Rands landet, soll nicht plötzlich im Nichts stehen.
	var far_outside := TerrainGenerator.sample(heights, samples, size, Vector2(9999.0, 9999.0))
	_check(is_equal_approx(far_outside, heights[heights.size() - 1]),
		"klemmt ausserhalb der Karte auf den Rand, statt zu extrapolieren")


func _test_generate_builds_mesh_and_collision() -> void:
	_section("generate() baut Mesh und Kollision")

	var mat := StandardMaterial3D.new()
	var terrain := TerrainGenerator.generate(Vector2(20.0, 20.0), 6, 7, 2.0, mat)
	root.add_child(terrain)
	await process_frame

	_check(terrain is StaticBody3D, "das Ergebnis ist ein StaticBody3D")

	var mesh_node := terrain.get_node_or_null("Mesh") as MeshInstance3D
	_check(mesh_node != null and mesh_node.mesh != null, "es gibt eine sichtbare Mesh")
	if mesh_node != null and mesh_node.mesh != null:
		_check(mesh_node.mesh.get_surface_count() == 1, "genau eine Flaeche")

	var collider := terrain.get_node_or_null("Kollision") as CollisionShape3D
	_check(collider != null and collider.shape is HeightMapShape3D,
		"die Kollision ist ein HeightMapShape3D")

	terrain.queue_free()
	await process_frame

	# --- WICKELREIHENFOLGE: DAS GELAENDE MUSS VON OBEN SICHTBAR SEIN ---
	#
	# Frueher stand hier eine Wickelreihenfolge, die geometrisch nach +Y
	# (oben) zeigte und trotzdem von Godots Rueckseitenausblendung verworfen
	# wurde — das Gelaende war komplett unsichtbar, nur die Kollision
	# stimmte noch (siehe der lange Kommentar in TerrainGenerator._build_
	# mesh()). Ein flaches Testfeld (Amplitude 0) macht die Rechnung
	# eindeutig, ohne dass Gelaende-Rauschen das Ergebnis verwaschen kann.
	var flat_mesh := TerrainGenerator._build_mesh(4, Vector2(10.0, 10.0),
		TerrainGenerator.heights_grid(4, 1, 0.0))
	_check(_first_triangle_is_front_facing_from_above(flat_mesh),
		"das erste Dreieck ist von oben sichtbar (nicht rueckseiten-ausgeblendet)")


## Der eigentliche Beweis: Ein fallender Koerper bleibt auf dem Gelaende
## liegen, statt hindurchzufallen oder darueber zu schweben — dieselbe
## Ueberlegung wie beim Ragdoll-Test (verify_character.gd): behaupten reicht
## nicht, es muss unter echter Physik nachgemessen werden.
func _test_body_rests_on_terrain() -> void:
	_section("Ein Koerper bleibt auf dem Gelaende liegen")

	var mat := StandardMaterial3D.new()
	var size := Vector2(30.0, 30.0)
	var terrain := TerrainGenerator.generate(size, 8, 99, 3.0, mat)
	root.add_child(terrain)
	await process_frame
	await physics_frame

	var samples := 8
	var heights := TerrainGenerator.heights_grid(samples, 99, 3.0)
	var expected_height := TerrainGenerator.sample(heights, samples, size, Vector2.ZERO)

	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = TerrainGenerator.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	body.add_child(shape)
	root.add_child(body)
	body.global_position = Vector3(0.0, expected_height + 5.0, 0.0)
	await process_frame

	for i in range(120):
		await physics_frame

	# Die Kugel ruht auf dem Gelaende, ihr Mittelpunkt liegt also einen Radius
	# ueber der Gelaendehoehe an dieser Stelle — nicht exakt (die Kollision
	# ist ein Raster, kein perfekter Kegel), aber deutlich naeher dran als am
	# Startpunkt 5 m darueber.
	var rest_height := body.global_position.y
	_check(absf(rest_height - (expected_height + sphere.radius)) < 0.5,
		"die Kugel ruht nahe der erwarteten Gelaendehoehe (%.2f gegen erwartet %.2f)"
			% [rest_height, expected_height + sphere.radius])

	body.queue_free()
	terrain.queue_free()
	await process_frame


## Prueft die Wickelreihenfolge des allerersten Dreiecks GEOMETRISCH, ohne
## zu rendern (headless kann das nicht, siehe render_viewmodel.gd) — das
## Kreuzprodukt der beiden Kanten muss in die Richtung zeigen, die Godot bei
## diesem Kamera-/Weltachsen-Setup tatsaechlich als Vorderseite behandelt.
##
## AN EINEM ECHTEN RENDERBILD NACHGEMESSEN, NICHT GERATEN: Mit der falschen
## (aber geometrisch "logisch" wirkenden) Reihenfolge kreuzt das Ergebnis
## nach +Y — und war trotzdem komplett unsichtbar. Erst -Y liess das
## Gelaende im Bild erscheinen. Diese Pruefung haelt genau diesen Befund
## fest, damit ein zukuenftiger "logischer" Umbau ihn nicht wieder umdreht,
## ohne dass es auffaellt.
func _first_triangle_is_front_facing_from_above(mesh: ArrayMesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.size() < 3:
		return false

	var v0 := vertices[indices[0]]
	var v1 := vertices[indices[1]]
	var v2 := vertices[indices[2]]
	var cross := (v1 - v0).cross(v2 - v0)
	return cross.y < -0.0001
