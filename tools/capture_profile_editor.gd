## Bildschirmfoto des Zuschnitt-Editors im Profil — rein zur Ansicht, speichert
## nichts (kein Klick auf "Übernehmen", rührt das echte Profil nicht an).
##
##   godot --path . --script res://tools/capture_profile_editor.gd
##
## NICHT mit --headless. Siehe tools/capture_ui.gd.
extends SceneTree

const OUT_DIR := "user://ui_shots"
const SETTLE_FRAMES := 6
const TEST_IMAGE := "user://capture_profile_editor_source.png"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# Absichtlich kein Quadrat, damit im Bild sichtbar wird, dass sich
	# zuschneiden und verschieben lohnt.
	var source := Image.create(300, 180, false, Image.FORMAT_RGB8)
	for y in source.get_height():
		for x in source.get_width():
			source.set_pixel(x, y, Color(
				float(x) / source.get_width(),
				float(y) / source.get_height(),
				0.5,
			))
	source.save_png(TEST_IMAGE)

	var packed: PackedScene = load("res://scenes/ui/main_menu.tscn")
	var menu: MainMenu = packed.instantiate()
	root.add_child(menu)
	await process_frame

	var profil_badge: PanelContainer = menu.get_node("TopBar/Profil")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	profil_badge.gui_input.emit(click)
	await process_frame

	var profile_panel: ProfilePanel = menu.get_node("ProfilePanel")
	profile_panel._on_avatar_file_selected(TEST_IMAGE)
	await _shot("05_profil_zuschnitt")

	print("\nFertig: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _shot(name: String) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	if image.save_png(path) != OK:
		push_error("[capture_profile_editor] Konnte %s nicht speichern" % path)
	else:
		print("  %s -> %s" % [name, ProjectSettings.globalize_path(path)])

	if FileAccess.file_exists(TEST_IMAGE):
		DirAccess.remove_absolute(TEST_IMAGE)
