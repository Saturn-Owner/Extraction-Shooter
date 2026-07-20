## Ein schwebendes Fenster mit dem Inhalt eines Behälters.
##
## Rechtsklick auf einen Rucksack, "Öffnen" wählen — und der Inhalt liegt in
## einem Fenster, das man an der Titelleiste verschieben und mit dem Kreuz
## schliessen kann.
##
## WARUM SCHWEBEND UND NICHT FEST EINGEBAUT:
## Ein festes Raster kann immer nur EINEN Behälter zeigen, nämlich den
## angelegten. Ein Fenster geht für jeden auf — auch für einen Rucksack, der
## noch in der Kiste liegt. Damit kann man hineinsehen, BEVOR man ihn
## mitnimmt, und das ist die eigentliche Entscheidung: Lohnt es sich, dafür
## stehenzubleiben?
##
## Das Fenster gehört seinem Wirtfenster (Charakter oder Kiste) und geht mit
## ihm zu. Ein Rucksackfenster, das offen bleibt, während man weiterläuft,
## wäre ein zweiter Bildschirm mitten im Raid.
class_name ContainerWindow
extends Control

signal closed()

## Wie viel von der Titelleiste immer sichtbar bleiben muss.
##
## Ohne diese Grenze liesse sich das Fenster so weit hinausschieben, dass die
## Titelleiste ausserhalb des Bildes liegt — danach bekommt man es nie wieder
## zu fassen und auch nicht mehr zu.
const MIN_VISIBLE := Vector2(80.0, 30.0)

## Der Gegenstand, dessen Inneres gezeigt wird.
var stack: ItemStack = null

@onready var view: InventoryGridView = $Fenster/Inhalt/Raster
@onready var _panel: PanelContainer = $Fenster
@onready var _bar: Control = $Fenster/Inhalt/Titelleiste
@onready var _title: Label = $Fenster/Inhalt/Titelleiste/Titel
@onready var _free: Label = $Fenster/Inhalt/Titelleiste/Frei
@onready var _close_button: Button = $Fenster/Inhalt/Titelleiste/Schliessen

## Abstand zwischen Zeiger und Fensterecke beim Anfassen der Titelleiste.
var _grab_offset := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	hide()
	set_process(false)
	_bar.gui_input.connect(_on_bar_input)
	_close_button.pressed.connect(close)


## Öffnet das Fenster für einen Behälter.
##
## Ist bereits dasselbe Fenster offen, wird es nur neu einsortiert statt ein
## zweites zu öffnen — zwei Fenster auf dasselbe Raster wären zwei Ansichten
## derselben Sache und ein sicherer Weg, sich zu verzetteln.
func open_for(p_stack: ItemStack, at_position: Vector2) -> bool:
	if p_stack == null or p_stack.container == null:
		return false

	var same := stack == p_stack and visible
	stack = p_stack

	var data := stack.get_data()
	_title.text = data.display_name if data != null else "Behaelter"
	view.setup(stack.container, _title.text)

	show()
	if not same:
		_move_to(at_position)
	_refresh()
	set_process(true)
	return true


func close() -> void:
	if not visible:
		return
	_dragging = false
	stack = null
	view.grid = null
	hide()
	set_process(false)
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if _dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_dragging = false
		else:
			_move_to(get_global_mouse_position() - _grab_offset)
	_refresh()


func _refresh() -> void:
	if stack == null or stack.container == null:
		return
	var grid := stack.container
	_free.text = "%d von %d frei" % [
		grid.get_free_cell_count(), grid.width * grid.height]
	view.queue_redraw()


## Verschiebt das Fenster, aber nie so weit, dass die Titelleiste aus dem Bild
## fällt.
func _move_to(target: Vector2) -> void:
	_panel.position = clamp_position(target, _panel.size, size)


## Bewusst statisch und ohne Knoten: So laesst sich im Test nachrechnen, dass
## ein Fenster nicht aus dem Bild geschoben werden kann, ohne eine Maus zu
## brauchen.
static func clamp_position(target: Vector2, panel_size: Vector2,
		screen_size: Vector2) -> Vector2:
	return Vector2(
		clampf(target.x, MIN_VISIBLE.x - panel_size.x, screen_size.x - MIN_VISIBLE.x),
		clampf(target.y, 0.0, maxf(0.0, screen_size.y - MIN_VISIBLE.y))
	)


func _on_bar_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return

	if button.pressed:
		_dragging = true
		_grab_offset = get_global_mouse_position() - _panel.global_position
		accept_event()
	else:
		_dragging = false
