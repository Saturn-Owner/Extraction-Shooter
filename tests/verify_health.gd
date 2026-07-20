## Prüft Gesundheit pro Körperteil, Survival-Werte und Ausrüstungsplätze.
##
##   godot --headless --path . --import --quit-after 120
##   godot --headless --path . --script res://tests/verify_health.gd
##
## Was hier NICHT geprüft werden kann: ob sich das Balancing gut anfühlt —
## ob Durst zu schnell steigt, ob ein zerschossenes Bein zu hart bestraft.
## Das muss ein Mensch spielen.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	# Kleidung gibt es im Spiel gerade nicht mehr — siehe test_items.gd.
	TestItems.install()
	print("=== Gesundheit, Zustand und Ausruestung pruefen ===\n")
	_test_body_parts()
	_test_death_rules()
	_test_overflow_to_chest()
	_test_penalties()
	_test_survival_drain()
	_test_cold()
	_test_equipment()
	await _test_scene_wiring()

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


func _make_health() -> HealthSystem:
	var health := HealthSystem.new()
	root.add_child(health)
	return health


func _test_body_parts() -> void:
	_section("Koerperteile")
	var health := _make_health()

	_check(HealthSystem.MAX_HP.size() == 7, "sieben Koerperteile")
	_check(not health.is_dead, "startet lebendig")

	for part in HealthSystem.Part.values():
		var maximum := HealthSystem.get_max_hp(part)
		_check(maximum > 0.0, "%s hat Trefferpunkte (%d)" % [HealthSystem.get_part_name(part), roundi(maximum)])
		_check(health.get_hp(part) == maximum, "%s startet voll" % HealthSystem.get_part_name(part))

	# Kopf muss weniger aushalten als die Brust — sonst lohnt Zielen nicht.
	_check(HealthSystem.get_max_hp(HealthSystem.Part.HEAD)
		< HealthSystem.get_max_hp(HealthSystem.Part.CHEST),
		"der Kopf haelt weniger aus als die Brust")

	health.free()


## Die zentrale Regel: Kopf oder Brust leer bedeutet tot, alles andere nicht.
func _test_death_rules() -> void:
	_section("Todesregel")

	for part in [HealthSystem.Part.HEAD, HealthSystem.Part.CHEST]:
		var health := _make_health()

		# Ein Array, KEINE einfache Variable: GDScript-Lambdas fangen lokale
		# Variablen als Kopie ein. Eine Zuweisung darin bliebe unsichtbar,
		# und der Test wuerde immer fehlschlagen, obwohl das Signal kommt.
		var reported: Array = []
		health.died.connect(func(p: int) -> void: reported.append(p))

		health.apply_damage(part, 9999.0)
		_check(health.is_dead, "%s auf null toetet" % HealthSystem.get_part_name(part))
		_check(reported.size() == 1 and reported[0] == part,
			"und meldet das richtige Koerperteil")
		health.free()

	# Arme, Beine und Bauch duerfen ausfallen, ohne zu toeten.
	var health := _make_health()
	for part in [HealthSystem.Part.LEFT_ARM, HealthSystem.Part.RIGHT_ARM,
			HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG,
			HealthSystem.Part.STOMACH]:
		health.apply_damage(part, HealthSystem.get_max_hp(part))
		_check(health.is_destroyed(part), "%s faellt aus" % HealthSystem.get_part_name(part))

	_check(not health.is_dead, "vier zerschossene Glieder und ein Bauch toeten nicht")
	_check(health.get_hp(HealthSystem.Part.CHEST) > 0.0, "die Brust ist noch unversehrt")
	health.free()


## Ein ausgefallenes Glied darf kein Schutzschild sein.
func _test_overflow_to_chest() -> void:
	_section("Ueberlauf in die Brust")
	var health := _make_health()

	var leg := HealthSystem.Part.LEFT_LEG
	health.apply_damage(leg, HealthSystem.get_max_hp(leg))
	_check(health.is_destroyed(leg), "Bein ist ausgefallen")

	var chest_before := health.get_hp(HealthSystem.Part.CHEST)
	health.apply_damage(leg, 20.0)
	var chest_after := health.get_hp(HealthSystem.Part.CHEST)

	_check(chest_after < chest_before,
		"weiterer Beinschaden geht auf die Brust (%.0f -> %.0f)" % [chest_before, chest_after])
	_check(is_equal_approx(chest_before - chest_after, 20.0 * HealthSystem.OVERFLOW_TO_CHEST),
		"gedaempft auf %d %%" % roundi(HealthSystem.OVERFLOW_TO_CHEST * 100.0))

	# Der Schuss, der ein Bein zerstoert, darf NICHT zusaetzlich in die Brust
	# durchschlagen. Sonst waere ein Beintreffer toedlich und Gliedmassen
	# waeren keine Puffer, sondern Zuender.
	var single := _make_health()
	single.apply_damage(HealthSystem.Part.RIGHT_LEG, 500.0)
	_check(single.is_destroyed(HealthSystem.Part.RIGHT_LEG), "ein schwerer Treffer zerstoert das Bein")
	_check(not single.is_dead, "toetet aber nicht")
	_check(single.get_hp(HealthSystem.Part.CHEST) == HealthSystem.get_max_hp(HealthSystem.Part.CHEST),
		"und laesst die Brust unberuehrt")

	health.free()
	single.free()


func _test_penalties() -> void:
	_section("Auswirkungen von Verletzungen")
	var health := _make_health()

	_check(health.get_movement_penalty() == 0.0, "unverletzt keine Tempostrafe")
	_check(health.get_aim_penalty() == 0.0, "unverletzt keine Zielstrafe")
	_check(health.get_metabolism_multiplier() == 1.0, "unverletzt normaler Verbrauch")

	health.apply_damage(HealthSystem.Part.LEFT_LEG, 999.0)
	var one_leg := health.get_movement_penalty()
	_check(one_leg > 0.0, "ein Bein bremst (%d %%)" % roundi(one_leg * 100.0))

	health.apply_damage(HealthSystem.Part.RIGHT_LEG, 999.0)
	var two_legs := health.get_movement_penalty()
	_check(two_legs > one_leg, "zwei Beine bremsen staerker (%d %%)" % roundi(two_legs * 100.0))
	_check(two_legs < one_leg * 2.0, "aber nicht doppelt so stark")
	_check(two_legs < 1.0, "und nie bis zum Stillstand")

	health.apply_damage(HealthSystem.Part.STOMACH, 999.0)
	_check(health.get_metabolism_multiplier() > 1.0, "Bauchtreffer zehrt schneller")

	_check(not health.is_dead, "all das toetet nicht")
	health.free()


func _test_survival_drain() -> void:
	_section("Hunger und Durst")
	var stats := SurvivalStats.new()
	root.add_child(stats)

	_check(stats.hunger == stats.max_hunger, "Hunger startet voll")
	_check(stats.thirst == stats.max_thirst, "Durst startet voll")

	# Eine Minute vergehen lassen.
	stats.tick(60.0)
	_check(stats.hunger < stats.max_hunger, "Hunger sinkt (%.1f)" % stats.hunger)
	_check(stats.thirst < stats.max_thirst, "Durst sinkt (%.1f)" % stats.thirst)
	_check(stats.thirst < stats.hunger, "Durst sinkt schneller als Hunger")

	# Bis auf null laufen lassen.
	stats.tick(60.0 * 60.0)
	_check(stats.hunger <= 0.0, "Hunger erreicht null")
	_check(stats.thirst <= 0.0, "Durst erreicht null")

	var damage := stats.get_damage_this_second()
	_check(not damage.is_empty(), "leer angekommen verursacht Schaden")
	var hits_stomach := false
	for entry in damage:
		if entry.part == HealthSystem.Part.STOMACH:
			hits_stomach = true
	_check(hits_stomach, "und zwar am Bauch")

	stats.eat(50.0)
	stats.drink(50.0)
	_check(stats.hunger > 0.0 and stats.thirst > 0.0, "Essen und Trinken helfen")

	# Waehrend der Stunde ist die Figur ohne Kleidung auch ausgekuehlt —
	# der Kaelteschaden laeuft also weiter. Hier geht es nur um den Bauch.
	stats.temperature = stats.normal_temperature
	_check(stats.get_damage_this_second().is_empty(),
		"nach Essen und Trinken kein Bauchschaden mehr")

	# Ein zerschossener Bauch zehrt schneller.
	var fast := SurvivalStats.new()
	root.add_child(fast)
	fast.metabolism_multiplier = 1.8
	fast.tick(60.0)
	var slow := SurvivalStats.new()
	root.add_child(slow)
	slow.tick(60.0)
	_check(fast.hunger < slow.hunger, "Bauchverletzung zehrt schneller (%.1f < %.1f)" % [fast.hunger, slow.hunger])

	stats.free()
	fast.free()
	slow.free()


func _test_cold() -> void:
	_section("Kaelte und Kleidung")

	# Ohne Kleidung muss die Temperatur in gefaehrliche Bereiche fallen.
	var cold := SurvivalStats.new()
	root.add_child(cold)
	cold.insulation = 0.0
	cold.tick(60.0 * 30.0)
	_check(cold.temperature < cold.danger_temperature,
		"ohne Kleidung sinkt die Temperatur unter die Gefahrenschwelle (%.1f)" % cold.temperature)
	_check(cold.get_cold_movement_penalty() > 0.0,
		"und bremst spuerbar (%d %%)" % roundi(cold.get_cold_movement_penalty() * 100.0))

	# Warm angezogen muss man gesund bleiben — sonst ist Kleidung sinnlos.
	var warm := SurvivalStats.new()
	root.add_child(warm)
	warm.insulation = 11.7
	warm.tick(60.0 * 30.0)
	_check(warm.temperature >= warm.danger_temperature,
		"warm angezogen bleibt man gesund (%.1f)" % warm.temperature)
	_check(warm.get_cold_movement_penalty() == 0.0, "und wird nicht gebremst")

	# Erfrierung trifft aussen, nicht den Rumpf.
	var frozen := SurvivalStats.new()
	root.add_child(frozen)
	frozen.temperature = frozen.critical_temperature - 1.0
	var parts := {}
	for entry in frozen.get_damage_this_second():
		parts[entry.part] = true
	_check(parts.has(HealthSystem.Part.LEFT_ARM) and parts.has(HealthSystem.Part.RIGHT_LEG),
		"Erfrierung trifft Arme und Beine")
	_check(not parts.has(HealthSystem.Part.CHEST), "aber nicht die Brust")

	cold.free()
	warm.free()
	frozen.free()


func _test_equipment() -> void:
	_section("Ausruestungsplaetze")
	ItemRegistry.ensure_loaded()

	var equipment := Equipment.new()
	root.add_child(equipment)

	var coat := ItemStack.create(&"shirt_winter_coat")
	var boots := ItemStack.create(&"boots_winter")
	_check(coat.get_data() != null, "Wintermantel existiert")
	if coat.get_data() == null:
		equipment.free()
		return

	_check(equipment.can_equip(coat, ItemData.EquipSlot.SHIRT), "Mantel passt ins Oberteil")
	_check(not equipment.can_equip(coat, ItemData.EquipSlot.BOOTS), "aber nicht in die Schuhe")

	equipment.equip(coat, ItemData.EquipSlot.SHIRT)
	equipment.equip(boots, ItemData.EquipSlot.BOOTS)
	_check(equipment.get_item(ItemData.EquipSlot.SHIRT) == coat, "Mantel ist angelegt")
	_check(equipment.get_total_insulation() > 0.0,
		"Kleidung waermt (%.1f)" % equipment.get_total_insulation())

	# Ein zweiter Mantel muss den ersten herausgeben, nicht verschlucken.
	var second := ItemStack.create(&"shirt_thermal")
	var displaced := equipment.equip(second, ItemData.EquipSlot.SHIRT)
	_check(displaced == coat, "der alte Mantel kommt zurueck, statt zu verschwinden")
	_check(equipment.get_item(ItemData.EquipSlot.SHIRT) == second, "das neue Teil sitzt")

	var removed := equipment.unequip(ItemData.EquipSlot.BOOTS)
	_check(removed == boots, "Ablegen gibt den Gegenstand heraus")
	_check(equipment.is_empty(ItemData.EquipSlot.BOOTS), "der Platz ist danach leer")

	equipment.free()


func _test_scene_wiring() -> void:
	_section("Szene")

	var packed: PackedScene = load("res://scenes/player/player.tscn")
	if packed == null:
		_check(false, "player.tscn laedt")
		return

	var player: PlayerController = packed.instantiate()
	root.add_child(player)
	# Ohne diesen Frame haben die @onready-Verweise noch keinen Wert.
	await process_frame

	_check(player.health is HealthSystem, "Spieler hat ein Gesundheitssystem")
	_check(player.survival is SurvivalStats, "Spieler hat Zustandswerte")
	_check(player.equipment is Equipment, "Spieler hat Ausruestungsplaetze")

	# Angelegte Kleidung muss sofort waermen und wiegen.
	var weight_before := player.carried_weight_kg
	var coat := ItemStack.create(&"shirt_winter_coat")
	player.equipment.equip(coat, ItemData.EquipSlot.SHIRT)
	_check(player.survival.insulation > 0.0, "Anziehen waermt sofort")
	_check(player.carried_weight_kg > weight_before,
		"und zaehlt zum Gewicht (%.2f -> %.2f)" % [weight_before, player.carried_weight_kg])

	# Verletzungen muessen das Tempo druecken.
	var speed_before := player.get_current_max_speed()
	player.health.apply_damage(HealthSystem.Part.LEFT_LEG, 999.0)
	_check(player.get_current_max_speed() < speed_before,
		"ein zerschossenes Bein macht langsamer (%.2f -> %.2f)" % [
			speed_before, player.get_current_max_speed()])
	_check(player.get_condition_factor() > 0.0, "aber nie bis zum Stillstand")

	# Die gezeichnete Figur: Jedes Koerperteil braucht einen Umriss, sonst
	# fehlt im Fenster ein Bein — und zwar lautlos.
	for part: HealthSystem.Part in HealthSystem.MAX_HP:
		var shape: Array = CharacterWindow.BODY_SHAPES.get(part, [])
		_check(shape.size() >= 3, "%s hat einen Umriss (%d Punkte)" % [
			HealthSystem.get_part_name(part), shape.size()])
		var inside := true
		for point: Vector2 in shape:
			if point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
				inside = false
		_check(inside, "und liegt ganz in der Zeichenflaeche")

	var window: PackedScene = load("res://scenes/ui/character_window.tscn")
	_check(window != null, "character_window.tscn laedt")
	if window != null:
		var node: Node = window.instantiate()
		_check(node is CharacterWindow, "character_window.gd laedt fehlerfrei")

		# Die Knotenpfade muessen stimmen. Ein Tippfehler faellt sonst erst
		# auf, wenn jemand im Spiel C drueckt — und dann als Nullzugriff.
		for path in ["Layout/Inhalt/Reiter/Ausruestung", "Layout/Inhalt/Reiter/Gesundheit",
				"Layout/Inhalt/Mitte/Links", "Layout/Inhalt/Mitte/Rechts",
				"Layout/Inhalt/Mitte/Figur/Zeichnung", "Layout/Inhalt/Mitte/Figur/Hinweis",
				"Layout/Inhalt/Werte", "Layout/Inhalt/Auswirkung"]:
			_check(node.get_node_or_null(path) != null, "Knoten vorhanden: %s" % path)

		# Und es muss sich mit einem echten Spieler oeffnen lassen, ohne zu
		# stolpern — inklusive einmal Aufbauen der Plaetze und Werte.
		root.add_child(node)
		await process_frame
		var character := node as CharacterWindow
		character.open_for(player)
		await process_frame
		_check(character.is_open(), "das Fenster oeffnet sich")
		_check(character.get_node("Layout/Inhalt/Werte").get_child_count() > 0,
			"die Werteleiste ist gefuellt")
		character.close()
		_check(not character.is_open(), "und laesst sich schliessen")

		root.remove_child(node)
		node.free()

	var level: PackedScene = load("res://scenes/levels/raid_eisstadt.tscn")
	if level != null:
		var raid: Node = level.instantiate()
		_check(raid.get_node_or_null("HUD/CharacterWindow") != null,
			"das Fenster haengt im HUD des Raids")
		raid.free()

	player.free()
