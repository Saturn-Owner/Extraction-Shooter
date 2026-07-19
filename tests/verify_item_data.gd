## Prüft, ob alle Item-Daten sauber laden und die Werte plausibel sind.
##
## Ausführen (ohne Editor, direkt aus der Kommandozeile):
##
##   godot --headless --path . --import --quit-after 120
##   godot --headless --path . --script res://tests/verify_item_data.gd
##
## WICHTIG: Der --import-Schritt muss nach einem frischen Clone einmal laufen.
## Ohne ihn kennt Godot die class_name-Typen (AmmoData, ArmorPlateData) nicht,
## weil der .godot/-Cache absichtlich nicht im Repo liegt. Der Test bricht dann
## mit "Could not find type" ab — das ist kein echter Fehler im Code.
##
## Exitcode 0 = alles in Ordnung, 1 = Probleme gefunden.
## Damit lässt sich das später auch automatisch bei jedem Push prüfen.
extends SceneTree

const AMMO_DIR := "res://assets/data/ammo"

var _failed := false


func _initialize() -> void:
	print("=== Item-Daten prüfen ===\n")
	_check_all_ammo()
	_check_plate_degradation()
	_check_ammo_vs_plate()
	_check_arsenal_coverage()
	_check_damage_penetration_tradeoff()
	_print_caliber_overview()

	print("\n=== ERGEBNIS: %s ===" % ("FEHLGESCHLAGEN" if _failed else "ALLES OK"))
	quit(1 if _failed else 0)


## Jede Waffe braucht mindestens eine passende Munition, sonst ist sie
## im Spiel unbenutzbar. Bei 12 Waffen faellt so ein Tippfehler im Kaliber
## sonst erst auf, wenn jemand die Waffe kauft.
func _check_arsenal_coverage() -> void:
	print("\n--- Waffen und Munition passen zusammen")
	ItemRegistry.ensure_loaded()

	var weapons := ItemRegistry.get_by_category(ItemData.Category.WEAPON)
	var ammo := ItemRegistry.get_by_category(ItemData.Category.AMMO)
	print("  %d Waffen, %d Munitionssorten" % [weapons.size(), ammo.size()])

	if weapons.is_empty() or ammo.is_empty():
		_fail("Arsenal ist leer")
		return

	for w in weapons:
		var weapon := w as WeaponData
		var matches := 0
		for a in ammo:
			if weapon.accepts_ammo(a as AmmoData):
				matches += 1
		if matches == 0:
			_fail("%s (%s) hat keine passende Munition" % [weapon.display_name, weapon.caliber])
		else:
			print("  OK  %-12s %-10s %d Sorten" % [weapon.display_name, weapon.caliber, matches])

	# Umgekehrt: Munition ohne Waffe waere toter Ballast im Loot.
	for a in ammo:
		var round_data := a as AmmoData
		var usable := false
		for w in weapons:
			if (w as WeaponData).accepts_ammo(round_data):
				usable = true
				break
		if not usable:
			_fail("%s passt in keine Waffe" % round_data.display_name)


## Der Kern des Balancings: Innerhalb eines Kalibers muss die Munition mit
## dem hoechsten Durchschlag NICHT gleichzeitig den hoechsten Schaden haben.
## Sonst gaebe es eine objektiv beste Sorte und die Wahl waere sinnlos.
func _check_damage_penetration_tradeoff() -> void:
	print("\n--- Kein Kaliber hat eine 'beste' Munition")
	ItemRegistry.ensure_loaded()

	var by_caliber: Dictionary = {}
	for a in ItemRegistry.get_by_category(ItemData.Category.AMMO):
		var round_data := a as AmmoData
		if not by_caliber.has(round_data.caliber):
			by_caliber[round_data.caliber] = []
		by_caliber[round_data.caliber].append(round_data)

	for caliber in by_caliber.keys():
		var rounds: Array = by_caliber[caliber]
		if rounds.size() < 2:
			continue

		var best_pen: AmmoData = rounds[0]
		var best_dmg: AmmoData = rounds[0]
		for r in rounds:
			if (r as AmmoData).penetration_power > best_pen.penetration_power:
				best_pen = r
			if (r as AmmoData).get_total_damage() > best_dmg.get_total_damage():
				best_dmg = r

		if best_pen == best_dmg:
			_fail("%s: '%s' hat sowohl den hoechsten Durchschlag als auch den hoechsten Schaden"
				% [caliber, best_pen.display_name])
		else:
			print("  OK  %-10s Pen: %-22s Schaden: %s"
				% [caliber, best_pen.display_name, best_dmg.display_name])


## Reine Uebersicht, kein Test — hilft beim Nachbalancieren.
func _print_caliber_overview() -> void:
	print("\n--- Uebersicht (nach Durchschlag sortiert)")
	ItemRegistry.ensure_loaded()

	var rounds: Array = ItemRegistry.get_by_category(ItemData.Category.AMMO)
	rounds.sort_custom(func(a, b): return (a as AmmoData).penetration_power > (b as AmmoData).penetration_power)

	print("  %-26s %-10s %5s %5s %8s" % ["Munition", "Kaliber", "Pen", "Schad", "Preis"])
	for r in rounds:
		var a := r as AmmoData
		var dmg_text := str(a.damage)
		if a.pellet_count > 1:
			dmg_text = "%dx%d" % [a.pellet_count, a.damage]
		print("  %-26s %-10s %5d %5s %8d" % [a.display_name, a.caliber, a.penetration_power, dmg_text, a.base_price])


func _fail(msg: String) -> void:
	print("  FEHLER: ", msg)
	_failed = true


## Lädt jede .tres im Munitionsordner und prüft sie.
func _check_all_ammo() -> void:
	print("--- Munition")
	var dir := DirAccess.open(AMMO_DIR)
	if dir == null:
		_fail("Ordner %s nicht gefunden" % AMMO_DIR)
		return

	var files := dir.get_files()
	if files.is_empty():
		_fail("keine Munitionsdateien gefunden")
		return

	for file in files:
		if not file.ends_with(".tres"):
			continue
		var path := "%s/%s" % [AMMO_DIR, file]
		var res := load(path)
		if res == null:
			_fail("%s konnte nicht geladen werden" % file)
			continue
		if not (res is AmmoData):
			_fail("%s ist kein AmmoData, sondern %s" % [file, res.get_class()])
			continue

		var ammo := res as AmmoData
		var problems := ammo.validate()
		if problems.is_empty():
			print("  OK  %-22s %s" % [ammo.id, ammo.get_stat_summary()])
		else:
			_fail("%s: %s" % [file, ", ".join(problems)])


## Die Schutzwirkung muss mit sinkender Haltbarkeit abnehmen und nie negativ werden.
func _check_plate_degradation() -> void:
	print("\n--- Plattenabnutzung (Klasse 4)")
	var plate := ArmorPlateData.new()
	plate.armor_class = 4
	plate.max_durability = 40.0

	var last := 999.0
	for durability in [40.0, 30.0, 20.0, 12.0, 4.0, 0.0]:
		var eff := plate.get_effective_class(durability)
		print("  Haltbarkeit %5.1f -> Klasse %.2f" % [durability, eff])
		if eff < 0.0:
			_fail("negative Schutzklasse bei Haltbarkeit %.1f" % durability)
		if eff > last:
			_fail("Schutz STEIGT bei sinkender Haltbarkeit (%.1f)" % durability)
		last = eff

	if plate.get_effective_class(0.0) != 0.0:
		_fail("zerstörte Platte schützt immer noch")


## Kernbalancing: M995 muss durch eine gute Platte kommen, M855A1 nicht.
## Das ist die zentrale Designaussage des Rüstungssystems — wenn dieser Test
## fällt, stimmt das Balancing nicht mehr.
func _check_ammo_vs_plate() -> void:
	print("\n--- Balancing-Kernaussage")
	var m995 := load("res://assets/data/ammo/556x45_m995.tres") as AmmoData
	var m855 := load("res://assets/data/ammo/556x45_m855a1.tres") as AmmoData
	if m995 == null or m855 == null:
		_fail("Vergleichsmunition nicht ladbar")
		return

	# Faustregel aus armor_plate_data.gd: Durchschlag muss etwa
	# (Schutzklasse * 10) erreichen.
	var class_4_threshold := 4 * 10

	if m995.penetration_power <= class_4_threshold:
		_fail("M995 (Pen %d) kommt nicht durch Klasse 4 — sollte es aber" % m995.penetration_power)
	else:
		print("  OK  M995 (Pen %d) durchschlägt Klasse 4" % m995.penetration_power)

	if m855.penetration_power > class_4_threshold:
		_fail("M855A1 (Pen %d) durchschlägt Klasse 4 — sollte es nicht" % m855.penetration_power)
	else:
		print("  OK  M855A1 (Pen %d) scheitert an Klasse 4" % m855.penetration_power)

	# Der Ausgleich: die schwächer durchschlagende Munition muss im Fleisch
	# mehr anrichten, sonst wäre M995 einfach besser und die Wahl sinnlos.
	if m855.damage <= m995.damage:
		_fail("M855A1 macht nicht mehr Fleischschaden als M995 — dann ist die Wahl sinnlos")
	else:
		print("  OK  M855A1 (%d Schaden) wirkt im Fleisch stärker als M995 (%d)" % [m855.damage, m995.damage])
