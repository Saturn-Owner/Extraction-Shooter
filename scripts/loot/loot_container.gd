## Ein durchsuchbarer Behälter: Kiste, Spind, Rucksack einer Leiche.
##
## ---------------------------------------------------------------------------
## DURCHSUCHEN GESCHIEHT PRO GEGENSTAND (wie in Arena Breakout)
##
## Man öffnet die Kiste und sieht sofort, WO etwas liegt: schwarze Umrisse
## in der richtigen Größe. Was es ist, zeigt sich erst nach und nach, jeder
## Gegenstand mit eigener Dauer:
##
##   9mm-Patrone      ~0.7 s
##   M995             ~1.3 s
##   Schutzplatte     ~3.3 s
##   Sturmgewehr      ~4.4 s
##
## Durchsucht wird in Lesereihenfolge: links nach rechts, dann zeilenweise
## nach unten. Wer nicht warten will, klickt einen anderen Umriss an — der
## wird dann vorgezogen, danach geht es normal weiter.
##
## Das erzeugt die eigentliche Entscheidung: Man sieht einen grossen Umriss
## und muss abwaegen, ob sich das Bleiben lohnt. Eine Militärkiste mit einem
## Gewehr darin hält einen fast fünf Sekunden fest — genau dann, wenn man
## am verwundbarsten ist. Die Groesse verraet dabei, wie lange es dauert,
## aber nicht, ob es sich lohnt.
##
## Der Inhalt wird beim ersten Öffnen gewürfelt, nicht beim Laden des Levels:
## Wer die Kiste nie öffnet, kostet keine Rechenzeit. Im Multiplayer würfelt
## später der Server erst dann, wenn jemand hinschaut — vorher gibt es
## nichts, was ein Client auslesen könnte.
class_name LootContainer
extends StaticBody3D

signal opened()
signal item_revealed(stack: ItemStack, remaining: int)
signal fully_searched()
signal search_paused()
signal contents_changed()

## Welche Loot-Tabelle gezogen wird.
@export var loot_table: LootTableData

## Grösse des Innenrasters.
@export var grid_width: int = 6
@export var grid_height: int = 4

## Beschriftung für die Anzeige.
@export var display_name: String = "Kiste"

## Zuschlag auf jede Durchsuchzeit. Eine verschlossene Militärkiste darf
## zäher sein als eine offene Schublade.
@export_range(0.5, 3.0) var search_time_multiplier: float = 1.0

var contents: InventoryGrid
var is_open: bool = false
var is_fully_searched: bool = false

## instance_id -> true, sobald der Gegenstand sichtbar ist.
var _revealed: Dictionary = {}

## Reihenfolge, in der aufgedeckt wird: Lesereihenfolge, vorne der aktuelle.
var _reveal_queue: Array[ItemStack] = []

## instance_id -> bereits verstrichene Suchzeit. Damit kostet weder eine
## Pause noch ein Wechsel den bisherigen Fortschritt.
var _elapsed: Dictionary = {}

var _reveal_timer: float = 0.0
var _current_reveal_time: float = 0.0
var _is_searching: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	contents = InventoryGrid.new(grid_width, grid_height)
	contents.changed.connect(func(): contents_changed.emit())
	_rng.randomize()
	add_to_group("loot_container")


## Für reproduzierbare Tests.
func set_seed(value: int) -> void:
	_rng.seed = value


## Öffnet die Kiste. Beim ersten Mal wird der Inhalt gewürfelt.
## Das Raster ist sofort sichtbar, die Gegenstände tauchen nach und nach auf.
func open() -> void:
	if not is_open:
		is_open = true
		_generate_contents()
		_build_reveal_queue()
		opened.emit()

	_is_searching = not _reveal_queue.is_empty()
	if _is_searching and _current_reveal_time <= 0.0:
		_start_next_reveal()


## Der Spieler geht weg oder schliesst das Fenster.
## Der Fortschritt am aktuellen Gegenstand bleibt erhalten — man muss nicht
## von vorn anfangen, nur weil man kurz in Deckung gegangen ist.
func pause_search() -> void:
	if not _is_searching:
		return
	_remember_progress()
	_is_searching = false
	search_paused.emit()


func _process(delta: float) -> void:
	if not _is_searching or _reveal_queue.is_empty():
		return

	_reveal_timer += delta
	if _reveal_timer < _current_reveal_time:
		return

	var stack: ItemStack = _reveal_queue.pop_front()
	_revealed[stack.instance_id] = true
	_elapsed.erase(stack.instance_id)
	item_revealed.emit(stack, _reveal_queue.size())

	if _reveal_queue.is_empty():
		_is_searching = false
		is_fully_searched = true
		_current_reveal_time = 0.0
		fully_searched.emit()
	else:
		_start_next_reveal()


func _start_next_reveal() -> void:
	if _reveal_queue.is_empty():
		return
	var next: ItemStack = _reveal_queue[0]
	var data := next.get_data()
	_current_reveal_time = (data.get_search_time() if data != null else 1.0) * search_time_multiplier
	# Dort weitermachen, wo dieser Gegenstand zuletzt stand.
	_reveal_timer = float(_elapsed.get(next.instance_id, 0.0))


## Fortschritt am aktuell gesuchten Gegenstand, 0 bis 1.
func get_current_progress() -> float:
	if not _is_searching or _current_reveal_time <= 0.0:
		return 0.0
	return clampf(_reveal_timer / _current_reveal_time, 0.0, 1.0)


## Was gerade gesucht wird — für die Fortschrittsanzeige.
## Bewusst OHNE den Namen: Man soll nicht vorab wissen, was kommt, sonst
## wäre die Entscheidung "warte ich das ab?" trivial.
func get_remaining_count() -> int:
	return _reveal_queue.size()


func is_searching() -> bool:
	return _is_searching


## Welcher Gegenstand gerade durchsucht wird — fuer die Hervorhebung im
## Raster. Der Spieler soll sehen, welcher schwarze Umriss an der Reihe ist.
func get_current_target() -> ItemStack:
	return _reveal_queue[0] if not _reveal_queue.is_empty() else null


## Ob dieser Gegenstand schon sichtbar ist.
func is_revealed(instance_id: int) -> bool:
	return _revealed.get(instance_id, false)


## Nur die bereits aufgedeckten Gegenstände. Alles andere existiert für den
## Spieler noch nicht.
func get_revealed_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for stack in contents.get_all_stacks():
		if is_revealed(stack.instance_id):
			result.append(stack)
	return result


func _generate_contents() -> void:
	if loot_table == null:
		return

	for drop in loot_table.roll(_rng):
		var stack := ItemStack.create(drop.id, drop.quantity)
		if stack.get_data() == null:
			push_error("[LootContainer] Unbekanntes Item in Loot-Tabelle: %s" % drop.id)
			continue
		if not contents.add_item(stack):
			# Container voll — der Rest fällt weg. Kein Fehler, sondern eine
			# Folge der Tabellengroesse. Sichtbar machen fuers Balancing.
			push_warning("[LootContainer] %s: kein Platz mehr fuer %s" % [display_name, drop.id])
			break


## In Lesereihenfolge durchsuchen: links nach rechts, dann zeilenweise nach
## unten. Das ist vorhersehbar — der Spieler sieht die schwarzen Umrisse und
## weiss, wann welcher an der Reihe ist. Genau das macht die Entscheidung
## moeglich, stattdessen gezielt auf einen anderen zu klicken.
func _build_reveal_queue() -> void:
	_reveal_queue.clear()
	for stack in contents.get_all_stacks():
		_reveal_queue.append(stack)
	_sort_reading_order(_reveal_queue)


func _sort_reading_order(list: Array[ItemStack]) -> void:
	list.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		var pa := contents.get_position(a.instance_id)
		var pb := contents.get_position(b.instance_id)
		if pa.y != pb.y:
			return pa.y < pb.y
		return pa.x < pb.x
	)


## Zieht einen Gegenstand vor: Er wird als naechstes durchsucht, danach geht
## es in der normalen Reihenfolge weiter.
##
## Der Sinn: Man sieht einen grossen Umriss und will wissen, ob sich das
## Bleiben lohnt — ohne vorher drei Patronenschachteln abzuwarten.
##
## Der Fortschritt am bisherigen Gegenstand bleibt erhalten. Neugier soll
## nichts kosten; wer zurueckwechselt, faengt nicht wieder bei null an.
func prioritize(instance_id: int) -> bool:
	if is_revealed(instance_id):
		return false

	var index := -1
	for i in _reveal_queue.size():
		if _reveal_queue[i].instance_id == instance_id:
			index = i
			break

	if index <= 0:
		# Nicht gefunden oder ohnehin schon an der Reihe.
		return false

	_remember_progress()
	var stack: ItemStack = _reveal_queue[index]
	_reveal_queue.remove_at(index)
	_reveal_queue.insert(0, stack)
	_start_next_reveal()
	return true


## Merkt sich, wie weit der aktuelle Gegenstand schon durchsucht ist.
func _remember_progress() -> void:
	if _reveal_queue.is_empty():
		return
	_elapsed[_reveal_queue[0].instance_id] = _reveal_timer


## Nimmt einen Gegenstand heraus und legt ihn ins Zielinventar.
## Nicht aufgedeckte Gegenstände lassen sich nicht nehmen.
##
## Passt er im Ziel nicht, bleibt er liegen — nichts geht verloren.
func take_item(instance_id: int, into: InventoryGrid) -> bool:
	if not is_revealed(instance_id):
		return false

	var stack := contents.get_stack(instance_id)
	if stack == null or into == null:
		return false

	# Erst prüfen, ob im Ziel Platz ist. Erst dann entnehmen — andersherum
	# könnte der Gegenstand zwischen beiden Rastern verschwinden.
	var free_spot := into.find_free_position(stack)
	var can_stack := false
	for existing in into.get_all_stacks():
		if existing.can_merge_with(stack):
			can_stack = true
			break

	if free_spot.x < 0 and not can_stack:
		return false

	contents.remove_item(instance_id)
	if not into.add_item(stack):
		contents.add_item(stack)
		return false

	_revealed.erase(instance_id)
	return true


## Legt einen Gegenstand in die Kiste — für Ablegen per Ziehen.
func put_item(stack: ItemStack, x: int, y: int) -> bool:
	if stack == null:
		return false
	if not contents.place(stack, x, y):
		return false
	mark_revealed(stack)
	return true


## Markiert einen Gegenstand als sichtbar.
## Nötig, wenn der Spieler etwas in die Kiste legt: Was er selbst
## hineingelegt hat, muss er auch sehen können.
func mark_revealed(stack: ItemStack) -> void:
	if stack != null:
		_revealed[stack.instance_id] = true


## Nimmt alles Aufgedeckte mit, was passt.
## Gibt zurück, wie viele Gegenstände liegen blieben.
func take_all(into: InventoryGrid) -> int:
	if into == null:
		return contents.get_item_count()

	for stack in get_revealed_stacks():
		take_item(stack.instance_id, into)
	return contents.get_item_count()


func is_empty() -> bool:
	return contents.get_item_count() == 0


## Für einen neuen Raid zurücksetzen.
func reset() -> void:
	is_open = false
	is_fully_searched = false
	_is_searching = false
	_revealed.clear()
	_reveal_queue.clear()
	_elapsed.clear()
	_reveal_timer = 0.0
	_current_reveal_time = 0.0
	contents.resize(grid_width, grid_height)
