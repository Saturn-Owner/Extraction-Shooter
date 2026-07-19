## Fragt, wie viele Stueck eines Stapels verschoben werden sollen.
##
## Erscheint beim Ziehen mit gedrueckter Strg-Taste. Ohne Strg wandert immer
## der ganze Stapel — der haeufigere Fall soll ohne Rueckfrage gehen.
##
## Voreingestellt ist die Haelfte: Wer aufteilt, will meistens teilen, und
## die Haelfte ist von dort aus mit wenigen Schritten in beide Richtungen
## erreichbar.
class_name SplitPrompt
extends Control

signal confirmed(amount: int)
signal cancelled()

var _maximum: int = 1

@onready var _slider: HSlider = $Panel/Inhalt/Slider
@onready var _amount: Label = $Panel/Inhalt/Menge
@onready var _title: Label = $Panel/Inhalt/Titel
@onready var _panel: PanelContainer = $Panel


func _ready() -> void:
	hide()
	_slider.value_changed.connect(_on_slider_changed)
	$Panel/Inhalt/Knoepfe/Nehmen.pressed.connect(_confirm)
	$Panel/Inhalt/Knoepfe/Abbrechen.pressed.connect(cancel)


## Öffnet die Abfrage. `at_position` ist die Bildschirmposition des Zeigers.
func ask(item_name: String, maximum: int, at_position: Vector2) -> void:
	_maximum = maxi(1, maximum)

	_title.text = item_name
	_slider.min_value = 1
	_slider.max_value = _maximum
	_slider.value = maxi(1, _maximum / 2)

	show()
	_update_label()

	# Neben den Zeiger setzen, aber nie ueber den Bildschirmrand hinaus.
	var panel_size := _panel.get_combined_minimum_size()
	var limit := size - panel_size
	_panel.position = Vector2(
		clampf(at_position.x + 12.0, 0.0, maxf(0.0, limit.x)),
		clampf(at_position.y + 12.0, 0.0, maxf(0.0, limit.y))
	)

	_slider.grab_focus()


func is_open() -> bool:
	return visible


func get_amount() -> int:
	return int(_slider.value)


func _on_slider_changed(_value: float) -> void:
	_update_label()


func _update_label() -> void:
	_amount.text = "%d von %d" % [get_amount(), _maximum]


func _confirm() -> void:
	var amount := get_amount()
	hide()
	confirmed.emit(amount)


func cancel() -> void:
	if not visible:
		return
	hide()
	cancelled.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.is_pressed() or key.is_echo():
		return

	match key.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()
