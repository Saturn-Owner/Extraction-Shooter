## Der Charakterbildschirm: Körper, Ausrüstung, Zustand.
##
## ---------------------------------------------------------------------------
## AUFBAU
##
##   links   Körperschema mit Trefferpunkten je Teil, anklickbar
##   mitte   Ausrüstungsplätze (Helm, Brust, Oberteil, Gürtel, Hose, Schuhe)
##   rechts  Hunger, Durst, Kälte
##
## Der Körper ist selbst gezeichnet, nicht aus Knoten zusammengesetzt: Er
## besteht aus sieben Flächen, die sich je nach Zustand einfärben. Sieben
## Knoten mit Stylebox-Umschaltung wären mehr Code für dasselbe Bild.
##
## WAS DIE FARBEN BEDEUTEN
## Grün bis Rot zeigt den Zustand. Schwarz heißt zerstört — und weil Kopf
## und Brust sofort tödlich sind, sieht man bei einem lebenden Spieler dort
## nie Schwarz. Genau das soll die Anzeige vermitteln: Arme und Beine kann
## man verlieren, den Rumpf nicht.
class_name CharacterWindow
extends Control

signal closed()
signal opened()

const COLOR_HEALTHY := Color(0.42, 0.66, 0.40)
const COLOR_HURT := Color(0.80, 0.70, 0.30)
const COLOR_CRITICAL := Color(0.78, 0.30, 0.24)
const COLOR_DESTROYED := Color(0.10, 0.10, 0.11)
const COLOR_OUTLINE := Color(0.35, 0.38, 0.42)
const COLOR_SELECTED := Color(0.85, 0.86, 0.88)

var player: PlayerController = null

## Welches Körperteil gerade ausgewählt ist — dazu zeigt die Anzeige Details.
var _selected: HealthSystem.Part = HealthSystem.Part.CHEST

@onready var _body: Control = $Layout/Spalten/Koerper/Schema
@onready var _body_detail: Label = $Layout/Spalten/Koerper/Detail
@onready var _slots_box: VBoxContainer = $Layout/Spalten/Ausruestung/Slots
@onready var _hp_label: Label = $Layout/Spalten/Zustand/GesamtHP
@onready var _hunger: ProgressBar = $Layout/Spalten/Zustand/Hunger/Balken
@onready var _thirst: ProgressBar = $Layout/Spalten/Zustand/Durst/Balken
@onready var _warmth: ProgressBar = $Layout/Spalten/Zustand/Kaelte/Balken
@onready var _hunger_text: Label = $Layout/Spalten/Zustand/Hunger/Wert
@onready var _thirst_text: Label = $Layout/Spalten/Zustand/Durst/Wert
@onready var _warmth_text: Label = $Layout/Spalten/Zustand/Kaelte/Wert
@onready var _condition: Label = $Layout/Spalten/Zustand/Auswirkung

## Slot -> Knopf, damit die Anzeige nicht jedes Mal neu aufgebaut wird.
var _slot_buttons: Dictionary = {}


func _ready() -> void:
	hide()
	_body.draw.connect(_draw_body)
	_body.gui_input.connect(_on_body_input)
	_build_slots()


func open_for(p_player: PlayerController) -> void:
	player = p_player
	show()
	_refresh()
	opened.emit()


func close() -> void:
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if visible and player != null:
		_refresh()


# ---------------------------------------------------------------------------
# Körperschema
# ---------------------------------------------------------------------------

## Wo die Körperteile im Schema liegen, in Anteilen der Zeichenfläche.
## Relativ statt in Pixeln, damit das Schema mitwächst.
const BODY_RECTS := {
	HealthSystem.Part.HEAD: Rect2(0.38, 0.02, 0.24, 0.14),
	HealthSystem.Part.CHEST: Rect2(0.30, 0.18, 0.40, 0.22),
	HealthSystem.Part.STOMACH: Rect2(0.32, 0.41, 0.36, 0.16),
	HealthSystem.Part.LEFT_ARM: Rect2(0.10, 0.18, 0.18, 0.34),
	HealthSystem.Part.RIGHT_ARM: Rect2(0.72, 0.18, 0.18, 0.34),
	HealthSystem.Part.LEFT_LEG: Rect2(0.30, 0.59, 0.18, 0.39),
	HealthSystem.Part.RIGHT_LEG: Rect2(0.52, 0.59, 0.18, 0.39),
}


func _rect_for(part: HealthSystem.Part) -> Rect2:
	var r: Rect2 = BODY_RECTS[part]
	var size := _body.size
	return Rect2(r.position * size, r.size * size)


func _draw_body() -> void:
	if player == null or player.health == null:
		return

	var font := ThemeDB.fallback_font

	for part in BODY_RECTS:
		var rect := _rect_for(part)
		var ratio := player.health.get_ratio(part)

		_body.draw_rect(rect, _color_for(ratio))

		var selected: bool = part == _selected
		_body.draw_rect(rect, COLOR_SELECTED if selected else COLOR_OUTLINE,
			false, 2.0 if selected else 1.0)

		# Zahlen direkt im Schema: Wer schnell schaut, will nicht erst
		# klicken muessen, um zu sehen, wo es brennt.
		var text := "%d" % roundi(player.health.get_hp(part))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var pos := rect.position + Vector2((rect.size.x - width) * 0.5, rect.size.y * 0.5 + 4.0)
		_body.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.95, 0.96, 0.97) if ratio > 0.0 else Color(0.55, 0.20, 0.18))


## Gruen bei voll, ueber Gelb nach Rot, schwarz bei zerstoert.
func _color_for(ratio: float) -> Color:
	if ratio <= 0.0:
		return COLOR_DESTROYED
	if ratio > 0.5:
		return COLOR_HURT.lerp(COLOR_HEALTHY, (ratio - 0.5) * 2.0)
	return COLOR_CRITICAL.lerp(COLOR_HURT, ratio * 2.0)


func _on_body_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return

	for part in BODY_RECTS:
		if _rect_for(part).has_point(button.position):
			_selected = part
			_body.queue_redraw()
			return


# ---------------------------------------------------------------------------
# Ausrüstung
# ---------------------------------------------------------------------------

func _build_slots() -> void:
	for slot in Equipment.SLOT_ORDER:
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 34)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_slot_pressed.bind(slot))
		_slots_box.add_child(button)
		_slot_buttons[slot] = button


## Klick auf einen belegten Platz legt ab — zurueck ins Inventar.
##
## Passt es dort nicht, bleibt es angezogen. Etwas fallen zu lassen, weil
## kein Platz ist, waere im Raid ein stiller Verlust.
func _on_slot_pressed(slot: ItemData.EquipSlot) -> void:
	if player == null or player.equipment == null:
		return

	var worn := player.equipment.get_item(slot)
	if worn == null:
		return

	if not player.inventory.grid.add_item(worn):
		return

	player.equipment.unequip(slot)
	_refresh()


func _refresh_slots() -> void:
	for slot in _slot_buttons:
		var button: Button = _slot_buttons[slot]
		var worn: ItemStack = player.equipment.get_item(slot) if player.equipment != null else null
		var slot_name := Equipment.get_slot_name(slot)

		if worn == null:
			button.text = "%s:  —" % slot_name
			button.disabled = true
			button.tooltip_text = ""
			continue

		var data := worn.get_data()
		button.disabled = false
		button.text = "%s:  %s" % [slot_name, data.display_name if data != null else "?"]
		button.tooltip_text = "Klicken zum Ablegen"
		if data != null:
			button.add_theme_color_override("font_color",
				ItemTooltip.get_rarity_color(data.get_rarity()))


# ---------------------------------------------------------------------------
# Zustand
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if player == null:
		return

	_body.queue_redraw()
	_refresh_slots()
	_refresh_detail()
	_refresh_bars()


func _refresh_detail() -> void:
	if player.health == null:
		return
	var name := HealthSystem.get_part_name(_selected)
	var hp := player.health.get_hp(_selected)
	var maximum := HealthSystem.get_max_hp(_selected)

	var lines := ["%s:  %d / %d" % [name, roundi(hp), roundi(maximum)]]
	if HealthSystem.is_vital(_selected):
		lines.append("Lebenswichtig — faellt es aus, ist der Raid vorbei.")
	elif player.health.is_destroyed(_selected):
		lines.append("Ausgefallen. Weitere Treffer gehen auf die Brust.")

	_body_detail.text = "\n".join(lines)

	_hp_label.text = "Gesamt:  %d / %d" % [
		roundi(player.health.get_total_hp()),
		roundi(HealthSystem.get_total_max_hp()),
	]


func _refresh_bars() -> void:
	if player.survival == null:
		return
	var s := player.survival

	_hunger.value = s.get_hunger_ratio() * 100.0
	_thirst.value = s.get_thirst_ratio() * 100.0
	_warmth.value = s.get_warmth_ratio() * 100.0

	_hunger_text.text = "%d %%" % roundi(s.get_hunger_ratio() * 100.0)
	_thirst_text.text = "%d %%" % roundi(s.get_thirst_ratio() * 100.0)
	_warmth_text.text = "%.1f Grad" % s.temperature

	_condition.text = _describe_condition()


## Sagt in Worten, was die Werte gerade anrichten. Ein Balken allein erklaert
## nicht, warum man ploetzlich langsamer laeuft.
func _describe_condition() -> String:
	var notes: Array[String] = []

	if player.health != null:
		var legs := player.health.get_movement_penalty()
		if legs > 0.0:
			notes.append("Beinverletzung:  %d %% langsamer" % roundi(legs * 100.0))
		var arms := player.health.get_aim_penalty()
		if arms > 0.0:
			notes.append("Armverletzung:  %d %% unruhiger" % roundi(arms * 100.0))
		if player.health.is_destroyed(HealthSystem.Part.STOMACH):
			notes.append("Bauchverletzung:  Hunger und Durst steigen schneller")

	if player.survival != null:
		var cold := player.survival.get_cold_movement_penalty()
		if cold > 0.0:
			notes.append("Unterkuehlt:  %d %% langsamer" % roundi(cold * 100.0))
		if player.survival.hunger <= 0.0:
			notes.append("Verhungert:  laufender Schaden am Bauch")
		if player.survival.thirst <= 0.0:
			notes.append("Verdurstet:  laufender Schaden am Bauch")
		if player.survival.temperature <= player.survival.critical_temperature:
			notes.append("Erfrierungen:  Schaden an Armen und Beinen")

	if notes.is_empty():
		return "Keine Beeintraechtigung."
	return "\n".join(notes)
