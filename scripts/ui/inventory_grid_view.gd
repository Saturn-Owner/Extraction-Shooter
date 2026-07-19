## Zeichnet ein Rasterinventar und macht es bedienbar (Tarkov-Stil).
##
## Zeichnet alles selbst über _draw(), statt pro Feld einen Knoten anzulegen.
## Ein 14x12-Lager wären sonst 168 Knoten, die bei jeder Änderung neu
## aufgebaut werden müssten.
##
## VERBINDUNG ZUM CONTAINER:
## Ist `container` gesetzt, werden noch nicht durchsuchte Gegenstände als
## schwarze Umrisse gezeichnet: Der Spieler sieht, WO etwas liegt und wie
## gross es ist, aber nicht, was es ist. Ein Klick darauf zieht es vor.
##
## ZIEHEN UND ABLEGEN läuft über das übergeordnete Fenster, damit man
## zwischen zwei Rastern ziehen kann. Diese Klasse meldet nur, was passiert.
class_name InventoryGridView
extends Control

signal item_pressed(stack: ItemStack, view: InventoryGridView)

## Klick auf einen noch nicht durchsuchten Umriss — der soll vorgezogen werden.
signal hidden_item_pressed(stack: ItemStack, view: InventoryGridView)
signal item_double_clicked(stack: ItemStack, view: InventoryGridView)
signal cell_released(grid_position: Vector2i, view: InventoryGridView)

## Der Zeiger steht auf einem erkannten Gegenstand (null = auf keinem).
signal item_hovered(stack: ItemStack, view: InventoryGridView)

const CELL_SIZE := 52.0
const CELL_GAP := 2.0

# Farbgebung bewusst düster (Tarkov-Anmutung): fast schwarze Felder, gedämpfte
# Gegenstände, keine leuchtenden Flächen. Ein Inventar, in dem man im Raid
# unter Zeitdruck sucht, soll ruhig wirken und nicht blenden.
const COLOR_CELL := Color(0.075, 0.080, 0.088, 0.95)
const COLOR_CELL_BORDER := Color(0.145, 0.155, 0.170)
const COLOR_ITEM := Color(0.145, 0.152, 0.163)
const COLOR_ITEM_BORDER := Color(0.26, 0.28, 0.31)
const COLOR_HOVER_OK := Color(0.30, 0.62, 0.36, 0.38)
const COLOR_HOVER_BAD := Color(0.68, 0.24, 0.20, 0.38)
const COLOR_TEXT := Color(0.80, 0.82, 0.84)
const COLOR_COUNT := Color(0.86, 0.80, 0.56)

## Feiner Rahmen um den Gegenstand unter dem Zeiger.
const COLOR_HIGHLIGHT := Color(0.62, 0.66, 0.72)

## Wie stark die Seltenheitsfarbe den dunklen Grundton einfaerbt.
## Niedrig halten: Die Farbe soll einordnen, nicht dominieren.
const RARITY_TINT := 0.22

## Noch nicht durchsuchte Gegenstände: schwarze Umrisse. Der Spieler sieht
## Groesse und Lage, aber nicht, was es ist.
const COLOR_HIDDEN := Color(0.03, 0.03, 0.04, 0.97)
const COLOR_HIDDEN_BORDER := Color(0.22, 0.23, 0.26)

## Der Umriss, der gerade durchsucht wird.
const COLOR_HIDDEN_ACTIVE_BORDER := Color(0.85, 0.78, 0.45)

## Farbe je Kategorie — nur noch als schmaler Streifen am linken Rand, damit
## man Munition von Medizin unterscheidet, ohne dass die Flaeche bunt wird.
const CATEGORY_COLORS := {
	ItemData.Category.AMMO: Color(0.62, 0.52, 0.30),
	ItemData.Category.WEAPON: Color(0.44, 0.50, 0.62),
	ItemData.Category.ARMOR_PLATE: Color(0.52, 0.44, 0.62),
	ItemData.Category.BACKPACK: Color(0.40, 0.56, 0.46),
	ItemData.Category.MEDICAL: Color(0.66, 0.40, 0.42),
	ItemData.Category.FOOD: Color(0.58, 0.56, 0.34),
}

var grid: InventoryGrid = null

## Optional: Wenn gesetzt, werden nur aufgedeckte Gegenstände gezeichnet.
var container: LootContainer = null

var title: String = ""

## Wird vom Fenster gesetzt, während gezogen wird.
var drag_stack: ItemStack = null
var drag_source: InventoryGridView = null

## Wo der gezogene Gegenstand landen würde (-1 = nicht über diesem Raster).
##
## Das setzt das Fenster, nicht dieses Raster: Godot schickt nach dem Klick
## alle Mausereignisse weiter an das Control, auf dem gedrückt wurde. Ein
## Raster erfährt also gar nicht, dass der Zeiger über ihm schwebt, solange
## der Gegenstand aus dem anderen Raster kommt.
var preview_cell: Vector2i = Vector2i(-1, -1)

var _hover_cell: Vector2i = Vector2i(-1, -1)

## Gegenstand unter dem Zeiger. 0 = keiner.
var _hover_stack_id: int = 0
var _last_click_time: float = 0.0
var _last_click_id: int = -1


func setup(p_grid: InventoryGrid, p_title: String, p_container: LootContainer = null) -> void:
	grid = p_grid
	title = p_title
	container = p_container
	if grid != null:
		custom_minimum_size = get_grid_pixel_size()
		if not grid.changed.is_connected(queue_redraw):
			grid.changed.connect(queue_redraw)
	queue_redraw()


func get_grid_pixel_size() -> Vector2:
	if grid == null:
		return Vector2.ZERO
	return Vector2(
		grid.width * (CELL_SIZE + CELL_GAP) + CELL_GAP,
		grid.height * (CELL_SIZE + CELL_GAP) + CELL_GAP
	)


## Rechnet Mausposition in Rasterkoordinaten um.
func position_to_cell(local: Vector2) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	var step := CELL_SIZE + CELL_GAP
	var cell := Vector2i(int((local.x - CELL_GAP) / step), int((local.y - CELL_GAP) / step))
	if not grid.is_inside(cell.x, cell.y):
		return Vector2i(-1, -1)
	return cell


func cell_to_position(cell: Vector2i) -> Vector2:
	var step := CELL_SIZE + CELL_GAP
	return Vector2(CELL_GAP + cell.x * step, CELL_GAP + cell.y * step)


## Alle Gegenstände, die als erkannt gezeichnet werden dürfen.
func _visible_stacks() -> Array[ItemStack]:
	if grid == null:
		return []
	if container != null:
		return container.get_revealed_stacks()
	return grid.get_all_stacks()


## Noch nicht durchsuchte Gegenstände — werden als schwarze Umrisse gezeigt.
func _hidden_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	if grid == null or container == null:
		return result
	for stack in grid.get_all_stacks():
		if not container.is_revealed(stack.instance_id):
			result.append(stack)
	return result


func _gui_input(event: InputEvent) -> void:
	if grid == null:
		return

	if event is InputEventMouseMotion:
		var cell := position_to_cell((event as InputEventMouseMotion).position)
		if cell != _hover_cell:
			_hover_cell = cell
			_update_hovered_stack(cell)
			queue_redraw()
		return

	if not (event is InputEventMouseButton):
		return

	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := position_to_cell(button.position)

	if button.pressed:
		if cell.x < 0:
			return
		var stack := grid.get_stack_at(cell.x, cell.y)
		if stack == null:
			return
		# Nicht durchsuchte Gegenstände lassen sich nicht anfassen — aber ein
		# Klick zieht sie vor. Man sieht den grossen Umriss und will wissen,
		# was es ist, ohne erst die Patronenschachteln abzuwarten.
		if container != null and not container.is_revealed(stack.instance_id):
			hidden_item_pressed.emit(stack, self)
			return

		# Doppelklick: schnell hinüberschicken, ohne zu ziehen.
		var now := Time.get_ticks_msec() / 1000.0
		if stack.instance_id == _last_click_id and now - _last_click_time < 0.35:
			_last_click_id = -1
			item_double_clicked.emit(stack, self)
			return

		_last_click_id = stack.instance_id
		_last_click_time = now
		item_pressed.emit(stack, self)
	else:
		cell_released.emit(cell, self)


## Meldet, welcher Gegenstand unter dem Zeiger liegt. Nicht durchsuchte
## zaehlen NICHT — ihre Werte darf der Spieler noch nicht sehen.
func _update_hovered_stack(cell: Vector2i) -> void:
	var found: ItemStack = null
	if cell.x >= 0:
		var stack := grid.get_stack_at(cell.x, cell.y)
		if stack != null and (container == null or container.is_revealed(stack.instance_id)):
			found = stack

	var new_id := found.instance_id if found != null else 0
	if new_id == _hover_stack_id:
		return
	_hover_stack_id = new_id
	item_hovered.emit(found, self)


## Der Zeiger hat das Raster verlassen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_cell = Vector2i(-1, -1)
		if _hover_stack_id != 0:
			_hover_stack_id = 0
			item_hovered.emit(null, self)
		queue_redraw()


func _draw() -> void:
	if grid == null:
		return

	_draw_cells()
	_draw_drag_preview()
	for stack in _hidden_stacks():
		_draw_hidden_stack(stack)
	for stack in _visible_stacks():
		_draw_stack(stack)


## Ein noch nicht durchsuchter Gegenstand: schwarze Flaeche in seiner echten
## Groesse. Die Groesse zu zeigen ist Absicht — sie verraet, wie lange das
## Durchsuchen dauert, aber nicht, ob es sich lohnt.
func _draw_hidden_stack(stack: ItemStack) -> void:
	var pos_cell := grid.get_position(stack.instance_id)
	if pos_cell.x < 0:
		return

	var size := stack.get_size()
	var rect := Rect2(cell_to_position(pos_cell), Vector2(
		size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP
	))

	draw_rect(rect, COLOR_HIDDEN)

	var is_current := container != null and container.get_current_target() == stack
	if is_current and container.is_searching():
		draw_rect(rect, COLOR_HIDDEN_ACTIVE_BORDER, false, 2.0)
	else:
		draw_rect(rect, COLOR_HIDDEN_BORDER, false, 1.0)


func _draw_cells() -> void:
	for y in range(grid.height):
		for x in range(grid.width):
			var pos := cell_to_position(Vector2i(x, y))
			var rect := Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect, COLOR_CELL)
			draw_rect(rect, COLOR_CELL_BORDER, false, 1.0)


## Zeigt beim Ziehen, ob der Gegenstand hier abgelegt werden kann.
func _draw_drag_preview() -> void:
	if drag_stack == null or preview_cell.x < 0 or preview_cell.y < 0:
		return

	var size := drag_stack.get_size()
	var pos := cell_to_position(preview_cell)
	var rect := Rect2(pos, Vector2(
		size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP
	))

	# Beim Verschieben innerhalb desselben Rasters darf sich der Gegenstand
	# mit sich selbst überlappen.
	var ignore := drag_stack.instance_id if drag_source == self else 0
	var fits := grid.can_place_or_merge(drag_stack, preview_cell.x, preview_cell.y, ignore)
	draw_rect(rect, COLOR_HOVER_OK if fits else COLOR_HOVER_BAD)


func _draw_stack(stack: ItemStack) -> void:
	# Der gezogene Gegenstand haengt am Mauszeiger — gezeichnet wird er dort
	# vom DragGhost des Fensters, nicht hier.
	if stack == drag_stack:
		return

	var pos_cell := grid.get_position(stack.instance_id)
	if pos_cell.x < 0:
		return

	var data := stack.get_data()
	var size := stack.get_size()
	var pos := cell_to_position(pos_cell)
	var rect := Rect2(pos, Vector2(
		size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP
	))

	if data == null:
		draw_rect(rect, COLOR_ITEM)
		draw_rect(rect, COLOR_ITEM_BORDER, false, 1.5)
		return

	# Dunkler Grundton, leicht in Richtung Seltenheit eingefaerbt.
	var rarity_color := ItemTooltip.get_rarity_color(data.get_rarity())
	draw_rect(rect, COLOR_ITEM.lerp(rarity_color, RARITY_TINT))

	# Schmaler Streifen links: die Kategorie auf einen Blick.
	var accent: Color = CATEGORY_COLORS.get(data.category, COLOR_ITEM_BORDER)
	draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), accent)

	var hovered := _hover_stack_id == stack.instance_id
	draw_rect(rect, COLOR_HIGHLIGHT if hovered else COLOR_ITEM_BORDER, false, 2.0 if hovered else 1.0)

	var font := ThemeDB.fallback_font
	var font_size := 12

	# Name umbrechen, damit er in schmale Gegenstände passt.
	var text := data.display_name
	draw_string(font, rect.position + Vector2(4, 14), text,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, font_size, COLOR_TEXT)

	# Stückzahl unten rechts, wie in Tarkov.
	if stack.quantity > 1:
		var count := "x%d" % stack.quantity
		var width := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, rect.position + Vector2(rect.size.x - width - 4, rect.size.y - 5),
			count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_COUNT)
