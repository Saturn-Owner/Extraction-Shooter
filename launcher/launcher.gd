## Der Launcher: Steam-Anmeldung, Auto-Update, News, Spielen.
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

const SESSION_FILE := "user://session.json"
const SETTINGS_FILE := "user://settings.json"
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
var _http_news: HTTPRequest

var _status: Label
var _login_status: Label
var _login_button: Button
var _name_line: LineEdit
var _play_button: Button
var _progress: ProgressBar
var _version_label: Label
var _news_box: VBoxContainer

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
	# Automatische Update-Suche laesst sich in den Einstellungen abschalten.
	if _settings.get("auto_update", true):
		_check_version()
	elif FileAccess.file_exists(GAME_EXE):
		_set_ready()
		_set_status("Automatische Update-Suche aus — starte installierte Version")
	else:
		_set_status("Automatische Update-Suche aus — „Dateien überprüfen\" für Update")
	_load_news()


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
	var brand_label := _mk_label("RED SNOW", 20, LauncherTheme.INK)
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

	var note := Label.new()
	note.text = "Zuletzt gespielt · vor 2 Tagen"
	note.theme_type_variation = &"DimLabel"
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pad := MarginContainer.new()
	for s in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(s, LauncherTheme.PADDING)
	pad.add_child(note)
	bar.add_child(pad)
	return bar


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

	var cap := _mk_label("[ KEY ART · 1920×1080 hier ablegen ]", 11, Color(1, 1, 1, 0.5))
	hero_col.add_child(cap)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_col.add_child(spacer)
	hero_col.add_child(_mk_label("NEUE SAISON · JETZT LIVE", 13, LauncherTheme.RED))
	var title := Label.new()
	title.text = "WHITEOUT"
	title.theme_type_variation = &"TitleLabel"
	hero_col.add_child(title)
	var lede := _mk_label("Ein Schneesturm hat die Karte verschluckt. Sicht unter zwanzig Metern, die Extraktionspunkte wandern, und der letzte Heli hebt zur vollen Stunde ab — ob ihr an Bord seid oder nicht.", 14, Color(1, 1, 1, 0.82))
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lede.custom_minimum_size = Vector2(0, 0)
	hero_col.add_child(lede)
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
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", LauncherTheme.PADDING + 8)

	var pad := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(s, LauncherTheme.PADDING + 8)
	pad.add_child(col)

	# Kopf: große rote Version + Datum.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(_mk_label("v0.8.4", 48, LauncherTheme.RED))
	var meta := VBoxContainer.new()
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(_mk_label("19. JULI 2026", 14, LauncherTheme.INK))
	meta.add_child(_mk_label("AKTUELLE VERSION", 11, LauncherTheme.TEXT_DIM))
	head.add_child(meta)
	col.add_child(head)

	col.add_child(_patch_group("BALANCE", [
		"Ausdauer regeneriert 12 % langsamer bei über 70 % Traglast.",
		"Nahkampfschaden des „Kithife\" um 8 % gesenkt.",
		"Streuung der DMR-Klasse im Anschlag um 15 % verringert.",
	]))
	col.add_child(_patch_group("NETCODE", [
		"Tickrate der Extraktionszonen von 30 auf 60 angehoben.",
		"Rubberbanding beim Heli-Extrakt in Randregionen behoben.",
		"Server wählt die Region jetzt nach Ping statt nach Standort.",
	]))
	col.add_child(_patch_group("FEHLERBEHEBUNGEN", [
		"Absturz beim Betreten des Kühlhauses behoben.",
		"Inventar-Sortierung merkt sich die zuletzt gewählte Reihenfolge.",
		"Falsch angezeigte Versicherungs-Rückgabezeiten korrigiert.",
	]))

	scroll.add_child(pad)
	return scroll


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
	var sub := _mk_label("Wohin Red Snow im nächsten Jahr steuert. Termine sind Richtwerte, keine Versprechen.", 14, LauncherTheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	col.add_child(spacer)

	col.add_child(_road_phase("Q3 2026", "LIVE", "live", [
		"Saison 2 „Whiteout\" — Schneesturm-Wetter & Sichtsystem",
		"Neue Extraktion: Kühlhaus (Nordsektor)",
		"Überarbeiteter Ausdauer- & Traglast-Haushalt",
	]))
	col.add_child(_road_phase("Q4 2026", "IN ARBEIT", "wip", [
		"Fraktions-Ruf — Händler-Freischaltungen & Aufträge",
		"Neue Waffenklasse: DMR",
		"Nacht-Raids mit Nachtsicht-Ausrüstung",
	]))
	col.add_child(_road_phase("Q1 2027", "GEPLANT", "plan", [
		"Koop-PvE-Missionen gegen die KI-Fraktion",
		"Unterschlupf-Ausbau — Werkbank & Lager",
		"Ranglisten-Saison mit eigenem Belohnungspfad",
	]))

	scroll.add_child(pad)
	return scroll


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
	dl.add_child(_mk_label("2,7 GB", 14, LauncherTheme.INK))
	inst.content.add_child(dl)

	var loc := _mk_label("E:\\Games\\Red Snow", 12, LauncherTheme.TEXT_DIM)
	loc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inst.content.add_child(loc)

	var verify := Button.new()
	verify.text = "Dateien überprüfen"
	verify.pressed.connect(_check_version)
	inst.content.add_child(verify)

	var relocate := Button.new()
	relocate.text = "Speicherort ändern"
	inst.content.add_child(relocate)
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
	_version_label = _mk_label("v—", 16, LauncherTheme.INK)
	verbox.add_child(_version_label)
	verbox.add_child(_mk_label("BUILD 20260719", 11, LauncherTheme.TEXT_DIM))
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
	_play_button.pressed.connect(_play)
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

	rows.add_child(_section_head("ALLGEMEIN"))
	rows.add_child(_setting_row("Sprache",
		_make_segment("language", ["Deutsch", "English"])))
	rows.add_child(_thin_line())
	rows.add_child(_setting_row("Server-Region",
		_make_segment("region", ["EU-Nord", "EU-West", "NA-Ost"])))
	rows.add_child(_thin_line())
	rows.add_child(_setting_row("Beim Start nach Updates suchen",
		_make_toggle("auto_update")))
	rows.add_child(_thin_line())
	rows.add_child(_setting_row("Ins Tray minimieren statt schließen",
		_make_toggle("minimize_to_tray")))

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
	var loc := HBoxContainer.new()
	loc.add_theme_constant_override("separation", 10)
	var loc_path := _mk_label("E:\\Games\\Red Snow", 12, LauncherTheme.TEXT_DIM)
	loc_path.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	loc.add_child(loc_path)
	var loc_btn := Button.new()
	loc_btn.text = "Ändern"
	loc.add_child(loc_btn)
	rows.add_child(_setting_row("Speicherort", loc))
	rows.add_child(_thin_line())
	var repair := Button.new()
	repair.text = "Spiel reparieren"
	repair.pressed.connect(func():
		_settings_overlay.visible = false
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
	foot.add_child(_mk_label("Red Snow Launcher · v0.8.4 · build 20260719", 11, LauncherTheme.TEXT_DIM))
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


## Segmentierte Auswahl: eine Reihe Toggle-Buttons, genau einer aktiv.
func _make_segment(id: String, options: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	var current: String = _settings.get(id, options[0])
	for i in options.size():
		if i > 0:
			row.add_child(_vline())
		var opt: String = options[i]
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.text = opt
		button.add_theme_font_size_override("font_size", 13)
		var active: bool = opt == current
		button.button_pressed = active
		_paint_active(button, active)
		button.toggled.connect(func(pressed):
			_paint_active(button, pressed)
			if pressed:
				_settings[id] = opt
				_save_settings())
		row.add_child(button)
	return row


func _logout() -> void:
	_token = ""
	_steam_id = ""
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))
	_login_status.text = "Nicht angemeldet"
	_settings_overlay.visible = false


func _load_settings() -> void:
	_settings = {
		language = "Deutsch",
		region = "EU-Nord",
		auto_update = true,
		close_on_launch = true,
		minimize_to_tray = false,
		launch_args = "",
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
	_play_button.disabled = false
	_set_status("Bereit. Der Server wartet.")
	# Ein ruhiges Pulsieren sagt: Hier geht es weiter.
	if _pulse == null or not _pulse.is_valid():
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_play_button, "modulate",
			Color(1.12, 1.09, 1.03), 0.9).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(_play_button, "modulate",
			Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)


func _refresh_version_label() -> void:
	var local := _local_version if _local_version != "" else "nicht installiert"
	var remote := _remote_version if _remote_version != "" else "?"
	_version_label.text = "v" + remote
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
	_refresh_version_label()

	if _remote_version == _local_version and FileAccess.file_exists(GAME_EXE):
		_set_ready()
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
	for child in _news_box.get_children():
		child.queue_free()

	var entries: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		entries = JSON.parse_string(body.get_string_from_utf8())
	if not (entries is Array) or (entries as Array).is_empty():
		var empty := Label.new()
		empty.text = "Keine Nachrichten erreichbar."
		empty.theme_type_variation = &"DimLabel"
		_news_box.add_child(empty)
		return

	for entry in entries:
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
		if _settings.get("close_on_launch", true):
			get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit())
	else:
		_fail("Spiel liess sich nicht starten")
