## Prüft das Pausenmenü im Raid: Esc öffnet/schliesst es, es sperrt die
## Steuerung wie jedes andere Fenster, und Einstellungen zeigt dasselbe Panel
## wie im Hauptmenü.
##
##   godot --headless --path . --script res://tests/verify_pause_menu.gd
##
## Was hier NICHT geprueft werden kann: ob es gut aussieht, ob sich Esc im
## Spielfluss richtig anfuehlt. Das muss ein Mensch im Editor testen.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	TestItems.install()
	print("=== Pausenmenue pruefen ===\n")
	_run_all()


func _run_all() -> void:
	await _test_pause_menu()

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


func _escape_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func _test_pause_menu() -> void:
	_section("Pausenmenue im Raid")

	var packed: PackedScene = load("res://scenes/levels/raid_eisstadt.tscn")
	_check(packed != null, "raid_eisstadt.tscn laedt")
	if packed == null:
		return

	var level: Node = packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var player := level.get_node_or_null("Player") as PlayerController
	var pause_menu := level.get_node_or_null("HUD/PauseMenu") as PauseMenu
	_check(player != null and pause_menu != null, "Spieler und Pausenmenue gefunden")
	if player == null or pause_menu == null:
		level.queue_free()
		await process_frame
		return

	_check(not pause_menu.is_open(), "Pausenmenue faengt versteckt an")
	_check(not player.ui_open, "Steuerung ist zu Beginn frei")

	# Esc bei keinem offenen Fenster oeffnet das Pausenmenue.
	level._unhandled_input(_escape_event())
	await process_frame
	_check(pause_menu.is_open(), "Esc oeffnet das Pausenmenue")
	_check(player.ui_open, "und sperrt die Steuerung, wie jedes andere Fenster")

	var info_panel := level.get_node("HUD/InfoPanel") as PanelContainer
	_check(not info_panel.visible,
		"und blendet die staendige Statusanzeige aus (sonst ueberlagert sie die Kopfzeile)")

	# Einstellungen im Pausenmenue zeigt dasselbe Panel wie im Hauptmenue.
	var settings := pause_menu.get_node("SettingsPanel") as SettingsPanel
	var einstellungen := pause_menu.get_node("MenuList/Einstellungen/Btn") as Button
	einstellungen.pressed.emit()
	await process_frame
	_check(settings.visible, "Einstellungen oeffnet das echte SettingsPanel")

	var close_button := settings.get_node("Panel/Inhalt/Kopf/Schliessen") as Button
	close_button.pressed.emit()
	await process_frame
	_check(not settings.visible, "und schliesst sich wieder")
	_check(pause_menu.is_open(), "das Pausenmenue selbst bleibt dabei offen")

	# Esc bei offenem Pausenmenue (kein anderes Fenster offen) schliesst es.
	level._unhandled_input(_escape_event())
	await process_frame
	_check(not pause_menu.is_open(), "Esc schliesst das Pausenmenue wieder")
	_check(not player.ui_open, "und gibt die Steuerung wieder frei")
	_check(info_panel.visible, "die Statusanzeige kommt zurueck")

	# Weiterspielen tut dasselbe wie Esc.
	pause_menu.open()
	await process_frame
	var weiterspielen := pause_menu.get_node("MenuList/Weiterspielen/Btn") as Button
	weiterspielen.pressed.emit()
	await process_frame
	_check(not pause_menu.is_open(), "Weiterspielen schliesst das Pausenmenue")

	var lobby_button := pause_menu.get_node_or_null("MenuList/ZurueckZurLobby/Btn") as Button
	_check(lobby_button != null and not lobby_button.disabled,
		"Zurueck-zur-Lobby-Knopf steht bereit")

	# queue_free() statt free(): Ein direktes free() kappt eine noch spielende
	# Schrittgeraeusch-Wiedergabe hart ab, statt ihr den Frame zum Aufraeumen
	# zu lassen — das meldete der Engine als Speicherleck beim Testende.
	level.queue_free()
	await process_frame
