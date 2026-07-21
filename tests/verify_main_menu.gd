## Prüft das Hauptmenü: Szenen laden sauber, Einstellungen lassen sich öffnen
## und schliessen, die Lautstärkeregler wirken auf die echten Audio-Busse.
##
##   godot --headless --path . --script res://tests/verify_main_menu.gd
##
## Was hier NICHT geprüft werden kann: ob das Menü gut aussieht, ob die
## Platzhalterfigur sich rund dreht, ob die Buttons sich richtig anfuehlen.
## Das muss ein Mensch im Editor ansehen.
##
## Was geprueft WERDEN kann: dass beide Szenen ohne Parserfehler laden, dass
## die Knotenpfade stimmen, die die Skripte per @onready erwarten, und dass
## Einstellungen -> Lautstaerke tatsaechlich am AudioServer ankommt statt nur
## an einem Regler, der nichts bewirkt.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	print("=== Hauptmenue pruefen ===\n")
	_run_all()


func _run_all() -> void:
	await _test_menu_scene()
	await _test_settings_panel()

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

func _test_menu_scene() -> void:
	_section("Hauptmenue-Szene")

	var scene := load("res://scenes/ui/main_menu.tscn") as PackedScene
	_check(scene != null, "Szene laedt")
	if scene == null:
		return

	var menu := scene.instantiate() as MainMenu
	_check(menu != null, "ist ein MainMenu")
	if menu == null:
		return

	root.add_child(menu)
	await process_frame

	var settings := menu.get_node_or_null("SettingsPanel") as SettingsPanel
	_check(settings != null, "SettingsPanel haengt im Baum")
	_check(settings != null and not settings.visible, "faengt versteckt an")

	var preview_box := menu.get_node_or_null("Content/Layout/Vorschau")
	_check(preview_box != null and preview_box.get_child_count() == 1,
		"die 3D-Vorschau wurde in die Vorschau-Box eingehaengt")
	_check(preview_box != null and preview_box.get_child(0) is CharacterPreview,
		"und ist eine CharacterPreview")

	var links := menu.get_node_or_null("Content/Layout/Links") as VBoxContainer
	var spielen := menu.get_node_or_null("Content/Layout/Links/Buttons/Spielen") as Button
	var einstellungen := menu.get_node_or_null("Content/Layout/Links/Buttons/Einstellungen") as Button
	_check(spielen != null and einstellungen != null, "beide Buttons stehen im Baum")

	if links != null and einstellungen != null and settings != null:
		einstellungen.pressed.emit()
		await process_frame
		_check(not links.visible, "Einstellungen blendet die Buttons aus")
		_check(settings.visible, "und zeigt das Panel")

		settings.closed.emit()
		await process_frame
		_check(links.visible, "Zurueck zeigt die Buttons wieder")

	menu.free()


func _test_settings_panel() -> void:
	_section("Lautstaerke wirkt auf den echten Bus")

	var scene := load("res://scenes/ui/settings_panel.tscn") as PackedScene
	_check(scene != null, "Szene laedt")
	if scene == null:
		return

	var panel := scene.instantiate() as SettingsPanel
	root.add_child(panel)
	await process_frame

	var world_bus := AudioServer.get_bus_index(GameAudio.WORLD_BUS)
	_check(world_bus >= 0, "GameAudio hat den Welt-Bus angelegt")

	var slider := panel.get_node_or_null("Panel/Inhalt/Lautstaerke/Welt/Slider") as HSlider
	_check(slider != null, "Welt-Regler steht im Baum")
	if slider != null:
		slider.value = 0.25
		# HSlider.value setzen loest value_changed nicht von selbst aus.
		slider.value_changed.emit(0.25)
		var expected_db := linear_to_db(0.25)
		var actual_db := AudioServer.get_bus_volume_db(world_bus)
		_check(is_equal_approx(actual_db, expected_db),
			"0.25 am Regler ergibt %.1f dB am Bus (ist %.1f)" % [expected_db, actual_db])

	# Zurueck auf volle Lautstaerke, damit der naechste Testlauf nicht auf dem
	# Rest dieses Laufs aufsetzt — Busse ueberleben, static var in GameAudio
	# auch, aber der Bus-Pegel selbst bleibt sonst leise stehen.
	AudioServer.set_bus_volume_db(world_bus, 0.0)

	var keys_list := panel.get_node_or_null("Panel/Inhalt/Tasten/Liste") as VBoxContainer
	_check(keys_list != null and keys_list.get_child_count() == SettingsPanel.ACTIONS.size(),
		"jede Aktion aus project.godot bekommt eine Zeile (%d von %d)" % [
			keys_list.get_child_count() if keys_list != null else -1,
			SettingsPanel.ACTIONS.size(),
		])

	panel.free()
