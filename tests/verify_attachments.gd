## Prüft Anbauteile: Daten, Kompatibilität und die Berechnung der Werte.
##
##   godot --headless --path . --script res://tests/verify_attachments.gd
##
## Der wichtigste Test hier ist _test_registry_stays_untouched(). Alles andere
## kann man beim Spielen bemerken — eine stillschweigend veränderte Vorlage
## nicht: Sie würde jede Waffe desselben Typs im ganzen Spiel mitverändern,
## und das fällt erst auf, wenn Werte "irgendwie nicht mehr stimmen".
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Anbauteile prüfen ===\n")
	_test_attachments_exist()
	_test_every_attachment_fits_somewhere()
	_test_foreign_interfaces_are_rejected()
	_test_empty_build_matches_template()
	_test_modifiers_apply()
	_test_order_does_not_matter()
	_test_values_stay_in_range()
	_test_registry_stays_untouched()
	_test_build_survives_serialisation()
	_test_attached_weapons_do_not_stack()
	_test_mount_anchors_exist()
	_test_attachments_become_visible()
	_test_sight_line_follows_the_optic()
	_test_muzzle_follows_the_suppressor()
	_test_workbench_rejects_nonsense()
	_test_workbench_options_are_mountable()

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


func _attachments() -> Array[AttachmentData]:
	var result: Array[AttachmentData] = []
	for item in ItemRegistry.get_by_category(ItemData.Category.ATTACHMENT):
		var attachment := item as AttachmentData
		if attachment != null:
			result.append(attachment)
	return result


func _weapons() -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var weapon := item as WeaponData
		if weapon != null:
			result.append(weapon)
	return result


func _test_attachments_exist() -> void:
	_section("Daten")

	var attachments := _attachments()
	_check(attachments.size() > 0, "Anbauteile in der Registry gefunden (%d)" % attachments.size())

	for attachment in attachments:
		var problems := attachment.validate()
		_check(problems.is_empty(), "%s ist gültig%s"
			% [attachment.id, "" if problems.is_empty() else ": " + ", ".join(problems)])
		# Ein Teil ohne Wirkung ist fast immer ein vergessener Wert.
		_check(attachment.changes_stats(), "%s ändert überhaupt etwas" % attachment.id)

	var weapons_with_mounts := 0
	for weapon in _weapons():
		if not weapon.mounts.is_empty():
			weapons_with_mounts += 1
	_check(weapons_with_mounts >= 3, "mindestens drei Waffen haben Aufnahmen (%d)" % weapons_with_mounts)


## Ein Teil, das an keine Waffe passt, ist toter Inhalt — meistens ein
## Tippfehler im interface_tag.
func _test_every_attachment_fits_somewhere() -> void:
	_section("Jedes Teil passt irgendwohin")

	var weapons := _weapons()
	for attachment in _attachments():
		var fits: Array[String] = []
		for weapon in weapons:
			if weapon.accepts_attachment(attachment):
				fits.append(weapon.display_name)
		_check(not fits.is_empty(), "%s passt an: %s" % [attachment.id, ", ".join(fits)])


func _test_foreign_interfaces_are_rejected() -> void:
	_section("Fremde Schnittstellen werden abgewiesen")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var pistol := ItemRegistry.get_item(&"weapon_pistol_g17") as WeaponData
	var suppressor_9mm := ItemRegistry.get_item(&"muzzle_suppressor_9mm") as AttachmentData
	var suppressor_556 := ItemRegistry.get_item(&"muzzle_suppressor_556") as AttachmentData
	var foregrip := ItemRegistry.get_item(&"foregrip_vertical") as AttachmentData

	_check(not ar15.accepts_attachment(suppressor_9mm),
		"9-mm-Dämpfer passt nicht auf das 5,56er Gewehr")
	_check(not pistol.accepts_attachment(suppressor_556),
		"5,56er Dämpfer passt nicht auf die Pistole")
	_check(ar15.accepts_attachment(suppressor_556), "5,56er Dämpfer passt aufs Gewehr")
	_check(pistol.accepts_attachment(suppressor_9mm), "9-mm-Dämpfer passt auf die Pistole")
	# Die Pistole hat den Steckplatz gar nicht.
	_check(not pistol.accepts_attachment(foregrip),
		"Vordergriff passt nicht an die Pistole (kein Steckplatz)")
	_check(pistol.find_mount(AttachmentData.Slot.FOREGRIP) == null,
		"Pistole hat keine Vordergriff-Aufnahme")


func _test_empty_build_matches_template() -> void:
	_section("Ohne Anbauteile ändert sich nichts")

	for weapon in _weapons():
		var result := WeaponBuild.apply(weapon, WeaponBuild.new())
		_check(result != null and _fields_equal(weapon, result),
			"%s: leere Bestückung ergibt die Vorlagenwerte" % weapon.display_name)

	# Trotzdem eine eigene Kopie, nicht die Vorlage selbst.
	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var copy := WeaponBuild.apply(ar15, WeaponBuild.new())
	_check(copy != ar15, "auch ohne Anbauteile ist es eine eigene Kopie")
	_check(copy.resource_path == "", "die Kopie hat keinen Ressourcenpfad")
	_check(copy.viewmodel == ar15.viewmodel, "die Kopie behält ihr Modell")
	_check(copy.create_viewmodel() != null, "create_viewmodel() funktioniert an der Kopie")


func _test_modifiers_apply() -> void:
	_section("Werte werden verrechnet")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var comp := ItemRegistry.get_item(&"muzzle_comp_556") as AttachmentData
	var scope := ItemRegistry.get_item(&"sight_scope4x") as AttachmentData

	var build := WeaponBuild.new()
	build.set_attachment(AttachmentData.Slot.MUZZLE, comp.id)
	var with_comp := WeaponBuild.apply(ar15, build)

	_check(with_comp.recoil_vertical < ar15.recoil_vertical,
		"Kompensator senkt den Hochschlag (%.1f -> %.1f)"
			% [ar15.recoil_vertical, with_comp.recoil_vertical])
	_check(with_comp.loudness_multiplier > ar15.loudness_multiplier,
		"Kompensator macht lauter (%.2f -> %.2f)"
			% [ar15.loudness_multiplier, with_comp.loudness_multiplier])

	build.set_attachment(AttachmentData.Slot.SIGHT, scope.id)
	var with_both := WeaponBuild.apply(ar15, build)
	_check(is_equal_approx(with_both.ads_fov, scope.ads_fov_override),
		"Zielfernrohr gibt das Sichtfeld vor (%.0f)" % with_both.ads_fov)
	_check(with_both.ads_time_multiplier > 1.0,
		"Zielfernrohr macht das Zielen träger (%.2f)" % with_both.ads_time_multiplier)
	_check(with_both.ergonomics < ar15.ergonomics,
		"beide zusammen kosten Ergonomie (%d -> %d)" % [ar15.ergonomics, with_both.ergonomics])

	# Ein Teil, das nicht passt, darf die Werte nicht anfassen.
	var wrong := WeaponBuild.new()
	wrong.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_suppressor_9mm")
	var unchanged := WeaponBuild.apply(ar15, wrong)
	_check(is_equal_approx(unchanged.recoil_vertical, ar15.recoil_vertical),
		"ein unpassendes Teil verändert nichts")


## Die Reihenfolge darf keine Rolle spielen — sonst hinge das Ergebnis davon
## ab, in welcher Reihenfolge der Spieler an der Werkbank geklickt hat.
func _test_order_does_not_matter() -> void:
	_section("Reihenfolge ist egal")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData

	var forward := WeaponBuild.new()
	forward.set_attachment(AttachmentData.Slot.SIGHT, &"sight_reddot")
	forward.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_suppressor_556")
	forward.set_attachment(AttachmentData.Slot.GRIP, &"grip_rubber")
	forward.set_attachment(AttachmentData.Slot.FOREGRIP, &"foregrip_vertical")

	var backward := WeaponBuild.new()
	backward.set_attachment(AttachmentData.Slot.FOREGRIP, &"foregrip_vertical")
	backward.set_attachment(AttachmentData.Slot.GRIP, &"grip_rubber")
	backward.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_suppressor_556")
	backward.set_attachment(AttachmentData.Slot.SIGHT, &"sight_reddot")

	var a := WeaponBuild.apply(ar15, forward)
	var b := WeaponBuild.apply(ar15, backward)
	_check(_fields_equal(a, b), "vier Teile in umgekehrter Reihenfolge ergeben dasselbe")


func _test_values_stay_in_range() -> void:
	_section("Werte bleiben im gültigen Bereich")

	# Volle Bestückung an jeder Waffe, die sie trägt.
	for weapon in _weapons():
		if weapon.mounts.is_empty():
			continue
		var build := WeaponBuild.new()
		for mount in weapon.mounts:
			for attachment in _attachments():
				if weapon.accepts_attachment(attachment) and attachment.slot == mount.slot:
					build.set_attachment(attachment.slot, attachment.id)
					break

		var result := WeaponBuild.apply(weapon, build)
		var ok := (
			result.recoil_vertical >= 0.0
			and result.ergonomics >= 0 and result.ergonomics <= 100
			and result.accuracy_moa > 0.0
			and result.ads_spread_multiplier > 0.0 and result.ads_spread_multiplier <= 1.0
			and result.ads_move_multiplier > 0.0 and result.ads_move_multiplier <= 1.0
			and result.muzzle_velocity_modifier > 0.0
			and result.ads_fov >= 8.0 and result.ads_fov <= 75.0
		)
		_check(ok, "%s voll bestückt bleibt in gültigen Grenzen (Ergo %d, MOA %.2f)"
			% [weapon.display_name, result.ergonomics, result.accuracy_moa])


## DER WICHTIGSTE TEST.
##
## Die Ressourcen aus der Registry werden von allen Exemplaren einer Waffe
## geteilt. Würde das Bestücken sie verändern, bekäme jede AR-15 im Spiel
## gleichzeitig einen Schalldämpfer. Deshalb hier: Momentaufnahme aller Werte,
## dann kräftig bestücken und benutzen, dann vergleichen.
func _test_registry_stays_untouched() -> void:
	_section("Die Vorlage bleibt unberührt")

	var before := {}
	for weapon in _weapons():
		before[weapon.id] = _snapshot(weapon)

	# Jede Waffe voll bestücken, die Werte holen und daran herumschreiben.
	for weapon in _weapons():
		var build := WeaponBuild.new()
		for attachment in _attachments():
			if weapon.accepts_attachment(attachment):
				build.set_attachment(attachment.slot, attachment.id)

		var effective := WeaponBuild.apply(weapon, build)
		# Absichtlich grob an der Kopie herumschreiben.
		effective.recoil_vertical = 1.0
		effective.ergonomics = 1
		effective.accuracy_moa = 19.0
		effective.fire_modes.clear()
		effective.mounts.clear()

	var all_intact := true
	var broken: Array[String] = []
	for weapon in _weapons():
		var after := _snapshot(weapon)
		if after != before[weapon.id]:
			all_intact = false
			broken.append(String(weapon.id))

	_check(all_intact, "keine Vorlage wurde verändert%s"
		% ("" if all_intact else ": " + ", ".join(broken)))

	# Und die Waffe in der Hand trennt sauber zwischen beidem.
	var gun := Weapon.new()
	gun.build = WeaponBuild.new()
	gun.build.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_suppressor_556")
	gun.setup(&"weapon_rifle_ar15", &"ammo_556x45_m855a1")

	var registry_copy := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	_check(gun.base_data == registry_copy, "base_data ist die Ressource aus der Registry")
	_check(gun.data != registry_copy, "data ist eine eigene Kopie")
	_check(gun.data.resource_path == "", "die Kopie liegt nicht im Ressourcen-Cache")
	_check(gun.data.recoil_vertical < registry_copy.recoil_vertical,
		"die Kopie trägt den gedämpften Rückstoß (%.1f statt %.1f)"
			% [gun.data.recoil_vertical, registry_copy.recoil_vertical])
	gun.free()


func _test_build_survives_serialisation() -> void:
	_section("Bestückung übersteht Speichern und Laden")

	var stack := ItemStack.create(&"weapon_rifle_ar15")
	stack.attachments[int(AttachmentData.Slot.SIGHT)] = &"sight_reddot"
	stack.attachments[int(AttachmentData.Slot.MUZZLE)] = &"muzzle_suppressor_556"

	var restored := ItemStack.from_dict(stack.to_dict())
	_check(restored.attachments.size() == 2, "beide Teile sind wieder da")
	_check(restored.attachments.get(int(AttachmentData.Slot.SIGHT)) == &"sight_reddot",
		"das Visier sitzt im richtigen Steckplatz")
	_check(restored.attachments.get(int(AttachmentData.Slot.MUZZLE)) == &"muzzle_suppressor_556",
		"der Dämpfer sitzt im richtigen Steckplatz")

	var build := WeaponBuild.from_stack(restored)
	_check(build.get_attachment(AttachmentData.Slot.SIGHT) != null,
		"aus dem Exemplar lässt sich die Bestückung lesen")


func _test_attached_weapons_do_not_stack() -> void:
	_section("Bestückte Waffen stapeln nicht")

	var a := ItemStack.create(&"weapon_rifle_ar15")
	var b := ItemStack.create(&"weapon_rifle_ar15")
	a.attachments[int(AttachmentData.Slot.SIGHT)] = &"sight_reddot"

	_check(not a.can_merge_with(b), "bestückt und unbestückt lassen sich nicht zusammenlegen")


## Baut ein Waffenmodell mit Bestückung, ohne Szenenbaum.
func _build_model(weapon: WeaponData, build: WeaponBuild) -> WeaponViewmodel:
	var model := weapon.create_viewmodel()
	model.weapon_data = weapon
	model.attachments = build.attachments.duplicate()
	model.build()
	return model


## Jeder Ankername muss im gebauten Modell wirklich existieren.
##
## Ein Tippfehler wäre sonst ein stiller Fehlschlag: Das Anbauteil
## verschwindet einfach, ohne Fehlermeldung im Spiel. Genau die Art Fehler,
## die man stundenlang an der falschen Stelle sucht.
func _test_mount_anchors_exist() -> void:
	_section("Aufnahme-Knoten existieren")

	for weapon in _weapons():
		if weapon.mounts.is_empty():
			continue
		var model := _build_model(weapon, WeaponBuild.new())
		for mount in weapon.mounts:
			var anchor := model.get_node_or_null(String(mount.anchor))
			_check(anchor != null, "%s: Anker '%s' für %s vorhanden"
				% [weapon.display_name, mount.anchor, AttachmentData.slot_name(mount.slot)])
		model.free()


func _test_attachments_become_visible() -> void:
	_section("Anbauteile erscheinen am Modell")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData

	var bare := _build_model(ar15, WeaponBuild.new())
	var iron_rear := bare.get_node_or_null("RearSight") as Node3D
	_check(iron_rear != null and iron_rear.visible, "ohne Optik ist die Kimme sichtbar")
	_check(bare.mounted.is_empty(), "ohne Bestückung hängt nichts an den Aufnahmen")
	bare.free()

	var build := WeaponBuild.new()
	build.set_attachment(AttachmentData.Slot.SIGHT, &"sight_reddot")
	build.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_suppressor_556")
	build.set_attachment(AttachmentData.Slot.GRIP, &"grip_target")
	build.set_attachment(AttachmentData.Slot.FOREGRIP, &"foregrip_vertical")
	var kitted := _build_model(ar15, build)

	_check(kitted.mounted.size() == 4, "alle vier Teile sind montiert (%d)" % kitted.mounted.size())

	# Was ersetzt wurde, ist weg — aber nicht gelöscht.
	for hidden_name in ["RearSight", "FrontSight", "FlashHider", "GripAssembly"]:
		var node := kitted.get_node_or_null(hidden_name) as Node3D
		_check(node != null and not node.visible,
			"%s ist vorhanden, aber ausgeblendet" % hidden_name)

	# Und die beweglichen Teile sind trotz Umbau noch auffindbar.
	_check(kitted.action != null and kitted.trigger != null and kitted.magazine != null,
		"die beweglichen Teile werden weiterhin gefunden")
	kitted.free()


## Zielt der Spieler durch das, wodurch er schaut?
##
## Das ist die fehleranfälligste Rechnung im ganzen Vorhaben: weapon_view.gd
## senkt die Waffe beim Zielen um sight_height ab. Stimmt der Wert nicht, sitzt
## der Rotpunkt sichtbar neben der Bildmitte — und die Waffe schiesst dorthin,
## wo der Punkt NICHT ist.
func _test_sight_line_follows_the_optic() -> void:
	_section("Die Visierlinie folgt der Optik")

	for entry in [
		{weapon = &"weapon_rifle_ar15", optic = &"sight_reddot"},
		{weapon = &"weapon_rifle_ar15", optic = &"sight_scope4x"},
		{weapon = &"weapon_pistol_g17", optic = &"sight_micro_dot"},
		{weapon = &"weapon_shotgun_m870", optic = &"sight_reddot"},
	]:
		var weapon := ItemRegistry.get_item(entry.weapon) as WeaponData
		var build := WeaponBuild.new()
		build.set_attachment(AttachmentData.Slot.SIGHT, entry.optic)
		var model := _build_model(weapon, build)

		var mount := weapon.find_mount(AttachmentData.Slot.SIGHT)
		var anchor := model.get_node_or_null(String(mount.anchor)) as Node3D
		var part: AttachmentViewmodel = model.mounted.get(int(AttachmentData.Slot.SIGHT))

		if anchor == null or part == null or part.aim_point == null:
			_check(false, "%s + %s: Optik und Zielpunkt gefunden" % [weapon.display_name, entry.optic])
			model.free()
			continue

		var expected := anchor.position.y + part.aim_point.position.y
		_check(is_equal_approx(model.sight_height, expected),
			"%s + %s: Zielhöhe stimmt (%.4f)" % [weapon.display_name, entry.optic, model.sight_height])
		_check(model.sight_height > model.iron_sight_height,
			"%s + %s: die Optik sitzt höher als die Notvisierung (%.4f > %.4f)"
				% [weapon.display_name, entry.optic, model.sight_height, model.iron_sight_height])
		_check(is_zero_approx(anchor.position.x) and is_zero_approx(part.aim_point.position.x),
			"%s + %s: der Zielpunkt steht mittig" % [weapon.display_name, entry.optic])

		model.free()

	# Ohne Optik bleibt alles wie vorher — das ist der Rückfall, auf den sich
	# verify_weapon_handling verlässt.
	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var bare := _build_model(ar15, WeaponBuild.new())
	_check(is_equal_approx(bare.sight_height, bare.iron_sight_height),
		"ohne Optik gilt weiterhin die eingebaute Visierhöhe")
	bare.free()


func _test_muzzle_follows_the_suppressor() -> void:
	_section("Die Mündung wandert mit dem Dämpfer")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var build := WeaponBuild.new()
	build.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_suppressor_556")
	var model := _build_model(ar15, build)

	_check(model.muzzle_z < model.bare_muzzle_z,
		"die Mündung sitzt weiter vorn (%.3f statt %.3f)" % [model.muzzle_z, model.bare_muzzle_z])
	_check(model.muzzle_point != null and is_equal_approx(model.muzzle_point.position.z, model.muzzle_z),
		"der Mündungspunkt sitzt an der neuen Mündung")
	model.free()

	# Ohne Aufsatz bleibt die Zusicherung aus verify_weapon_handling gültig.
	var bare := _build_model(ar15, WeaponBuild.new())
	_check(is_equal_approx(bare.muzzle_z, bare.bare_muzzle_z),
		"ohne Aufsatz bleibt die Mündung, wo sie war")
	bare.free()


## Alle gespeicherten Eigenschaften einer Ressource als Vergleichswert.
##
## Über die Eigenschaftsliste statt einer Handliste, damit neue Felder
## automatisch mitgeprüft werden.
##
## Verglichen werden WERTE, nicht Objekte: `duplicate(true)` erzeugt für die
## Aufnahmen eigene Unterressourcen, die inhaltlich gleich, als Objekt aber
## verschieden sind. Ein direkter Vergleich wäre deshalb immer "ungleich" und
## der Test damit wertlos. Der Ressourcenpfad fällt ebenfalls raus — dass die
## Kopie keinen hat, ist gewollt und wird an anderer Stelle geprüft.
const IGNORED_PROPERTIES := [
	"resource_path", "resource_name", "resource_local_to_scene", "script",
]


func _snapshot(resource: Resource) -> Dictionary:
	var values := {}
	for property in resource.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE):
			continue
		if IGNORED_PROPERTIES.has(property.name):
			continue
		values[property.name] = _to_value(resource.get(property.name))
	return values


## Wandelt einen Wert in etwas rein Vergleichbares.
func _to_value(value: Variant) -> Variant:
	if value is WeaponMount:
		var mount := value as WeaponMount
		return [mount.slot, String(mount.interface_tag), String(mount.anchor),
			mount.hides.duplicate()]
	if value is Script:
		return (value as Script).resource_path
	if value is Array:
		var items := []
		for entry in value:
			items.append(_to_value(entry))
		return items
	return value


func _fields_equal(a: WeaponData, b: WeaponData) -> bool:
	return _snapshot(a) == _snapshot(b)


## Die Werkbank muss Unfug ablehnen, BEVOR er im ItemStack landet.
##
## Der Test ruft bewusst die statischen Prüfungen auf und nicht die Station
## selbst: Genau diese Funktionen laufen später auf dem Server, wo es weder
## Szenenbaum noch Spieler gibt. Was hier grün ist, ist dort abgesichert.
func _test_workbench_rejects_nonsense() -> void:
	var rifle := ItemStack.create(&"weapon_rifle_ar15")
	var ammo := ItemStack.create(&"ammo_556x45_m855a1")

	_check(WorkbenchStation.check_attach(null, AttachmentData.Slot.SIGHT, &"sight_reddot") != "",
		"Werkbank: ohne Waffe kein Anbau")
	_check(WorkbenchStation.check_attach(ammo, AttachmentData.Slot.SIGHT, &"sight_reddot") != "",
		"Werkbank: an Munition laesst sich nichts schrauben")
	_check(WorkbenchStation.check_attach(rifle, AttachmentData.Slot.SIGHT, &"gibt_es_nicht") != "",
		"Werkbank: unbekanntes Teil wird abgelehnt")
	_check(WorkbenchStation.check_attach(rifle, AttachmentData.Slot.MUZZLE, &"sight_reddot") != "",
		"Werkbank: Visier gehoert nicht in den Muendungsplatz")
	_check(WorkbenchStation.check_attach(rifle, AttachmentData.Slot.SIGHT, &"sight_reddot") == "",
		"Werkbank: Rotpunkt passt auf die AR-15")

	# Eine abgelehnte Anfrage darf den Gegenstand nicht anfassen.
	_check(rifle.attachments.is_empty(), "Werkbank: Pruefung veraendert den Gegenstand nicht")

	# Ein Teil, das an einer fremden Aufnahme sitzt, muss auffliegen.
	var mismatched := 0
	for weapon_id in [&"weapon_rifle_ar15", &"weapon_pistol_g17", &"weapon_shotgun_m870"]:
		var weapon_data := ItemRegistry.get_item(weapon_id) as WeaponData
		for item in ItemRegistry.get_by_category(ItemData.Category.ATTACHMENT):
			var attachment := item as AttachmentData
			var mount := weapon_data.find_mount(attachment.slot)
			if mount != null and mount.interface_tag != attachment.interface_tag:
				mismatched += 1
				_check(WorkbenchStation.check_attach_data(weapon_data, attachment) != "",
					"Werkbank: %s passt nicht an %s" % [attachment.id, weapon_id])
	_check(mismatched > 0, "Werkbank: es gibt ueberhaupt unpassende Paarungen zum Pruefen")


## Was die Werkbank zur Auswahl anbietet, muss sich auch anbauen lassen.
##
## Ohne diesen Test wäre eine Schaltfläche denkbar, die bei jedem Klick eine
## Fehlermeldung erzeugt — der Spieler sähe ein Angebot, das keines ist.
func _test_workbench_options_are_mountable() -> void:
	for weapon_id in [&"weapon_rifle_ar15", &"weapon_pistol_g17", &"weapon_shotgun_m870"]:
		var weapon_data := ItemRegistry.get_item(weapon_id) as WeaponData
		var stack := ItemStack.create(weapon_id)
		var offered := 0

		for slot in weapon_data.get_slots():
			for attachment in WorkbenchStation.get_options(weapon_data, slot):
				offered += 1
				var problem := WorkbenchStation.check_attach(stack, slot, attachment.id)
				_check(problem == "", "Werkbank: %s bietet %s an und nimmt es auch" % [
					weapon_id, attachment.id])

		_check(offered > 0, "Werkbank: %s hat ueberhaupt etwas zur Auswahl" % weapon_id)
