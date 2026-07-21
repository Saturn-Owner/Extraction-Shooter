## Der Launcher: Steam-Anmeldung, Update-Prüfung, News, Spielen.
##
## Warum es ihn gibt:
##   1. Tester bekommen EINMAL diese eine Datei. Ab dann PRÜFT der Launcher
##      vor jedem Spielen, ob eine neue Version vorliegt — niemand spielt
##      mehr aus Versehen mit einer alten .exe gegen einen neuen Server.
##      Geladen wird das Update aber nie von selbst: SPIELEN wird so lange
##      zu HERUNTERLADEN, bis der Tester selbst klickt (siehe _prompt_download).
##   2. Anmeldung über Steam (OpenID): Steam bestätigt, wer der Spieler ist,
##      und wir bekommen nur seine Steam-ID. ES GIBT KEIN PASSWORT BEI UNS —
##      nichts zu speichern, nichts zu verlieren.
##   3. Der Launcher hält auch SICH SELBST aktuell (eigenes Manifest
##      launcher_version.json, gleicher Server) — tauscht die eigene .exe
##      aus und startet neu. Auch für den Launcher selbst bekommt niemand
##      je wieder eine neue Datei zugeschickt.
##
## Ablauf der Steam-Anmeldung:
##   Launcher öffnet den Browser mit der Steam-Login-Seite. Steam schickt
##   den Browser danach zu http://127.0.0.1:<port>/auth zurück — dort horcht
##   der Launcher selbst. Die Antwort-Parameter gehen an UNSEREN Server, der
##   sie bei Steam GEGENPRÜFT (sonst könnte jeder eine fremde ID behaupten)
##   und dafür ein Sitzungs-Token ausgibt. Das Token nimmt das Spiel mit.
##
## Das AUSSEHEN wohnt komplett in launcher_theme.gd und background.gdshader —
## diese Datei kennt keine Farben, nur Theme-Typen. Stilrichtung: Modernist /
## "Red Snow" — Titelleiste, Tab-Leiste (Neuigkeiten/Patchnotes/Roadmap),
## Hero + News, Installations-/Konto-Spalte rechts, Aktionsleiste unten.
extends Control

## Wo Update, News und Anmeldung herkommen.
const SERVER := "193.23.160.41"
const AUTH_PORT := 24568
const DOWNLOAD_PORT := 24569
## Auf diesem örtlichen Port fängt der Launcher die Steam-Rückkehr ab.
const CALLBACK_PORT := 27444

## Version des Launchers selbst (nicht des Spiels) — bei Launcher-Änderungen
## von Hand hochzählen, damit Tester sagen können, welchen sie haben, UND
## damit der Selbst-Update-Vergleich unten überhaupt etwas zu vergleichen hat.
const LAUNCHER_VERSION := "1.3"

const SESSION_FILE := "user://session.json"
const SETTINGS_FILE := "user://settings.json"
const GAME_DIR := "user://game"
const VERSION_FILE := "user://game/version.txt"
const GAME_EXE := "user://game/extraction_shooter.exe"

## Wohin die heruntergeladene neue Launcher-.exe erst einmal kommt, bevor
## sie die laufende .exe ersetzt — und das Batch-Skript, das den Tausch
## übernimmt (siehe _apply_launcher_update).
const LAUNCHER_UPDATE_FILE := "user://launcher_update.exe"
const LAUNCHER_UPDATE_SCRIPT := "user://apply_update.bat"

enum State {CHECKING, NEEDS_UPDATE, DOWNLOADING, UNPACKING, READY, ERROR}

var _state: State = State.CHECKING
var _remote_version := ""
var _remote_file := ""
var _remote_sha256 := ""
var _local_version := ""
## Wie oft der aktuelle Download schon versucht wurde — bei einer kaputten
## Prüfsumme oder abgebrochener Übertragung einmal automatisch neu holen,
## bevor der Tester zur Handarbeit ("Dateien überprüfen") muss.
var _download_attempt := 0

## Selbst-Update des Launchers: Prüfsumme der geladenen neuen .exe, bis sie
## verifiziert und eingesetzt ist.
var _launcher_update_sha256 := ""
var _http_launcher_version: HTTPRequest
var _http_launcher_download: HTTPRequest

var _steam_id := ""
var _token := ""

var _callback_server: TCPServer
var _http_version: HTTPRequest
var _http_download: HTTPRequest
var _http_auth: HTTPRequest
var _http_news: HTTPRequest

var _status: Label
var _login_status: Label
var _login_button: Button
var _name_line: LineEdit
var _play_button: Button
var _progress: ProgressBar
var _version_label: Label
var _installed_label: Label
var _news_box: VBoxContainer
var _hero_kicker: Label
var _hero_title: Label
var _hero_text: Label
var _patch_box: VBoxContainer
var _road_box: VBoxContainer
var _size_label: Label
var _last_played_label: Label
var _http_patch: HTTPRequest
var _http_road: HTTPRequest

var _views := {}
var _tab_buttons := {}
var _pulse: Tween

var _settings := {}
var _settings_overlay: Control
var _settings_ready := false

## Ob die Titelleiste gerade zum Verschieben gepackt ist.
var _drag_active := false


func _ready() -> void:
	theme = LauncherTheme.build()
	_load_settings()
	_build_layout()
	_load_session()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GAME_DIR))
	_local_version = _read_local_version()
	# Der Selbst-Update-Check laeuft IMMER, unabhaengig vom Auto-Update-
	# Schalter unten — der gilt nur fuer das Spiel. Ein veralteter Launcher
	# mit einem Bug darin darf sich nicht selbst aus der Update-Kette werfen.
	_check_launcher_update()
	# Automatische Update-Suche laesst sich in den Einstellungen abschalten.
	if _settings.get("auto_update", true):
		_check_version()
	elif FileAccess.file_exists(GAME_EXE):
		_set_ready()
		_set_status("Automatische Update-Suche aus — starte installierte Version")
	else:
		_set_status("Automatische Update-Suche aus — „Dateien überprüfen\" für Update")
	_load_news()
	_load_patchnotes()
	_load_roadmap()


# ------------------------------------------------------------------ Aufbau

func _build_layout() -> void:
	# Der lebendige Hintergrund — alles Weitere liegt darüber.
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = load("res://background.gdshader")
	background.material = material
	add_child(background)

	# Wurzel-Spalte: roter Deckstreifen, Titelleiste, Tabs, Körper, Aktionsleiste.
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	# 4px roter Deckstreifen — die Marke berührt die Fensterkante.
	var top_accent := ColorRect.new()
	top_accent.color = LauncherTheme.RED
	top_accent.custom_minimum_size = Vector2(0, 4)
	column.add_child(top_accent)

	column.add_child(_build_titlebar())
	column.add_child(_hline())
	column.add_child(_build_tabbar())
	column.add_child(_hline())
	column.add_child(_build_body())
	column.add_child(_hline())
	column.add_child(_build_actionbar())

	_show_tab("news")

	_settings_overlay = _build_settings_overlay()
	add_child(_settings_overlay)
	_settings_ready = true


## Eine 2px-Tintenlinie — Modernist zieht Struktur mit Linien, nicht mit Schatten.
func _hline() -> ColorRect:
	var line := ColorRect.new()
	line.color = LauncherTheme.INK
	line.custom_minimum_size = Vector2(0, LauncherTheme.EDGE_WIDTH)
	return line


func _vline() -> ColorRect:
	var line := ColorRect.new()
	line.color = LauncherTheme.INK
	line.custom_minimum_size = Vector2(LauncherTheme.EDGE_WIDTH, 0)
	return line


## Grotesk-Label mit Archivo, frei in Größe und Farbe.
func _mk_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", LauncherTheme.heading_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_titlebar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 52)
	bar.add_theme_constant_override("separation", 0)
	# Das Fenster ist randlos (die Leiste hier IST die Titelleiste) — ohne
	# eigenes Anfassen ließe es sich nicht mehr verschieben.
	bar.gui_input.connect(_on_titlebar_input)

	# Marke: rotes Quadrat + RED SNOW.
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	brand.custom_minimum_size = Vector2(0, 0)
	var pad_brand := MarginContainer.new()
	for s in ["margin_left", "margin_right"]:
		pad_brand.add_theme_constant_override(s, LauncherTheme.PADDING)
	pad_brand.add_child(brand)
	var sq := ColorRect.new()
	sq.color = LauncherTheme.RED
	sq.custom_minimum_size = Vector2(16, 16)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(sq)
	var brand_label := _mk_label("EXTRACTION SHOOTER", 20, LauncherTheme.INK)
	brand_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(brand_label)
	bar.add_child(pad_brand)

	# Dehnfuge.
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(stretch)

	# Anmelde-Status kompakt rechts (wird von _load_session gefüttert).
	_login_status = Label.new()
	_login_status.text = "Nicht angemeldet"
	_login_status.theme_type_variation = &"DimLabel"
	_login_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_login_status.custom_minimum_size = Vector2(0, 0)
	var pad_status := MarginContainer.new()
	for s in ["margin_left", "margin_right"]:
		pad_status.add_theme_constant_override(s, LauncherTheme.PADDING)
	pad_status.add_child(_login_status)
	bar.add_child(pad_status)

	# Einstellungen + Fenster-Kontrollen als schmale Knöpfe.
	bar.add_child(_vline())
	bar.add_child(_icon_button("OPTIONEN", func(): _settings_overlay.visible = not _settings_overlay.visible))
	bar.add_child(_vline())
	bar.add_child(_icon_button("—", func(): get_window().mode = Window.MODE_MINIMIZED))
	bar.add_child(_vline())
	var close := _icon_button("X", func(): get_tree().quit())
	bar.add_child(close)
	return bar


## Verschieben am Griff der Titelleiste, wie es eine echte könnte.
func _on_titlebar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag_active = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _drag_active:
		get_window().position += Vector2i((event as InputEventMouseMotion).relative)


func _icon_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(56, 0)
	button.pressed.connect(on_press)
	return button


func _build_tabbar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 44)
	bar.add_theme_constant_override("separation", 0)

	bar.add_child(_tab_button("news", "NEUIGKEITEN"))
	bar.add_child(_vline())
	bar.add_child(_tab_button("patch", "PATCHNOTES"))
	bar.add_child(_vline())
	bar.add_child(_tab_button("road", "ROADMAP"))
	bar.add_child(_vline())

	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(stretch)

	_last_played_label = Label.new()
	_last_played_label.text = _format_last_played()
	_last_played_label.theme_type_variation = &"DimLabel"
	_last_played_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pad := MarginContainer.new()
	for s in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(s, LauncherTheme.PADDING)
	pad.add_child(_last_played_label)
	bar.add_child(pad)
	return bar


## "Zuletzt gespielt" aus dem gespeicherten Zeitstempel — und nur dann,
## wenn es wirklich ein letztes Mal gab.
func _format_last_played() -> String:
	var stamp: float = _settings.get("last_played", 0.0)
	if stamp <= 0.0:
		return ""
	var days := int((Time.get_unix_time_from_system() - stamp) / 86400.0)
	if days <= 0:
		return "Zuletzt gespielt · heute"
	if days == 1:
		return "Zuletzt gespielt · gestern"
	return "Zuletzt gespielt · vor %d Tagen" % days


## Ein Tab-Knopf: flach, transparent, Hover füllt grau, aktiv färbt rot.
func _tab_button(id: String, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	button.custom_minimum_size = Vector2(0, 44)

	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_content_margin_all(0)
	flat.content_margin_left = LauncherTheme.PADDING
	flat.content_margin_right = LauncherTheme.PADDING
	var hover := flat.duplicate()
	hover.bg_color = LauncherTheme.HOVER_FILL
	button.add_theme_stylebox_override("normal", flat)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	button.pressed.connect(func(): _show_tab(id))
	_tab_buttons[id] = button
	return button


func _build_body() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)

	# --- Mitte: die drei Ansichten liegen übereinander, eine ist sichtbar. ---
	var main := Control.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.clip_contents = true

	_views["news"] = _wrap_view(main, _build_news_view())
	_views["patch"] = _wrap_view(main, _build_patch_view())
	_views["road"] = _wrap_view(main, _build_road_view())
	body.add_child(main)

	body.add_child(_vline())

	# --- Rechts: Installation und Konto. ---
	body.add_child(_build_side())
	return body


## Legt eine Ansicht deckend über die Mitte.
func _wrap_view(parent: Control, view: Control) -> Control:
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(view)
	return view


func _show_tab(id: String) -> void:
	for key in _views:
		_views[key].visible = (key == id)
	for key in _tab_buttons:
		var button: Button = _tab_buttons[key]
		# key kommt als Variant aus dem Dictionary — den bool ausdrücklich machen.
		var active: bool = key == id
		button.add_theme_color_override("font_color",
			LauncherTheme.RED if active else LauncherTheme.INK)
		button.add_theme_color_override("font_hover_color",
			LauncherTheme.RED if active else LauncherTheme.INK)


# --------------------------------------------------------- Ansicht: News

func _build_news_view() -> Control:
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", 0)

	# Hero mit Key-Art-Platzhalter.
	var hero := PanelContainer.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dark := StyleBoxFlat.new()
	dark.bg_color = Color("201e1d")
	dark.set_content_margin_all(LauncherTheme.PADDING + 8)
	hero.add_theme_stylebox_override("panel", dark)

	var hero_col := VBoxContainer.new()
	hero_col.alignment = BoxContainer.ALIGNMENT_END
	hero_col.add_theme_constant_override("separation", 6)
	hero.add_child(hero_col)

	# Der Hero zeigt die NEUESTE echte Nachricht vom Server — keine
	# ausgedachte Saison. Bis sie geladen ist, steht hier nur Zurückhaltung.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_col.add_child(spacer)
	_hero_kicker = _mk_label("AUS DER BETA", 13, LauncherTheme.RED)
	hero_col.add_child(_hero_kicker)
	_hero_title = Label.new()
	_hero_title.text = "..."
	_hero_title.theme_type_variation = &"TitleLabel"
	_hero_title.add_theme_font_size_override("font_size", 40)
	_hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_col.add_child(_hero_title)
	_hero_text = _mk_label("", 14, Color(1, 1, 1, 0.82))
	_hero_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_col.add_child(_hero_text)
	view.add_child(hero)

	view.add_child(_hline())

	# News-Streifen (wird vom Server gefüllt).
	var news_panel := _panel("AUS DEM FELDLAGER")
	news_panel.panel.custom_minimum_size = Vector2(0, 168)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	news_panel.content.add_child(scroll)
	_news_box = VBoxContainer.new()
	_news_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_news_box.add_theme_constant_override("separation", 12)
	scroll.add_child(_news_box)
	var loading := Label.new()
	loading.text = "Lade Nachrichten ..."
	loading.theme_type_variation = &"DimLabel"
	_news_box.add_child(loading)
	view.add_child(news_panel.panel)
	return view


# ----------------------------------------------------- Ansicht: Patchnotes

func _build_patch_view() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_patch_box = VBoxContainer.new()
	_patch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_patch_box.add_theme_constant_override("separation", LauncherTheme.PADDING + 8)

	var pad := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(s, LauncherTheme.PADDING + 8)
	pad.add_child(_patch_box)

	var loading := Label.new()
	loading.text = "Lade Patchnotes ..."
	loading.theme_type_variation = &"DimLabel"
	_patch_box.add_child(loading)

	scroll.add_child(pad)
	return scroll


## Patchnotes kommen als patchnotes.json vom Server — dieselbe Pflege wie
## die News: docs/patchnotes.json editieren, publish_news.ps1, fertig.
func _load_patchnotes() -> void:
	_http_patch = HTTPRequest.new()
	add_child(_http_patch)
	_http_patch.request_completed.connect(_on_patchnotes_response)
	_http_patch.request("http://%s:%d/patchnotes.json" % [SERVER, DOWNLOAD_PORT])


func _on_patchnotes_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_http_patch.queue_free()
	_http_patch = null
	for child in _patch_box.get_children():
		child.queue_free()

	var entries: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		entries = JSON.parse_string(body.get_string_from_utf8())
	if not (entries is Array) or (entries as Array).is_empty():
		var empty := Label.new()
		empty.text = "Keine Patchnotes erreichbar."
		empty.theme_type_variation = &"DimLabel"
		_patch_box.add_child(empty)
		return

	for i in (entries as Array).size():
		var entry: Dictionary = (entries as Array)[i]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 16)
		head.add_child(_mk_label(String(entry.get("version", "?")), 48, LauncherTheme.RED))
		var meta := VBoxContainer.new()
		meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meta.add_child(_mk_label(String(entry.get("date", "")), 14, LauncherTheme.INK))
		meta.add_child(_mk_label("AKTUELLE VERSION" if i == 0 else "ÄLTERE VERSION",
			11, LauncherTheme.TEXT_DIM))
		head.add_child(meta)
		_patch_box.add_child(head)

		for group in entry.get("groups", []):
			if group is Dictionary:
				_patch_box.add_child(_patch_group(
					String(group.get("heading", "")), group.get("items", [])))


func _patch_group(heading: String, items: Array) -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 0)
	group.add_child(_mk_label(heading, 14, LauncherTheme.RED))
	var line := _hline()
	group.add_child(line)
	for i in items.size():
		if i > 0:
			var thin := ColorRect.new()
			thin.color = LauncherTheme.HAIRLINE
			thin.custom_minimum_size = Vector2(0, 1)
			group.add_child(thin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var bullet := ColorRect.new()
		bullet.color = LauncherTheme.RED
		bullet.custom_minimum_size = Vector2(9, 9)
		bullet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bullet)
		var text := Label.new()
		text.text = items[i]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_child(text)
		row.add_child(margin)
		group.add_child(row)
	return group


# -------------------------------------------------------- Ansicht: Roadmap

func _build_road_view() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)

	var pad := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(s, LauncherTheme.PADDING + 8)
	pad.add_child(col)

	col.add_child(_mk_label("ROADMAP", 36, LauncherTheme.INK))
	var sub := _mk_label("Woran wir wirklich arbeiten. Reihenfolge ist Absicht, Termine gibt es keine.", 14, LauncherTheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	col.add_child(spacer)

	_road_box = VBoxContainer.new()
	_road_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_road_box.add_theme_constant_override("separation", 0)
	var loading := Label.new()
	loading.text = "Lade Roadmap ..."
	loading.theme_type_variation = &"DimLabel"
	_road_box.add_child(loading)
	col.add_child(_road_box)

	scroll.add_child(pad)
	return scroll


## Die Roadmap kommt als roadmap.json vom Server — gepflegt wie die News.
func _load_roadmap() -> void:
	_http_road = HTTPRequest.new()
	add_child(_http_road)
	_http_road.request_completed.connect(_on_roadmap_response)
	_http_road.request("http://%s:%d/roadmap.json" % [SERVER, DOWNLOAD_PORT])


func _on_roadmap_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_http_road.queue_free()
	_http_road = null
	for child in _road_box.get_children():
		child.queue_free()

	var entries: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		entries = JSON.parse_string(body.get_string_from_utf8())
	if not (entries is Array) or (entries as Array).is_empty():
		var empty := Label.new()
		empty.text = "Keine Roadmap erreichbar."
		empty.theme_type_variation = &"DimLabel"
		_road_box.add_child(empty)
		return

	for entry in entries:
		if entry is Dictionary:
			_road_box.add_child(_road_phase(
				String(entry.get("quarter", "")),
				String(entry.get("status", "")),
				String(entry.get("kind", "plan")),
				entry.get("items", [])))


func _road_phase(quarter: String, status: String, kind: String, items: Array) -> Control:
	var phase := VBoxContainer.new()
	phase.add_theme_constant_override("separation", 0)

	var head := HBoxContainer.new()
	head.add_child(_mk_label(quarter, 20, LauncherTheme.INK))
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(stretch)
	head.add_child(_status_chip(status, kind))
	phase.add_child(head)

	var line := _hline()
	var line_pad := MarginContainer.new()
	line_pad.add_theme_constant_override("margin_top", 10)
	line_pad.add_theme_constant_override("margin_bottom", 6)
	line_pad.add_child(line)
	phase.add_child(line_pad)

	for i in items.size():
		if i > 0:
			var thin := ColorRect.new()
			thin.color = LauncherTheme.HAIRLINE
			thin.custom_minimum_size = Vector2(0, 1)
			phase.add_child(thin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var mark := ColorRect.new()
		mark.color = LauncherTheme.INK
		mark.custom_minimum_size = Vector2(9, 9)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mark)
		var text := Label.new()
		text.text = items[i]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_top", 9)
		margin.add_theme_constant_override("margin_bottom", 9)
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_child(text)
		row.add_child(margin)
		phase.add_child(row)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, LauncherTheme.PADDING + 8)
	phase.add_child(gap)
	return phase


## Status-Marke: LIVE rot gefüllt, IN ARBEIT rot umrandet, GEPLANT grau.
func _status_chip(text: String, kind: String) -> Control:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(0)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	var label_color := Color.WHITE
	match kind:
		"live":
			box.bg_color = LauncherTheme.RED
		"wip":
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = LauncherTheme.RED
			box.set_border_width_all(LauncherTheme.EDGE_WIDTH)
			label_color = LauncherTheme.RED
		_:
			box.bg_color = Color(0, 0, 0, 0)
			box.border_color = LauncherTheme.HAIRLINE
			box.set_border_width_all(LauncherTheme.EDGE_WIDTH)
			label_color = LauncherTheme.TEXT_DIM
	chip.add_theme_stylebox_override("panel", box)
	chip.add_child(_mk_label(text, 10, label_color))
	return chip


# ----------------------------------------------------- Rechte Spalte

func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(328, 0)
	side.add_theme_constant_override("separation", 0)

	# --- Installation ---
	var inst := _panel("INSTALLATION")
	var stand := Label.new()
	stand.name = "Stand"
	stand.theme_type_variation = &"MonoLabel"
	stand.text = "Prüfe ..."
	inst.content.add_child(stand)

	var dl := HBoxContainer.new()
	dl.add_child(_mk_label("Downloadgröße", 11, LauncherTheme.TEXT_DIM))
	var dl_stretch := Control.new()
	dl_stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.add_child(dl_stretch)
	_size_label = _mk_label("—", 14, LauncherTheme.INK)
	dl.add_child(_size_label)
	inst.content.add_child(dl)

	# Der ECHTE Installationsort — der Launcher legt das Spiel in sein
	# Benutzerverzeichnis, und genau das steht hier.
	var loc := _mk_label(ProjectSettings.globalize_path(GAME_DIR), 12, LauncherTheme.TEXT_DIM)
	loc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inst.content.add_child(loc)

	var verify := Button.new()
	verify.text = "Dateien überprüfen"
	verify.pressed.connect(_check_version)
	inst.content.add_child(verify)
	side.add_child(inst.panel)

	side.add_child(_hline())

	# --- Konto (Steam-Anmeldung + Spielername) ---
	var acct := _panel("KONTO")
	acct.panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_login_button = Button.new()
	_login_button.text = "Mit Steam anmelden"
	_login_button.pressed.connect(_start_steam_login)
	acct.content.add_child(_login_button)

	var name_heading := Label.new()
	name_heading.text = "Spielername"
	name_heading.theme_type_variation = &"DimLabel"
	acct.content.add_child(name_heading)

	_name_line = LineEdit.new()
	_name_line.placeholder_text = "Wie sollen dich die anderen sehen?"
	acct.content.add_child(_name_line)

	var hint := Label.new()
	hint.text = "Spielen geht auch als Gast — Anmeldung nur für Fortschritt."
	hint.theme_type_variation = &"DimLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acct.content.add_child(hint)
	side.add_child(acct.panel)
	return side


func _build_actionbar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 100)
	bar.add_theme_constant_override("separation", 0)

	# Version / Build.
	var verbox := VBoxContainer.new()
	verbox.alignment = BoxContainer.ALIGNMENT_CENTER
	verbox.custom_minimum_size = Vector2(150, 0)
	verbox.add_theme_constant_override("separation", 2)
	_version_label = _mk_label("—", 16, LauncherTheme.INK)
	verbox.add_child(_version_label)
	_installed_label = _mk_label("INSTALLIERT: —", 11, LauncherTheme.TEXT_DIM)
	verbox.add_child(_installed_label)
	var verpad := MarginContainer.new()
	for s in ["margin_left", "margin_right"]:
		verpad.add_theme_constant_override(s, LauncherTheme.PADDING)
	verpad.add_child(verbox)
	bar.add_child(verpad)

	bar.add_child(_vline())

	# Status + Fortschritt.
	var status_col := VBoxContainer.new()
	status_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_col.alignment = BoxContainer.ALIGNMENT_CENTER
	status_col.add_theme_constant_override("separation", 8)
	_status = Label.new()
	_status.text = "Prüfe auf Updates ..."
	status_col.add_child(_status)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.custom_minimum_size = Vector2(0, 10)
	_progress.show_percentage = false
	_progress.visible = false
	status_col.add_child(_progress)
	var status_pad := MarginContainer.new()
	for s in ["margin_left", "margin_right"]:
		status_pad.add_theme_constant_override(s, LauncherTheme.PADDING)
	status_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_pad.add_child(status_col)
	bar.add_child(status_pad)

	bar.add_child(_vline())

	# SPIELEN.
	_play_button = Button.new()
	_play_button.text = "SPIELEN"
	_play_button.theme_type_variation = &"PlayButton"
	_play_button.custom_minimum_size = Vector2(260, 0)
	_play_button.disabled = true
	_play_button.pressed.connect(_on_play_button_pressed)
	bar.add_child(_play_button)
	return bar


# ----------------------------------------------------- Einstellungen

func _build_settings_overlay() -> Control:
	# Abgedunkelter Hintergrund, faengt alle Klicks ab.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.13, 0.12, 0.11, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false

	# Zentriertes Blatt.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(660, 0)
	center.add_child(sheet)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	sheet.add_child(col)

	# Kopf: Titel + Schliessen.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.add_child(_mk_label("EINSTELLUNGEN", 22, LauncherTheme.INK))
	var head_stretch := Control.new()
	head_stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_stretch)
	head.add_child(_icon_button("X", func(): _settings_overlay.visible = false))
	col.add_child(head)
	col.add_child(_hline())

	var pad := MarginContainer.new()
	for s in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(s, LauncherTheme.PADDING)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	pad.add_child(rows)
	col.add_child(pad)

	# Nur Schalter, die wirklich etwas tun — Attrappen gehören nicht in
	# einen echten Launcher.
	rows.add_child(_section_head("ALLGEMEIN"))
	rows.add_child(_setting_row("Beim Start nach Updates suchen",
		_make_toggle("auto_update")))

	rows.add_child(_gap(LauncherTheme.PADDING))
	rows.add_child(_section_head("SPIEL"))
	rows.add_child(_setting_row("Launcher nach Spielstart schließen",
		_make_toggle("close_on_launch")))
	rows.add_child(_thin_line())
	var args := LineEdit.new()
	args.placeholder_text = "z. B. --fullscreen"
	args.text = _settings.get("launch_args", "")
	args.custom_minimum_size = Vector2(280, 0)
	args.text_changed.connect(func(t):
		_settings["launch_args"] = t
		_save_settings())
	rows.add_child(_setting_row("Startoptionen", args))
	rows.add_child(_thin_line())
	var loc_path := _mk_label(ProjectSettings.globalize_path(GAME_DIR), 12, LauncherTheme.TEXT_DIM)
	loc_path.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	loc_path.custom_minimum_size = Vector2(300, 0)
	rows.add_child(_setting_row("Speicherort", loc_path))
	rows.add_child(_thin_line())
	var repair := Button.new()
	repair.text = "Spiel neu herunterladen"
	repair.pressed.connect(func():
		_settings_overlay.visible = false
		# Reparieren heißt: frisch holen, nicht nur nachsehen.
		if _remote_version != "":
			_start_download()
		else:
			_check_version())
	rows.add_child(_setting_row("Dateien prüfen & reparieren", repair))

	rows.add_child(_gap(LauncherTheme.PADDING))
	rows.add_child(_section_head("KONTO"))
	var logout := Button.new()
	logout.text = "Abmelden"
	logout.pressed.connect(_logout)
	rows.add_child(_setting_row("Steam-Anmeldung", logout))

	col.add_child(_hline())
	var foot := HBoxContainer.new()
	foot.add_child(_mk_label("Extraction Launcher · " + LAUNCHER_VERSION, 11, LauncherTheme.TEXT_DIM))
	var foot_stretch := Control.new()
	foot_stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(foot_stretch)
	var done := Button.new()
	done.text = "Fertig"
	done.pressed.connect(func(): _settings_overlay.visible = false)
	foot.add_child(done)
	col.add_child(foot)
	return backdrop


func _section_head(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_mk_label(text, 12, LauncherTheme.RED))
	box.add_child(_hline())
	return box


func _setting_row(label: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LauncherTheme.PADDING)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.add_child(row)
	var text := _mk_label(label, 14, LauncherTheme.INK)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return pad


func _thin_line() -> ColorRect:
	var line := ColorRect.new()
	line.color = LauncherTheme.HAIRLINE
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	return gap


## Roter Fuellkasten fuer den aktiven Zustand von Toggles/Segmenten.
func _accent_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = LauncherTheme.RED
	box.border_color = LauncherTheme.RED
	box.set_border_width_all(LauncherTheme.EDGE_WIDTH)
	box.set_corner_radius_all(0)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


func _paint_active(button: Button, active: bool) -> void:
	if active:
		button.add_theme_stylebox_override("normal", _accent_box())
		button.add_theme_stylebox_override("hover", _accent_box())
		button.add_theme_stylebox_override("pressed", _accent_box())
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
	else:
		for key in ["normal", "hover", "pressed"]:
			button.remove_theme_stylebox_override(key)
		for key in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.remove_theme_color_override(key)


## Ein-Aus-Schalter aus einem Toggle-Button (AN rot, AUS Papier).
func _make_toggle(id: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(84, 0)
	var on: bool = _settings.get(id, false)
	button.button_pressed = on
	button.text = "AN" if on else "AUS"
	_paint_active(button, on)
	button.toggled.connect(func(pressed):
		button.text = "AN" if pressed else "AUS"
		_paint_active(button, pressed)
		_settings[id] = pressed
		_save_settings())
	return button


func _logout() -> void:
	_token = ""
	_steam_id = ""
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))
	_login_status.text = "Nicht angemeldet"
	_settings_overlay.visible = false


func _load_settings() -> void:
	_settings = {
		auto_update = true,
		close_on_launch = true,
		launch_args = "",
		last_played = 0.0,
	}
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_FILE))
	if data is Dictionary:
		for key in data:
			_settings[key] = data[key]


func _save_settings() -> void:
	if not _settings_ready:
		return
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(_settings))


## Ein Panel im Modernist-Look: Papierfläche, kräftige Tintenkante,
## optionale Überschrift oben. Gibt Panel und Inhalts-Behälter zurück.
func _panel(heading: String) -> Dictionary:
	var panel := PanelContainer.new()
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	if heading != "":
		var label := Label.new()
		label.text = heading
		label.theme_type_variation = &"PanelTitle"
		content.add_child(label)
	return {panel = panel, content = content}


func _set_status(text: String) -> void:
	_status.remove_theme_color_override("font_color")
	_status.text = text


func _set_ready() -> void:
	_state = State.READY
	_play_button.text = "SPIELEN"
	_play_button.disabled = false
	_set_status("Bereit. Der Server wartet.")
	_pulse_play_button()


## Ein Update liegt bereit, wird aber NIE von selbst geladen — der Tester
## entscheidet per Klick, wann die Bandbreite drauf geht (z. B. nicht
## mitten in einer laufenden Testsitzung). Derselbe Knopf, der sonst
## SPIELEN heißt, wird so lange zum Download-Auslöser.
func _prompt_download(status_text: String) -> void:
	_state = State.NEEDS_UPDATE
	_play_button.text = "HERUNTERLADEN"
	_play_button.disabled = false
	_set_status(status_text)
	_pulse_play_button()


## Ein ruhiges Pulsieren sagt: Hier geht es weiter.
func _pulse_play_button() -> void:
	if _pulse == null or not _pulse.is_valid():
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_play_button, "modulate",
			Color(1.12, 1.09, 1.03), 0.9).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(_play_button, "modulate",
			Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)


## SPIELEN und HERUNTERLADEN teilen sich denselben Knopf — was ein Klick
## auslöst, hängt vom Zustand ab (siehe _prompt_download/_set_ready).
func _on_play_button_pressed() -> void:
	if _state == State.NEEDS_UPDATE:
		_start_download()
	else:
		_play()


func _refresh_version_label() -> void:
	var local := _local_version if _local_version != "" else "nicht installiert"
	var remote := _remote_version if _remote_version != "" else "?"
	_version_label.text = remote
	_installed_label.text = "INSTALLIERT: " + local
	# Über den Baum gesucht statt gemerkt: Das Label wohnt im Installations-Panel.
	for label in _all_labels(self):
		if label.name == "Stand":
			label.text = "installiert  %s\naktuell      %s" % [local, remote]


func _all_labels(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Label:
			found.append(child)
		found.append_array(_all_labels(child))
	return found


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
	_http_version.queue_free()
	_http_version = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# Kein Server heißt nicht kein Spiel: Was installiert ist, bleibt
		# spielbar — nur eben ohne Update-Garantie.
		if FileAccess.file_exists(GAME_EXE):
			_set_ready()
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
	_remote_sha256 = String(data.get("sha256", ""))
	# Die echte Downloadgröße steht im Manifest — nichts wird geschätzt.
	if data.has("size_mb") and _size_label != null:
		_size_label.text = "%d MB" % int(data.size_mb)
	_refresh_version_label()

	if _remote_version == _local_version and FileAccess.file_exists(GAME_EXE):
		_set_ready()
	else:
		_prompt_download("Version %s bereit — HERUNTERLADEN klicken." % _remote_version)


func _start_download() -> void:
	_download_attempt += 1
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
	_http_download.queue_free()
	_http_download = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_retry_or_fail("Download fehlgeschlagen (Code %d)" % code)
		return
	if not _remote_sha256.is_empty():
		_set_status("Prüfe Download ...")
		var actual := _sha256_of_file(GAME_DIR + "/download.zip")
		if actual != _remote_sha256.to_lower():
			_retry_or_fail("Download beschädigt (Prüfsumme falsch)")
			return
	_download_attempt = 0
	_unpack()


## Ein einzelner kaputter Download ist meistens nur ein Netzwerk-Aussetzer —
## deshalb einmal automatisch neu versuchen, statt den Tester sofort zur
## Handarbeit ("Dateien überprüfen") zu schicken. Bleibt es beim zweiten
## Mal kaputt, ist es vermutlich kein Zufall mehr.
func _retry_or_fail(message: String) -> void:
	_cleanup_partial_download()
	if _download_attempt < 2:
		_set_status("%s — versuche erneut ..." % message)
		_start_download()
	else:
		_download_attempt = 0
		_fail(message + " — auch nach erneutem Versuch")


func _cleanup_partial_download() -> void:
	var path := GAME_DIR + "/download.zip"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Berechnet den SHA-256-Hash einer Datei blockweise — Downloads (Spiel wie
## Launcher) können zu groß fürs Auf-einmal-Einlesen sein.
func _sha256_of_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var remaining := file.get_length()
	while remaining > 0:
		var chunk_size: int = min(remaining, 65536)
		ctx.update(file.get_buffer(chunk_size))
		remaining -= chunk_size
	file.close()
	return ctx.finish().hex_encode()


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
	_set_ready()


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
	_status.text = "FEHLER: " + message
	_status.add_theme_color_override("font_color", LauncherTheme.RED)


# ------------------------------------------------------- Launcher-Selbst-Update
#
# Gleiches Prinzip wie beim Spiel, aber für die eigene .exe: ein Manifest
# (launcher_version.json, veröffentlicht mit tools/publish_launcher.ps1)
# nennt Version, Dateiname und SHA-256. Ist die Serverversion neuer, wird
# die neue .exe heruntergeladen, ihre Prüfsumme verifiziert, und ein
# kleines Batch-Skript tauscht sie gegen die laufende .exe aus, sobald
# dieser Prozess sich beendet hat. Ohne Server oder bei Abweichung passiert
# einfach nichts — die installierte Version läuft normal weiter.

func _check_launcher_update() -> void:
	_http_launcher_version = HTTPRequest.new()
	add_child(_http_launcher_version)
	_http_launcher_version.request_completed.connect(_on_launcher_version_response)
	_http_launcher_version.request("http://%s:%d/launcher_version.json" % [SERVER, DOWNLOAD_PORT])


func _on_launcher_version_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_http_launcher_version.queue_free()
	_http_launcher_version = null
	# Kein Manifest erreichbar oder keins veröffentlicht: einfach weiterlaufen.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or not data.has("version") or not data.has("file"):
		return
	if not _is_newer(String(data.version), LAUNCHER_VERSION):
		return
	_launcher_update_sha256 = String(data.get("sha256", ""))
	_download_launcher_update(String(data.file))


## Numerischer Versionsvergleich ("1.2" vs "1.10") — ein reiner Stringvergleich
## würde "1.10" fälschlich als älter als "1.2" einstufen.
func _is_newer(remote: String, local: String) -> bool:
	var remote_parts := remote.split(".")
	var local_parts := local.split(".")
	for i in maxi(remote_parts.size(), local_parts.size()):
		var remote_value := int(remote_parts[i]) if i < remote_parts.size() else 0
		var local_value := int(local_parts[i]) if i < local_parts.size() else 0
		if remote_value != local_value:
			return remote_value > local_value
	return false


func _download_launcher_update(filename: String) -> void:
	_set_status("Lade neue Launcher-Version ...")
	_http_launcher_download = HTTPRequest.new()
	add_child(_http_launcher_download)
	_http_launcher_download.download_file = LAUNCHER_UPDATE_FILE
	_http_launcher_download.request_completed.connect(_on_launcher_update_downloaded)
	var error := _http_launcher_download.request(
		"http://%s:%d/%s" % [SERVER, DOWNLOAD_PORT, filename])
	if error != OK:
		push_warning("Launcher-Update: Download startet nicht")


func _on_launcher_update_downloaded(result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_http_launcher_download.queue_free()
	_http_launcher_download = null
	# Ein gescheitertes Selbst-Update darf niemals den normalen Start
	# verhindern — im Zweifel läuft die installierte Version einfach weiter.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Launcher-Update: Download fehlgeschlagen (Code %d)" % code)
		_delete_if_exists(LAUNCHER_UPDATE_FILE)
		return
	if not _launcher_update_sha256.is_empty():
		var actual := _sha256_of_file(LAUNCHER_UPDATE_FILE)
		if actual != _launcher_update_sha256.to_lower():
			push_warning("Launcher-Update: Prüfsumme falsch — breche ab")
			_delete_if_exists(LAUNCHER_UPDATE_FILE)
			return
	_apply_launcher_update()


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Windows lässt eine laufende .exe nicht durch sich selbst überschreiben —
## deshalb übernimmt ein kleines Batch-Skript den Tausch: warten, bis dieser
## Prozess sich beendet hat, kopieren, neu starten, sich selbst löschen.
## Das Skript startet noch VOR dem eigenen _fail()/quit(), läuft also mit
## dem Prozess um die Wette — daher die Wiederholschleife statt eines
## einzelnen Versuchs.
func _apply_launcher_update() -> void:
	var current_exe := OS.get_executable_path()
	var new_exe := ProjectSettings.globalize_path(LAUNCHER_UPDATE_FILE)
	var script_path := ProjectSettings.globalize_path(LAUNCHER_UPDATE_SCRIPT)
	var lines := PackedStringArray([
		"@echo off",
		":wait",
		"timeout /t 1 /nobreak > nul",
		"copy /y \"%s\" \"%s\" > nul" % [new_exe, current_exe],
		"if errorlevel 1 goto wait",
		"del \"%s\"" % new_exe,
		"start \"\" \"%s\"" % current_exe,
		"del \"%~f0\"",
	])
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		push_warning("Launcher-Update: Update-Skript lässt sich nicht schreiben")
		return
	file.store_string("\r\n".join(lines))
	file.close()
	_set_status("Starte neue Version ...")
	OS.create_process("cmd.exe", ["/c", script_path])
	get_tree().quit()


func _process(_delta: float) -> void:
	if _state == State.DOWNLOADING and _http_download != null:
		var total := _http_download.get_body_size()
		if total > 0:
			_progress.value = float(_http_download.get_downloaded_bytes()) / float(total)
	_poll_steam_callback()


# --------------------------------------------------------------------- News

func _load_news() -> void:
	_http_news = HTTPRequest.new()
	add_child(_http_news)
	_http_news.request_completed.connect(_on_news_response)
	_http_news.request("http://%s:%d/news.json" % [SERVER, DOWNLOAD_PORT])


func _on_news_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_http_news.queue_free()
	_http_news = null
	for child in _news_box.get_children():
		child.queue_free()

	var entries: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		entries = JSON.parse_string(body.get_string_from_utf8())
	if not (entries is Array) or (entries as Array).is_empty():
		_hero_title.text = "EXTRACTION SHOOTER"
		_hero_text.text = "Multiplayer-Beta — Server gerade nicht erreichbar."
		var empty := Label.new()
		empty.text = "Keine Nachrichten erreichbar."
		empty.theme_type_variation = &"DimLabel"
		_news_box.add_child(empty)
		return

	# Die neueste Nachricht wird zum Hero, der Rest zur Liste darunter.
	var first: Dictionary = (entries as Array)[0]
	_hero_kicker.text = String(first.get("date", "AUS DER BETA"))
	_hero_title.text = String(first.get("title", "")).to_upper()
	_hero_text.text = first.get("text", "")

	var rest: Array = (entries as Array).slice(1)
	if rest.is_empty():
		var quiet := Label.new()
		quiet.text = "Keine weiteren Meldungen."
		quiet.theme_type_variation = &"DimLabel"
		_news_box.add_child(quiet)
	for entry in rest:
		if not (entry is Dictionary):
			continue
		var title := Label.new()
		title.text = "%s  —  %s" % [entry.get("date", ""), entry.get("title", "")]
		title.theme_type_variation = &"NewsTitle"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_news_box.add_child(title)

		var text := Label.new()
		text.text = entry.get("text", "")
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_news_box.add_child(text)


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
	_http_auth.queue_free()
	_http_auth = null
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
	# Eigene Startoptionen aus den Einstellungen anhaengen.
	var extra: String = _settings.get("launch_args", "").strip_edges()
	if not extra.is_empty():
		for part in extra.split(" ", false):
			args.append(part)
	if OS.create_process(exe, args) > 0:
		_set_status("Spiel gestartet — viel Erfolg da draußen.")
		_settings["last_played"] = Time.get_unix_time_from_system()
		_save_settings()
		if _last_played_label != null:
			_last_played_label.text = _format_last_played()
		if _settings.get("close_on_launch", true):
			get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit())
	else:
		_fail("Spiel liess sich nicht starten")
