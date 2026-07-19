## Infoanzeige, die erscheint, wenn der Zeiger auf einem Gegenstand steht.
##
## Die Werte kommen aus den Datenklassen selbst (get_info_lines), nicht aus
## einer Fallunterscheidung hier. Sonst müsste diese Datei jedes Mal
## angefasst werden, wenn eine neue Gegenstandsart dazukommt — genau das
## soll die datengetriebene Architektur verhindern.
class_name ItemTooltip
extends Control

## Abstand zum Mauszeiger, damit die Anzeige nicht unter ihm klebt.
const OFFSET := Vector2(18.0, 14.0)

var _stack: ItemStack = null

@onready var _panel: PanelContainer = $Panel
@onready var _name: Label = $Panel/Inhalt/Name
@onready var _type: Label = $Panel/Inhalt/Typ
@onready var _stats: Label = $Panel/Inhalt/Werte


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	set_process(false)


func show_for(stack: ItemStack) -> void:
	if stack == null:
		clear()
		return

	var data := stack.get_data()
	if data == null:
		clear()
		return

	_stack = stack

	var title := data.display_name
	if stack.quantity > 1:
		title += "  x%d" % stack.quantity
	_name.text = title
	_name.add_theme_color_override("font_color", get_rarity_color(data.get_rarity()))

	_type.text = data.get_type_label()

	var lines := data.get_info_lines()
	# Haltbarkeit gehoert ans Exemplar, nicht an die Vorlage: zwei Platten
	# derselben Sorte koennen unterschiedlich zerschossen sein.
	if stack.durability >= 0.0:
		var plate := data as ArmorPlateData
		if plate != null:
			lines.insert(0, "Zustand:      %.0f von %.0f" % [stack.durability, plate.max_durability])
	_stats.text = "\n".join(lines)

	show()
	set_process(true)
	_follow_mouse()


func clear() -> void:
	_stack = null
	hide()
	set_process(false)


func is_showing_for(stack: ItemStack) -> bool:
	return visible and _stack == stack


func _process(_delta: float) -> void:
	_follow_mouse()


## Neben dem Zeiger halten, aber nie über den Bildschirmrand hinaus.
func _follow_mouse() -> void:
	var panel_size := _panel.get_combined_minimum_size()
	var mouse := get_local_mouse_position()
	var limit := size - panel_size

	# Nach links kippen, wenn rechts kein Platz mehr ist — sonst würde die
	# Anzeige am Rand kleben und den Gegenstand verdecken.
	var x := mouse.x + OFFSET.x
	if x > limit.x:
		x = mouse.x - panel_size.x - OFFSET.x

	_panel.position = Vector2(
		clampf(x, 0.0, maxf(0.0, limit.x)),
		clampf(mouse.y + OFFSET.y, 0.0, maxf(0.0, limit.y))
	)


## Farbe je Seltenheitsstufe. Gedämpft gehalten — das Inventar soll düster
## bleiben, nicht leuchten wie ein Rollenspiel-Beutefenster.
static func get_rarity_color(rarity: ItemData.Rarity) -> Color:
	match rarity:
		ItemData.Rarity.EPIC: return Color(0.82, 0.66, 0.36)
		ItemData.Rarity.RARE: return Color(0.52, 0.66, 0.82)
		ItemData.Rarity.UNCOMMON: return Color(0.60, 0.72, 0.56)
	return Color(0.70, 0.72, 0.74)
