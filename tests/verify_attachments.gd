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
	_test_reticle_sits_in_the_glass()
	_test_muzzle_follows_the_suppressor()
	_test_workbench_rejects_nonsense()
	_test_workbench_options_are_mountable()
	_test_attachments_add_weight()

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

	var shotgun := ItemRegistry.get_item(&"weapon_shotgun_m870") as WeaponData
	var pistol := ItemRegistry.get_item(&"weapon_pistol_g17") as WeaponData
	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var suppressor_9mm := ItemRegistry.get_item(&"muzzle_suppressor_9mm") as AttachmentData
	var choke := ItemRegistry.get_item(&"muzzle_choke_12") as AttachmentData
	var reddot := ItemRegistry.get_item(&"sight_reddot") as AttachmentData

	_check(not shotgun.accepts_attachment(suppressor_9mm),
		"9-mm-Dämpfer passt nicht auf die Flinte")
	_check(not pistol.accepts_attachment(choke),
		"Würgebohrung passt nicht auf die Pistole")
	_check(shotgun.accepts_attachment(choke), "Würgebohrung passt auf die Flinte")
	_check(pistol.accepts_attachment(suppressor_9mm), "9-mm-Dämpfer passt auf die Pistole")
	# Die Pistole hat den Steckplatz gar nicht.
	_check(pistol.find_mount(AttachmentData.Slot.FOREGRIP) == null,
		"Pistole hat keine Vordergriff-Aufnahme")

	# DIE AR-15 IST BEWUSST ABGEKOPPELT.
	#
	# Sie bekommt eigene Teile, die auf ihr neues Modell zugeschnitten sind,
	# und dafür eigene Aufnahmen (ar15_rail statt picatinny). Ein allgemeines
	# Schienenvisier passt deshalb absichtlich NICHT mehr an sie.
	_check(not ar15.accepts_attachment(reddot),
		"das allgemeine Schienenvisier passt nicht mehr an die AR-15")
	_check(shotgun.accepts_attachment(reddot),
		"dieselbe Optik passt weiterhin auf die Flinte")


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

	var gun := ItemRegistry.get_item(&"weapon_shotgun_m870") as WeaponData
	var choke := ItemRegistry.get_item(&"muzzle_choke_12") as AttachmentData
	var scope := ItemRegistry.get_item(&"sight_scope4x") as AttachmentData

	var build := WeaponBuild.new()
	build.set_attachment(AttachmentData.Slot.MUZZLE, choke.id)
	var with_choke := WeaponBuild.apply(gun, build)

	_check(with_choke.accuracy_moa < gun.accuracy_moa,
		"Würgebohrung engt die Garbe ein (%.2f -> %.2f)"
			% [gun.accuracy_moa, with_choke.accuracy_moa])
	_check(with_choke.ergonomics < gun.ergonomics,
		"und kostet etwas Ergonomie (%d -> %d)" % [gun.ergonomics, with_choke.ergonomics])

	build.set_attachment(AttachmentData.Slot.SIGHT, scope.id)
	var with_both := WeaponBuild.apply(gun, build)
	_check(is_equal_approx(with_both.ads_fov, scope.ads_fov_override),
		"Zielfernrohr gibt das Sichtfeld vor (%.0f)" % with_both.ads_fov)
	_check(with_both.ads_time_multiplier > 1.0,
		"Zielfernrohr macht das Zielen träger (%.2f)" % with_both.ads_time_multiplier)
	_check(with_both.ergonomics < with_choke.ergonomics,
		"beide zusammen kosten mehr Ergonomie (%d -> %d)"
			% [with_choke.ergonomics, with_both.ergonomics])

	# Ein Teil, das nicht passt, darf die Werte nicht anfassen.
	var wrong := WeaponBuild.new()
	wrong.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_suppressor_9mm")
	var unchanged := WeaponBuild.apply(gun, wrong)
	_check(is_equal_approx(unchanged.accuracy_moa, gun.accuracy_moa),
		"ein unpassendes Teil verändert nichts")


## Die Reihenfolge darf keine Rolle spielen — sonst hinge das Ergebnis davon
## ab, in welcher Reihenfolge der Spieler an der Werkbank geklickt hat.
func _test_order_does_not_matter() -> void:
	_section("Reihenfolge ist egal")

	var gun := ItemRegistry.get_item(&"weapon_shotgun_m870") as WeaponData

	var forward := WeaponBuild.new()
	forward.set_attachment(AttachmentData.Slot.SIGHT, &"sight_reddot")
	forward.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_choke_12")

	var backward := WeaponBuild.new()
	backward.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_choke_12")
	backward.set_attachment(AttachmentData.Slot.SIGHT, &"sight_reddot")

	var a := WeaponBuild.apply(gun, forward)
	var b := WeaponBuild.apply(gun, backward)
	_check(_fields_equal(a, b), "umgekehrte Reihenfolge ergibt dasselbe")


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
	gun.build.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_choke_12")
	gun.setup(&"weapon_shotgun_m870", &"ammo_12x70_buckshot")

	var registry_copy := ItemRegistry.get_item(&"weapon_shotgun_m870") as WeaponData
	_check(gun.base_data == registry_copy, "base_data ist die Ressource aus der Registry")
	_check(gun.data != registry_copy, "data ist eine eigene Kopie")
	_check(gun.data.resource_path == "", "die Kopie liegt nicht im Ressourcen-Cache")
	_check(gun.data.accuracy_moa < registry_copy.accuracy_moa,
		"die Kopie trägt die engere Garbe (%.2f statt %.2f)"
			% [gun.data.accuracy_moa, registry_copy.accuracy_moa])
	gun.free()


func _test_build_survives_serialisation() -> void:
	_section("Bestückung übersteht Speichern und Laden")

	var stack := ItemStack.create(&"weapon_shotgun_m870")
	stack.attachments[int(AttachmentData.Slot.SIGHT)] = &"sight_reddot"
	stack.attachments[int(AttachmentData.Slot.MUZZLE)] = &"muzzle_choke_12"

	var restored := ItemStack.from_dict(stack.to_dict())
	_check(restored.attachments.size() == 2, "beide Teile sind wieder da")
	_check(restored.attachments.get(int(AttachmentData.Slot.SIGHT)) == &"sight_reddot",
		"das Visier sitzt im richtigen Steckplatz")
	_check(restored.attachments.get(int(AttachmentData.Slot.MUZZLE)) == &"muzzle_choke_12",
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

	var gun := ItemRegistry.get_item(&"weapon_shotgun_m870") as WeaponData

	var bare := _build_model(gun, WeaponBuild.new())
	var iron_rear := bare.get_node_or_null("RearSight") as Node3D
	_check(iron_rear != null and iron_rear.visible, "ohne Optik ist die Kimme sichtbar")
	_check(bare.mounted.is_empty(), "ohne Bestückung hängt nichts an den Aufnahmen")
	bare.free()

	var build := WeaponBuild.new()
	build.set_attachment(AttachmentData.Slot.SIGHT, &"sight_reddot")
	build.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_choke_12")
	var kitted := _build_model(gun, build)

	_check(kitted.mounted.size() == 2, "beide Teile sind montiert (%d)" % kitted.mounted.size())

	# Was ersetzt wurde, ist weg — aber nicht gelöscht.
	for hidden_name in ["RearSight", "FrontSight"]:
		var node := kitted.get_node_or_null(hidden_name) as Node3D
		_check(node != null and not node.visible,
			"%s ist ausgeblendet, aber noch da" % hidden_name)
	kitted.free()


## der Rotpunkt sichtbar neben der Bildmitte — und die Waffe schiesst dorthin,
## wo der Punkt NICHT ist.
func _test_sight_line_follows_the_optic() -> void:
	_section("Die Visierlinie folgt der Optik")

	for entry in [
		{weapon = &"weapon_shotgun_m870", optic = &"sight_scope4x"},
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

	var gun := ItemRegistry.get_item(&"weapon_shotgun_m870") as WeaponData
	var build := WeaponBuild.new()
	build.set_attachment(AttachmentData.Slot.MUZZLE, &"muzzle_choke_12")
	var model := _build_model(gun, build)

	_check(model.muzzle_z < model.bare_muzzle_z,
		"die Mündung sitzt weiter vorn (%.3f statt %.3f)" % [model.muzzle_z, model.bare_muzzle_z])
	_check(model.muzzle_point != null and is_equal_approx(model.muzzle_point.position.z, model.muzzle_z),
		"der Mündungspunkt sitzt an der neuen Mündung")
	model.free()

	# Ohne Aufsatz bleibt die Zusicherung aus verify_weapon_handling gültig.
	var bare := _build_model(gun, WeaponBuild.new())
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
	var rifle := ItemStack.create(&"weapon_shotgun_m870")
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
		"Werkbank: Rotpunkt passt auf die Flinte")

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
## Waffen, deren Sortiment gerade neu gebaut wird und die deshalb (noch)
## nichts anzubieten haben.
##
## BEWUSST EINE LISTE UND KEIN WEGLASSEN DER PRUEFUNG: So steht schwarz auf
## weiss, dass die AR-15 im Umbau ist, und der Test erinnert daran, sobald
## ihre neuen Teile stehen — dann fliegt der Eintrag hier raus.
const IM_UMBAU := []


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

		if IM_UMBAU.has(weapon_id):
			_check(offered == 0, "Werkbank: %s ist im Umbau und bietet noch nichts an" % weapon_id)
		else:
			_check(offered > 0, "Werkbank: %s hat ueberhaupt etwas zur Auswahl" % weapon_id)


## Anbauteile muessen wiegen.
##
## Ohne das waere ein Rotpunktvisier ein reiner Gewinn: schneller im Anschlag,
## bessere Ergonomie, kein Nachteil — dann gaebe es nie einen Grund, ohne zu
## laufen. Ueber das Gewicht bremst jede Bestueckung den Spieler, und damit
## hat die Entscheidung an der Werkbank einen Preis.
func _test_attachments_add_weight() -> void:
	_section("Anbauteile wiegen mit")

	var stack := ItemStack.create(&"weapon_shotgun_m870")
	var bare := stack.get_total_weight()

	var scope := ItemRegistry.get_item(&"sight_scope4x") as AttachmentData
	var suppressor := ItemRegistry.get_item(&"muzzle_choke_12") as AttachmentData

	stack.attachments[int(AttachmentData.Slot.SIGHT)] = scope.id
	_check(is_equal_approx(stack.get_total_weight(), bare + scope.weight_kg),
		"Zielfernrohr wiegt mit (%.2f -> %.2f kg)" % [bare, stack.get_total_weight()])

	stack.attachments[int(AttachmentData.Slot.MUZZLE)] = suppressor.id
	_check(is_equal_approx(stack.get_total_weight(), bare + scope.weight_kg + suppressor.weight_kg),
		"Wuergebohrung kommt oben drauf (%.2f kg)" % stack.get_total_weight())

	stack.attachments.clear()
	_check(is_equal_approx(stack.get_total_weight(), bare),
		"abgenommen wiegt die Waffe wieder wie vorher")

	# Jedes Teil muss ein Gewicht haben, sonst ist es stillschweigend gratis.
	for attachment in _attachments():
		_check(attachment.weight_kg > 0.0, "%s hat ein Gewicht (%.2f kg)"
			% [attachment.id, attachment.weight_kg])


## DER ZIELPUNKT MUSS IM GLAS LIEGEN.
##
## Er lag vorher im Ursprung des Visiers, und der ist nicht das Absehen: beim
## Rotpunkt 6,8 mm darunter, beim Holovisier 2,7 mm. Beim Zielen senkt
## weapon_view.gd die Waffe um sight_height ab — war der Wert zu klein, stand
## der Leuchtpunkt ueber der Bildmitte, waehrend die Kugel in die Mitte ging.
## Bei 0,16 m Zielabstand sind 6,8 mm rund 2,4 Grad, also gut ein Meter zu
## tief auf 25 m. Man zielt sauber und trifft nichts.
##
## Geprueft wird bewusst NICHT gegen feste Zahlen: Verschiebt der Modellierer
## das Absehen, waere der Test rot, obwohl alles stimmt. Geprueft wird die
## Eigenschaft, auf die es ankommt — der Punkt, durch den gezielt wird, muss
## innerhalb der Glasflaeche liegen. Sonst schaut man daran vorbei.
func _test_reticle_sits_in_the_glass() -> void:
	_section("Der Zielpunkt liegt im Glas")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData

	for optic_id in [&"ar15_sight_reddot", &"ar15_sight_holo"]:
		var build := WeaponBuild.new()
		build.set_attachment(AttachmentData.Slot.SIGHT, optic_id)
		var model := _build_model(ar15, build)

		var part := model.mounted.get(int(AttachmentData.Slot.SIGHT)) as AttachmentViewmodel
		if part == null or part.aim_point == null:
			_check(false, "%s: Optik montiert und hat einen Zielpunkt" % optic_id)
			model.free()
			continue

		var glass: Variant = _glass_extent(part, Transform3D.IDENTITY)
		if glass == null:
			_check(false, "%s: Glasflaeche gefunden" % optic_id)
			model.free()
			continue

		var box: AABB = glass
		var aim := part.aim_point.position
		_check(aim.y >= box.position.y - 0.001 and aim.y <= box.end.y + 0.001,
			"%s: Zielpunkt liegt auf Glashoehe (%.4f in %.4f..%.4f)"
				% [optic_id, aim.y, box.position.y, box.end.y])

		# Und die Visierhoehe der Waffe muss genau diesen Punkt uebernehmen.
		var expected := part.position.y + aim.y
		_check(is_equal_approx(model.sight_height, expected),
			"%s: sight_height folgt dem Zielpunkt (%.4f / %.4f)"
				% [optic_id, model.sight_height, expected])

		# Gegenprobe gegen den alten Fehler: Der Ursprung des Teils allein
		# waere zu tief gewesen.
		_check(not is_equal_approx(model.sight_height, part.position.y),
			"%s: der Ursprung des Visiers wird NICHT als Zielpunkt benutzt" % optic_id)

		model.free()


## Ausdehnung der Glasflaeche eines Anbauteils, in dessen eigenen Achsen.
##
## DIE TRANSFORMATIONEN MUESSEN MIT. Ohne sie kommen die rohen Eckpunkte aus
## der Datei heraus, und die stehen bei skalierten Knoten in einem voellig
## anderen Massstab: Beim Rotpunkt spannte das "Glas" dadurch von -0,44 bis
## 0,45 statt ueber zwei Zentimeter. Der Test war gruen, ohne irgendetwas zu
## pruefen — jeder Zielpunkt haette in diesem Bereich gelegen.
func _glass_extent(part: Node, transform: Transform3D) -> Variant:
	if part is MeshInstance3D:
		var mesh: Mesh = (part as MeshInstance3D).mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(i)
				if material == null or material.resource_name != "glass":
					continue
				var vertices: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				if vertices.is_empty():
					continue
				var low := Vector3.INF
				var high := -Vector3.INF
				for vertex in vertices:
					var point: Vector3 = transform * vertex
					low = low.min(point)
					high = high.max(point)
				return AABB(low, high - low)

	for child in part.get_children():
		if not (child is Node3D):
			continue
		var found: Variant = _glass_extent(child, transform * (child as Node3D).transform)
		if found != null:
			return found
	return null
