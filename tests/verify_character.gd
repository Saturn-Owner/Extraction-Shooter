## Prüft die Figur: Masse, Trefferzonen und der Weg vom Schuss zum Körperteil.
##
##   godot --headless --path . --script res://tests/verify_character.gd
##
## Der wichtigste Test hier ist _test_a_real_ray_finds_the_body(). Alles andere
## liesse sich auch prüfen, indem man `take_hit_on_part()` direkt aufruft — und
## genau das wäre wertlos: Der Fehler, um den es geht, liegt NICHT in der
## Schadensrechnung, sondern darin, ob ein Geschoss den Kasten überhaupt
## findet. `Projectile` fragt mit `collide_with_areas = false` ab; eine Area3D
## wäre unsichtbar, und ein Test, der die Physik überspringt, wäre trotzdem
## grün. Deshalb wird hier ein echter Strahl geschossen.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Figur prüfen ===\n")

	_test_measurements()
	_test_parts_do_not_overlap()
	await _test_a_real_ray_finds_the_body()
	await _test_damage_reaches_the_right_part()
	await _test_the_plate_covers_only_the_chest()
	await _test_the_target_can_be_reset()
	_test_colours()

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


func _make() -> BlockyCharacter:
	var character := BlockyCharacter.new()
	root.add_child(character)
	return character


func _ammo(id: StringName) -> AmmoData:
	return ItemRegistry.get_item(id) as AmmoData


func _test_measurements() -> void:
	_section("Masse")

	var character := _make()

	var head := character.centre_of(HealthSystem.Part.HEAD)
	var head_size := character.size_of(HealthSystem.Part.HEAD)
	var top := head.y + head_size.y * 0.5
	_check(is_equal_approx(top, BlockyCharacter.HEIGHT),
		"der Scheitel liegt bei %.2f m" % top)

	var leg := character.centre_of(HealthSystem.Part.LEFT_LEG)
	var leg_size := character.size_of(HealthSystem.Part.LEFT_LEG)
	var sole := leg.y - leg_size.y * 0.5
	_check(is_zero_approx(sole), "die Sohlen stehen auf dem Boden (%.3f m)" % sole)

	# Die Schulterbreite soll zur vorhandenen Kollisionskapsel passen
	# (radius 0.35, also 0.70 Durchmesser) — sonst ragen Arme hindurch.
	var arm := character.centre_of(HealthSystem.Part.LEFT_ARM)
	var arm_size := character.size_of(HealthSystem.Part.LEFT_ARM)
	var width := (absf(arm.x) + arm_size.x * 0.5) * 2.0
	_check(absf(width - 0.70) < 0.02, "die Figur ist %.2f m breit" % width)

	# Links ist die linke Hand der FIGUR. Sie schaut nach -Z, ihre Linke
	# liegt damit bei -X. Wer das spiegelt, zielt bei Gegnern verkehrt.
	_check(character.centre_of(HealthSystem.Part.LEFT_ARM).x < 0.0,
		"der linke Arm liegt bei -X")
	_check(character.centre_of(HealthSystem.Part.RIGHT_ARM).x > 0.0,
		"der rechte bei +X")

	# Alle sieben, nicht sechs.
	_check(BlockyCharacter.VERTICAL.size() == 7,
		"es sind sieben Körperteile (%d)" % BlockyCharacter.VERTICAL.size())
	_check(BlockyCharacter.HORIZONTAL.size() == 7,
		"und für jedes gibt es Breite und Tiefe (%d)" % BlockyCharacter.HORIZONTAL.size())

	character.queue_free()


## Die Kästen dürfen sich nicht durchdringen.
##
## Nicht Schönheit, sondern Treffsicherheit: Überlappen Brust und Bauch, hängt
## es an der Reihenfolge in der Physik, welches Teil ein Schuss erwischt — und
## das ist dann nicht reproduzierbar.
func _test_parts_do_not_overlap() -> void:
	_section("Keine Überschneidungen")

	var character := _make()

	var boxes: Dictionary = {}
	for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
		var centre := character.centre_of(part)
		var size := character.size_of(part)
		boxes[part] = AABB(centre - size * 0.5, size)

	var overlaps := 0
	var parts: Array = BlockyCharacter.VERTICAL.keys()
	for i in range(parts.size()):
		for j in range(i + 1, parts.size()):
			var a: AABB = boxes[parts[i]]
			var b: AABB = boxes[parts[j]]
			# Etwas schrumpfen, damit blosses Aneinanderstossen nicht zählt.
			if a.grow(-0.001).intersects(b.grow(-0.001)):
				overlaps += 1
				print("         %s schneidet %s" % [
					BlockyCharacter.part_name(parts[i]),
					BlockyCharacter.part_name(parts[j])])

	_check(overlaps == 0, "kein Kasten schneidet einen anderen (%d)" % overlaps)

	character.queue_free()


## DER KERNTEST: ein echter Strahl, wie ihn das Geschoss schiesst.
func _test_a_real_ray_finds_the_body() -> void:
	_section("Ein echter Strahl trifft")

	var character := _make()

	# NICHT IM URSPRUNG UND NICHT UNGEDREHT PRÜFEN.
	#
	# Genau daran ist dieser Test einmal vorbeigelaufen: Er stellte die Figur
	# auf (0,0,0) ohne Drehung — dort sind lokale und globale Koordinaten
	# identisch, und ein Fehler, bei dem die Trefferzonen im Weltursprung
	# kleben bleiben, ist schlicht nicht zu sehen. Im Spiel stand die Figur
	# bei (3, 0, -25), ihre Trefferzonen bei (0, 1.3, 0), und kein Schuss kam
	# je an. Der Test war trotzdem grün.
	character.global_position = Vector3(3.0, 0.0, -25.0)
	character.rotation_degrees = Vector3(0.0, 180.0, 0.0)

	# Zwei Bilder, damit die Physik die neuen Körper kennt.
	await process_frame
	await physics_frame

	var space := root.world_3d.direct_space_state

	# Von vorn auf jedes Körperteil einzeln. Die Figur ist gedreht, der
	# Mittelpunkt muss deshalb über ihre Transformation umgerechnet werden.
	for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
		var centre := character.global_transform * character.centre_of(part)
		var from := centre + Vector3(0.0, 0.0, 3.0)
		var query := PhysicsRayQueryParameters3D.create(from, centre)
		# GENAU WIE IM GESCHOSS. Wird hier `true` gesetzt, besteht der Test
		# auch mit Area3D-Trefferzonen — und im Spiel ginge jeder Schuss durch.
		query.collide_with_areas = false
		query.collision_mask = character.hit_layer

		var hit := space.intersect_ray(query)
		var collider = hit.get("collider")
		var found: bool = collider is CharacterHitbox \
			and (collider as CharacterHitbox).part == part
		_check(found, "%s wird von vorn getroffen" % BlockyCharacter.part_name(part))

	# Und der Weg, den das Geschoss wirklich geht: hat der Getroffene
	# take_hit()? Ohne das fällt der Treffer in Projectile durch.
	var chest := character.hitbox_of(HealthSystem.Part.CHEST)
	_check(chest != null and chest.has_method("take_hit"),
		"die Trefferzone hat take_hit() — sonst ignoriert Projectile sie")
	_check(chest is AnimatableBody3D,
		"und sie ist ein Körper, keine Area3D")

	# DIE TREFFERZONE MUSS MIT DER FIGUR WANDERN. Das ist der Fehler von oben,
	# noch einmal direkt gemessen statt über einen Strahl: AnimatableBody3D
	# übernimmt mit sync_to_physics die Hoheit über seine Welttransformation
	# und bleibt dann im Ursprung liegen.
	_check(not chest.sync_to_physics,
		"sync_to_physics ist aus — sonst folgt sie der Figur nicht")
	_check(chest.global_position.distance_to(character.global_position) < 2.0,
		"und sie steht bei der Figur (%v gegen %v)"
			% [chest.global_position, character.global_position])

	character.queue_free()


func _test_damage_reaches_the_right_part() -> void:
	_section("Schaden landet am richtigen Teil")

	var character := _make()
	await process_frame

	var ammo := _ammo(&"ammo_556x45_m855a1")
	_check(ammo != null, "Munition geladen")
	if ammo == null:
		character.queue_free()
		return

	var before := character.health.get_hp(HealthSystem.Part.LEFT_LEG)
	character.take_hit_on_part(HealthSystem.Part.LEFT_LEG, ammo, 50.0,
		Vector3.ZERO, Vector3.FORWARD)
	var after := character.health.get_hp(HealthSystem.Part.LEFT_LEG)

	_check(after < before, "ein Beintreffer kostet Trefferpunkte (%.0f auf %.0f)"
		% [before, after])
	_check(is_equal_approx(character.health.get_hp(HealthSystem.Part.HEAD),
		HealthSystem.MAX_HP[HealthSystem.Part.HEAD]),
		"und der Kopf bleibt unversehrt")

	# EIN ZERSCHOSSENES BEIN TÖTET NICHT. Das ist die Zusage des ganzen
	# Systems: Arme, Beine und Bauch fallen aus, ohne zu töten.
	#
	# Drei Treffer und nicht zwanzig: Ein 5,56er macht rund 43 Schaden, das
	# Bein hat 65. Nach zwei Treffern ist es ab, der dritte geht gedämpft auf
	# die Brust. Zwanzig wären 860 Schaden — daran stirbt man selbstredend,
	# und der Test hätte etwas geprüft, was das System nie versprochen hat.
	var alive := _make()
	await process_frame
	for i in range(3):
		alive.take_hit_on_part(HealthSystem.Part.LEFT_LEG, ammo, 10.0,
			Vector3.ZERO, Vector3.FORWARD)

	_check(alive.health.is_destroyed(HealthSystem.Part.LEFT_LEG),
		"das Bein ist ab (%.0f)" % alive.health.get_hp(HealthSystem.Part.LEFT_LEG))
	_check(not alive.health.is_dead,
		"aber es tötet nicht (Brust %.0f von %.0f)"
			% [alive.health.get_hp(HealthSystem.Part.CHEST),
				HealthSystem.MAX_HP[HealthSystem.Part.CHEST]])

	# Weitere Treffer auf das tote Bein gehen aber auf die Brust über, sonst
	# wäre ein ausgefallenes Glied ein Freibrief.
	_check(alive.health.get_hp(HealthSystem.Part.CHEST)
		< HealthSystem.MAX_HP[HealthSystem.Part.CHEST],
		"der Überschuss geht auf die Brust")

	# Kopfschüsse dagegen töten sofort.
	#
	# Der Merker ist ein Array und kein bool: GDScript-Lambdas fangen lokale
	# Variablen ALS WERT ein. `func(): fertig = true` setzt eine Kopie, und
	# draussen bleibt es false — der Test war dadurch rot, obwohl das Signal
	# einwandfrei kam. Ein Array wird als Verweis gefangen.
	var doomed := _make()
	await process_frame
	var died := [false]
	doomed.died.connect(func(): died[0] = true)
	doomed.take_hit_on_part(HealthSystem.Part.HEAD, ammo, 10.0,
		Vector3.ZERO, Vector3.FORWARD)
	_check(doomed.health.is_dead, "ein Kopftreffer tötet")
	_check(died[0], "und die Figur meldet es über ihr eigenes Signal")

	character.queue_free()
	alive.queue_free()
	doomed.queue_free()


func _test_the_plate_covers_only_the_chest() -> void:
	_section("Die Platte deckt nur, was sie deckt")

	var plate := ItemRegistry.get_item(&"plate_class4_front") as ArmorPlateData
	if plate == null:
		# Die Platten sind mit den 28 Gegenständen geloescht worden. Kein
		# Fehler — der Test überspringt sich dann selbst, statt rot zu sein.
		print("  (übersprungen: es gibt derzeit keine Platten)")
		return

	var character := _make()
	character.plate = plate
	character.plate_durability = plate.max_durability
	await process_frame

	var ammo := _ammo(&"ammo_556x45_m855a1")
	var chest := character.take_hit_on_part(HealthSystem.Part.CHEST, ammo, 50.0,
		Vector3.ZERO, Vector3.FORWARD)
	_check(chest.was_armored, "die Brust ist geschützt")

	var head := character.take_hit_on_part(HealthSystem.Part.HEAD, ammo, 50.0,
		Vector3.ZERO, Vector3.FORWARD)
	_check(not head.was_armored,
		"der Kopf nicht — eine Brustplatte deckt keinen Kopf ab")

	character.queue_free()


## Die Zielfigur muss sich zurücksetzen lassen — sonst ist sie einmal
## benutzbar und man muss das Level neu starten, um weiterzuprobieren.
func _test_the_target_can_be_reset() -> void:
	_section("Zielfigur")

	var figure := HumanoidTarget.new()
	figure.label_text = "Prüfung"
	root.add_child(figure)
	await process_frame

	var ammo := _ammo(&"ammo_556x45_m855a1")
	for i in range(6):
		figure.take_hit_on_part(HealthSystem.Part.HEAD, ammo, 10.0,
			Vector3.ZERO, Vector3.FORWARD)

	_check(figure.health.is_dead, "sechs Kopftreffer töten sie")
	_check(figure.describe().contains("TOT"),
		"und die HUD-Zeile sagt es: %s" % figure.describe())

	# DIE SCHRIFT ÜBER DEM KOPF MUSS KURZ BLEIBEN. Stand dort die lange
	# Fassung, war sie viermal so breit wie die Schilder der flachen
	# Scheiben — auf 25 m überlappten sich alle drei zu einem grauen Brei.
	_check(figure.label_lines().length() < figure.describe().length(),
		"das Schild ist kürzer als die HUD-Zeile (%d gegen %d Zeichen)"
			% [figure.label_lines().length(), figure.describe().length()])
	for line in figure.label_lines().split("\n"):
		_check(String(line).length() <= 16,
			"jede Zeile bleibt schmal: '%s'" % line)

	figure.reset()
	_check(not figure.health.is_dead, "reset() bringt sie zurück")
	_check(is_equal_approx(figure.health.get_hp(HealthSystem.Part.HEAD),
		HealthSystem.MAX_HP[HealthSystem.Part.HEAD]),
		"mit vollen Trefferpunkten (%.0f)" % figure.health.get_hp(HealthSystem.Part.HEAD))
	_check(not figure.describe().contains("TOT"),
		"und die HUD-Zeile auch: %s" % figure.describe())
	_check(figure.label_lines() == figure.label_text,
		"unbeschädigt steht nur der Name auf dem Schild: '%s'" % figure.label_lines())

	# Die Trefferzähler müssen mit zurück, sonst zählt die Beschriftung
	# über mehrere Durchgänge weiter und die Zahl ist wertlos.
	_check(figure.describe().contains("0 Treffer"),
		"der Trefferzähler steht wieder auf null")

	# Dieselbe Schnittstelle wie die flache Scheibe, damit das Testgelände
	# beide über denselben Aufruf zurücksetzen kann.
	_check(figure.has_method("reset"), "sie hat reset() wie TargetDummy")

	figure.queue_free()


func _test_colours() -> void:
	_section("Farben")

	_check(BlockyCharacter.color_for(1.0).is_equal_approx(BlockyCharacter.COLOR_HEALTHY),
		"unversehrt ist grün")
	_check(BlockyCharacter.color_for(0.0).is_equal_approx(BlockyCharacter.COLOR_DESTROYED),
		"ausgefallen ist fast schwarz")

	# Dazwischen muss es sich WIRKLICH ändern. Eine Prüfung auf die Endpunkte
	# allein bestünde auch eine Funktion, die dazwischen konstant bleibt.
	var half := BlockyCharacter.color_for(0.5)
	_check(not half.is_equal_approx(BlockyCharacter.COLOR_HEALTHY)
		and not half.is_equal_approx(BlockyCharacter.COLOR_DESTROYED),
		"halb verletzt liegt dazwischen (%v)" % half)
