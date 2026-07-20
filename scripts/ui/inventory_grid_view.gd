## Zeichnet ein Rasterinventar und macht es bedienbar (Tarkov-Stil).
##
## Zeichnet alles selbst über _draw(), statt pro Feld einen Knoten anzulegen.
## Ein 14x12-Lager wären sonst 168 Knoten, die bei jeder Änderung neu
## aufgebaut werden müssten.
##
## VERBINDUNG ZUM CONTAINER:
## Ist `container` gesetzt, werden noch nicht durchsuchte Gegenstände als
## schwarze Umrisse gezeichnet: Der Spieler sieht, WO etwas liegt und wie
## gross es ist, aber nicht, was es ist. Ein Klick darauf zieht es vor.
##
## ZIEHEN UND ABLEGEN läuft über das übergeordnete Fenster, damit man
## zwischen zwei Rastern ziehen kann. Diese Klasse meldet nur, was passiert.
class_name InventoryGridView
extends Control

signal item_pressed(stack: ItemStack, view: InventoryGridView)

## Klick auf einen noch nicht durchsuchten Umriss — der soll vorgezogen werden.
signal hidden_item_pressed(stack: ItemStack, view: InventoryGridView)
signal item_double_clicked(stack: ItemStack, view: InventoryGridView)
signal cell_released(grid_position: Vector2i, view: InventoryGridView)

## Der Zeiger steht auf einem erkannten Gegenstand (null = auf keinem).
signal item_hovered(stack: ItemStack, view: InventoryGridView)

## Rechtsklick auf einen erkannten Gegenstand — das Wirtfenster macht daraus
## ein Kontextmenü. `at_position` ist die Bildschirmposition des Zeigers.
##
## Nicht durchsuchte Umrisse loesen das NICHT aus: Ein Menue mit "Oeffnen"
## verriete, dass dort ein Behaelter liegt, und die Entscheidung "warte ich
## das ab?" waere entwertet.
signal item_right_clicked(stack: ItemStack, view: InventoryGridView, at_position: Vector2)

const CELL_SIZE := 52.0
const CELL_GAP := 2.0

# Farbgebung bewusst düster (Tarkov-Anmutung): fast schwarze Felder, gedämpfte
# Gegenstände, keine leuchtenden Flächen. Ein Inventar, in dem man im Raid
# unter Zeitdruck sucht, soll ruhig wirken und nicht blenden.
const COLOR_CELL := Color(0.075, 0.080, 0.088, 0.95)
const COLOR_CELL_BORDER := Color(0.145, 0.155, 0.170)
const COLOR_ITEM := Color(0.145, 0.152, 0.163)
const COLOR_ITEM_BORDER := Color(0.26, 0.28, 0.31)
const COLOR_HOVER_OK := Color(0.30, 0.62, 0.36, 0.38)
const COLOR_HOVER_BAD := Color(0.68, 0.24, 0.20, 0.38)
const COLOR_TEXT := Color(0.80, 0.82, 0.84)
const COLOR_COUNT := Color(0.86, 0.80, 0.56)

## Feiner Rahmen um den Gegenstand unter dem Zeiger.
const COLOR_HIGHLIGHT := Color(0.62, 0.66, 0.72)

## Wie stark die Seltenheitsfarbe den dunklen Grundton einfaerbt.
##
## Hoch: Der GANZE Gegenstand traegt seine Seltenheit, nicht nur ein
## Streifen am Rand. Man soll eine goldene Flaeche im Raster sehen, ohne
## hinzuschauen. Der dunkle Grundton bleibt beigemischt, damit das Inventar
## nicht anfaengt zu leuchten wie ein Beutefenster.
const RARITY_TINT := 0.78

## Noch nicht durchsuchte Gegenstände: dunkle Flächen mit Schraffur.
## Der Spieler sieht Groesse und Lage, aber nicht, was es ist.
const COLOR_HIDDEN := Color(0.055, 0.058, 0.065, 0.97)
const COLOR_HIDDEN_BORDER := Color(0.22, 0.23, 0.26)

## Die diagonalen Striche auf allem Unbesuchten. Sie sagen "hier war noch
## niemand" auf einen Blick — deutlicher als eine bloss dunklere Fläche,
## die man auch für ein leeres Feld halten könnte.
const COLOR_HATCH := Color(0.135, 0.142, 0.155)
const HATCH_SPACING := 7.0
const HATCH_WIDTH := 1.0

## Der Umriss, der gerade durchsucht wird.
const COLOR_HIDDEN_ACTIVE_BORDER := Color(0.85, 0.78, 0.45)

## Wie lange die Fundanimation läuft, je Seltenheitsstufe.
## Krimskrams blitzt nur kurz auf, damit man merkt DASS etwas erschien —
## ein guter Fund leuchtet lange genug, um den Blick hinzuziehen.
const REVEAL_DURATION := {
	ItemData.Rarity.COMMON: 0.30,
	ItemData.Rarity.UNCOMMON: 0.45,
	ItemData.Rarity.RARE: 0.70,
	ItemData.Rarity.EPIC: 1.00,
	ItemData.Rarity.LEGENDARY: 1.30,
}

## Wie weit ein Gegenstand unter dem Mauszeiger wächst.
##
## Bewusst spürbar, aber klein: Das ist die Rückmeldung "du bist drauf",
## bevor irgendetwas passiert. Beim Durchsuchen ist sie besonders wichtig —
## die schwarzen Umrisse sehen alle gleich aus, und ein Klick zieht einen
## davon vor. Ohne diese Anzeige klickt man ins Blaue.
const HOVER_GROW := 0.06

## Wie lange das Wachsen dauert. Kurz genug, um direkt zu wirken, lang
## genug, dass es nicht springt.
const HOVER_TIME := 0.10

## Wie weit der Gegenstand beim Auftauchen über seine Größe hinauswächst.
##
## Bewusst sehr klein: Ein deutliches Herausspringen sah aus, als loese sich
## der Gegenstand aus seinem Feld. Ein guter Fund soll AUFLEUCHTEN, nicht
## hüpfen — die Aufmerksamkeit kommt jetzt aus dem Schein, nicht aus Bewegung.
const POP_SCALE := 0.03

## Farbe je Kategorie. Wird derzeit NICHT gezeichnet: Die Flaeche zeigt die
## Seltenheit, und zwei Farbsysteme nebeneinander machen das Raster unlesbar.
## Bleibt erhalten, falls die Kategorie spaeter woanders auftauchen soll —
## etwa als Symbol oder beim Sortieren im Lager.
const CATEGORY_COLORS := {
	ItemData.Category.AMMO: Color(0.62, 0.52, 0.30),
	ItemData.Category.WEAPON: Color(0.44, 0.50, 0.62),
	ItemData.Category.ARMOR_PLATE: Color(0.52, 0.44, 0.62),
	ItemData.Category.BACKPACK: Color(0.40, 0.56, 0.46),
	ItemData.Category.MEDICAL: Color(0.66, 0.40, 0.42),
	ItemData.Category.FOOD: Color(0.58, 0.56, 0.34),
}

var grid: InventoryGrid = null

## Optional: Wenn gesetzt, werden nur aufgedeckte Gegenstände gezeichnet.
var container: LootContainer = null

var title: String = ""

## Wird vom Fenster gesetzt, während gezogen wird.
var drag_stack: ItemStack = null
var drag_source: InventoryGridView = null

## Wo der gezogene Gegenstand landen würde (-1 = nicht über diesem Raster).
##
## Das setzt das Fenster, nicht dieses Raster: Godot schickt nach dem Klick
## alle Mausereignisse weiter an das Control, auf dem gedrückt wurde. Ein
## Raster erfährt also gar nicht, dass der Zeiger über ihm schwebt, solange
## der Gegenstand aus dem anderen Raster kommt.
var preview_cell: Vector2i = Vector2i(-1, -1)

var _hover_cell: Vector2i = Vector2i(-1, -1)

## Aufgedeckter Gegenstand unter dem Zeiger. 0 = keiner.
## Steuert die Infoanzeige — verdeckte Gegenstände dürfen nichts verraten.
var _hover_stack_id: int = 0

## Gegenstand unter dem Zeiger, AUCH ein noch verdeckter. Steuert nur die
## Hervorhebung: Man soll sehen, was man anklicken würde, um es vorzuziehen.
var _hover_any_id: int = 0

## Wie weit die Hervorhebung gerade eingeblendet ist, 0 bis 1.
var _hover_amount: float = 0.0

## Laufende Fundanimationen: instance_id -> verstrichene Zeit.
var _reveal_animations: Dictionary = {}


func _ready() -> void:
	# Nur laufen lassen, wenn wirklich etwas animiert wird — sonst rechnet
	# jedes Raster im Spiel dauerhaft mit, auch das der Ausruestung.
	set_process(false)


## Startet die Fundanimation für einen gerade aufgedeckten Gegenstand.
func play_reveal(stack: ItemStack) -> void:
	if stack == null:
		return
	_reveal_animations[stack.instance_id] = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var busy := false

	if not _reveal_animations.is_empty():
		busy = true
		var finished: Array = []
		for id in _reveal_animations:
			var elapsed: float = _reveal_animations[id] + delta
			_reveal_animations[id] = elapsed
			if elapsed >= _duration_for(id):
				finished.append(id)
		for id in finished:
			_reveal_animations.erase(id)

	# Hervorhebung weich ein- und ausblenden.
	var target := 1.0 if _hover_any_id != 0 else 0.0
	if not is_equal_approx(_hover_amount, target):
		_hover_amount = move_toward(_hover_amount, target, delta / HOVER_TIME)
		busy = true

	if busy:
		queue_redraw()
	else:
		set_process(false)


## Wie lange die Animation dieses Gegenstands dauert.
func _duration_for(instance_id: int) -> float:
	if grid == null:
		return 0.0
	var stack := grid.get_stack(instance_id)
	if stack == null:
		return 0.0
	var data := stack.get_data()
	if data == null:
		return 0.3
	return REVEAL_DURATION.get(data.get_rarity(), 0.3)


## Fortschritt der Animation, 0 bis 1. Negativ = keine Animation.
func _reveal_progress(instance_id: int) -> float:
	if not _reveal_animations.has(instance_id):
		return -1.0
	var duration := _duration_for(instance_id)
	if duration <= 0.0:
		return -1.0
	return clampf(float(_reveal_animations[instance_id]) / duration, 0.0, 1.0)
var _last_click_time: float = 0.0
var _last_click_id: int = -1


func setup(p_grid: InventoryGrid, p_title: String, p_container: LootContainer = null) -> void:
	grid = p_grid
	title = p_title
	container = p_container
	if grid != null:
		custom_minimum_size = get_grid_pixel_size()
		if not grid.changed.is_connected(queue_redraw):
			grid.changed.connect(queue_redraw)
	queue_redraw()


func get_grid_pixel_size() -> Vector2:
	if grid == null:
		return Vector2.ZERO
	return Vector2(
		grid.width * (CELL_SIZE + CELL_GAP) + CELL_GAP,
		grid.height * (CELL_SIZE + CELL_GAP) + CELL_GAP
	)


## Rechnet Mausposition in Rasterkoordinaten um.
func position_to_cell(local: Vector2) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	var step := CELL_SIZE + CELL_GAP
	var cell := Vector2i(int((local.x - CELL_GAP) / step), int((local.y - CELL_GAP) / step))
	if not grid.is_inside(cell.x, cell.y):
		return Vector2i(-1, -1)
	return cell


func cell_to_position(cell: Vector2i) -> Vector2:
	var step := CELL_SIZE + CELL_GAP
	return Vector2(CELL_GAP + cell.x * step, CELL_GAP + cell.y * step)


## Alle Gegenstände, die als erkannt gezeichnet werden dürfen.
func _visible_stacks() -> Array[ItemStack]:
	if grid == null:
		return []
	if container != null:
		return container.get_revealed_stacks()
	return grid.get_all_stacks()


## Noch nicht durchsuchte Gegenstände — werden als schwarze Umrisse gezeigt.
func _hidden_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	if grid == null or container == null:
		return result
	for stack in grid.get_all_stacks():
		if not container.is_revealed(stack.instance_id):
			result.append(stack)
	return result


func _gui_input(event: InputEvent) -> void:
	if grid == null:
		return

	if event is InputEventMouseMotion:
		var cell := position_to_cell((event as InputEventMouseMotion).position)
		if cell != _hover_cell:
			_hover_cell = cell
			_update_hovered_stack(cell)
			queue_redraw()
		return

	if not (event is InputEventMouseButton):
		return

	var button := event as InputEventMouseButton

	if button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed:
			_emit_right_click(button)
		return

	if button.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := position_to_cell(button.position)

	if button.pressed:
		if cell.x < 0:
			return
		var stack := grid.get_stack_at(cell.x, cell.y)
		if stack == null:
			return
		# Nicht durchsuchte Gegenstände lassen sich nicht anfassen — aber ein
		# Klick zieht sie vor. Man sieht den grossen Umriss und will wissen,
		# was es ist, ohne erst die Patronenschachteln abzuwarten.
		if container != null and not container.is_revealed(stack.instance_id):
			hidden_item_pressed.emit(stack, self)
			return

		# Doppelklick: schnell hinüberschicken, ohne zu ziehen.
		var now := Time.get_ticks_msec() / 1000.0
		if stack.instance_id == _last_click_id and now - _last_click_time < 0.35:
			_last_click_id = -1
			item_double_clicked.emit(stack, self)
			return

		_last_click_id = stack.instance_id
		_last_click_time = now
		item_pressed.emit(stack, self)
	else:
		cell_released.emit(cell, self)


## Rechtsklick auf ein Feld. Auf leeren Feldern und auf noch nicht
## durchsuchten Umrissen passiert bewusst nichts.
func _emit_right_click(button: InputEventMouseButton) -> void:
	var cell := position_to_cell(button.position)
	if cell.x < 0:
		return
	var stack := grid.get_stack_at(cell.x, cell.y)
	if stack == null:
		return
	if container != null and not container.is_revealed(stack.instance_id):
		return
	item_right_clicked.emit(stack, self, button.global_position)


## Meldet, welcher Gegenstand unter dem Zeiger liegt. Nicht durchsuchte
## zaehlen NICHT — ihre Werte darf der Spieler noch nicht sehen.
func _update_hovered_stack(cell: Vector2i) -> void:
	var under: ItemStack = null
	if cell.x >= 0:
		under = grid.get_stack_at(cell.x, cell.y)

	# Hervorhebung gilt auch fuer verdeckte Umrisse — man soll sehen, was
	# man anklicken wuerde. Ein Gegenstand, den man gerade zieht, haengt am
	# Zeiger und soll sich im Raster nicht mitbewegen.
	var highlight_id := 0
	if under != null and under != drag_stack:
		highlight_id = under.instance_id
	if highlight_id != _hover_any_id:
		_hover_any_id = highlight_id
		set_process(true)

	# Die Infoanzeige dagegen nur fuer Aufgedecktes: Werte eines noch nicht
	# gefundenen Gegenstands duerfen nicht sichtbar werden.
	var found: ItemStack = null
	if under != null and (container == null or container.is_revealed(under.instance_id)):
		found = under

	var new_id := found.instance_id if found != null else 0
	if new_id == _hover_stack_id:
		return
	_hover_stack_id = new_id
	item_hovered.emit(found, self)


## Wie stark dieser Gegenstand gerade hervorgehoben ist, 0 bis 1.
func _hover_factor(instance_id: int) -> float:
	return _hover_amount if instance_id == _hover_any_id else 0.0


## Der Zeiger hat das Raster verlassen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_cell = Vector2i(-1, -1)
		if _hover_any_id != 0:
			_hover_any_id = 0
			set_process(true)
		if _hover_stack_id != 0:
			_hover_stack_id = 0
			item_hovered.emit(null, self)
		queue_redraw()


func _draw() -> void:
	if grid == null:
		return

	_draw_cells()
	_draw_drag_preview()

	# Der hervorgehobene Gegenstand kommt zuletzt: Er waechst ueber sein Feld
	# hinaus und wuerde sonst von den Nachbarn ueberzeichnet.
	var highlighted: ItemStack = null
	var highlighted_hidden := false

	for stack in _hidden_stacks():
		if stack.instance_id == _hover_any_id:
			highlighted = stack
			highlighted_hidden = true
			continue
		_draw_hidden_stack(stack)

	for stack in _visible_stacks():
		if stack.instance_id == _hover_any_id:
			highlighted = stack
			continue
		_draw_stack(stack)

	if highlighted != null:
		if highlighted_hidden:
			_draw_hidden_stack(highlighted)
		else:
			_draw_stack(highlighted)


## Ein noch nicht durchsuchter Gegenstand: schwarze Flaeche in seiner echten
## Groesse. Die Groesse zu zeigen ist Absicht — sie verraet, wie lange das
## Durchsuchen dauert, aber nicht, ob es sich lohnt.
func _draw_hidden_stack(stack: ItemStack) -> void:
	var pos_cell := grid.get_position(stack.instance_id)
	if pos_cell.x < 0:
		return

	var size := stack.get_size()
	var rect := Rect2(cell_to_position(pos_cell), Vector2(
		size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP
	))

	# Unter dem Zeiger wachsen: Alle Umrisse sehen gleich aus, und ein Klick
	# zieht einen davon vor — ohne Rueckmeldung klickt man ins Blaue.
	var hover := _hover_factor(stack.instance_id)
	if hover > 0.0:
		rect = rect.grow(rect.size.x * HOVER_GROW * hover * 0.5)

	draw_rect(rect, COLOR_HIDDEN)
	_draw_hatch(rect, COLOR_HATCH)
	_draw_magnifier(rect, COLOR_HATCH.lerp(COLOR_TEXT, 0.35 + 0.5 * hover))

	var is_current := container != null and container.get_current_target() == stack
	if is_current and container.is_searching():
		draw_rect(rect, COLOR_HIDDEN_ACTIVE_BORDER, false, 2.0)
	elif hover > 0.0:
		draw_rect(rect, COLOR_HIDDEN_BORDER.lerp(COLOR_HIGHLIGHT, hover), false, 1.0 + hover)
	else:
		draw_rect(rect, COLOR_HIDDEN_BORDER, false, 1.0)


## Diagonale Striche innerhalb eines Rechtecks.
##
## Godot kennt keine Schraffur und `draw_line` beschneidet nicht. Jede Linie
## wird deshalb selbst am Rechteck abgeschnitten: Die Gerade läuft in
## Richtung (1,1), und aus den Grenzen in x und y ergibt sich der Abschnitt,
## der wirklich innen liegt.
func _draw_hatch(rect: Rect2, color: Color, spacing: float = HATCH_SPACING) -> void:
	var offset := -rect.size.y
	while offset < rect.size.x:
		var start := Vector2(rect.position.x + offset, rect.position.y)

		# Gültiger Bereich entlang der Geraden, getrennt für x und y.
		var t_min := maxf(rect.position.x - start.x, 0.0)
		var t_max := minf(rect.position.x + rect.size.x - start.x, rect.size.y)

		if t_max > t_min:
			draw_line(
				start + Vector2(t_min, t_min),
				start + Vector2(t_max, t_max),
				color, HATCH_WIDTH
			)
		offset += spacing


## Eine kleine Lupe in der Mitte — dasselbe Zeichen wie auf der Kiste selbst.
## Nur wenn genug Platz ist: Auf einem einzelnen Feld wäre sie nur ein Fleck.
func _draw_magnifier(rect: Rect2, color: Color) -> void:
	var radius := minf(rect.size.x, rect.size.y) * 0.16
	if radius < 5.0:
		return

	var center := rect.position + rect.size * 0.5 - Vector2(radius * 0.3, radius * 0.3)
	draw_arc(center, radius, 0.0, TAU, 20, color, 1.6)

	var diagonal := Vector2(0.7071, 0.7071)
	draw_line(center + diagonal * radius, center + diagonal * (radius * 2.1), color, 1.6)


func _draw_cells() -> void:
	# Solange die Kiste nicht fertig durchsucht ist, liegt ueber dem ganzen
	# Raster eine Schraffur: "Hier war noch niemand." Erst wenn alles
	# gefunden ist, wird daraus ein normales Inventar.
	var unsearched := container != null and not container.is_fully_searched

	for y in range(grid.height):
		for x in range(grid.width):
			var pos := cell_to_position(Vector2i(x, y))
			var rect := Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect, COLOR_CELL)
			if unsearched:
				_draw_hatch(rect, COLOR_HATCH.darkened(0.35), HATCH_SPACING * 1.6)
			draw_rect(rect, COLOR_CELL_BORDER, false, 1.0)


## Zeigt beim Ziehen, ob der Gegenstand hier abgelegt werden kann.
func _draw_drag_preview() -> void:
	if drag_stack == null or preview_cell.x < 0 or preview_cell.y < 0:
		return

	var size := drag_stack.get_size()
	var pos := cell_to_position(preview_cell)
	var rect := Rect2(pos, Vector2(
		size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP
	))

	# Beim Verschieben innerhalb desselben Rasters darf sich der Gegenstand
	# mit sich selbst überlappen.
	var ignore := drag_stack.instance_id if drag_source == self else 0
	var fits := grid.can_place_or_merge(drag_stack, preview_cell.x, preview_cell.y, ignore)
	draw_rect(rect, COLOR_HOVER_OK if fits else COLOR_HOVER_BAD)


## Das kurze Aufleuchten nach dem Aufdecken.
##
## Bewusst ohne Shader: Ein echter Leuchteffekt braucht Nachbearbeitung im
## ganzen Bild, und dafuer ist das hier zu klein. Stattdessen eine helle
## Flaeche plus mehrere Rahmen nach aussen — das liest sich aus zwei Metern
## Entfernung genauso wie ein Schein.
##
## Gute Funde pulsieren zusaetzlich, damit sie im Augenwinkel auffallen,
## auch wenn man gerade woanders hinsieht.
func _draw_reveal_glow(rect: Rect2, color: Color, progress: float, strong: bool) -> void:
	# Schnell hell, langsam aus: So wirkt es wie ein Aufblitzen und nicht
	# wie ein Ein- und Ausblenden.
	var fade := pow(1.0 - progress, 2.2)

	if strong:
		# Zwei Pulse ueber die Dauer, die mit dem Ausklingen schwaecher werden.
		fade *= 0.65 + 0.35 * absf(sin(progress * PI * 2.0))

	var fill := color
	fill.a = fade * (0.55 if strong else 0.32)
	draw_rect(rect, fill)

	# Rahmen nach aussen, jeder schwaecher — das ergibt den Schein.
	var rings := 4 if strong else 2
	for i in range(rings):
		var ring := color
		ring.a = fade * (0.5 if strong else 0.3) * (1.0 - float(i) / float(rings))
		draw_rect(rect.grow(float(i) * 2.0 + 1.0), ring, false, 2.0)


func _draw_stack(stack: ItemStack) -> void:
	# Der gezogene Gegenstand haengt am Mauszeiger — gezeichnet wird er dort
	# vom DragGhost des Fensters, nicht hier.
	if stack == drag_stack:
		return

	var pos_cell := grid.get_position(stack.instance_id)
	if pos_cell.x < 0:
		return

	var data := stack.get_data()
	var size := stack.get_size()
	var pos := cell_to_position(pos_cell)
	var rect := Rect2(pos, Vector2(
		size.x * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		size.y * (CELL_SIZE + CELL_GAP) - CELL_GAP
	))

	if data == null:
		draw_rect(rect, COLOR_ITEM)
		draw_rect(rect, COLOR_ITEM_BORDER, false, 1.5)
		return

	var rarity := data.get_rarity()
	var rarity_color := ItemTooltip.get_rarity_color(rarity)
	var progress := _reveal_progress(stack.instance_id)
	var hover := _hover_factor(stack.instance_id)

	if hover > 0.0:
		rect = rect.grow(rect.size.x * HOVER_GROW * hover * 0.5)

	# Aufploppen: kurz ueber die eigene Groesse hinaus und zurueck.
	# Nur bei guten Funden — bei jeder Patrone wuerde das Raster zappeln.
	if progress >= 0.0 and data.is_high_value():
		# sin(pi * x) waechst und faellt in einer Bewegung, ohne Sprung
		# am Anfang oder Ende.
		var pop := sin(PI * progress) * POP_SCALE
		rect = rect.grow(rect.size.x * pop * 0.5)

	# Die ganze Flaeche traegt die Seltenheit.
	var fill := COLOR_ITEM.lerp(rarity_color, RARITY_TINT)
	draw_rect(rect, fill)

	if progress >= 0.0:
		_draw_reveal_glow(rect, rarity_color, progress, data.is_high_value())

	draw_rect(rect, COLOR_ITEM_BORDER.lerp(COLOR_HIGHLIGHT, hover), false, 1.0 + hover)

	var font := ThemeDB.fallback_font
	var font_size := 12

	# Auf goldenem oder rotem Untergrund ist heller Text nicht mehr lesbar.
	# Die Schrift richtet sich deshalb nach der Helligkeit der Flaeche.
	var text_color := _readable_on(fill)

	# Name umbrechen, damit er in schmale Gegenstände passt.
	var text := data.display_name
	draw_string(font, rect.position + Vector2(4, 14), text,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, font_size, text_color)

	# Stückzahl unten rechts, wie in Tarkov.
	if stack.quantity > 1:
		var count := "x%d" % stack.quantity
		var width := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, rect.position + Vector2(rect.size.x - width - 4, rect.size.y - 5),
			count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


## Schriftfarbe, die auf diesem Untergrund lesbar bleibt.
##
## Die Gewichtung folgt der wahrgenommenen Helligkeit: Gruen wirkt viel
## heller als Blau, obwohl der Zahlenwert derselbe sein kann. Ohne diese
## Gewichtung waere Text auf Gold schlecht lesbar und auf Blau unnoetig dunkel.
static func _readable_on(background: Color) -> Color:
	var luminance := 0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b
	return Color(0.06, 0.06, 0.07) if luminance > 0.45 else COLOR_TEXT
