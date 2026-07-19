## PrÃ¼ft das Raster-Inventar ohne Editor und ohne UI.
##
##   godot --headless --path . --import --quit-after 120
##   godot --headless --path . --script res://tests/verify_inventory.gd
##
## Exitcode 0 = alles in Ordnung, 1 = mindestens ein Test fehlgeschlagen.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Raster-Inventar prÃ¼fen ===")
	print("(%d Item-Vorlagen geladen)\n" % ItemRegistry.get_count())
	_test_basic_placement()
	_test_no_overlap()
	_test_bounds()
	_test_rotation()
	_test_auto_stacking()
	_test_move_onto_self()
	_test_nested_container()
	_test_weight()
	_test_serialization()
	_test_grid_full()

	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK    ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


## Ein 5x2-Gewehr muss genau 10 Felder belegen, nicht mehr und nicht weniger.
func _test_basic_placement() -> void:
	_section("Grundlegendes Platzieren")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")

	_check(grid.place(rifle, 0, 0), "Gewehr passt auf (0,0)")
	_check(grid.get_free_cell_count() == 60 - 10, "belegt genau 10 Felder")
	_check(grid.get_stack_at(4, 1) == rifle, "rechte untere Ecke gehÃ¶rt zum Gewehr")
	_check(grid.get_stack_at(5, 0) == null, "Feld daneben ist frei")
	_check(grid.get_position(rifle.instance_id) == Vector2i(0, 0), "Position wird gemerkt")


## Der hÃ¤ufigste Fehler in Rasterinventaren: Items Ã¼berlappen sich.
func _test_no_overlap() -> void:
	_section("Ãœberlappung verhindern")
	var grid := InventoryGrid.new(10, 6)
	var a := ItemStack.create(&"weapon_rifle_ar15")
	var b := ItemStack.create(&"weapon_rifle_ar15")

	grid.place(a, 0, 0)
	_check(not grid.place(b, 0, 0), "exakt Ã¼bereinander wird abgelehnt")
	_check(not grid.place(b, 4, 1), "teilweise Ãœberlappung wird abgelehnt")
	_check(not grid.place(b, 2, 0), "Ãœberlappung in der Mitte wird abgelehnt")
	_check(grid.place(b, 5, 0), "direkt daneben ist erlaubt")
	_check(grid.get_item_count() == 2, "beide Gewehre sind drin")


## Items dÃ¼rfen nicht Ã¼ber den Rand hinausragen.
func _test_bounds() -> void:
	_section("RasterrÃ¤nder")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")

	_check(not grid.place(rifle, 6, 0), "ragt rechts heraus -> abgelehnt")
	_check(not grid.place(rifle, 0, 5), "ragt unten heraus -> abgelehnt")
	_check(not grid.place(rifle, -1, 0), "negative Position -> abgelehnt")
	_check(grid.place(rifle, 5, 4), "genau bÃ¼ndig am Rand -> erlaubt")


func _test_rotation() -> void:
	_section("Drehen")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	grid.place(rifle, 0, 0)

	_check(rifle.get_size() == Vector2i(5, 2), "ungedreht 5x2")
	_check(grid.rotate_item(rifle.instance_id), "Drehen gelingt")
	_check(rifle.get_size() == Vector2i(2, 5), "gedreht 2x5")
	_check(grid.get_free_cell_count() == 50, "belegt weiterhin 10 Felder")
	_check(grid.get_stack_at(1, 4) == rifle, "Feld unten gehÃ¶rt jetzt zum Gewehr")
	_check(grid.get_stack_at(4, 0) == null, "Feld rechts ist wieder frei")

	# Platte darf sich laut Vorlage nicht drehen.
	var plate := ItemStack.create(&"plate_class4_front")
	grid.place(plate, 6, 0)
	_check(not grid.rotate_item(plate.instance_id), "nicht drehbare Platte bleibt ungedreht")

	# Drehen muss scheitern, wenn kein Platz da ist â€” und dann sauber zurÃ¼ckrollen.
	var narrow := InventoryGrid.new(5, 2)
	var r2 := ItemStack.create(&"weapon_rifle_ar15")
	narrow.place(r2, 0, 0)
	var before := r2.rotated
	_check(not narrow.rotate_item(r2.instance_id), "Drehen ohne Platz scheitert")
	_check(r2.rotated == before, "Zustand nach Fehlschlag unverÃ¤ndert")
	_check(narrow.get_stack_at(4, 1) == r2, "Item liegt danach noch korrekt")


## Patronen sollen sich stapeln statt 60 Einzelfelder zu belegen.
func _test_auto_stacking() -> void:
	_section("Automatisches Stapeln")
	var grid := InventoryGrid.new(4, 4)

	grid.add_item(ItemStack.create(&"ammo_556x45_m995", 30))
	grid.add_item(ItemStack.create(&"ammo_556x45_m995", 20))
	_check(grid.get_item_count() == 1, "zwei Lieferungen landen auf einem Stapel")
	_check(grid.count_items(&"ammo_556x45_m995") == 50, "Gesamtmenge stimmt (50)")

	# max_stack ist 60 -> der Rest muss einen neuen Stapel aufmachen.
	grid.add_item(ItemStack.create(&"ammo_556x45_m995", 30))
	_check(grid.get_item_count() == 2, "Ãœberschuss beginnt neuen Stapel")
	_check(grid.count_items(&"ammo_556x45_m995") == 80, "Gesamtmenge stimmt (80)")

	# Unterschiedliche Munition darf NICHT vermischt werden.
	grid.add_item(ItemStack.create(&"ammo_556x45_m855a1", 10))
	_check(grid.count_items(&"ammo_556x45_m995") == 80, "M995 unverÃ¤ndert")
	_check(grid.count_items(&"ammo_556x45_m855a1") == 10, "M855A1 getrennt gezÃ¤hlt")

	# Platten haben individuelle Haltbarkeit und dÃ¼rfen nie stapeln.
	var g2 := InventoryGrid.new(6, 6)
	g2.add_item(ItemStack.create(&"plate_class4_front"))
	g2.add_item(ItemStack.create(&"plate_class4_front"))
	_check(g2.get_item_count() == 2, "Platten stapeln nicht (eigene Haltbarkeit)")


## Ein Item um ein Feld verschieben darf nicht an sich selbst scheitern.
func _test_move_onto_self() -> void:
	_section("Verschieben")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	grid.place(rifle, 0, 0)

	_check(grid.move_item(rifle.instance_id, 1, 0), "ein Feld nach rechts (Ã¼berlappt sich selbst)")
	_check(grid.get_position(rifle.instance_id) == Vector2i(1, 0), "neue Position stimmt")
	_check(grid.get_stack_at(0, 0) == null, "altes Feld wurde freigegeben")
	_check(grid.get_free_cell_count() == 50, "immer noch 10 Felder belegt")

	_check(not grid.move_item(rifle.instance_id, 8, 0), "Verschieben Ã¼ber den Rand scheitert")
	_check(grid.get_position(rifle.instance_id) == Vector2i(1, 0), "Position nach Fehlschlag unverÃ¤ndert")


func _test_nested_container() -> void:
	_section("Verschachtelte Container")
	var grid := InventoryGrid.new(10, 6)
	var backpack := ItemStack.create(&"backpack_small")

	_check(backpack.container != null, "Rucksack hat ein Innenraster")
	_check(backpack.container.width == 5 and backpack.container.height == 4, "Innenraster ist 5x4")

	grid.place(backpack, 0, 0)
	backpack.container.add_item(ItemStack.create(&"ammo_556x45_m995", 60))
	backpack.container.add_item(ItemStack.create(&"plate_class4_front"))

	_check(backpack.container.get_item_count() == 2, "zwei GegenstÃ¤nde im Rucksack")
	_check(grid.get_item_count() == 1, "Aussenraster sieht nur den Rucksack")
	_check(grid.count_items(&"ammo_556x45_m995", true) == 60, "verschachtelt gezÃ¤hlt: 60 Patronen")
	_check(grid.count_items(&"ammo_556x45_m995", false) == 0, "ohne Verschachtelung: 0")


func _test_weight() -> void:
	_section("Gewicht")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	grid.place(rifle, 0, 0)
	_check(is_equal_approx(grid.get_total_weight(), 3.1), "Gewehr wiegt 3.1 kg")

	# 60 Patronen a 0.013 kg = 0.78 kg
	var ammo := ItemStack.create(&"ammo_556x45_m995", 60)
	grid.add_item(ammo)
	_check(is_equal_approx(grid.get_total_weight(), 3.1 + 0.78), "Munition zÃ¤hlt mit StÃ¼ckzahl")

	# Ein voller Rucksack muss schwerer sein als ein leerer.
	var g2 := InventoryGrid.new(10, 6)
	var backpack := ItemStack.create(&"backpack_small")
	g2.place(backpack, 0, 0)
	var empty_weight := g2.get_total_weight()
	backpack.container.add_item(ItemStack.create(&"plate_class4_front"))
	var full_weight := g2.get_total_weight()
	_check(is_equal_approx(empty_weight, 1.2), "leerer Rucksack wiegt 1.2 kg")
	_check(is_equal_approx(full_weight, 1.2 + 3.4), "Inhalt zÃ¤hlt zum Gewicht dazu")


## Speichern und Laden muss alles erhalten â€” sonst gehen beim Autosave
## Fortschritt, Haltbarkeit oder Rucksackinhalte verloren.
func _test_serialization() -> void:
	_section("Speichern und Laden")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	grid.place(rifle, 2, 1)
	grid.rotate_item(rifle.instance_id)

	var backpack := ItemStack.create(&"backpack_small")
	grid.place(backpack, 5, 0)
	backpack.container.add_item(ItemStack.create(&"ammo_556x45_m855a1", 42))

	var plate := ItemStack.create(&"plate_class4_front")
	plate.durability = 17.5
	grid.add_item(plate)

	var restored := InventoryGrid.from_dict(grid.to_dict())

	_check(restored.get_item_count() == grid.get_item_count(), "gleiche Anzahl GegenstÃ¤nde")
	_check(is_equal_approx(restored.get_total_weight(), grid.get_total_weight()), "Gewicht identisch")
	_check(restored.count_items(&"ammo_556x45_m855a1", true) == 42, "Rucksackinhalt Ã¼berlebt")

	var restored_rifle := restored.get_stack(rifle.instance_id)
	_check(restored_rifle != null, "Gewehr Ã¼ber instance_id wiederfindbar")
	_check(restored_rifle != null and restored_rifle.rotated, "Drehung bleibt erhalten")
	_check(restored.get_position(rifle.instance_id) == Vector2i(2, 1), "Position bleibt erhalten")

	var restored_plate := restored.get_stack(plate.instance_id)
	_check(restored_plate != null and is_equal_approx(restored_plate.durability, 17.5), "Haltbarkeit bleibt erhalten")


## Volles Inventar darf nichts mehr annehmen und nichts stillschweigend schlucken.
func _test_grid_full() -> void:
	_section("Volles Inventar")
	var grid := InventoryGrid.new(2, 3)
	var plate := ItemStack.create(&"plate_class4_front")

	_check(grid.add_item(plate), "erste Platte passt genau")
	_check(grid.get_free_cell_count() == 0, "Raster ist voll")

	var second := ItemStack.create(&"plate_class4_front")
	_check(not grid.add_item(second), "zweite Platte wird abgelehnt")
	_check(grid.get_item_count() == 1, "nichts wurde stillschweigend verschluckt")

	# Nach dem Herausnehmen muss wieder Platz sein.
	var taken := grid.remove_item(plate.instance_id)
	_check(taken == plate, "Herausnehmen liefert das Item zurÃ¼ck")
	_check(grid.get_free_cell_count() == 6, "Felder sind wieder frei")
	_check(grid.add_item(second), "jetzt passt die zweite Platte")

