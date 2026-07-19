## Prüft die Trefferberechnung: Durchschlag, Schadensabfall, Plattenabnutzung.
##
##   godot --headless --path . --import --quit-after 120
##   godot --headless --path . --script res://tests/verify_ballistics.gd
##
## Diese Tests halten das Kern-Balancing fest. Wenn jemand später Werte
## verstellt und M995 plötzlich an einer Klasse-4-Platte scheitert, schlägt
## der Test fehl — statt dass es erst im Spiel jemandem auffällt.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Ballistik prüfen ===\n")
	_test_penetration_chance_curve()
	_test_ammo_against_plates()
	_test_distance_falloff()
	_test_armor_wears_down()
	_test_blocked_hits_still_hurt()
	_test_shotgun_vs_armor()
	_print_penetration_matrix()

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


func _ammo(id: StringName) -> AmmoData:
	return ItemRegistry.get_item(id) as AmmoData


## Die Übergangszone muss weich sein: kein harter Schalter bei einem Punkt
## Durchschlag Unterschied, sonst wirkt Rüstung willkürlich.
func _test_penetration_chance_curve() -> void:
	_section("Durchschlagskurve")

	# Klasse 4 verlangt 40 Durchschlag.
	_check(is_equal_approx(Ballistics.get_required_penetration(4.0), 40.0),
		"Klasse 4 verlangt 40 Durchschlag")

	_check(is_equal_approx(Ballistics.get_penetration_chance(40.0, 4.0), 0.5),
		"genau an der Schwelle: 50 Prozent")
	_check(Ballistics.get_penetration_chance(24.0, 4.0) <= 0.0,
		"16 Punkte darunter: kommt nie durch")
	_check(Ballistics.get_penetration_chance(56.0, 4.0) >= 1.0,
		"16 Punkte darüber: kommt immer durch")
	_check(is_equal_approx(Ballistics.get_penetration_chance(30.0, 0.0), 1.0),
		"ohne Platte immer Durchschlag")

	# Streng monoton: mehr Durchschlag darf nie schlechter sein.
	var last := -1.0
	var monotonic := true
	for pen in [10.0, 20.0, 30.0, 35.0, 40.0, 45.0, 50.0, 60.0]:
		var c := Ballistics.get_penetration_chance(pen, 4.0)
		if c < last:
			monotonic = false
		last = c
	_check(monotonic, "mehr Durchschlag ist nie schlechter")


## Die zentrale Designaussage, jetzt gegen echte Munitionsdaten.
func _test_ammo_against_plates() -> void:
	_section("Munition gegen Platten (auf 10 m)")

	var cases := [
		# id, Plattenklasse, soll durchkommen
		[&"ammo_556x45_m995", 4.0, true, "M995 gegen Klasse 4"],
		[&"ammo_556x45_m855a1", 4.0, false, "M855A1 gegen Klasse 4"],
		[&"ammo_556x45_m855a1", 2.0, true, "M855A1 gegen Klasse 2"],
		[&"ammo_9x19_fmj", 2.0, false, "9mm FMJ gegen Klasse 2"],
		[&"ammo_9x19_ap", 2.0, true, "9mm AP gegen Klasse 2"],
		[&"ammo_338lm_ap", 6.0, true, ".338 AP gegen Klasse 6"],
		[&"ammo_762x51_m61", 5.0, true, "M61 gegen Klasse 5"],
		[&"ammo_762x51_nosler", 4.0, false, "Nosler gegen Klasse 4"],
		[&"ammo_12x70_buckshot", 2.0, false, "Buckshot gegen Klasse 2"],
	]

	for case in cases:
		var ammo := _ammo(case[0])
		if ammo == null:
			_check(false, "Munition %s nicht gefunden" % case[0])
			continue

		var pen := Ballistics.get_penetration_at_distance(ammo, 10.0)
		var chance := Ballistics.get_penetration_chance(pen, case[1])
		var expected: bool = case[2]
		var ok := (chance > 0.5) if expected else (chance < 0.5)
		_check(ok, "%s: Chance %.0f%% (erwartet: %s)" % [
			case[3], chance * 100.0, "durch" if expected else "gestoppt"])


## Auf Distanz muss dieselbe Munition schwächer werden — sonst hätte
## Entfernung keine taktische Bedeutung.
func _test_distance_falloff() -> void:
	_section("Abfall über Entfernung")

	var m855a1 := _ammo(&"ammo_556x45_m855a1")
	_check(m855a1 != null, "M855A1 gefunden")
	if m855a1 == null:
		return

	var pen_10 := Ballistics.get_penetration_at_distance(m855a1, 10.0)
	var pen_300 := Ballistics.get_penetration_at_distance(m855a1, 300.0)
	var dmg_10 := Ballistics.get_damage_at_distance(m855a1, 10.0)
	var dmg_300 := Ballistics.get_damage_at_distance(m855a1, 300.0)

	_check(pen_300 < pen_10, "Durchschlag sinkt mit Entfernung (%.1f -> %.1f)" % [pen_10, pen_300])
	_check(dmg_300 < dmg_10, "Schaden sinkt mit Entfernung (%.1f -> %.1f)" % [dmg_10, dmg_300])

	# Durchschlag muss stärker abfallen als Schaden — auf Distanz wird
	# Rüstung wichtiger, nicht die reine Wucht.
	var pen_ratio := pen_300 / maxf(0.01, pen_10)
	var dmg_ratio := dmg_300 / maxf(0.01, dmg_10)
	_check(pen_ratio < dmg_ratio,
		"Durchschlag fällt schneller als Schaden (%.2f vs %.2f)" % [pen_ratio, dmg_ratio])

	# Schrot muss auf Distanz praktisch wertlos werden.
	var buck := _ammo(&"ammo_12x70_buckshot")
	if buck != null:
		var buck_50 := Ballistics.get_damage_at_distance(buck, 50.0)
		_check(buck_50 < float(buck.damage) * 0.75,
			"Buckshot verliert auf 50 m deutlich (%.1f von %d)" % [buck_50, buck.damage])

	# Ein Präzisionskaliber soll die Werte länger halten.
	var lapua := _ammo(&"ammo_338lm_ap")
	if lapua != null and m855a1 != null:
		var lapua_ratio := Ballistics.get_penetration_at_distance(lapua, 500.0) / float(lapua.penetration_power)
		var nato_ratio := Ballistics.get_penetration_at_distance(m855a1, 500.0) / float(m855a1.penetration_power)
		_check(lapua_ratio > nato_ratio,
			".338 hält auf 500 m besser als 5.56 (%.2f vs %.2f)" % [lapua_ratio, nato_ratio])


## Auch gestoppte Treffer zerstören die Platte — das ist der Grund, warum
## Rüstung nicht ewig hält und Dauerbeschuss eine gültige Taktik ist.
func _test_armor_wears_down() -> void:
	_section("Platten nutzen sich ab")

	var plate := ItemRegistry.get_item(&"plate_class4_front") as ArmorPlateData
	var weak := _ammo(&"ammo_9x19_fmj")
	_check(plate != null and weak != null, "Platte und schwache Munition gefunden")
	if plate == null or weak == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var durability := plate.max_durability
	var shots := 0
	while durability > 0.0 and shots < 200:
		var result := Ballistics.resolve_hit(weak, 10.0, plate, durability, rng)
		durability = maxf(0.0, durability - result.damage_to_armor)
		shots += 1

	_check(durability <= 0.0, "9mm FMJ zerstört eine Klasse-4-Platte irgendwann (%d Schuss)" % shots)
	# Untergrenze, damit Pistolen keine Plattenknacker sind. Obergrenze, damit
	# Dauerbeschuss eine echte Taktik bleibt und nicht sinnlos wird.
	_check(shots >= 15, "aber nicht zu schnell (%d Schuss, mindestens 15)" % shots)
	_check(shots <= 80, "und nicht unendlich (%d Schuss, höchstens 80)" % shots)

	# Zum Vergleich: passende Munition muss die Platte deutlich schneller
	# zerlegen, sonst lohnt sich teure Munition nicht.
	var strong := _ammo(&"ammo_556x45_m995")
	if strong != null:
		var d2 := plate.max_durability
		var shots2 := 0
		while d2 > 0.0 and shots2 < 200:
			var r2 := Ballistics.resolve_hit(strong, 10.0, plate, d2, rng)
			d2 = maxf(0.0, d2 - r2.damage_to_armor)
			shots2 += 1
		_check(shots2 < shots, "M995 zerlegt dieselbe Platte schneller (%d statt %d Schuss)" % [shots2, shots])

	# Danach muss dieselbe schwache Munition durchkommen.
	var after := Ballistics.resolve_hit(weak, 10.0, plate, 0.0, rng)
	_check(after.penetrated, "durch die zerstörte Platte kommt auch 9mm durch")
	_check(not after.was_armored, "zerstörte Platte zählt als ungeschützt")


func _test_blocked_hits_still_hurt() -> void:
	_section("Gestoppte Treffer")

	var plate := ItemRegistry.get_item(&"plate_class4_front") as ArmorPlateData
	var weak := _ammo(&"ammo_9x19_fmj")
	if plate == null or weak == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 999

	var result := Ballistics.resolve_hit(weak, 10.0, plate, plate.max_durability, rng)
	_check(not result.penetrated, "9mm wird von Klasse 4 gestoppt")
	_check(result.damage_to_target > 0.0,
		"gestoppter Treffer macht trotzdem Wucht-Schaden (%.1f)" % result.damage_to_target)
	_check(result.damage_to_target < float(weak.damage) * 0.3,
		"aber deutlich weniger als ein Durchschlag")
	_check(not result.caused_bleeding, "gestoppter Treffer verursacht keine Blutung")
	_check(result.damage_to_armor > 0.0, "die Platte nimmt Schaden")


## Schrot ist der Extremfall: viele Projektile, fast kein Durchschlag.
## Gegen Ungepanzerte tödlich, gegen Platten nutzlos.
func _test_shotgun_vs_armor() -> void:
	_section("Schrot")

	var buck := _ammo(&"ammo_12x70_buckshot")
	var slug := _ammo(&"ammo_12x70_slug")
	if buck == null or slug == null:
		return

	_check(buck.pellet_count > 1, "Buckshot verschiesst mehrere Kugeln (%d)" % buck.pellet_count)
	_check(buck.get_total_damage() > slug.damage * 0.5,
		"Buckshot gesamt (%d) ist mit dem Slug (%d) vergleichbar" % [buck.get_total_damage(), slug.damage])

	var plate := ItemRegistry.get_item(&"plate_class4_front") as ArmorPlateData
	if plate != null:
		var pen := Ballistics.get_penetration_at_distance(buck, 10.0)
		var chance := Ballistics.get_penetration_chance(pen, 4.0)
		_check(chance <= 0.01, "Buckshot kommt nie durch Klasse 4 (%.0f%%)" % (chance * 100.0))


## Übersicht zum Nachbalancieren — kein Test.
func _print_penetration_matrix() -> void:
	print("\n--- Durchschlagschance auf 50 m (Prozent)")
	ItemRegistry.ensure_loaded()

	var rounds: Array = ItemRegistry.get_by_category(ItemData.Category.AMMO)
	rounds.sort_custom(func(a, b): return (a as AmmoData).penetration_power > (b as AmmoData).penetration_power)

	print("  %-26s %5s %5s %5s %5s %5s %5s" % ["Munition", "Kl.1", "Kl.2", "Kl.3", "Kl.4", "Kl.5", "Kl.6"])
	for r in rounds:
		var ammo := r as AmmoData
		var pen := Ballistics.get_penetration_at_distance(ammo, 50.0)
		var cells := ""
		for cls in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
			cells += "%5.0f" % (Ballistics.get_penetration_chance(pen, cls) * 100.0)
		print("  %-26s%s" % [ammo.display_name, cells])
