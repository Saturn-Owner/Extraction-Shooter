## Ein konkretes Exemplar eines Gegenstands im Spiel.
##
## Wichtige Unterscheidung:
##   ItemData  = die VORLAGE ("5.56x45 M995" als Konzept, existiert einmal)
##   ItemStack = das EXEMPLAR (die 43 Patronen in deinem Rucksack)
##
## Eine halb zerschossene Platte ist ein ItemStack mit eigener Haltbarkeit —
## die ItemData-Vorlage bleibt davon unberührt. Würden wir das vermischen,
## würde die Abnutzung einer Platte alle Platten im Spiel beschädigen.
##
## ItemStacks werden NICHT als .tres gespeichert, sondern über to_dict()
## in die Datenbank geschrieben und über das Netzwerk übertragen.
class_name ItemStack
extends RefCounted

## Fortlaufender Zähler für Instanz-IDs.
## WICHTIG: Im Mehrspielerbetrieb vergibt ausschließlich der Server IDs.
## Clients dürfen nie selbst welche erzeugen, sonst kollidieren sie.
static var _next_instance_id: int = 1

## Eindeutige ID dieses Exemplars. Über sie referenzieren Client und Server
## denselben Gegenstand ("verschiebe Item 417"), ohne Objekte zu übertragen.
var instance_id: int = 0

## Verweis auf die Vorlage, z.B. &"ammo_556x45_m995".
var item_id: StringName = &""

## Stückzahl. Bei nicht stapelbaren Gegenständen immer 1.
var quantity: int = 1

## Ob das Item im Raster um 90° gedreht liegt.
var rotated: bool = false

## Restliche Haltbarkeit bei Platten und Waffen. -1.0 = nicht zutreffend.
var durability: float = -1.0

## Verschachtelter Inhalt: Rucksäcke und Westen haben ein eigenes Raster.
## null bei allen Gegenständen, die nichts enthalten können.
var container: InventoryGrid = null


static func create(p_item_id: StringName, p_quantity: int = 1) -> ItemStack:
	var stack := ItemStack.new()
	stack.instance_id = _next_instance_id
	_next_instance_id += 1
	stack.item_id = p_item_id
	stack.quantity = p_quantity

	var data := stack.get_data()
	if data != null:
		# Rucksäcke und Westen bekommen ihr Innenraster gleich mit.
		if data.is_container():
			stack.container = InventoryGrid.new(data.container_width, data.container_height)
		# Platten und Waffen starten unbeschädigt.
		if data is ArmorPlateData:
			stack.durability = (data as ArmorPlateData).max_durability

	return stack


## Nur der Server darf den Zähler zurücksetzen (z.B. beim Laden eines Spielstands).
static func reset_id_counter(start_at: int = 1) -> void:
	_next_instance_id = start_at


## Die Vorlage zu diesem Exemplar.
func get_data() -> ItemData:
	return ItemRegistry.get_item(item_id)


## Belegte Fläche im Raster, unter Berücksichtigung der Drehung.
func get_size() -> Vector2i:
	var data := get_data()
	if data == null:
		return Vector2i.ONE
	if rotated:
		return Vector2i(data.grid_height, data.grid_width)
	return Vector2i(data.grid_width, data.grid_height)


## Gesamtgewicht inklusive allem, was im Container steckt.
## Ein voller Rucksack wiegt entsprechend mehr — das bremst den Spieler.
func get_total_weight() -> float:
	var data := get_data()
	if data == null:
		return 0.0
	var w := data.weight_kg * float(quantity)
	if container != null:
		w += container.get_total_weight()
	return w


## Ob noch etwas auf diesen Stapel draufpasst.
func get_free_stack_space() -> int:
	var data := get_data()
	if data == null:
		return 0
	return maxi(0, data.max_stack - quantity)


## Ob zwei Stapel zusammengelegt werden dürfen.
## Gegenstände mit individuellem Zustand (beschädigte Platten, Container)
## dürfen NIE gestapelt werden — sonst geht der Zustand verloren.
func can_merge_with(other: ItemStack) -> bool:
	if other == null or other == self:
		return false
	if item_id != other.item_id:
		return false
	if container != null or other.container != null:
		return false
	if durability >= 0.0 or other.durability >= 0.0:
		return false
	return get_free_stack_space() > 0


## Legt so viel wie möglich von other auf diesen Stapel.
## Gibt zurück, wie viele Stück übernommen wurden.
func merge_from(other: ItemStack) -> int:
	if not can_merge_with(other):
		return 0
	var moved := mini(get_free_stack_space(), other.quantity)
	quantity += moved
	other.quantity -= moved
	return moved


## Teilt einen Stapel und gibt den abgetrennten Teil zurück (null bei Unfug).
func split(amount: int) -> ItemStack:
	if amount <= 0 or amount >= quantity:
		return null
	quantity -= amount
	return ItemStack.create(item_id, amount)


## Für Netzwerkübertragung und Speicherung in der Datenbank.
func to_dict() -> Dictionary:
	var d := {
		"instance_id": instance_id,
		"item_id": String(item_id),
		"quantity": quantity,
		"rotated": rotated,
		"durability": durability,
	}
	if container != null:
		d["container"] = container.to_dict()
	return d


static func from_dict(d: Dictionary) -> ItemStack:
	var stack := ItemStack.new()
	stack.instance_id = int(d.get("instance_id", 0))
	stack.item_id = StringName(d.get("item_id", ""))
	stack.quantity = int(d.get("quantity", 1))
	stack.rotated = bool(d.get("rotated", false))
	stack.durability = float(d.get("durability", -1.0))
	if d.has("container"):
		stack.container = InventoryGrid.from_dict(d["container"])
	# Zähler mitziehen, damit nach dem Laden keine IDs doppelt vergeben werden.
	if stack.instance_id >= _next_instance_id:
		_next_instance_id = stack.instance_id + 1
	return stack
