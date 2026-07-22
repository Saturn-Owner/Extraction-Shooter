## Prueft WorldPath: Wegerzeugung, Abstandsberechnung, sichtbare Mesh.
##
##   godot --headless --path . --script res://tests/verify_world_path.gd
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	print("=== Waldwege pruefen ===\n")

	_test_generate_reaches_edges()
	_test_distance_to_path()
	_test_build_mesh()

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


func _test_generate_reaches_edges() -> void:
	_section("generate() erzeugt Wege bis zum Kartenrand")

	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var map_size := Vector2(200.0, 200.0)
	var paths: Array = WorldPath.generate(rng, map_size, 3)

	_check(paths.size() == 3, "liefert die angeforderte Anzahl Wege (%d von 3)" % paths.size())

	var half := map_size * 0.5
	for path: Array in paths:
		_check(path.size() >= 2, "ein Weg hat mindestens Start und Ziel")
		var start: Vector2 = path[0]
		var target: Vector2 = path[path.size() - 1]
		_check(_on_edge(start, half), "der Weg beginnt am Kartenrand (%s)" % start)
		_check(_on_edge(target, half), "der Weg endet am Kartenrand (%s)" % target)

		# Kein Sprung zwischen zwei Wegpunkten, der viel groesser ist als die
		# Schrittweite — sonst waere der Weg irgendwo abgerissen statt
		# durchgehend gelaufen.
		var max_gap := 0.0
		for i in range(path.size() - 1):
			max_gap = maxf(max_gap, (path[i + 1] - path[i]).length())
		_check(max_gap <= 6.0 + 0.01, "keine Wegpunkte weiter als die Schrittweite auseinander (%.2f)" % max_gap)


func _on_edge(point: Vector2, half: Vector2) -> bool:
	return is_equal_approx(absf(point.x), half.x) or is_equal_approx(absf(point.y), half.y)


func _test_distance_to_path() -> void:
	_section("distance_to_path()")

	var straight: Array = [Vector2(-10.0, 0.0), Vector2(10.0, 0.0)]

	_check(is_equal_approx(WorldPath.distance_to_path(Vector2(0.0, 0.0), straight), 0.0),
		"ein Punkt auf dem Weg hat Abstand 0")

	_check(is_equal_approx(WorldPath.distance_to_path(Vector2(0.0, 4.0), straight), 4.0),
		"seitlicher Abstand zur Mitte des Wegs stimmt")

	# Ausserhalb der Endpunkte zaehlt der Abstand zum naechsten Endpunkt, nicht
	# zur verlaengerten Linie — sonst waere ein Weg unendlich lang gedacht.
	var to_end := WorldPath.distance_to_path(Vector2(15.0, 0.0), straight)
	_check(is_equal_approx(to_end, 5.0),
		"Abstand jenseits des Wegendes zaehlt zum Endpunkt (%.2f gegen erwartet 5.0)" % to_end)


func _test_build_mesh() -> void:
	_section("build_mesh() baut eine hoehenfolgende Flaeche")

	var samples := 4
	var map_size := Vector2(10.0, 10.0)
	var heights := TerrainGenerator.heights_grid(samples, 3, 0.0)
	var straight: Array = [Vector2(-2.0, 0.0), Vector2(2.0, 0.0)]
	var mat := StandardMaterial3D.new()

	var view := WorldPath.build_mesh(straight, heights, samples, map_size, mat)
	_check(view.mesh != null, "es gibt eine Mesh")

	if view.mesh != null:
		var arrays := view.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

		_check(vertices.size() == 4, "ein Teilstueck ergibt vier Eckpunkte (%d)" % vertices.size())
		_check(indices.size() == 6, "ein Teilstueck ergibt zwei Dreiecke (%d Indizes)" % indices.size())

		# Bei einem flachen Hoehenfeld (Amplitude 0) liegen alle Ecken auf
		# derselben Hoehe plus dem festen LIFT-Abstand.
		var expected_y := TerrainGenerator.sample(heights, samples, map_size, Vector2.ZERO) \
			+ WorldPath.LIFT
		var all_lifted := true
		for v in vertices:
			if not is_equal_approx(v.y, expected_y):
				all_lifted = false
		_check(all_lifted, "alle Ecken liegen auf Gelaendehoehe plus LIFT (erwartet %.3f)" % expected_y)

		_check(_first_triangle_is_front_facing_from_above(vertices, indices),
			"das erste Dreieck ist von oben sichtbar (nicht rueckseiten-ausgeblendet)")


## Dieselbe Pruefung wie in verify_terrain.gd, aus demselben Grund: die
## Wickelreihenfolge entscheidet ueber Sichtbarkeit, unabhaengig vom NORMAL-
## Array (siehe TerrainGenerator._build_mesh()).
func _first_triangle_is_front_facing_from_above(vertices: PackedVector3Array,
		indices: PackedInt32Array) -> bool:
	if indices.size() < 3:
		return false
	var v0 := vertices[indices[0]]
	var v1 := vertices[indices[1]]
	var v2 := vertices[indices[2]]
	var cross := (v1 - v0).cross(v2 - v0)
	return cross.y < -0.0001
