## Das Inventar eines Spielers: was er am Körper trägt und in der Hand hält.
##
## Verbindet das Rasterinventar mit der Waffe und der Bewegung:
##   - Nachladen holt Patronen wirklich aus dem Inventar
##   - Das Gesamtgewicht bremst den Spieler
##   - Waffen werden aus dem Inventar in die Hand genommen
##
## VEREINFACHUNG GEGENÜBER TARKOV:
## Magazine sind (noch) keine eigenen Gegenstände. Nachladen zieht lose
## Patronen aus dem Inventar, statt ein vorbereitetes Magazin einzusetzen.
## Das echte Magazinsystem ist deutlich mehr Arbeit (Magazine befüllen,
## Teilmagazine, Ladezeiten je nach Magazintyp) und lohnt sich erst, wenn
## der Rest steht.
##
## NETZWERK: Später prüft der Server jede Entnahme. Ein Client darf nie
## selbst entscheiden, dass er Munition hat — er fragt an.
class_name PlayerInventory
extends Node

signal changed()
signal weapon_equipped(stack: ItemStack)

## Grösse des Rasters, das man OHNE Ausrüstung hat — die eigenen Taschen.
##
## 12 Felder sind wenig, und das ist der Punkt: Ohne Weste und Rucksack soll
## man kaum etwas mittragen können. Wer mehr will, muss Ausrüstung finden und
## anziehen. Das ist die Entscheidung, die ein Extraction-Shooter braucht —
## bei 80 Feldern von Anfang an gäbe es sie nicht.
##
## Später soll die Grösse von der getragenen Weste abhängen und der Rucksack
## sein eigenes Innenraster mitbringen; dann wird das hier der nackte
## Grundstock, auf den beides addiert wird.
##
## ACHTUNG: Ein Sturmgewehr (5x2) belegt zehn dieser zwölf Felder. Es passt
## also hinein, aber danach ist praktisch nichts mehr übrig. Wer eine zweite
## Waffe mitnehmen will, braucht die Waffenplätze, nicht die Taschen.
@export var grid_width: int = 6
@export var grid_height: int = 2

var grid: InventoryGrid

## Die Waffe, die gerade in der Hand ist. null = unbewaffnet.
var equipped_weapon: ItemStack = null


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	grid = InventoryGrid.new(grid_width, grid_height)
	grid.changed.connect(func(): changed.emit())


## Gesamtgewicht inklusive der Waffe in der Hand.
## Genau dieser Wert bremst den Spieler.
func get_total_weight() -> float:
	var total := grid.get_total_weight()
	if equipped_weapon != null:
		total += equipped_weapon.get_total_weight()
	return total


## Legt einen Gegenstand ins Inventar. Gibt false zurück, wenn kein Platz ist.
func add(item_id: StringName, quantity: int = 1) -> bool:
	var stack := ItemStack.create(item_id, quantity)
	if stack.get_data() == null:
		push_error("[PlayerInventory] Unbekanntes Item: %s" % item_id)
		return false
	var ok := grid.add_item(stack)
	if ok:
		changed.emit()
	return ok


## Nimmt eine Waffe aus dem Inventar in die Hand.
## Die bisherige Waffe wandert zurück ins Raster.
func equip_weapon(stack: ItemStack) -> bool:
	if stack == null or not (stack.get_data() is WeaponData):
		return false

	# Dieselbe Waffe nochmal anlegen ist ein gültiger Aufruf und muss folgenlos
	# bleiben. Ohne diese Abkürzung würde sie unten als "vorherige" Waffe ins
	# Raster zurückgelegt, während sie gleichzeitig in der Hand bleibt — die
	# Waffe wäre danach doppelt vorhanden.
	if stack == equipped_weapon:
		return true

	# Erst zurücklegen, dann herausnehmen — sonst kann die alte Waffe
	# verloren gehen, wenn das Raster inzwischen voll ist.
	var previous := equipped_weapon
	if grid.get_stack(stack.instance_id) != null:
		grid.remove_item(stack.instance_id)

	equipped_weapon = stack

	if previous != null and not grid.add_item(previous):
		# Kein Platz für die alte Waffe: lieber die neue nicht nehmen,
		# als dem Spieler stillschweigend Ausrüstung zu löschen.
		grid.add_item(stack)
		equipped_weapon = previous
		return false

	changed.emit()
	weapon_equipped.emit(stack)
	return true


## Alle Waffen, die der Spieler dabei hat — einschliesslich der in der Hand.
##
## DIE IN DER HAND GEHOERT DAZU, auch wenn sie nicht im Raster liegt.
## Vorher fehlte sie: Beim Durchschalten mit Q/E schrumpfte die Liste dadurch
## bei jedem Wechsel um eins, der Zaehler zeigte auf die falsche Stelle und
## dieselbe Waffe kam zweimal hintereinander dran.
##
## Die Reihenfolge ist nach ID sortiert und damit stabil. Ohne das haengt sie
## davon ab, welche Waffe gerade im Raster liegt und welche nicht — und dann
## springt das Durchschalten bei jedem Wechsel neu durcheinander.
func get_carried_weapons() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for stack in grid.get_all_stacks():
		if stack.get_data() is WeaponData:
			result.append(stack)
	if equipped_weapon != null:
		result.append(equipped_weapon)

	result.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		return String(a.item_id) < String(b.item_id))
	return result


## Meldet eine Änderung, die nicht über das Raster gelaufen ist.
##
## Gebraucht von der Werkbank: Ein Anbauteil ändert weder Belegung noch
## Stückzahl, wohl aber das Gewicht — und ohne diese Meldung würde der
## Spieler erst beim nächsten Umpacken merken, dass ihn das Zielfernrohr
## bremst.
func notify_changed() -> void:
	changed.emit()


## Wie viele Patronen dieser Sorte vorhanden sind.
func count_ammo(ammo_id: StringName) -> int:
	return grid.count_items(ammo_id, true)


## Entnimmt bis zu `wanted` Patronen und gibt zurück, wie viele es wirklich
## waren. Leere Stapel werden dabei entfernt.
##
## Gibt bewusst die tatsächliche Menge zurück statt true/false: Ein halb
## gefülltes Magazin ist ein gültiges Ergebnis und gehört zum Spielgefühl.
func take_ammo(ammo_id: StringName, wanted: int) -> int:
	if wanted <= 0:
		return 0

	var taken := 0
	# Kopie durchlaufen, weil wir dabei Stapel entfernen.
	for stack in grid.get_all_stacks():
		if taken >= wanted:
			break
		if stack.item_id != ammo_id:
			continue

		var from_this := mini(stack.quantity, wanted - taken)
		stack.quantity -= from_this
		taken += from_this

		if stack.quantity <= 0:
			grid.remove_item(stack.instance_id)

	# Auch verschachtelte Container durchsuchen (Rucksack).
	if taken < wanted:
		for stack in grid.get_all_stacks():
			if taken >= wanted:
				break
			if stack.container == null:
				continue
			taken += _take_from_container(stack.container, ammo_id, wanted - taken)

	if taken > 0:
		changed.emit()
	return taken


func _take_from_container(container: InventoryGrid, ammo_id: StringName, wanted: int) -> int:
	var taken := 0
	for stack in container.get_all_stacks():
		if taken >= wanted:
			break
		if stack.item_id == ammo_id:
			var from_this := mini(stack.quantity, wanted - taken)
			stack.quantity -= from_this
			taken += from_this
			if stack.quantity <= 0:
				container.remove_item(stack.instance_id)
		elif stack.container != null:
			taken += _take_from_container(stack.container, ammo_id, wanted - taken)
	return taken


## Alle Munitionssorten im Inventar, die in die angegebene Waffe passen.
## Grundlage für den Munitionswechsel im Spiel.
func get_compatible_ammo(weapon_data: WeaponData) -> Array[StringName]:
	var result: Array[StringName] = []
	if weapon_data == null:
		return result

	for stack in grid.get_all_stacks():
		_collect_ammo(stack, weapon_data, result)
	return result


func _collect_ammo(stack: ItemStack, weapon_data: WeaponData, into: Array[StringName]) -> void:
	var data := stack.get_data()
	if data is AmmoData and weapon_data.accepts_ammo(data as AmmoData):
		if not into.has(stack.item_id):
			into.append(stack.item_id)
	if stack.container != null:
		for child in stack.container.get_all_stacks():
			_collect_ammo(child, weapon_data, into)
