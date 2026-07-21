## Einstellungen: Lautstärke und eine reine Anzeige der Tastenbelegung.
##
## Lautstärke greift direkt auf die beiden Busse aus GameAudio zu (siehe
## scripts/audio/game_audio.gd) — Master und Welt. Es gibt noch kein
## Speichersystem im Projekt (RaidManager.to_dict()/from_dict() betreffen nur
## das Lager), darum gilt jede Änderung hier nur für die laufende Sitzung und
## setzt sich nach einem Neustart zurück.
##
## Die Tastenbelegung steht schon vollständig in project.godot (InputMap) —
## hier wird sie nur ausgelesen und angezeigt, nicht verändert. Neu belegen
## wäre ein eigenes Stück Arbeit (InputMap zur Laufzeit umschreiben und
## dauerhaft sichern) und wartet auf das Speichersystem.
class_name SettingsPanel
extends Control

signal closed()

## Reihenfolge und Beschriftung der Aktionen aus project.godot.
const ACTIONS := [
	{action = &"move_forward", label = "Vorwärts"},
	{action = &"move_back", label = "Rückwärts"},
	{action = &"move_left", label = "Links"},
	{action = &"move_right", label = "Rechts"},
	{action = &"sprint", label = "Sprinten"},
	{action = &"crouch", label = "Ducken"},
	{action = &"jump", label = "Springen"},
	{action = &"fire", label = "Feuern"},
	{action = &"aim", label = "Zielen"},
	{action = &"reload", label = "Nachladen"},
	{action = &"interact", label = "Interagieren"},
	{action = &"fire_mode", label = "Feuermodus"},
	{action = &"toggle_mouse", label = "Maus umschalten"},
]

@onready var _master_slider: HSlider = $Panel/Inhalt/Lautstaerke/Master/Slider
@onready var _world_slider: HSlider = $Panel/Inhalt/Lautstaerke/Welt/Slider
@onready var _keys_list: VBoxContainer = $Panel/Inhalt/Tasten/Liste
@onready var _back_button: Button = $Panel/Inhalt/Zurueck


func _ready() -> void:
	GameAudio.ensure_buses()

	_master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index("Master")))
	_master_slider.value_changed.connect(_on_master_changed)

	var world_bus := AudioServer.get_bus_index(GameAudio.WORLD_BUS)
	_world_slider.value = db_to_linear(AudioServer.get_bus_volume_db(world_bus))
	_world_slider.value_changed.connect(_on_world_changed)

	_back_button.pressed.connect(_on_back_pressed)

	_build_key_list()


func open() -> void:
	show()


func _on_master_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))


func _on_world_changed(value: float) -> void:
	var world_bus := AudioServer.get_bus_index(GameAudio.WORLD_BUS)
	AudioServer.set_bus_volume_db(world_bus, linear_to_db(value))


func _on_back_pressed() -> void:
	hide()
	closed.emit()


func _build_key_list() -> void:
	for entry in ACTIONS:
		var action: StringName = entry.action
		if not InputMap.has_action(action):
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var caption := Label.new()
		caption.text = entry.label
		caption.custom_minimum_size = Vector2(140, 0)
		caption.add_theme_color_override("font_color", Color(0.60, 0.63, 0.67))
		row.add_child(caption)

		var key := Label.new()
		key.text = _key_text(action)
		key.add_theme_color_override("font_color", Color(0.906, 0.890, 0.847))
		row.add_child(key)

		_keys_list.add_child(row)


## Erste zugewiesene Taste als lesbarer Text, oder "—" ohne Zuweisung.
func _key_text(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "—"
	return events[0].as_text().trim_suffix(" - Physical")
