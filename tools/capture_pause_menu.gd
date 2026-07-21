## Bildschirmfoto des Pausenmenüs im echten Raid.
##
##   godot --path . --script res://tools/capture_pause_menu.gd
##
## NICHT mit --headless. Siehe tools/capture_ui.gd.
extends SceneTree

const OUT_DIR := "user://ui_shots"
const SETTLE_FRAMES := 10


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var packed: PackedScene = load("res://scenes/levels/raid_eisstadt.tscn")
	var level: Node = packed.instantiate()
	root.add_child(level)

	for i in 20:
		await process_frame

	var pause_menu: PauseMenu = level.get_node("HUD/PauseMenu")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	level._unhandled_input(event)

	await _shot("01_pause")

	var einstellungen: Button = pause_menu.get_node("MenuList/Einstellungen/Btn")
	einstellungen.pressed.emit()
	await _shot("02_pause_einstellungen")

	print("\nFertig: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _shot(name: String) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	if image.save_png(path) != OK:
		push_error("[capture_pause_menu] Konnte %s nicht speichern" % path)
		return
	print("  %s -> %s" % [name, ProjectSettings.globalize_path(path)])
