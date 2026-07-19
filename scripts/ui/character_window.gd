## Der Charakterbildschirm: Ausrüstung und Gesundheit.
##
## ---------------------------------------------------------------------------
## AUFBAU (nach dem Vorbild aus Arena Breakout)
##
##   Reiter oben     Ausrüstung  |  Gesundheit
##   Mitte           die Figur, links und rechts davon die Ausrüstungsplätze
##   unten           Trefferpunkte, Energie, Wasser, Gewicht, Wärme
##
## Beide Reiter zeigen DIESELBE Figur, nur unterschiedlich eingefärbt:
## unter "Ausrüstung" neutral grau, unter "Gesundheit" nach Zustand von Grün
## bis Rot. Eine Zeichenroutine, zwei Bedeutungen — und der Spieler sieht
## sofort, dass es derselbe Körper ist.
##
## Die Figur ist selbst gezeichnet, kein 3D-Modell: Sieben Flächen genügen,
## um Kopf, Rumpf, Arme und Beine zu unterscheiden. Ein richtiges Modell
## kommt, wenn es Charaktermodelle gibt.
class_name CharacterWindow
extends Control

signal closed()
signal opened()

const COLOR_HEALTHY := Color(0.42, 0.66, 0.40)
const COLOR_HURT := Color(0.80, 0.70, 0.30)
const COLOR_CRITICAL := Color(0.78, 0.30, 0.24)
const COLOR_DESTROYED := Color(0.10, 0.10, 0.11)
const COLOR_NEUTRAL := Color(0.20, 0.215, 0.235)
const COLOR_OUTLINE := Color(0.33, 0.36, 0.40)
const COLOR_SELECTED := Color(0.85, 0.86, 0.88)

## Ein leerer Platz. Bewusst sehr dunkel — belegte Plätze sollen auffallen.
const COLOR_SLOT_EMPTY := Color(0.075, 0.080, 0.088)
const COLOR_SLOT_BORDER := Color(0.21, 0.225, 0.245)

enum Tab { AUSRUESTUNG, GESUNDHEIT }

## Welche Plätze links und rechts der Figur stehen — wie am Körper verteilt.
const LEFT_SLOTS := [
	ItemData.EquipSlot.HEAD,
	ItemData.EquipSlot.SHIRT,
	ItemData.EquipSlot.BELT,
]
const RIGHT_SLOTS := [
	ItemData.EquipSlot.CHEST,
	ItemData.EquipSlot.PANTS,
	ItemData.EquipSlot.BOOTS,
	ItemData.EquipSlot.BACKPACK,
]

var player: PlayerController = null

var _tab: Tab = Tab.AUSRUESTUNG
var _selected: HealthSystem.Part = HealthSystem.Part.CHEST

## Slot -> der Knopf, der ihn darstellt.
var _slot_buttons: Dictionary = {}

@onready var _tab_equipment: Button = $Layout/Inhalt/Reiter/Ausruestung
@onready var _tab_health: Button = $Layout/Inhalt/Reiter/Gesundheit
@onready var _left_column: VBoxContainer = $Layout/Inhalt/Mitte/Links
@onready var _right_column: VBoxContainer = $Layout/Inhalt/Mitte/Rechts
@onready var _figure: Control = $Layout/Inhalt/Mitte/Figur/Zeichnung
@onready var _figure_hint: Label = $Layout/Inhalt/Mitte/Figur/Hinweis
@onready var _stats: HBoxContainer = $Layout/Inhalt/Werte
@onready var _effects: Label = $Layout/Inhalt/Auswirkung


func _ready() -> void:
	hide()
	_figure.draw.connect(_draw_figure)
	_figure.gui_input.connect(_on_figure_input)
	_tab_equipment.pressed.connect(_switch_tab.bind(Tab.AUSRUESTUNG))
	_tab_health.pressed.connect(_switch_tab.bind(Tab.GESUNDHEIT))
	_build_slots()
	_switch_tab(Tab.AUSRUESTUNG)


func open_for(p_player: PlayerController) -> void:
	player = p_player
	show()
	_refresh()
	opened.emit()


func close() -> void:
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if visible and player != null:
		_refresh()


func _switch_tab(tab: Tab) -> void:
	_tab = tab
	_tab_equipment.button_pressed = tab == Tab.AUSRUESTUNG
	_tab_health.button_pressed = tab == Tab.GESUNDHEIT

	# Die Plaetze verschwinden unter "Gesundheit" — dort geht es um den
	# Koerper, und halb ausgeblendete Knoepfe daneben lenken nur ab.
	_left_column.visible = tab == Tab.AUSRUESTUNG
	_right_column.visible = tab == Tab.AUSRUESTUNG
	_effects.visible = tab == Tab.GESUNDHEIT

	_figure_hint.text = "Klicken zeigt Einzelheiten" if tab == Tab.GESUNDHEIT else ""
	_figure.queue_redraw()


# ---------------------------------------------------------------------------
# Ausrüstungsplätze
# ---------------------------------------------------------------------------

func _build_slots() -> void:
	for slot in LEFT_SLOTS:
		_left_column.add_child(_make_slot(slot))
	for slot in RIGHT_SLOTS:
		_right_column.add_child(_make_slot(slot))


## Ein Platz: Beschriftung darüber, darunter das Feld — wie in der Vorlage.
func _make_slot(slot: ItemData.EquipSlot) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var caption := Label.new()
	caption.text = Equipment.get_slot_name(slot)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.60, 0.63, 0.67))
	box.add_child(caption)

	var button := Button.new()
	button.custom_minimum_size = Vector2(132, 74)
	button.clip_text = true
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(_on_slot_pressed.bind(slot))
	box.add_child(button)

	_slot_buttons[slot] = button
	return box


## Klick auf einen belegten Platz legt ab — zurueck ins Inventar.
##
## Passt es dort nicht, bleibt es an. Etwas fallen zu lassen, weil kein Platz
## ist, waere im Raid ein stiller Verlust.
func _on_slot_pressed(slot: ItemData.EquipSlot) -> void:
	if player == null or player.equipment == null:
		return

	var worn := player.equipment.get_item(slot)
	if worn == null:
		return
	if not player.inventory.grid.add_item(worn):
		return

	player.equipment.unequip(slot)
	_refresh()


func _refresh_slots() -> void:
	if player == null or player.equipment == null:
		return

	for slot in _slot_buttons:
		var button: Button = _slot_buttons[slot]
		var worn: ItemStack = player.equipment.get_item(slot)

		if worn == null:
			button.text = "leer"
			button.disabled = true
			button.tooltip_text = ""
			button.add_theme_color_override("font_color", Color(0.32, 0.34, 0.37))
			continue

		var data := worn.get_data()
		button.disabled = false
		button.text = data.display_name if data != null else "?"
		if data != null:
			button.tooltip_text = "%s\n%s\n\nKlicken legt ab" % [
				data.display_name, data.get_type_label()]
			button.add_theme_color_override("font_color",
				ItemTooltip.get_rarity_color(data.get_rarity()))


# ---------------------------------------------------------------------------
# Die Figur
# ---------------------------------------------------------------------------

## Wo die Körperteile liegen, in Anteilen der Zeichenfläche.
const BODY_RECTS := {
	HealthSystem.Part.HEAD: Rect2(0.38, 0.02, 0.24, 0.13),
	HealthSystem.Part.CHEST: Rect2(0.30, 0.17, 0.40, 0.22),
	HealthSystem.Part.STOMACH: Rect2(0.32, 0.40, 0.36, 0.16),
	HealthSystem.Part.LEFT_ARM: Rect2(0.11, 0.17, 0.17, 0.34),
	HealthSystem.Part.RIGHT_ARM: Rect2(0.72, 0.17, 0.17, 0.34),
	HealthSystem.Part.LEFT_LEG: Rect2(0.30, 0.58, 0.18, 0.40),
	HealthSystem.Part.RIGHT_LEG: Rect2(0.52, 0.58, 0.18, 0.40),
}


func _rect_for(part: HealthSystem.Part) -> Rect2:
	var r: Rect2 = BODY_RECTS[part]
	return Rect2(r.position * _figure.size, r.size * _figure.size)


func _draw_figure() -> void:
	if player == null or player.health == null:
		return

	var font := ThemeDB.fallback_font
	var show_health := _tab == Tab.GESUNDHEIT

	for part in BODY_RECTS:
		var rect := _rect_for(part)
		var ratio := player.health.get_ratio(part)

		# Unter "Ausruestung" neutral, unter "Gesundheit" nach Zustand.
		# Ein zerstoertes Glied bleibt aber IMMER schwarz — das ist zu
		# wichtig, um es hinter einem Reiter zu verstecken.
		var fill := COLOR_NEUTRAL
		if show_health or ratio <= 0.0:
			fill = _color_for(ratio)
		_figure.draw_rect(rect, fill)

		var selected: bool = show_health and part == _selected
		_figure.draw_rect(rect, COLOR_SELECTED if selected else COLOR_OUTLINE,
			false, 2.0 if selected else 1.0)

		if not show_health:
			continue

		var text := "%d" % roundi(player.health.get_hp(part))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var pos := rect.position + Vector2((rect.size.x - width) * 0.5, rect.size.y * 0.5 + 4.0)
		_figure.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.95, 0.96, 0.97) if ratio > 0.0 else Color(0.62, 0.24, 0.20))


func _color_for(ratio: float) -> Color:
	if ratio <= 0.0:
		return COLOR_DESTROYED
	if ratio > 0.5:
		return COLOR_HURT.lerp(COLOR_HEALTHY, (ratio - 0.5) * 2.0)
	return COLOR_CRITICAL.lerp(COLOR_HURT, ratio * 2.0)


func _on_figure_input(event: InputEvent) -> void:
	if _tab != Tab.GESUNDHEIT:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return

	for part in BODY_RECTS:
		if _rect_for(part).has_point(button.position):
			_selected = part
			_figure.queue_redraw()
			return


# ---------------------------------------------------------------------------
# Werteleiste
# ---------------------------------------------------------------------------

## Ein Wert in der unteren Leiste: Beschriftung und Zahl.
func _make_stat(key: String, caption: String) -> Control:
	var box := VBoxContainer.new()
	box.name = key
	box.add_theme_constant_override("separation", 1)

	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	box.add_child(label)

	var value := Label.new()
	value.name = "Wert"
	value.text = "-"
	value.add_theme_font_size_override("font_size", 15)
	box.add_child(value)

	return box


func _ensure_stats_built() -> void:
	if _stats.get_child_count() > 0:
		return
	_stats.add_child(_make_stat("hp", "Trefferpunkte"))
	_stats.add_child(_make_stat("energie", "Energie"))
	_stats.add_child(_make_stat("wasser", "Wasser"))
	_stats.add_child(_make_stat("waerme", "Koerperwaerme"))
	_stats.add_child(_make_stat("last", "Traglast"))
	_stats.add_child(_make_stat("tempo", "Tempo"))


func _set_stat(key: String, text: String, color: Color) -> void:
	var box := _stats.get_node_or_null(key)
	if box == null:
		return
	var value := box.get_node_or_null("Wert") as Label
	if value == null:
		return
	value.text = text
	value.add_theme_color_override("font_color", color)


## Gruen bei gut, Gelb ab 40 %, Rot ab 15 %.
func _value_color(ratio: float) -> Color:
	if ratio > 0.4:
		return Color(0.72, 0.80, 0.72)
	if ratio > 0.15:
		return COLOR_HURT
	return COLOR_CRITICAL


func _refresh() -> void:
	if player == null:
		return

	_ensure_stats_built()
	_figure.queue_redraw()
	_refresh_slots()
	_refresh_stats()

	if _tab == Tab.GESUNDHEIT:
		_effects.text = _describe_condition()


func _refresh_stats() -> void:
	if player.health != null:
		var hp := player.health.get_total_hp()
		var max_hp := HealthSystem.get_total_max_hp()
		_set_stat("hp", "%d / %d" % [roundi(hp), roundi(max_hp)],
			_value_color(hp / maxf(1.0, max_hp)))

	if player.survival != null:
		var s := player.survival
		_set_stat("energie", "%d %%" % roundi(s.get_hunger_ratio() * 100.0),
			_value_color(s.get_hunger_ratio()))
		_set_stat("wasser", "%d %%" % roundi(s.get_thirst_ratio() * 100.0),
			_value_color(s.get_thirst_ratio()))
		_set_stat("waerme", "%.1f Grad" % s.temperature,
			_value_color(s.get_warmth_ratio()))

	_set_stat("last", "%.2f kg" % player.carried_weight_kg, Color(0.78, 0.80, 0.82))

	# Tempo als Prozent des normalen Gehtempos: Ein Wert, der alles
	# zusammenfasst — Gewicht, Verletzungen und Kaelte.
	var speed := player.get_weight_factor() * player.get_condition_factor()
	_set_stat("tempo", "%d %%" % roundi(speed * 100.0), _value_color(speed))


func _refresh_detail() -> void:
	pass


## Sagt in Worten, was die Werte gerade anrichten. Ein Balken allein erklaert
## nicht, warum man ploetzlich langsamer laeuft.
func _describe_condition() -> String:
	var notes: Array[String] = []

	if player.health != null:
		var name := HealthSystem.get_part_name(_selected)
		notes.append("%s:  %d / %d" % [
			name,
			roundi(player.health.get_hp(_selected)),
			roundi(HealthSystem.get_max_hp(_selected)),
		])
		if HealthSystem.is_vital(_selected):
			notes.append("Lebenswichtig — faellt es aus, ist der Raid vorbei.")
		elif player.health.is_destroyed(_selected):
			notes.append("Ausgefallen. Weitere Treffer gehen auf die Brust.")
		notes.append("")

		var legs := player.health.get_movement_penalty()
		if legs > 0.0:
			notes.append("Beinverletzung:  %d %% langsamer" % roundi(legs * 100.0))
		var arms := player.health.get_aim_penalty()
		if arms > 0.0:
			notes.append("Armverletzung:  %d %% unruhiger" % roundi(arms * 100.0))
		if player.health.is_destroyed(HealthSystem.Part.STOMACH):
			notes.append("Bauchverletzung:  Hunger und Durst steigen schneller")

	if player.survival != null:
		var cold := player.survival.get_cold_movement_penalty()
		if cold > 0.0:
			notes.append("Unterkuehlt:  %d %% langsamer" % roundi(cold * 100.0))
		if player.survival.hunger <= 0.0:
			notes.append("Verhungert:  laufender Schaden am Bauch")
		if player.survival.thirst <= 0.0:
			notes.append("Verdurstet:  laufender Schaden am Bauch")
		if player.survival.temperature <= player.survival.critical_temperature:
			notes.append("Erfrierungen:  Schaden an Armen und Beinen")

	return "\n".join(notes)
