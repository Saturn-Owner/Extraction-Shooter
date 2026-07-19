## Zeichnet ein Rasterinventar und macht es bedienbar (Tarkov-Stil).
##
## Zeichnet alles selbst über _draw(), statt pro Feld einen Knoten anzulegen.
## Ein 14x12-Lager wären sonst 168 Knoten, die bei jeder Änderung neu
## aufgebaut werden müssten.
##
## VERBINDUNG ZUM CONTAINER:
## Ist `container` gesetzt, werden nur AUFGEDECKTE Gegenstände gezeichnet.
## Alles andere existiert für den Spieler noch nicht — das ist die Grundlage
## des schrittweisen Durchsuchens.
##
## ZIEHEN UND ABLEGEN läuft über das übergeordnete Fenster, damit man
## zwischen zwei Rastern ziehen kann. Diese Klasse meldet nur, was passiert.
class_name InventoryGridView
extends Control

signal item_pressed(stack: ItemStack, view: InventoryGridView)
signal item_double_clicked(stack: ItemStack, view: InventoryGridView)
signal cell_released(grid_position: Vector2i, view: InventoryGridView)

const CELL_SIZE := 52.0
const CELL_GAP := 2.0

const COLOR_CELL := Color(0.16, 0.17, 0.19, 0.9)
const COLOR_CELL_BORDER := Color(0.28, 0.30, 0.33)
const COLOR_ITEM := Color(0.32, 0.35, 0.38)
const COLOR_ITEM_BORDER := Color(0.55, 0.58, 0.62)
const COLOR_HOVER_OK := Color(0.35, 0.75, 0.42, 0.45)
const COLOR_HOVER_BAD := Color(0.80, 0.30, 0.25, 0.45)
const COLOR_TEXT := Color(0.88, 0.90, 0.92)
const COLOR_COUNT := Color(1.0, 0.92, 0.6)

## Farbe je Kategorie — auf einen Blick erkennbar, was wo liegt.
const CATEGORY_COLORS := {
	ItemData.Category.AMMO: Color(0.42, 0.36, 0.22),
	ItemData.Category.WEAPON: Color(0.30, 0.34, 0.42),
	ItemData.Category.ARMOR_PLATE: Color(0.36, 0.30, 0.42),
	ItemData.Category.BACKPACK: Color(0.28, 0.38, 0.32),
	ItemData.Category.MEDICAL: Color(0.44, 0.28, 0.30),
	ItemData.Category.FOOD: Color(0.40, 0.38, 0.24),
}

var grid: InventoryGrid = null

## Optional: Wenn gesetzt, werden nur aufgedeckte Gegenstände gezeichnet.
var container: LootContainer = null

var title: String = ""

## Wird vom Fenster gesetzt, während gezogen wird.
var drag_stack: ItemStack = null
var drag_source: InventoryGridView = null

var _hover_cell: Vector2i = Vector2i(-1, -1)
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


## Alle Gegenstände, die gezeichnet werden dürfen.
func _visible_stacks() -> Array[ItemStack]:
	if grid == null:
		return []
	if container != null:
		return container.get_revealed_stacks()
	return grid.get_all_stacks()


func _gui_input(event: InputEvent) -> void:
	if grid == null:
		return

	if event is InputEventMouseMotion:
		var cell := position_to_cell((event as InputEventMouseMotion).position)
		if cell != _hover_cell:
			_hover_cell = cell
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
		# Nicht aufgedeckte Gegenstände sind für den Spieler unsichtbar
		# und dürfen auch nicht anfassbar sein.
		if container != null and not container.is_revealed(stack.instance_id):
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


func _draw() -> void:
	if grid == null:
		return

	_draw_cells()
	_draw_drag_preview()
	for stack in _visible_stacks():
		_draw_stack(stack)


func _draw_cells() -> void:
	for y in range(grid.height):
		for x in range(grid.width):
			var pos := cell_to_position(Vector2i(x, y))
			var rect := Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect, COLOR_CELL)
			draw_rect(rect, COLOR_CELL_BORDER, false, 1.0)


## Zeigt beim Ziehen, ob der Gegenstand hier abgelegt werden kann.
func _draw_drag_preview() -> void:
	if drag_stack == null or _hover_cell.x < 0:
		return

	var size := drag_stack.get_size()
	var pos := cell_to_position(_hover_cell)
	var rect := Rect2(pos, Vector2(
		size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP
	))

	# Beim Verschieben innerhalb desselben Rasters darf sich der Gegenstand
	# mit sich selbst überlappen.
	var ignore := drag_stack.instance_id if drag_source == self else 0
	var fits := grid.can_place(drag_stack, _hover_cell.x, _hover_cell.y, ignore)
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

	var fill: Color = CATEGORY_COLORS.get(data.category, COLOR_ITEM) if data != null else COLOR_ITEM
	draw_rect(rect, fill)
	draw_rect(rect, COLOR_ITEM_BORDER, false, 1.5)

	if data == null:
		return

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
