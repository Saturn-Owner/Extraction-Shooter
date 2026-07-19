## Ein durchsuchbarer Behälter: Kiste, Spind, Rucksack einer Leiche.
##
## Der Inhalt wird beim ersten Öffnen gewürfelt, nicht beim Laden des Levels.
## Zwei Gründe:
##   - Wer den Container nie öffnet, kostet keine Rechenzeit
##   - Im Multiplayer würfelt später der Server erst dann, wenn wirklich
##     jemand hinschaut — vorher gibt es nichts, was ein Client auslesen
##     könnte, um sich die besten Kisten anzeigen zu lassen
##
## Das Durchsuchen dauert. Das ist Absicht: Ein Container, der sich sofort
## öffnet, macht das Looten risikofrei. Die Sekunden, in denen man
## bewegungsunfähig davorsteht, sind der Preis für die Beute.
class_name LootContainer
extends StaticBody3D

signal search_started(duration: float)
signal search_finished()
signal search_cancelled()
signal contents_changed()

## Wie lange das Durchsuchen dauert.
@export var search_time: float = 2.5

## Welche Loot-Tabelle gezogen wird.
@export var loot_table: LootTableData

## Grösse des Innenrasters.
@export var grid_width: int = 6
@export var grid_height: int = 4

## Beschriftung für die Anzeige.
@export var display_name: String = "Kiste"

var contents: InventoryGrid
var is_searched: bool = false
var is_being_searched: bool = false

var _search_progress: float = 0.0
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


## Beginnt das Durchsuchen. Läuft über mehrere Frames.
func begin_search() -> bool:
	if is_being_searched:
		return false
	if is_searched:
		# Schon durchsucht: sofort offen, kein zweites Warten.
		return true

	is_being_searched = true
	_search_progress = 0.0
	search_started.emit(search_time)
	return true


## Bricht das Durchsuchen ab — etwa wenn der Spieler weggeht oder schiesst.
func cancel_search() -> void:
	if not is_being_searched:
		return
	is_being_searched = false
	_search_progress = 0.0
	search_cancelled.emit()


func _process(delta: float) -> void:
	if not is_being_searched:
		return

	_search_progress += delta
	if _search_progress < search_time:
		return

	is_being_searched = false
	is_searched = true
	_generate_contents()
	search_finished.emit()


## Fortschritt von 0 bis 1 — für den Balken in der Anzeige.
func get_search_progress() -> float:
	if not is_being_searched:
		return 1.0 if is_searched else 0.0
	return clampf(_search_progress / maxf(0.01, search_time), 0.0, 1.0)


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
			# Folge der Tabellengroesse. Sichtbar machen, damit es beim
			# Balancing auffaellt.
			push_warning("[LootContainer] %s: kein Platz mehr fuer %s" % [display_name, drop.id])
			break


## Nimmt einen Gegenstand heraus und legt ihn ins Zielinventar.
## Passt er dort nicht, bleibt er im Container liegen — nichts geht verloren.
func take_item(instance_id: int, into: InventoryGrid) -> bool:
	var stack := contents.get_stack(instance_id)
	if stack == null or into == null:
		return false

	# Erst versuchen, ob im Ziel überhaupt Platz ist. Erst dann entnehmen.
	# Andersherum könnte der Gegenstand zwischen beiden Rastern verschwinden.
	var test_position := into.find_free_position(stack)
	var can_stack := false
	for existing in into.get_all_stacks():
		if existing.can_merge_with(stack):
			can_stack = true
			break

	if test_position.x < 0 and not can_stack:
		return false

	contents.remove_item(instance_id)
	if not into.add_item(stack):
		# Sollte nach der Prüfung nicht passieren — zur Sicherheit zurücklegen.
		contents.add_item(stack)
		return false
	return true


## Nimmt alles mit, was passt. Gibt zurück, wie viele Gegenstände übrig blieben.
func take_all(into: InventoryGrid) -> int:
	if into == null:
		return contents.get_item_count()

	# Kopie durchlaufen, weil take_item den Container verändert.
	for stack in contents.get_all_stacks():
		take_item(stack.instance_id, into)
	return contents.get_item_count()


func is_empty() -> bool:
	return contents.get_item_count() == 0
