## Das eigene Inventar, ohne Kiste davor.
##
## Zeigt dasselbe Raster wie im Loot-Fenster, dazu die Werte, die von der
## Traglast abhaengen. Das ist bewusst dieselbe Ansicht: Wer im Raid vor einer
## Kiste umsortiert, soll dieselbe Bedienung vorfinden wie unterwegs.
##
## Bedienung:
##   Ziehen        umsortieren
##   Doppelklick   Waffe in die Hand nehmen
##   R             Gegenstand drehen
class_name InventoryWindow
extends Control

signal closed()
signal opened()

var player: PlayerController = null

var _drag_stack: ItemStack = null

@onready var _view: InventoryGridView = $Layout/Inhalt/GridView
@onready var _stats: Label = $Layout/Inhalt/Stats


func _ready() -> void:
	hide()
	_view.item_pressed.connect(_on_item_pressed)
	_view.item_double_clicked.connect(_on_item_double_clicked)
	_view.cell_released.connect(_on_cell_released)


func open_for(p_player: PlayerController) -> void:
	player = p_player
	_view.setup(player.inventory.grid, "Inventar")
	show()
	_update_stats()
	opened.emit()


func close() -> void:
	_cancel_drag()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if visible:
		_update_stats()


func _update_stats() -> void:
	if player == null:
		return

	var lines := [
		"Traglast:  %.1f kg" % player.carried_weight_kg,
		"Tempo:     %.0f %%" % (player.get_weight_factor() * 100.0),
		"Plaetze:   %d von %d frei" % [
			player.inventory.grid.get_free_cell_count(),
			player.inventory.grid.width * player.inventory.grid.height,
		],
	]

	if player.inventory.equipped_weapon != null:
		var data := player.inventory.equipped_weapon.get_data()
		if data != null:
			lines.append("In der Hand: %s" % data.display_name)

	_stats.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# Bedienung
# ---------------------------------------------------------------------------

func _on_item_pressed(stack: ItemStack, view: InventoryGridView) -> void:
	_drag_stack = stack
	_view.drag_stack = stack
	_view.drag_source = view
	_view.queue_redraw()


func _on_cell_released(cell: Vector2i, _view: InventoryGridView) -> void:
	if _drag_stack != null and cell.x >= 0:
		_view.grid.move_item(_drag_stack.instance_id, cell.x, cell.y)
	_cancel_drag()


## Doppelklick nimmt eine Waffe in die Hand. Bei allem anderen passiert
## bewusst nichts — ein versehentliches Wegwerfen im Raid waere fatal.
func _on_item_double_clicked(stack: ItemStack, _view: InventoryGridView) -> void:
	if player == null:
		return
	var data := stack.get_data()
	if data == null or data.category != ItemData.Category.WEAPON:
		return
	player.equip_from_inventory(stack)
	_update_stats()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _drag_stack == null:
		return
	var key := event as InputEventKey
	if key == null or not key.is_pressed() or key.is_echo():
		return
	if key.physical_keycode == KEY_R:
		_view.grid.rotate_item(_drag_stack.instance_id)
		_view.queue_redraw()
		get_viewport().set_input_as_handled()


func _cancel_drag() -> void:
	_drag_stack = null
	_view.drag_stack = null
	_view.drag_source = null
	_view.queue_redraw()
