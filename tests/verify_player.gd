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
	_test_ui_lock()
	_test_windows()

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
	var empty_factor := p.get_weight_factor()
	_check(empty_factor > 1.0, "leeres Inventar gibt einen Tempo-Bonus (%.2f)" % empty_factor)

	p.carried_weight_kg = p.comfortable_weight_kg
	_check(is_equal_approx(p.get_weight_factor(), 1.0),
		"an der Komfortgrenze (%.0f kg) genau Normaltempo" % p.comfortable_weight_kg)

	# Kein Sprung an der Komfortgrenze — sonst ruckelt das Tempo beim Aufheben
	# eines einzelnen Gegenstands sichtbar.
	p.carried_weight_kg = p.comfortable_weight_kg - 0.1
	var just_below := p.get_weight_factor()
	p.carried_weight_kg = p.comfortable_weight_kg + 0.1
	var just_above := p.get_weight_factor()
	_check(absf(just_below - just_above) < 0.03, "stetiger Übergang an der Komfortgrenze")

	# Das eigentliche Feedback: 6 kg drueber muss man deutlich merken.
	p.carried_weight_kg = p.comfortable_weight_kg + 6.0
	var noticeable := p.get_weight_factor()
	_check(noticeable < 0.9,
		"6 kg über der Grenze sind spürbar (Faktor %.2f)" % noticeable)

	var last := 99.0
	var monotonic := true
	for kg in [0.0, 3.0, 6.0, 12.0, 20.0, 30.0, 40.0, 60.0]:
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


## Bei offenem Fenster darf die Figur nichts mehr tun.
##
## Ohne diese Sperre loest ein Klick auf einen Gegenstand gleichzeitig einen
## Schuss aus — und wer im Dauerfeuer das Inventar oeffnet, ballert weiter.
func _test_ui_lock() -> void:
	_section("Steuerung bei offenem Fenster")

	var packed: PackedScene = load("res://scenes/player/player.tscn")
	if packed == null:
		_check(false, "player.tscn lädt")
		return

	# Ohne Fenster laesst sich der Mausmodus headless nicht pruefen (es gibt
	# keins), und ein Physikschritt ausserhalb des Baums liefert nur Fehler.
	# Geprueft wird deshalb der Zustand, den beide Fenster setzen — dass er
	# dann wirklich greift, steht direkt in den drei Abfragen im Controller.
	var p := packed.instantiate() as PlayerController
	root.add_child(p)

	_check(not p.ui_open, "Steuerung ist zu Beginn frei")

	p.is_sprinting = true
	p.set_ui_open(true)
	_check(p.ui_open, "Fenster offen sperrt die Steuerung")
	_check(not p.is_sprinting, "Sprint endet beim Öffnen")

	# Zweimal öffnen darf nichts kaputtmachen — zwei Fenster können sich
	# überlappen, ohne dass der Spieler danach gelähmt bleibt.
	p.set_ui_open(true)
	p.set_ui_open(false)
	_check(not p.ui_open, "Schliessen gibt die Steuerung wieder frei")

	root.remove_child(p)
	p.free()


## Es gibt nur noch EIN Fenster fuer Ausruestung, Gesundheit und Inventar,
## und es haengt auf Tab. Das eigene Inventarfenster ist geloescht — dieser
## Test haelt fest, dass es auch geloescht bleibt.
func _test_windows() -> void:
	_section("Fenster im Raid")

	_check(not ResourceLoader.exists("res://scenes/ui/inventory_window.tscn"),
		"das alte Inventarfenster ist weg")

	var packed: PackedScene = load("res://scenes/ui/character_window.tscn")
	_check(packed != null, "character_window.tscn lädt")
	if packed == null:
		return

	var window: Node = packed.instantiate()
	_check(window is CharacterWindow, "Wurzel ist ein CharacterWindow")
	# Die Teile, die das Ziehen braucht — frueher lagen sie im Inventarfenster.
	_check(window.get_node_or_null("Layout/Inhalt/Mitte/Inventar/Raster") is InventoryGridView,
		"Rasteransicht vorhanden")
	_check(window.get_node_or_null("DragGhost") is DragGhost, "Zeiger-Abbild vorhanden")
	_check(window.get_node_or_null("SplitPrompt") is SplitPrompt, "Mengenabfrage vorhanden")
	_check(window.get_node_or_null("ItemTooltip") is ItemTooltip, "Infoanzeige vorhanden")
	window.free()

	var level: PackedScene = load("res://scenes/levels/raid_eisstadt.tscn")
	if level == null:
		_check(false, "raid_eisstadt.tscn lädt")
		return
	var raid: Node = level.instantiate()
	_check(raid.get_node_or_null("HUD/CharacterWindow") != null,
		"das Charakterfenster hängt im HUD des Raids")
	_check(raid.get_node_or_null("HUD/InventoryWindow") == null,
		"und kein zweites Inventarfenster daneben")
	raid.free()
