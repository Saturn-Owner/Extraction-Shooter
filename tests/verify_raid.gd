## Prüft die Kernschleife: looten, extrahieren, sterben.
##
##   godot --headless --path . --script res://tests/verify_raid.gd
##
## Der wichtigste Test des Projekts. Hier entscheidet sich, ob Beute wirklich
## sicher ist — und ob Verlust wirklich wehtut. Beides ist die Grundlage des
## Genres. Ein Fehler hier zerstört entweder die Spannung (kein echter
## Verlust) oder das Vertrauen (Ausrüstung verschwindet grundlos).
extends SceneTree

const TIMEOUT_SECONDS := 60.0

var _failed := 0
var _passed := 0
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Raid-Schleife pruefen ===\n")
	_run_all()


func _process(delta: float) -> bool:
	if _done:
		return false
	_elapsed += delta
	if _elapsed >= TIMEOUT_SECONDS:
		print("\n=== ABBRUCH: Test haengt seit %.0f s ===" % TIMEOUT_SECONDS)
		print("Bisher: %d bestanden, %d fehlgeschlagen" % [_passed, _failed])
		quit(1)
	return false


func _run_all() -> void:
	await process_frame
	_test_loot_tables_are_valid()
	_test_loot_distribution()
	await _test_container_search()
	await _test_extraction_secures_loot()
	await _test_death_loses_loot()
	await _test_locked_exit()
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


func _load_table(name: String) -> LootTableData:
	return load("res://assets/data/loot/%s.tres" % name) as LootTableData


## Ein Tippfehler in einer Item-ID darf nicht erst beim Oeffnen auffallen.
func _test_loot_tables_are_valid() -> void:
	_section("Loot-Tabellen")

	for name in ["wohnung", "werkstatt", "militaer"]:
		var table := _load_table(name)
		_check(table != null, "Tabelle '%s' laedt" % name)
		if table == null:
			continue
		var problems := table.validate()
		_check(problems.is_empty(), "'%s' ist fehlerfrei%s" % [
			name, "" if problems.is_empty() else ": " + ", ".join(problems)])


## Die Tabellen muessen sich wirklich unterscheiden, sonst lohnt sich der
## Weg ins Militaerlager nicht.
func _test_loot_distribution() -> void:
	_section("Loot-Verteilung")

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var rare := [&"ammo_556x45_m995", &"ammo_762x51_m61", &"ammo_545x39_bs"]
	var counts := {}

	for name in ["wohnung", "werkstatt", "militaer"]:
		var table := _load_table(name)
		if table == null:
			continue

		var total_items := 0
		var rare_items := 0
		var empty_rolls := 0

		for i in range(400):
			var drops := table.roll(rng)
			if drops.is_empty():
				empty_rolls += 1
			for drop in drops:
				total_items += 1
				if rare.has(drop.id):
					rare_items += 1

		counts[name] = {"total": total_items, "rare": rare_items}
		print("  %-10s %4d Funde in 400 Zuegen, davon %d selten, %d mal komplett leer"
			% [name, total_items, rare_items, empty_rolls])

		_check(total_items > 0, "'%s' liefert ueberhaupt Loot" % name)

	# Militaer muss mehr hergeben als eine Wohnung — sonst gibt es keinen
	# Grund, das Risiko einzugehen.
	if counts.has("wohnung") and counts.has("militaer"):
		_check(counts["militaer"]["total"] > counts["wohnung"]["total"],
			"Militaerkisten geben mehr her als Wohnungen (%d vs %d)"
			% [counts["militaer"]["total"], counts["wohnung"]["total"]])
		_check(counts["militaer"]["rare"] > counts["wohnung"]["rare"],
			"seltene Munition kommt fast nur aus dem Militaer (%d vs %d)"
			% [counts["militaer"]["rare"], counts["wohnung"]["rare"]])


func _test_container_search() -> void:
	_section("Container durchsuchen")

	var container := LootContainer.new()
	container.loot_table = _load_table("militaer")
	container.search_time = 0.05
	root.add_child(container)
	await process_frame
	container.set_seed(777)

	_check(not container.is_searched, "Container startet undurchsucht")
	_check(container.is_empty(), "und ohne Inhalt — erst beim Oeffnen gewuerfelt")

	_check(container.begin_search(), "Durchsuchen startet")
	_check(container.is_being_searched, "laeuft")

	# Abbrechen darf keinen Inhalt erzeugen.
	container.cancel_search()
	_check(not container.is_being_searched, "Abbrechen stoppt das Durchsuchen")
	_check(container.is_empty(), "abgebrochenes Durchsuchen erzeugt keinen Loot")

	container.begin_search()
	var waited := 0
	while container.is_being_searched and waited < 60:
		await process_frame
		waited += 1

	_check(container.is_searched, "Durchsuchen wird fertig")
	_check(not container.is_empty(), "Container hat jetzt Inhalt (%d Gegenstaende)" % container.contents.get_item_count())

	# Entnehmen in ein volles Inventar darf nichts vernichten.
	var tiny := InventoryGrid.new(1, 1)
	var before := container.contents.get_item_count()
	var stacks := container.contents.get_all_stacks()
	var big := stacks[0]
	for s in stacks:
		if s.get_size().x * s.get_size().y > big.get_size().x * big.get_size().y:
			big = s

	if big.get_size().x > 1 or big.get_size().y > 1:
		_check(not container.take_item(big.instance_id, tiny), "zu grosser Gegenstand passt nicht ins Minirad")
		_check(container.contents.get_item_count() == before, "und bleibt im Container liegen")

	container.free()


func _make_player() -> PlayerController:
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	var player: PlayerController = packed.instantiate()
	root.add_child(player)
	return player


func _make_raid(player: PlayerController) -> RaidManager:
	var raid := RaidManager.new()
	root.add_child(raid)
	raid.setup(player)
	return raid


## Die zentrale Zusage des Genres: Wer rauskommt, behaelt alles.
func _test_extraction_secures_loot() -> void:
	_section("Erfolgreiche Extraction")

	var player := _make_player()
	await process_frame
	var raid := _make_raid(player)

	player.inventory.add(&"weapon_rifle_ar15", 1)
	player.inventory.add(&"ammo_556x45_m995", 30)
	player.inventory.add(&"plate_class4_front", 1)
	var weapons := player.inventory.get_carried_weapons()
	player.equip_from_inventory(weapons[0])

	raid.start_raid()
	var carried := raid.get_items_taken_in()
	_check(carried > 0, "Spieler startet mit Ausruestung (%d Gegenstaende)" % carried)
	_check(raid.stash.get_item_count() == 0, "Lager ist zu Beginn leer")

	# Beim Ausruesten wandert Munition ins Magazin. Genau diese Patronen
	# gingen frueher bei der Extraction verloren.
	var in_magazine := player.weapon.rounds_in_magazine
	_check(in_magazine > 0, "Munition steckt im Magazin (%d)" % in_magazine)

	var secured := raid.extract()
	_check(secured > 0, "Extraction sichert Gegenstaende (%d)" % secured)
	_check(raid.stash.count_items(&"ammo_556x45_m995", true) == 30,
		"die Munition liegt vollstaendig im Lager — auch die aus dem Magazin (%d)"
		% raid.stash.count_items(&"ammo_556x45_m995", true))
	_check(player.weapon.rounds_in_magazine == 0, "das Magazin ist entladen")
	_check(raid.stash.count_items(&"weapon_rifle_ar15", true) == 1,
		"auch die gefuehrte Waffe ist im Lager")
	_check(player.inventory.grid.get_item_count() == 0, "der Spieler traegt nichts mehr")
	_check(player.inventory.equipped_weapon == null, "und hat keine Waffe mehr in der Hand")

	raid.free()
	player.free()


## Die andere Haelfte der Zusage: Wer stirbt, verliert alles Mitgefuehrte —
## aber niemals das Lager.
func _test_death_loses_loot() -> void:
	_section("Tod im Raid")

	var player := _make_player()
	await process_frame
	var raid := _make_raid(player)

	# Erst einen erfolgreichen Raid, damit etwas im Lager liegt.
	player.inventory.add(&"ammo_556x45_m995", 30)
	raid.start_raid()
	raid.extract()
	var stash_before := raid.stash.get_item_count()
	_check(stash_before > 0, "Lager gefuellt (%d Gegenstaende)" % stash_before)

	# Zweiter Raid, diesmal toedlich.
	player.inventory.add(&"weapon_rifle_ar15", 1)
	player.inventory.add(&"ammo_762x51_m61", 20)
	var weapons := player.inventory.get_carried_weapons()
	player.equip_from_inventory(weapons[0])

	raid.start_raid()
	_check(player.inventory.grid.get_item_count() > 0, "Spieler hat Beute dabei")

	raid.die()
	_check(player.inventory.grid.get_item_count() == 0, "nach dem Tod ist das Inventar leer")
	_check(player.inventory.equipped_weapon == null, "die gefuehrte Waffe ist weg")
	_check(raid.stash.get_item_count() == stash_before,
		"das LAGER bleibt unangetastet (%d)" % raid.stash.get_item_count())
	_check(raid.stash.count_items(&"ammo_556x45_m995", true) == 30,
		"frueher gesicherte Munition ist noch da")

	# Nach dem Tod aus dem Lager neu ausruesten.
	var moved := raid.equip_from_stash([&"ammo_556x45_m995"])
	_check(moved == 1, "Ausruesten aus dem Lager funktioniert")
	_check(player.inventory.count_ammo(&"ammo_556x45_m995") == 30, "die Munition ist wieder am Mann")
	_check(raid.stash.count_items(&"ammo_556x45_m995", true) == 0, "und nicht mehr im Lager")

	raid.free()
	player.free()


## Ausgaenge mit Ausruestungsbedingung — der Eispickel aus dem Konzept.
func _test_locked_exit() -> void:
	_section("Ausgang mit Bedingung")

	var player := _make_player()
	await process_frame

	var zone := ExtractionZone.new()
	zone.required_item_id = &"backpack_small"
	zone.display_name = "Vereiste Klippe"
	root.add_child(zone)

	_check(not zone.can_use(player), "ohne das noetige Item gesperrt")
	_check(zone.get_block_reason(player) != "", "Grund wird angezeigt: '%s'" % zone.get_block_reason(player))

	player.inventory.add(&"backpack_small", 1)
	_check(zone.can_use(player), "mit dem Item nutzbar")
	_check(zone.get_block_reason(player) == "", "kein Hinderungsgrund mehr")

	# Geschlossener Ausgang bleibt gesperrt, auch mit Item.
	zone.is_open = false
	_check(zone.get_block_reason(player) == "geschlossen", "geschlossener Ausgang meldet das")

	zone.free()
	player.free()
