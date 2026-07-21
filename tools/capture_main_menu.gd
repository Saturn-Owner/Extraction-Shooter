## Macht Bildschirmfotos des Hauptmenüs — Menü und geöffnete Einstellungen.
##
##   godot --path . --script res://tools/capture_main_menu.gd
##
## NICHT mit --headless: Ohne Fenster gibt es nichts zu fotografieren.
##
## Die Bilder landen unter
##   %APPDATA%\Godot\app_userdata\Extraction Shooter\ui_shots\
##
## Siehe tools/capture_ui.gd — gleiches Werkzeug, gleicher Grund: Claude kann
## nicht sehen, wie eine Oberfläche aussieht, aber ein gespeichertes Bild lesen.
## Ob es GUT aussieht, muss weiterhin ein Mensch beurteilen.
extends SceneTree

const OUT_DIR := "user://ui_shots"
const SETTLE_FRAMES := 6

## Etwas länger, damit sich die Platzhalterfigur schon sichtbar gedreht hat.
const TURN_FRAMES := 40


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var packed: PackedScene = load("res://scenes/ui/main_menu.tscn")
	var menu: MainMenu = packed.instantiate()
	root.add_child(menu)

	for i in TURN_FRAMES:
		await process_frame

	await _shot("01_hauptmenue")

	var einstellungen: Button = menu.get_node("Content/Layout/Links/Buttons/Einstellungen")
	einstellungen.pressed.emit()
	await _shot("02_einstellungen")

	print("\nFertig: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _shot(name: String) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	if image.save_png(path) != OK:
		push_error("[capture_main_menu] Konnte %s nicht speichern" % path)
		return
	print("  %s -> %s" % [name, ProjectSettings.globalize_path(path)])
