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
signal died(killing_part: HealthSystem.Part, at: Vector3)

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

## Wo der letzte Treffer sass — die Weltposition aus take_hit_on_part(). Fuer
## RagdollRig, damit eine Figur sich beim Sterben genau dorthin greift statt
## an eine geschaetzte Stelle. War der Treffer, der gerade toetet, ist das
## exakt die Wundstelle: apply_damage() loest died() synchron innerhalb
## desselben Aufrufs aus, bevor sich dieser Wert wieder aendern kann.
var _last_hit_point: Vector3 = Vector3.ZERO

## Alle bisher gesetzten Einschusslöcher und Blutstreifen — siehe
## _spawn_wound(). Nur damit clear_blood() sie beim Zuruecksetzen
## wiederfindet, ohne den ganzen Knotenbaum abzusuchen.
var _blood: Array[Node3D] = []


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

## Was am Rumpf hängt statt direkt an der Figur.
##
## ---------------------------------------------------------------------------
## WARUM ES DIESEN ZWISCHENKNOTEN GIBT
##
## Vorher hingen alle sieben Teile NEBENEINANDER an der Figur, jedes mit
## seiner absoluten Höhe. Für Gehen und Nachladen genügt das: Da bewegen sich
## nur einzelne Glieder.
##
## Ducken und Hinlegen bewegen dagegen den ganzen Oberkörper. Ohne diesen
## Knoten müsste man Kopf, Brust, Bauch, beide Arme UND den Waffenpunkt
## einzeln absenken und einzeln kippen — sechs Stellen, die beim nächsten
## Ändern auseinanderlaufen. Mit ihm ist Ducken eine Zeile und Hinlegen eine
## zweite.
##
## Die Beine bleiben absichtlich an der Figur: Sie tragen den Körper, sie
## werden nicht von ihm getragen. Beim Ducken sinkt der Rumpf, während die
## Beine sich beugen — genau die entgegengesetzte Bewegung.
##
## Trefferzonen, Waffe und Weste hängen darunter und gehen von selbst mit.
## Eine geduckte Figur ist damit auch wirklich ein kleineres Ziel, ohne dass
## dafür eine einzige Zeile Trefferzonen-Code nötig wäre.
##
## ---------------------------------------------------------------------------
## ER SITZT AUF HÜFTHÖHE, NICHT AM BODEN
##
## Erst stand der Rumpf auf Position null. Das war bequem — alle Höhen aus
## VERTICAL blieben unverändert gültig —, aber falsch, sobald er sich neigt:
## Eine Drehung geht immer um den EIGENEN Ursprung, und der lag damit zwischen
## den Füssen. Elf Grad Vorneigung beim Rennen schoben die Brust dadurch 29 cm
## nach vorn; die Figur kippte wie ein gefällter Baum, statt sich zu beugen.
##
## Jetzt sitzt er auf Hüfthöhe, also dort, wo ein Mensch sich beugt. Die
## Oberkörperteile ziehen diese Höhe von ihrer Position ab und stehen damit
## unverändert an derselben Stelle.
const TORSO_NODE := "Rumpf"

## Höhe des Rumpfgelenks über dem Boden: die Hüfte, also die Oberkante der
## Beine. Aus derselben Quelle gerechnet wie die Beine selbst — wer die
## Proportionen ändert, verschiebt das Gelenk mit.
static func torso_pivot() -> float:
	var vertical: Array = VERTICAL[HealthSystem.Part.LEFT_LEG]
	return (BOTTOM_FRACTION - float(vertical[0])) * SCALE

const UPPER_BODY := [
	HealthSystem.Part.HEAD,
	HealthSystem.Part.CHEST,
	HealthSystem.Part.STOMACH,
	HealthSystem.Part.LEFT_ARM,
	HealthSystem.Part.RIGHT_ARM,
]


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

	# Der Rumpf zuerst: Oberkörper und Waffenpunkt hängen darunter.
	var old_torso := torso()
	if old_torso != null:
		old_torso.queue_free()
	var pivot := torso_pivot()
	var trunk := Node3D.new()
	trunk.name = TORSO_NODE
	trunk.position = Vector3(0.0, pivot, 0.0)
	add_child(trunk)

	var mount := Node3D.new()
	mount.name = "Waffenpunkt"
	# Die Hüfthöhe abziehen: WEAPON_MOUNT ist vom Boden aus gemessen, der
	# Waffenpunkt hängt aber jetzt unter dem Rumpf.
	mount.position = WEAPON_MOUNT - Vector3(0.0, pivot, 0.0)
	mount.rotation_degrees = WEAPON_MOUNT_ROTATION
	trunk.add_child(mount)

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
		# Oberkörper an den Rumpf, Beine an die Figur — siehe UPPER_BODY.
		if UPPER_BODY.has(part):
			# Die Hüfthöhe abziehen, weil der Rumpf dort sitzt. Ohne das
			# stünde der Oberkörper 75 cm zu hoch.
			joint.position.y -= pivot
			trunk.add_child(joint)
		else:
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


## Der Oberkörper als Ganzes. Ducken senkt ihn, Hinlegen kippt ihn.
## Siehe UPPER_BODY.
func torso() -> Node3D:
	return get_node_or_null(NodePath(TORSO_NODE)) as Node3D


## Die sichtbaren Kästen eines Körperteils. Zweiteilige Glieder haben zwei.
##
## Gebraucht, um einzelne Teile vor einer bestimmten Kamera auszublenden —
## der Spieler versteckt so seinen eigenen Kopf, in dem seine Kamera steckt.
func meshes_of(part: HealthSystem.Part) -> Array:
	return _meshes.get(part, [])


## Das obere Gelenk eines Körperteils: Schulter, Hüfte, Hals.
## Hier setzt die Animation an.
##
## Sucht an beiden Stellen, weil die Beine an der Figur hängen und der
## Oberkörper am Rumpf. Wer hier nur einen der beiden Orte absucht, bekommt
## für die halbe Figur `null` zurück — und eine Animation, die stillschweigend
## nur die Beine bewegt.
func joint_of(part: HealthSystem.Part) -> Node3D:
	var name := NodePath(part_name(part))
	var direct := get_node_or_null(name) as Node3D
	if direct != null:
		return direct
	var trunk := torso()
	return trunk.get_node_or_null(name) as Node3D if trunk != null else null


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
const WEAPON_MOUNT := Vector3(0.18, 1.30, -0.14)

## Wie die Waffe im Anschlag steht.
##
## ---------------------------------------------------------------------------
## ANGEWINKELT, NICHT ACHSPARALLEL
##
## Eine Waffe, die genau nach vorn zeigt und dabei rechts am Körper sitzt,
## steht schräg zur Ziellinie — der Schütze zielte an ihr vorbei. In
## Wirklichkeit liegt der Schaft an der rechten Schulter und die Mündung
## wandert zur Mitte, die Waffe steht also im Winkel zum Körper.
##
## Das löst nebenbei zwei Probleme auf einmal: Der Schaft schwenkt nach
## rechts aus der Brust heraus, und die Mündung — und mit ihr der
## Stützgriff — kommt zur Mitte, also näher an die linke Hand. Erst dadurch
## darf die Waffe überhaupt so weit rechts sitzen.
const WEAPON_MOUNT_ROTATION := Vector3(0.0, 12.0, 0.0)


## Der Knoten, an den eine Waffe gehängt wird.
func weapon_mount() -> Node3D:
	# Hängt am Rumpf, damit die Waffe beim Ducken und Hinlegen mitgeht.
	var trunk := torso()
	if trunk != null:
		var at_torso := trunk.get_node_or_null("Waffenpunkt") as Node3D
		if at_torso != null:
			return at_torso
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
		point: Vector3, direction: Vector3) -> Ballistics.HitResult:
	_last_hit_point = point

	# Eine Platte deckt nur ab, was sie abdeckt. Ein Kopfschuss geht daran
	# vorbei, auch wenn die Weste noch heil ist — genau darum ist Rüstung in
	# diesem Spiel kein Stufensystem, sondern Fläche.
	var covering := plate if _is_covered_by_plate(part) else null
	var result := Ballistics.resolve_hit(ammo, distance, covering, plate_durability, _rng)

	if covering != null:
		plate_durability = maxf(0.0, plate_durability - result.damage_to_armor)

	if health != null and result.damage_to_target > 0.0:
		health.apply_damage(part, result.damage_to_target)

	# JEDER Treffer, der wirklich Fleisch erreicht — nicht mehr nur, wenn
	# Ballistics eine Blutung auswuerfelt (AmmoData.bleeding_chance faerbt nur
	# noch, wie stark der Streifen ausfaellt, siehe caused_heavy_bleeding
	# unten). Ein von der Platte GESTOPPTER Treffer bleibt aussen vor: stumpfe
	# Wucht durch heile Haut blutet nicht, siehe Ballistics._roll_bleeding().
	var reached_flesh := result.damage_to_target > 0.0 and (not result.was_armored or result.penetrated)
	if reached_flesh:
		_spawn_wound(part, point, direction, result.caused_heavy_bleeding)

	refresh_colors()
	part_hit.emit(part, result)
	return result


## Setzt Einschussloch, herablaufenden Blutstreifen und ein paar Spritzer an
## die Einschlagstelle. Haengt am naeheren der ein oder zwei Meshes des
## Koerperteils, damit alles bei zweiteiligen Gliedern (Arm/Bein) am
## richtigen Segment sitzt und nicht am Oberarm klebt, obwohl der Unterarm
## getroffen wurde.
##
## `direction` ist die Flugrichtung des Geschosses (Schuetze -> Trefferpunkt),
## keine echte Flaechennormale — CharacterHitbox liefert keine. Die
## GEGENRICHTUNG ist trotzdem eine brauchbare Naeherung: Genau dieselbe
## Ersatzrechnung nutzt Projectile._check_segment() schon dort, wo die Physik
## keine echte Normale liefert (`-_velocity.normalized()`).
func _spawn_wound(part: HealthSystem.Part, point: Vector3, direction: Vector3, heavy: bool) -> void:
	var target_mesh: MeshInstance3D = null
	var local_point := Vector3.ZERO

	for mesh: MeshInstance3D in meshes_of(part):
		var candidate := mesh.global_transform.affine_inverse() * point
		if target_mesh == null:
			target_mesh = mesh
			local_point = candidate

		var box := mesh.mesh as BoxMesh
		if box == null:
			continue
		var half := box.size * 0.5
		if absf(candidate.x) <= half.x and absf(candidate.y) <= half.y \
				and absf(candidate.z) <= half.z:
			target_mesh = mesh
			local_point = candidate
			break

	if target_mesh == null:
		return

	var normal := -direction if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var hole := WoundHole.spawn(target_mesh, point, normal)
	if hole != null:
		_blood.append(hole)

	var bleed := WoundBleed.new()
	bleed.heavy = heavy
	bleed.target_length = _edge_length(target_mesh, local_point)
	bleed.body_hit_layer = hit_layer
	target_mesh.add_child(bleed)
	bleed.position = local_point
	_blood.append(bleed)

	_spawn_splatter(point, direction, part)


## Standardlaenge, wenn das Mesh aus irgendeinem Grund kein BoxMesh ist.
const FALLBACK_DRIP_LENGTH := 0.16

## Wie weit die Wunde vom UNTEREN Rand des eigenen Meshs entfernt ist — so
## weit darf WoundBleed als starrer Streifen laufen, bevor er (siehe dort)
## in einzelne, frei fallende Tropfen uebergeht.
##
## FRUEHER lief der Streifen bis zum BODEN (per Strahl gemessen), egal wie
## weit das war. Bei einem Brusttreffer bedeutete das: der Streifen zog sich
## als starre, gerade Linie durch die Luft bis zum Boden — durch die Luecke
## zwischen den Beinen hindurch, denn die Figur ist dort keine durchgehende
## Flaeche. Jetzt bleibt der Streifen auf dem Koerperteil, an dem er
## tatsaechlich haengt, und alles danach faellt als echter Tropfen (siehe
## BloodDrop), statt eine Gerade zu simulieren, wo keine Flaeche ist.
##
## `local_point` ist bereits im lokalen Raum von `mesh` — ein BoxMesh ist
## dort um seinen eigenen Mittelpunkt zentriert, der untere Rand liegt also
## bei -size.y * 0.5.
func _edge_length(mesh: MeshInstance3D, local_point: Vector3) -> float:
	var box := mesh.mesh as BoxMesh
	if box == null:
		return FALLBACK_DRIP_LENGTH
	return maxf(0.03, local_point.y + box.size.y * 0.5)


## Wie viele Spritzer ein Treffer zusaetzlich zum Hauptstreifen wirft. War 6.
const SPLATTER_COUNT := 10

## Wie weit ein einzelner Spritzer hoechstens fliegt, bevor er landen kann.
const SPLATTER_DISTANCE := 0.5

## Wirft ein paar kleine Spritzer in eine zufaellige, nach unten und vom
## Schuetzen weg geneigte Richtung — landen sie auf einer festen Flaeche
## (Boden, Wand, oder ein anderes Koerperteil derselben Figur), bleibt dort
## ein kleiner Fleck zurueck. Landet keiner (offener Raum), passiert einfach
## nichts — kein Spritzer erzwungen, wo keiner hinpasst.
func _spawn_splatter(point: Vector3, direction: Vector3, part: HealthSystem.Part) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var away := -direction if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var own_hitbox := hitbox_of(part)

	for i in range(SPLATTER_COUNT):
		# Zufallsrichtung, bevorzugt nach unten (nie nach oben — das saehe aus
		# wie ein Springbrunnen), mit der Schussgegenrichtung gemischt, damit
		# es tendenziell vom Schuetzen weg spritzt statt kreisfoermig.
		var random_dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, -0.1),
			randf_range(-1.0, 1.0))
		var spread := (random_dir + away * 0.6).normalized()
		var to := point + spread * randf_range(0.15, SPLATTER_DISTANCE)

		var query := PhysicsRayQueryParameters3D.create(point, to)
		# Welt UND die eigenen Trefferzonen — ein Spritzer soll auch auf einem
		# anderen Koerperteil derselben Figur landen koennen.
		query.collision_mask = 1 | hit_layer
		query.collide_with_areas = false
		if own_hitbox != null:
			query.exclude = [own_hitbox.get_rid()]

		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue

		var collider: Object = hit.get("collider")
		var landing_point: Vector3 = hit.position
		var landing_normal: Vector3 = hit.get("normal", Vector3.UP)
		var landing_parent: Node = get_tree().current_scene

		if collider is CharacterHitbox and (collider as CharacterHitbox).character == self:
			var landed_meshes := meshes_of((collider as CharacterHitbox).part)
			if not landed_meshes.is_empty():
				landing_parent = landed_meshes[0]

		if landing_parent == null:
			continue

		var splatter := WoundHole.spawn(landing_parent, landing_point, landing_normal)
		if splatter != null:
			splatter.size *= 0.6
			_blood.append(splatter)


## Entfernt alle Einschusslöcher und Blutstreifen — gerufen beim
## Zuruecksetzen (siehe HumanoidTarget.reset()), sonst klebt eine geheilte
## Figur weiter voller Wunden von der letzten Runde.
func clear_blood() -> void:
	for mark in _blood:
		if is_instance_valid(mark):
			mark.queue_free()
	_blood.clear()


## Meldet einen Wund-/Blutfleck zur Nachverfolgung an, der NICHT direkt beim
## Treffer entstand, sondern zeitversetzt — etwa ein BloodDrop (siehe dort),
## der erst Sekunden spaeter auf einem Koerperteil DERSELBEN Figur landet.
## Ohne das wuerde clear_blood() ihn nicht finden, und ein zurueckgesetztes
## Ziel bliebe an dieser einen Stelle trotzdem befleckt.
func remember_wound_mark(mark: Node3D) -> void:
	_blood.append(mark)


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


func _on_died(killing_part: HealthSystem.Part) -> void:
	# Die Trefferzonen bleiben stehen: Eine Leiche soll man weiter treffen
	# können, sonst fliegen Schüsse durch sie hindurch in die Wand dahinter.
	refresh_colors()
	died.emit(killing_part, _last_hit_point)


func _make_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.metallic = 0.0
	material.roughness = 0.72
	return material
