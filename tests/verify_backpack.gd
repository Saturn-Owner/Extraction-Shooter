## Prüft den Rucksack: das Item selbst, die Ausruestungskiste und was ein
## angelegter Rucksack am Inventar aendert.
##
##   godot --headless --path . --script res://tests/verify_backpack.gd
##
## Der Kern dieser Suite sind die STILLEN VERLUSTE. Ein zweites Raster am
## Spieler bricht genau dort, wo Code bisher selbstverstaendlich von einem
## einzigen ausging: Nachladen, Aufsammeln, Waffe ziehen. Jeder dieser Fehler
## faellt im Spiel erst auf, wenn schon etwas weg ist.
##
## Was hier NICHT geprüft werden kann: ob das zweite Raster im Fenster gut
## aussieht und ob 24 Felder die richtige Groesse sind. Das muss ein Mensch
## sehen und spielen.
extends SceneTree

const BACKPACK := &"backpack_wander"

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Rucksack pruefen ===\n")

	_test_item()
	_test_loot_table()
	_test_fits_in_pockets()
	_test_extra_space()
	_test_ammo_in_backpack()
	_test_weapon_from_backpack()
	_test_not_into_itself()
	_test_weight_counts()

	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


# ---------------------------------------------------------------------------

func _test_item() -> void:
	_section("Das Item")

	var data := ItemRegistry.get_item(BACKPACK)
	_check(data != null, "Vorlage '%s' ist eingetragen" % BACKPACK)
	if data == null:
		return

	_check(data.category == ItemData.Category.BACKPACK, "Kategorie ist Rucksack")
	_check(data.equip_slot == ItemData.EquipSlot.BACKPACK, "gehoert in den Rucksackplatz")
	_check(data.is_container(), "hat ein Innenraster")

	# Ein Rucksack, der nicht mehr fasst als die Taschen, waere kein Fund.
	var inside := data.container_width * data.container_height
	_check(inside > 12, "fasst mehr als die blossen Taschen (%d Felder)" % inside)


func _test_loot_table() -> void:
	_section("Ausruestungskiste")

	var table := load("res://assets/data/loot/ausruestung.tres") as LootTableData
	_check(table != null, "Loot-Tabelle laedt")
	if table == null:
		return

	_check(table.validate().is_empty(),
		"Tabelle ohne Datenfehler: %s" % ", ".join(table.validate()))

	# Diese eine Kiste soll NIE leer sein: Sie steht direkt vor dem Einstieg
	# und ist der Grund, ueberhaupt loszulaufen. Ein Leerzug waere ein Raid,
	# der ohne Rucksack anfaengt, obwohl er mit einem anfangen sollte.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var empty_rolls := 0
	for i in range(50):
		var drops := table.roll(rng)
		if drops.size() != 1 or drops[0].id != BACKPACK:
			empty_rolls += 1
	_check(empty_rolls == 0, "50 Zuege ergeben immer genau einen Rucksack (%d Ausreisser)" % empty_rolls)


## Der Rucksack muss in die 6x2-Taschen passen, sonst kann man ihn gar nicht
## erst aus der Kiste nehmen — und ein Fund, den man nicht anfassen kann, ist
## schlimmer als keiner.
func _test_fits_in_pockets() -> void:
	_section("Passt in die Taschen")

	var pockets := InventoryGrid.new(6, 2)
	var stack := ItemStack.create(BACKPACK, 1)
	_check(pockets.add_item(stack), "liegt zusammengelegt in den blossen Taschen")


func _test_extra_space() -> void:
	_section("Mehr Platz")

	var setup := _make_player()
	var inventory: PlayerInventory = setup.inventory

	_check(inventory.get_backpack_grid() == null, "ohne Rucksack gibt es kein zweites Raster")
	_check(inventory.get_all_grids().size() == 1, "ohne Rucksack genau ein Raster")

	_equip_backpack(setup)

	_check(inventory.get_backpack_grid() != null, "angelegt taucht das Innenraster auf")
	_check(inventory.get_all_grids().size() == 2, "mit Rucksack zwei Raster")

	# Taschen randvoll: Was jetzt noch dazukommt, MUSS im Rucksack landen.
	var pockets := inventory.grid
	while pockets.get_free_cell_count() > 0:
		if not inventory.add(&"ammo_9x19_fmj", 1):
			break

	var before := inventory.get_backpack_grid().get_item_count()
	var ok := inventory.add(&"ammo_556x45_m855a1", 30)
	_check(ok, "mit vollen Taschen wird trotzdem aufgesammelt")
	_check(inventory.get_backpack_grid().get_item_count() > before,
		"und zwar in den Rucksack")

	setup.player.free()


## Munition im Rucksack muss beim Nachladen gefunden werden.
##
## Sonst steht man mit vollem Rucksack vor einer leeren Waffe — der Fehler,
## den man im Gefecht bemerkt und nicht davor.
func _test_ammo_in_backpack() -> void:
	_section("Nachladen aus dem Rucksack")

	var setup := _make_player()
	var inventory: PlayerInventory = setup.inventory
	_equip_backpack(setup)

	var pack := inventory.get_backpack_grid()
	pack.add_item(ItemStack.create(&"ammo_9x19_fmj", 40))

	_check(inventory.count_ammo(&"ammo_9x19_fmj") == 40,
		"40 Patronen im Rucksack werden gezaehlt (%d)" % inventory.count_ammo(&"ammo_9x19_fmj"))

	var taken := inventory.take_ammo(&"ammo_9x19_fmj", 15)
	_check(taken == 15, "15 davon lassen sich entnehmen (%d)" % taken)
	_check(inventory.count_ammo(&"ammo_9x19_fmj") == 25, "25 bleiben liegen")

	setup.player.free()


## Eine Waffe aus dem Rucksack in die Hand darf sie nicht verdoppeln.
func _test_weapon_from_backpack() -> void:
	_section("Waffe aus dem Rucksack")

	var setup := _make_player()
	var inventory: PlayerInventory = setup.inventory
	_equip_backpack(setup)

	var pack := inventory.get_backpack_grid()
	var pistol := ItemStack.create(&"weapon_pistol_g17", 1)
	if not pack.add_item(pistol):
		_check(false, "Pistole passt in den Rucksack")
		setup.player.free()
		return

	inventory.equip_weapon(pistol)

	_check(inventory.equipped_weapon == pistol, "sie liegt in der Hand")
	_check(pack.get_stack(pistol.instance_id) == null,
		"und NICHT mehr im Rucksack — sonst haette man sie doppelt")

	setup.player.free()


## Ein Behaelter darf nicht in sich selbst wandern.
func _test_not_into_itself() -> void:
	_section("Nicht in sich selbst")

	var pack := ItemStack.create(BACKPACK, 1)
	_check(pack.container != null, "der Rucksack hat sein eigenes Raster")
	if pack.container == null:
		return

	_check(PlayerController._contains_grid(pack.container, pack.container),
		"sein Raster ist sein eigenes")

	# Eine Tasche im Rucksack zaehlt mit: Der Rucksack darf auch dort nicht
	# hinein, sonst verschwindet er ueber zwei Ecken.
	var inner := ItemStack.create(BACKPACK, 1)
	pack.container.add_item(inner)
	_check(PlayerController._contains_grid(pack.container, inner.container),
		"auch ueber eine Zwischenstufe erkannt")

	var loose := InventoryGrid.new(4, 4)
	_check(not PlayerController._contains_grid(pack.container, loose),
		"ein fremdes Raster gilt nicht als sein eigenes")


## Was im Rucksack liegt, muss den Spieler bremsen.
func _test_weight_counts() -> void:
	_section("Gewicht")

	var pack := ItemStack.create(BACKPACK, 1)
	var empty := pack.get_total_weight()
	pack.container.add_item(ItemStack.create(&"ammo_9x19_fmj", 50))
	var full := pack.get_total_weight()

	_check(full > empty, "voll wiegt er mehr als leer (%.2f statt %.2f kg)" % [full, empty])


# ---------------------------------------------------------------------------
# Aufbau
#
# Der PlayerController braucht seine ganze Szene (Kamera, Waffe, Werte), um
# hochzufahren. Fuer diese Suite genuegen Inventar und Ausruestung — also
# werden nur die beiden als lose Knoten gebaut und von Hand verbunden, genau
# wie es der Controller im Spiel tut.
# ---------------------------------------------------------------------------

func _make_player() -> Dictionary:
	var holder := Node.new()

	var equipment := Equipment.new()
	equipment.name = "Equipment"
	holder.add_child(equipment)

	var inventory := PlayerInventory.new()
	inventory.name = "Inventory"
	holder.add_child(inventory)

	# _ready() laeuft erst im Baum — hier von Hand, damit das Raster steht.
	inventory.grid = InventoryGrid.new(inventory.grid_width, inventory.grid_height)
	inventory.equipment = equipment

	return {player = holder, inventory = inventory, equipment = equipment}


func _equip_backpack(setup: Dictionary) -> ItemStack:
	var stack := ItemStack.create(BACKPACK, 1)
	var equipment: Equipment = setup.equipment
	equipment.equip(stack, ItemData.EquipSlot.BACKPACK)
	return stack
