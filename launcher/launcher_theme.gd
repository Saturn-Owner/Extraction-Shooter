## Das Aussehen des Launchers — ALLE Stellschrauben in dieser einen Datei.
##
## Wer am Design drehen will, dreht hier: Farben, Schriften, Kanten,
## Abstände. Der Aufbau der Oberfläche (launcher.gd) fragt nur noch nach
## Theme-Typen und kennt keine einzige Farbe selbst.
##
## Stilrichtung: Modernist / "Red Snow". Schnee-weisser Grund, tiefschwarze
## Tinte, harte 2px-Kanten und Null-Rundung. Ein einziges Signal-Rot traegt
## Marke, Aktiv-Zustand, SPIELEN und alles Dringende — sonst ist alles Tinte
## auf Papier. Flaechen werden nicht gefuellt, Struktur machen die Linien.
class_name LauncherTheme

# ------------------------------------------------------------------ Farben
## Der Schnee-Grund und die Panel-Flaeche eine Spur darunter.
const BACKGROUND := Color("f3f2f2")
const PANEL := Color("eae9e9")
## Tiefschwarze Tinte — Text und alle tragenden Kanten.
const INK := Color("201e1d")
const PANEL_EDGE := Color("201e1d")
const TEXT := Color("201e1d")
const TEXT_DIM := Color("7d7979")
## Feine Trennlinien: Tinte, aber durchscheinend (Neutral-300).
const HAIRLINE := Color("d7d3d3")
## Primaer- und einziger Akzent: Marke, Aktiv-Balken, SPIELEN, Fortschritt.
const RED := Color("ec3013")
const RED_HOVER := Color("ae1800")
const RED_PRESSED := Color("7c1405")
## Hover-Fuellung fuer ruhige Knoepfe (Neutral-200).
const HOVER_FILL := Color("eae7e7")
const PRESSED_FILL := Color("d7d3d3")

# ---------------------------------------------------------------- Maße
## Null Rundung — Modernist zeichnet nur rechte Winkel.
const CORNER := 0
## Kraeftige 2px-Kante statt Haarlinie.
const EDGE_WIDTH := 2
## Der rote Aktiv-Balken am linken Rand des gewaehlten Menuepunkts.
const STRIPE_WIDTH := 5.0
const PADDING := 16
const GAP := 12

# ---------------------------------------------------------------- Schriften

## Archivo traegt das ganze System — Ueberschriften wie Fliesstext, fett und
## grotesk. Fehlt sie (Tester ohne Archivo), faellt Godot lautlos auf die
## naechste Grotesk zurueck.
static func heading_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = ["Archivo", "Archivo Black", "Arial"]
	return font


## Auch Status/Version stehen in Archivo — Modernist kennt keine zweite Stimme.
## (Als Konstante behalten, falls anderswo eine Schmalschrift gebraucht wird.)
static func mono_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = ["Archivo", "Consolas", "Courier New"]
	return font


# ------------------------------------------------------------------ Theme

static func build() -> Theme:
	var theme := Theme.new()
	var heading := heading_font()
	var mono := mono_font()

	# --- Panels: Papier-Flaeche, kraeftige Tinten-Kante, keine Rundung ---
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = INK
	panel.set_border_width_all(EDGE_WIDTH)
	panel.set_corner_radius_all(CORNER)
	panel.set_content_margin_all(PADDING)
	theme.set_stylebox("panel", "PanelContainer", panel)

	# --- Normale Knoepfe: Papier mit Tinten-Kante, Hover fuellt grau ---
	theme.set_font("font", "Button", heading)
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", RED)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_stylebox("normal", "Button", _button_box(BACKGROUND, INK))
	theme.set_stylebox("hover", "Button", _button_box(HOVER_FILL, INK))
	theme.set_stylebox("pressed", "Button", _button_box(PRESSED_FILL, INK))
	theme.set_stylebox("disabled", "Button", _button_box(BACKGROUND, HAIRLINE))
	theme.set_stylebox("focus", "Button", _focus_box())

	# --- Der SPIELEN-Knopf: volle Rot-Flaeche, weisse Schrift ---
	theme.set_type_variation(&"PlayButton", &"Button")
	theme.set_font_size("font_size", "PlayButton", 30)
	theme.set_color("font_color", "PlayButton", Color.WHITE)
	theme.set_color("font_hover_color", "PlayButton", Color.WHITE)
	theme.set_color("font_pressed_color", "PlayButton", Color.WHITE)
	theme.set_color("font_disabled_color", "PlayButton", Color("eae7e7"))
	theme.set_stylebox("normal", "PlayButton", _button_box(RED, RED))
	theme.set_stylebox("hover", "PlayButton", _button_box(RED_HOVER, RED_HOVER))
	theme.set_stylebox("pressed", "PlayButton", _button_box(RED_PRESSED, RED_PRESSED))
	theme.set_stylebox("disabled", "PlayButton", _button_box(Color("bab6b6"), Color("bab6b6")))

	# --- Eingabefelder: Papier, Tinten-Kante, Fokus schaltet auf Rot ---
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", RED)
	var line := _button_box(BACKGROUND, INK)
	theme.set_stylebox("normal", "LineEdit", line)
	theme.set_stylebox("focus", "LineEdit", _button_box(BACKGROUND, RED))

	# --- Fortschrittsbalken: Rot auf grauer Rinne, keine Rundung ---
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color("d7d3d3")
	trough.set_border_width_all(0)
	trough.set_corner_radius_all(CORNER)
	var fill := StyleBoxFlat.new()
	fill.bg_color = RED
	fill.set_corner_radius_all(CORNER)
	theme.set_stylebox("background", "ProgressBar", trough)
	theme.set_stylebox("fill", "ProgressBar", fill)

	# --- Label-Spielarten ---
	theme.set_color("font_color", "Label", INK)

	# Der grosse Hero-Titel (WHITEOUT) — steht weiss ueber der Key-Art.
	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_font("font", "TitleLabel", heading)
	theme.set_font_size("font_size", "TitleLabel", 72)
	theme.set_color("font_color", "TitleLabel", Color.WHITE)

	# Abschnitts-Ueberschrift (INSTALLATION, KONTO) — kleine, dunkle Grotesk.
	theme.set_type_variation(&"PanelTitle", &"Label")
	theme.set_font("font", "PanelTitle", heading)
	theme.set_font_size("font_size", "PanelTitle", 13)
	theme.set_color("font_color", "PanelTitle", Color("605d5d"))

	theme.set_type_variation(&"DimLabel", &"Label")
	theme.set_color("font_color", "DimLabel", TEXT_DIM)

	# Version/Status/Build — ebenfalls Archivo, gedaempft.
	theme.set_type_variation(&"MonoLabel", &"Label")
	theme.set_font("font", "MonoLabel", mono)
	theme.set_font_size("font_size", "MonoLabel", 12)
	theme.set_color("font_color", "MonoLabel", Color("605d5d"))

	# News-Kicker (PATCH, ZONE, EVENT) — das rote Signal ueber der Kachel.
	theme.set_type_variation(&"NewsTitle", &"Label")
	theme.set_font("font", "NewsTitle", heading)
	theme.set_font_size("font_size", "NewsTitle", 15)
	theme.set_color("font_color", "NewsTitle", RED)

	return theme


static func _button_box(background: Color, edge: Color = INK) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = edge
	box.set_border_width_all(EDGE_WIDTH)
	box.set_corner_radius_all(CORNER)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 9.0
	box.content_margin_bottom = 9.0
	return box


## Tastatur-Fokus: 2px roter Rahmen statt des Browser-/Godot-Standards.
static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = RED
	box.set_border_width_all(EDGE_WIDTH)
	box.set_corner_radius_all(CORNER)
	return box
