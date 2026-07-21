## Hauptmenü. Erste Szene des Spiels (siehe project.godot, run/main_scene).
##
## Nur zwei Menüpunkte funktionieren wirklich: Spielen und Einstellungen.
## Store/Shop und Statistiken/Profil aus dem ursprünglichen Entwurf fehlen
## bewusst — es gibt weder einen Händler noch Spielerfortschritt im Projekt,
## ein Knopf ins Leere wäre schlimmer als gar keiner.
##
## Die Statuszeile (Server/Ping/Build) ist reine Deko ohne echten Bezug —
## das Spiel ist noch Singleplayer, siehe CLAUDE.md Grundsatz 2.
class_name MainMenu
extends Control

const RAID_SCENE := "res://scenes/levels/raid_eisstadt.tscn"

@onready var _spielen_button: Button = $Content/Layout/Links/Buttons/Spielen
@onready var _einstellungen_button: Button = $Content/Layout/Links/Buttons/Einstellungen
@onready var _links: VBoxContainer = $Content/Layout/Links
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _preview_box: Control = $Content/Layout/Vorschau


func _ready() -> void:
	_spielen_button.pressed.connect(_on_spielen_pressed)
	_einstellungen_button.pressed.connect(_on_einstellungen_pressed)
	_settings_panel.closed.connect(_on_settings_closed)
	_settings_panel.hide()

	# Code statt Szene: Die Vorschau baut ihre eigene 3D-Welt selbst zusammen
	# (siehe CharacterPreview), genau wie WeaponPreview an der Werkbank.
	var preview := CharacterPreview.new()
	preview.name = "Figur"
	_preview_box.add_child(preview)


func _on_spielen_pressed() -> void:
	get_tree().change_scene_to_file(RAID_SCENE)


func _on_einstellungen_pressed() -> void:
	_links.hide()
	_settings_panel.open()


func _on_settings_closed() -> void:
	_links.show()
