## Prüft das Raster-Inventar ohne Editor und ohne UI.
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
	# Platte, Rucksack und Kleidung gibt es im Spiel gerade nicht mehr.
	TestItems.install()
	print("=== Raster-Inventar prüfen ===")
	print("(%d Item-Vorlagen geladen)\n" % ItemRegistry.get_count())
	_test_basic_placement()
	_test_no_overlap()
	_test_bounds()
	_test_rotation()
	_test_auto_stacking()
	_test_move_onto_self()
	_test_rotation_from_outside()
	_test_place_or_merge()
	_test_splitting()
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
	_check(grid.get_stack_at(4, 1) == rifle, "rechte untere Ecke gehört zum Gewehr")
	_check(grid.get_stack_at(5, 0) == null, "Feld daneben ist frei")
	_check(grid.get_position(rifle.instance_id) == Vector2i(0, 0), "Position wird gemerkt")


## Der häufigste Fehler in Rasterinventaren: Items überlappen sich.
func _test_no_overlap() -> void:
	_section("Überlappung verhindern")
	var grid := InventoryGrid.new(10, 6)
	var a := ItemStack.create(&"weapon_rifle_ar15")
	var b := ItemStack.create(&"weapon_rifle_ar15")

	grid.place(a, 0, 0)
	_check(not grid.place(b, 0, 0), "exakt übereinander wird abgelehnt")
	_check(not grid.place(b, 4, 1), "teilweise Überlappung wird abgelehnt")
	_check(not grid.place(b, 2, 0), "Überlappung in der Mitte wird abgelehnt")
	_check(grid.place(b, 5, 0), "direkt daneben ist erlaubt")
	_check(grid.get_item_count() == 2, "beide Gewehre sind drin")


## Items dürfen nicht über den Rand hinausragen.
func _test_bounds() -> void:
	_section("Rasterränder")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")

	_check(not grid.place(rifle, 6, 0), "ragt rechts heraus -> abgelehnt")
	_check(not grid.place(rifle, 0, 5), "ragt unten heraus -> abgelehnt")
	_check(not grid.place(rifle, -1, 0), "negative Position -> abgelehnt")
	_check(grid.place(rifle, 5, 4), "genau bündig am Rand -> erlaubt")


func _test_rotation() -> void:
	_section("Drehen")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	grid.place(rifle, 0, 0)

	_check(rifle.get_size() == Vector2i(5, 2), "ungedreht 5x2")
	_check(grid.rotate_item(rifle.instance_id), "Drehen gelingt")
	_check(rifle.get_size() == Vector2i(2, 5), "gedreht 2x5")
	_check(grid.get_free_cell_count() == 50, "belegt weiterhin 10 Felder")
	_check(grid.get_stack_at(1, 4) == rifle, "Feld unten gehört jetzt zum Gewehr")
	_check(grid.get_stack_at(4, 0) == null, "Feld rechts ist wieder frei")

	# Ein Rucksack darf sich laut Vorlage nicht drehen — er wird getragen,
	# nicht verstaut. (Die Schutzplatte war hier frueher das Beispiel; sie
	# ist inzwischen drehbar, weil sie im Rucksack quer liegen darf.)
	var pack := ItemStack.create(&"backpack_small")
	grid.place(pack, 6, 0)
	_check(not grid.rotate_item(pack.instance_id), "nicht drehbarer Rucksack bleibt ungedreht")

	# Und die Platte muss sich jetzt umgekehrt WIRKLICH drehen lassen.
	var plate_grid := InventoryGrid.new(6, 6)
	var plate := ItemStack.create(&"plate_class4_front")
	plate_grid.place(plate, 0, 0)
	_check(plate_grid.rotate_item(plate.instance_id), "Schutzplatte laesst sich drehen")
	_check(plate.get_size() == Vector2i(3, 2), "und liegt dann quer (3x2)")

	# Drehen muss scheitern, wenn kein Platz da ist — und dann sauber zurückrollen.
	var narrow := InventoryGrid.new(5, 2)
	var r2 := ItemStack.create(&"weapon_rifle_ar15")
	narrow.place(r2, 0, 0)
	var before := r2.rotated
	_check(not narrow.rotate_item(r2.instance_id), "Drehen ohne Platz scheitert")
	_check(r2.rotated == before, "Zustand nach Fehlschlag unverändert")
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
	_check(grid.get_item_count() == 2, "Überschuss beginnt neuen Stapel")
	_check(grid.count_items(&"ammo_556x45_m995") == 80, "Gesamtmenge stimmt (80)")

	# Unterschiedliche Munition darf NICHT vermischt werden.
	grid.add_item(ItemStack.create(&"ammo_556x45_m855a1", 10))
	_check(grid.count_items(&"ammo_556x45_m995") == 80, "M995 unverändert")
	_check(grid.count_items(&"ammo_556x45_m855a1") == 10, "M855A1 getrennt gezählt")

	# Platten haben individuelle Haltbarkeit und dürfen nie stapeln.
	var g2 := InventoryGrid.new(6, 6)
	g2.add_item(ItemStack.create(&"plate_class4_front"))
	g2.add_item(ItemStack.create(&"plate_class4_front"))
	_check(g2.get_item_count() == 2, "Platten stapeln nicht (eigene Haltbarkeit)")


## Das Raster muss genau die Felder freigeben, die es belegt hat — auch
## wenn der Gegenstand von aussen gedreht wurde, waehrend er darin lag.
##
## GEFUNDEN IM SPIEL, NICHT IM TEST: Beim Ziehen dreht R den Gegenstand,
## der dabei noch im Ursprungsraster liegt. remove_item() raeumte danach
## mit der NEUEN Flaeche frei — ein 5x2-Gewehr wurde als 2x5 freigegeben
## und lief aus dem Raster heraus ("Out of bounds set index 25").
##
## Die Tests waren gruen, weil die Faelle dort zufaellig im Raster blieben.
func _test_rotation_from_outside() -> void:
	_section("Drehen von aussen")

	var grid := InventoryGrid.new(10, 8)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	_check(grid.place(rifle, 4, 5), "Gewehr 5x2 liegt bei (4,5)")

	var free_before := grid.get_free_cell_count()

	# So macht es das Loot-Fenster beim Ziehen: einfach umschalten.
	rifle.rotated = not rifle.rotated
	_check(rifle.get_size() == Vector2i(2, 5), "gedreht ist es 2x5")

	# Bei (4,5) waere 2x5 weit ausserhalb — genau hier kam der Absturz.
	var removed := grid.remove_item(rifle.instance_id)
	_check(removed != null, "es laesst sich trotzdem herausnehmen")
	_check(grid.get_free_cell_count() == free_before + 10,
		"und gibt genau seine 10 alten Felder frei (%d)" % grid.get_free_cell_count())
	_check(grid.get_item_count() == 0, "das Raster ist danach leer")

	# Das Raster muss weiter benutzbar sein: keine Geisterfelder.
	var second := ItemStack.create(&"weapon_rifle_ar15")
	_check(grid.place(second, 4, 5), "an derselben Stelle passt wieder eines hin")

	# Auch das Verschieben eines von aussen gedrehten Gegenstands.
	second.rotated = true
	_check(grid.move_item(second.instance_id, 0, 0), "gedreht laesst es sich verschieben")
	_check(grid.get_position(second.instance_id) == Vector2i(0, 0), "und liegt bei (0,0)")
	_check(grid.get_stack_at(1, 4) == second, "belegt jetzt wirklich 2x5")
	_check(grid.get_stack_at(4, 1) == null, "und nicht mehr die alten Felder")


## Gezieltes Ablegen auf ein belegtes Feld: die Maus zeigt genau dorthin,
## und der Spieler erwartet, dass aufgestapelt wird statt abzuprallen.
func _test_place_or_merge() -> void:
	_section("Stapeln beim Ablegen")
	var grid := InventoryGrid.new(6, 6)

	var base := ItemStack.create(&"ammo_556x45_m995", 20)
	grid.place(base, 0, 0)

	var extra := ItemStack.create(&"ammo_556x45_m995", 15)
	_check(grid.can_place_or_merge(extra, 0, 0), "belegtes Feld gilt als gueltiges Ziel")
	_check(grid.place_or_merge(extra, 0, 0) == null, "alles wandert auf den Stapel")
	_check(base.quantity == 35, "Stapel ist gewachsen (35)")
	_check(grid.get_item_count() == 1, "kein zweiter Stapel entstanden")

	# max_stack ist 60: was drueber liegt, muss als Rest zurueckkommen —
	# stillschweigend verwerfen waere Diebstahl am Spieler.
	var zuviel := ItemStack.create(&"ammo_556x45_m995", 40)
	var rest := grid.place_or_merge(zuviel, 0, 0)
	_check(base.quantity == 60, "Stapel laeuft nur bis max_stack (60)")
	_check(rest != null and rest.quantity == 15, "der Rest kommt zurueck (15)")

	# Fremde Munition darf nicht auf den Stapel.
	var fremd := ItemStack.create(&"ammo_556x45_m855a1", 5)
	_check(not grid.can_place_or_merge(fremd, 0, 0), "andere Sorte stapelt nicht")

	# Platten haben eigene Haltbarkeit und duerfen nie verschmelzen.
	var g2 := InventoryGrid.new(6, 6)
	var platte := ItemStack.create(&"plate_class4_front")
	g2.place(platte, 0, 0)
	_check(not g2.can_place_or_merge(ItemStack.create(&"plate_class4_front"), 0, 0),
		"Platten stapeln auch beim gezielten Ablegen nicht")


## Strg + Ziehen teilt einen Stapel. Entscheidend ist, dass dabei die
## Gesamtmenge erhalten bleibt — sonst vermehrt oder vernichtet die
## Oberflaeche Munition.
func _test_splitting() -> void:
	_section("Stapel teilen")

	var stack := ItemStack.create(&"ammo_556x45_m995", 30)
	var part := stack.split(12)
	_check(part != null, "Teilen liefert einen neuen Stapel")
	_check(part.quantity == 12, "abgetrennte Menge stimmt (12)")
	_check(stack.quantity == 18, "Ursprungsstapel schrumpft (18)")
	_check(part.instance_id != stack.instance_id, "der Teil ist ein eigenes Exemplar")

	_check(stack.split(0) == null, "null Stueck abtrennen ist Unfug")
	_check(stack.split(18) == null, "den ganzen Stapel abtrennen ist Unfug")
	_check(stack.split(99) == null, "mehr als vorhanden abtrennen ist Unfug")
	_check(stack.quantity == 18, "gescheitertes Teilen laesst den Stapel unveraendert")

	# Der abgetrennte Teil muss sich wieder zusammenlegen lassen.
	var grid := InventoryGrid.new(6, 6)
	grid.place(stack, 0, 0)
	_check(grid.place_or_merge(part, 0, 0) == null, "Teil laesst sich zurueckstapeln")
	_check(stack.quantity == 30, "wieder vollstaendig (30)")


## Ein Item um ein Feld verschieben darf nicht an sich selbst scheitern.
func _test_move_onto_self() -> void:
	_section("Verschieben")
	var grid := InventoryGrid.new(10, 6)
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	grid.place(rifle, 0, 0)

	_check(grid.move_item(rifle.instance_id, 1, 0), "ein Feld nach rechts (überlappt sich selbst)")
	_check(grid.get_position(rifle.instance_id) == Vector2i(1, 0), "neue Position stimmt")
	_check(grid.get_stack_at(0, 0) == null, "altes Feld wurde freigegeben")
	_check(grid.get_free_cell_count() == 50, "immer noch 10 Felder belegt")

	_check(not grid.move_item(rifle.instance_id, 8, 0), "Verschieben über den Rand scheitert")
	_check(grid.get_position(rifle.instance_id) == Vector2i(1, 0), "Position nach Fehlschlag unverändert")


func _test_nested_container() -> void:
	_section("Verschachtelte Container")
	var grid := InventoryGrid.new(10, 6)
	var backpack := ItemStack.create(&"backpack_small")

	_check(backpack.container != null, "Rucksack hat ein Innenraster")
	_check(backpack.container.width == 5 and backpack.container.height == 4, "Innenraster ist 5x4")

	grid.place(backpack, 0, 0)
	backpack.container.add_item(ItemStack.create(&"ammo_556x45_m995", 60))
	backpack.container.add_item(ItemStack.create(&"plate_class4_front"))

	_check(backpack.container.get_item_count() == 2, "zwei Gegenstände im Rucksack")
	_check(grid.get_item_count() == 1, "Aussenraster sieht nur den Rucksack")
	_check(grid.count_items(&"ammo_556x45_m995", true) == 60, "verschachtelt gezählt: 60 Patronen")
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
	_check(is_equal_approx(grid.get_total_weight(), 3.1 + 0.78), "Munition zählt mit Stückzahl")

	# Ein voller Rucksack muss schwerer sein als ein leerer.
	var g2 := InventoryGrid.new(10, 6)
	var backpack := ItemStack.create(&"backpack_small")
	g2.place(backpack, 0, 0)
	var empty_weight := g2.get_total_weight()
	backpack.container.add_item(ItemStack.create(&"plate_class4_front"))
	var full_weight := g2.get_total_weight()
	_check(is_equal_approx(empty_weight, 1.2), "leerer Rucksack wiegt 1.2 kg")
	_check(is_equal_approx(full_weight, 1.2 + 3.4), "Inhalt zählt zum Gewicht dazu")


## Speichern und Laden muss alles erhalten — sonst gehen beim Autosave
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

	_check(restored.get_item_count() == grid.get_item_count(), "gleiche Anzahl Gegenstände")
	_check(is_equal_approx(restored.get_total_weight(), grid.get_total_weight()), "Gewicht identisch")
	_check(restored.count_items(&"ammo_556x45_m855a1", true) == 42, "Rucksackinhalt überlebt")

	var restored_rifle := restored.get_stack(rifle.instance_id)
	_check(restored_rifle != null, "Gewehr über instance_id wiederfindbar")
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
	_check(taken == plate, "Herausnehmen liefert das Item zurück")
	_check(grid.get_free_cell_count() == 6, "Felder sind wieder frei")
	_check(grid.add_item(second), "jetzt passt die zweite Platte")

