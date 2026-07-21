## Der Launcher: Steam-Anmeldung, Auto-Update, Spielen.
##
## Warum es ihn gibt:
##   1. Tester bekommen EINMAL diese eine Datei. Ab dann holt der Launcher
##      vor jedem Spielen die neueste Version vom Server — niemand spielt
##      mehr mit einer alten .exe gegen einen neuen Server.
##   2. Anmeldung über Steam (OpenID): Steam bestätigt, wer der Spieler ist,
##      und wir bekommen nur seine Steam-ID. ES GIBT KEIN PASSWORT BEI UNS —
##      nichts zu speichern, nichts zu verlieren.
##
## Ablauf der Steam-Anmeldung:
##   Launcher öffnet den Browser mit der Steam-Login-Seite. Steam schickt
##   den Browser danach zu http://127.0.0.1:<port>/auth zurück — dort horcht
##   der Launcher selbst. Die Antwort-Parameter gehen an UNSEREN Server, der
##   sie bei Steam GEGENPRÜFT (sonst könnte jeder eine fremde ID behaupten)
##   und dafür ein Sitzungs-Token ausgibt. Das Token nimmt das Spiel mit.
extends Control

## Wo Update und Anmeldung herkommen.
const SERVER := "193.23.160.41"
const AUTH_PORT := 24568
const DOWNLOAD_PORT := 24569
## Auf diesem örtlichen Port fängt der Launcher die Steam-Rückkehr ab.
const CALLBACK_PORT := 27444

const SESSION_FILE := "user://session.json"
const GAME_DIR := "user://game"
const VERSION_FILE := "user://game/version.txt"
const GAME_EXE := "user://game/extraction_shooter.exe"

enum State {CHECKING, NEEDS_UPDATE, DOWNLOADING, UNPACKING, READY, ERROR}

var _state: State = State.CHECKING
var _remote_version := ""
var _remote_file := ""
var _local_version := ""

var _steam_id := ""
var _token := ""

var _callback_server: TCPServer
var _http_version: HTTPRequest
var _http_download: HTTPRequest
var _http_auth: HTTPRequest

var _status: Label
var _login_status: Label
var _login_button: Button
var _name_line: LineEdit
var _play_button: Button
var _progress: ProgressBar
var _version_label: Label


func _ready() -> void:
	_build_layout()
	_load_session()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GAME_DIR))
	_local_version = _read_local_version()
	_check_version()


# ------------------------------------------------------------------ Anzeige

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.10)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "EXTRACTION SHOOTER"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Launcher — Multiplayer-Beta"
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	column.add_child(_spacer(8))

	# --- Anmeldung ---
	var login_heading := Label.new()
	login_heading.text = "Anmeldung"
	login_heading.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	column.add_child(login_heading)

	_login_button = Button.new()
	_login_button.text = "Mit Steam anmelden"
	_login_button.pressed.connect(_start_steam_login)
	column.add_child(_login_button)

	_login_status = Label.new()
	_login_status.text = "Nicht angemeldet — Spielen geht auch als Gast"
	_login_status.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	column.add_child(_login_status)

	_name_line = LineEdit.new()
	_name_line.placeholder_text = "Spielername"
	column.add_child(_name_line)

	column.add_child(_spacer(8))

	# --- Spielstand / Update ---
	var game_heading := Label.new()
	game_heading.text = "Spiel"
	game_heading.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	column.add_child(game_heading)

	_version_label = Label.new()
	_version_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	column.add_child(_version_label)

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.visible = false
	column.add_child(_progress)

	_status = Label.new()
	_status.text = "Prüfe auf Updates ..."
	column.add_child(_status)

	column.add_child(_spacer(8))

	_play_button = Button.new()
	_play_button.text = "SPIELEN"
	_play_button.custom_minimum_size = Vector2(0, 56)
	_play_button.add_theme_font_size_override("font_size", 24)
	_play_button.disabled = true
	_play_button.pressed.connect(_play)
	column.add_child(_play_button)

	var hint := Label.new()
	hint.text = "Der Launcher hält das Spiel automatisch aktuell."
	hint.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _set_status(text: String) -> void:
	_status.text = text


func _refresh_version_label() -> void:
	var local := _local_version if _local_version != "" else "nicht installiert"
	var remote := _remote_version if _remote_version != "" else "?"
	_version_label.text = "Installiert: %s   ·   Aktuell: %s" % [local, remote]


# ------------------------------------------------------------ Sitzung/Namen

func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_FILE):
		return
	var raw := FileAccess.get_file_as_string(SESSION_FILE)
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		return
	_token = data.get("token", "")
	_steam_id = data.get("steam_id", "")
	_name_line.text = data.get("name", "")
	if _steam_id != "":
		_login_status.text = "Angemeldet über Steam (%s)" % _steam_id


func _save_session() -> void:
	var file := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		token = _token,
		steam_id = _steam_id,
		name = _name_line.text.strip_edges(),
	}))


# ------------------------------------------------------------------- Update

func _check_version() -> void:
	_http_version = HTTPRequest.new()
	add_child(_http_version)
	_http_version.request_completed.connect(_on_version_response)
	var error := _http_version.request("http://%s:%d/version.json" % [SERVER, DOWNLOAD_PORT])
	if error != OK:
		_fail("Update-Server nicht erreichbar")


func _on_version_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# Kein Server heißt nicht kein Spiel: Was installiert ist, bleibt
		# spielbar — nur eben ohne Update-Garantie.
		if FileAccess.file_exists(GAME_EXE):
			_state = State.READY
			_play_button.disabled = false
			_set_status("Update-Server nicht erreichbar — starte installierte Version")
		else:
			_fail("Update-Server nicht erreichbar und kein Spiel installiert")
		return

	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or not data.has("version") or not data.has("file"):
		_fail("Antwort des Update-Servers ist kaputt")
		return
	_remote_version = data.version
	_remote_file = data.file
	_refresh_version_label()

	if _remote_version == _local_version and FileAccess.file_exists(GAME_EXE):
		_state = State.READY
		_play_button.disabled = false
		_set_status("Spiel ist aktuell.")
	else:
		_state = State.NEEDS_UPDATE
		_start_download()


func _start_download() -> void:
	_state = State.DOWNLOADING
	_set_status("Lade Version %s ..." % _remote_version)
	_progress.visible = true
	_play_button.disabled = true

	_http_download = HTTPRequest.new()
	add_child(_http_download)
	_http_download.download_file = GAME_DIR + "/download.zip"
	_http_download.request_completed.connect(_on_download_done)
	var error := _http_download.request("http://%s:%d/%s" % [SERVER, DOWNLOAD_PORT, _remote_file])
	if error != OK:
		_fail("Download startet nicht")


func _on_download_done(result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_progress.visible = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Download fehlgeschlagen (Code %d)" % code)
		return
	_unpack()


## Entpackt das Spiel-ZIP nach user://game/.
func _unpack() -> void:
	_state = State.UNPACKING
	_set_status("Entpacke ...")
	var reader := ZIPReader.new()
	if reader.open(GAME_DIR + "/download.zip") != OK:
		_fail("ZIP lässt sich nicht öffnen")
		return
	for inner_path in reader.get_files():
		if inner_path.ends_with("/"):
			continue
		var target := GAME_DIR + "/" + inner_path
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(target.get_base_dir()))
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			# Die laufende .exe lässt sich unter Windows nicht überschreiben —
			# das passiert, wenn das Spiel noch offen ist.
			_fail("Kann %s nicht schreiben — läuft das Spiel noch?" % inner_path.get_file())
			reader.close()
			return
		out.store_buffer(reader.read_file(inner_path))
		out.close()
	reader.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GAME_DIR + "/download.zip"))

	_write_local_version(_remote_version)
	_local_version = _remote_version
	_refresh_version_label()
	_state = State.READY
	_play_button.disabled = false
	_set_status("Spiel ist aktuell.")


func _read_local_version() -> String:
	if not FileAccess.file_exists(VERSION_FILE):
		return ""
	return FileAccess.get_file_as_string(VERSION_FILE).strip_edges()


func _write_local_version(version: String) -> void:
	var file := FileAccess.open(VERSION_FILE, FileAccess.WRITE)
	file.store_string(version)


func _fail(message: String) -> void:
	_state = State.ERROR
	_progress.visible = false
	_set_status("FEHLER: " + message)


func _process(_delta: float) -> void:
	if _state == State.DOWNLOADING and _http_download != null:
		var total := _http_download.get_body_size()
		if total > 0:
			_progress.value = float(_http_download.get_downloaded_bytes()) / float(total)
	_poll_steam_callback()


# ---------------------------------------------------------- Steam-Anmeldung

func _start_steam_login() -> void:
	if _callback_server == null:
		_callback_server = TCPServer.new()
		if _callback_server.listen(CALLBACK_PORT, "127.0.0.1") != OK:
			_login_status.text = "Örtlicher Port %d belegt — läuft der Launcher doppelt?" % CALLBACK_PORT
			_callback_server = null
			return

	var return_to := "http://127.0.0.1:%d/auth" % CALLBACK_PORT
	var params := [
		"openid.ns=" + "http://specs.openid.net/auth/2.0".uri_encode(),
		"openid.mode=checkid_setup",
		"openid.return_to=" + return_to.uri_encode(),
		"openid.realm=" + ("http://127.0.0.1:%d" % CALLBACK_PORT).uri_encode(),
		"openid.identity=" + "http://specs.openid.net/auth/2.0/identifier_select".uri_encode(),
		"openid.claimed_id=" + "http://specs.openid.net/auth/2.0/identifier_select".uri_encode(),
	]
	OS.shell_open("https://steamcommunity.com/openid/login?" + "&".join(params))
	_login_status.text = "Browser geöffnet — dort bei Steam anmelden ..."


## Fängt die Rückkehr des Browsers von Steam ab.
func _poll_steam_callback() -> void:
	if _callback_server == null or not _callback_server.is_connection_available():
		return
	var connection := _callback_server.take_connection()
	# Die Anfrage ist winzig (eine GET-Zeile plus Kopfzeilen) — was nach
	# einem kurzen Moment da ist, ist alles, was wir brauchen.
	var request := ""
	for _attempt in range(20):
		if connection.get_available_bytes() > 0:
			request += connection.get_utf8_string(connection.get_available_bytes())
			if "\r\n" in request:
				break
		OS.delay_msec(25)

	var reply := "Anmeldung übernommen — dieses Fenster kann zu."
	connection.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" +
		"Content-Length: %d\r\nConnection: close\r\n\r\n%s" % [reply.to_utf8_buffer().size(), reply]).to_utf8_buffer())
	connection.disconnect_from_host()
	_callback_server.stop()
	_callback_server = null

	# "GET /auth?openid...=... HTTP/1.1" -> nur die Parameter interessieren.
	var first_line := request.get_slice("\r\n", 0)
	if not first_line.begins_with("GET /auth?"):
		_login_status.text = "Steam-Rückkehr sah falsch aus — nochmal versuchen"
		return
	var query := first_line.trim_prefix("GET /auth?").get_slice(" ", 0)
	_verify_with_server(query)


## Schickt die Steam-Antwort an unseren Server zur Gegenprüfung.
func _verify_with_server(openid_query: String) -> void:
	_login_status.text = "Prüfe Anmeldung ..."
	_http_auth = HTTPRequest.new()
	add_child(_http_auth)
	_http_auth.request_completed.connect(_on_auth_response)
	var error := _http_auth.request("http://%s:%d/steam-auth" % [SERVER, AUTH_PORT],
		["Content-Type: application/x-www-form-urlencoded"],
		HTTPClient.METHOD_POST, openid_query)
	if error != OK:
		_login_status.text = "Anmelde-Server nicht erreichbar"


func _on_auth_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_login_status.text = "Anmeldung abgelehnt (Code %d) — Server an?" % code
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or not data.has("token"):
		_login_status.text = "Anmelde-Antwort ist kaputt"
		return
	_token = data.token
	_steam_id = data.get("steam_id", "")
	_login_status.text = "Angemeldet über Steam (%s)" % _steam_id
	if _name_line.text.strip_edges().is_empty() and data.has("name"):
		_name_line.text = data.name
	_save_session()


# ------------------------------------------------------------------ Spielen

func _play() -> void:
	_save_session()
	var exe := ProjectSettings.globalize_path(GAME_EXE)
	if not FileAccess.file_exists(GAME_EXE):
		_fail("Spiel fehlt — Update nötig")
		return
	# Hinter "--", damit die Engine die Argumente nicht selbst frisst —
	# das Spiel liest sie über OS.get_cmdline_user_args().
	var args: PackedStringArray = ["--"]
	var chosen_name := _name_line.text.strip_edges()
	if not chosen_name.is_empty():
		args.append_array(["--name", chosen_name])
	if not _token.is_empty():
		args.append_array(["--token", _token])
	if OS.create_process(exe, args) > 0:
		_set_status("Spiel gestartet — viel Erfolg!")
	else:
		_fail("Spiel liess sich nicht starten")
