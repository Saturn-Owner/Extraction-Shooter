## Kleines Menü, das beim Rechtsklick neben dem Zeiger aufgeht.
##
## Gebaut wie der SplitPrompt: ein Vollbild-Control, in dem ein Panel frei
## positioniert wird. Ein Unterschied ist wichtig — dieses Control steht auf
## `MOUSE_FILTER_STOP`. Nur so bekommt es den Klick DANEBEN zu sehen und kann
## sich schliessen. Der SplitPrompt kann das nicht und braucht es auch nicht,
## weil er zwei Knöpfe hat; ein Kontextmenü ohne "Klick daneben schliesst"
## wäre dagegen eine Falle.
##
## Die Einträge kommen von aussen. Vorerst gibt es nur "Öffnen", aber
## "Ablegen", "Anlegen" und "Aufteilen" sind absehbar — deshalb eine Liste
## statt fester Knöpfe.
class_name ContextMenu
extends Control

signal chosen(id: StringName)
signal cancelled()

## Abstand zum Zeiger. Direkt darunter würde der erste Eintrag beim Loslassen
## der Maustaste versehentlich mitgeklickt.
const OFFSET := Vector2(6.0, 6.0)

@onready var _panel: PanelContainer = $Panel
@onready var _entries: VBoxContainer = $Panel/Eintraege


## Welche Einträge es für diesen Gegenstand gibt.
##
## An einer Stelle, weil beide Wirtfenster dieselbe Antwort brauchen — und
## damit sich im Test nachrechnen laesst, dass eine Patrone kein Menue bekommt.
static func entries_for(stack: ItemStack) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if stack == null:
		return entries
	if stack.container != null:
		entries.append({id = &"oeffnen", label = "Oeffnen"})
	return entries


func _ready() -> void:
	hide()


## Öffnet das Menü. `entries` ist eine Liste aus {id: StringName, label: String}.
## Eine leere Liste öffnet bewusst gar nichts — ein leeres Menü sähe aus wie
## ein Fehler, und der Spieler müsste es wieder wegklicken.
func open(entries: Array[Dictionary], at_position: Vector2) -> void:
	if entries.is_empty():
		close()
		return

	for child in _entries.get_children():
		child.queue_free()

	for entry in entries:
		var button := Button.new()
		button.text = String(entry.get("label", "?"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(150, 28)
		button.pressed.connect(_on_entry_pressed.bind(StringName(entry.get("id", &""))))
		_entries.add_child(button)

	show()
	_place_at(at_position)


## Setzt das Panel neben den Zeiger, ohne über den Bildschirmrand zu geraten.
##
## Am rechten Rand klappt es nach links um, statt nur zu klemmen — geklemmt
## läge es unter dem Zeiger und man würde den obersten Eintrag anfassen, ohne
## ihn lesen zu können. Dasselbe macht der ItemTooltip.
func _place_at(at_position: Vector2) -> void:
	# Die Größe steht erst, wenn die Knöpfe eingehängt sind.
	var panel_size := _panel.get_combined_minimum_size()
	var limit := size - panel_size

	var x := at_position.x + OFFSET.x
	if x > limit.x:
		x = at_position.x - panel_size.x - OFFSET.x

	var y := at_position.y + OFFSET.y
	if y > limit.y:
		y = at_position.y - panel_size.y - OFFSET.y

	_panel.position = Vector2(
		clampf(x, 0.0, maxf(0.0, limit.x)),
		clampf(y, 0.0, maxf(0.0, limit.y))
	)


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	hide()
	cancelled.emit()


func _on_entry_pressed(id: StringName) -> void:
	hide()
	chosen.emit(id)


## Ein Klick irgendwo neben dem Panel schliesst das Menü.
##
## Das Control liegt über dem ganzen Bild und faengt den Klick ab. Er ist damit
## verbraucht — genau richtig: Wer das Menü wegklickt, will nicht gleichzeitig
## den Gegenstand darunter anfassen.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if _panel.get_global_rect().has_point(button.global_position):
		return
	close()
	accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.is_pressed() or key.is_echo():
		return
	if key.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
