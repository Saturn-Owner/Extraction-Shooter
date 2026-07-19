## Das Loot-Fenster: Kiste links, eigenes Inventar rechts.
##
## Bedienung wie in Tarkov und Arena Breakout:
##   Ziehen              Gegenstand verschieben, auch zwischen den Rastern
##   Doppelklick         schnell ins andere Raster schicken
##   Rechtsklick ziehen  (später: Kontextmenü)
##
## Solange die Kiste noch durchsucht wird, tauchen oben laufend neue
## Gegenstände auf. Der Balken zeigt den Fortschritt am aktuellen Fund —
## aber NICHT, was es ist. Sonst wäre die Entscheidung "warte ich das ab?"
## trivial, und genau diese Entscheidung ist der Reiz.
class_name LootWindow
extends Control

signal closed()

const PANEL_BG := Color(0.09, 0.10, 0.11, 0.96)
const PANEL_BORDER := Color(0.35, 0.38, 0.42)

var container: LootContainer = null
var player_inventory: PlayerInventory = null

var _drag_stack: ItemStack = null
var _drag_source: InventoryGridView = null

@onready var _container_view: InventoryGridView = $Layout/Columns/Left/ContainerView
@onready var _player_view: InventoryGridView = $Layout/Columns/Right/PlayerView
@onready var _container_title: Label = $Layout/Columns/Left/ContainerTitle
@onready var _player_title: Label = $Layout/Columns/Right/PlayerTitle
@onready var _status: Label = $Layout/Columns/Left/Status
@onready var _progress: ProgressBar = $Layout/Columns/Left/SearchProgress


func _ready() -> void:
	hide()
	for view in [_container_view, _player_view]:
		view.item_pressed.connect(_on_item_pressed)
		view.item_double_clicked.connect(_on_item_double_clicked)
		view.cell_released.connect(_on_cell_released)


## Öffnet das Fenster für eine Kiste.
func open_for(p_container: LootContainer, p_inventory: PlayerInventory) -> void:
	container = p_container
	player_inventory = p_inventory

	container.open()
	if not container.item_revealed.is_connected(_on_item_revealed):
		container.item_revealed.connect(_on_item_revealed)

	_container_view.setup(container.contents, container.display_name, container)
	_player_view.setup(player_inventory.grid, "Ausruestung")
	_container_title.text = container.display_name
	_player_title.text = "Ausruestung"

	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_status()


func close() -> void:
	if container != null:
		container.pause_search()
	_cancel_drag()
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func is_open() -> bool:
	return visible


func _on_item_revealed(_stack: ItemStack, _remaining: int) -> void:
	_container_view.queue_redraw()
	_update_status()


func _process(_delta: float) -> void:
	if not visible or container == null:
		return
	_update_status()


func _update_status() -> void:
	if container == null:
		return

	if container.is_searching():
		var remaining := container.get_remaining_count()
		_status.text = "Durchsuche... noch %d Fund%s" % [remaining, "" if remaining == 1 else "e"]
		_progress.show()
		_progress.value = container.get_current_progress() * 100.0
	elif container.is_fully_searched:
		_status.text = "vollstaendig durchsucht"
		_progress.hide()
	else:
		_status.text = "unterbrochen — [F] fortsetzen"
		_progress.hide()


# ---------------------------------------------------------------------------
# Ziehen und Ablegen
# ---------------------------------------------------------------------------

func _on_item_pressed(stack: ItemStack, view: InventoryGridView) -> void:
	_drag_stack = stack
	_drag_source = view
	for v in [_container_view, _player_view]:
		v.drag_stack = stack
		v.drag_source = view
		v.queue_redraw()


func _on_cell_released(cell: Vector2i, view: InventoryGridView) -> void:
	if _drag_stack == null:
		return
	if cell.x < 0:
		_cancel_drag()
		return

	if view == _drag_source:
		_move_within(view, cell)
	else:
		_move_between(view, cell)

	_cancel_drag()


## Innerhalb desselben Rasters verschieben.
func _move_within(view: InventoryGridView, cell: Vector2i) -> void:
	view.grid.move_item(_drag_stack.instance_id, cell.x, cell.y)


## Von einem Raster ins andere. Erst prüfen, dann verschieben — sonst kann
## der Gegenstand zwischen beiden verloren gehen.
func _move_between(target: InventoryGridView, cell: Vector2i) -> void:
	var source_grid := _drag_source.grid
	var target_grid := target.grid

	if not target_grid.can_place(_drag_stack, cell.x, cell.y):
		return

	# Aus der Kiste nehmen: nur aufgedeckte Gegenstände.
	if _drag_source == _container_view and container != null:
		if not container.is_revealed(_drag_stack.instance_id):
			return

	var removed := source_grid.remove_item(_drag_stack.instance_id)
	if removed == null:
		return

	if not target_grid.place(removed, cell.x, cell.y):
		# Zurücklegen — nichts darf verschwinden.
		source_grid.add_item(removed)
		return

	# Was der Spieler selbst hineinlegt, muss er auch sehen können.
	if target == _container_view and container != null:
		container.mark_revealed(removed)

	_notify_changed()


func _on_item_double_clicked(stack: ItemStack, view: InventoryGridView) -> void:
	if view == _container_view:
		if container.take_item(stack.instance_id, player_inventory.grid):
			_notify_changed()
	else:
		# Vom Spieler in die Kiste zurücklegen.
		var spot := container.contents.find_free_position(stack)
		if spot.x < 0:
			return
		var removed := player_inventory.grid.remove_item(stack.instance_id)
		if removed == null:
			return
		if not container.put_item(removed, spot.x, spot.y):
			player_inventory.grid.add_item(removed)
			return
		_notify_changed()


func _cancel_drag() -> void:
	_drag_stack = null
	_drag_source = null
	for v in [_container_view, _player_view]:
		if v == null:
			continue
		v.drag_stack = null
		v.drag_source = null
		v.queue_redraw()


func _notify_changed() -> void:
	if player_inventory != null:
		player_inventory.changed.emit()
	_container_view.queue_redraw()
	_player_view.queue_redraw()


## Nimmt alles Aufgedeckte mit, was passt.
func take_all() -> int:
	if container == null or player_inventory == null:
		return 0
	var left := container.take_all(player_inventory.grid)
	_notify_changed()
	return left
