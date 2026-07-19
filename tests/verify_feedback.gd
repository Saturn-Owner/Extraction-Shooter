## Prüft die Treffer-Rückmeldung im echten Szenenbaum.
##
##   godot --headless --path . --script res://tests/verify_feedback.gd
##
## Anders als die anderen Tests laeuft dieser nicht auf reiner Mathematik,
## sondern baut das Testgelaende auf, drueckt wirklich ab und schaut nach,
## ob Geschosse, Effekte und Anzeigen tatsaechlich entstehen.
##
## Was er NICHT pruefen kann: ob es gut aussieht oder sich gut anfuehlt.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Treffer-Rueckmeldung pruefen ===\n")
	_run_all()


## Muss asynchron laufen: In _initialize() ist der Szenenbaum noch nicht
## bereit, Knoten landen dann nicht wirklich im Baum und _ready() feuert nie.
func _run_all() -> void:
	await process_frame

	_test_audio_generation()
	_test_crosshair()
	await _test_effects_spawn()
	await _test_firing_in_level()


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
	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Die Sounds werden gerechnet, nicht geladen — also pruefen, dass wirklich
## Audiodaten herauskommen und nicht ein leerer Puffer.
func _test_audio_generation() -> void:
	_section("Synthetische Sounds")

	var shot := WeaponAudio.make_gunshot(0.6, 0.28)
	_check(shot != null, "Schussgeraeusch wird erzeugt")
	_check(shot != null and shot.data.size() > 1000, "enthaelt Audiodaten (%d Bytes)" % (shot.data.size() if shot else 0))
	_check(shot != null and shot.mix_rate == WeaponAudio.SAMPLE_RATE, "korrekte Abtastrate")

	# Nicht nur Stille: mindestens ein Wert deutlich ungleich null.
	var loudest := 0
	if shot != null:
		for i in range(0, mini(shot.data.size(), 4000), 2):
			var value := shot.data[i] | (shot.data[i + 1] << 8)
			if value > 32767:
				value -= 65536
			loudest = maxi(loudest, absi(value))
	_check(loudest > 3000, "Signal ist hoerbar laut (Spitze %d)" % loudest)

	_check(WeaponAudio.make_dry_fire() != null, "Leerschuss-Klick wird erzeugt")
	_check(WeaponAudio.make_reload() != null, "Nachladegeraeusch wird erzeugt")

	# Grosse Waffen muessen wuchtiger klingen als kleine.
	var pistol := ItemRegistry.get_item(&"weapon_pistol_g17") as WeaponData
	var sniper := ItemRegistry.get_item(&"weapon_sniper_axmc") as WeaponData
	if pistol != null and sniper != null:
		var p1 := WeaponAudio.get_power_for_weapon(pistol)
		var p2 := WeaponAudio.get_power_for_weapon(sniper)
		_check(p2 > p1, "AXMC klingt wuchtiger als G17 (%.2f vs %.2f)" % [p2, p1])


func _test_crosshair() -> void:
	_section("Fadenkreuz")

	var crosshair := Crosshair.new()
	crosshair.size = Vector2(1600, 900)
	root.add_child(crosshair)

	_check(is_zero_approx(crosshair._bloom), "startet geschlossen")

	crosshair.add_bloom(10.0)
	_check(crosshair._bloom > 0.0, "geht bei Schuss auf")

	var before := crosshair._bloom
	crosshair._process(0.1)
	_check(crosshair._bloom < before, "schliesst sich wieder")

	# Nicht unbegrenzt aufgehen, sonst ist das Fadenkreuz vom Bildschirm.
	for i in range(50):
		crosshair.add_bloom(20.0)
	_check(crosshair._bloom <= crosshair.max_bloom, "geht nicht unbegrenzt auf")

	# Trefferfarbe muss sich nach dem Ergebnis richten.
	var stopped := Ballistics.HitResult.new()
	stopped.was_armored = true
	stopped.penetrated = false
	crosshair.show_hit(stopped)
	_check(crosshair._hit_color == Crosshair.COLOR_ARMOR_STOPPED, "gestoppt = gelb")

	var penetrated := Ballistics.HitResult.new()
	penetrated.was_armored = true
	penetrated.penetrated = true
	crosshair.show_hit(penetrated)
	_check(crosshair._hit_color == Crosshair.COLOR_PENETRATED, "durchschlagen = orange")

	var flesh := Ballistics.HitResult.new()
	flesh.was_armored = false
	crosshair.show_hit(flesh)
	_check(crosshair._hit_color == Crosshair.COLOR_FLESH, "ungeschuetzt = rot")

	crosshair.free()


func _test_effects_spawn() -> void:
	_section("Effekte")

	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame

	var impact := ImpactEffect.spawn(holder, Vector3(1, 2, 3), Vector3.UP, ImpactEffect.Kind.FLESH)
	_check(impact != null, "Einschlag wird erzeugt")
	_check(impact != null and impact.global_position.is_equal_approx(Vector3(1, 2, 3)),
		"Einschlag sitzt an der Trefferstelle")
	_check(impact != null and impact.get_child_count() > 0, "Einschlag hat Partikel")

	var flash := MuzzleFlash.spawn(holder, Transform3D(Basis(), Vector3(0, 1, 0)), 1.2)
	_check(flash != null, "Muendungsfeuer wird erzeugt")
	_check(flash != null and flash.get_child_count() > 0, "Muendungsfeuer hat Licht und Partikel")

	var result := Ballistics.HitResult.new()
	result.was_armored = true
	result.penetrated = false
	result.damage_to_target = 7.0
	var number := DamageNumber.spawn(holder, Vector3.ZERO, result)
	_check(number != null, "Schadenszahl wird erzeugt")
	_check(number != null and number.text.begins_with("("),
		"gestoppter Treffer wird eingeklammert dargestellt: '%s'" % (number.text if number else ""))

	holder.free()


## Der eigentliche Integrationstest: Level aufbauen, abdruecken, nachsehen.
func _test_firing_in_level() -> void:
	_section("Schuss im echten Level")

	var packed: PackedScene = load("res://scenes/levels/testgelaende.tscn")
	if packed == null:
		_check(false, "Testgelaende laedt")
		_finish()
		return

	var level: Node = packed.instantiate()
	root.add_child(level)
	# Ein Frame, damit _ready() und @onready im ganzen Baum durchlaufen.
	await process_frame
	_check(true, "Testgelaende laedt und startet")

	var player := level.get_node_or_null("Player") as PlayerController
	_check(player != null, "Spieler gefunden")
	if player == null:
		_finish()
		return

	_check(player.crosshair != null, "Fadenkreuz ist mit dem Spieler verbunden")

	var weapon := player.weapon
	_check(weapon != null, "Waffe gefunden")
	if weapon == null:
		_finish()
		return

	_check(weapon.data != null, "Waffendaten geladen: %s" % (weapon.data.display_name if weapon.data else "-"))
	_check(weapon.rounds_in_magazine > 0, "Magazin ist gefuellt (%d)" % weapon.rounds_in_magazine)

	var before := weapon.rounds_in_magazine
	var projectiles_before := _count_projectiles(level)

	weapon._shoot()

	_check(weapon.rounds_in_magazine == before - 1,
		"Schuss verbraucht genau eine Patrone (%d -> %d)" % [before, weapon.rounds_in_magazine])

	# Ein Frame vergehen lassen, damit die erzeugten Knoten im Baum landen.
	await process_frame
	await process_frame

	var projectiles_after := _count_projectiles(level)
	_check(projectiles_after > projectiles_before,
		"Geschoss wurde erzeugt (%d -> %d)" % [projectiles_before, projectiles_after])

	# Leerschiessen darf nicht knallen und nicht ins Minus laufen.
	weapon.rounds_in_magazine = 0
	var fired_empty := weapon._shoot()
	_check(not fired_empty, "leeres Magazin schiesst nicht")
	_check(weapon.rounds_in_magazine == 0, "Munition geht nicht ins Minus")

	weapon.reload()
	_check(weapon.rounds_in_magazine == weapon.data.magazine_size, "Nachladen fuellt das Magazin")

	# Schrot muss mehrere Geschosse gleichzeitig erzeugen.
	weapon.setup(&"weapon_shotgun_m870", &"ammo_12x70_buckshot")
	var before_buck := _count_projectiles(level)
	weapon._shoot()
	await process_frame
	await process_frame
	var spawned := _count_projectiles(level) - before_buck
	_check(spawned >= 8, "Buckshot erzeugt 8 Projektile (erzeugt: %d)" % spawned)

	level.free()
	_finish()


func _count_projectiles(from: Node) -> int:
	var count := 0
	for child in from.get_children():
		if child is Projectile:
			count += 1
	return count
