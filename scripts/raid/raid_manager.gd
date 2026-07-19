## Steuert einen Raid: Start, Extraction, Tod — und was danach vom
## Mitgebrachten übrig ist.
##
## ---------------------------------------------------------------------------
## DIE KERNREGEL DES GENRES
##
##   Erfolgreich extrahiert  ->  alles Mitgeführte wandert ins Lager
##   Gestorben               ->  alles Mitgeführte ist weg
##
## Genau diese Regel erzeugt die Spannung. Ohne echten Verlust ist Looten
## belanglos, und der Moment am Ausgang bedeutet nichts.
##
## Das LAGER (Stash) ist der sichere Ort und überlebt jeden Raid. Es ist
## bewusst getrennt vom Inventar des Spielers: Was im Lager liegt, kann nie
## verloren gehen. Was am Körper ist, immer.
##
## NETZWERK: Das Lager gehört später auf den Server und in die Datenbank.
## Ein Client darf niemals selbst entscheiden, dass er einen Raid überlebt
## hat — sonst behauptet das jeder.
class_name RaidManager
extends Node

signal raid_started()
signal raid_ended(survived: bool, items_secured: int)
signal stash_changed()

enum State { VORBEREITUNG, LAEUFT, BEENDET }

## Grösse des Lagers. Wächst später mit dem Bunker-Ausbau.
@export var stash_width: int = 14
@export var stash_height: int = 12

var state: State = State.VORBEREITUNG
var stash: InventoryGrid

## Was der Spieler beim Start dabeihatte — nur für die Auswertung danach.
var _items_taken_in: int = 0

var _player: PlayerController = null


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	stash = InventoryGrid.new(stash_width, stash_height)
	stash.changed.connect(func(): stash_changed.emit())


## Meldet den Spieler an und verbindet alle Ausgänge im Level.
func setup(player: PlayerController) -> void:
	_player = player

	for zone in get_tree().get_nodes_in_group("extraction_zone"):
		var extraction := zone as ExtractionZone
		if extraction != null and not extraction.extraction_complete.is_connected(_on_extraction_complete):
			extraction.extraction_complete.connect(_on_extraction_complete)


func start_raid() -> void:
	if _player == null:
		push_error("[RaidManager] Kein Spieler angemeldet")
		return

	state = State.LAEUFT
	_items_taken_in = _count_carried()

	for zone in get_tree().get_nodes_in_group("extraction_zone"):
		var extraction := zone as ExtractionZone
		if extraction != null:
			extraction.reset()

	raid_started.emit()


func _count_carried() -> int:
	if _player == null or _player.inventory == null:
		return 0
	var count := _player.inventory.grid.get_item_count()
	if _player.inventory.equipped_weapon != null:
		count += 1
	return count


func _on_extraction_complete(_player_node: Node) -> void:
	extract()


## Erfolgreiche Extraction: alles Mitgeführte ins Lager.
func extract() -> int:
	if state != State.LAEUFT:
		return 0

	state = State.BEENDET
	var secured := _move_carried_to_stash()
	raid_ended.emit(true, secured)
	return secured


## Tod: alles Mitgeführte ist weg. Das Lager bleibt unangetastet.
func die() -> void:
	if state != State.LAEUFT:
		return

	state = State.BEENDET
	if _player != null and _player.inventory != null:
		_player.inventory.grid.resize(
			_player.inventory.grid_width,
			_player.inventory.grid_height
		)
		_player.inventory.equipped_weapon = null
		_player.inventory.changed.emit()

	raid_ended.emit(false, 0)


## Schafft das Mitgeführte ins Lager. Gibt zurück, wie viele Gegenstände
## wirklich angekommen sind.
##
## Passt etwas nicht mehr ins Lager, bleibt es beim Spieler, statt gelöscht
## zu werden — Ausrüstung stillschweigend zu vernichten wäre der schlimmste
## denkbare Fehler in einem Spiel, in dem Beute alles ist.
func _move_carried_to_stash() -> int:
	if _player == null or _player.inventory == null:
		return 0

	var inventory := _player.inventory
	var secured := 0

	# Zuerst das Magazin entladen. Ohne das verschwinden die geladenen
	# Patronen bei jeder Extraction — bei teurer Munition ein erheblicher
	# stiller Verlust, den niemand bemerkt.
	_player.unload_weapon()

	# Die Waffe in der Hand zuerst — sie ist meist das Wertvollste.
	if inventory.equipped_weapon != null:
		if stash.add_item(inventory.equipped_weapon):
			inventory.equipped_weapon = null
			secured += 1

	for item in inventory.grid.get_all_stacks():
		if stash.add_item(item):
			inventory.grid.remove_item(item.instance_id)
			secured += 1
		else:
			push_warning("[RaidManager] Lager voll — %s bleibt beim Spieler" % item.item_id)

	inventory.changed.emit()
	return secured


## Rüstet den Spieler aus dem Lager aus — der Weg in den nächsten Raid.
## Gibt zurück, wie viele Gegenstände übernommen wurden.
func equip_from_stash(item_ids: Array) -> int:
	if _player == null or _player.inventory == null:
		return 0

	var moved := 0
	for wanted in item_ids:
		for item in stash.get_all_stacks():
			if item.item_id != wanted:
				continue
			if _player.inventory.grid.add_item(item):
				stash.remove_item(item.instance_id)
				moved += 1
			break

	_player.inventory.changed.emit()
	return moved


func get_items_taken_in() -> int:
	return _items_taken_in


## Für das Speichersystem. Das Lager ist der einzige Zustand, der einen
## Raid überdauert — damit ist es auch das Einzige, was zwingend
## gespeichert werden muss.
func to_dict() -> Dictionary:
	return {"stash": stash.to_dict()}


func from_dict(data: Dictionary) -> void:
	if data.has("stash"):
		stash = InventoryGrid.from_dict(data["stash"])
		stash.changed.connect(func(): stash_changed.emit())
		stash_changed.emit()
