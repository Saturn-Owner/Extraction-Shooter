## Oberfläche der Waffenwerkbank: drei Spalten, von links nach rechts.
##
##     Waffe        →   Steckplatz     →   Teil
##     (was du       (was diese         (was an diese Aufnahme
##      dabei hast)   Waffe anbietet)    passt)
##
## Bewusst schmucklos. Kein Theme, keine Farben ausser dem Nötigsten — das
## kommt, wenn die Schleife nachweislich funktioniert. Wer zuerst gestaltet
## und dann merkt, dass die Bedienung nicht stimmt, gestaltet zweimal.
##
## Die Oberfläche ändert NICHTS selbst. Jeder Klick geht als Anfrage an die
## Station, und erst deren Antwort führt zum Neuzeichnen (Grundsatz 2).
## Deshalb ist die Fehlermeldung unten kein Schönheitsfehler, sondern der
## sichtbare Beweis, dass die Prüfung woanders sitzt.
##
## Wird im Code aufgebaut, nicht als .tscn: Szenen lassen sich bei Konflikten
## nicht mergen, und an dieser Datei wird noch viel geändert.
class_name WorkbenchUI
extends CanvasLayer

const COLUMN_WIDTH := 260.0

## Wer die Anfragen entgegennimmt. Muss vor show_for() gesetzt sein.
var station: WorkbenchStation

var _player: PlayerController
var _stack: ItemStack = null
var _slot: int = -1
var _message: String = ""

var _weapon_column: VBoxContainer
var _slot_column: VBoxContainer
var _part_column: VBoxContainer
var _stats_label: Label
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
	background.color = Color(0.06, 0.07, 0.08, 0.92)
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

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	root.add_child(_stats_label)

	_message_label = Label.new()
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	root.add_child(_message_label)

	var hint := Label.new()
	hint.text = "Tab schliesst die Werkbank"
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	root.add_child(hint)


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
		_part_column.add_child(remove)

	for attachment in WorkbenchStation.get_options(weapon_data, _slot as AttachmentData.Slot):
		var is_mounted: bool = _stack.attachments.get(_slot, &"") == attachment.id
		var button := _make_button(attachment.display_name, is_mounted)
		button.pressed.connect(_on_attach.bind(attachment.id))
		_part_column.add_child(button)


## Werte der ausgewählten Waffe mit ihrer aktuellen Bestückung.
##
## Der Vergleich vorher/nachher kommt im nächsten Schritt. Schon diese Liste
## reicht, um zu sehen, dass ein Teil überhaupt etwas bewirkt — und genau das
## soll hier zuerst nachweisbar sein.
func _refresh_stats() -> void:
	var base := _current_weapon_data()
	if base == null:
		_stats_label.text = ""
		return

	var build := WeaponBuild.from_stack(_stack)
	var built := WeaponBuild.apply(base, build)

	var lines := [
		_stat_line("Rueckstoss hoch", base.recoil_vertical, built.recoil_vertical, false),
		_stat_line("Rueckstoss seitlich", base.recoil_horizontal, built.recoil_horizontal, false),
		_stat_line("Ergonomie", base.ergonomics, built.ergonomics, true),
		_stat_line("Streuung (MOA)", base.accuracy_moa, built.accuracy_moa, false),
		_stat_line("Sichtfeld beim Zielen", base.ads_fov, built.ads_fov, false),
		_stat_line("Lautstaerke", base.loudness_multiplier, built.loudness_multiplier, false),
	]
	_stats_label.text = "   ".join(lines)


## Zeigt den Wert, und bei Abweichung auch den ursprünglichen.
func _stat_line(label: String, before: float, after: float, higher_is_better: bool) -> String:
	if is_equal_approx(before, after):
		return "%s %.1f" % [label, after]
	# Pfeil und Vorzeichen: Ein Wert allein sagt nicht, ob das Teil hilft.
	var better := (after > before) == higher_is_better
	return "%s %.1f → %.1f %s" % [label, before, after, "+" if better else "-"]


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


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
		container.remove_child(child)


# -------------------------------------------------------------- Bedienung

func _on_weapon_chosen(stack: ItemStack) -> void:
	_stack = stack
	_slot = -1
	_message = ""
	refresh()


func _on_slot_chosen(slot: int) -> void:
	_slot = slot
	_message = ""
	refresh()


func _on_attach(attachment_id: StringName) -> void:
	if station == null or _stack == null or _slot < 0:
		return
	_message = station.request_attach(_stack.instance_id, _slot as AttachmentData.Slot, attachment_id)
	refresh()


func _on_detach() -> void:
	if station == null or _stack == null or _slot < 0:
		return
	_message = station.request_detach(_stack.instance_id, _slot as AttachmentData.Slot)
	refresh()
