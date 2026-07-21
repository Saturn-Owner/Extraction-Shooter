## Das Aussehen des Launchers — ALLE Stellschrauben in dieser einen Datei.
##
## Wer am Design drehen will, dreht hier: Farben, Schriften, Kanten,
## Abstände. Der Aufbau der Oberfläche (launcher.gd) fragt nur noch nach
## Theme-Typen und kennt keine einzige Farbe selbst.
##
## Stilrichtung: Militärakte. Fast-schwarzer Grund, kantige Panels mit
## dünner Kante und farbigem Aktenstreifen links, Oliv für Ruhiges,
## Signal-Orange für alles, was Aufmerksamkeit will.
class_name LauncherTheme

# ------------------------------------------------------------------ Farben
const BACKGROUND := Color("0d0f10")
const PANEL := Color("16191b")
const PANEL_EDGE := Color("2a2f33")
const TEXT := Color("c8ccc9")
const TEXT_DIM := Color("7a807c")
## Sekundär-Akzent: Anmeldung, Bestätigung, Ruhe.
const OLIVE := Color("5a6b4a")
const OLIVE_BRIGHT := Color("7d925f")
## Primär-Akzent: SPIELEN, Fortschritt, alles Dringende.
const ORANGE := Color("d97b29")
const ORANGE_BRIGHT := Color("f09441")
const RED := Color("b5442e")

# ---------------------------------------------------------------- Maße
const CORNER := 2
const EDGE_WIDTH := 1
## Der Aktenstreifen am linken Panelrand.
const STRIPE_WIDTH := 3.0
const PADDING := 16
const GAP := 12

# ---------------------------------------------------------------- Schriften

## Kantige Überschriften-Schrift, die jedes Windows dabei hat.
## Fehlt sie (Linux-Tester), fällt Godot lautlos auf die Standardschrift.
static func heading_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = ["Bahnschrift", "Arial Narrow"]
	return font


## Dienstliche Schreibmaschinen-Schrift für Versionen und Status.
static func mono_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = ["Consolas", "Courier New"]
	return font


# ------------------------------------------------------------------ Theme

static func build() -> Theme:
	var theme := Theme.new()
	var heading := heading_font()
	var mono := mono_font()

	# --- Panels: dunkle Fläche, feine Kante, kaum Rundung ---
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = PANEL_EDGE
	panel.set_border_width_all(EDGE_WIDTH)
	panel.set_corner_radius_all(CORNER)
	panel.set_content_margin_all(PADDING)
	theme.set_stylebox("panel", "PanelContainer", panel)

	# --- Normale Knöpfe: dunkel, Hover schärft die Kante zum Akzent ---
	theme.set_font("font", "Button", heading)
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_stylebox("normal", "Button", _button_box(Color("1c2023"), PANEL_EDGE))
	theme.set_stylebox("hover", "Button", _button_box(Color("22272a"), OLIVE_BRIGHT))
	theme.set_stylebox("pressed", "Button", _button_box(Color("101314"), OLIVE))
	theme.set_stylebox("disabled", "Button", _button_box(Color("141719"), Color("1e2224")))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# --- Der SPIELEN-Knopf: volle Orange-Fläche, dunkle Schrift ---
	theme.set_type_variation(&"PlayButton", &"Button")
	theme.set_font_size("font_size", "PlayButton", 26)
	theme.set_color("font_color", "PlayButton", Color("141414"))
	theme.set_color("font_hover_color", "PlayButton", Color("000000"))
	theme.set_color("font_disabled_color", "PlayButton", TEXT_DIM)
	theme.set_stylebox("normal", "PlayButton", _button_box(ORANGE, ORANGE))
	theme.set_stylebox("hover", "PlayButton", _button_box(ORANGE_BRIGHT, ORANGE_BRIGHT))
	theme.set_stylebox("pressed", "PlayButton", _button_box(Color("b5661f"), Color("b5661f")))
	theme.set_stylebox("disabled", "PlayButton", _button_box(Color("2a221a"), Color("3a2f22")))

	# --- Eingabefelder ---
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	var line := _button_box(Color("101314"), PANEL_EDGE)
	theme.set_stylebox("normal", "LineEdit", line)
	theme.set_stylebox("focus", "LineEdit", _button_box(Color("101314"), OLIVE_BRIGHT))

	# --- Fortschrittsbalken: Orange auf dunkler Rinne ---
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color("101314")
	trough.border_color = PANEL_EDGE
	trough.set_border_width_all(1)
	trough.set_corner_radius_all(CORNER)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ORANGE
	fill.set_corner_radius_all(CORNER)
	theme.set_stylebox("background", "ProgressBar", trough)
	theme.set_stylebox("fill", "ProgressBar", fill)

	# --- Label-Spielarten ---
	theme.set_color("font_color", "Label", TEXT)

	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_font("font", "TitleLabel", heading)
	theme.set_font_size("font_size", "TitleLabel", 30)
	theme.set_color("font_color", "TitleLabel", Color.WHITE)

	theme.set_type_variation(&"PanelTitle", &"Label")
	theme.set_font("font", "PanelTitle", heading)
	theme.set_font_size("font_size", "PanelTitle", 15)
	theme.set_color("font_color", "PanelTitle", TEXT_DIM)

	theme.set_type_variation(&"DimLabel", &"Label")
	theme.set_color("font_color", "DimLabel", TEXT_DIM)

	theme.set_type_variation(&"MonoLabel", &"Label")
	theme.set_font("font", "MonoLabel", mono)
	theme.set_font_size("font_size", "MonoLabel", 13)
	theme.set_color("font_color", "MonoLabel", TEXT_DIM)

	theme.set_type_variation(&"NewsTitle", &"Label")
	theme.set_font("font", "NewsTitle", heading)
	theme.set_font_size("font_size", "NewsTitle", 16)
	theme.set_color("font_color", "NewsTitle", ORANGE_BRIGHT)

	return theme


static func _button_box(background: Color, edge: Color = PANEL_EDGE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = edge
	box.set_border_width_all(EDGE_WIDTH)
	box.set_corner_radius_all(CORNER)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box
