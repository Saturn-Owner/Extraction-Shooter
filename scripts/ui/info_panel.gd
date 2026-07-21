## Generisches Infofenster für Menüpunkte ohne eigenes System (Store/Shop,
## Statistiken/Profil). Zeigt ehrlich, dass es das noch nicht gibt, statt
## Zahlen zu erfinden — anders als der ursprüngliche Entwurf, der dort
## erfundene Werte (K/D, Level) zeigte.
class_name InfoPanel
extends Control

signal closed()

@onready var _index_label: Label = $Panel/Inhalt/Kopf/Index
@onready var _title_label: Label = $Panel/Inhalt/Kopf/Titel
@onready var _body_label: Label = $Panel/Inhalt/Text
@onready var _close_button: Button = $Panel/Inhalt/Kopf/Schliessen


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)


func open(index: String, title: String, body: String) -> void:
	_index_label.text = index
	_title_label.text = title
	_body_label.text = body
	show()


func _on_close_pressed() -> void:
	hide()
	closed.emit()
