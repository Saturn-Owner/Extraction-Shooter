## Prüft Waffenhandling: Patrone im Lauf, Nachladezeit, Ladehemmungen,
## Zielen und den Aufbau des sichtbaren Modells.
##
##   godot --headless --path . --import --quit-after 120
##   godot --headless --path . --script res://tests/verify_weapon_handling.gd
##
## Die Waffe wird hier bewusst OHNE Szenenbaum gebaut. Dadurch entstehen keine
## Projektile und keine Audioknoten — getestet wird ausschliesslich die Logik,
## und der Test bleibt schnell und deterministisch.
extends SceneTree

var _failed := 0
var _passed := 0

## Wieviel Munition der Testvorrat hergibt.
var _supply_left := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Waffenhandling prüfen ===\n")
	_test_chambering()
	_test_reload_takes_time()
	_test_tactical_vs_empty_reload()
	_test_reload_cancel_costs_nothing()
	_test_reload_respects_supply()
	_test_jamming()
	_test_jam_chance_grows_with_wear()
	_test_jam_never_loses_ammo()
	_test_aiming_reduces_spread()
	_test_every_weapon_builds()
	_test_viewmodels_are_unique()

	# Laeuft asynchron weiter und ruft am Ende _finish() auf: Der Waffenwechsel
	# braucht einen echten Frame, damit _ready() im Szenenbaum durchlaeuft.
	_test_weapon_switch_swaps_model()


func _finish() -> void:
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


## Baut eine Waffe ohne Szenenbaum, mit einem Munitionsvorrat als Quelle.
func _make_weapon(supply: int = 200) -> Weapon:
	var weapon := Weapon.new()
	weapon.setup(&"weapon_rifle_ar15", &"ammo_556x45_m855a1")
	_supply_left = supply
	weapon.ammo_supplier = _take_from_supply
	return weapon


func _take_from_supply(_id: StringName, count: int) -> int:
	var given := mini(count, _supply_left)
	_supply_left -= given
	return given


## Laesst Zeit vergehen, indem _process in kleinen Schritten aufgerufen wird.
## Ohne Szenenbaum laeuft sonst kein Timer.
func _advance(weapon: Weapon, seconds: float) -> void:
	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < seconds:
		weapon._process(step)
		elapsed += step


func _test_chambering() -> void:
	_section("Patrone im Lauf")

	var weapon := _make_weapon()
	_check(weapon.rounds_in_magazine == 0 and not weapon.round_chambered,
		"Waffe kommt komplett leer aus setup()")

	# Ohne Patrone im Lauf faellt der Hahn ins Leere, auch bei vollem Magazin.
	weapon.rounds_in_magazine = 30
	weapon.round_chambered = false
	_check(not weapon._shoot(), "volles Magazin ohne Patrone im Lauf schiesst nicht")

	weapon.free()


func _test_reload_takes_time() -> void:
	_section("Nachladen dauert")

	var weapon := _make_weapon()
	var duration := weapon.data.get_reload_duration(true)
	_check(duration > 0.5, "Nachladezeit ist gesetzt (%.2fs)" % duration)

	_check(weapon.request_reload(), "Nachladen laesst sich anstossen")
	_check(weapon.is_reloading(), "Waffe ist waehrend des Nachladens beschaeftigt")

	# Auf halber Strecke darf noch nichts angekommen sein.
	_advance(weapon, duration * 0.5)
	_check(weapon.rounds_in_magazine == 0,
		"auf halber Strecke ist noch keine Patrone im Magazin")
	_check(not weapon.try_fire(true, true), "waehrend des Nachladens wird nicht geschossen")

	_advance(weapon, duration * 0.6)
	_check(not weapon.is_reloading(), "Nachladen ist nach Ablauf der Zeit fertig")
	_check(weapon.get_total_rounds() == weapon.data.magazine_size,
		"leer nachgeladen ergibt genau %d Schuss (ist: %d)"
			% [weapon.data.magazine_size, weapon.get_total_rounds()])

	weapon.free()


## Der eigentliche Sinn der Patrone im Lauf: taktisch nachladen bringt
## einen Schuss mehr als leergeschossen nachladen.
func _test_tactical_vs_empty_reload() -> void:
	_section("Taktisch gegen leergeschossen")

	var mag_size := 0

	# Leer nachgeladen: Der Verschluss muss eine Patrone aus dem Magazin holen.
	var empty := _make_weapon()
	mag_size = empty.data.magazine_size
	empty.request_reload()
	_advance(empty, empty.data.get_reload_duration(true) + 0.1)
	var total_empty := empty.get_total_rounds()
	_check(total_empty == mag_size,
		"leergeschossen nachgeladen = %d Schuss (ist: %d)" % [mag_size, total_empty])
	empty.free()

	# Taktisch: Patrone bleibt im Lauf, das Magazin wird voll — ein Schuss mehr.
	var tactical := _make_weapon()
	tactical.rounds_in_magazine = 10
	tactical.round_chambered = true
	tactical.request_reload()
	_advance(tactical, tactical.data.get_reload_duration(false) + 0.1)
	var total_tactical := tactical.get_total_rounds()
	_check(total_tactical == mag_size + 1,
		"taktisch nachgeladen = %d Schuss (ist: %d)" % [mag_size + 1, total_tactical])
	tactical.free()

	_check(total_tactical > total_empty,
		"taktisch nachladen lohnt sich gegenueber leerschiessen")

	# Und es geht auch schneller.
	var weapon := _make_weapon()
	_check(weapon.data.get_reload_duration(false) < weapon.data.get_reload_duration(true),
		"taktisch nachladen geht schneller als leergeschossen")
	weapon.free()


func _test_reload_cancel_costs_nothing() -> void:
	_section("Abbrechen kostet nichts")

	var weapon := _make_weapon(200)
	weapon.request_reload()
	_advance(weapon, 0.4)
	weapon.cancel_reload()

	_check(not weapon.is_reloading(), "Abbruch beendet das Nachladen")
	_check(_supply_left == 200,
		"beim Abbruch wird keine Munition entnommen (Vorrat: %d)" % _supply_left)
	_check(weapon.rounds_in_magazine == 0, "das Magazin bleibt leer")

	# Danach muss ein neuer Versuch wieder gehen.
	_check(weapon.request_reload(), "nach dem Abbruch kann erneut geladen werden")
	weapon.free()


## Ein halb gefuelltes Magazin ist ein gueltiges Ergebnis — die Waffe
## darf keine Munition erfinden, die der Spieler nicht dabei hat.
func _test_reload_respects_supply() -> void:
	_section("Nachladen erfindet keine Munition")

	var weapon := _make_weapon(7)
	weapon.request_reload()
	_advance(weapon, weapon.data.get_reload_duration(true) + 0.1)

	_check(weapon.get_total_rounds() == 7,
		"nur 7 Patronen vorhanden, also 7 geladen (ist: %d)" % weapon.get_total_rounds())
	_check(_supply_left == 0, "der Vorrat ist aufgebraucht")
	weapon.free()


func _test_jamming() -> void:
	_section("Ladehemmung")

	var weapon := _make_weapon()
	weapon.fill_magazine()
	weapon.is_jammed = true

	_check(weapon.is_busy(), "geklemmte Waffe gilt als beschaeftigt")
	_check(not weapon.try_fire(true, true), "geklemmte Waffe schiesst nicht")
	_check(not weapon.request_reload(), "geklemmte Waffe laesst sich nicht nachladen")

	_check(weapon.request_unjam(), "Hemmung laesst sich beheben")
	_advance(weapon, weapon.data.jam_clear_time * 0.5)
	_check(weapon.is_jammed, "waehrend des Behebens klemmt sie noch")

	_advance(weapon, weapon.data.jam_clear_time * 0.6)
	_check(not weapon.is_jammed, "nach Ablauf der Zeit ist die Hemmung weg")
	_check(weapon.round_chambered, "nach dem Beheben steckt wieder eine Patrone im Lauf")
	# Nicht wirklich abdruecken: Ohne Szenenbaum gibt es keine Projektile.
	# Geprueft wird, dass die Waffe die Blockade aufgehoben hat.
	_check(not weapon.is_busy(), "die Waffe ist wieder bedienbar")

	weapon.free()


## Verschleiss muss sich auszahlen — sonst ist der Zustandswert Dekoration.
func _test_jam_chance_grows_with_wear() -> void:
	_section("Verschleiss treibt Hemmungen hoch")

	var weapon := _make_weapon()

	weapon.condition = 100.0
	var jams_new := _count_jams(weapon, 4000)

	weapon.condition = 0.0
	var jams_worn := _count_jams(weapon, 4000)

	_check(jams_worn > jams_new,
		"abgenutzte Waffe klemmt oefter (neu: %d, Schrott: %d von 4000)" % [jams_new, jams_worn])
	_check(jams_new < 200,
		"neue Waffe klemmt selten (%d von 4000)" % jams_new)

	weapon.free()


## Buchhaltung ueber Ladehemmungen hinweg.
##
## Eine Hemmung unterbricht das Nachladen des Verschlusses — die naechste
## Patrone bleibt im Magazin. Dabei darf keine Patrone verschwinden und schon
## gar keine entstehen. Genau hier ist der bestehende Ladungstest zufaellig
## rot geworden, weil er den Magazininhalt statt der Gesamtzahl geprueft hat.
func _test_jam_never_loses_ammo() -> void:
	_section("Hemmungen verschlucken keine Munition")

	var weapon := _make_weapon()
	weapon.rounds_in_magazine = 30
	weapon.round_chambered = true
	# Schrottzustand, damit im Testlauf wirklich Hemmungen auftreten.
	weapon.condition = 0.0

	# Ueber viele Magazine laufen lassen. Bei 2 % Hemmungswahrscheinlichkeit
	# bliebe ein einzelnes Magazin oft hemmungsfrei — der Test waere dann
	# selbst zufaellig rot, also genau der Fehler, den er aufdecken soll.
	const TARGET_SHOTS := 600
	var supplied := weapon.get_total_rounds()
	var shots := 0
	var jams := 0
	var bookkeeping_ok := true

	while shots < TARGET_SHOTS:
		if weapon.is_jammed:
			# Beheben schiebt nur eine Patrone weiter, verbraucht aber keine.
			var before_clear := weapon.get_total_rounds()
			weapon.is_jammed = false
			weapon._chamber_if_possible()
			if weapon.get_total_rounds() != before_clear:
				bookkeeping_ok = false
			jams += 1
			continue

		if not weapon.round_chambered:
			if weapon.rounds_in_magazine <= 0:
				weapon.rounds_in_magazine = weapon.data.magazine_size
				supplied += weapon.data.magazine_size
			weapon._chamber_if_possible()
			continue

		var before_shot := weapon.get_total_rounds()
		# Schuss ohne Projektil nachbilden: Patrone raus, Verschluss nachladen.
		weapon.round_chambered = false
		weapon._cycle_action()
		shots += 1
		if weapon.get_total_rounds() != before_shot - 1:
			bookkeeping_ok = false

	_check(jams > 0, "im Schrottzustand traten Hemmungen auf (%d bei %d Schuss)" % [jams, shots])
	_check(bookkeeping_ok, "jeder Schuss verbraucht genau eine Patrone, auch bei Hemmungen")
	# Gesamtbilanz: Was reingegeben wurde, ist verschossen oder noch da.
	_check(shots + weapon.get_total_rounds() == supplied,
		"Bilanz stimmt: %d verschossen + %d uebrig = %d geladen"
			% [shots, weapon.get_total_rounds(), supplied])

	weapon.free()


func _count_jams(weapon: Weapon, samples: int) -> int:
	var jams := 0
	for i in range(samples):
		if weapon._roll_jam():
			jams += 1
	return jams


## Zielen muss messbar praeziser sein, nicht nur optisch anders.
func _test_aiming_reduces_spread() -> void:
	_section("Zielen verringert die Streuung")

	var weapon := _make_weapon()
	var forward := Vector3(0.0, 0.0, -1.0)

	weapon.aiming = false
	var hip := _average_deviation(weapon, forward, 600)

	weapon.aiming = true
	var ads := _average_deviation(weapon, forward, 600)

	_check(ads < hip,
		"gezielt streut weniger als aus der Huefte (%.4f gegen %.4f Grad)" % [ads, hip])

	# Der Faktor aus den Daten muss auch ungefaehr ankommen.
	var ratio := ads / maxf(0.0001, hip)
	var expected := weapon.data.ads_spread_multiplier
	_check(absf(ratio - expected) < 0.15,
		"Streuungsfaktor passt zu den Daten (gemessen %.2f, erwartet %.2f)" % [ratio, expected])

	weapon.free()


func _average_deviation(weapon: Weapon, forward: Vector3, samples: int) -> float:
	var total := 0.0
	for i in range(samples):
		var dir := weapon._apply_spread(forward, 0)
		total += rad_to_deg(forward.angle_to(dir))
	return total / float(samples)


## Prueft JEDE Waffe im Arsenal, nicht nur die AR-15.
##
## Der Grundsatz lautet: jede Waffe eigenes Modell, eigene Datei, eigene
## Mechanik. Ein Test, der nur eine Waffe anfasst, kann diesen Grundsatz nicht
## absichern — er wuerde erst im Spiel auffallen, wenn jemand die Flinte in
## die Hand nimmt und sie unsichtbar ist.
func _test_every_weapon_builds() -> void:
	_section("Jede Waffe baut ihr Modell")

	var weapons := ItemRegistry.get_by_category(ItemData.Category.WEAPON)
	_check(weapons.size() > 0, "Waffen im Arsenal gefunden (%d)" % weapons.size())

	var own := 0
	var placeholder: Array[String] = []

	for item in weapons:
		var weapon_data := item as WeaponData
		if weapon_data == null:
			continue

		var model := weapon_data.create_viewmodel()
		model.build()

		var label := weapon_data.display_name

		# weapon_view.gd findet die beweglichen Teile ausschliesslich ueber
		# diese Namen. Wer sie umbenennt, bekommt eine stumme Waffe.
		# Action, Abzug und Muendung hat jede Waffe — Magazin und
		# Feuerwahlhebel bewusst nicht: Eine Flinte hat kein abnehmbares
		# Magazin, eine Pistole keinen Feuerwahlhebel.
		_check(model.action != null, "%s: Verschluss/Schlitten vorhanden" % label)
		_check(model.trigger != null, "%s: Abzug vorhanden" % label)
		_check(model.muzzle_point != null, "%s: Muendungspunkt vorhanden" % label)

		if model.muzzle_point != null:
			_check(is_equal_approx(model.muzzle_point.position.z, model.muzzle_z),
				"%s: Muendungspunkt sitzt bei muzzle_z (%.3f / %.3f)"
					% [label, model.muzzle_point.position.z, model.muzzle_z])

		_check_sight_line(model, label)

		if weapon_data.has_own_viewmodel():
			own += 1
		else:
			placeholder.append(label)

		model.free()

	print("\n  %d von %d Waffen haben ein eigenes Modell." % [own, weapons.size()])
	if not placeholder.is_empty():
		# Kein Fehler, sondern eine Arbeitsliste: Der Grundsatz ist, dass hier
		# irgendwann nichts mehr steht.
		print("  Noch am Platzhalter: ", ", ".join(placeholder))


## Der subtilste Fehler ueberhaupt: Wenn Kimme und Korn nicht auf einer Hoehe
## liegen, zielt der Spieler an seinem eigenen Visier vorbei — und niemand
## merkt, warum die Schuesse danebengehen. Weil weapon_view.gd das Modell
## beim Zielen um genau sight_height absenkt, muss dieser Wert auch stimmen.
func _check_sight_line(model: WeaponViewmodel, label: String) -> void:
	var rear := model.get_node_or_null("RearSight") as Node3D
	var front := model.get_node_or_null("FrontSight") as Node3D

	if rear == null or front == null:
		_check(false, "%s: Kimme und Korn vorhanden" % label)
		return

	_check(is_equal_approx(rear.position.y, front.position.y),
		"%s: Kimme und Korn auf gleicher Hoehe (%.4f / %.4f)"
			% [label, rear.position.y, front.position.y])
	_check(is_equal_approx(rear.position.y, model.sight_height),
		"%s: Visierhoehe stimmt mit sight_height ueberein (%.4f / %.4f)"
			% [label, rear.position.y, model.sight_height])
	_check(is_zero_approx(rear.position.x) and is_zero_approx(front.position.x),
		"%s: Visierung steht mittig" % label)
	_check(front.position.z < rear.position.z,
		"%s: das Korn sitzt vor der Kimme" % label)


## Der Kern des Ganzen: Nimmt der Spieler eine andere Waffe, muss auch ein
## anderes Modell in der Hand liegen. Ohne diesen Test faellt ein fehlendes
## Signal erst auf, wenn jemand im Spiel die Pistole zieht und weiter ein
## Sturmgewehr sieht.
func _test_weapon_switch_swaps_model() -> void:
	_section("Waffenwechsel tauscht das Modell")

	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var player := scene.instantiate() as PlayerController
	root.add_child(player)
	# Ein Frame, damit _ready() und @onready im ganzen Baum durchlaufen.
	await process_frame

	var view := player.weapon_view
	_check(view != null, "Waffenansicht ist in der Szene verbaut")
	if view == null:
		player.free()
		_finish()
		return

	var first := view.get_viewmodel()
	_check(first is AR15Viewmodel,
		"Startwaffe zeigt das AR-15-Modell (%s)" % (first.get_model_name() if first else "-"))

	# Auf die Pistole wechseln — voellig andere Mechanik, anderes Modell.
	player.weapon.setup(&"weapon_pistol_g17", &"ammo_9x19_fmj")
	var second := view.get_viewmodel()
	_check(second is Glock17Viewmodel,
		"nach dem Wechsel liegt das Glock-Modell in der Hand (%s)"
			% (second.get_model_name() if second else "-"))
	_check(first != second, "es ist wirklich ein neues Modell, kein umgebautes")

	# Die Muendung muss mitwandern, sonst blitzt es dort, wo die alte Waffe war.
	_check(player.weapon._visual_muzzle == second.muzzle_point,
		"das Muendungsfeuer haengt an der neuen Waffe")

	# Und eine Waffe ohne passende Munition darf das Modell ebenfalls wechseln.
	var shotgun := ItemRegistry.get_item(&"weapon_shotgun_m870") as WeaponData
	player.weapon.equip_without_ammo(shotgun)
	_check(view.get_viewmodel() is M870Viewmodel,
		"auch ohne passende Munition wird das Modell gewechselt")

	player.free()
	_finish()


## Jede Waffe muss ihr eigenes Modell bekommen — verschiedene Waffen duerfen
## sich nicht dieselbe Klasse teilen. Genau das waere der schleichende Rueckfall
## in die Einheitswaffe.
func _test_viewmodels_are_unique() -> void:
	_section("Kein geteiltes Modell")

	var seen := {}
	var shared: Array[String] = []

	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var weapon_data := item as WeaponData
		if weapon_data == null or not weapon_data.has_own_viewmodel():
			continue
		var path: String = weapon_data.viewmodel.resource_path
		if seen.has(path):
			shared.append("%s teilt sich %s mit %s" % [weapon_data.display_name, path, seen[path]])
		else:
			seen[path] = weapon_data.display_name

	_check(shared.is_empty(),
		"keine zwei Waffen teilen sich ein Modell%s"
			% ("" if shared.is_empty() else ": " + ", ".join(shared)))
