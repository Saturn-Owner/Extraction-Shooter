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

## Was der Spieler am Koerper traegt. Wird vom PlayerController gesetzt.
##
## Das Inventar braucht das nur fuer den Rucksack: Sein Innenraster gehoert
## genauso zum Mitgefuehrten wie die Taschen. Ohne diese Verbindung waere
## Munition im Rucksack beim Nachladen unsichtbar — man stuende mit vollem
## Rucksack vor einer leeren Waffe.
var equipment: Equipment = null


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	grid = InventoryGrid.new(grid_width, grid_height)
	grid.changed.connect(func(): changed.emit())


## Das Innenraster des angelegten Rucksacks, oder null ohne Rucksack.
func get_backpack_grid() -> InventoryGrid:
	if equipment == null:
		return null
	var worn := equipment.get_item(ItemData.EquipSlot.BACKPACK)
	return worn.container if worn != null else null


## Alle Raster, die der Spieler dabeihat — Taschen zuerst, dann der Rucksack.
##
## Die Reihenfolge ist Absicht: Was in die Taschen passt, gehoert dorthin.
## An den Rucksack kommt man spaeter (geplant) nur langsamer heran.
func get_all_grids() -> Array[InventoryGrid]:
	var grids: Array[InventoryGrid] = [grid]
	var backpack := get_backpack_grid()
	if backpack != null:
		grids.append(backpack)
	return grids


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
	var ok := stow(stack)
	if ok:
		changed.emit()
	return ok


## Legt einen Gegenstand ins erste Raster, in dem er Platz findet.
##
## Erst die Taschen, dann der Rucksack. Ohne den zweiten Versuch waere ein
## angelegter Rucksack beim Aufsammeln wertlos.
func stow(stack: ItemStack) -> bool:
	for target in get_all_grids():
		if target.add_item(stack):
			return true
	return false


## Ob dieser Gegenstand irgendwo Platz findet, ohne ihn schon abzulegen.
##
## Gebraucht, bevor getauscht wird: Erst pruefen, dann verdraengen — sonst
## steht man mit einem Gegenstand da, der nirgends hinpasst.
func has_room(stack: ItemStack) -> bool:
	for target in get_all_grids():
		if target.can_place_or_merge(stack, 0, 0) \
				or target.find_free_position(stack).x >= 0:
			return true
	return false


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
	# Aus dem Raster nehmen, in dem sie wirklich liegt. Wuerde hier nur in den
	# Taschen gesucht, bliebe eine Waffe aus dem Rucksack dort liegen UND
	# waere gleichzeitig in der Hand — der Spieler haette sie doppelt.
	var came_from: InventoryGrid = null
	for source in get_all_grids():
		if source.get_stack(stack.instance_id) != null:
			source.remove_item(stack.instance_id)
			came_from = source
			break

	equipped_weapon = stack

	if previous != null and not stow(previous):
		# Kein Platz für die alte Waffe: lieber die neue nicht nehmen,
		# als dem Spieler stillschweigend Ausrüstung zu löschen. Sie geht dabei
		# genau dorthin zurueck, wo sie hergekommen ist — dort war sie eben noch.
		if came_from != null:
			came_from.add_item(stack)
		else:
			stow(stack)
		equipped_weapon = previous
		return false

	changed.emit()
	weapon_equipped.emit(stack)
	return true


## Alle Waffen, die der Spieler dabei hat.
##
## ---------------------------------------------------------------------------
## DREI ORTE, NICHT ZWEI
##
## Eine Waffe kann an drei Stellen sein, und alle drei gehoeren in diese Liste:
##
##   1. im Raster (Taschen oder Rucksack)
##   2. in der Hand — `equipped_weapon`
##   3. AUF DEM ANDEREN WAFFENPLATZ, also umgehaengt statt eingepackt
##
## Der dritte Fall fehlte, und mit zwei Waffen faellt das nicht auf: Eine ist
## in der Hand, die andere im Raster. Erst ab der dritten steckt eine dauerhaft
## auf dem freien Platz — `assign_weapon()` legt sie dorthin und NICHT ins
## Raster zurueck.
##
## Im Testgelaende mit Gewehr, Flinte und Pistole hiess das: Die Liste
## schrumpfte auf zwei, das Durchschalten mit Q/E pendelte zwischen Gewehr und
## Flinte, und die Pistole kam nie wieder. Sie war nicht verloren — sie hing
## am Koerper und wurde nur nicht mitgezaehlt.
##
## Die Reihenfolge ist nach ID sortiert und damit stabil. Ohne das haengt sie
## davon ab, welche Waffe gerade wo liegt — und dann springt das Durchschalten
## bei jedem Wechsel neu durcheinander.
func get_carried_weapons() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	var seen: Dictionary = {}

	for stack in grid.get_all_stacks():
		if stack.get_data() is WeaponData and not seen.has(stack.instance_id):
			seen[stack.instance_id] = true
			result.append(stack)

	# Die Waffenplaetze am Koerper. Die Waffe in der Hand steht ebenfalls auf
	# einem davon, deshalb der Abgleich ueber `instance_id` — sonst kaeme sie
	# doppelt vor und das Durchschalten bliebe an ihr haengen.
	if equipment != null:
		for slot: ItemData.EquipSlot in [ItemData.EquipSlot.PRIMARY,
				ItemData.EquipSlot.SECONDARY]:
			var held := equipment.get_item(slot)
			if held != null and not seen.has(held.instance_id):
				seen[held.instance_id] = true
				result.append(held)

	if equipped_weapon != null and not seen.has(equipped_weapon.instance_id):
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
	var total := 0
	for source in get_all_grids():
		total += source.count_items(ammo_id, true)
	return total


## Entnimmt bis zu `wanted` Patronen und gibt zurück, wie viele es wirklich
## waren. Leere Stapel werden dabei entfernt.
##
## Gibt bewusst die tatsächliche Menge zurück statt true/false: Ein halb
## gefülltes Magazin ist ein gültiges Ergebnis und gehört zum Spielgefühl.
func take_ammo(ammo_id: StringName, wanted: int) -> int:
	if wanted <= 0:
		return 0

	var taken := 0
	var sources := get_all_grids()

	# Erst alles, was lose herumliegt — in den Taschen wie im Rucksack.
	# Kopie durchlaufen, weil wir dabei Stapel entfernen.
	for source in sources:
		for stack in source.get_all_stacks():
			if taken >= wanted:
				break
			if stack.item_id != ammo_id:
				continue

			var from_this := mini(stack.quantity, wanted - taken)
			stack.quantity -= from_this
			taken += from_this

			if stack.quantity <= 0:
				source.remove_item(stack.instance_id)

	# Erst danach in Behaelter hineingreifen. Wer eine Schachtel aufmachen
	# muss, tut das zuletzt.
	if taken < wanted:
		for source in sources:
			for stack in source.get_all_stacks():
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

	for source in get_all_grids():
		for stack in source.get_all_stacks():
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
