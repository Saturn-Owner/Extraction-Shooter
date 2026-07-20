## Einstiegspunkt des Spiels — die neue Main-Scene.
##
## Entscheidet beim Start, was dieser Prozess ist:
##
##   Server:  gestartet mit  godot --headless -- --server [--port 24567]
##            (oder schlicht headless ohne Fenster, wie auf dem VPS).
##            Lädt die Arena ohne Spieler und wartet auf Verbindungen.
##   Client:  zeigt das Startmenü. Verbinden lädt die Arena,
##            Solo lädt die bisherigen Karten unverändert.
##
## Der Bootstrap selbst enthält keinen Spielzustand — der liegt im
## Net-Autoload, das jeden Szenenwechsel überlebt.
extends Node

const ARENA_SCENE := "res://scenes/levels/arena_beta.tscn"

var _menu: MainMenu


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args or DisplayServer.get_name() == "headless":
		_start_server(args)
	else:
		_show_menu()


# --- Server ---------------------------------------------------------------

func _start_server(args: PackedStringArray) -> void:
	var error := Net.start_server(_port_from_args(args))
	if not error.is_empty():
		push_error("[Bootstrap] " + error)
		get_tree().quit(1)
		return
	_load_arena()


## Liest --port 12345 oder --port=12345 aus den Startargumenten.
func _port_from_args(args: PackedStringArray) -> int:
	for index in args.size():
		var arg := args[index]
		if arg == "--port" and index + 1 < args.size() and args[index + 1].is_valid_int():
			return args[index + 1].to_int()
		if arg.begins_with("--port=") and arg.trim_prefix("--port=").is_valid_int():
			return arg.trim_prefix("--port=").to_int()
	return Net.DEFAULT_PORT


# --- Client ---------------------------------------------------------------

func _show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = MainMenu.new()
	_menu.name = "Menue"
	_menu.connect_requested.connect(_on_connect_requested)
	_menu.solo_requested.connect(_on_solo_requested)
	_menu.quit_requested.connect(func() -> void: get_tree().quit())
	add_child(_menu)
	Net.connection_succeeded.connect(_on_connection_succeeded)
	Net.connection_failed.connect(_on_connection_failed)


func _on_connect_requested(ip: String, port: int) -> void:
	var chosen_name := _menu.entered_name()
	if not chosen_name.is_empty():
		Net.player_name = chosen_name
	var error := Net.start_client(ip, port if port > 0 else Net.DEFAULT_PORT)
	if not error.is_empty():
		_menu.set_status(error)
		return
	_menu.set_busy(true)
	_menu.set_status("Verbinde ...")


func _on_connection_succeeded() -> void:
	_load_arena()


func _on_connection_failed() -> void:
	if _menu != null:
		_menu.set_busy(false)
		_menu.set_status("Verbindung fehlgeschlagen — Server erreichbar?")


func _on_solo_requested(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


# --- Gemeinsam ------------------------------------------------------------

func _load_arena() -> void:
	if not ResourceLoader.exists(ARENA_SCENE):
		# Phase 0: Die Arena kommt erst in Phase 1 — bis dahin bleibt der
		# Server leer stehen und der Client sieht den Hinweis im Menü.
		if _menu != null:
			_menu.set_status("Verbunden! (Arena folgt in Phase 1)")
		else:
			print("[Bootstrap] Arena-Szene fehlt noch — Server wartet leer.")
		return
	# Aufgeschoben: _load_arena läuft beim Serverstart noch in _ready(), und
	# mitten im Baumaufbau darf die alte Szene nicht entfernt werden —
	# der direkte Aufruf schreibt einen Fehler ins Log (remove_child busy).
	get_tree().change_scene_to_file.call_deferred(ARENA_SCENE)
