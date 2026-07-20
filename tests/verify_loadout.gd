## Prüft das Zusammenspiel von Inventar, Waffe und Bewegung.
##
##   godot --headless --path . --script res://tests/verify_loadout.gd
##
## Das ist die Stelle, an der die drei bisher getrennten Systeme
## aufeinandertreffen — und damit die Stelle, an der Ausrüstung verloren
## gehen oder Munition aus dem Nichts entstehen kann.
extends SceneTree

## Notbremse gegen haengende Tests — siehe verify_feedback.gd.
const TIMEOUT_SECONDS := 60.0

var _failed := 0
var _passed := 0
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	# Platte, Rucksack und Kleidung gibt es im Spiel gerade nicht mehr.
	TestItems.install()
	print("=== Inventar, Waffe und Gewicht ===\n")
	_run_all()


func _process(delta: float) -> bool:
	if _done:
		return false
	_elapsed += delta
	if _elapsed >= TIMEOUT_SECONDS:
		print("\n=== ABBRUCH: Test haengt seit %.0f s ===" % TIMEOUT_SECONDS)
		print("Wahrscheinlich hat ein Laufzeitfehler die Koroutine abgebrochen.")
		print("Bisher: %d bestanden, %d fehlgeschlagen" % [_passed, _failed])
		quit(1)
	return false


func _run_all() -> void:
	await process_frame
	_test_ammo_accounting()
	_test_weapon_switching_keeps_gear()
	await _test_ammo_switch_returns_rounds()
	await _test_in_level()
	await _test_weapon_slots()
	_finish()


## Primaer- und Sekundaerwaffe auf den Tasten 1 und 2.
##
## Der heikle Teil ist das MAGAZIN: Die Patronen im Lauf gehoeren zu DIESER
## Waffe. Gehen sie beim Wechsel verloren, faellt das im Spiel kaum auf und
## kostet trotzdem jedes Mal Munition — genau dieser Fehler hat uns schon
## einmal bei jeder Extraction ein volles Magazin gekostet.
func _test_weapon_slots() -> void:
	_section("Waffenplaetze")

	var packed: PackedScene = load("res://scenes/player/player.tscn")
	var player: PlayerController = packed.instantiate()

	# Grosses Raster: Hier geht es um die Waffenplaetze, nicht um Platzmangel.
	# In den nackten Taschen (6x2) liegen schon zwei Waffen nicht nebeneinander.
	var inventory: PlayerInventory = player.get_node("Inventory")
	inventory.grid_width = 10
	inventory.grid_height = 8

	root.add_child(player)
	await process_frame

	player.inventory.add(&"weapon_rifle_ar15", 1)
	player.inventory.add(&"weapon_pistol_g17", 1)
	player.inventory.add(&"ammo_556x45_m855a1", 60)
	player.inventory.add(&"ammo_9x19_fmj", 34)

	var weapons := player.inventory.get_carried_weapons()
	var rifle: ItemStack = null
	var pistol: ItemStack = null
	for stack in weapons:
		if stack.item_id == &"weapon_rifle_ar15":
			rifle = stack
		elif stack.item_id == &"weapon_pistol_g17":
			pistol = stack

	_check(rifle != null and pistol != null, "beide Waffen liegen im Inventar")
	if rifle == null or pistol == null:
		player.free()
		return

	_check(player.assign_weapon(rifle), "Gewehr auf den ersten Platz")
	_check(player.equipment.get_item(ItemData.EquipSlot.PRIMARY) == rifle,
		"es liegt auf der Primaerwaffe")
	_check(player.active_weapon_slot == ItemData.EquipSlot.PRIMARY,
		"und ist in der Hand")

	_check(player.assign_weapon(pistol), "Pistole auf den zweiten Platz")
	_check(player.equipment.get_item(ItemData.EquipSlot.SECONDARY) == pistol,
		"sie liegt auf der Sekundaerwaffe")

	# Waffen liegen jetzt am Koerper, nicht mehr im Raster.
	_check(player.inventory.grid.get_stack(rifle.instance_id) == null,
		"das Gewehr belegt keine Rasterfelder mehr")

	# Das Gewicht darf NICHT doppelt zaehlen, nur weil die Waffe sowohl
	# "in der Hand" als auch "am Koerper" ist.
	var expected := player.inventory.grid.get_total_weight() + player.equipment.get_total_weight()
	_check(is_equal_approx(player.carried_weight_kg, expected),
		"das Gewicht zaehlt jede Waffe genau einmal (%.2f)" % player.carried_weight_kg)

	# Magazin fuellen, wechseln, zurueckwechseln.
	player.select_weapon_slot(ItemData.EquipSlot.PRIMARY)
	player.try_reload()
	var rifle_rounds := player.weapon.rounds_in_magazine
	var rifle_ammo := player.weapon.ammo_id
	_check(rifle_rounds > 0, "das Gewehr ist geladen (%d)" % rifle_rounds)

	_check(player.select_weapon_slot(ItemData.EquipSlot.SECONDARY), "Wechsel auf die Pistole")
	_check(player.weapon.data.id == &"weapon_pistol_g17", "die Pistole ist in der Hand")
	_check(player.weapon.rounds_in_magazine != rifle_rounds
		or player.weapon.ammo_id != rifle_ammo, "mit eigener Munition")

	_check(player.select_weapon_slot(ItemData.EquipSlot.PRIMARY), "zurueck auf das Gewehr")
	_check(player.weapon.rounds_in_magazine == rifle_rounds,
		"das Magazin ist noch so voll wie vorher (%d)" % player.weapon.rounds_in_magazine)
	_check(player.weapon.ammo_id == rifle_ammo, "und mit derselben Munition")

	# Ein leerer Platz darf keinen Wechsel auf leere Haende ausloesen.
	player.equipment.unequip(ItemData.EquipSlot.SECONDARY)
	_check(not player.select_weapon_slot(ItemData.EquipSlot.SECONDARY),
		"ein leerer Platz wechselt nicht")
	_check(player.weapon.data.id == &"weapon_rifle_ar15",
		"das Gewehr bleibt in der Hand")

	# --- Wegpacken: vom Koerper zurueck ins Raster (Ziehen mit der Maus) ---

	# Die Pistole wieder anlegen, damit es etwas zum Wechseln gibt.
	player.assign_weapon(pistol, ItemData.EquipSlot.SECONDARY)
	player.select_weapon_slot(ItemData.EquipSlot.PRIMARY)
	rifle_rounds = player.weapon.rounds_in_magazine

	_check(player.stow_equipment(ItemData.EquipSlot.PRIMARY, 0, 0),
		"das Gewehr wandert ins Raster")
	_check(player.equipment.get_item(ItemData.EquipSlot.PRIMARY) == null,
		"der Waffenplatz ist wieder leer")
	_check(player.inventory.grid.get_stack(rifle.instance_id) == rifle,
		"und es liegt jetzt im Raster")

	# Wer seine Waffe wegpackt, soll nicht mit leeren Haenden dastehen,
	# solange er eine zweite hat.
	_check(player.weapon.data != null and player.weapon.data.id == &"weapon_pistol_g17",
		"die Pistole rutscht automatisch in die Hand")

	# Das Magazin haengt an der WAFFE, nicht am Platz. Sonst waeren die
	# Patronen weg, sobald die Waffe einmal im Rucksack war.
	_check(player.assign_weapon(rifle, ItemData.EquipSlot.PRIMARY),
		"das Gewehr kommt zurueck auf den Platz")
	_check(player.weapon.rounds_in_magazine == rifle_rounds,
		"das Magazin hat den Rucksack ueberlebt (%d von %d)" % [
			player.weapon.rounds_in_magazine, rifle_rounds])

	# Letzte Waffe weggepackt: leere Haende sind erlaubt, aber dann darf auch
	# nicht mehr geschossen werden.
	player.stow_equipment(ItemData.EquipSlot.SECONDARY)
	player.stow_equipment(ItemData.EquipSlot.PRIMARY)
	_check(player.weapon.data == null, "ohne Waffe sind die Haende leer")
	_check(not player.weapon.try_fire(true, true), "und es faellt kein Schuss")

	# Passt es nicht ins Raster, bleibt es angelegt — kein stiller Verlust.
	player.assign_weapon(rifle, ItemData.EquipSlot.PRIMARY)
	var filler := player.inventory.grid
	while filler.add_item(ItemStack.create(&"ammo_556x45_m855a1", 1)):
		pass
	_check(not player.stow_equipment(ItemData.EquipSlot.PRIMARY),
		"im vollen Raster bleibt die Waffe am Koerper")
	_check(player.equipment.get_item(ItemData.EquipSlot.PRIMARY) == rifle,
		"sie haengt noch im Platz")

	player.free()


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


func _finish() -> void:
	_done = true
	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Ein Inventar mit reichlich Platz.
##
## Die eigenen Taschen sind nur 2x8 gross — hier geht es aber um Buchhaltung
## (verschwindet Munition? zaehlt der Rucksack mit?), nicht um Platzmangel.
## Mit den nackten Taschen wuerden diese Tests am fehlenden Platz scheitern
## statt an dem, was sie pruefen sollen.
func _make_inventory() -> PlayerInventory:
	var inv := PlayerInventory.new()
	inv.grid_width = 10
	inv.grid_height = 8
	root.add_child(inv)
	return inv


## Munition darf weder verschwinden noch sich vermehren.
func _test_ammo_accounting() -> void:
	_section("Munitionsbuchhaltung")

	var inv := _make_inventory()
	inv.add(&"ammo_556x45_m855a1", 60)
	_check(inv.count_ammo(&"ammo_556x45_m855a1") == 60, "60 Patronen eingelagert")

	var taken := inv.take_ammo(&"ammo_556x45_m855a1", 30)
	_check(taken == 30, "30 entnommen")
	_check(inv.count_ammo(&"ammo_556x45_m855a1") == 30, "30 bleiben uebrig")

	# Mehr verlangen als da ist: bekommt man nur, was da ist.
	var rest := inv.take_ammo(&"ammo_556x45_m855a1", 100)
	_check(rest == 30, "Anfrage ueber Bestand liefert nur den Bestand (%d)" % rest)
	_check(inv.count_ammo(&"ammo_556x45_m855a1") == 0, "Inventar ist danach leer")
	_check(inv.take_ammo(&"ammo_556x45_m855a1", 10) == 0, "aus leerem Inventar kommt nichts")

	# Aus dem Rucksack muss ebenfalls entnommen werden.
	var backpack := ItemStack.create(&"backpack_small")
	inv.grid.add_item(backpack)
	backpack.container.add_item(ItemStack.create(&"ammo_9x19_fmj", 40))
	_check(inv.count_ammo(&"ammo_9x19_fmj") == 40, "Rucksackinhalt wird mitgezaehlt")
	_check(inv.take_ammo(&"ammo_9x19_fmj", 25) == 25, "aus dem Rucksack wird entnommen")
	_check(inv.count_ammo(&"ammo_9x19_fmj") == 15, "Restbestand im Rucksack stimmt")

	inv.free()


## Beim Waffenwechsel darf keine Ausrüstung verschwinden.
func _test_weapon_switching_keeps_gear() -> void:
	_section("Waffenwechsel")

	var inv := _make_inventory()
	inv.add(&"weapon_rifle_ar15", 1)
	inv.add(&"weapon_pistol_g17", 1)

	var weapons := inv.get_carried_weapons()
	_check(weapons.size() == 2, "zwei Waffen im Inventar")

	var rifle := weapons[0]
	_check(inv.equip_weapon(rifle), "erste Waffe in die Hand genommen")
	_check(inv.equipped_weapon == rifle, "Waffe ist in der Hand")
	_check(inv.grid.get_stack(rifle.instance_id) == null, "und nicht mehr im Raster")
	_check(inv.get_carried_weapons().size() == 1, "eine Waffe bleibt im Raster")

	var pistol := inv.get_carried_weapons()[0]
	_check(inv.equip_weapon(pistol), "zweite Waffe in die Hand genommen")
	_check(inv.equipped_weapon == pistol, "Pistole ist in der Hand")
	_check(inv.grid.get_stack(rifle.instance_id) != null, "das Gewehr ist zurueck im Raster")

	# Nichts darf verloren gehen: beide Waffen sind noch da.
	var total := inv.get_carried_weapons().size() + (1 if inv.equipped_weapon != null else 0)
	_check(total == 2, "insgesamt weiterhin zwei Waffen (%d)" % total)

	# Das Gewicht muss die Waffe in der Hand mitzaehlen.
	_check(inv.get_total_weight() > 0.0, "Gewicht beruecksichtigt die gefuehrte Waffe (%.2f kg)" % inv.get_total_weight())

	inv.free()


## Beim Munitionswechsel muessen die Patronen aus dem Magazin zurueck
## ins Inventar — sonst verliert der Spieler bei jedem Wechsel Munition.
func _test_ammo_switch_returns_rounds() -> void:
	_section("Munitionswechsel")

	# Die echte Szene verwenden statt den Spieler von Hand zusammenzusetzen:
	# @onready sucht feste Knotenpfade (CameraPivot, Muzzle/AudioStreamPlayer3D)
	# und ueberschreibt sonst nach _ready alles mit null.
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	var player: PlayerController = packed.instantiate()
	root.add_child(player)
	await process_frame

	var inv := player.inventory
	var weapon := player.weapon
	_check(inv != null and weapon != null, "Spielerszene liefert Inventar und Waffe")
	if inv == null or weapon == null:
		player.free()
		return

	inv.add(&"ammo_556x45_m855a1", 60)
	inv.add(&"ammo_556x45_m995", 30)
	weapon.setup(&"weapon_rifle_ar15", &"ammo_556x45_m855a1")

	_check(weapon.rounds_in_magazine == 0, "Waffe startet leer")

	var loaded := player.try_reload()
	_check(loaded == 30, "Nachladen zieht 30 Patronen (%d)" % loaded)
	_check(weapon.rounds_in_magazine == 30, "Magazin ist voll")
	_check(inv.count_ammo(&"ammo_556x45_m855a1") == 30, "Inventar hat 30 weniger")

	# Jetzt auf M995 wechseln: die 30 M855A1 muessen zurueck.
	_check(player.switch_ammo(&"ammo_556x45_m995"), "Wechsel auf M995 gelingt")
	_check(inv.count_ammo(&"ammo_556x45_m855a1") == 60, "die geladenen Patronen sind zurueck im Inventar")
	_check(weapon.ammo_id == &"ammo_556x45_m995", "M995 ist geladen")
	_check(weapon.rounds_in_magazine == 30, "Magazin mit M995 gefuellt")
	_check(inv.count_ammo(&"ammo_556x45_m995") == 0, "M995-Vorrat aufgebraucht")

	# Falsches Kaliber muss abgelehnt werden.
	_check(not player.switch_ammo(&"ammo_762x39_ps"), "falsches Kaliber wird abgelehnt")

	# Teilweise nachladen, wenn nicht genug da ist.
	weapon.rounds_in_magazine = 0
	inv.add(&"ammo_556x45_m995", 7)
	var partial := player.try_reload()
	_check(partial == 7, "halb gefuelltes Magazin bei knapper Munition (%d)" % partial)

	player.free()


## Der Gesamtdurchlauf im echten Level.
func _test_in_level() -> void:
	_section("Testgelaende mit Startausruestung")

	var packed: PackedScene = load("res://scenes/levels/testgelaende.tscn")
	if packed == null:
		_check(false, "Testgelaende laedt")
		return

	var level: Node = packed.instantiate()
	root.add_child(level)
	await process_frame

	var player := level.get_node_or_null("Player") as PlayerController
	_check(player != null, "Spieler gefunden")
	if player == null:
		return

	_check(player.inventory != null, "Spieler hat ein Inventar")

	# Die komplette Startausruestung muss ins Raster passen. Eine Waffe ist
	# in der Hand, also liegt ein Eintrag weniger im Raster. Ohne diese
	# Pruefung geht Ausruestung still verloren, wenn das Raster zu klein ist.
	var level_script: GDScript = level.get_script()
	var loadout: Array = level_script.get("LOADOUT")
	var expected: int = loadout.size() - 1
	var actual := player.inventory.grid.get_item_count()
	_check(actual == expected,
		"komplette Startausruestung passt ins Raster (%d von %d)" % [actual, expected])
	_check(player.inventory.equipped_weapon != null, "eine Waffe ist in der Hand")
	_check(player.weapon.rounds_in_magazine > 0, "die Waffe ist geladen (%d)" % player.weapon.rounds_in_magazine)

	# Das Gewicht muss automatisch aus dem Inventar kommen.
	_check(player.carried_weight_kg > 0.0,
		"Traglast kommt aus dem Inventar (%.2f kg)" % player.carried_weight_kg)
	_check(player.get_weight_factor() < 1.0,
		"volle Ausruestung bremst spuerbar (Faktor %.2f)" % player.get_weight_factor())

	# Schiessen muss Munition verbrauchen, aber nicht den Inventarvorrat.
	var magazine_before := player.weapon.rounds_in_magazine
	var supply_before := player.inventory.count_ammo(player.weapon.ammo_id)
	player.weapon._shoot()
	_check(player.weapon.rounds_in_magazine == magazine_before - 1, "Schuss leert das Magazin")
	_check(player.inventory.count_ammo(player.weapon.ammo_id) == supply_before,
		"Schiessen greift nicht direkt auf den Vorrat zu")

	# Leerschiessen und nachladen bis der Vorrat alle ist.
	player.weapon.rounds_in_magazine = 0
	var total_supply := player.inventory.count_ammo(player.weapon.ammo_id)
	var reloads := 0
	while player.try_reload() > 0 and reloads < 50:
		player.weapon.rounds_in_magazine = 0
		reloads += 1
	_check(reloads > 0, "konnte %d mal nachladen" % reloads)
	_check(player.inventory.count_ammo(player.weapon.ammo_id) == 0,
		"Vorrat ist irgendwann wirklich leer (war %d)" % total_supply)
	_check(player.try_reload() == 0, "ohne Vorrat laesst sich nicht nachladen")

	# Gewicht muss beim Verbrauch sinken — leergeschossen ist man schneller.
	var weight_empty := player.carried_weight_kg
	player.inventory.add(&"ammo_556x45_m855a1", 60)
	_check(player.carried_weight_kg > weight_empty,
		"neue Munition erhoeht das Gewicht (%.2f -> %.2f kg)" % [weight_empty, player.carried_weight_kg])

	level.free()
