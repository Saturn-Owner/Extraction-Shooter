## Was der Spieler am Körper trägt.
##
## Getrennt vom Inventar: Was man ANHAT, ist etwas anderes als was man
## DABEIHAT. Eine Jacke im Rucksack wärmt niemanden, eine Platte im Rucksack
## hält keine Kugel auf.
##
## Jeder Platz nimmt genau einen Gegenstand. Angelegte Sachen zählen weiter
## zum Gewicht — man trägt sie ja — aber sie belegen keine Rasterfelder.
## Das ist der eigentliche Anreiz, überhaupt etwas anzuziehen.
##
## HINWEIS ZUM NETZWERK: Anlegen und Ablegen sind zustandsverändernd und
## laufen später über den Server. Der Client fragt, der Server entscheidet.
class_name Equipment
extends Node

signal changed()
signal item_equipped(slot: ItemData.EquipSlot, stack: ItemStack)
signal item_unequipped(slot: ItemData.EquipSlot, stack: ItemStack)

## Reihenfolge für die Anzeige — von oben nach unten am Körper.
const SLOT_ORDER := [
	ItemData.EquipSlot.HEAD,
	ItemData.EquipSlot.CHEST,
	ItemData.EquipSlot.SHIRT,
	ItemData.EquipSlot.BELT,
	ItemData.EquipSlot.PANTS,
	ItemData.EquipSlot.BOOTS,
	ItemData.EquipSlot.BACKPACK,
]

const SLOT_NAMES := {
	ItemData.EquipSlot.HEAD: "Helm",
	ItemData.EquipSlot.CHEST: "Brustpanzer",
	ItemData.EquipSlot.SHIRT: "Oberteil",
	ItemData.EquipSlot.BELT: "Guertel",
	ItemData.EquipSlot.PANTS: "Hose",
	ItemData.EquipSlot.BOOTS: "Schuhe",
	ItemData.EquipSlot.BACKPACK: "Rucksack",
}

## Slot -> ItemStack (oder nicht vorhanden, wenn leer).
var _slots: Dictionary = {}


static func get_slot_name(slot: ItemData.EquipSlot) -> String:
	return SLOT_NAMES.get(slot, "Platz")


func get_item(slot: ItemData.EquipSlot) -> ItemStack:
	return _slots.get(slot)


func is_empty(slot: ItemData.EquipSlot) -> bool:
	return not _slots.has(slot)


## Ob dieser Gegenstand in diesen Platz gehört.
func can_equip(stack: ItemStack, slot: ItemData.EquipSlot) -> bool:
	if stack == null or slot == ItemData.EquipSlot.NONE:
		return false
	var data := stack.get_data()
	return data != null and data.equip_slot == slot


## Legt einen Gegenstand an. Gibt zurueck, was vorher dort war (oder null).
##
## Der Aufrufer MUSS den zurueckgegebenen Gegenstand unterbringen — sonst
## verschwindet er. Deshalb gibt diese Funktion ihn heraus, statt ihn selbst
## irgendwohin zu legen: Wo er hingehoert, weiss nur der Aufrufer.
func equip(stack: ItemStack, slot: ItemData.EquipSlot) -> ItemStack:
	if not can_equip(stack, slot):
		return null

	var previous: ItemStack = _slots.get(slot)
	_slots[slot] = stack

	if previous != null:
		item_unequipped.emit(slot, previous)
	item_equipped.emit(slot, stack)
	changed.emit()
	return previous


## Nimmt ab, was in diesem Platz steckt.
func unequip(slot: ItemData.EquipSlot) -> ItemStack:
	if not _slots.has(slot):
		return null
	var stack: ItemStack = _slots[slot]
	_slots.erase(slot)
	item_unequipped.emit(slot, stack)
	changed.emit()
	return stack


func clear() -> void:
	if _slots.is_empty():
		return
	_slots.clear()
	changed.emit()


## Summe der Wärmedämmung aller getragenen Teile.
func get_total_insulation() -> float:
	var total := 0.0
	for slot in _slots:
		var data: ItemData = _slots[slot].get_data()
		if data != null:
			total += data.insulation
	return total


## Gewicht der getragenen Ausrüstung, inklusive dem, was im Rucksack steckt.
func get_total_weight() -> float:
	var total := 0.0
	for slot in _slots:
		total += (_slots[slot] as ItemStack).get_total_weight()
	return total


## Die angelegte Schutzplatte, falls vorhanden. Fuer die Trefferberechnung.
func get_chest_plate() -> ItemStack:
	var stack: ItemStack = _slots.get(ItemData.EquipSlot.CHEST)
	if stack == null:
		return null
	return stack if stack.get_data() is ArmorPlateData else null


## Der Helm, falls vorhanden.
func get_helmet() -> ItemStack:
	return _slots.get(ItemData.EquipSlot.HEAD)


## Alles Getragene, etwa um es bei der Extraction ins Lager zu bringen.
func get_all_items() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for slot in SLOT_ORDER:
		if _slots.has(slot):
			result.append(_slots[slot])
	return result


func to_dict() -> Dictionary:
	var out := {}
	for slot in _slots:
		out[str(slot)] = (_slots[slot] as ItemStack).to_dict()
	return out


func from_dict(data: Dictionary) -> void:
	_slots.clear()
	for key in data:
		var stack := ItemStack.from_dict(data[key])
		if stack != null:
			_slots[int(key)] = stack
	changed.emit()
