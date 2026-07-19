## Der Charakterbildschirm: Ausrüstung und Gesundheit.
##
## ---------------------------------------------------------------------------
## AUFBAU (nach dem Vorbild aus Arena Breakout)
##
##   Reiter oben     Ausrüstung  |  Gesundheit
##   Mitte           die Figur, links und rechts davon die Ausrüstungsplätze,
##                   daneben das Rasterinventar
##   unten           Trefferpunkte, Energie, Wasser, Gewicht, Wärme
##
## Es gibt genau EIN Fenster dafür, und es liegt auf Tab. Ausrüstung, Zustand
## und Rucksack gehören zusammen — wer im Raid nachsieht, was er dabeihat,
## will meist auch wissen, wie es ihm geht.
##
## Beide Reiter zeigen DIESELBE Figur, nur unterschiedlich eingefärbt:
## unter "Ausrüstung" neutral grau, unter "Gesundheit" nach Zustand von Grün
## bis Rot. Eine Zeichenroutine, zwei Bedeutungen — und der Spieler sieht
## sofort, dass es derselbe Körper ist.
##
## Die Figur ist selbst gezeichnet, kein 3D-Modell: sieben Umrisse, die
## aneinanderstossen und zusammen eine menschliche Silhouette ergeben. Ein
## richtiges Modell kommt, wenn es Charaktermodelle gibt.
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

## Die Waffenplätze stehen unter der Figur, nebeneinander — wie in der
## Vorlage, und weil 1 und 2 nebeneinander liegende Tasten sind.
const WEAPON_SLOTS := [
	ItemData.EquipSlot.PRIMARY,
	ItemData.EquipSlot.SECONDARY,
]

var player: PlayerController = null

var _tab: Tab = Tab.AUSRUESTUNG
var _selected: HealthSystem.Part = HealthSystem.Part.CHEST

# --- Ziehen im Raster (vormals das eigene Inventarfenster) ------------------
var _drag_stack: ItemStack = null
var _drag_offset: Vector2i = Vector2i.ZERO
var _drag_target_cell: Vector2i = Vector2i(-1, -1)

## Ob beim Anfassen Strg gedrueckt war — dann wird nach der Menge gefragt.
var _drag_ctrl: bool = false

var _split_stack: ItemStack = null
var _split_cell: Vector2i = Vector2i(-1, -1)

## Wie der Gegenstand lag, bevor er angefasst wurde — siehe LootWindow.
var _drag_original_rotated: bool = false

## Slot -> der Knopf, der ihn darstellt.
var _slot_buttons: Dictionary = {}

@onready var _tab_equipment: Button = $Layout/Inhalt/Reiter/Ausruestung
@onready var _tab_health: Button = $Layout/Inhalt/Reiter/Gesundheit
@onready var _left_column: VBoxContainer = $Layout/Inhalt/Mitte/Links
@onready var _right_column: VBoxContainer = $Layout/Inhalt/Mitte/Rechts
@onready var _figure: Control = $Layout/Inhalt/Mitte/Figur/Zeichnung
@onready var _figure_hint: Label = $Layout/Inhalt/Mitte/Figur/Hinweis
@onready var _weapons_row: HBoxContainer = $Layout/Inhalt/Mitte/Figur/Waffen
@onready var _inventory_column: VBoxContainer = $Layout/Inhalt/Mitte/Inventar
@onready var _inventory_view: InventoryGridView = $Layout/Inhalt/Mitte/Inventar/Raster
@onready var _inventory_title: Label = $Layout/Inhalt/Mitte/Inventar/Titel
@onready var _stats: HBoxContainer = $Layout/Inhalt/Werte
@onready var _effects: Label = $Layout/Inhalt/Auswirkung
@onready var _ghost: DragGhost = $DragGhost
@onready var _split_prompt: SplitPrompt = $SplitPrompt
@onready var _tooltip: ItemTooltip = $ItemTooltip


func _ready() -> void:
	hide()
	_figure.draw.connect(_draw_figure)
	_figure.gui_input.connect(_on_figure_input)
	_tab_equipment.pressed.connect(_switch_tab.bind(Tab.AUSRUESTUNG))
	_tab_health.pressed.connect(_switch_tab.bind(Tab.GESUNDHEIT))

	# cell_released bleibt ungenutzt — siehe LootWindow: das Loslassen geht
	# immer an das Control, auf dem gedrueckt wurde.
	_inventory_view.item_pressed.connect(_on_item_pressed)
	_inventory_view.item_double_clicked.connect(_on_item_double_clicked)
	_inventory_view.item_hovered.connect(_on_item_hovered)
	_split_prompt.confirmed.connect(_on_split_confirmed)
	_split_prompt.cancelled.connect(_on_split_cancelled)

	_build_slots()
	_switch_tab(Tab.AUSRUESTUNG)


func open_for(p_player: PlayerController) -> void:
	player = p_player
	# Das Raster liegt direkt neben der Ausruestung: Was man anzieht und was
	# man dabeihat, gehoert auf einen Blick zusammen.
	if player.inventory != null:
		_inventory_view.setup(player.inventory.grid, "Inventar")
	show()
	_refresh()
	opened.emit()


func close() -> void:
	if _split_prompt != null and _split_prompt.is_open():
		_split_prompt.cancel()
	if _tooltip != null:
		_tooltip.clear()
	_cancel_drag()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if not visible:
		return

	if _drag_stack != null:
		_update_drag_target()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			drop_at(_drag_target_cell)

	if player != null:
		_refresh()


func _switch_tab(tab: Tab) -> void:
	# Das Raster verschwindet gleich — ein Gegenstand darf nicht am Zeiger
	# haengen bleiben, wenn das Feld darunter nicht mehr da ist.
	_cancel_drag()
	if _tooltip != null:
		_tooltip.clear()

	_tab = tab
	_tab_equipment.button_pressed = tab == Tab.AUSRUESTUNG
	_tab_health.button_pressed = tab == Tab.GESUNDHEIT

	# Die Plaetze verschwinden unter "Gesundheit" — dort geht es um den
	# Koerper, und halb ausgeblendete Knoepfe daneben lenken nur ab.
	_left_column.visible = tab == Tab.AUSRUESTUNG
	_right_column.visible = tab == Tab.AUSRUESTUNG
	_weapons_row.visible = tab == Tab.AUSRUESTUNG
	_inventory_column.visible = tab == Tab.AUSRUESTUNG
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
	for slot in WEAPON_SLOTS:
		_weapons_row.add_child(_make_slot(slot))


## Ein Platz: Beschriftung darüber, darunter das Feld — wie in der Vorlage.
func _make_slot(slot: ItemData.EquipSlot) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var caption := Label.new()
	# Die Taste steht dabei: Wer die Waffe im Fenster sieht, soll wissen,
	# womit er sie im Gefecht zieht, ohne erst zu probieren.
	var key := ""
	if slot == ItemData.EquipSlot.PRIMARY:
		key = "  [1]"
	elif slot == ItemData.EquipSlot.SECONDARY:
		key = "  [2]"
	caption.text = Equipment.get_slot_name(slot) + key
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

	# Ein Klick auf einen Waffenplatz ZIEHT die Waffe, statt sie abzulegen.
	# Das ist der haeufigere Wunsch, und Ablegen bleibt ueber das Raster
	# moeglich. Umgekehrt waere es eine Falle: Wer im Gefecht wechseln will,
	# steht ploetzlich mit leeren Haenden da.
	if Equipment.is_weapon_slot(slot):
		player.select_weapon_slot(slot)
		_refresh()
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

		var is_weapon := Equipment.is_weapon_slot(slot)
		var is_active: bool = is_weapon and player.active_weapon_slot == slot

		if worn == null:
			button.text = "leer"
			button.disabled = true
			button.tooltip_text = ""
			button.add_theme_color_override("font_color", Color(0.32, 0.34, 0.37))
			continue

		var data := worn.get_data()
		button.disabled = false

		# Die Waffe in der Hand wird markiert — sonst weiss man nach einem
		# Wechsel nicht mehr, welche man gerade traegt.
		var label := data.display_name if data != null else "?"
		button.text = ("> " + label) if is_active else label

		if data != null:
			button.tooltip_text = "%s\n%s\n\n%s" % [
				data.display_name,
				data.get_type_label(),
				"Klicken nimmt sie in die Hand" if is_weapon else "Klicken legt ab",
			]
			var color := ItemTooltip.get_rarity_color(data.get_rarity())
			button.add_theme_color_override("font_color",
				color if not is_active else color.lerp(Color.WHITE, 0.45))


# ---------------------------------------------------------------------------
# Die Figur
# ---------------------------------------------------------------------------

## Die Umrisse der Körperteile, in Anteilen der Zeichenfläche.
##
## Vorher waren das sieben Rechtecke — verständlich, aber es sah aus wie ein
## Bauplan, nicht wie ein Mensch. Die Flächen stossen bewusst aneinander:
## Zwischen Brust und Bauch soll keine Lücke klaffen, sonst zerfällt der
## Körper optisch in Einzelteile.
##
## Links und rechts sind aus SICHT DES SPIELERS gemeint, also gespiegelt zum
## Bild — die Figur schaut einen an. Ein Treffer am linken Arm leuchtet damit
## rechts im Fenster auf, so wie im Spiegel.
const BODY_SHAPES := {
	HealthSystem.Part.HEAD: [
		Vector2(0.445, 0.020), Vector2(0.555, 0.020), Vector2(0.585, 0.055),
		Vector2(0.575, 0.105), Vector2(0.540, 0.130), Vector2(0.540, 0.152),
		Vector2(0.460, 0.152), Vector2(0.460, 0.130), Vector2(0.425, 0.105),
		Vector2(0.415, 0.055),
	],
	HealthSystem.Part.CHEST: [
		Vector2(0.460, 0.150), Vector2(0.540, 0.150), Vector2(0.680, 0.200),
		Vector2(0.700, 0.245), Vector2(0.672, 0.400), Vector2(0.328, 0.400),
		Vector2(0.300, 0.245), Vector2(0.320, 0.200),
	],
	HealthSystem.Part.STOMACH: [
		Vector2(0.328, 0.400), Vector2(0.672, 0.400), Vector2(0.660, 0.505),
		Vector2(0.640, 0.560), Vector2(0.360, 0.560), Vector2(0.340, 0.505),
	],
	HealthSystem.Part.RIGHT_ARM: [
		Vector2(0.320, 0.200), Vector2(0.300, 0.245), Vector2(0.328, 0.400),
		Vector2(0.315, 0.470), Vector2(0.290, 0.560), Vector2(0.205, 0.545),
		Vector2(0.215, 0.400), Vector2(0.230, 0.250),
	],
	HealthSystem.Part.LEFT_ARM: [
		Vector2(0.680, 0.200), Vector2(0.770, 0.250), Vector2(0.785, 0.400),
		Vector2(0.795, 0.545), Vector2(0.710, 0.560), Vector2(0.685, 0.470),
		Vector2(0.672, 0.400), Vector2(0.700, 0.245),
	],
	HealthSystem.Part.RIGHT_LEG: [
		Vector2(0.360, 0.560), Vector2(0.496, 0.560), Vector2(0.496, 0.760),
		Vector2(0.470, 0.940), Vector2(0.475, 0.985), Vector2(0.375, 0.985),
		Vector2(0.372, 0.940), Vector2(0.348, 0.760),
	],
	HealthSystem.Part.LEFT_LEG: [
		Vector2(0.504, 0.560), Vector2(0.640, 0.560), Vector2(0.652, 0.760),
		Vector2(0.628, 0.940), Vector2(0.625, 0.985), Vector2(0.525, 0.985),
		Vector2(0.530, 0.940), Vector2(0.504, 0.760),
	],
}


func _poly_for(part: HealthSystem.Part) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point: Vector2 in BODY_SHAPES[part]:
		scaled.append(point * _figure.size)
	return scaled


## Der Mittelpunkt einer Fläche — dorthin kommt die Zahl.
func _center_of(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point: Vector2 in poly:
		sum += point
	return sum / maxf(1.0, float(poly.size()))


func _draw_figure() -> void:
	if player == null or player.health == null:
		return

	var font := ThemeDB.fallback_font
	var show_health := _tab == Tab.GESUNDHEIT

	for part: HealthSystem.Part in BODY_SHAPES:
		var poly := _poly_for(part)
		var ratio := player.health.get_ratio(part)

		# Unter "Ausruestung" neutral, unter "Gesundheit" nach Zustand.
		# Ein zerstoertes Glied bleibt aber IMMER schwarz — das ist zu
		# wichtig, um es hinter einem Reiter zu verstecken.
		var fill := COLOR_NEUTRAL
		if show_health or ratio <= 0.0:
			fill = _color_for(ratio)
		_figure.draw_colored_polygon(poly, fill)

		var selected: bool = show_health and part == _selected
		var outline := poly.duplicate()
		outline.append(poly[0])
		_figure.draw_polyline(outline, COLOR_SELECTED if selected else COLOR_OUTLINE,
			2.0 if selected else 1.0, true)

		if not show_health:
			continue

		var text := "%d" % roundi(player.health.get_hp(part))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var pos := _center_of(poly) + Vector2(-width * 0.5, 4.0)
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

	for part: HealthSystem.Part in BODY_SHAPES:
		if Geometry2D.is_point_in_polygon(button.position, _poly_for(part)):
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

	if player.inventory != null and player.inventory.grid != null:
		var grid := player.inventory.grid
		_inventory_title.text = "Inventar  —  %d von %d Feldern frei" % [
			grid.get_free_cell_count(), grid.width * grid.height]
		_inventory_view.queue_redraw()

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


# ---------------------------------------------------------------------------
# Das Raster: Ziehen, Drehen, Stapel teilen
#
# Das stand frueher in einem eigenen Inventarfenster auf Taste C. Es gibt
# jetzt nur noch dieses eine Fenster auf Tab — zwei Fenster fuer denselben
# Rucksack waren eine Frage zu viel beim Oeffnen.
# ---------------------------------------------------------------------------

func _on_item_hovered(stack: ItemStack, _source: InventoryGridView) -> void:
	if stack == null or _drag_stack != null:
		_tooltip.clear()
		return
	_tooltip.show_for(stack)


func _on_item_pressed(stack: ItemStack, view: InventoryGridView) -> void:
	if _split_prompt.is_open():
		return

	_drag_stack = stack
	_drag_ctrl = Input.is_key_pressed(KEY_CTRL)
	_drag_original_rotated = stack.rotated
	_tooltip.clear()

	var origin := view.grid.get_position(stack.instance_id)
	var local := view.get_local_mouse_position()
	var grabbed := view.position_to_cell(local)
	_drag_offset = grabbed - origin if grabbed.x >= 0 and origin.x >= 0 else Vector2i.ZERO
	var pixel_offset := local - view.cell_to_position(origin) if origin.x >= 0 else Vector2.ZERO

	_ghost.show_stack(stack, pixel_offset)
	_inventory_view.drag_stack = stack
	_inventory_view.drag_source = view
	_inventory_view.preview_cell = Vector2i(-1, -1)
	_inventory_view.queue_redraw()


func _update_drag_target() -> void:
	_drag_target_cell = Vector2i(-1, -1)
	if _inventory_view.get_global_rect().has_point(get_global_mouse_position()):
		var cell := _inventory_view.position_to_cell(_inventory_view.get_local_mouse_position())
		if cell.x >= 0:
			_drag_target_cell = cell - _drag_offset
	_inventory_view.preview_cell = _drag_target_cell
	_inventory_view.queue_redraw()


func drop_at(cell: Vector2i) -> void:
	if _drag_stack == null:
		return
	if cell.x < 0 or cell.y < 0:
		_cancel_drag()
		return

	# Mit Strg wird nach der Menge gefragt, statt alles zu verschieben.
	if _drag_ctrl and _drag_stack.quantity > 1:
		_split_stack = _drag_stack
		_split_cell = cell
		var data := _split_stack.get_data()
		_split_prompt.ask(
			data.display_name if data != null else "Aufteilen",
			_split_stack.quantity,
			get_global_mouse_position()
		)
		_cancel_drag()
		return

	# Auf einen passenden Stapel drauflegen, statt am belegten Feld zu scheitern.
	var moved := false
	var existing := _inventory_view.grid.get_stack_at(cell.x, cell.y)
	if existing != null and existing.can_merge_with(_drag_stack):
		existing.merge_from(_drag_stack)
		if _drag_stack.quantity <= 0:
			_inventory_view.grid.remove_item(_drag_stack.instance_id)
		_inventory_view.grid.changed.emit()
		moved = true
	else:
		moved = _inventory_view.grid.move_item(_drag_stack.instance_id, cell.x, cell.y)

	# Nur ein wirklich umgezogener Gegenstand behaelt seine neue Lage.
	if moved:
		_drag_original_rotated = _drag_stack.rotated

	_cancel_drag()


func _on_split_confirmed(amount: int) -> void:
	var stack := _split_stack
	var cell := _split_cell
	_split_stack = null
	_split_cell = Vector2i(-1, -1)

	if stack == null or amount >= stack.quantity:
		return

	var part := stack.split(amount)
	if part == null:
		return

	var leftover := _inventory_view.grid.place_or_merge(part, cell.x, cell.y)
	if leftover != null:
		# Passte nicht: zurueck auf den Ursprungsstapel, nichts geht verloren.
		stack.quantity += leftover.quantity
		return

	_inventory_view.queue_redraw()


func _on_split_cancelled() -> void:
	_split_stack = null
	_split_cell = Vector2i(-1, -1)


## Doppelklick nimmt eine Waffe in die Hand — sie wandert dabei auf den
## freien Waffenplatz. Bei allem anderen passiert bewusst nichts: ein
## versehentliches Wegwerfen im Raid waere fatal.
func _on_item_double_clicked(stack: ItemStack, _source: InventoryGridView) -> void:
	if player == null:
		return
	var data := stack.get_data()
	if data == null or data.category != ItemData.Category.WEAPON:
		return
	player.equip_from_inventory(stack)
	_refresh()


## R dreht den Gegenstand, der gerade am Zeiger haengt.
##
## Frueher drehte R den Gegenstand AN ORT UND STELLE. Das scheiterte fast
## immer, weil quer genau dort selten Platz ist. Jetzt dreht sich nur die
## Anzeige am Zeiger, geprueft wird erst beim Ablegen.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _drag_stack == null:
		return
	var key := event as InputEventKey
	if key == null or not key.is_pressed() or key.is_echo():
		return
	if key.physical_keycode != KEY_R:
		return

	var data := _drag_stack.get_data()
	if data == null or not data.can_rotate:
		return

	_drag_stack.rotated = not _drag_stack.rotated
	_drag_offset = Vector2i(_drag_offset.y, _drag_offset.x)
	_ghost.grab_offset = Vector2(_ghost.grab_offset.y, _ghost.grab_offset.x)
	_update_drag_target()
	get_viewport().set_input_as_handled()


func _cancel_drag() -> void:
	# Nicht abgelegt: Er liegt noch auf seinem alten Platz und muss wieder
	# so herum liegen wie vorher.
	if _drag_stack != null and _drag_stack.rotated != _drag_original_rotated:
		_drag_stack.rotated = _drag_original_rotated

	_drag_stack = null
	_drag_offset = Vector2i.ZERO
	_drag_target_cell = Vector2i(-1, -1)
	_drag_ctrl = false
	if _ghost != null:
		_ghost.clear()
	if _inventory_view != null:
		_inventory_view.drag_stack = null
		_inventory_view.drag_source = null
		_inventory_view.preview_cell = Vector2i(-1, -1)
		_inventory_view.queue_redraw()

