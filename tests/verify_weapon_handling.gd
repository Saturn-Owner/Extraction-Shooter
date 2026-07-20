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
	_test_jam_survives_weapon_switch()
	_test_chamber_only_reload()
	await _test_viewmodel_arms()
	_test_aiming_reduces_spread()
	_test_generated_meshes_are_closed()
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
## Eine Ladehemmung darf den Waffenwechsel ueberleben.
##
## ---------------------------------------------------------------------------
## SONST IST WEGSTECKEN DER BILLIGSTE AUSWEG
##
## `is_jammed` stand nicht im Magazingedaechtnis des Spielers. Taste 2, Taste 1
## — und die Waffe war sauber, waehrend das richtige Beheben `jam_clear_time`
## kostet. Gemeldet wurde nicht der Exploit, sondern seine Folge: das
## seltsame Nachladen danach, siehe _test_chamber_only_reload().
func _test_jam_survives_weapon_switch() -> void:
	_section("Hemmung ueberlebt den Waffenwechsel")

	var weapon := _make_weapon()
	weapon.rounds_in_magazine = 30
	weapon.round_chambered = false
	weapon.is_jammed = true

	# Genau das tut player_controller beim Wechsel.
	var remembered := {
		"rounds": weapon.rounds_in_magazine,
		"chambered": weapon.round_chambered,
		"jammed": weapon.is_jammed,
	}
	weapon.restore_magazine(int(remembered["rounds"]),
		bool(remembered["chambered"]), bool(remembered["jammed"]))

	_check(weapon.is_jammed, "nach dem Zurueckwechseln klemmt sie weiterhin")
	_check(not weapon.request_reload(),
		"und laesst sich nicht einfach nachladen")

	# Ohne den gemerkten Wert muss der Standard weiter sauber sein: Wer
	# restore_magazine ohne dritten Wert ruft, bekommt keine Hemmung
	# geschenkt.
	weapon.restore_magazine(30, true)
	_check(not weapon.is_jammed, "ohne Angabe bleibt sie hemmungsfrei")


## Volles Magazin, leere Kammer: Es wird nur durchgeladen.
##
## ---------------------------------------------------------------------------
## DIE ANIMATION DARF NICHTS ZEIGEN, WAS NICHT PASSIERT
##
## Gemeldet beim Spielen: "wechselt manchmal gar nicht das Magazin, sondern
## zieht nur den Stift nach hinten, und dann hat man wieder Munition."
##
## Genau so war es. Nach einer Hemmung ist das Magazin voll und der Lauf leer.
## Nachladen liess dann den vollen Magazinwechsel abspielen, fuellte nichts
## nach (`get_missing_rounds()` ist null) und schob am Ende eine Patrone aus
## dem Magazin in die Kammer — 30 wurden zu 29.
func _test_chamber_only_reload() -> void:
	_section("Durchladen statt Magazinwechsel")

	var weapon := _make_weapon()
	var size: int = weapon.data.magazine_size

	var reported := [false]
	weapon.reload_started.connect(
		func(_d: float, _empty: bool, only: bool) -> void: reported[0] = only)

	# --- Volles Magazin, leerer Lauf ---
	weapon.rounds_in_magazine = size
	weapon.round_chambered = false
	_check(weapon.request_reload(), "nachladen ist moeglich")
	_check(weapon._reload_chamber_only, "es gilt als blosses Durchladen")
	_check(reported[0], "und wird so gemeldet, damit die Animation es weiss")

	while weapon.is_reloading():
		weapon._advance_reload(1.0 / 60.0)
	_check(weapon.round_chambered, "danach steckt eine Patrone im Lauf")
	_check(weapon.get_total_rounds() == size,
		"und es ist keine verschwunden (%d von %d)"
			% [weapon.get_total_rounds(), size])

	# --- Ein echter Wechsel bleibt ein echter Wechsel ---
	weapon.rounds_in_magazine = 3
	weapon.round_chambered = false
	weapon.request_reload()
	_check(not weapon._reload_chamber_only,
		"ein halbleeres Magazin wird weiterhin gewechselt")
	_check(not reported[0], "und auch so gemeldet")


## Die Haende, die der Spieler an seiner Waffe sieht.
##
## ---------------------------------------------------------------------------
## DIE LAENGE ERGIBT SICH AUS DER WAFFE
##
## Erster Versuch waren 0,15 und 0,17 m — "Kameragroesse" hatte ich als
## kuerzer verstanden. Der Vorderschaft liegt aber 0,59 m von der linken
## Schulter entfernt; der Arm reichte nicht einmal in die Naehe und blieb auf
## halbem Weg stehen. Im Bild sah man nur eine dunkle Ecke unten.
##
## Geprueft wird deshalb die REICHWEITE gegen den tatsaechlichen Bedarf, nicht
## eine Zahl gegen sich selbst.
func _test_viewmodel_arms() -> void:
	_section("Haende am Kameramodell")

	var reach: float = ViewmodelArms.UPPER_LENGTH + ViewmodelArms.LOWER_LENGTH

	# --- HAENDE GIBT ES NUR, WO DIE GRIFFPUNKTE GEMESSEN SIND ---
	#
	# Eine Waffe ohne gemessene Punkte bekaeme Haende, die sichtbar daneben
	# fassen - schlimmer als gar keine. Jede Waffe entscheidet das selbst
	# ueber `shows_hands`, nicht eine Liste im Kameracode.
	#
	# Geprueft wird die BEDINGUNG, nicht die Auswahl: Wer den Schalter setzt,
	# muss auch Griffpunkte liefern. Damit darf die naechste Waffe jederzeit
	# dazukommen, ohne dass dieser Test angefasst wird.
	var with_hands: Array[String] = []
	for entry in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var wd := entry as WeaponData
		var vm := wd.create_viewmodel()
		vm.weapon_data = wd
		root.add_child(vm)
		await process_frame
		if vm.shows_hands:
			with_hands.append(String(wd.id))
			_check(vm.grip_point != null and vm.support_point != null,
				"%s zeigt Haende und nennt dafuer Griff und Vorderschaft"
					% wd.id)
		vm.queue_free()
		await process_frame

	_check(with_hands.size() >= 1,
		"mindestens eine Waffe hat Haende (%s)" % ", ".join(with_hands))
	_check(with_hands.size() == 1 and with_hands[0] == "weapon_rifle_ar15",
		"und zwar vorerst nur die AR-15 (%s)" % ", ".join(with_hands))

	# Wie weit muessen die Haende wirklich? Aus den Griffpunkten der AR-15 in
	# ihrer Ruhelage, nicht geschaetzt.
	var data := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var model := data.create_viewmodel()
	model.weapon_data = data
	root.add_child(model)
	# Erst nach einem Bild laeuft _ready() und damit _collect_parts() — vorher
	# sind grip_point und support_point noch null. Dieselbe Falle wie bei den
	# Figuren im Testgelaende.
	await process_frame
	model.position = model.hip_position
	model.rotation_degrees = model.hip_rotation_degrees

	_check(model.grip_point != null and model.support_point != null,
		"das Waffenmodell nennt Griff und Vorderschaft")
	if model.grip_point == null or model.support_point == null:
		model.queue_free()
		return

	var to_grip := ViewmodelArms.RIGHT_SHOULDER.distance_to(
		model.grip_point.position + model.position)
	var to_fore := ViewmodelArms.LEFT_SHOULDER.distance_to(
		model.support_point.position + model.position)

	_check(reach > to_grip,
		"der rechte Arm reicht an den Griff (%.3f von %.3f m)" % [to_grip, reach])
	_check(reach > to_fore,
		"der linke an den Vorderschaft (%.3f von %.3f m)" % [to_fore, reach])

	# Nicht beliebig lang: Ein Arm, der immer gestreckt ist, sieht steif aus.
	_check(reach < to_fore + 0.20,
		"und nicht unnoetig weit darueber (%.3f gegen %.3f m)" % [reach, to_fore])

	# Duenner als ein Weltglied — das war der eigentliche Punkt an
	# "Kameragroesse".
	_check(ViewmodelArms.UPPER_THICK < 0.10,
		"die Glieder sind schlank genug fuer 30 cm vor dem Auge (%.3f m)"
			% ViewmodelArms.UPPER_THICK)

	# --- DIE FARBE KOMMT VOM KOERPER ---
	#
	# Es ist derselbe Mensch: Was man am eigenen Arm sieht, muss zu dem
	# passen, was andere von aussen sehen. Hier stand erst ein selbst
	# gewaehltes Olivgruen, und beim Umschalten auf F5 wechselte die Figur
	# sichtbar die Kleidung.
	var sleeve := ViewmodelArms._skin_material()
	_check(sleeve.albedo_color.is_equal_approx(BlockyCharacter.COLOR_HEALTHY),
		"der Aermel hat die Farbe des Koerpers")

	# --- DER NACHLADEWEG IST VOLLSTAENDIG ---
	#
	# Der erste Anlauf hatte den Ablauf grob nachgebaut und fuer den
	# Abschnitt "neues Magazin holen" gar nichts gesetzt — die Hand blieb
	# stehen, und das Nachladen sah abgebrochen aus.
	#
	# Geprueft wird die BAHN, nicht der Code: An den sechs Stationen muss die
	# Hand wirklich woanders sein.
	var handguard := Vector3(0.13, -0.15, -0.46)
	var magwell := Vector3(-0.10, -0.23, -0.43)
	var pulled := magwell + Vector3(0.0, -0.08, 0.0)
	var pouch := Vector3(-0.22, -0.46, -0.10)
	var handle := Vector3(0.06, -0.15, -0.29)

	# GEZIELT GEPRUEFT, NICHT "sechs verschiedene Orte".
	#
	# Genau das hatte ich bei den Figuren schon einmal falsch: Greifen (0,20)
	# und Einschieben (0,80) passieren BEIDE am Magazinschacht — sie muessen
	# zusammenfallen. Ein Test auf sechs verschiedene Stellen ist deshalb
	# falsch und wurde hier prompt ein zweites Mal geschrieben.
	# An den WEGMARKEN gemessen, nicht an gegriffenen Zahlen dazwischen.
	# Erster Versuch pruefte bei 0,20 und 0,92 — dort ist die Hand schon
	# wieder unterwegs, und beide Pruefungen waren rot, obwohl der Ablauf
	# stimmte.
	var during_grip := (CharacterAnimation.RELOAD_REACH
		+ CharacterAnimation.RELOAD_GRIP) * 0.5
	var at_grip := CharacterAnimation.reload_hand_path(during_grip, handguard,
		magwell, pulled, pouch, handle)
	var at_seat := CharacterAnimation.reload_hand_path(
		CharacterAnimation.RELOAD_SEAT, handguard, magwell, pulled, pouch, handle)
	var at_charge := CharacterAnimation.reload_hand_path(
		CharacterAnimation.RELOAD_CHARGE, handguard, magwell, pulled, pouch, handle)

	_check(at_grip.distance_to(magwell) < 0.01,
		"waehrend des Greifens liegt die Hand am Schacht (%.3f m)"
			% at_grip.distance_to(magwell))
	_check(at_seat.distance_to(magwell) < 0.01,
		"beim Einschieben wieder dort — dieselbe Stelle, mit Absicht")
	_check(at_charge.distance_to(handle) < 0.01,
		"und zum Schluss am Ladehebel (%.3f m)"
			% at_charge.distance_to(handle))
	_check(at_grip.distance_to(handguard) > 0.15,
		"keine davon mehr am Vorderschaft")

	# Am Schluss zurueck an den Schaft — sonst bliebe die Hand am Ladehebel
	# haengen und die naechste Bewegung faenge falsch an.
	var ending := CharacterAnimation.reload_hand_path(1.0, handguard, magwell,
		pulled, pouch, handle)
	_check(ending.distance_to(handguard) < 0.01,
		"und am Ende liegt die Hand wieder am Vorderschaft (%.3f m)"
			% ending.distance_to(handguard))

	# Die Tasche liegt unter dem Bildrand: Man sieht die Hand hinuntergehen,
	# nicht die Tasche selbst.
	var fetching := CharacterAnimation.reload_hand_path(0.45, handguard,
		magwell, pulled, pouch, handle)
	_check(fetching.y < magwell.y - 0.10,
		"beim Holen greift sie deutlich nach unten (%.3f gegen %.3f m)"
			% [fetching.y, magwell.y])

	model.queue_free()


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


## Prueft die selbstgebauten Meshes auf Dichtheit.
##
## Seit die Modelle angefaste Quader und gekruemmte Koerper benutzen, werden
## die Dreiecke im Code erzeugt statt von Godot. Ein Loch oder ein falsch
## herum gewickeltes Dreieck sieht man am fertigen Bild oft nicht — man sieht
## nur, dass "irgendwas komisch aussieht", und sucht dann an der falschen
## Stelle. Diese Pruefung sagt es direkt.
##
## Dicht heisst: Jede Kante gehoert zu genau zwei Dreiecken. Fehlt eine
## Flaeche, gehoert sie nur zu einer.
func _test_generated_meshes_are_closed() -> void:
	_section("Erzeugte Koerper sind dicht")

	var box_size := Vector3(0.08, 0.05, 0.12)
	var box_mesh := ViewmodelParts.beveled_box_mesh(box_size, 0.004)
	_check_mesh_closed(box_mesh, "angefaster Quader")

	var aabb := box_mesh.get_aabb()
	_check(aabb.size.is_equal_approx(box_size),
		"angefaster Quader behaelt seine Masse (%v statt %v)" % [aabb.size, box_size])
	_check(aabb.get_center().length() < 0.0001,
		"angefaster Quader ist um den Ursprung zentriert")

	# Fase groesser als das Teil dick ist: darf nicht in sich zusammenfallen.
	var thin := ViewmodelParts.beveled_box_mesh(Vector3(0.02, 0.004, 0.006), 0.01)
	_check_mesh_closed(thin, "duennes Blech mit uebergrosser Fase")

	var curved := ViewmodelParts.curved_body_mesh(0.025, 0.046, 0.13, 12.0, 8)
	_check_mesh_closed(curved, "gekruemmter Koerper")

	var straight := ViewmodelParts.curved_body_mesh(0.02, 0.02, 0.06, 0.0, 4)
	_check_mesh_closed(straight, "ungekruemmter Koerper")

	_check_winding(box_mesh, "angefaster Quader")
	_check_winding(curved, "gekruemmter Koerper")


## Prueft die Umlaufrichtung gegen Godots eigene Meshes.
##
## DAS IST DER FIESESTE FEHLER IN DIESER GANZEN DATEI. Godot entscheidet
## ueber Vorder- und Rueckseite anhand der REIHENFOLGE der Eckpunkte, nicht
## anhand der Normale. Sind die Normalen richtig, aber die Wicklung
## spiegelverkehrt, dann sieht die Waffe im Standbild fast normal aus — man
## blickt naemlich durch die zugewandte Wand hindurch auf die Rueckseite der
## abgewandten. Erst im Spiel faellt auf, dass die Waffe hohl wirkt.
##
## Genau das war der Fall: Alle erzeugten Koerper waren spiegelverkehrt
## gewickelt, und im Spiel sah man von links in die Waffen hinein.
##
## Godots BoxMesh ist hier die Wahrheit, gegen die verglichen wird — statt
## eine Konvention aus der Dokumentation abzuschreiben und zu hoffen.
func _check_winding(mesh: ArrayMesh, label: String) -> void:
	var reference := BoxMesh.new()
	reference.size = Vector3.ONE
	var expected := _winding_sign(reference.get_mesh_arrays())
	var actual := _winding_sign(mesh.surface_get_arrays(0))

	_check(expected != 0 and actual == expected,
		"%s ist wie Godots Meshes gewickelt (erwartet %d, ist %d)" % [label, expected, actual])


## +1 wenn das Kreuzprodukt der Kanten mit der Normale gleichgerichtet ist,
## -1 wenn entgegengesetzt, 0 wenn uneinheitlich.
func _winding_sign(arrays: Array) -> int:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]

	var count := indices.size() / 3 if indices.size() > 0 else vertices.size() / 3
	var sign := 0

	for t in range(count):
		var ia := indices[t * 3] if indices.size() > 0 else t * 3
		var ib := indices[t * 3 + 1] if indices.size() > 0 else t * 3 + 1
		var ic := indices[t * 3 + 2] if indices.size() > 0 else t * 3 + 2
		var cross := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
		var current := 1 if cross.dot(normals[ia]) > 0.0 else -1
		if sign == 0:
			sign = current
		elif sign != current:
			return 0

	return sign


## Zaehlt, wie oft jede Kante vorkommt. Bei einem geschlossenen Koerper
## genau zweimal. Zusaetzlich wird geprueft, dass alle Normalen nach aussen
## zeigen — nach innen gedrehte Flaechen sind unsichtbar und hinterlassen
## genau denselben Eindruck wie ein echtes Loch.
func _check_mesh_closed(mesh: ArrayMesh, label: String) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	if vertices.size() < 3 or vertices.size() % 3 != 0:
		_check(false, "%s: Dreiecksliste ist gueltig (%d Punkte)" % [label, vertices.size()])
		return

	var edges := {}
	var centre := Vector3.ZERO
	for v in vertices:
		centre += v
	centre /= float(vertices.size())

	var outward := true
	for i in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		for pair in [[a, b], [b, c], [c, a]]:
			# Kanten richtungsunabhaengig zaehlen, sonst haengt das Ergebnis
			# an der Wicklung statt an der Dichtheit.
			var key := _edge_key(pair[0], pair[1])
			edges[key] = int(edges.get(key, 0)) + 1
		if normals[i].dot((a + b + c) / 3.0 - centre) <= 0.0:
			outward = false

	var open_edges := 0
	for count in edges.values():
		if count != 2:
			open_edges += 1

	_check(open_edges == 0,
		"%s ist geschlossen (%d offene Kanten von %d)" % [label, open_edges, edges.size()])
	_check(outward, "%s: alle Normalen zeigen nach aussen" % label)


func _edge_key(a: Vector3, b: Vector3) -> String:
	var first := _point_key(a)
	var second := _point_key(b)
	return first + "|" + second if first < second else second + "|" + first


## Punkte auf ein feines Raster runden, damit Rechenungenauigkeiten zwei
## eigentlich gleiche Ecken nicht zu verschiedenen machen.
func _point_key(p: Vector3) -> String:
	return "%.6f,%.6f,%.6f" % [p.x, p.y, p.z]


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

	if rear == null and front == null:
		# WAFFE OHNE NOTVISIERUNG. Die AR-15 hat seit dem neuen Modell keine
		# mehr — man zielt ueber die nackte Schiene, bis eine Optik drauf ist.
		# Das ist eine Entscheidung des Modells, kein Fehler.
		#
		# Geprueft wird trotzdem, und zwar das, worauf es dann ankommt: Die
		# Zielhoehe muss ueber dem Lauf liegen und darf nicht auf null stehen.
		# Bei sight_height = 0 wuerde weapon_view.gd die Waffe beim Zielen gar
		# nicht absenken, und der Spieler schoesse ueber alles hinweg.
		_check(model.sight_height > 0.0,
			"%s: ohne Notvisierung ist die Zielhoehe trotzdem gesetzt (%.4f)"
				% [label, model.sight_height])
		return

	if rear == null or front == null:
		# Nur eines von beiden ist immer ein Fehler: Entweder die Waffe hat
		# eine Visierung oder sie hat keine.
		_check(false, "%s: Kimme und Korn entweder beide oder keines" % label)
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
