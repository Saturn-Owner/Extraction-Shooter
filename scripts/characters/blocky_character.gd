## Die Figur: sieben Kästen, die zugleich das Modell und die Trefferzonen sind.
##
## ---------------------------------------------------------------------------
## EIN KASTEN JE KÖRPERTEIL, UND DAS IST DER GANZE PUNKT
##
## `HealthSystem` führt sieben Körperteile, `CharacterWindow` zeichnet sieben
## Rechtecke — und bis jetzt gab es keinen Weg, eines davon zu treffen. Der
## Spieler hatte eine einzige Kapsel, und `Projectile._apply_damage()` sucht
## nach `take_hit()`, das nur die Zielscheibe hat. Ein Bein liess sich schlicht
## nicht zerschiessen; Trefferpunkte sanken ausschliesslich durch Hunger,
## Durst und Kälte.
##
## Deshalb sind Modell und Trefferzone hier **dasselbe Ding**. Wer einen Kasten
## verschiebt, verschiebt die Trefferzone mit. Zwei getrennte Beschreibungen
## würden über kurz oder lang auseinanderlaufen, und das merkt man erst, wenn
## Schüsse an sichtbaren Beinen vorbeigehen.
##
## ---------------------------------------------------------------------------
## DIE PROPORTIONEN KOMMEN AUS DEM CHARAKTERFENSTER — ABER NUR SENKRECHT
##
## Die Höhen sind exakt die aus `CharacterWindow.BODY_RECTS`: Kopf 13 %, Brust
## 22 %, Bauch 16 %, Beine 40 %. Damit sieht die Figur im Spiel aus wie die im
## Fenster, und wer eines von beiden ändert, sieht es sofort am anderen.
##
## Die BREITEN kommen NICHT von dort. Im Fenster stehen die Arme mit Abstand
## neben dem Rumpf, damit die Trefferpunktzahlen hineinpassen — die Figur ist
## dort 1,46 m breit. Als Körper wäre das eine Vogelscheuche. Waagerecht sind
## die Masse deshalb frei gewählt und ergeben 0,70 m Schulterbreite, was genau
## dem Durchmesser der vorhandenen Kollisionskapsel entspricht.
##
## ---------------------------------------------------------------------------
## KEIN SKELETT
##
## Bewegt wird später über die Knoten selbst, wie bei den Waffen: `Weapon`
## dreht `Action` und `ChargingHandle`, hier drehen sich Arme und Beine. Für
## eckige Gliedmassen ist starre Drehung kein Notbehelf, sondern der Stil —
## ein Skelett mit weicher Verformung würde die Kanten weich ziehen und genau
## das kaputtmachen, was an der Figur gefällt.
class_name BlockyCharacter
extends Node3D

signal part_hit(part: HealthSystem.Part, result: Ballistics.HitResult)
signal died()

## Gesamthöhe in Metern. Die Kollisionskapsel des Spielers ist 1,8 m hoch.
const HEIGHT := 1.8

## Der senkrechte Ausschnitt aus CharacterWindow.BODY_RECTS: Der Kopf beginnt
## dort bei 0,02, die Füsse enden bei 0,98.
const TOP_FRACTION := 0.02
const BOTTOM_FRACTION := 0.98

## Umrechnung von Fensteranteil in Meter.
const SCALE := HEIGHT / (BOTTOM_FRACTION - TOP_FRACTION)

## Höhe je Körperteil, als Anteil wie im Fenster: [Oberkante, Höhe].
##
## Die Werte stehen absichtlich doppelt und nicht als Verweis auf
## CharacterWindow: Das Fenster ist eine Anzeige, die Figur ein Körper. Sie
## sollen sich gleichen, aber die Anzeige darf sich ändern, ohne dass sich die
## Trefferzonen mitbewegen — sonst verschiebt eine Layoutkorrektur im Fenster
## unbemerkt, wo im Spiel der Kopf sitzt.
const VERTICAL := {
	HealthSystem.Part.HEAD: [0.02, 0.13],
	HealthSystem.Part.CHEST: [0.17, 0.22],
	HealthSystem.Part.STOMACH: [0.40, 0.16],
	HealthSystem.Part.LEFT_ARM: [0.17, 0.34],
	HealthSystem.Part.RIGHT_ARM: [0.17, 0.34],
	HealthSystem.Part.LEFT_LEG: [0.58, 0.40],
	HealthSystem.Part.RIGHT_LEG: [0.58, 0.40],
}

## Breite, Tiefe und seitlicher Versatz in Metern. Frei gewählt, siehe oben.
##
## LINKS IST DIE LINKE HAND DER FIGUR, nicht die linke Bildschirmseite. Die
## Figur schaut nach -Z (dieselbe Richtung wie die Waffen), ihre linke Seite
## liegt damit bei -X. Im Fenster steht LEFT_ARM am linken Rand, was aus Sicht
## eines Betrachters von vorn der RECHTE Arm wäre — dort ist es nach der
## Bildschirmseite benannt. Für einen Körper ist die anatomische Zuordnung die
## richtige, sonst zielt man später bei Gegnern spiegelverkehrt.
const HORIZONTAL := {
	HealthSystem.Part.HEAD: {width = 0.20, depth = 0.22, offset = 0.0},
	HealthSystem.Part.CHEST: {width = 0.40, depth = 0.24, offset = 0.0},
	HealthSystem.Part.STOMACH: {width = 0.36, depth = 0.22, offset = 0.0},
	# Zwischen Arm und Rumpf bleibt ein Spalt von 1,5 cm. Stiessen sie
	# bündig aneinander, verschmelzen sie im Bild zu einer Masse — im ersten
	# Rendering war der Arm nur als Schattenkante zu erkennen. Das Fenster
	# macht es genauso, dort steht zwischen Arm und Brust ebenfalls Luft.
	HealthSystem.Part.LEFT_ARM: {width = 0.13, depth = 0.15, offset = -0.28},
	HealthSystem.Part.RIGHT_ARM: {width = 0.13, depth = 0.15, offset = 0.28},
	HealthSystem.Part.LEFT_LEG: {width = 0.17, depth = 0.20, offset = -0.095},
	HealthSystem.Part.RIGHT_LEG: {width = 0.17, depth = 0.20, offset = 0.095},
}

## Farben wie im Charakterfenster, damit ein zerschossenes Bein in der Welt
## dieselbe Farbe hat wie im Fenster.
const COLOR_HEALTHY := Color(0.42, 0.66, 0.40)
const COLOR_HURT := Color(0.80, 0.70, 0.30)
const COLOR_CRITICAL := Color(0.78, 0.30, 0.24)
const COLOR_DESTROYED := Color(0.10, 0.10, 0.11)

## Auf welcher Ebene die Trefferzonen liegen (1 = Welt, 2 = Spieler, 4 = Ziele).
##
## ACHTUNG, FALLE FÜR SPÄTER: `Projectile` schliesst nur den Schützen selbst
## von der Abfrage aus, nicht dessen Kinder. Bekommt der Spieler einmal einen
## sichtbaren Körper, schiesst er sich mit jedem Schuss selbst in den eigenen
## Arm. Dann muss der Ausschluss in `Projectile` um die Trefferzonen erweitert
## werden — solange die Figur nur Ziele und später Gegner sind, stellt sich das
## Problem nicht.
@export_flags_3d_physics var hit_layer: int = 4

## Eigenes Gesundheitssystem. Wird angelegt, wenn keines gesetzt ist —
## damit eine Figur als Ziel für sich allein funktioniert.
var health: HealthSystem

## Schutzplatte, falls die Figur eine trägt. Deckt vorerst nur die Brust ab.
var plate: ArmorPlateData
var plate_durability: float = 0.0

var _meshes: Dictionary = {}
var _hitboxes: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if health == null:
		health = HealthSystem.new()
		health.name = "Health"
		add_child(health)
	if not health.died.is_connected(_on_died):
		health.died.connect(_on_died)
	build()
	refresh_colors()


## Welche Glieder ein Zwischengelenk bekommen, und wo es sitzt.
##
## ---------------------------------------------------------------------------
## SIEBEN KÖRPERTEILE, ABER MEHR ALS SIEBEN KÄSTEN
##
## Ein Arm aus einem Stück kann nur pendeln. Für alles, was darüber hinausgeht
## — greifen, eine Waffe anlegen, sich abstützen — braucht es den Ellenbogen.
##
## `HealthSystem` bleibt davon UNBERÜHRT: Ober- und Unterarm melden beide
## `LEFT_ARM`. Ein Treffer in den Unterarm ist ein Armtreffer, und das ist auch
## richtig so — ein eigenes Trefferziel „Unterarm" hiesse, Lucas' Datenmodell
## anzufassen, und dafür gibt es keinen Grund. Die Geometrie wird feiner, die
## Spielregel bleibt gleich.
##
## `at` ist der Anteil des Glieds, der ÜBER dem Gelenk liegt. Beim Arm sitzt
## der Ellenbogen etwas oberhalb der Mitte, weil Unterarm plus Hand länger sind
## als der Oberarm; beim Bein liegt das Knie fast mittig.
const HINGES := {
	HealthSystem.Part.LEFT_ARM: {name = "LeftElbow", at = 0.44},
	HealthSystem.Part.RIGHT_ARM: {name = "RightElbow", at = 0.44},
	HealthSystem.Part.LEFT_LEG: {name = "LeftKnee", at = 0.48},
	HealthSystem.Part.RIGHT_LEG: {name = "RightKnee", at = 0.48},
}

## Wie stark sich das untere Segment verjüngt. Ein Unterarm ist schmaler als
## ein Oberarm, ein Unterschenkel schmaler als ein Oberschenkel.
const TAPER := 0.85


## Baut die Figur samt Trefferzonen auf. Mehrfach aufrufbar.
func build() -> void:
	for part in _meshes:
		for node in _meshes[part]:
			(node as Node).queue_free()
	for part in _hitboxes:
		for node in _hitboxes[part]:
			(node as Node).queue_free()
	_meshes.clear()
	_hitboxes.clear()

	var old_mount := weapon_mount()
	if old_mount != null:
		old_mount.queue_free()
	var mount := Node3D.new()
	mount.name = "Waffenpunkt"
	mount.position = WEAPON_MOUNT
	add_child(mount)

	for part: HealthSystem.Part in VERTICAL:
		var size := size_of(part)
		var centre := centre_of(part)

		_meshes[part] = []
		_hitboxes[part] = []

		# Der Gelenkpunkt sitzt OBEN am Teil, nicht in seiner Mitte: Ein Arm
		# dreht sich um die Schulter, ein Bein um die Hüfte. Läge der Punkt in
		# der Mitte, drehte sich der Arm um den Ellenbogen und der Kopf würde
		# beim Nicken durch den Hals wandern.
		var joint := Node3D.new()
		joint.name = part_name(part)
		joint.position = Vector3(centre.x, centre.y + size.y * 0.5, centre.z)
		add_child(joint)

		if not HINGES.has(part):
			_add_segment(joint, part, size)
			continue

		# Zweiteilig: oberes Segment am Hauptgelenk, unteres an einem
		# Zwischengelenk genau an ihrer Nahtstelle.
		var hinge_data: Dictionary = HINGES[part]
		var upper_height: float = size.y * float(hinge_data.at)
		var lower_height: float = size.y - upper_height

		_add_segment(joint, part, Vector3(size.x, upper_height, size.z))

		var hinge := Node3D.new()
		hinge.name = hinge_data.name
		hinge.position = Vector3(0.0, -upper_height, 0.0)
		joint.add_child(hinge)

		_add_segment(hinge, part, Vector3(size.x * TAPER, lower_height, size.z * TAPER))

		# Am unteren Ende des Unterarms sitzt die Hand. Sie hat keine
		# Geometrie und keine eigene Trefferzone — sie ist nur der Punkt, an
		# dem eine Waffe hängt. Dadurch folgt die Waffe der Armhaltung von
		# selbst, statt getrennt ausgerichtet werden zu müssen.
		if part == HealthSystem.Part.LEFT_ARM or part == HealthSystem.Part.RIGHT_ARM:
			var hand := Node3D.new()
			hand.name = "Hand"
			hand.position = Vector3(0.0, -lower_height, 0.0)
			hinge.add_child(hand)


## Legt einen Kasten samt Trefferzone unter einem Gelenk an.
##
## Der Kasten hängt vom Gelenk nach unten, sein Mittelpunkt liegt also eine
## halbe Höhe darunter. Trefferzone und Mesh bekommen dieselbe Position und
## dieselbe Grösse — sie sind dasselbe Ding, nur einmal sichtbar und einmal
## fühlbar.
func _add_segment(joint: Node3D, part: HealthSystem.Part, size: Vector3) -> void:
	var drop := Vector3(0.0, -size.y * 0.5, 0.0)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = drop
	mesh.material_override = _make_material(COLOR_HEALTHY)
	joint.add_child(mesh)

	var hitbox := CharacterHitbox.new()
	hitbox.name = "Trefferzone"
	hitbox.part = part
	hitbox.character = self

	# OHNE DIESE ZEILE BLEIBEN ALLE TREFFERZONEN IM WELTURSPRUNG STEHEN.
	#
	# AnimatableBody3D übernimmt mit `sync_to_physics` die Hoheit über
	# seine eigene Welttransformation und folgt seinem Elternknoten nicht
	# mehr — gedacht ist das für bewegliche Plattformen, die man direkt
	# verschiebt. Hier hängen die Kästen aber unter der Figur und sollen
	# mit ihr wandern.
	#
	# Die Figur sah dadurch völlig richtig aus (die Meshes folgen ja),
	# während die Trefferzonen aller Figuren übereinander im Ursprung
	# lagen. Ein Schuss ins Nichts hätte getroffen, ein Schuss auf die
	# Figur nichts.
	hitbox.sync_to_physics = false

	hitbox.collision_layer = hit_layer
	# Die Trefferzone selbst sucht nichts — sie wird nur gefunden.
	hitbox.collision_mask = 0
	hitbox.position = drop

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	hitbox.add_child(shape)
	joint.add_child(hitbox)

	_meshes[part].append(mesh)
	_hitboxes[part].append(hitbox)


## Grösse eines Körperteils in Metern.
func size_of(part: HealthSystem.Part) -> Vector3:
	var vertical: Array = VERTICAL[part]
	var horizontal: Dictionary = HORIZONTAL[part]
	return Vector3(horizontal.width, float(vertical[1]) * SCALE, horizontal.depth)


## Mittelpunkt eines Körperteils, gemessen vom Boden zwischen den Füssen.
func centre_of(part: HealthSystem.Part) -> Vector3:
	var vertical: Array = VERTICAL[part]
	var top: float = vertical[0]
	var height: float = vertical[1]
	var centre_y := (BOTTOM_FRACTION - top - height * 0.5) * SCALE
	return Vector3(HORIZONTAL[part].offset, centre_y, 0.0)


## Das obere Gelenk eines Körperteils: Schulter, Hüfte, Hals.
## Hier setzt die Animation an.
func joint_of(part: HealthSystem.Part) -> Node3D:
	return get_node_or_null(NodePath(part_name(part)))


## Das Zwischengelenk — Ellenbogen oder Knie. Null bei Rumpf und Kopf.
func hinge_of(part: HealthSystem.Part) -> Node3D:
	if not HINGES.has(part):
		return null
	var joint := joint_of(part)
	if joint == null:
		return null
	return joint.get_node_or_null(NodePath(HINGES[part].name))


## Der Punkt, an dem eine Waffe hängt. Nur an Armen vorhanden.
##
## Zurzeit nur zur Kontrolle: Die Waffe hängt NICHT hier, siehe
## `weapon_mount()`. Der Knoten bleibt, weil er der richtige Aufhängepunkt
## wäre, sobald es inverse Kinematik gibt.
func hand_of(part: HealthSystem.Part) -> Node3D:
	var hinge := hinge_of(part)
	return hinge.get_node_or_null("Hand") as Node3D if hinge != null else null


## Wo eine Waffe vor dem Körper sitzt: rechts der Mitte, auf Brusthöhe.
##
## ---------------------------------------------------------------------------
## WARUM NICHT AN DER HAND, OBWOHL DAS NAHELIEGT
##
## Erster Versuch war genau das, mit der Begründung, dass die Waffe dann der
## Armhaltung von selbst folgt. Im Rendering stand die Mündung daraufhin auf
## 2,02 m Höhe — die Waffe zeigte in den Himmel.
##
## Der Grund: Eine Hand am Ende von Schulter und Ellenbogen trägt deren
## aufsummierte Drehung, und die ist nicht die Richtung, in die die Waffe
## zeigen soll. Um sie auszugleichen, müsste man die Haltung rückwärts
## rechnen — und bei jeder Änderung der Haltung neu.
##
## Andersherum ist es stabil: Die Waffe sitzt fest und richtig, die Arme
## werden so gestellt, dass sie plausibel danach greifen. Eine Waffe, die in
## die falsche Richtung zeigt, fällt sofort auf; eine Hand, die zwei
## Zentimeter neben dem Griff liegt, bei eckigen Gliedmassen nicht.
## DIE REICHWEITE DES STÜTZARMS BESTIMMT DIESEN WERT MIT. Der Arm ist 0,637 m
## lang, die Schultern stehen 0,56 m auseinander — je weiter rechts die Waffe
## sitzt, desto weiter muss die linke Hand hinüber. Bei 0,06 stak der Schaft
## mitten im Rumpf, bei 0,20 kommt die Stützhand nicht mehr an den
## Vorderschaft. 0,16 ist das Beste aus beidem: Der Schaft sitzt an der
## rechten Kante der Brust statt in ihrer Mitte.
##
## Zum Nachladen reicht auch das nicht — dafür holt `CharacterWeapon` die
## Waffe kurz an den Körper heran, so wie ein Mensch es auch tut.
const WEAPON_MOUNT := Vector3(0.16, 1.30, -0.14)


## Der Knoten, an den eine Waffe gehängt wird.
func weapon_mount() -> Node3D:
	return get_node_or_null("Waffenpunkt") as Node3D


## Die vordere Trefferzone eines Körperteils. Bei zweiteiligen Gliedern das
## obere Segment — für Messungen und Tests, wo eine genügt.
func hitbox_of(part: HealthSystem.Part) -> CharacterHitbox:
	var boxes: Array = _hitboxes.get(part, [])
	return boxes[0] if not boxes.is_empty() else null


## Alle Trefferzonen eines Körperteils. Ein Arm hat zwei.
func hitboxes_of(part: HealthSystem.Part) -> Array:
	return _hitboxes.get(part, [])


## Wertet einen Treffer aus. Gerufen von CharacterHitbox.
##
## Die Rechnung liegt hier und nicht im Kasten, damit es genau eine Stelle
## gibt, an der über Schaden entschieden wird — dieselbe Stelle, die im
## Mehrspielerbetrieb auf den Server wandert.
func take_hit_on_part(part: HealthSystem.Part, ammo: AmmoData, distance: float,
		_point: Vector3, _direction: Vector3) -> Ballistics.HitResult:
	# Eine Platte deckt nur ab, was sie abdeckt. Ein Kopfschuss geht daran
	# vorbei, auch wenn die Weste noch heil ist — genau darum ist Rüstung in
	# diesem Spiel kein Stufensystem, sondern Fläche.
	var covering := plate if _is_covered_by_plate(part) else null
	var result := Ballistics.resolve_hit(ammo, distance, covering, plate_durability, _rng)

	if covering != null:
		plate_durability = maxf(0.0, plate_durability - result.damage_to_armor)

	if health != null and result.damage_to_target > 0.0:
		health.apply_damage(part, result.damage_to_target)

	refresh_colors()
	part_hit.emit(part, result)
	return result


## Welche Teile eine Brustplatte abdeckt.
##
## Nur die Brust. Bauch und Arme bleiben frei — wer sie abdecken will, braucht
## später eigene Platten, und genau das soll die Entscheidung an der
## Ausrüstung interessant machen.
func _is_covered_by_plate(part: HealthSystem.Part) -> bool:
	return plate != null and part == HealthSystem.Part.CHEST


## Färbt die Kästen nach ihrem Zustand ein.
func refresh_colors() -> void:
	if health == null:
		return
	for part: HealthSystem.Part in _meshes:
		var colour := color_for(health.get_ratio(part))
		for mesh: MeshInstance3D in _meshes[part]:
			var material := mesh.material_override as StandardMaterial3D
			if material != null:
				material.albedo_color = colour


static func color_for(ratio: float) -> Color:
	if ratio <= 0.0:
		return COLOR_DESTROYED
	if ratio > 0.5:
		return COLOR_HEALTHY.lerp(COLOR_HURT, (1.0 - ratio) * 2.0)
	return COLOR_HURT.lerp(COLOR_CRITICAL, 1.0 - ratio * 2.0)


## Lesbarer Knotenname, z.B. "LeftArm". Auch der Name, unter dem eine
## Animation das Teil später findet.
static func part_name(part: HealthSystem.Part) -> String:
	return {
		HealthSystem.Part.HEAD: "Head",
		HealthSystem.Part.CHEST: "Chest",
		HealthSystem.Part.STOMACH: "Stomach",
		HealthSystem.Part.LEFT_ARM: "LeftArm",
		HealthSystem.Part.RIGHT_ARM: "RightArm",
		HealthSystem.Part.LEFT_LEG: "LeftLeg",
		HealthSystem.Part.RIGHT_LEG: "RightLeg",
	}.get(part, "Part")


func _on_died(_killing_part: HealthSystem.Part) -> void:
	# Die Trefferzonen bleiben stehen: Eine Leiche soll man weiter treffen
	# können, sonst fliegen Schüsse durch sie hindurch in die Wand dahinter.
	refresh_colors()
	died.emit()


func _make_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.metallic = 0.0
	material.roughness = 0.72
	return material
