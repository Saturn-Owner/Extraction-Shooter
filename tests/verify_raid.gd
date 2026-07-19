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
	_test_search_times_scale()
	await _test_container_search()
	await _test_hidden_items_are_untouchable()
	await _test_drag_between_grids()
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


## Die Durchsuchzeit muss sich pro Gegenstand unterscheiden — das ist der
## Kern des Arena-Breakout-Modells.
func _test_search_times_scale() -> void:
	_section("Durchsuchzeit pro Gegenstand")

	var ammo := ItemRegistry.get_item(&"ammo_9x19_fmj")
	var rare_ammo := ItemRegistry.get_item(&"ammo_556x45_m995")
	var plate := ItemRegistry.get_item(&"plate_class4_front")
	var rifle := ItemRegistry.get_item(&"weapon_rifle_ar15")

	if ammo == null or rare_ammo == null or plate == null or rifle == null:
		_check(false, "Vergleichsgegenstaende gefunden")
		return

	var t_ammo := ammo.get_search_time()
	var t_rare := rare_ammo.get_search_time()
	var t_plate := plate.get_search_time()
	var t_rifle := rifle.get_search_time()

	print("  9mm %.2fs | M995 %.2fs | Platte %.2fs | AR-15 %.2fs"
		% [t_ammo, t_rare, t_plate, t_rifle])

	_check(t_rare > t_ammo, "seltene Munition dauert laenger als billige (gleiche Groesse)")
	_check(t_rifle > t_plate, "das Gewehr dauert am laengsten")
	_check(t_plate > t_rare, "die grosse Platte dauert laenger als eine Patrone")
	_check(t_ammo >= 0.4, "auch das Kleinste braucht spuerbar Zeit (%.2fs)" % t_ammo)
	_check(t_rifle <= 7.0, "nichts dauert unertraeglich lang (%.2fs)" % t_rifle)


func _test_container_search() -> void:
	_section("Container schrittweise durchsuchen")

	var container := LootContainer.new()
	container.loot_table = _load_table("militaer")
	# Stark beschleunigt, damit der Test nicht 20 Sekunden braucht.
	container.search_time_multiplier = 0.5
	root.add_child(container)
	await process_frame
	container.set_seed(777)

	_check(not container.is_open, "Container startet geschlossen")
	_check(container.is_empty(), "und ohne Inhalt — erst beim Oeffnen gewuerfelt")

	container.open()
	_check(container.is_open, "Container ist offen")
	_check(not container.is_empty(), "Inhalt wurde gewuerfelt (%d Gegenstaende)" % container.contents.get_item_count())
	_check(container.get_revealed_stacks().is_empty(),
		"aber noch NICHTS ist sichtbar — Gegenstaende tauchen einzeln auf")

	var total := container.contents.get_item_count()
	_check(container.get_remaining_count() == total, "alle %d Funde stehen noch aus" % total)

	# Aufdecken abwarten.
	var waited := 0
	var previous_revealed := 0
	var grew_gradually := false
	while container.is_searching() and waited < 900:
		await process_frame
		var now_revealed := container.get_revealed_stacks().size()
		if now_revealed > previous_revealed and now_revealed < total:
			grew_gradually = true
		previous_revealed = now_revealed
		waited += 1

	_check(container.is_fully_searched, "Durchsuchen wird fertig")
	_check(container.get_revealed_stacks().size() == total, "am Ende ist alles sichtbar")
	if total > 1:
		_check(grew_gradually, "die Gegenstaende sind einzeln aufgetaucht, nicht alle auf einmal")

	# Kleine Dinge zuerst — sonst starrt man sekundenlang auf ein leeres Raster.
	container.free()

	var ordered := LootContainer.new()
	ordered.loot_table = _load_table("militaer")
	ordered.search_time_multiplier = 0.4
	root.add_child(ordered)
	await process_frame
	ordered.set_seed(31337)
	ordered.open()

	var reveal_order: Array[float] = []
	var guard := 0
	while ordered.is_searching() and guard < 900:
		await process_frame
		guard += 1
		for stack in ordered.get_revealed_stacks():
			var data := stack.get_data()
			var t := data.get_search_time() if data != null else 0.0
			if not reveal_order.has(t):
				reveal_order.append(t)

	var ascending := true
	for i in range(1, reveal_order.size()):
		if reveal_order[i] < reveal_order[i - 1]:
			ascending = false
	_check(ascending, "schnell findbare Gegenstaende tauchen zuerst auf")

	ordered.free()


## Nicht aufgedeckte Gegenstaende duerfen nicht greifbar sein — sonst
## koennte man die Kiste anklicken und sofort alles leerraeumen.
func _test_hidden_items_are_untouchable() -> void:
	_section("Verdeckte Gegenstaende")

	var container := LootContainer.new()
	container.loot_table = _load_table("werkstatt")
	root.add_child(container)
	await process_frame
	container.set_seed(2024)
	container.open()

	var stacks := container.contents.get_all_stacks()
	if stacks.is_empty():
		_check(false, "Container hat Inhalt")
		container.free()
		return

	var target := InventoryGrid.new(10, 10)
	var hidden := stacks[0]
	_check(not container.is_revealed(hidden.instance_id), "Gegenstand ist noch verdeckt")
	_check(not container.take_item(hidden.instance_id, target), "verdeckter Gegenstand laesst sich nicht nehmen")
	_check(target.get_item_count() == 0, "und landet nicht im Inventar")

	_check(container.take_all(target) == container.contents.get_item_count(),
		"'alles nehmen' nimmt nur Aufgedecktes — also nichts")

	# Nach dem Aufdecken muss es gehen.
	container.mark_revealed(hidden)
	_check(container.take_item(hidden.instance_id, target), "aufgedeckt laesst er sich nehmen")
	_check(target.get_item_count() == 1, "und liegt im Inventar")

	container.free()


## Ziehen mit der Maus, so wie das Fenster es ausloest.
##
## Geprueft wird der Weg, den ein Mausklick nimmt: gedrueckt auf einem Feld
## der Kiste, losgelassen auf einem Feld des Inventars. Was dabei NICHT
## geprueft werden kann, ist ob sich das Ziehen fluessig anfuehlt.
func _test_drag_between_grids() -> void:
	_section("Ziehen zwischen den Rastern")

	var packed: PackedScene = load("res://scenes/ui/loot_window.tscn")
	if packed == null:
		_check(false, "loot_window.tscn laedt")
		return

	# Bewusst erst ungetypt: Hat loot_window.gd einen Parserfehler, bleibt der
	# Knoten ein blankes Control. Ohne diese Pruefung bricht die Zuweisung mit
	# einem Laufzeitfehler ab und die Suite meldet nur stillschweigend weniger
	# Pruefungen statt eines Fehlers.
	var node: Node = packed.instantiate()
	_check(node is LootWindow, "loot_window.gd laedt fehlerfrei")
	if not (node is LootWindow):
		node.free()
		return

	var window: LootWindow = node
	root.add_child(window)
	await process_frame

	_check(window.get_node_or_null("DragGhost") is DragGhost,
		"Anzeige am Mauszeiger ist vorhanden")

	var container := LootContainer.new()
	container.loot_table = _load_table("werkstatt")
	root.add_child(container)
	await process_frame
	container.set_seed(7)

	var player := _make_player()
	await process_frame

	window.open_for(container, player.inventory)

	# Alles aufdecken — das Verdecken ist bereits eigens geprueft.
	for stack in container.contents.get_all_stacks():
		container.mark_revealed(stack)

	var stacks := container.contents.get_all_stacks()
	if stacks.is_empty():
		_check(false, "Container hat Inhalt")
		window.free()
		container.free()
		player.free()
		return

	var dragged: ItemStack = stacks[0]
	var id := dragged.instance_id
	var before := player.inventory.grid.get_item_count()

	var container_view: InventoryGridView = window.get_node("Layout/Columns/Left/ContainerView")
	var player_view: InventoryGridView = window.get_node("Layout/Columns/Right/PlayerView")

	# Aufnehmen in der Kiste, ablegen im Inventar.
	#
	# drop_at() ist genau der Weg, den auch das Loslassen der Maustaste geht.
	# Frueher hat dieser Test cell_released des Zielrasters ausgeloest — und
	# damit etwas geprueft, das im Spiel NIE passiert: Godot schickt das
	# Loslassen immer an das Raster, auf dem gedrueckt wurde. Der Test war
	# gruen, das Ziehen war kaputt.
	container_view.item_pressed.emit(dragged, container_view)
	window.drop_at(player_view, Vector2i(0, 0))

	_check(player.inventory.grid.get_stack(id) != null,
		"gezogener Gegenstand liegt im Inventar")
	_check(container.contents.get_stack(id) == null,
		"und nicht mehr in der Kiste")
	_check(player.inventory.grid.get_item_count() == before + 1,
		"nichts verdoppelt, nichts verloren")

	# Zurueck in die Kiste ziehen muss genauso gehen.
	var back: ItemStack = player.inventory.grid.get_stack(id)
	player_view.item_pressed.emit(back, player_view)
	window.drop_at(container_view, Vector2i(0, 0))
	_check(container.contents.get_stack(id) != null, "und laesst sich zurueckziehen")
	_check(container.is_revealed(id), "was man selbst hineinlegt, bleibt sichtbar")

	window.free()
	container.free()
	player.free()


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
