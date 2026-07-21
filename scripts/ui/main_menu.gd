## Hauptmenü. Erste Szene des Spiels (siehe project.godot, run/main_scene).
##
## Layout und Aufbau folgen bewusst 1:1 der Design-Vorlage (vier Menüpunkte,
## Profil-Badge, Eckklammern, Statuszeile unten rechts). Zwei der vier Punkte
## haben aber noch kein System dahinter: Store/Shop und Statistiken/Profil
## öffnen ein InfoPanel, das ehrlich sagt, dass es das noch nicht gibt, statt
## wie im Entwurf erfundene Zahlen zu zeigen. Spielen und Einstellungen
## behalten ihre echte Funktion.
##
## Die Statuszeile (Server/Ping/Build) ist reine Deko ohne echten Bezug —
## das Spiel ist noch Singleplayer, siehe CLAUDE.md Grundsatz 2.
##
## Das Profil-Abzeichen oben links ist klickbar und öffnet ProfilePanel zum
## Bearbeiten von Namen und Bild (siehe PlayerProfile) — echte, gespeicherte
## Werte statt der reinen Deko-Angaben im Rest der Kopfzeile.
class_name MainMenu
extends Control

const RAID_SCENE := "res://scenes/levels/raid_eisstadt.tscn"

const STORE_INDEX := "02"
const STORE_TITLE := "STORE / SHOP"
const STORE_BODY := "Es gibt noch keinen Händler im Spiel. Waffen, Aufsätze, Rüstung und Verbrauchsgüter kaufen ist als System geplant, aber noch nicht gebaut."

const STATS_INDEX := "03"
const STATS_TITLE := "STATISTIKEN / PROFIL"
const STATS_BODY := "Es gibt noch keinen Spielerfortschritt im Spiel. Level, K/D und Einsatzstatistik sind als System geplant, aber noch nicht gebaut."

## Grad pro Sekunde für das Pulsieren des Punkts neben "Spielen".
const PULSE_SPEED := 4.4

@onready var _menu_list: VBoxContainer = $MenuList
@onready var _spielen_button: Button = $MenuList/Spielen/Btn
@onready var _store_button: Button = $MenuList/Store/Btn
@onready var _statistiken_button: Button = $MenuList/Statistiken/Btn
@onready var _einstellungen_button: Button = $MenuList/Einstellungen/Btn
@onready var _pulse_dot: Panel = $MenuList/Spielen/Row/Inhalt/PulseDot
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _info_panel: InfoPanel = $InfoPanel
@onready var _profile_panel: ProfilePanel = $ProfilePanel
@onready var _preview_box: CenterContainer = $Vorschau

@onready var _profil_badge: PanelContainer = $TopBar/Profil
@onready var _callsign_label: Label = $TopBar/Profil/ProfilInner/ProfilText/Callsign
@onready var _avatar_label: Label = $TopBar/Profil/ProfilInner/Avatar/AvatarLabel
@onready var _avatar_texture: TextureRect = $TopBar/Profil/ProfilInner/Avatar/AvatarTexture

var _pulse_time := 0.0


func _ready() -> void:
	_spielen_button.pressed.connect(_on_spielen_pressed)
	_store_button.pressed.connect(_on_store_pressed)
	_statistiken_button.pressed.connect(_on_statistiken_pressed)
	_einstellungen_button.pressed.connect(_on_einstellungen_pressed)
	_settings_panel.closed.connect(_on_panel_closed)
	_info_panel.closed.connect(_on_panel_closed)
	_profile_panel.closed.connect(_on_profile_closed)
	_profil_badge.gui_input.connect(_on_profil_gui_input)
	_settings_panel.hide()
	_info_panel.hide()
	_profile_panel.hide()

	_refresh_profile_badge()

	# Code statt Szene: Die Vorschau baut ihre eigene 3D-Welt selbst zusammen
	# (siehe CharacterPreview), genau wie WeaponPreview an der Werkbank.
	var preview := CharacterPreview.new()
	preview.name = "Figur"
	_preview_box.add_child(preview)


func _refresh_profile_badge() -> void:
	_callsign_label.text = PlayerProfile.get_display_name()

	var texture := PlayerProfile.load_avatar_texture()
	if texture != null:
		_avatar_texture.texture = texture
		_avatar_texture.show()
		_avatar_label.hide()
	else:
		_avatar_texture.hide()
		_avatar_label.show()


func _on_profil_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	_menu_list.hide()
	_profile_panel.open()


func _on_profile_closed() -> void:
	_refresh_profile_badge()
	_menu_list.show()


func _process(delta: float) -> void:
	_pulse_time += delta * PULSE_SPEED
	_pulse_dot.modulate.a = 0.4 + 0.6 * ((sin(_pulse_time) + 1.0) * 0.5)


func _on_spielen_pressed() -> void:
	get_tree().change_scene_to_file(RAID_SCENE)


func _on_store_pressed() -> void:
	_menu_list.hide()
	_info_panel.open(STORE_INDEX, STORE_TITLE, STORE_BODY)


func _on_statistiken_pressed() -> void:
	_menu_list.hide()
	_info_panel.open(STATS_INDEX, STATS_TITLE, STATS_BODY)


func _on_einstellungen_pressed() -> void:
	_menu_list.hide()
	_settings_panel.open()


func _on_panel_closed() -> void:
	_menu_list.show()
