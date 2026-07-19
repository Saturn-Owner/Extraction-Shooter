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
signal opened()

const PANEL_BG := Color(0.09, 0.10, 0.11, 0.96)
const PANEL_BORDER := Color(0.35, 0.38, 0.42)

var container: LootContainer = null
var player_inventory: PlayerInventory = null

var _drag_stack: ItemStack = null
var _drag_source: InventoryGridView = null

## Um wie viele Felder der Anfasspunkt von der Ecke des Gegenstands abweicht.
var _drag_offset: Vector2i = Vector2i.ZERO

## Wo der Gegenstand gerade landen wuerde. Jeden Frame neu bestimmt.
var _drag_target: InventoryGridView = null
var _drag_target_cell: Vector2i = Vector2i(-1, -1)

## Ob beim Anfassen Strg gedrueckt war — dann wird nach der Menge gefragt.
var _drag_ctrl: bool = false

## Was nach dem Loslassen noch auf die Mengenabfrage wartet.
var _split_stack: ItemStack = null
var _split_source: InventoryGridView = null
var _split_target: InventoryGridView = null
var _split_cell: Vector2i = Vector2i(-1, -1)

@onready var _container_view: InventoryGridView = $Layout/Columns/Left/ContainerView
@onready var _player_view: InventoryGridView = $Layout/Columns/Right/PlayerView
@onready var _container_title: Label = $Layout/Columns/Left/ContainerTitle
@onready var _player_title: Label = $Layout/Columns/Right/PlayerTitle
@onready var _status: Label = $Layout/Columns/Left/Status
@onready var _progress: ProgressBar = $Layout/Columns/Left/SearchProgress
@onready var _ghost: DragGhost = $DragGhost
@onready var _split_prompt: SplitPrompt = $SplitPrompt
@onready var _tooltip: ItemTooltip = $ItemTooltip
@onready var _find_sound: AudioStreamPlayer = $FundGeraeusch


func _ready() -> void:
	hide()
	# cell_released wird bewusst NICHT verwendet: Godot schickt das Loslassen
	# immer an das Control, auf dem gedrueckt wurde. Beim Ziehen von der Kiste
	# ins Inventar kam es also nie beim Inventar an. Das Ziel bestimmt deshalb
	# das Fenster selbst anhand der Zeigerposition.
	for view in [_container_view, _player_view]:
		view.item_pressed.connect(_on_item_pressed)
		view.item_double_clicked.connect(_on_item_double_clicked)
		view.hidden_item_pressed.connect(_on_hidden_item_pressed)
		view.item_hovered.connect(_on_item_hovered)

	_split_prompt.confirmed.connect(_on_split_confirmed)
	_split_prompt.cancelled.connect(_on_split_cancelled)


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
	_update_status()
	opened.emit()


func close() -> void:
	if container != null:
		container.pause_search()
	if _split_prompt != null and _split_prompt.is_open():
		_split_prompt.cancel()
	if _tooltip != null:
		_tooltip.clear()
	_cancel_drag()
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _on_item_revealed(stack: ItemStack, _remaining: int) -> void:
	_container_view.queue_redraw()
	_update_status()
	_play_find_sound(stack)


## Man hoert den Gegenstand selbst: der Schluessel klimpert, die Waffe setzt
## sich schwer. Krimskrams bleibt still, sonst waere jede Kiste ein
## Dauergeklapper.
func _play_find_sound(stack: ItemStack) -> void:
	if stack == null or _find_sound == null:
		return
	var data := stack.get_data()
	if data == null:
		return

	var stream := SearchAudio.get_stream(data)
	if stream == null:
		return

	_find_sound.stream = stream
	_find_sound.play()


## Infoanzeige zum Gegenstand unter dem Zeiger.
func _on_item_hovered(stack: ItemStack, _view: InventoryGridView) -> void:
	# Waehrend des Ziehens waere die Anzeige nur im Weg.
	if stack == null or _drag_stack != null:
		_tooltip.clear()
		return
	_tooltip.show_for(stack)


## Klick auf einen schwarzen Umriss: den zuerst durchsuchen.
func _on_hidden_item_pressed(stack: ItemStack, view: InventoryGridView) -> void:
	if container == null or view != _container_view:
		return
	if container.prioritize(stack.instance_id):
		_container_view.queue_redraw()
		_update_status()


func _process(_delta: float) -> void:
	if not visible:
		return

	if _drag_stack != null:
		_update_drag_target()
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			drop_at(_drag_target, _drag_target_cell)

	if container != null:
		_update_status()


func _update_status() -> void:
	if container == null:
		return

	if container.is_searching():
		var remaining := container.get_remaining_count()
		_status.text = "Durchsuche... noch %d  —  Klick zieht einen vor" % remaining
		_progress.show()
		_progress.value = container.get_current_progress() * 100.0
		# Der gelbe Rahmen wandert mit; ohne das bliebe er am alten Umriss.
		_container_view.queue_redraw()
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
	# Solange die Mengenabfrage offen ist, wird nichts Neues angefasst.
	if _split_prompt.is_open():
		return

	_drag_stack = stack
	_drag_source = view
	_drag_ctrl = Input.is_key_pressed(KEY_CTRL)
	_tooltip.clear()

	# Anfasspunkt merken, damit der Gegenstand nicht zur Ecke springt.
	var origin := view.grid.get_position(stack.instance_id)
	var local := view.get_local_mouse_position()
	var grabbed := view.position_to_cell(local)
	_drag_offset = grabbed - origin if grabbed.x >= 0 and origin.x >= 0 else Vector2i.ZERO
	var pixel_offset := local - view.cell_to_position(origin) if origin.x >= 0 else Vector2.ZERO

	_ghost.show_stack(stack, pixel_offset)
	for v in [_container_view, _player_view]:
		v.drag_stack = stack
		v.drag_source = view
		v.preview_cell = Vector2i(-1, -1)
		v.queue_redraw()


## Sucht jeden Frame das Raster unter dem Zeiger und rechnet aus, wo der
## Gegenstand dort landen wuerde.
func _update_drag_target() -> void:
	_drag_target = null
	_drag_target_cell = Vector2i(-1, -1)

	var mouse := get_global_mouse_position()
	for v: InventoryGridView in [_container_view, _player_view]:
		if not v.get_global_rect().has_point(mouse):
			continue
		var cell := v.position_to_cell(v.get_local_mouse_position())
		if cell.x >= 0:
			_drag_target = v
			_drag_target_cell = cell - _drag_offset
		break

	for v: InventoryGridView in [_container_view, _player_view]:
		v.preview_cell = _drag_target_cell if v == _drag_target else Vector2i(-1, -1)
		v.queue_redraw()


## Legt den gezogenen Gegenstand ab. Ohne gueltiges Ziel bleibt er, wo er war.
func drop_at(target: InventoryGridView, cell: Vector2i) -> void:
	if _drag_stack == null:
		return

	if target == null or cell.x < 0 or cell.y < 0:
		_cancel_drag()
		return

	# Mit Strg wird nach der Menge gefragt, statt alles zu verschieben.
	if _drag_ctrl and _drag_stack.quantity > 1 and _can_take_from_source(_drag_stack):
		_begin_split(target, cell)
		return

	if target == _drag_source:
		_move_within(target, cell)
	else:
		_move_between(target, cell)

	_cancel_drag()


## Innerhalb desselben Rasters verschieben — oder auf einen passenden
## Stapel drauflegen.
func _move_within(view: InventoryGridView, cell: Vector2i) -> void:
	var existing := view.grid.get_stack_at(cell.x, cell.y)
	if existing != null and existing.can_merge_with(_drag_stack):
		existing.merge_from(_drag_stack)
		# Ein leer geraeumter Stapel darf nicht als Geisterfeld liegenbleiben.
		if _drag_stack.quantity <= 0:
			view.grid.remove_item(_drag_stack.instance_id)
		view.grid.changed.emit()
		_notify_changed()
		return

	view.grid.move_item(_drag_stack.instance_id, cell.x, cell.y)


## Von einem Raster ins andere. Erst prüfen, dann verschieben — sonst kann
## der Gegenstand zwischen beiden verloren gehen.
func _move_between(target: InventoryGridView, cell: Vector2i) -> void:
	var source_grid := _drag_source.grid
	var target_grid := target.grid

	if not target_grid.can_place_or_merge(_drag_stack, cell.x, cell.y):
		return

	if not _can_take_from_source(_drag_stack):
		return

	var removed := source_grid.remove_item(_drag_stack.instance_id)
	if removed == null:
		return

	var leftover := target_grid.place_or_merge(removed, cell.x, cell.y)
	if leftover != null:
		# Zurücklegen — nichts darf verschwinden. Auch ein Rest, der nicht
		# mehr auf den Zielstapel passte, gehoert wieder zurueck.
		source_grid.add_item(leftover)
		if leftover == removed:
			return

	# Was der Spieler selbst hineinlegt, muss er auch sehen können.
	if target == _container_view and container != null:
		container.mark_revealed(removed)

	_notify_changed()


## Aus der Kiste darf nur genommen werden, was aufgedeckt ist.
func _can_take_from_source(stack: ItemStack) -> bool:
	if _drag_source != _container_view or container == null:
		return true
	return container.is_revealed(stack.instance_id)


# ---------------------------------------------------------------------------
# Aufteilen mit Strg
# ---------------------------------------------------------------------------

func _begin_split(target: InventoryGridView, cell: Vector2i) -> void:
	_split_stack = _drag_stack
	_split_source = _drag_source
	_split_target = target
	_split_cell = cell

	var data := _split_stack.get_data()
	var item_name := data.display_name if data != null else "Aufteilen"
	_split_prompt.ask(item_name, _split_stack.quantity, get_global_mouse_position())

	# Das Ziehen ist vorbei — die Abfrage uebernimmt.
	_cancel_drag()


func _on_split_confirmed(amount: int) -> void:
	if _split_stack == null or _split_target == null:
		_clear_split()
		return

	var stack := _split_stack
	var target := _split_target
	var cell := _split_cell
	var source := _split_source
	_clear_split()

	# Alles gewaehlt: das ist ein normales Verschieben.
	if amount >= stack.quantity:
		_drag_stack = stack
		_drag_source = source
		if target == source:
			_move_within(target, cell)
		else:
			_move_between(target, cell)
		_cancel_drag()
		return

	var part := stack.split(amount)
	if part == null:
		return

	var leftover := target.grid.place_or_merge(part, cell.x, cell.y)
	if leftover != null:
		# Passte nicht: zurueck auf den Ursprungsstapel, nichts geht verloren.
		stack.quantity += leftover.quantity
		return

	if target == _container_view and container != null:
		container.mark_revealed(part)

	_notify_changed()


func _on_split_cancelled() -> void:
	_clear_split()


func _clear_split() -> void:
	_split_stack = null
	_split_source = null
	_split_target = null
	_split_cell = Vector2i(-1, -1)


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
	_drag_target = null
	_drag_target_cell = Vector2i(-1, -1)
	_drag_offset = Vector2i.ZERO
	_drag_ctrl = false
	if _ghost != null:
		_ghost.clear()
	for v in [_container_view, _player_view]:
		if v == null:
			continue
		v.drag_stack = null
		v.drag_source = null
		v.preview_cell = Vector2i(-1, -1)
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
