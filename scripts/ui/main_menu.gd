## Startmenü — das Erste, was ein Spieler sieht.
##
## Bewusst schlicht: Adresse eintippen und verbinden, oder solo spielen.
## Das Menü entscheidet nichts selbst — es meldet nur Wünsche per Signal an
## den Bootstrap, der den Szenenwechsel und die Verbindung übernimmt.
##
## Wird im Code aufgebaut, nicht als .tscn (Szenen lassen sich bei
## Konflikten nicht mergen).
class_name MainMenu
extends CanvasLayer

signal connect_requested(ip: String, port: int)
signal solo_requested(scene_path: String)
signal quit_requested

const SOLO_RAID := "res://scenes/levels/raid_eisstadt.tscn"
const SOLO_RANGE := "res://scenes/levels/testgelaende.tscn"

var _address_line: LineEdit
var _name_line: LineEdit
var _connect_button: Button
var _status_label: Label


func _ready() -> void:
	_build_layout()
	# Wer gerade vom Server abgewiesen wurde, soll den Grund lesen können —
	# die Verbindung ist da längst weg.
	if Net.rejection_reason != "":
		set_status(Net.rejection_reason)


func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.10)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(360, 0)
	center.add_child(column)

	var title := Label.new()
	title.text = "EXTRACTION SHOOTER"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Multiplayer-Beta"
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	column.add_child(_make_spacer(12))

	_name_line = LineEdit.new()
	_name_line.placeholder_text = "Spielername"
	# Kommt das Spiel aus dem Launcher, ist der Name schon gewählt.
	if Net.player_name != "Spieler":
		_name_line.text = Net.player_name
	column.add_child(_name_line)

	_address_line = LineEdit.new()
	# Der Beta-Server ist vorbelegt: Tester sollen nur Name eingeben und auf
	# Verbinden klicken. Für lokale Tests 127.0.0.1 eintippen oder F9 -> host.
	_address_line.text = "193.23.160.41"
	_address_line.placeholder_text = "Server-Adresse (ip[:port])"
	_address_line.text_submitted.connect(func(_text: String) -> void: _on_connect_pressed())
	column.add_child(_address_line)

	_connect_button = Button.new()
	_connect_button.text = "Mit Server verbinden"
	_connect_button.pressed.connect(_on_connect_pressed)
	column.add_child(_connect_button)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)

	column.add_child(_make_spacer(12))

	var solo_raid := Button.new()
	solo_raid.text = "Solo: Raid Eisstadt"
	solo_raid.pressed.connect(func() -> void: solo_requested.emit(SOLO_RAID))
	column.add_child(solo_raid)

	var solo_range := Button.new()
	solo_range.text = "Solo: Testgelaende"
	solo_range.pressed.connect(func() -> void: solo_requested.emit(SOLO_RANGE))
	column.add_child(solo_range)

	var quit := Button.new()
	quit.text = "Beenden"
	quit.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit)

	var hint := Label.new()
	hint.text = "F9 oeffnet die Konsole"
	hint.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _make_spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func set_status(text: String) -> void:
	_status_label.text = text


## Solange ein Verbindungsversuch läuft, soll man nicht doppelt klicken.
func set_busy(busy: bool) -> void:
	_connect_button.disabled = busy


func entered_name() -> String:
	return _name_line.text.strip_edges()


func _on_connect_pressed() -> void:
	var address := _address_line.text.strip_edges()
	if address.is_empty():
		set_status("Adresse fehlt")
		return
	var ip := address
	var port := 0
	if ":" in address:
		var parts := address.rsplit(":", false, 1)
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = parts[1].to_int()
	connect_requested.emit(ip, port)
