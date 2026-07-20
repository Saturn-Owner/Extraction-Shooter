## Macht Bildschirmfotos der geöffneten Fenster.
##
##   godot --path . --script res://tools/capture_ui.gd
##
## NICHT mit --headless: Ohne Fenster gibt es nichts zu fotografieren.
##
## Die Bilder landen unter
##   %APPDATA%\Godot\app_userdata\Extraction Shooter\ui_shots\
##
## ---------------------------------------------------------------------------
## WOZU
##
## In CLAUDE.md steht, dass Claude nicht sehen kann, wie etwas aussieht. Das
## stimmt für das Spielgefühl weiterhin — aber ob ein Fenster überhaupt
## erscheint, ob der Hintergrund abgedunkelt wird oder ob Text abgeschnitten
## ist, lässt sich so nachsehen, statt es zu raten.
##
## Ein Mensch muss trotzdem urteilen, ob es GUT aussieht.
extends SceneTree

const OUT_DIR := "user://ui_shots"

## Wie viele Frames vor jedem Foto vergehen, damit die Oberfläche steht.
const SETTLE_FRAMES := 6


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var packed: PackedScene = load("res://scenes/levels/raid_eisstadt.tscn")
	var level: Node = packed.instantiate()
	root.add_child(level)

	# Der Raid braucht ein paar Frames, bis Ausrüstung und HUD stehen.
	for i in 20:
		await process_frame

	var player: PlayerController = level.get_node("Player")
	var loot_window: LootWindow = level.get_node("HUD/LootWindow")
	var character_window: CharacterWindow = level.get_node("HUD/CharacterWindow")

	await _shot("01_raid")

	var containers := level.get_tree().get_nodes_in_group("loot_container")
	if containers.is_empty():
		push_warning("[capture_ui] Keine Kiste im Level gefunden")
	else:
		var box: LootContainer = containers[0]
		box.open()
		loot_window.open_for(box, player.inventory)
		await _shot("02_loot")
		loot_window.close()

	character_window.open_for(player)
	await _shot("03_charakter")

	print("\nFertig: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _shot(name: String) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	if image.save_png(path) != OK:
		push_error("[capture_ui] Konnte %s nicht speichern" % path)
		return
	print("  %s -> %s" % [name, ProjectSettings.globalize_path(path)])
