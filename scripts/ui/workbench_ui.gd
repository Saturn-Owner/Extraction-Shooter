## Oberfläche der Waffenwerkbank.
##
##     Waffe        →   Steckplatz     →   Teil        |  Vorschau
##     (was du       (was diese         (was hier      |  und Werte
##      dabei hast)   Waffe anbietet)    passt)        |
##
## Die Oberfläche ändert NICHTS selbst. Jeder Klick geht als Anfrage an die
## Station, und erst deren Antwort führt zum Neuzeichnen (Grundsatz 2).
## Deshalb ist die Fehlermeldung unten kein Schönheitsfehler, sondern der
## sichtbare Beweis, dass die Prüfung woanders sitzt.
##
## Zeigt man mit der Maus auf ein Teil, ohne zu klicken, rechnet die Wertespalte
## sofort aus, was es ändern würde. Das ist der eigentliche Zweck der Bank:
## Man soll die Entscheidung treffen können, BEVOR man schraubt.
##
## Wird im Code aufgebaut, nicht als .tscn: Szenen lassen sich bei Konflikten
## nicht mergen, und an dieser Datei wird noch viel geändert.
class_name WorkbenchUI
extends CanvasLayer

const COLUMN_WIDTH := 240.0

## Die angezeigten Werte. `higher_is_better` entscheidet nur über das
## Vorzeichen in der Anzeige — mehr Ergonomie ist gut, mehr Streuung nicht.
const STATS := [
	{label = "Rueckstoss hoch", field = "recoil_vertical", digits = 0, higher_is_better = false},
	{label = "Rueckstoss seitlich", field = "recoil_horizontal", digits = 0, higher_is_better = false},
	{label = "Ergonomie", field = "ergonomics", digits = 0, higher_is_better = true},
	{label = "Streuung (MOA)", field = "accuracy_moa", digits = 2, higher_is_better = false},
	{label = "Sichtfeld beim Zielen", field = "ads_fov", digits = 0, higher_is_better = false},
	{label = "Zielzeit", field = "ads_time_multiplier", digits = 2, higher_is_better = false},
	{label = "Lautstaerke", field = "loudness_multiplier", digits = 2, higher_is_better = false},
]

## Wer die Anfragen entgegennimmt. Muss vor show_for() gesetzt sein.
var station: WorkbenchStation

var _player: PlayerController
var _stack: ItemStack = null
var _slot: int = -1
var _message: String = ""

## Das Teil, auf das der Spieler gerade zeigt, ohne geklickt zu haben.
## `_hovering` unterscheidet dabei "zeigt auf Abnehmen" (leere ID) von
## "zeigt auf gar nichts" — beides wäre sonst dieselbe leere ID.
var _candidate: StringName = &""
var _hovering: bool = false

var _weapon_column: VBoxContainer
var _slot_column: VBoxContainer
var _part_column: VBoxContainer
var _stats_grid: GridContainer
var _condition_label: Label
var _repair_button: Button
var _preview: WeaponPreview
var _message_label: Label


func _ready() -> void:
	# Muss bei angehaltenem Spiel weiterlaufen, sonst reagiert kein Knopf.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_layout()
	# CanvasLayer erbt nicht von CanvasItem — es gibt hier kein show()/hide(),
	# nur das Feld.
	visible = false


func _build_layout() -> void:
	var background := ColorRect.new()
	background.name = "Hintergrund"
	background.color = Color(0.06, 0.07, 0.08, 0.94)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 32)
	background.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "WERKBANK"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	_weapon_column = _add_column(columns, "Waffe")
	_slot_column = _add_column(columns, "Steckplatz")
	_part_column = _add_column(columns, "Teil")
	_build_right_panel(columns)

	_message_label = Label.new()
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	root.add_child(_message_label)

	var hint := Label.new()
	hint.text = "Tab schliesst die Werkbank  ·  auf ein Teil zeigen zeigt seine Wirkung"
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	root.add_child(hint)


## Vorschau, Werte und Instandsetzung.
func _build_right_panel(parent: HBoxContainer) -> void:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	_preview = WeaponPreview.new()
	_preview.name = "Vorschau"
	panel.add_child(_preview)

	# Drei Spalten: Bezeichnung, jetziger Wert, Wert mit dem Teil, auf das
	# gerade gezeigt wird.
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 3
	_stats_grid.add_theme_constant_override("h_separation", 18)
	panel.add_child(_stats_grid)

	var repair_row := HBoxContainer.new()
	repair_row.add_theme_constant_override("separation", 12)
	panel.add_child(repair_row)

	_condition_label = Label.new()
	repair_row.add_child(_condition_label)

	_repair_button = Button.new()
	_repair_button.text = "Instandsetzen"
	_repair_button.pressed.connect(_on_repair)
	repair_row.add_child(_repair_button)


## Eine Spalte mit Überschrift. Gibt den Behälter für die Knöpfe zurück.
func _add_column(parent: HBoxContainer, heading: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var label := Label.new()
	label.text = heading
	label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	column.add_child(label)

	var list := VBoxContainer.new()
	list.name = "Liste"
	list.add_theme_constant_override("separation", 4)
	column.add_child(list)
	return list


# ------------------------------------------------------------------ Anzeige

func show_for(player: PlayerController) -> void:
	_player = player
	_message = ""
	_candidate = &""

	# Beim Öffnen die Waffe in der Hand vorwählen — das ist fast immer die,
	# die man umbauen will.
	_stack = null
	if player != null and player.inventory != null:
		_stack = player.inventory.equipped_weapon
	_slot = -1

	refresh()
	visible = true


func refresh() -> void:
	_refresh_weapons()
	_refresh_slots()
	_refresh_parts()
	_refresh_stats()
	_refresh_condition()
	_refresh_preview()
	_message_label.text = _message


func _refresh_weapons() -> void:
	_clear(_weapon_column)
	if _player == null or _player.inventory == null:
		return

	for stack in _player.inventory.get_carried_weapons():
		var data := stack.get_data()
		if data == null:
			continue
		var suffix := ""
		if not stack.attachments.is_empty():
			suffix = "  (%d Teile)" % stack.attachments.size()
		var button := _make_button(data.display_name + suffix, stack == _stack)
		button.pressed.connect(_on_weapon_chosen.bind(stack))
		_weapon_column.add_child(button)


func _refresh_slots() -> void:
	_clear(_slot_column)
	var weapon_data := _current_weapon_data()
	if weapon_data == null:
		return

	for slot in weapon_data.get_slots():
		var mounted: String = "leer"
		if _stack.attachments.has(int(slot)):
			var part := ItemRegistry.get_item(_stack.attachments[int(slot)])
			mounted = part.display_name if part != null else "unbekannt"
		var button := _make_button(
			"%s: %s" % [AttachmentData.slot_name(slot), mounted], int(slot) == _slot)
		button.pressed.connect(_on_slot_chosen.bind(int(slot)))
		_slot_column.add_child(button)


func _refresh_parts() -> void:
	_clear(_part_column)
	var weapon_data := _current_weapon_data()
	if weapon_data == null or _slot < 0:
		return

	if _stack.attachments.has(_slot):
		var remove := _make_button("— abnehmen —", false)
		remove.pressed.connect(_on_detach)
		remove.mouse_entered.connect(_on_candidate.bind(&""))
		remove.mouse_exited.connect(_on_candidate_cleared)
		_part_column.add_child(remove)

	for attachment in WorkbenchStation.get_options(weapon_data, _slot as AttachmentData.Slot):
		var is_mounted: bool = _stack.attachments.get(_slot, &"") == attachment.id
		var button := _make_button(attachment.display_name, is_mounted)
		button.pressed.connect(_on_attach.bind(attachment.id))
		# Zeigen genügt, um die Wirkung zu sehen — kein Klick nötig.
		button.mouse_entered.connect(_on_candidate.bind(attachment.id))
		button.mouse_exited.connect(_on_candidate_cleared)
		button.tooltip_text = attachment.description
		_part_column.add_child(button)


## Werte der ausgewählten Waffe: jetzt, und wie sie mit dem Teil wären, auf
## das der Spieler gerade zeigt.
func _refresh_stats() -> void:
	_clear(_stats_grid)
	var base := _current_weapon_data()
	if base == null:
		return

	var current := WeaponBuild.apply(base, WeaponBuild.from_stack(_stack))
	var candidate := _candidate_data(base)

	_add_stat_row("", "jetzt", "danach" if candidate != null else "",
		Color(0.65, 0.72, 0.8))

	for stat in STATS:
		var now: float = current.get(stat.field)
		var later: float = candidate.get(stat.field) if candidate != null else now
		var format := "%%.%df" % stat.digits

		var colour := Color(0.85, 0.86, 0.88)
		var later_text := ""
		if candidate != null and not is_equal_approx(now, later):
			var better: bool = (later > now) == stat.higher_is_better
			colour = Color(0.55, 0.9, 0.55) if better else Color(1.0, 0.55, 0.45)
			later_text = format % later

		_add_stat_row(stat.label, format % now, later_text, colour)

	_add_weight_row(base)


## Das Gewicht steht bewusst unter den Werten und nicht dazwischen: Es kommt
## nicht aus der WeaponData, sondern aus der Waffe plus allem, was dranhängt.
## Es ist der Preis, den jedes Teil kostet — auch die, die sonst nur Vorteile
## haben.
func _add_weight_row(base: WeaponData) -> void:
	var now := _build_weight(base, WeaponBuild.from_stack(_stack))
	var later_text := ""
	var colour := Color(0.85, 0.86, 0.88)

	if _slot >= 0 and _hovering:
		var build := WeaponBuild.from_stack(_stack)
		if _candidate == &"":
			build.clear_slot(_slot as AttachmentData.Slot)
		else:
			build.set_attachment(_slot as AttachmentData.Slot, _candidate)
		var later := _build_weight(base, build)
		if not is_equal_approx(now, later):
			colour = Color(0.55, 0.9, 0.55) if later < now else Color(1.0, 0.55, 0.45)
			later_text = "%.2f kg" % later

	_add_stat_row("Gewicht", "%.2f kg" % now, later_text, colour)


func _build_weight(base: WeaponData, build: WeaponBuild) -> float:
	var total := base.weight_kg
	for attachment in build.get_all():
		total += attachment.weight_kg
	return total


func _add_stat_row(label: String, now: String, later: String, colour: Color) -> void:
	for text in [label, now, later]:
		var cell := Label.new()
		cell.text = text
		cell.add_theme_font_size_override("font_size", 14)
		cell.add_theme_color_override("font_color", colour)
		_stats_grid.add_child(cell)


## Die Werte, die die Waffe hätte, wenn man das gezeigte Teil anbaut.
## null, wenn gerade auf nichts gezeigt wird.
func _candidate_data(base: WeaponData) -> WeaponData:
	if _slot < 0 or not _hovering:
		return null

	var build := WeaponBuild.from_stack(_stack)
	if _candidate == &"":
		build.clear_slot(_slot as AttachmentData.Slot)
	else:
		build.set_attachment(_slot as AttachmentData.Slot, _candidate)
	return WeaponBuild.apply(base, build)


func _refresh_condition() -> void:
	if _stack == null:
		_condition_label.text = ""
		_repair_button.disabled = true
		return

	var condition := _stack.durability
	if condition < 0.0:
		condition = WorkbenchStation.FULL_CONDITION
	_condition_label.text = "Zustand: %.0f %%" % condition
	_repair_button.disabled = condition >= WorkbenchStation.FULL_CONDITION


func _refresh_preview() -> void:
	if _preview == null:
		return
	# Die Vorschau zeigt, was gerade wirklich an der Waffe ist — nicht das
	# Teil, auf das gezeigt wird. Ein Modell, das beim Mausbewegen aufflackert,
	# macht die Beurteilung unmöglich.
	if _stack == null:
		_preview.show_weapon(null, {})
		return
	_preview.show_weapon(_current_weapon_data(), _stack.attachments)


func _current_weapon_data() -> WeaponData:
	if _stack == null:
		return null
	return _stack.get_data() as WeaponData


func _make_button(text: String, highlighted: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if highlighted:
		button.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
	return button


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# -------------------------------------------------------------- Bedienung

func _on_weapon_chosen(stack: ItemStack) -> void:
	_stack = stack
	_slot = -1
	_message = ""
	_hovering = false
	refresh()


func _on_slot_chosen(slot: int) -> void:
	_slot = slot
	_message = ""
	_hovering = false
	refresh()


## Nur die Wertespalte neu zeichnen. Würde hier refresh() laufen, würden die
## Knöpfe unter der Maus neu gebaut — die Maus verlöre den Knopf, auf dem sie
## steht, und der Vergleich flackerte bei jeder Bewegung.
func _on_candidate(attachment_id: StringName) -> void:
	_candidate = attachment_id
	_hovering = true
	_refresh_stats()


func _on_candidate_cleared() -> void:
	_candidate = &""
	_hovering = false
	_refresh_stats()


func _on_attach(attachment_id: StringName) -> void:
	if station == null or _stack == null or _slot < 0:
		return
	_message = station.request_attach(_stack.instance_id, _slot as AttachmentData.Slot, attachment_id)
	_hovering = false
	refresh()


func _on_detach() -> void:
	if station == null or _stack == null or _slot < 0:
		return
	_message = station.request_detach(_stack.instance_id, _slot as AttachmentData.Slot)
	_hovering = false
	refresh()


func _on_repair() -> void:
	if station == null or _stack == null:
		return
	_message = station.request_repair(_stack.instance_id)
	refresh()
