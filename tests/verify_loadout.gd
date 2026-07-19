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
	_test_weapon_cycling()
	_test_ammo_accounting()
	_test_weapon_switching_keeps_gear()
	await _test_ammo_switch_returns_rounds()
	await _test_in_level()
	_finish()


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


## Waffe ueber ihre ID holen statt ueber die Position in der Liste.
func _find_weapon(inv: PlayerInventory, id: StringName) -> ItemStack:
	for stack in inv.get_carried_weapons():
		if stack.item_id == id:
			return stack
	return null


func _make_inventory() -> PlayerInventory:
	var inv := PlayerInventory.new()
	root.add_child(inv)
	return inv


## Durchschalten mit Q/E muss jede Waffe genau einmal zeigen.
##
## Im Spiel kam die Glock zweimal hintereinander dran. Ursache: Die
## ausgeruestete Waffe wird beim Anlegen aus dem Raster genommen, und
## get_carried_weapons() las nur das Raster. Damit schrumpfte die Liste bei
## jedem Wechsel um eins und der Zaehler im Testgelaende zeigte daneben.
func _test_weapon_cycling() -> void:
	_section("Waffen durchschalten")

	var inv := _make_inventory()
	var ids: Array[StringName] = [&"weapon_rifle_ar15", &"weapon_shotgun_m870", &"weapon_pistol_g17"]
	for id in ids:
		inv.add(id, 1)

	var weapons := inv.get_carried_weapons()
	_check(weapons.size() == ids.size(),
		"alle %d Waffen werden aufgelistet (%d)" % [ids.size(), weapons.size()])

	inv.equip_weapon(weapons[0])
	_check(inv.get_carried_weapons().size() == ids.size(),
		"die Waffe in der Hand bleibt in der Liste (%d)" % inv.get_carried_weapons().size())

	# Einmal komplett durchschalten, so wie es das Testgelaende macht.
	var seen: Array[StringName] = []
	var index := 0
	for step in range(ids.size()):
		var list := inv.get_carried_weapons()
		index = wrapi(index + 1, 0, list.size())
		inv.equip_weapon(list[index])
		seen.append(inv.equipped_weapon.item_id)

	var unique := {}
	for id in seen:
		unique[id] = true
	_check(unique.size() == ids.size(),
		"jede Waffe kommt genau einmal dran (%s)" % str(seen))

	# Dieselbe Waffe nochmal anlegen darf sie nicht verdoppeln.
	var before := inv.get_carried_weapons().size()
	inv.equip_weapon(inv.equipped_weapon)
	_check(inv.get_carried_weapons().size() == before,
		"dieselbe Waffe erneut anlegen verdoppelt sie nicht (%d -> %d)"
			% [before, inv.get_carried_weapons().size()])

	inv.free()


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

	_check(inv.get_carried_weapons().size() == 2, "zwei Waffen im Inventar")

	# Waffen ueber ihre ID holen, nicht ueber die Position in der Liste:
	# Die Liste ist nach ID sortiert, und "weapons[0]" war deshalb schon
	# einmal stillschweigend die Pistole statt des Gewehrs.
	var rifle := _find_weapon(inv, &"weapon_rifle_ar15")
	var pistol := _find_weapon(inv, &"weapon_pistol_g17")
	_check(rifle != null and pistol != null, "Gewehr und Pistole gefunden")

	_check(inv.equip_weapon(rifle), "erste Waffe in die Hand genommen")
	_check(inv.equipped_weapon == rifle, "Waffe ist in der Hand")
	_check(inv.grid.get_stack(rifle.instance_id) == null, "und nicht mehr im Raster")
	_check(inv.grid.get_stack(pistol.instance_id) != null, "die andere liegt weiter im Raster")

	_check(inv.equip_weapon(pistol), "zweite Waffe in die Hand genommen")
	_check(inv.equipped_weapon == pistol, "Pistole ist in der Hand")
	_check(inv.grid.get_stack(rifle.instance_id) != null, "das Gewehr ist zurueck im Raster")

	# Nichts darf verloren gehen. get_carried_weapons() zaehlt die Waffe in
	# der Hand mit, deshalb ist die Gesamtzahl direkt die Listenlaenge.
	_check(inv.get_carried_weapons().size() == 2,
		"insgesamt weiterhin zwei Waffen (%d)" % inv.get_carried_weapons().size())

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
	# Eine der 30 Patronen sitzt im Lauf, nicht im Magazin — deshalb wird
	# hier die Gesamtzahl geprueft und nicht nur der Magazininhalt.
	_check(weapon.get_total_rounds() == 30, "Magazin ist voll")
	_check(inv.count_ammo(&"ammo_556x45_m855a1") == 30, "Inventar hat 30 weniger")

	# Jetzt auf M995 wechseln: die 30 M855A1 muessen zurueck.
	_check(player.switch_ammo(&"ammo_556x45_m995"), "Wechsel auf M995 gelingt")
	_check(inv.count_ammo(&"ammo_556x45_m855a1") == 60, "die geladenen Patronen sind zurueck im Inventar")
	_check(weapon.ammo_id == &"ammo_556x45_m995", "M995 ist geladen")
	_check(weapon.get_total_rounds() == 30, "Magazin mit M995 gefuellt")
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
	#
	# Geprueft wird die Gesamtzahl, nicht der Magazininhalt: Bei einer
	# Ladehemmung bleibt die naechste Patrone im Magazin stecken, statt in den
	# Lauf zu wandern. Der Magazininhalt aendert sich dann nicht — verbraucht
	# ist die Patrone trotzdem. Auf rounds_in_magazine geprueft war der Test
	# selten, aber zuverlaessig zufaellig rot.
	var total_before := player.weapon.get_total_rounds()
	var supply_before := player.inventory.count_ammo(player.weapon.ammo_id)
	player.weapon._shoot()
	_check(player.weapon.get_total_rounds() == total_before - 1,
		"Schuss verbraucht genau eine Patrone (%d -> %d)"
			% [total_before, player.weapon.get_total_rounds()])
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
