## Ein rasterbasiertes Inventar im Stil von Escape from Tarkov.
##
## Gegenstände belegen mehrere Felder (ein Sturmgewehr 5x2, eine Patrone 1x1),
## lassen sich drehen und Container haben ihr eigenes Innenraster.
##
## WICHTIG — server-autoritativ:
## Diese Klasse enthält NUR Logik und Daten, keine Darstellung. Sie läuft auf
## dem Server. Der Client zeigt lediglich an, was ihm der Server mitteilt, und
## bittet um Änderungen. Ein Client, der `place()` selbst aufruft, verändert
## nur seine eigene Anzeige — der Server übernimmt das nicht.
##
## Interne Darstellung: ein flaches Array der Größe width*height, das je Feld
## die instance_id des dort liegenden Gegenstands enthält (0 = frei).
## Ein 5x2-Gewehr belegt also 10 Felder mit derselben ID.
class_name InventoryGrid
extends RefCounted

## Wird ausgelöst, wenn sich der Inhalt ändert — die UI hängt sich hier ein.
signal changed()

const EMPTY := 0

var width: int = 10
var height: int = 6

## Feldbelegung, flach gespeichert. Index = y * width + x.
var _cells: PackedInt32Array = PackedInt32Array()

## instance_id -> ItemStack
var _stacks: Dictionary[int, ItemStack] = {}

## instance_id -> Vector2i (linke obere Ecke)
var _positions: Dictionary[int, Vector2i] = {}


func _init(p_width: int = 10, p_height: int = 6) -> void:
	resize(p_width, p_height)


## Ändert die Rastergröße und leert den Inhalt.
## Wird beim Bunker-Ausbau gebraucht: ein größeres Lager = größeres Raster.
func resize(p_width: int, p_height: int) -> void:
	width = maxi(1, p_width)
	height = maxi(1, p_height)
	_cells = PackedInt32Array()
	_cells.resize(width * height)
	_cells.fill(EMPTY)
	_stacks.clear()
	_positions.clear()


func _index(x: int, y: int) -> int:
	return y * width + x


func is_inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


## Was liegt auf diesem Feld? 0 = nichts.
func get_cell(x: int, y: int) -> int:
	if not is_inside(x, y):
		return EMPTY
	return _cells[_index(x, y)]


# ---------------------------------------------------------------------------
# Platzieren
# ---------------------------------------------------------------------------

## Passt der Gegenstand an diese Stelle?
## ignore_id erlaubt es, ein Item beim Verschieben mit sich selbst zu
## überlappen — sonst könnte man ein Gewehr nie um ein Feld verschieben.
func can_place(stack: ItemStack, x: int, y: int, ignore_id: int = 0) -> bool:
	if stack == null:
		return false
	var size := stack.get_size()
	if not is_inside(x, y) or not is_inside(x + size.x - 1, y + size.y - 1):
		return false

	for oy in range(size.y):
		for ox in range(size.x):
			var occupant := _cells[_index(x + ox, y + oy)]
			if occupant != EMPTY and occupant != ignore_id:
				return false
	return true


## Legt den Gegenstand ab. Gibt false zurück, wenn kein Platz ist.
func place(stack: ItemStack, x: int, y: int) -> bool:
	if not can_place(stack, x, y):
		return false
	_write_cells(stack, x, y, stack.instance_id)
	_stacks[stack.instance_id] = stack
	_positions[stack.instance_id] = Vector2i(x, y)
	changed.emit()
	return true


func _write_cells(stack: ItemStack, x: int, y: int, value: int) -> void:
	var size := stack.get_size()
	for oy in range(size.y):
		for ox in range(size.x):
			_cells[_index(x + ox, y + oy)] = value


## Sucht den ersten freien Platz von links oben nach rechts unten.
## Probiert bei Bedarf auch die gedrehte Lage — das erspart dem Spieler
## das manuelle Puzzeln beim automatischen Aufsammeln.
## Gibt Vector2i(-1, -1) zurück, wenn nichts passt.
func find_free_position(stack: ItemStack, allow_rotation: bool = true) -> Vector2i:
	for y in range(height):
		for x in range(width):
			if can_place(stack, x, y):
				return Vector2i(x, y)

	var data := stack.get_data()
	if allow_rotation and data != null and data.can_rotate and data.grid_width != data.grid_height:
		var was_rotated := stack.rotated
		stack.rotated = not was_rotated
		for y in range(height):
			for x in range(width):
				if can_place(stack, x, y):
					return Vector2i(x, y)
		stack.rotated = was_rotated

	return Vector2i(-1, -1)


## Legt den Gegenstand irgendwo ab, wo Platz ist.
## Stapelt vorher automatisch auf passende vorhandene Stapel —
## sonst hätte man 30 einzelne Felder mit je einer Patrone.
func add_item(stack: ItemStack) -> bool:
	if stack == null:
		return false

	for existing in _stacks.values():
		if existing.can_merge_with(stack):
			existing.merge_from(stack)
			if stack.quantity <= 0:
				changed.emit()
				return true

	var pos := find_free_position(stack)
	if pos.x < 0:
		return false
	return place(stack, pos.x, pos.y)


# ---------------------------------------------------------------------------
# Entfernen und Verschieben
# ---------------------------------------------------------------------------

## Nimmt den Gegenstand heraus und gibt ihn zurück (null wenn nicht vorhanden).
func remove_item(instance_id: int) -> ItemStack:
	if not _stacks.has(instance_id):
		return null
	var stack: ItemStack = _stacks[instance_id]
	var pos: Vector2i = _positions[instance_id]
	_write_cells(stack, pos.x, pos.y, EMPTY)
	_stacks.erase(instance_id)
	_positions.erase(instance_id)
	changed.emit()
	return stack


## Verschiebt innerhalb desselben Rasters. Bei Misserfolg bleibt alles, wie es war.
func move_item(instance_id: int, x: int, y: int) -> bool:
	if not _stacks.has(instance_id):
		return false
	var stack: ItemStack = _stacks[instance_id]
	if not can_place(stack, x, y, instance_id):
		return false

	var old_pos: Vector2i = _positions[instance_id]
	_write_cells(stack, old_pos.x, old_pos.y, EMPTY)
	_write_cells(stack, x, y, instance_id)
	_positions[instance_id] = Vector2i(x, y)
	changed.emit()
	return true


## Dreht einen Gegenstand um 90°, sofern er an seiner Position gedreht passt.
func rotate_item(instance_id: int) -> bool:
	if not _stacks.has(instance_id):
		return false
	var stack: ItemStack = _stacks[instance_id]
	var data := stack.get_data()
	if data == null or not data.can_rotate:
		return false

	var pos: Vector2i = _positions[instance_id]
	# Erst die Felder freigeben, sonst blockiert sich das Item selbst.
	_write_cells(stack, pos.x, pos.y, EMPTY)
	stack.rotated = not stack.rotated

	if can_place(stack, pos.x, pos.y):
		_write_cells(stack, pos.x, pos.y, instance_id)
		changed.emit()
		return true

	# Passt nicht — alles exakt zurückdrehen.
	stack.rotated = not stack.rotated
	_write_cells(stack, pos.x, pos.y, instance_id)
	return false


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

func get_stack(instance_id: int) -> ItemStack:
	return _stacks.get(instance_id)


func get_position(instance_id: int) -> Vector2i:
	return _positions.get(instance_id, Vector2i(-1, -1))


func get_stack_at(x: int, y: int) -> ItemStack:
	var id := get_cell(x, y)
	if id == EMPTY:
		return null
	return _stacks.get(id)


func get_all_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for stack in _stacks.values():
		result.append(stack)
	return result


func get_item_count() -> int:
	return _stacks.size()


## Gesamtgewicht inklusive verschachtelter Container.
## Davon hängen Ausdauerverbrauch und Bewegungstempo ab.
func get_total_weight() -> float:
	var total := 0.0
	for stack in _stacks.values():
		total += stack.get_total_weight()
	return total


func get_free_cell_count() -> int:
	var free := 0
	for cell in _cells:
		if cell == EMPTY:
			free += 1
	return free


## Zählt Stückzahl einer Item-Sorte über alle Stapel — für Händleraufträge
## ("bringe 5 Verbandspäckchen") und Bunker-Baukosten.
func count_items(item_id: StringName, include_nested: bool = true) -> int:
	var total := 0
	for stack in _stacks.values():
		if stack.item_id == item_id:
			total += stack.quantity
		if include_nested and stack.container != null:
			total += stack.container.count_items(item_id, true)
	return total


# ---------------------------------------------------------------------------
# Speichern und Netzwerk
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var items: Array[Dictionary] = []
	for id in _stacks.keys():
		var entry := (_stacks[id] as ItemStack).to_dict()
		var pos: Vector2i = _positions[id]
		entry["x"] = pos.x
		entry["y"] = pos.y
		items.append(entry)
	return {"width": width, "height": height, "items": items}


static func from_dict(d: Dictionary) -> InventoryGrid:
	var grid := InventoryGrid.new(int(d.get("width", 10)), int(d.get("height", 6)))
	for entry in d.get("items", []):
		var stack := ItemStack.from_dict(entry)
		grid.place(stack, int(entry.get("x", 0)), int(entry.get("y", 0)))
	return grid


## Textdarstellung des Rasters — nur zum Debuggen im Headless-Test,
## damit man ohne UI sieht, was wo liegt.
func debug_render() -> String:
	var out := ""
	for y in range(height):
		for x in range(width):
			var id := get_cell(x, y)
			out += "." if id == EMPTY else str(id % 10)
		out += "\n"
	return out
