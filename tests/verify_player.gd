## Prüft Spielerszene, Testgelände, Eingabebelegung und Bewegungsrechnung.
##
##   godot --headless --path . --import --quit-after 120
##   godot --headless --path . --script res://tests/verify_player.gd
##
## Was hier NICHT geprüft werden kann: ob sich die Bewegung gut anfühlt.
## Das muss ein Mensch im Spiel beurteilen.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	print("=== Spieler und Testgelände prüfen ===\n")
	_test_input_actions()
	_test_player_scene()
	_test_level_scene()
	_test_weight_curve()
	_test_sprint_rules()

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


## Fehlende Eingabeaktionen führen sonst erst beim Spielen zu Fehlern.
func _test_input_actions() -> void:
	_section("Eingabebelegung")
	for action in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump", "toggle_mouse"]:
		var exists := InputMap.has_action(action)
		_check(exists, "Aktion '%s' ist belegt" % action)
		if exists:
			_check(not InputMap.action_get_events(action).is_empty(),
				"Aktion '%s' hat mindestens eine Taste" % action)


func _test_player_scene() -> void:
	_section("Spielerszene")
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	_check(packed != null, "player.tscn lädt")
	if packed == null:
		return

	var player: Node = packed.instantiate()
	_check(player is PlayerController, "Wurzel ist ein PlayerController")
	_check(player.get_node_or_null("CollisionShape3D") != null, "CollisionShape3D vorhanden")
	_check(player.get_node_or_null("CameraPivot") != null, "CameraPivot vorhanden")
	_check(player.get_node_or_null("CameraPivot/Camera3D") != null, "Kamera unter dem Pivot")

	var p := player as PlayerController
	_check(p.walk_speed < p.sprint_speed, "Sprint ist schneller als Gehen")
	_check(p.crouch_speed < p.walk_speed, "Ducken ist langsamer als Gehen")
	_check(p.crouch_eye_height < p.stand_eye_height, "Augenhöhe sinkt beim Ducken")

	player.free()


func _test_level_scene() -> void:
	_section("Testgelände")
	var packed: PackedScene = load("res://scenes/levels/testgelaende.tscn")
	_check(packed != null, "testgelaende.tscn lädt")
	if packed == null:
		return

	var level: Node = packed.instantiate()
	_check(level.get_node_or_null("Player") != null, "Spieler ist im Level")
	_check(level.get_node_or_null("Boden") != null, "Boden vorhanden")
	_check(level.get_node_or_null("Sonne") != null, "Licht vorhanden")
	_check(level.get_node_or_null("WorldEnvironment") != null, "Umgebung vorhanden")
	_check(level.get_node_or_null("HUD/DebugPanel/DebugLabel") != null, "Debug-Anzeige vorhanden")

	# Ohne Kollision am Boden fällt der Spieler durch die Welt.
	var boden := level.get_node_or_null("Boden/CollisionShape3D") as CollisionShape3D
	_check(boden != null and boden.shape != null, "Boden hat eine Kollisionsform")

	# Die im Projekt eingetragene Startszene muss auch existieren.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_scene != "", "Startszene ist im Projekt eingetragen")
	_check(ResourceLoader.exists(main_scene), "Startszene existiert: %s" % main_scene)

	level.free()


## Die Traglast muss stetig bremsen — keine Sprünge, nie schneller durch Gewicht.
func _test_weight_curve() -> void:
	_section("Traglast")
	var p := PlayerController.new()

	p.carried_weight_kg = 0.0
	_check(is_equal_approx(p.get_weight_factor(), 1.0), "leer = volles Tempo")

	p.carried_weight_kg = p.comfortable_weight_kg
	_check(is_equal_approx(p.get_weight_factor(), 1.0), "bis zur Komfortgrenze kein Abzug")

	var last := 1.0
	var monotonic := true
	for kg in [20.0, 26.0, 32.0, 40.0, 48.0, 60.0]:
		p.carried_weight_kg = kg
		var f := p.get_weight_factor()
		if f > last:
			monotonic = false
		last = f
	_check(monotonic, "mehr Gewicht macht nie schneller")

	p.carried_weight_kg = 999.0
	_check(p.get_weight_factor() > 0.0, "auch überladen bleibt Restbewegung möglich")

	p.free()


## Sprinten soll bewusst eingeschränkt sein, sonst rennt jeder dauernd.
func _test_sprint_rules() -> void:
	_section("Sprintregeln")
	var p := PlayerController.new()
	var forward := Vector2(0.0, -1.0)
	var backward := Vector2(0.0, 1.0)

	# is_on_floor() ist ausserhalb des Spiels immer false, deshalb prüfen wir
	# hier nur die Regeln, die unabhängig davon greifen.
	p.stamina = 0.0
	_check(not p.can_sprint(forward), "ohne Ausdauer kein Sprint")

	p.stamina = p.max_stamina
	_check(not p.can_sprint(backward), "rückwärts kein Sprint")

	p.carried_weight_kg = p.max_weight_kg + 5.0
	_check(not p.can_sprint(forward), "hoffnungslos überladen kein Sprint")

	p.free()
