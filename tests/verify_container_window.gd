## Prüft Kontextmenü und das schwebende Behälterfenster.
##
##   godot --headless --path . --script res://tests/verify_container_window.gd
##
## Was hier NICHT geprüft werden kann: ob sich das Fenster gut anfassen lässt,
## ob das Menü an der richtigen Stelle aufgeht und ob der Rechtsklick sich
## natürlich anfühlt. Das muss ein Mensch klicken.
##
## Was geprüft WERDEN kann: dass ein Menü nie leer aufgeht, dass zweimal
## Öffnen ein Fenster ergibt statt zwei, dass sich das Fenster nicht aus dem
## Bild schieben lässt — und dass die Szenen sauber zusammengesteckt sind.
extends SceneTree

const BACKPACK := &"backpack_wander"

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Behaelterfenster pruefen ===\n")
	_run_all()


## Getrennt, weil die Fenstertests auf einen Frame warten.
func _run_all() -> void:
	_test_entries()
	await _test_window()
	await _test_wiring()
	_test_clamp()

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


# ---------------------------------------------------------------------------

## Ein Menü, das leer aufgeht, ist ein Fehler: Der Spieler muss es wegklicken
## und hat nichts davon.
func _test_entries() -> void:
	_section("Menueeintraege")

	_check(ContextMenu.entries_for(null).is_empty(), "ohne Gegenstand kein Menue")

	var ammo := ItemStack.create(&"ammo_9x19_fmj", 30)
	_check(ContextMenu.entries_for(ammo).is_empty(),
		"eine Patrone bietet nichts an")

	var pack := ItemStack.create(BACKPACK, 1)
	var entries := ContextMenu.entries_for(pack)
	_check(entries.size() == 1, "der Rucksack bietet genau einen Eintrag (%d)" % entries.size())
	if entries.size() == 1:
		_check(entries[0].get("id") == &"oeffnen", "und der heisst 'oeffnen'")


func _test_window() -> void:
	_section("Das Fenster")

	var scene := load("res://scenes/ui/container_window.tscn") as PackedScene
	_check(scene != null, "Szene laedt")
	if scene == null:
		return

	var window := scene.instantiate() as ContainerWindow
	root.add_child(window)
	await process_frame

	_check(window != null, "ist ein ContainerWindow")
	_check(not window.is_open(), "faengt geschlossen an")

	# Nur Behaelter lassen sich oeffnen. Eine Patrone hat kein Inneres.
	var ammo := ItemStack.create(&"ammo_9x19_fmj", 30)
	_check(not window.open_for(ammo, Vector2(100, 100)),
		"eine Patrone laesst sich nicht oeffnen")
	_check(not window.is_open(), "und das Fenster bleibt zu")

	var pack := ItemStack.create(BACKPACK, 1)
	_check(window.open_for(pack, Vector2(100, 100)), "der Rucksack laesst sich oeffnen")
	_check(window.is_open(), "das Fenster steht offen")
	_check(window.view.grid == pack.container,
		"es zeigt genau das Innenraster dieses Rucksacks")

	# Zweimal derselbe Rucksack ergibt EIN Fenster, nicht zwei Ansichten auf
	# dasselbe Raster.
	window.open_for(pack, Vector2(400, 300))
	_check(window.stack == pack, "zweites Oeffnen bleibt bei demselben Rucksack")

	# Ein zweiter Rucksack loest den ersten ab.
	var other := ItemStack.create(BACKPACK, 1)
	window.open_for(other, Vector2(200, 200))
	_check(window.view.grid == other.container, "ein anderer Rucksack loest ihn ab")

	window.close()
	_check(not window.is_open(), "schliessen macht es zu")
	_check(window.view.grid == null,
		"und laesst kein Raster zurueck, in das man noch ziehen koennte")

	window.free()


## Beide Wirtfenster muessen Menue und Behaelterfenster wirklich enthalten.
##
## Ohne diese Pruefung faellt ein vergessener Knoten erst auf, wenn jemand im
## Spiel rechtsklickt — und dann stuerzt es ab.
func _test_wiring() -> void:
	_section("Verkabelung")

	for path: String in ["res://scenes/ui/character_window.tscn",
			"res://scenes/ui/loot_window.tscn"]:
		var scene := load(path) as PackedScene
		if scene == null:
			_check(false, "%s laedt" % path.get_file())
			continue

		var window := scene.instantiate()
		root.add_child(window)
		await process_frame

		var name := path.get_file()
		var menu := window.get_node_or_null("ContextMenu") as ContextMenu
		var floating := window.get_node_or_null("ContainerWindow") as ContainerWindow

		_check(menu != null, "%s hat ein Kontextmenue" % name)
		_check(floating != null, "%s hat ein Behaelterfenster" % name)

		# Zeichenreihenfolge: Beide muessen VOR dem DragGhost stehen, sonst
		# zieht man Gegenstaende hinter dem Fenster her.
		var ghost := window.get_node_or_null("DragGhost")
		if floating != null and ghost != null:
			_check(floating.get_index() < ghost.get_index(),
				"%s: das Fenster liegt unter dem Ziehbild" % name)

		# Das feste Rucksackraster ist bewusst wieder verschwunden.
		_check(window.get_node_or_null("Layout/Inhalt/Mitte/Inventar/RucksackRaster") == null
			and window.get_node_or_null("Layout/Columns/Right/BackpackView") == null,
			"%s: kein fest eingebautes Rucksackraster mehr" % name)

		window.free()


## Das Fenster darf sich nicht so weit hinausschieben lassen, dass die
## Titelleiste ausserhalb des Bildes liegt — danach bekaeme man es nie wieder
## zu fassen und auch nicht mehr zu.
func _test_clamp() -> void:
	_section("Nicht aus dem Bild")

	var panel := Vector2(360, 260)
	var screen := Vector2(1920, 1080)

	var far_right := ContainerWindow.clamp_position(Vector2(9000, 500), panel, screen)
	_check(far_right.x <= screen.x - ContainerWindow.MIN_VISIBLE.x,
		"nach rechts bleibt ein Streifen sichtbar (x = %.0f)" % far_right.x)

	var far_left := ContainerWindow.clamp_position(Vector2(-9000, 500), panel, screen)
	_check(far_left.x + panel.x >= ContainerWindow.MIN_VISIBLE.x,
		"nach links auch (rechte Kante bei %.0f)" % (far_left.x + panel.x))

	var far_down := ContainerWindow.clamp_position(Vector2(500, 9000), panel, screen)
	_check(far_down.y <= screen.y - ContainerWindow.MIN_VISIBLE.y,
		"nach unten bleibt die Titelleiste im Bild (y = %.0f)" % far_down.y)

	# Nach oben gar nicht: Dort liegt die Titelleiste, die man braucht.
	var far_up := ContainerWindow.clamp_position(Vector2(500, -9000), panel, screen)
	_check(far_up.y >= 0.0, "nach oben endet es am Bildrand (y = %.0f)" % far_up.y)

	# Mitten im Bild wird nichts verschoben.
	var free_move := ContainerWindow.clamp_position(Vector2(400, 300), panel, screen)
	_check(free_move.is_equal_approx(Vector2(400, 300)),
		"innerhalb des Bildes bleibt die Position unveraendert")
