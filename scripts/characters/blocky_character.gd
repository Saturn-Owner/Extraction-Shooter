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


## Baut die sieben Kästen samt Trefferzonen auf. Mehrfach aufrufbar.
func build() -> void:
	for node in _meshes.values():
		(node as Node).queue_free()
	for node in _hitboxes.values():
		(node as Node).queue_free()
	_meshes.clear()
	_hitboxes.clear()

	for part: HealthSystem.Part in VERTICAL:
		var size := size_of(part)
		var centre := centre_of(part)

		# Der Gelenkpunkt sitzt OBEN am Teil, nicht in seiner Mitte: Ein Arm
		# dreht sich um die Schulter, ein Bein um die Hüfte. Läge der Punkt in
		# der Mitte, drehte sich der Arm um den Ellenbogen und der Kopf würde
		# beim Nicken durch den Hals wandern.
		var joint := Node3D.new()
		joint.name = part_name(part)
		joint.position = Vector3(centre.x, centre.y + size.y * 0.5, centre.z)
		add_child(joint)

		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.position = Vector3(0.0, -size.y * 0.5, 0.0)
		mesh.material_override = _make_material(COLOR_HEALTHY)
		joint.add_child(mesh)

		var hitbox := CharacterHitbox.new()
		hitbox.name = "Trefferzone"
		hitbox.part = part
		hitbox.character = self
		hitbox.collision_layer = hit_layer
		# Die Trefferzone selbst sucht nichts — sie wird nur gefunden.
		hitbox.collision_mask = 0
		hitbox.position = mesh.position

		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		hitbox.add_child(shape)
		joint.add_child(hitbox)

		_meshes[part] = mesh
		_hitboxes[part] = hitbox


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


## Der bewegliche Knoten eines Körperteils — hier setzen später Animationen an.
func joint_of(part: HealthSystem.Part) -> Node3D:
	var mesh: Node = _meshes.get(part)
	return mesh.get_parent() as Node3D if mesh != null else null


func hitbox_of(part: HealthSystem.Part) -> CharacterHitbox:
	return _hitboxes.get(part)


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
		var mesh: MeshInstance3D = _meshes[part]
		var material := mesh.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = color_for(health.get_ratio(part))


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
