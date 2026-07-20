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
## Beide Reiter zeigen DIESELBE Figur, gleich eingefärbt: nach Zustand von
## Grün bis Rot. Der Gesundheitsreiter zeigt zusätzlich die Trefferpunkte in
## jedem Körperteil, den Auswahlrahmen und den Zustandstext darunter —
## derselbe Körper, einmal auf einen Blick und einmal mit Einzelheiten.
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

## Aus welchem Raster gezogen wird und in welches gerade gezielt wird.
## Seit es den Rucksack gibt, sind es zwei — vorher genuegte das eine.
var _drag_source: InventoryGridView = null
var _drag_target_view: InventoryGridView = null

## Aus welchem Ausruestungsplatz gezogen wird (NONE = aus dem Raster),
## und auf welchen gerade gezielt wird.
var _drag_from_slot: ItemData.EquipSlot = ItemData.EquipSlot.NONE
var _drag_target_slot: ItemData.EquipSlot = ItemData.EquipSlot.NONE

## Ob beim Anfassen Strg gedrueckt war — dann wird nach der Menge gefragt.
var _drag_ctrl: bool = false

## Worauf sich das offene Kontextmenue bezieht.
var _menu_stack: ItemStack = null

var _split_stack: ItemStack = null
var _split_target: InventoryGridView = null
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
@onready var _context_menu: ContextMenu = $ContextMenu
@onready var _container_window: ContainerWindow = $ContainerWindow
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
	for view: InventoryGridView in [_inventory_view, _container_window.view]:
		view.item_pressed.connect(_on_item_pressed)
		view.item_double_clicked.connect(_on_item_double_clicked)
		view.item_hovered.connect(_on_item_hovered)
		view.item_right_clicked.connect(_on_item_right_clicked)

	_context_menu.chosen.connect(_on_menu_chosen)
	_container_window.closed.connect(_cancel_drag)
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
	if _context_menu != null:
		_context_menu.close()
	# Das schwebende Fenster gehoert diesem hier und geht mit ihm zu. Sonst
	# stuende der Rucksackinhalt noch auf dem Bild, waehrend man weiterlaeuft.
	if _container_window != null:
		_container_window.close()
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
			if _drag_target_slot != ItemData.EquipSlot.NONE:
				drop_on_slot(_drag_target_slot)
			else:
				drop_at(_drag_target_view, _drag_target_cell)

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
	# Rechtsklick geht an `gui_input` vorbei an `pressed` — ein Button hoert
	# von sich aus nur auf die linke Taste. Die Maske zu erweitern waere der
	# falsche Weg: Dann wuerde ein Rechtsklick auch `button_down` ausloesen
	# und damit ein Ziehen starten.
	button.gui_input.connect(_on_slot_gui_input.bind(slot))
	# Gedrueckt halten und ziehen holt den Gegenstand heraus. Der Klick
	# (pressed) kommt erst beim Loslassen und weiss dann schon, ob gezogen
	# wurde — siehe _on_slot_pressed.
	button.button_down.connect(_on_slot_grabbed.bind(slot))
	box.add_child(button)

	_slot_buttons[slot] = button
	return box


## Anfassen: Gedrueckt halten und ziehen holt heraus, was im Platz steckt.
func _on_slot_grabbed(slot: ItemData.EquipSlot) -> void:
	if player == null or player.equipment == null \
			or _split_prompt.is_open() or _context_menu.is_open():
		return

	var worn := player.equipment.get_item(slot)
	if worn == null:
		return

	_drag_stack = worn
	_drag_from_slot = slot
	_drag_ctrl = false
	_drag_original_rotated = worn.rotated
	_drag_offset = Vector2i.ZERO
	_tooltip.clear()

	# Der Gegenstand haengt mittig am Zeiger: Aus einem Platz gibt es kein
	# Feld, an dem man ihn "angefasst" haette.
	var step := InventoryGridView.CELL_SIZE + InventoryGridView.CELL_GAP
	_ghost.show_stack(worn, Vector2(worn.get_size()) * step * 0.5)


## Rechtsklick auf einen Ausruestungsplatz: Menue fuer das, was darin steckt.
func _on_slot_gui_input(event: InputEvent, slot: ItemData.EquipSlot) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed \
			or button.button_index != MOUSE_BUTTON_RIGHT:
		return
	if player == null or player.equipment == null:
		return
	_open_menu_for(player.equipment.get_item(slot), button.global_position)


## Rechtsklick auf einen Gegenstand im Raster.
func _on_item_right_clicked(stack: ItemStack, _view: InventoryGridView,
		at_position: Vector2) -> void:
	_open_menu_for(stack, at_position)


## Oeffnet das Kontextmenue — oder gar nichts, wenn es fuer diesen Gegenstand
## nichts anzubieten gibt.
func _open_menu_for(stack: ItemStack, at_position: Vector2) -> void:
	if stack == null:
		return
	var entries := ContextMenu.entries_for(stack)
	if entries.is_empty():
		return

	# Ein Menue mitten im Ziehen waere ein Gegenstand, der am Zeiger klebt,
	# waehrend man etwas anderes anklickt.
	_cancel_drag()
	_tooltip.clear()
	_menu_stack = stack
	_context_menu.open(entries, at_position)


func _on_menu_chosen(id: StringName) -> void:
	var stack := _menu_stack
	_menu_stack = null
	if stack == null or id != &"oeffnen":
		return
	_container_window.open_for(stack, get_global_mouse_position())


## Klick auf einen belegten Platz legt ab — zurueck ins Inventar.
##
## Passt es dort nicht, bleibt es an. Etwas fallen zu lassen, weil kein Platz
## ist, waere im Raid ein stiller Verlust.
func _on_slot_pressed(slot: ItemData.EquipSlot) -> void:
	if player == null or player.equipment == null:
		return

	# Wurde gezogen, ist das kein Klick: Das Ablegen erledigt _process, sobald
	# es die Maustaste losgelassen sieht.
	if _drag_stack != null:
		if _drag_target_slot != slot or _drag_target_cell.x >= 0:
			return
		# Nicht weggezogen — also doch nur ein Klick.
		_cancel_drag()

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

## Wo die Körperteile liegen, in Anteilen der Zeichenfläche.
##
## Sieben Rechtecke. Es gab zwischendurch eine Silhouette aus Polygonen —
## sie sah menschlicher aus, aber Lucas wollte die schlichte Fassung zurück.
## Für eine Anzeige, die vor allem lesbar sein muss, ist sie auch die
## ehrlichere: klare Flächen, klare Zahlen, nichts überlappt.
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

	for part: HealthSystem.Part in BODY_RECTS:
		var rect := _rect_for(part)
		var ratio := player.health.get_ratio(part)

		# In BEIDEN Reitern nach Zustand eingefaerbt.
		#
		# Unter "Ausruestung" war die Figur frueher neutral grau, um nicht vom
		# Anziehen abzulenken. Das kostete aber genau die Information, nach der
		# man greift, bevor man wieder rausgeht: wie es einem geht.
		_figure.draw_rect(rect, _color_for(ratio))

		# Zahlen und Auswahlrahmen bleiben dem Gesundheitsreiter vorbehalten —
		# das ist der Unterschied zwischen "wie geht es mir" auf einen Blick
		# und den Einzelheiten.
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

	for part: HealthSystem.Part in BODY_RECTS:
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

	if player.inventory != null and player.inventory.grid != null:
		var grid := player.inventory.grid
		_inventory_title.text = "Taschen  —  %d von %d Feldern frei" % [
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
	if _split_prompt.is_open() or _context_menu.is_open():
		return

	_drag_stack = stack
	_drag_source = view
	_drag_ctrl = Input.is_key_pressed(KEY_CTRL)
	_drag_original_rotated = stack.rotated
	_tooltip.clear()

	var origin := view.grid.get_position(stack.instance_id)
	var local := view.get_local_mouse_position()
	var grabbed := view.position_to_cell(local)
	_drag_offset = grabbed - origin if grabbed.x >= 0 and origin.x >= 0 else Vector2i.ZERO
	var pixel_offset := local - view.cell_to_position(origin) if origin.x >= 0 else Vector2.ZERO

	_ghost.show_stack(stack, pixel_offset)
	for v in _grid_views():
		v.drag_stack = stack
		v.drag_source = view
		v.preview_cell = Vector2i(-1, -1)
		v.queue_redraw()


func _update_drag_target() -> void:
	var mouse := get_global_mouse_position()

	# Die Plaetze haben Vorrang: Sie liegen ueber dem Raster, und wer auf einen
	# Platz zielt, meint auch den Platz.
	_drag_target_slot = _slot_under(mouse)

	_drag_target_view = null
	_drag_target_cell = Vector2i(-1, -1)
	if _drag_target_slot == ItemData.EquipSlot.NONE:
		for v: InventoryGridView in _grid_views():
			if not v.get_global_rect().has_point(mouse):
				continue
			var cell := v.position_to_cell(v.get_local_mouse_position())
			if cell.x >= 0:
				_drag_target_view = v
				_drag_target_cell = cell - _drag_offset
			break

	for v: InventoryGridView in _grid_views():
		v.preview_cell = _drag_target_cell if v == _drag_target_view else Vector2i(-1, -1)
		v.queue_redraw()
	_highlight_slots()


## Welcher Ausruestungsplatz unter diesem Punkt liegt.
func _slot_under(global_point: Vector2) -> ItemData.EquipSlot:
	for slot: ItemData.EquipSlot in _slot_buttons:
		var button: Button = _slot_buttons[slot]
		if button.is_visible_in_tree() and button.get_global_rect().has_point(global_point):
			return slot
	return ItemData.EquipSlot.NONE


## Faerbt den Platz unter dem Zeiger ein, solange etwas am Zeiger haengt.
## Gruen heisst "passt hier rein", Rot "passt nicht" — sonst probiert man
## blind herum, weil ein leerer Platz aussieht wie jeder andere.
func _highlight_slots() -> void:
	for slot: ItemData.EquipSlot in _slot_buttons:
		var button: Button = _slot_buttons[slot]
		if _drag_stack == null or slot != _drag_target_slot:
			button.modulate = Color.WHITE
		elif player != null and player.equipment.can_equip(_drag_stack, slot):
			button.modulate = Color(0.70, 1.15, 0.70)
		else:
			button.modulate = Color(1.15, 0.65, 0.60)


## Ablegen auf einem Ausruestungsplatz.
##
## Waffen gehen ueber assign_weapon(), damit die verdraengte Waffe geprueft
## im Raster landet statt zu verschwinden.
func drop_on_slot(slot: ItemData.EquipSlot) -> bool:
	if _drag_stack == null or player == null:
		return false

	var stack := _drag_stack
	var from := _drag_from_slot
	# Aus welchem Raster er kommt, muss vor _cancel_drag() feststehen.
	var from_grid: InventoryGrid = _drag_source.grid if _drag_source != null else null
	_cancel_drag()

	# Auf den eigenen Platz zurueck: nichts zu tun.
	if from == slot:
		return true
	if not player.equipment.can_equip(stack, slot):
		return false

	if Equipment.is_weapon_slot(slot):
		# Aus einem anderen Platz heraus: erst abnehmen, sonst haengt dieselbe
		# Waffe an zwei Stellen.
		if from != ItemData.EquipSlot.NONE:
			player.equipment.unequip(from)
		var ok := player.assign_weapon(stack, slot)
		if not ok and from != ItemData.EquipSlot.NONE:
			player.equipment.equip(stack, from)
		_refresh()
		return ok

	# Alles andere: Der verdraengte Gegenstand muss ins Raster passen, sonst
	# bleibt alles, wie es war.
	var displaced := player.equipment.get_item(slot)
	if displaced != null and player.inventory.grid.find_free_position(displaced).x < 0:
		return false

	if from != ItemData.EquipSlot.NONE:
		player.equipment.unequip(from)
	elif from_grid != null:
		from_grid.remove_item(stack.instance_id)
	else:
		player.inventory.grid.remove_item(stack.instance_id)

	player.equipment.equip(stack, slot)
	if displaced != null:
		player.inventory.grid.add_item(displaced)

	_refresh()
	return true


func drop_at(target: InventoryGridView, cell: Vector2i) -> void:
	if _drag_stack == null:
		return
	if target == null or cell.x < 0 or cell.y < 0:
		_cancel_drag()
		return

	# Vom Koerper ins Raster: Der Spieler packt etwas weg.
	if _drag_from_slot != ItemData.EquipSlot.NONE:
		var slot := _drag_from_slot
		var into := target.grid
		_cancel_drag()
		player.stow_equipment(slot, cell.x, cell.y, into)
		_refresh()
		return

	# Mit Strg wird nach der Menge gefragt, statt alles zu verschieben.
	if _drag_ctrl and _drag_stack.quantity > 1:
		_split_stack = _drag_stack
		_split_target = target
		_split_cell = cell
		var data := _split_stack.get_data()
		_split_prompt.ask(
			data.display_name if data != null else "Aufteilen",
			_split_stack.quantity,
			get_global_mouse_position()
		)
		_cancel_drag()
		return

	var moved := _move_within(target, cell) if target == _drag_source \
		else _move_between(target, cell)

	# Nur ein wirklich umgezogener Gegenstand behaelt seine neue Lage.
	if moved:
		_drag_original_rotated = _drag_stack.rotated

	_cancel_drag()


## Innerhalb desselben Rasters verschieben — oder auf einen passenden Stapel
## drauflegen. Wortgleich zum Loot-Fenster; beide Fenster machen dasselbe.
func _move_within(view: InventoryGridView, cell: Vector2i) -> bool:
	var existing := view.grid.get_stack_at(cell.x, cell.y)
	if existing != null and existing.can_merge_with(_drag_stack):
		existing.merge_from(_drag_stack)
		if _drag_stack.quantity <= 0:
			view.grid.remove_item(_drag_stack.instance_id)
		view.grid.changed.emit()
		return true
	return view.grid.move_item(_drag_stack.instance_id, cell.x, cell.y)


## Zwischen Taschen und Rucksack. Erst pruefen, dann verschieben — sonst kann
## der Gegenstand zwischen beiden Rastern verlorengehen.
func _move_between(target: InventoryGridView, cell: Vector2i) -> bool:
	if _drag_source == null:
		return false

	# Der Rucksack darf nicht in sich selbst wandern.
	if _drag_stack.container != null \
			and PlayerController._contains_grid(_drag_stack.container, target.grid):
		return false

	if not target.grid.can_place_or_merge(_drag_stack, cell.x, cell.y):
		return false

	var removed := _drag_source.grid.remove_item(_drag_stack.instance_id)
	if removed == null:
		return false

	var leftover := target.grid.place_or_merge(removed, cell.x, cell.y)
	if leftover != null:
		_drag_source.grid.add_item(leftover)
		if leftover == removed:
			return false

	return true


func _on_split_confirmed(amount: int) -> void:
	var stack := _split_stack
	var cell := _split_cell
	var target := _split_target
	_split_stack = null
	_split_target = null
	_split_cell = Vector2i(-1, -1)

	if stack == null or target == null or amount >= stack.quantity:
		return

	var part := stack.split(amount)
	if part == null:
		return

	var leftover := target.grid.place_or_merge(part, cell.x, cell.y)
	if leftover != null:
		# Passte nicht: zurueck auf den Ursprungsstapel, nichts geht verloren.
		stack.quantity += leftover.quantity
		return

	target.queue_redraw()


func _on_split_cancelled() -> void:
	_split_stack = null
	_split_target = null
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
	_drag_source = null
	_drag_target_view = null
	_drag_offset = Vector2i.ZERO
	_drag_target_cell = Vector2i(-1, -1)
	_drag_from_slot = ItemData.EquipSlot.NONE
	_drag_target_slot = ItemData.EquipSlot.NONE
	_drag_ctrl = false
	_highlight_slots()
	if _ghost != null:
		_ghost.clear()
	for v in _grid_views():
		v.drag_stack = null
		v.drag_source = null
		v.preview_cell = Vector2i(-1, -1)
		v.queue_redraw()


## Die Raster, in denen gerade gezogen werden darf. Das Taschenraster immer,
## das schwebende Behaelterfenster nur, solange es offen ist.
func _grid_views() -> Array[InventoryGridView]:
	var views: Array[InventoryGridView] = []
	if _inventory_view != null:
		views.append(_inventory_view)
	if _container_window != null and _container_window.is_open() \
			and _container_window.view.grid != null:
		views.append(_container_window.view)
	return views

