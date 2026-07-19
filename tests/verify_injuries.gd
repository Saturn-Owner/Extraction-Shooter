## Prüft Verletzungen, Blut und die medizinische Versorgung.
##
##   godot --headless --path . --script res://tests/verify_injuries.gd
##
## Die heiklen Stellen sind nicht die Zahlen, sondern die Verluste:
##   * Ein Verband darf sich nicht an einem heilen Arm verbrauchen.
##   * Eine abgebrochene Behandlung darf den Gegenstand nicht kosten.
##   * Eine Operation muss das Maximum senken — sonst ist sie gratis.
extends SceneTree

const TIMEOUT_SECONDS := 60.0

var _failed := 0
var _passed := 0
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	InjuryRegistry.ensure_loaded()
	print("=== Verletzungen, Blut und Medizin pruefen ===\n")
	_run_all()


func _process(delta: float) -> bool:
	if _done:
		return false
	_elapsed += delta
	if _elapsed >= TIMEOUT_SECONDS:
		print("\n=== ABBRUCH: Test haengt seit %.0f s ===" % TIMEOUT_SECONDS)
		quit(1)
	return false


func _run_all() -> void:
	await process_frame
	_test_data()
	_test_bleeding()
	_test_penalties_and_painkillers()
	await _test_treatment()
	await _test_surgery()
	await _test_blood_bag()
	_finish()


# ---------------------------------------------------------------------------

func _test_data() -> void:
	_section("Daten")

	for id in [&"bleed_light", &"bleed_heavy", &"cut", &"fracture"]:
		_check(InjuryRegistry.has_injury(id), "Verletzung vorhanden: %s" % id)

	for id in [&"med_bandage", &"med_tourniquet", &"med_splint",
			&"med_painkillers", &"med_surgical_kit", &"med_blood_bag"]:
		var item := ItemRegistry.get_item(id)
		_check(item is MedicalData, "Medizin vorhanden: %s" % id)

	# Eine starke Blutung MUSS deutlich schneller toeten als eine leichte,
	# sonst ist die Aderpresse nur ein teurerer Verband.
	var light := InjuryRegistry.get_injury(&"bleed_light")
	var heavy := InjuryRegistry.get_injury(&"bleed_heavy")
	if light != null and heavy != null:
		_check(heavy.blood_per_second > light.blood_per_second * 2.0,
			"starke Blutung ist mehr als doppelt so schnell (%.2f vs %.2f)" % [
				heavy.blood_per_second, light.blood_per_second])

	# Der Verband darf die starke Blutung NICHT koennen — sonst braucht
	# niemand eine Aderpresse.
	var bandage := ItemRegistry.get_item(&"med_bandage") as MedicalData
	if bandage != null:
		_check(bandage.treats_kind(InjuryData.Kind.BLEED_LIGHT), "Verband stoppt leichte Blutungen")
		_check(not bandage.treats_kind(InjuryData.Kind.BLEED_HEAVY),
			"aber keine starke — dafuer gibt es die Aderpresse")


func _test_bleeding() -> void:
	_section("Blutverlust")

	var health := HealthSystem.new()
	var injuries := InjurySystem.new()

	_check(is_equal_approx(health.blood, HealthSystem.MAX_BLOOD), "voller Koerper zu Beginn")

	injuries.add(&"bleed_heavy", HealthSystem.Part.LEFT_LEG)
	_check(injuries.get_count() == 1, "die Blutung haengt am Bein")

	var hp_before := health.get_hp(HealthSystem.Part.LEFT_LEG)
	injuries.tick(10.0, health)
	_check(health.blood < HealthSystem.MAX_BLOOD, "Blut sinkt (%.1f %%)" % health.blood)
	_check(is_equal_approx(health.get_hp(HealthSystem.Part.LEFT_LEG), hp_before),
		"die Trefferpunkte bleiben, wo sie waren")

	# Zwei Blutungen bluten doppelt.
	var second := HealthSystem.new()
	var both := InjurySystem.new()
	both.add(&"bleed_heavy", HealthSystem.Part.LEFT_LEG)
	both.add(&"bleed_heavy", HealthSystem.Part.RIGHT_ARM)
	both.tick(10.0, second)
	_check(second.blood < health.blood, "zwei Wunden bluten schneller als eine (%.1f vs %.1f)"
		% [second.blood, health.blood])

	# Und am Ende ist man tot, mit vollen Trefferpunkten.
	var doomed := HealthSystem.new()
	var wound := InjurySystem.new()
	wound.add(&"bleed_heavy", HealthSystem.Part.CHEST)
	for i in 200:
		wound.tick(1.0, doomed)
	_check(doomed.is_dead, "wer nichts tut, verblutet")
	_check(doomed.death_cause == "verblutet", "und die Todesursache steht fest: '%s'" % doomed.death_cause)
	_check(doomed.get_hp(HealthSystem.Part.HEAD) > 0.0,
		"obwohl der Kopf unversehrt ist — Blut ist die zweite Uhr")

	health.free()
	injuries.free()
	second.free()
	both.free()
	doomed.free()
	wound.free()


func _test_penalties_and_painkillers() -> void:
	_section("Schmerzmittel")

	var injuries := InjurySystem.new()
	injuries.add(&"fracture", HealthSystem.Part.LEFT_LEG)

	var penalty := injuries.get_movement_penalty()
	_check(penalty > 0.0, "ein gebrochenes Bein bremst (%.0f %%)" % (penalty * 100.0))

	injuries.apply_painkillers(180.0)
	_check(injuries.is_pain_relieved(), "Schmerzmittel wirken")
	_check(is_zero_approx(injuries.get_movement_penalty()),
		"und man laeuft wieder — weil man es nicht mehr spuert")
	_check(injuries.get_count() == 1, "der Bruch ist trotzdem noch da")

	# Blutungen lassen sich NICHT wegdruecken. Wer das glaubt, verblutet
	# mit gutem Gefuehl.
	var bleeding := InjurySystem.new()
	bleeding.add(&"bleed_heavy", HealthSystem.Part.LEFT_LEG)
	bleeding.apply_painkillers(180.0)
	var blood_test := HealthSystem.new()
	bleeding.tick(5.0, blood_test)
	_check(blood_test.blood < HealthSystem.MAX_BLOOD,
		"Schmerzmittel stopfen kein Loch")

	# Die Wirkung laeuft ab.
	injuries.tick(200.0, null)
	_check(not injuries.is_pain_relieved(), "nach drei Minuten ist Schluss")
	_check(injuries.get_movement_penalty() > 0.0, "und das Bein ist immer noch gebrochen")

	injuries.free()
	bleeding.free()
	blood_test.free()


func _test_treatment() -> void:
	_section("Behandeln dauert")

	var player := await _make_player()

	player.inventory.add(&"med_bandage", 2)
	var bandage := _find(player, &"med_bandage")
	_check(bandage != null and bandage.quantity == 2, "zwei Verbaende im Rucksack")

	# An einem heilen Arm darf gar nicht erst angefangen werden.
	_check(not player.can_treat_with(bandage.get_data(), HealthSystem.Part.RIGHT_ARM),
		"am unverletzten Arm gibt es nichts zu verbinden")

	player.injuries.add(&"bleed_light", HealthSystem.Part.RIGHT_ARM)
	_check(player.start_treatment(bandage, HealthSystem.Part.RIGHT_ARM),
		"an der blutenden Stelle geht es los")

	player.tick_treatment(2.0)
	_check(player.is_treating(), "nach zwei Sekunden laeuft sie noch")
	_check(player.injuries.get_count() == 1, "und die Blutung ist noch offen")
	_check(player.get_treatment_progress() > 0.0 and player.get_treatment_progress() < 1.0,
		"der Fortschritt steht bei %.0f %%" % (player.get_treatment_progress() * 100.0))

	# Abbrechen darf nichts kosten.
	player.cancel_treatment()
	_check(not player.is_treating(), "abgebrochen")
	_check(bandage.quantity == 2, "der Verband ist noch da — Abbrechen kostet nichts")
	_check(player.injuries.get_count() == 1, "die Blutung ebenso")

	# Und jetzt zu Ende.
	player.start_treatment(bandage, HealthSystem.Part.RIGHT_ARM)
	player.tick_treatment(10.0)
	_check(not player.is_treating(), "die zweite Behandlung laeuft durch")
	_check(player.injuries.get_count() == 0, "die Blutung ist gestillt")
	_check(bandage.quantity == 1, "und ein Verband ist aufgebraucht (%d uebrig)" % bandage.quantity)

	# Die Aderpresse gehoert zur starken Blutung, der Verband nicht.
	player.injuries.add(&"bleed_heavy", HealthSystem.Part.LEFT_LEG)
	_check(not player.injuries.can_treat(bandage.get_data(), HealthSystem.Part.LEFT_LEG),
		"gegen die Arterie hilft der Verband nicht")

	player.inventory.add(&"med_tourniquet", 1)
	var tourniquet := _find(player, &"med_tourniquet")
	player.start_treatment(tourniquet, HealthSystem.Part.LEFT_LEG)
	player.tick_treatment(10.0)
	_check(player.injuries.get_count() == 0, "die Aderpresse haelt sie auf")

	player.free()


func _test_surgery() -> void:
	_section("Chirurgenkit")

	var player := await _make_player()
	player.inventory.add(&"med_surgical_kit", 3)
	var kit := _find(player, &"med_surgical_kit")

	var leg := HealthSystem.Part.LEFT_LEG
	var full := HealthSystem.get_max_hp(leg)

	# An einem Bein, das noch steht, gibt es nichts zu operieren.
	player.health.apply_damage(leg, 20.0)
	_check(not player.can_treat_with(kit.get_data(), leg),
		"ein angeschlagenes Bein ist kein Fall fuer das Kit")

	player.health.apply_damage(leg, 999.0)
	_check(player.health.is_destroyed(leg), "das Bein ist ausgefallen")
	_check(player.can_treat_with(kit.get_data(), leg), "jetzt schon")

	player.start_treatment(kit, leg)
	player.tick_treatment(5.0)
	_check(player.is_treating(), "20 Sekunden sind nach 5 nicht um")
	player.tick_treatment(20.0)

	_check(not player.health.is_destroyed(leg), "das Bein ist wieder da")
	_check(player.health.get_effective_max_hp(leg) < full,
		"aber es haelt weniger aus (%.0f statt %.0f)" % [
			player.health.get_effective_max_hp(leg), full])
	_check(is_equal_approx(player.health.get_max_hp_scale(leg), 0.75),
		"genau ein Viertel weniger (%.2f)" % player.health.get_max_hp_scale(leg))
	_check(is_equal_approx(player.health.get_hp(leg), player.health.get_effective_max_hp(leg)),
		"und es kommt voll zurueck, nicht halb tot")

	# Wer sich dasselbe Bein immer wieder flicken laesst, hat irgendwann
	# keines mehr — aber es hoert bei 40 Prozent auf.
	for i in 5:
		player.health.apply_damage(leg, 999.0)
		player.health.apply_surgery(leg)
	_check(is_equal_approx(player.health.get_max_hp_scale(leg), HealthSystem.SURGERY_MAX_HP_FLOOR),
		"nach mehreren Operationen bleibt es bei %d %%" % roundi(
			HealthSystem.SURGERY_MAX_HP_FLOOR * 100.0))

	player.free()


func _test_blood_bag() -> void:
	_section("Blutbeutel")

	var player := await _make_player()
	player.inventory.add(&"med_blood_bag", 1)
	var bag := _find(player, &"med_blood_bag")
	var med := bag.get_data() as MedicalData

	# Mit vollem Koerper gibt es nichts zu tun — der Beutel ist zu teuer,
	# um ihn aus Versehen zu verschwenden.
	_check(not player.can_treat_with(med, HealthSystem.Part.CHEST),
		"am vollen Koerper laesst er sich nicht anlegen")

	player.health.lose_blood(40.0)
	_check(player.can_treat_with(med, HealthSystem.Part.CHEST), "nach Blutverlust schon")

	# Die Dauer haengt daran, wie viel fehlt.
	player.start_treatment(bag, HealthSystem.Part.CHEST)
	var long_duration := float(player._treatment["duration"])
	player.cancel_treatment()

	player.health.restore_blood(30.0)
	player.start_treatment(bag, HealthSystem.Part.CHEST)
	var short_duration := float(player._treatment["duration"])
	_check(short_duration < long_duration,
		"wer weniger verloren hat, ist schneller fertig (%.1f s statt %.1f s)" % [
			short_duration, long_duration])

	player.tick_treatment(short_duration + 0.1)
	_check(is_equal_approx(player.health.blood, HealthSystem.MAX_BLOOD),
		"danach ist der Koerper voll (%.0f %%)" % player.health.blood)
	_check(player.inventory.grid.get_stack(bag.instance_id) == null,
		"und der Beutel ist verbraucht")

	player.free()


# ---------------------------------------------------------------------------

func _make_player() -> PlayerController:
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	var player: PlayerController = packed.instantiate()
	root.add_child(player)
	await process_frame
	return player


func _find(player: PlayerController, id: StringName) -> ItemStack:
	for stack in player.inventory.grid.get_all_stacks():
		if stack.item_id == id:
			return stack
	return null


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
