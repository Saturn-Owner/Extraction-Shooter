## Hauptmenü — das Erste, was ein Spieler sieht (siehe net_bootstrap.gd, das
## VOR dieser Szene entscheidet, ob der Prozess Server oder Client ist —
## ohne diese Weiche würde der VPS als Server versuchen, dieses Menü samt
## 3D-Vorschau zu laden, statt headless auf Verbindungen zu warten).
##
## Optik und Aufbau stammen aus der Design-Session des Kollegen
## (scenes/ui/main_menu.tscn, Charaktervorschau, Einstellungen-Panel) —
## SPIELEN verband dort noch direkt zur Solo-Karte, weil das Menü ohne
## Wissen vom Multiplayer-Zweig entstand. Jetzt meldet SPIELEN einen
## Verbindungswunsch an den Bootstrap, der die Verbindung selbst aufbaut;
## das Menü entscheidet nichts selbst (gleiches Prinzip wie zuvor beim
## codegebauten Menü, jetzt nur mit echter Szene statt Code-Aufbau).
class_name MainMenu
extends Control

signal connect_requested(ip: String, port: int)
signal solo_requested(scene_path: String)
signal quit_requested

const SOLO_RAID := "res://scenes/levels/raid_eisstadt.tscn"
## Wie im alten Menü vorbelegt: Tester klicken nur SPIELEN, ohne eine
## Adresse eintippen zu müssen.
const BETA_SERVER := "193.23.160.41"

@onready var _spielen_button: Button = $Content/Layout/Links/Buttons/Spielen
@onready var _solo_button: Button = $Content/Layout/Links/Buttons/Solo
@onready var _einstellungen_button: Button = $Content/Layout/Links/Buttons/Einstellungen
@onready var _links: VBoxContainer = $Content/Layout/Links
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _preview_box: Control = $Content/Layout/Vorschau
## Zeigt jetzt den echten Verbindungsstatus statt der ausgedachten
## "SERVER: EU-NORD-02"-Deko von vorher.
@onready var _status_label: Label = $Content/Layout/Links/Status/Server


func _ready() -> void:
	_spielen_button.pressed.connect(_on_spielen_pressed)
	_solo_button.pressed.connect(_on_solo_pressed)
	_einstellungen_button.pressed.connect(_on_einstellungen_pressed)
	_settings_panel.closed.connect(_on_settings_closed)
	_settings_panel.hide()

	# Code statt Szene: Die Vorschau baut ihre eigene 3D-Welt selbst zusammen
	# (siehe CharacterPreview), genau wie WeaponPreview an der Werkbank.
	var preview := CharacterPreview.new()
	preview.name = "Figur"
	_preview_box.add_child(preview)

	_status_label.text = "Bereit."
	# Wer gerade vom Server abgewiesen wurde, soll den Grund lesen können —
	# die Verbindung ist da längst weg.
	var reason := _net_property("rejection_reason")
	if reason != "":
		set_status(reason)


func _on_spielen_pressed() -> void:
	connect_requested.emit(BETA_SERVER, 0)


func _on_solo_pressed() -> void:
	solo_requested.emit(SOLO_RAID)


func _on_einstellungen_pressed() -> void:
	_links.hide()
	_settings_panel.open()


func _on_settings_closed() -> void:
	_links.show()


func set_status(text: String) -> void:
	_status_label.text = text


## Solange ein Verbindungsversuch läuft, soll man nicht doppelt klicken.
func set_busy(busy: bool) -> void:
	_spielen_button.disabled = busy


## Der Name kommt über den Launcher (--name) schon in Net.player_name an —
## dieses Menü hat bewusst kein eigenes Namensfeld mehr (siehe Kollegen-
## Entwurf: nur Spielen und Einstellungen funktionieren wirklich).
func entered_name() -> String:
	return _net_property("player_name")


## BEWUSST ÜBER DEN KNOTENPFAD statt über den globalen Namen `Net`: Der
## globale Name steht erst fest, wenn die Autoloads registriert sind — und
## verify_main_menu.gd laedt diese Szene teils davor (siehe dieselbe
## Begruendung in workbench_station.gd::_is_multiplayer). Ein Compile-Fehler
## hier risse die ganze Testsuite mit.
func _net_property(property: StringName) -> String:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return ""
	return String(net.get(property))
