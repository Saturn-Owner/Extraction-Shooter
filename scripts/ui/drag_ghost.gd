## Zeichnet den gerade gezogenen Gegenstand am Mauszeiger.
##
## Ohne diese Ebene verschwindet ein Gegenstand beim Anfassen einfach —
## das Raster zeichnet ihn dann bewusst nicht mehr, weil er "am Mauszeiger
## haengt". Genau das ist hier.
##
## Liegt als letztes Kind im Fenster, damit sie ueber beiden Rastern liegt,
## und nimmt selbst keine Mausereignisse entgegen (mouse_filter = IGNORE) —
## sonst koennte man nichts mehr ablegen.
class_name DragGhost
extends Control

const ALPHA := 0.85

var stack: ItemStack = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func show_stack(p_stack: ItemStack) -> void:
	stack = p_stack
	set_process(stack != null)
	queue_redraw()


func clear() -> void:
	show_stack(null)


## Nur waehrend gezogen wird — sonst zeichnet das Fenster jeden Frame umsonst.
func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if stack == null:
		return

	var data := stack.get_data()
	var size := stack.get_size()
	var step := InventoryGridView.CELL_SIZE + InventoryGridView.CELL_GAP

	# Die linke obere Ecke sitzt am Zeiger — genau dort landet der Gegenstand
	# auch. Was man sieht, ist damit das, was passiert.
	var rect := Rect2(
		get_local_mouse_position(),
		Vector2(size.x * step - InventoryGridView.CELL_GAP,
			size.y * step - InventoryGridView.CELL_GAP)
	)

	var fill: Color = InventoryGridView.COLOR_ITEM
	if data != null:
		fill = InventoryGridView.CATEGORY_COLORS.get(data.category, InventoryGridView.COLOR_ITEM)
	fill.a = ALPHA

	draw_rect(rect, fill)
	draw_rect(rect, InventoryGridView.COLOR_ITEM_BORDER, false, 2.0)

	if data != null:
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 14),
			data.display_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 12,
			InventoryGridView.COLOR_TEXT)
