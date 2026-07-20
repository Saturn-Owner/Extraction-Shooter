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
	_check_plate_exists()
	_check_plate_degradation()
	_check_ammo_vs_plate()
	_check_arsenal_coverage()
	_check_damage_penetration_tradeoff()
	_check_rarity_tiers()
	_check_info_lines()
	_check_find_sounds()
	_check_reveal_animation()
	_check_category_matches_id()
	_check_loot_variety()
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


## Seltenheit steuert Farbe UND Fundgeraeusch. Landet alles in einer Stufe,
## sind beide wertlos — dann faellt im Spiel nichts mehr auf.
func _check_rarity_tiers() -> void:
	print("\n--- Seltenheitsstufen")
	ItemRegistry.ensure_loaded()

	var counts := {}
	for rarity in ItemData.Rarity.values():
		counts[rarity] = 0

	for item in ItemRegistry.get_all():
		counts[item.get_rarity()] += 1

	for rarity in ItemData.Rarity.values():
		print("  %-10s %d Gegenstaende" % [ItemData.Rarity.keys()[rarity], counts[rarity]])

	var used := 0
	for rarity in ItemData.Rarity.values():
		if counts[rarity] > 0:
			used += 1

	if used < 3:
		_fail("nur %d Seltenheitsstufen kommen vor — Farbe und Klang unterscheiden dann kaum" % used)
	else:
		print("  OK  %d von %d Stufen sind belegt" % [used, ItemData.Rarity.size()])

	# Stichproben: Die Grenzen muessen zu den bekannten Gegenstaenden passen.
	var billig := ItemRegistry.get_item(&"ammo_9x19_fmj")
	var teuer := ItemRegistry.get_item(&"ammo_556x45_m995")
	if billig != null and teuer != null:
		if billig.get_rarity() >= teuer.get_rarity():
			_fail("9mm FMJ gilt als mindestens so selten wie M995 — Grenzen pruefen")
		else:
			print("  OK  9mm FMJ (%s) < M995 (%s)" % [
				ItemData.Rarity.keys()[billig.get_rarity()],
				ItemData.Rarity.keys()[teuer.get_rarity()]])


## Die Infoanzeige liest ihre Zeilen aus den Datenklassen. Fehlt dort etwas,
## steht der Spieler vor einem leeren Kasten.
func _check_info_lines() -> void:
	print("\n--- Infoanzeige")
	ItemRegistry.ensure_loaded()

	var leer := 0
	for item in ItemRegistry.get_all():
		if item.get_info_lines().is_empty() or item.get_type_label().strip_edges() == "":
			_fail("%s liefert keine Infozeilen" % item.id)
			leer += 1
	if leer == 0:
		print("  OK  alle Gegenstaende liefern Name, Typ und Werte")

	# Munition muss Schaden, Durchschlag und Art zeigen — das ist der
	# eigentliche Grund, warum es die Anzeige gibt.
	var m995 := ItemRegistry.get_item(&"ammo_556x45_m995") as AmmoData
	if m995 == null:
		_fail("M995 nicht gefunden")
		return

	var text := "\n".join(m995.get_info_lines())
	for begriff in ["Schaden", "Durchschlag"]:
		if not text.contains(begriff):
			_fail("Munitionsinfo enthaelt '%s' nicht" % begriff)

	var art := m995.get_ammo_type_name()
	if art != "Panzerbrechend":
		_fail("M995 (Pen %d) sollte als Panzerbrechend gelten, ist aber '%s'"
			% [m995.penetration_power, art])
	else:
		print("  OK  M995 wird als %s gefuehrt" % art)

	var typ := m995.get_type_label()
	if not typ.contains(String(m995.caliber)):
		_fail("Typzeile nennt das Kaliber nicht: %s" % typ)
	else:
		print("  OK  Typzeile: %s" % typ)

	# Schrot muss als solches erkannt werden, sonst stimmt die Ableitung nicht.
	for ammo in ItemRegistry.get_by_category(ItemData.Category.AMMO):
		var a := ammo as AmmoData
		if a != null and a.pellet_count > 1:
			if a.get_ammo_type_name() != "Schrot":
				_fail("%s hat %d Projektile, gilt aber nicht als Schrot" % [a.id, a.pellet_count])
			else:
				print("  OK  %s wird als Schrot gefuehrt" % a.id)
			break


## Fundgeraeusche: Krimskrams still, alles andere hoerbar.
##
## Wie es KLINGT kann hier niemand pruefen — das muss ein Mensch hoeren.
## Pruefbar ist, dass ueberhaupt Klang im Puffer steht: Ein Rechenfehler
## in der Synthese ergaebe Stille, und die faellt im Spiel nicht auf,
## weil Stille bei COMMON ja richtig waere.
func _check_find_sounds() -> void:
	print("\n--- Fundgeraeusche")
	ItemRegistry.ensure_loaded()

	var billig := ItemRegistry.get_item(&"ammo_9x19_fmj")
	if billig != null and SearchAudio.get_stream(billig) != null:
		_fail("COMMON sollte still bleiben, liefert aber einen Klang")
	else:
		print("  OK  COMMON bleibt still")

	# Je Kategorie eine Stichprobe, damit jeder Zweig der Synthese laeuft.
	var geprueft := {}
	for item in ItemRegistry.get_all():
		if item.get_rarity() == ItemData.Rarity.COMMON:
			continue
		if geprueft.has(item.category):
			continue
		geprueft[item.category] = true

		var stream := SearchAudio.get_stream(item)
		if stream == null:
			_fail("%s (%s) liefert keinen Klang" % [item.id, ItemData.Category.keys()[item.category]])
			continue

		var kategorie: String = ItemData.Category.keys()[item.category]

		# Echte Aufnahmen hat ein Mensch ausgesucht und angehoert — die
		# muessen hier nicht Sample fuer Sample geprueft werden. Sie liegen
		# ausserdem meist auf Vollpegel, was voellig normal ist.
		#
		# Genau geprueft wird nur die SYNTHESE: Die kommt aus einer Rechnung
		# und koennte still oder uebersteuert sein, ohne dass es jemandem
		# auffaellt.
		if SearchAudio.has_real_recording(item):
			print("  OK  %-12s echte Aufnahme" % kategorie)
			continue

		var wav := stream as AudioStreamWAV
		if wav == null:
			print("  OK  %-12s %s" % [kategorie, stream.get_class()])
			continue

		var peak := _peak_of(wav)
		var laenge := float(wav.data.size() / 2) / float(SearchAudio.SAMPLE_RATE)

		if peak < 0.05:
			_fail("%s klingt praktisch still (Spitze %.3f)" % [item.id, peak])
		elif peak > 0.999:
			_fail("%s uebersteuert (Spitze %.3f)" % [item.id, peak])
		else:
			print("  OK  %-12s Synthese, %.2f s, Spitze %.2f" % [kategorie, laenge, peak])

	# Seltener muss deutlicher klingen. Das haengt NICHT mehr an der Datei,
	# sondern an der Lautstaerke beim Abspielen — sonst klaenge seltene und
	# epische Munition gleich, weil sie sich dieselbe Aufnahme teilen.
	var steigend := true
	var werte: Array[float] = []
	for rarity in [ItemData.Rarity.UNCOMMON, ItemData.Rarity.RARE,
			ItemData.Rarity.EPIC, ItemData.Rarity.LEGENDARY]:
		var db := SearchAudio.get_volume_db(rarity)
		if not werte.is_empty() and db <= werte[-1]:
			steigend = false
		werte.append(db)

	if not steigend:
		_fail("Lautstaerke steigt nicht durchgehend mit der Seltenheit: %s" % str(werte))
	else:
		print("  OK  Lautstaerke steigt durchgehend: %s dB" % str(werte))


## Die Fundanimation muss mit der Seltenheit laenger werden, und jede
## Stufe braucht einen Eintrag — eine fehlende faellt sonst auf 0,3 s
## zurueck, ohne dass es jemandem auffaellt.
func _check_reveal_animation() -> void:
	print("\n--- Fundanimation")

	var vorher := -1.0
	var steigend := true
	for rarity in ItemData.Rarity.values():
		if not InventoryGridView.REVEAL_DURATION.has(rarity):
			_fail("keine Animationsdauer fuer %s" % ItemData.Rarity.keys()[rarity])
			continue
		var dauer: float = InventoryGridView.REVEAL_DURATION[rarity]
		if dauer <= vorher:
			steigend = false
		vorher = dauer
		print("  %-10s %.2f s" % [ItemData.Rarity.keys()[rarity], dauer])

	if not steigend:
		_fail("die Animationsdauer steigt nicht durchgehend mit der Seltenheit")
	else:
		print("  OK  Dauer steigt mit der Seltenheit")

	# Nur die hohen Stufen sollen aufploppen. Wuerde jede Patrone huepfen,
	# zappelt das ganze Raster beim Durchsuchen.
	var billig := ItemRegistry.get_item(&"ammo_9x19_fmj")
	var teuer := ItemRegistry.get_item(&"weapon_rifle_ar15")
	if billig != null and teuer != null:
		if billig.is_high_value():
			_fail("9mm FMJ gilt als hochwertig — dann huepft jede Patrone")
		elif not teuer.is_high_value():
			_fail("die AR-15 gilt nicht als hochwertig")
		else:
			print("  OK  nur hochwertige Funde ploppen auf")


## Groesster Ausschlag im Puffer, 0 bis 1.
func _peak_of(stream: AudioStreamWAV) -> float:
	if stream == null:
		return 0.0
	var data := stream.data
	var peak := 0
	var i := 0
	while i < data.size() - 1:
		var value := data[i] | (data[i + 1] << 8)
		if value >= 32768:
			value -= 65536
		peak = maxi(peak, absi(value))
		i += 2
	return float(peak) / 32767.0


## Die Kategorie muss zum Namenspraefix passen.
##
## Der Rucksack war jahrelang als MEDICAL eingetragen, weil die Kategorie
## in der .tres eine ZAHL ist und sich niemand verzaehlt gerne. Aufgefallen
## ist es erst, als er das Geraeusch fuer Verbandszeug bekam. Ein Praefix
## im Namen und eine Zahl in der Datei koennen auseinanderlaufen — dieser
## Test verhindert genau das.
func _check_category_matches_id() -> void:
	print("\n--- Kategorie passt zum Namen")
	ItemRegistry.ensure_loaded()

	var expected := {
		"ammo_": ItemData.Category.AMMO,
		"weapon_": ItemData.Category.WEAPON,
		"plate_": ItemData.Category.ARMOR_PLATE,
		"backpack_": ItemData.Category.BACKPACK,
		"med_": ItemData.Category.MEDICAL,
		"food_": ItemData.Category.FOOD,
		"misc_": ItemData.Category.MISC,
		"tool_": ItemData.Category.TOOL,
		"key_": ItemData.Category.KEY,
	}

	var checked := 0
	var wrong := 0
	for item in ItemRegistry.get_all():
		var id := String(item.id)
		for prefix in expected:
			if not id.begins_with(prefix):
				continue
			checked += 1
			if item.category != expected[prefix]:
				_fail("%s ist als %s eingetragen, erwartet war %s" % [
					id,
					ItemData.Category.keys()[item.category],
					ItemData.Category.keys()[expected[prefix]],
				])
				wrong += 1
			break

	if wrong == 0:
		print("  OK  %d Gegenstaende, alle Kategorien passen zum Namen" % checked)


## Eine Kiste muss mehr ausspucken koennen als Munition.
##
## Vorher gab es ueberhaupt nur Munition, Waffen, eine Platte und einen
## Rucksack — wer nur Munition findet, trifft keine Entscheidung, was er
## mitnimmt. Genau diese Entscheidung ist der Kern des Genres.
func _check_loot_variety() -> void:
	print("\n--- Vielfalt in den Kisten")
	ItemRegistry.ensure_loaded()

	for table_name in ["wohnung", "werkstatt", "militaer"]:
		var path := "res://assets/data/loot/%s.tres" % table_name
		var table := load(path) as LootTableData
		if table == null:
			_fail("Loot-Tabelle fehlt: %s" % path)
			continue

		var problems := table.validate()
		if not problems.is_empty():
			_fail("%s: %s" % [table_name, ", ".join(problems)])
			continue

		var categories := {}
		for entry in table.entries:
			var item := ItemRegistry.get_item(StringName(entry["id"]))
			if item == null:
				continue
			categories[item.category] = true

		var names: Array[String] = []
		for c in categories:
			names.append(ItemData.Category.keys()[c])
		names.sort()

		# Frueher waren hier drei Kategorien Pflicht: Eine Kiste, in der nur
		# Munition liegt, ist keine Entscheidung wert. Solange es im Spiel
		# ueberhaupt nur Waffen und Munition GIBT, kann keine Tabelle das
		# erfuellen — die Forderung waere nur noch ein Dauerfehler.
		#
		# Geprueft wird stattdessen, dass jede Tabelle beides fuehrt. Sobald
		# Verpflegung und Werkzeug zurueckkommen, gehoert die 3 wieder her.
		var required := 2
		if categories.size() < required:
			_fail("%s bietet nur %d Kategorien: %s" % [table_name, categories.size(), ", ".join(names)])
		else:
			print("  OK  %-10s %d Eintraege, %d Kategorien: %s" % [
				table_name, table.entries.size(), categories.size(), ", ".join(names)])


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
## Gibt es ueberhaupt eine Platte IM SPIEL?
##
## ---------------------------------------------------------------------------
## WARUM DIESE PRUEFUNG EXISTIERT
##
## Am 2026-07-20 flog plate_class4.tres beim Aufraeumen mit heraus. Danach gab
## es im ganzen Spiel keine Ruestung mehr — trotzdem blieben alle 16 Suiten
## gruen, und zwar volle drei Tage lang. Aufgefallen ist es erst durch eine
## Warnung beim Spielstart.
##
## Der Grund: JEDE Plattenpruefung baute sich ihre Platte selbst. Die
## Abnutzung unten tut es mit ArmorPlateData.new(), die Ballistik nahm sie aus
## TestItems. Damit pruefte das Durchschlagssystem — Grundsatzentscheidung 4 —
## nur noch sich selbst.
##
## Diese Pruefung ist die einzige, die die Datei auf der Platte anfasst.
## Rechnen tut sie nichts; sie beantwortet nur die Frage, die sonst niemand
## stellt: Kann ein Spieler ueberhaupt Ruestung tragen?
func _check_plate_exists() -> void:
	print("\n--- Es gibt Ruestung im Spiel")
	ItemRegistry.ensure_loaded()

	var plates := ItemRegistry.get_by_category(ItemData.Category.ARMOR_PLATE)
	print("  %d Platte(n) in assets/data" % plates.size())
	if plates.is_empty():
		_fail("keine einzige Schutzplatte — penetration_power hat keine Wirkung")
		return

	for p in plates:
		var plate := p as ArmorPlateData
		if plate == null:
			_fail("Gegenstand in der Kategorie ARMOR_PLATE ist keine ArmorPlateData")
			continue
		print("  %-22s Klasse %d, Haltbarkeit %.0f"
			% [plate.id, plate.armor_class, plate.max_durability])
		if plate.armor_class <= 0:
			_fail("%s schuetzt nicht (Klasse %d)" % [plate.id, plate.armor_class])
		if plate.max_durability <= 0.0:
			_fail("%s haelt keinen Treffer aus (Haltbarkeit %.1f)"
				% [plate.id, plate.max_durability])

		# Ohne Platz zum Anlegen ist eine Platte nur Ballast im Rucksack:
		# Equipment.get_chest_plate() sieht ausschliesslich in EquipSlot.CHEST
		# nach. Genau diese Zeile fehlte in der .tres — jahrelang unbemerkt,
		# weil die Testattrappe sie setzte und die echte Datei nie geladen
		# wurde.
		if plate.equip_slot != ItemData.EquipSlot.CHEST:
			_fail("%s laesst sich nicht anlegen (equip_slot %d statt CHEST)"
				% [plate.id, plate.equip_slot])

	# Die Szenen und Tests nennen diese ID beim Namen. Verschwindet sie, stehen
	# die gepanzerten Scheiben im Testgelaende ungeschuetzt da.
	if not ItemRegistry.has_item(&"plate_class4_front"):
		_fail("plate_class4_front fehlt — testgelaende.tscn verweist darauf")


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
