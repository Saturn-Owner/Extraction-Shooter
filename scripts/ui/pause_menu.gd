## Pausenmenü im Raid — Esc öffnet es, wenn kein anderes Fenster offen ist.
##
## Gleiche Optik wie das Hauptmenü (scripts/ui/main_menu.gd) — Eckklammern,
## Profil-Badge, Statuszeile, derselbe Button-Stil — nur mit drei statt vier
## Punkten: Weiterspielen, Einstellungen (dasselbe SettingsPanel wie im
## Hauptmenü) und Zurück zur Lobby.
##
## opened()/closed() folgen demselben Vertrag wie LootWindow/CharacterWindow
## (siehe scripts/levels/raid_level.gd), damit sich RaidLevel um Mausfang und
## Spielersteuerung kümmert, ohne dass dieses Skript davon etwas wissen muss.
class_name PauseMenu
extends Control

signal opened()
signal closed()

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var _menu_list: VBoxContainer = $MenuList
@onready var _weiterspielen_button: Button = $MenuList/Weiterspielen/Btn
@onready var _einstellungen_button: Button = $MenuList/Einstellungen/Btn
@onready var _lobby_button: Button = $MenuList/ZurueckZurLobby/Btn
@onready var _settings_panel: SettingsPanel = $SettingsPanel


func _ready() -> void:
	hide()
	_weiterspielen_button.pressed.connect(_on_weiterspielen_pressed)
	_einstellungen_button.pressed.connect(_on_einstellungen_pressed)
	_lobby_button.pressed.connect(_on_lobby_pressed)
	_settings_panel.closed.connect(_on_settings_closed)
	_settings_panel.hide()


func open() -> void:
	_menu_list.show()
	_settings_panel.hide()
	show()
	opened.emit()


func close() -> void:
	_settings_panel.hide()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _on_weiterspielen_pressed() -> void:
	close()


func _on_einstellungen_pressed() -> void:
	_menu_list.hide()
	_settings_panel.open()


func _on_settings_closed() -> void:
	_menu_list.show()


func _on_lobby_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
