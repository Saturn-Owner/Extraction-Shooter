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
	await _test_movement()
	await _test_hinges()
	await _test_weapon_in_hand()
	await _test_vest()
	await _test_stances()
	await _test_marking()
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

	# --- DIE FIGUR MUSS IN IHRE LAUFRICHTUNG SCHAUEN ---
	#
	# Hier lag ein Fehler, den nur ein Mensch im Spiel bemerkt hat: Die
	# Drehung war von Hand gesetzt und das Vorzeichen verdreht, die Figur
	# lief also rückwärts. Sichtbar war das als "die Animation ist
	# spiegelverkehrt" — die Beine schwangen richtig, nur eben in die
	# falsche Richtung.
	#
	# Gemessen wird deshalb nicht der Winkel, sondern das, worauf es
	# ankommt: Zeigt die Blickachse dorthin, wo die Figur hinwandert?
	var walker := HumanoidTarget.new()
	walker.patrol_width = 6.0
	walker.patrol_speed = 2.0
	root.add_child(walker)
	walker.global_position = Vector3(0.0, 0.0, -10.0)
	await process_frame

	var backwards := 0
	var samples := 0
	var previous := walker.global_position
	for i in range(200):
		walker._process(1.0 / 60.0)
		var movement := walker.global_position - previous
		previous = walker.global_position
		if movement.length() < 0.005:
			continue  # Umkehrpunkt, dort gibt es keine Richtung.
		samples += 1
		# -Z ist vorn. Zeigt sie dorthin, wo sie hingeht?
		if (-walker.global_basis.z).dot(movement.normalized()) < 0.0:
			backwards += 1

	_check(samples > 50, "genug Messpunkte (%d)" % samples)
	_check(backwards == 0,
		"sie läuft nie rückwärts (%d von %d Bildern)" % [backwards, samples])

	walker.queue_free()


func _test_movement() -> void:
	_section("Bewegung")

	var character := _make()
	var animation := CharacterAnimation.new()
	character.add_child(animation)
	animation.attach(character)
	await process_frame

	var leg := character.joint_of(HealthSystem.Part.LEFT_LEG)
	var arm := character.joint_of(HealthSystem.Part.LEFT_ARM)
	_check(leg != null and arm != null, "die Gelenke sind da")
	if leg == null or arm == null:
		character.queue_free()
		return

	# --- Im Stand bewegt sich nichts sichtbar ---
	animation.speed = 0.0
	for i in range(40):
		animation._process(1.0 / 60.0)
	_check(absf(leg.rotation_degrees.x) < 0.01,
		"im Stand hängen die Beine gerade (%.4f Grad)" % leg.rotation_degrees.x)

	# --- Beim Gehen schwingen sie, UND ZWAR MERKLICH ---
	#
	# Beide Schranken, nicht nur eine. Beim Mündungsknall hat genau das
	# gefehlt: Der Effekt war vierzigmal zu schwach, und der Test war grün,
	# weil er nur nach oben geprüft hat — null besteht eine Obergrenze
	# mühelos.
	animation.speed = 4.0
	var widest_leg := 0.0
	var widest_arm := 0.0
	for i in range(240):
		animation._process(1.0 / 60.0)
		widest_leg = maxf(widest_leg, absf(leg.rotation_degrees.x))
		widest_arm = maxf(widest_arm, absf(arm.rotation_degrees.x))

	_check(widest_leg > CharacterAnimation.SWING_LEG * 0.5,
		"beim Gehen schwingen die Beine deutlich (%.1f von %.1f Grad)"
			% [widest_leg, CharacterAnimation.SWING_LEG])
	_check(widest_leg <= CharacterAnimation.SWING_LEG + 0.1,
		"aber nie über den eingestellten Wert (%.1f Grad)" % widest_leg)
	_check(widest_arm < widest_leg,
		"die Arme schwingen weniger weit als die Beine (%.1f gegen %.1f)"
			% [widest_arm, widest_leg])

	# --- Arm und Bein DERSELBEN Seite laufen gegeneinander ---
	# Andersherum sieht ein Gang sofort falsch aus, ohne dass man sagen
	# könnte warum. Ein Vorzeichenfehler in der Tabelle faellt sonst niemandem
	# auf, weil sich ja etwas bewegt.
	animation._phase = PI * 0.5
	animation._intensity = 1.0
	animation._process(0.0)
	_check(signf(leg.rotation_degrees.x) != signf(arm.rotation_degrees.x),
		"linker Arm und linkes Bein gegenläufig (%.1f gegen %.1f)"
			% [leg.rotation_degrees.x, arm.rotation_degrees.x])

	# --- DIE TREFFERZONE MUSS MITSCHWINGEN ---
	#
	# Der eigentliche Sinn der Übung: Ein vorgestrecktes Bein soll auch dort
	# treffbar sein, wo es aussieht. Bewegte sich nur das Mesh, zielte man
	# ins Leere und die Kugel ginge durch ein Bein, das gar nicht mehr da ist.
	var hitbox := character.hitbox_of(HealthSystem.Part.LEFT_LEG)
	var swung := hitbox.global_position
	animation.reset()
	animation._process(0.0)
	var resting := hitbox.global_position
	_check(swung.distance_to(resting) > 0.05,
		"die Trefferzone des Beins wandert mit (%.3f m)" % swung.distance_to(resting))

	# --- Und die Ruhelage kommt exakt zurück ---
	_check(leg.rotation_degrees.is_zero_approx() and arm.rotation_degrees.is_zero_approx(),
		"reset() stellt die Ruhelage her")

	# --- Eine Leiche atmet nicht ---
	var dead := _make()
	var dead_animation := CharacterAnimation.new()
	dead.add_child(dead_animation)
	dead_animation.attach(dead)
	await process_frame
	dead.health.apply_damage(HealthSystem.Part.HEAD, 999.0)
	dead_animation.speed = 4.0
	for i in range(120):
		dead_animation._process(1.0 / 60.0)
	var dead_leg := dead.joint_of(HealthSystem.Part.LEFT_LEG)
	_check(absf(dead_leg.rotation_degrees.x) < 0.01,
		"eine tote Figur geht nicht weiter (%.4f Grad)" % dead_leg.rotation_degrees.x)

	character.queue_free()
	dead.queue_free()


## Ellenbogen und Knie.
func _test_hinges() -> void:
	_section("Ellenbogen und Knie")

	var character := _make()
	var animation := CharacterAnimation.new()
	character.add_child(animation)
	animation.attach(character)
	await process_frame

	# Vier Zwischengelenke, und nur an Armen und Beinen.
	for part: HealthSystem.Part in [HealthSystem.Part.LEFT_ARM,
			HealthSystem.Part.RIGHT_ARM, HealthSystem.Part.LEFT_LEG,
			HealthSystem.Part.RIGHT_LEG]:
		_check(character.hinge_of(part) != null,
			"%s hat ein Zwischengelenk" % BlockyCharacter.part_name(part))
	for part: HealthSystem.Part in [HealthSystem.Part.HEAD,
			HealthSystem.Part.CHEST, HealthSystem.Part.STOMACH]:
		_check(character.hinge_of(part) == null,
			"%s hat keines — ein Rumpf knickt nicht" % BlockyCharacter.part_name(part))

	# ZWEI TREFFERZONEN JE GLIED, ABER DASSELBE KÖRPERTEIL.
	#
	# Das ist der Kern der Sache: Die Geometrie wird feiner, Lucas'
	# Datenmodell bleibt unberührt. Ein Treffer in den Unterarm ist ein
	# Armtreffer.
	var arm_boxes := character.hitboxes_of(HealthSystem.Part.LEFT_ARM)
	_check(arm_boxes.size() == 2, "der Arm hat zwei Trefferzonen (%d)" % arm_boxes.size())
	var wrong := 0
	for box in arm_boxes:
		if (box as CharacterHitbox).part != HealthSystem.Part.LEFT_ARM:
			wrong += 1
	_check(wrong == 0, "und beide melden LEFT_ARM (%d falsch)" % wrong)

	var chest_boxes := character.hitboxes_of(HealthSystem.Part.CHEST)
	_check(chest_boxes.size() == 1, "die Brust hat eine (%d)" % chest_boxes.size())

	# EIN KNIE KNICKT NUR IN EINE RICHTUNG.
	#
	# Ein sin() um null wäre die naheliegende Lösung und sähe bei jedem
	# zweiten Schritt aus wie ein gebrochenes Bein. Über einen vollen Zyklus
	# darf deshalb nie ein positiver Winkel herauskommen.
	var knee := character.hinge_of(HealthSystem.Part.LEFT_LEG)
	animation.speed = 4.0
	var worst_forward := -999.0
	var deepest := 0.0
	for i in range(400):
		animation._process(1.0 / 60.0)
		worst_forward = maxf(worst_forward, knee.rotation_degrees.x)
		deepest = minf(deepest, knee.rotation_degrees.x)

	_check(worst_forward <= 0.001,
		"das Knie knickt nie nach vorn (schlimmster Wert %.3f Grad)" % worst_forward)
	_check(deepest < -CharacterAnimation.BEND_KNEE * 0.4,
		"beugt sich beim Laufen aber deutlich (%.1f Grad)" % deepest)

	# Der Ellenbogen hält auch im Stand einen Winkel — sonst hängen die Arme
	# wie an einer Puppe.
	animation.reset()
	animation._process(0.0)
	var elbow := character.hinge_of(HealthSystem.Part.LEFT_ARM)
	_check(elbow.rotation_degrees.x > 1.0,
		"der Ellenbogen bleibt auch im Stand gebeugt (%.1f Grad)"
			% elbow.rotation_degrees.x)

	# Und beim Rennen mehr als beim Stehen.
	var standing := elbow.rotation_degrees.x
	animation.speed = 4.5
	for i in range(120):
		animation._process(1.0 / 60.0)
	_check(elbow.rotation_degrees.x > standing + 5.0,
		"beim Rennen winkelt er weiter an (%.1f gegen %.1f Grad)"
			% [elbow.rotation_degrees.x, standing])

	# DIE TREFFERZONE DES UNTERARMS MUSS DEM ELLENBOGEN FOLGEN.
	# Sonst zielt man auf einen angewinkelten Unterarm und trifft die Luft,
	# wo er im Stand gewesen wäre.
	var forearm := character.hitboxes_of(HealthSystem.Part.LEFT_ARM)[1] as CharacterHitbox
	var bent := forearm.global_position
	animation.reset()
	animation._process(0.0)
	_check(bent.distance_to(forearm.global_position) > 0.02,
		"die Trefferzone des Unterarms folgt dem Ellenbogen (%.3f m)"
			% bent.distance_to(forearm.global_position))

	character.queue_free()


## Stellt ein Einzelbild mitten im Nachladen her — in derselben Reihenfolge,
## in der es das Spiel tut: erst die Waffe, dann das Modell, dann der Arm.
func _advance_reload_frame(figure: HumanoidTarget, progress: float) -> void:
	var weapon := figure.weapon
	if progress < 0.0:
		weapon._reloading = false
	else:
		weapon._reloading = true
		weapon._reload_left = (1.0 - progress) * weapon.reload_seconds

	weapon._update_hold_pose()
	weapon.viewmodel.notify_reload(maxf(progress, 0.0), true)
	weapon.viewmodel.update_mechanics(1.0 / 60.0)

	figure._animation.reload_progress = weapon.reload_progress()
	figure._animation._process(1.0 / 60.0)


## Die Waffe in der Hand.
func _test_weapon_in_hand() -> void:
	_section("Waffe")

	var figure := HumanoidTarget.new()
	figure.label_text = "Träger"
	figure.weapon_id = &"weapon_rifle_ar15"
	figure.weapon_attachments = [&"ar15_muzzle_suppressor"] as Array[StringName]
	figure.weapon_behaviour = CharacterWeapon.Behaviour.HOLD
	root.add_child(figure)
	await process_frame

	_check(figure.weapon != null, "die Figur hat eine Waffe")
	if figure.weapon == null:
		figure.queue_free()
		return

	_check(figure.weapon.viewmodel != null, "und ein Modell dazu")
	_check(figure.weapon.viewmodel is AR15Viewmodel,
		"es ist die AR-15 aus Blender, nicht der Platzhalter")

	# DER SCHALLDÄMPFER MUSS WIRKEN, nicht nur montiert sein.
	_check(figure.weapon.data.loudness_multiplier < WeaponAudio.SUPPRESSED_BELOW,
		"der Schalldämpfer senkt die Lautstärke (%.2f)"
			% figure.weapon.data.loudness_multiplier)
	_check(WeaponAudio.volume_db_for(figure.weapon.data) < -6.0,
		"und sie wird hörbar leiser abgespielt (%.1f dB)"
			% WeaponAudio.volume_db_for(figure.weapon.data))

	# DIE MÜNDUNG MUSS NACH VORN ZEIGEN.
	#
	# Hier lag der Fehler des ersten Versuchs: Die Waffe hing an der Hand und
	# erbte damit die aufsummierte Drehung von Schulter und Ellenbogen — die
	# Mündung stand auf 2,02 m Höhe, also über dem Kopf, und zeigte in den
	# Himmel. Gemessen wird deshalb nicht, DASS eine Waffe da ist, sondern
	# wohin sie zeigt.
	var muzzle := figure.weapon.viewmodel.muzzle_point
	_check(muzzle != null, "es gibt einen Mündungspunkt")
	if muzzle != null:
		var local := figure.global_transform.affine_inverse() * muzzle.global_position
		_check(local.z < -0.5,
			"die Mündung sitzt vor dem Körper (%.2f m)" % local.z)
		_check(local.y > 1.0 and local.y < 1.6,
			"auf Brusthöhe, nicht über dem Kopf (%.2f m)" % local.y)

	# Die Arme gehören an die Waffe, nicht in den Gehzyklus.
	_check(figure._animation.holding_weapon, "die Arme sind im Anschlag")

	# DIE HÄNDE MÜSSEN AUF DEN GRIFFPUNKTEN LIEGEN.
	#
	# Das ist der eigentliche Beweis, dass die inverse Kinematik rechnet und
	# nicht nur plausibel aussieht: Die Waffe sagt, wo sie angefasst wird,
	# und danach muss die Hand dort sein — auf den Millimeter, nicht
	# ungefähr. Feste Winkel haben genau daran versagt.
	_check(figure.weapon.viewmodel.grip_point != null, "die Waffe nennt ihren Griff")
	_check(figure.weapon.viewmodel.support_point != null, "und ihren Vorderschaft")

	figure._animation._process(1.0 / 60.0)

	for entry in [
		{
			hand = HealthSystem.Part.RIGHT_ARM,
			point = figure.weapon.viewmodel.grip_point,
			label = "die rechte Hand liegt am Griff",
		},
		{
			hand = HealthSystem.Part.LEFT_ARM,
			point = figure.weapon.viewmodel.support_point,
			label = "die linke Hand liegt am Vorderschaft",
		},
	]:
		var hand := figure.hand_of(entry.hand)
		var gap := hand.global_position.distance_to(entry.point.global_position)
		_check(gap < 0.02, "%s (%.1f mm daneben)" % [entry.label, gap * 1000.0])

	# UND SIE MÜSSEN DORT BLEIBEN, WENN DIE FIGUR WOANDERS STEHT.
	#
	# Die Rechnung läuft im Raum der Figur. Stünde irgendwo eine
	# Weltkoordinate darin, ginge sie hier schief — und im Testgelände steht
	# keine Figur im Ursprung.
	figure.global_position = Vector3(7.0, 0.0, -33.0)
	figure.rotation_degrees = Vector3(0.0, 143.0, 0.0)
	figure._animation._process(1.0 / 60.0)
	var moved_hand := figure.hand_of(HealthSystem.Part.RIGHT_ARM)
	var moved_gap := moved_hand.global_position.distance_to(
		figure.weapon.viewmodel.grip_point.global_position)
	_check(moved_gap < 0.02,
		"auch versetzt und gedreht (%.1f mm daneben)" % (moved_gap * 1000.0))

	var arm := figure.joint_of(HealthSystem.Part.RIGHT_ARM)
	var before := arm.rotation_degrees
	figure._animation.speed = 4.0
	for i in range(120):
		figure._animation._process(1.0 / 60.0)
	_check(arm.rotation_degrees.distance_to(before) < 6.0,
		"und pendeln beim Laufen nicht frei mit (%.1f Grad Unterschied)"
			% arm.rotation_degrees.distance_to(before))

	# --- DIE HAND MUSS DIE GANZE NACHLADEBAHN ERREICHEN ---
	#
	# Der Arm ist 0,64 m lang. Liegt eine Wegmarke weiter weg, streckt er
	# sich und die Hand bleibt davor in der Luft stehen — sichtbar als
	# Greifen ins Leere. Genau daran ist der erste Entwurf gescheitert, der
	# dem fallenden Magazin folgen wollte: Das faellt 34 cm.
	#
	# Geprüft wird deshalb der ganze Ablauf in Schritten, nicht nur Anfang
	# und Ende.
	var support := figure.weapon.viewmodel.support_point
	_check(figure.weapon.viewmodel.magwell_point != null,
		"die Waffe nennt ihren Magazinschacht")

	# DEN ECHTEN ABLAUF NACHSTELLEN, NICHT NUR DEN FORTSCHRITT SETZEN.
	#
	# Beim Nachladen zieht die Figur die Waffe an sich heran — ohne das läge
	# der Schacht ausserhalb der Armlänge. Ein Test, der nur
	# `reload_progress` setzt, misst deshalb eine Lage, die es im Spiel nie
	# gibt, und meldet 109 mm Abweichung, wo in Wahrheit alles passt.
	var worst := 0.0
	var worst_at := 0.0
	for step in range(41):
		var progress := float(step) / 40.0
		_advance_reload_frame(figure, progress)

		var goal := figure._animation._support_hand_goal()
		var hand_now := figure.hand_of(HealthSystem.Part.LEFT_ARM)
		var gap := hand_now.global_position.distance_to(goal)
		if gap > worst:
			worst = gap
			worst_at = progress

	_check(worst < 0.03,
		"die linke Hand erreicht jede Stelle des Nachladens (%.0f mm bei %.2f)"
			% [worst * 1000.0, worst_at])

	# Und sie muss sich dabei WIRKLICH bewegen — eine Hand, die stur am
	# Schaft klebt, bestünde die Prüfung darüber mühelos.
	_advance_reload_frame(figure, -1.0)
	var resting_hand := figure.hand_of(HealthSystem.Part.LEFT_ARM).global_position

	_advance_reload_frame(figure, 0.38)
	var fetching_hand := figure.hand_of(HealthSystem.Part.LEFT_ARM).global_position

	_check(resting_hand.distance_to(fetching_hand) > 0.15,
		"und wandert dabei zur Magazintasche (%.2f m)"
			% resting_hand.distance_to(fetching_hand))

	# DIE SECHS SCHRITTE MÜSSEN WIRKLICH STATTFINDEN.
	#
	# Nicht alle haben eine eigene Stelle: Greifen und Einschieben passieren
	# beide am Schacht, das ist die Sache selbst und kein Fehler. Geprüft
	# wird deshalb, was die Schritte voneinander unterscheidet.
	var at := func(progress: float) -> Vector3:
		_advance_reload_frame(figure, progress)
		return figure.hand_of(HealthSystem.Part.LEFT_ARM).global_position

	var gripping: Vector3 = at.call(0.13)
	var pulled: Vector3 = at.call(0.30)
	# Am Umkehrpunkt messen, nicht auf dem Weg dorthin: Bei 0,38 ist die Hand
	# erst gut zur Haelfte an der Tasche.
	var at_pouch: Vector3 = at.call(0.44)
	var seating: Vector3 = at.call(0.80)
	var charging: Vector3 = at.call(0.94)

	# Herausziehen: die Hand wandert aus der Waffe heraus.
	var pull := gripping.distance_to(pulled)
	_check(pull > CharacterAnimation.PULL_DISTANCE * 0.8,
		"das Magazin wird herausgezogen (%.0f mm)" % (pull * 1000.0))

	# Zur Tasche: der weiteste Weg des ganzen Ablaufs.
	_check(at_pouch.distance_to(gripping) > 0.20,
		"die Hand holt ein neues aus der Tasche (%.2f m entfernt)"
			% at_pouch.distance_to(gripping))

	# Einschieben: zurück nach oben in den Schacht, nicht irgendwohin.
	_check(seating.distance_to(gripping) < pulled.distance_to(gripping),
		"das neue Magazin geht wieder hinein")

	# Ladehebel: hinten oben, deutlich woanders als der Schacht.
	_check(charging.distance_to(gripping) > 0.10,
		"der Ladehebel wird durchgezogen (%.2f m vom Schacht)"
			% charging.distance_to(gripping))
	_check(charging.y > gripping.y,
		"und er liegt höher als der Schacht (%.2f gegen %.2f)"
			% [charging.y, gripping.y])

	# Die rechte Hand bleibt derweil am Griff — die Waffe hält man fest.
	_advance_reload_frame(figure, 0.55)
	var right_hand := figure.hand_of(HealthSystem.Part.RIGHT_ARM)
	_check(right_hand.global_position.distance_to(
		figure.weapon.viewmodel.grip_point.global_position) < 0.02,
		"die rechte Hand bleibt beim Nachladen am Griff")

	_advance_reload_frame(figure, -1.0)
	_check(figure.hand_of(HealthSystem.Part.LEFT_ARM).global_position
		.distance_to(support.global_position) < 0.02,
		"danach liegt sie wieder am Vorderschaft")

	figure.queue_free()

	# --- Nachladen und Schiessen laufen ohne Fehler durch ---
	for entry in [
		{name = "nachladend", mode = CharacterWeapon.Behaviour.RELOAD},
		{name = "schiessend", mode = CharacterWeapon.Behaviour.SHOOT},
	]:
		var actor := HumanoidTarget.new()
		actor.weapon_id = &"weapon_rifle_ar15"
		actor.weapon_attachments = [&"ar15_muzzle_suppressor"] as Array[StringName]
		actor.weapon_behaviour = entry.mode
		root.add_child(actor)
		await process_frame

		# Ein voller Durchlauf: leerschiessen, nachladen, weiter.
		for i in range(400):
			actor.weapon._process(1.0 / 60.0)

		_check(actor.weapon.viewmodel != null,
			"%s: das Modell steht nach 400 Bildern noch" % entry.name)
		actor.queue_free()

	# Eine Figur OHNE Waffe darf sich davon nicht stören lassen.
	var bare := HumanoidTarget.new()
	root.add_child(bare)
	await process_frame
	_check(bare.weapon == null, "ohne weapon_id bleibt die Figur unbewaffnet")
	_check(not bare._animation.holding_weapon, "und ihre Arme schwingen frei")
	bare.queue_free()


## Die taktische Weste und das Magazin, das aus ihr gezogen wird.
func _test_vest() -> void:
	_section("Weste")

	var figure := HumanoidTarget.new()
	figure.wears_vest = true
	figure.weapon_id = &"weapon_rifle_ar15"
	figure.weapon_attachments = [&"ar15_muzzle_suppressor"] as Array[StringName]
	figure.weapon_behaviour = CharacterWeapon.Behaviour.RELOAD
	root.add_child(figure)
	await process_frame

	_check(figure.vest != null, "die Figur trägt eine Weste")
	if figure.vest == null:
		figure.queue_free()
		return

	_check(figure.vest.pouch_count() == CharacterVest.POUCH_COUNT,
		"alle %d Magazintaschen sind im Modell gefunden (%d)"
			% [CharacterVest.POUCH_COUNT, figure.vest.pouch_count()])

	# DIE VORDERSTE TASCHE MUSS LINKS SITZEN.
	#
	# Danach greift die linke Hand. Läge sie rechts, müsste der Arm quer über
	# den Körper — erreichbar wäre sie vielleicht noch, aussehen würde es
	# falsch.
	var front := figure.vest.front_pouch()
	var local := figure.global_transform.affine_inverse() * front.global_position
	_check(local.x < 0.0, "die vorderste Tasche sitzt links (%.3f)" % local.x)
	_check(local.z < 0.0, "und vorn am Körper (%.3f)" % local.z)

	# DER GRIFFPUNKT KOMMT AUS DEM MODELL, NICHT AUS DER KONSTANTEN.
	#
	# Das ist die Zusage, die das Ganze wartbar macht: Wer eine Tasche in
	# Blender verschiebt, verschiebt damit auch, wohin die Hand greift.
	_check(figure._animation.pouch_target == front,
		"die Animation greift an die Tasche aus dem Modell")
	_check(figure._animation.pouch_position().is_equal_approx(front.global_position),
		"und nicht mehr an den festen Punkt")

	# Und die Hand kommt hin.
	var worst := 0.0
	for step in range(41):
		_advance_reload_frame(figure, float(step) / 40.0)
		var goal := figure._animation._support_hand_goal()
		var hand := figure.hand_of(HealthSystem.Part.LEFT_ARM)
		worst = maxf(worst, hand.global_position.distance_to(goal))
	_check(worst < 0.03,
		"die Hand erreicht auch die Tasche der Weste (%.0f mm)" % (worst * 1000.0))

	# --- Das Ersatzmagazin wandert wirklich mit ---
	#
	# Vorher tauchte an der Waffe eines auf, ohne dass je eines getragen
	# wurde. Man sah die Geste, aber nicht den Gegenstand.
	_advance_reload_frame(figure, -1.0)
	figure._update_spare_magazine()
	_check(figure._spare_magazine != null, "es gibt ein Ersatzmagazin")
	if figure._spare_magazine == null:
		figure.queue_free()
		return

	_check(figure._spare_magazine.visible, "im Ruhezustand steckt es in der Tasche")
	_check(figure._spare_magazine.global_position.distance_to(front.global_position) < 0.01,
		"und zwar genau dort (%.0f mm)"
			% (figure._spare_magazine.global_position.distance_to(front.global_position) * 1000.0))

	# Beim Tragen haengt es an der Hand.
	_advance_reload_frame(figure, 0.55)
	figure._update_spare_magazine()
	var hand_now := figure.hand_of(HealthSystem.Part.LEFT_ARM)
	_check(figure._spare_magazine.visible, "beim Tragen ist es sichtbar")
	_check(figure._spare_magazine.global_position.distance_to(hand_now.global_position) < 0.01,
		"und liegt in der Hand")

	# Sobald es in der Waffe sitzt, zeigt die Waffe ihr eigenes — zwei
	# gleichzeitig waeren eines zu viel.
	_advance_reload_frame(figure, 0.92)
	figure._update_spare_magazine()
	_check(not figure._spare_magazine.visible,
		"sobald es in der Waffe sitzt, verschwindet das getragene")

	figure.queue_free()

	# Eine Figur OHNE Weste muss weiter nachladen koennen.
	var bare := HumanoidTarget.new()
	bare.weapon_id = &"weapon_rifle_ar15"
	bare.weapon_behaviour = CharacterWeapon.Behaviour.RELOAD
	root.add_child(bare)
	await process_frame
	_check(bare.vest == null, "ohne wears_vest bleibt sie ohne Weste")
	_check(bare._animation.pouch_target == null,
		"und greift an den festen Punkt am Bauch")
	bare._process(1.0 / 60.0)
	_check(true, "das Nachladen laeuft trotzdem ohne Fehler")
	bare.queue_free()


## Ducken, Zielen, Rennen.
##
## ---------------------------------------------------------------------------
## DER FUSS IST DIE EIGENTLICHE PRÜFUNG
##
## Der Kniewinkel beim Ducken wird aus der Beinlänge gerechnet, damit die Füsse
## stehen bleiben. Wer die Ducktiefe ändert und den Winkel vergisst, bekommt
## eine Figur, die im Boden versinkt oder in der Luft schwebt — und das fällt
## beim Spielen kaum auf, weil man auf den Oberkörper sieht.
##
## Geprüft wird deshalb nicht der Winkel, sondern das Ergebnis: Wo steht der
## Fuss? Ein Test auf den Winkel würde die Formel gegen sich selbst prüfen.
func _test_stances() -> void:
	_section("Haltungen")

	var figure := HumanoidTarget.new()
	figure.wears_vest = true
	figure.weapon_id = &"weapon_rifle_ar15"
	root.add_child(figure)
	await process_frame

	var head := figure.joint_of(HealthSystem.Part.HEAD)
	var standing_head := head.global_position.y
	var standing_foot := _foot_height(figure)
	_check(absf(standing_foot) < 0.001,
		"stehend steht der Fuss auf dem Boden (%.4f m)" % standing_foot)

	# --- Ducken ---
	figure.crouching = true
	for i in range(200):
		await process_frame

	var crouched_head := head.global_position.y
	var crouched_foot := _foot_height(figure)
	# Die Figur duckt sich GENAU SO TIEF WIE DER SPIELER.
	#
	# Nicht „ungefähr" und nicht nach Augenmass: Sobald der Spieler einen
	# sichtbaren Körper bekommt, ist jeder Unterschied eine Lüge — der Körper
	# sähe anders geduckt aus, als seine Kollisionskapsel es ist. Hier standen
	# vorher von Hand gewählte 0,22 m, und die passten zu nichts.
	_check(absf(crouched_head - PlayerController.CROUCH_HEIGHT) < 0.02,
		"geduckt ist die Figur so hoch wie die Spielerkapsel (%.2f gegen %.2f m)"
			% [crouched_head, PlayerController.CROUCH_HEIGHT])
	_check(absf(standing_head - PlayerController.STAND_HEIGHT) < 0.02,
		"stehend ebenso (%.2f gegen %.2f m)"
			% [standing_head, PlayerController.STAND_HEIGHT])
	_check(absf(crouched_foot) < 0.005,
		"und der Fuss bleibt trotzdem am Boden (%.4f m)" % crouched_foot)

	# Ein Knie, das nach hinten knickt, ergibt ein Vogelbein. Beim Rendern war
	# genau das der Verdacht — die Messung hat ihn widerlegt, und diese Prüfung
	# hält das fest.
	var hip := figure.joint_of(HealthSystem.Part.LEFT_LEG)
	var knee := figure.hinge_of(HealthSystem.Part.LEFT_LEG)
	_check(knee.global_position.z < hip.global_position.z - 0.05,
		"das Knie zeigt nach vorn, nicht nach hinten (%.3f)"
			% knee.global_position.z)

	# --- Wieder aufstehen ---
	figure.crouching = false
	for i in range(240):
		await process_frame

	_check(absf(figure.joint_of(HealthSystem.Part.LEFT_LEG).position.y
			- figure._animation._rest[HealthSystem.Part.LEFT_LEG].y) < 0.001,
		"nach dem Aufstehen sitzt die Hüfte wieder in der Ruhelage")
	_check(absf(_foot_height(figure)) < 0.001,
		"und der Fuss steht wieder genau auf null")

	# --- Die Waffe sitzt in JEDER Haltung gleich ---
	#
	# Hier stand vorher das Gegenteil: dass Zielen die Waffe hebt und Rennen
	# sie senkt. Beide Werte hatte ich erfunden, und beim Ausprobieren fiel
	# auf, dass die betroffenen Figuren die Waffe anders hielten als die
	# übrigen. Jetzt ist es umgekehrt festgeschrieben — wer die Waffe je
	# wieder haltungsabhängig bewegen will, soll erst hier vorbeikommen.
	var resting := figure.weapon.position
	for probe_stance in [[true, false], [false, true], [true, true]]:
		figure.aiming = probe_stance[0]
		figure.sprinting = probe_stance[1]
		for i in range(120):
			await process_frame
		_check(figure.weapon.position.is_equal_approx(resting)
				and figure.weapon.rotation_degrees.is_zero_approx(),
			"zielend=%s rennend=%s sitzt die Waffe unverändert"
				% [probe_stance[0], probe_stance[1]])
	figure.aiming = false
	figure.sprinting = true

	# --- Beim Rennen nach VORN, nicht nach hinten ---
	#
	# Das Vorzeichen ist nicht dasselbe wie beim Bein: Ein Bein hängt vom
	# Gelenk nach unten, der Rumpf ragt nach oben. Mit dem Vorzeichen des
	# Beins lehnte sich die Figur beim Rennen zurück, und im Rendering sah
	# das aus wie eine Haltung, nur eben die falsche.
	figure.aiming = false
	for i in range(60):
		await process_frame
	var chest := figure.joint_of(HealthSystem.Part.CHEST)
	var leaning := chest.global_position.z
	figure.sprinting = false
	for i in range(180):
		await process_frame
	_check(leaning < chest.global_position.z - 0.05,
		"rennend neigt sich der Oberkörper nach vorn (%.2f m)"
			% (chest.global_position.z - leaning))

	figure.queue_free()
	await process_frame

	# --- Die Hände bleiben in JEDER Haltung an der Waffe ---
	#
	# ---------------------------------------------------------------------
	# DIESE PRÜFUNG FEHLTE, UND DAS HAT WEHGETAN
	#
	# Nach dem Einbau des Rumpfknotens rechnete die Armlösung die Schulter im
	# Raum des Rumpfes, das Ziel aber im Raum der Figur. Aufrecht fiel das
	# nicht auf, weil beide Räume dann zusammenfallen — geduckt und rennend
	# griffen die Hände 22 cm neben die Waffe.
	#
	# Alle 123 Prüfungen blieben dabei grün. Gefunden hat es ein Mensch, der
	# hingesehen hat. Genau deshalb steht die Prüfung jetzt hier.
	for setup in [
			{n = "stehend", a = false, c = false, s = false, v = 0.0},
			{n = "zielend", a = true, c = false, s = false, v = 0.0},
			{n = "geduckt", a = true, c = true, s = false, v = 0.0},
			{n = "rennend", a = false, c = false, s = true, v = 5.2},
		]:
		var probe := HumanoidTarget.new()
		probe.weapon_id = &"weapon_rifle_ar15"
		probe.wears_vest = true
		root.add_child(probe)
		await process_frame
		probe.aiming = setup.a
		probe.crouching = setup.c
		probe.sprinting = setup.s
		probe._animation.speed = setup.v
		for i in range(150):
			await process_frame

		var right := probe.hand_of(HealthSystem.Part.RIGHT_ARM)
		var left := probe.hand_of(HealthSystem.Part.LEFT_ARM)
		var to_grip := right.global_position.distance_to(
			probe._animation.grip_target.global_position)
		var to_fore := left.global_position.distance_to(
			probe._animation.support_target.global_position)
		# 5 cm Spielraum: Bei gesenkter Waffe im Sprint kommt der Stützarm
		# knapp an seine Reichweite, gemessene 24 mm. Alles darüber heisst,
		# dass die Hand die Waffe verloren hat.
		_check(to_grip < 0.05 and to_fore < 0.05,
			"%s hält die Waffe mit beiden Händen (%.0f / %.0f mm)"
				% [setup.n, to_grip * 1000.0, to_fore * 1000.0])
		probe.queue_free()
		await process_frame


## Tiefster Punkt des linken Beins, entlang der Richtung des Unterschenkels.
##
## NICHT über `global_position.y - halbe Höhe`: Das gilt nur für einen
## ungedrehten Kasten. Bei 45 Grad Beugung lag diese Rechnung um 8 cm daneben
## und liess eine korrekte Haltung falsch aussehen.
func _foot_height(figure: HumanoidTarget) -> float:
	var size := figure.size_of(HealthSystem.Part.LEFT_LEG)
	var at: float = BlockyCharacter.HINGES[HealthSystem.Part.LEFT_LEG].at
	var lower := size.y - size.y * at
	var knee := figure.hinge_of(HealthSystem.Part.LEFT_LEG)
	return (knee.global_transform * Vector3(0.0, -lower, 0.0)).y


## Die Kennzeichnung — eine Nummer, damit man ueber eine bestimmte Figur
## reden kann.
##
## ---------------------------------------------------------------------------
## DIE HUD-ZEILE MUSS EINZEILIG BLEIBEN
##
## Die Schrift ueber dem Kopf ist zweizeilig, die HUD-Ausgabe einzeilig — das
## ist Absicht und in `label_lines()` begruendet. Die Nummer einfach vorne an
## `label_text` zu haengen waere der kurze Weg gewesen und haette die HUD-Zeile
## mitten im Namen zerrissen. Deshalb ein eigenes Feld, und deshalb diese
## Pruefung.
func _test_marking() -> void:
	_section("Kennzeichnung")

	var figure := HumanoidTarget.new()
	figure.marking = "#7"
	figure.label_text = "15 m  zielt"
	root.add_child(figure)
	await process_frame

	_check(figure.label_lines().begins_with("#7\n"),
		"ueber dem Kopf steht die Nummer in einer eigenen Zeile")
	_check(figure.describe().begins_with("#7 15 m"),
		"im HUD steht sie davor, ohne Umbruch")
	_check(not ("\n" in figure.describe()),
		"und die HUD-Zeile bleibt einzeilig")

	# Auch beschaedigt darf die HUD-Zeile nicht umbrechen.
	figure.health.apply_damage(HealthSystem.Part.CHEST, 30.0)
	_check(not ("\n" in figure.describe()),
		"auch nach einem Treffer")

	# Ohne Kennzeichnung muss alles bleiben wie vorher — sonst haetten die
	# Figuren im Raid ploetzlich eine leere Zeile ueber dem Kopf.
	var plain := HumanoidTarget.new()
	plain.label_text = "ohne Nummer"
	root.add_child(plain)
	await process_frame
	_check(plain.label_lines() == "ohne Nummer",
		"ohne Kennzeichnung bleibt die Beschriftung unveraendert")
	_check(plain.describe().begins_with("ohne Nummer:"),
		"und die HUD-Zeile ebenso")

	figure.queue_free()
	plain.queue_free()
	await process_frame


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
		# %v gilt nur fuer Vektoren, eine Color faellt durch — die Meldung blieb
		# dadurch unlesbar, obwohl die Pruefung selbst stimmte.
		"halb verletzt liegt dazwischen (%.2f/%.2f/%.2f)" % [half.r, half.g, half.b])
