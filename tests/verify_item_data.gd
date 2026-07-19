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

	print("\n=== ERGEBNIS: %s ===" % ("FEHLGESCHLAGEN" if _failed else "ALLES OK"))
	quit(1 if _failed else 0)


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
