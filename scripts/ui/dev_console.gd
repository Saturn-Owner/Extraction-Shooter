## Entwicklerkonsole — F9 öffnet sie, überall: im Menü wie im Spiel.
##
## Die Konsole kennt keine Spiellogik. Sie führt nur Befehle aus, die andere
## Systeme bei ihr registriert haben:
##
##     DevConsole.instance.register_command("connect",
##         "Mit Server verbinden: connect <ip[:port]>", callable)
##
## So kann später alles Mögliche dazukommen (Debug-Anzeigen, Test-Cheats,
## Server-Verwaltung), ohne dass diese Datei wächst. Der Befehl bekommt die
## Argumente als PackedStringArray und gibt seinen Ausgabetext als String
## zurück — leer heißt: nichts zu sagen.
##
## Wird im Code aufgebaut, nicht als .tscn (Szenen lassen sich bei Konflikten
## nicht mergen). Sie hängt unter dem Net-Autoload und überlebt damit jeden
## Szenenwechsel.
##
## Pausiert das Spiel NICHT — im Multiplayer läuft die Welt weiter. Stattdessen
## bekommt der lokale Spieler set_ui_open(true), damit Tippen nicht losläuft.
class_name DevConsole
extends CanvasLayer

## Anteil des Bildschirms, den die Konsole von oben belegt.
const PANEL_HEIGHT_FRACTION := 0.45
const MAX_LOG_LINES := 200
const MAX_HISTORY := 50

## Die eine Instanz, bei der Systeme ihre Befehle registrieren.
static var instance: DevConsole

var _commands: Dictionary = {}  # Name -> {description: String, action: Callable}
var _history: PackedStringArray = []
var _history_index: int = -1
## Merkt sich den Mauszustand von vor dem Öffnen, um ihn wiederherzustellen.
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _panel: Control
var _log: RichTextLabel
var _input_line: LineEdit


func _ready() -> void:
	instance = self
	# Muss auch reagieren, wenn irgendwer das Spiel angehalten hat.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Über allem anderen (Werkbank liegt auf 10).
	layer = 20
	_build_layout()
	visible = false
	register_command("help", "Listet alle Befehle", _cmd_help)
	register_command("clear", "Leert die Ausgabe", _cmd_clear)


func _build_layout() -> void:
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.anchor_bottom = PANEL_HEIGHT_FRACTION
	add_child(_panel)

	var background := ColorRect.new()
	background.color = Color(0.05, 0.06, 0.07, 0.92)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	_panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	_log = RichTextLabel.new()
	_log.name = "Ausgabe"
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	rows.add_child(_log)

	_input_line = LineEdit.new()
	_input_line.name = "Eingabe"
	_input_line.placeholder_text = "Befehl eingeben — help listet alles"
	_input_line.add_theme_font_size_override("font_size", 14)
	_input_line.text_submitted.connect(_on_text_submitted)
	# Historie und Vervollständigung müssen VOR dem LineEdit an die Tasten,
	# sonst frisst es Pfeile und Tab selbst.
	_input_line.gui_input.connect(_on_input_line_key)
	rows.add_child(_input_line)


## Registriert einen Befehl. `action` bekommt die Argumente als
## PackedStringArray und gibt den Ausgabetext zurück (leer = still).
func register_command(command_name: String, description: String, action: Callable) -> void:
	_commands[command_name] = {description = description, action = action}


func print_line(text: String) -> void:
	_log.append_text(text + "\n")
	# Nicht endlos wachsen lassen.
	while _log.get_paragraph_count() > MAX_LOG_LINES:
		_log.remove_paragraph(0)


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_input_line.grab_focus()
	_set_player_blocked(true)


func close() -> void:
	if not visible:
		return
	visible = false
	Input.mouse_mode = _previous_mouse_mode
	_set_player_blocked(false)


## Solange die Konsole offen ist, darf der Spieler nicht auf WASD & Co.
## reagieren — sonst rennt man beim Tippen los. Der Spieler heißt in jeder
## Szene "Player"; gibt es keinen (Hauptmenü), passiert einfach nichts.
func _set_player_blocked(blocked: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := scene.get_node_or_null("Player")
	if player != null and player.has_method("set_ui_open"):
		player.set_ui_open(blocked)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_F9:
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and key.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _on_input_line_key(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed():
		return
	match (event as InputEventKey).physical_keycode:
		KEY_UP:
			_recall_history(-1)
			_input_line.accept_event()
		KEY_DOWN:
			_recall_history(1)
			_input_line.accept_event()
		KEY_TAB:
			_complete_command()
			_input_line.accept_event()


func _recall_history(direction: int) -> void:
	if _history.is_empty():
		return
	if _history_index < 0:
		# Frisch getippt — Pfeil hoch beginnt beim neuesten Eintrag.
		_history_index = _history.size()
	_history_index = clampi(_history_index + direction, 0, _history.size())
	_input_line.text = "" if _history_index >= _history.size() else _history[_history_index]
	_input_line.caret_column = _input_line.text.length()


## Vervollständigt den Befehlsnamen, solange noch kein Leerzeichen dasteht.
func _complete_command() -> void:
	var typed := _input_line.text
	if typed.is_empty() or " " in typed:
		return
	var matches: PackedStringArray = []
	for command_name in _commands:
		if String(command_name).begins_with(typed):
			matches.append(command_name)
	if matches.size() == 1:
		_input_line.text = matches[0] + " "
		_input_line.caret_column = _input_line.text.length()
	elif matches.size() > 1:
		matches.sort()
		print_line("  " + "   ".join(matches))


func _on_text_submitted(text: String) -> void:
	_input_line.clear()
	_history_index = -1
	var line := text.strip_edges()
	if line.is_empty():
		return
	if _history.is_empty() or _history[_history.size() - 1] != line:
		_history.append(line)
		while _history.size() > MAX_HISTORY:
			_history.remove_at(0)
	print_line("> " + line)
	_execute(line)


func _execute(line: String) -> void:
	var parts := line.split(" ", false)
	var command_name := parts[0]
	if not _commands.has(command_name):
		print_line("Unbekannter Befehl: %s — help listet alles" % command_name)
		return
	var args := parts.slice(1)
	var result: Variant = (_commands[command_name].action as Callable).call(args)
	if result is String and not (result as String).is_empty():
		print_line(result)


func _cmd_help(_args: PackedStringArray) -> String:
	var names := _commands.keys()
	names.sort()
	var lines: PackedStringArray = []
	for command_name in names:
		lines.append("  %-12s %s" % [command_name, _commands[command_name].description])
	return "\n".join(lines)


func _cmd_clear(_args: PackedStringArray) -> String:
	_log.clear()
	return ""
