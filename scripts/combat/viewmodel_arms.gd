## Arme im Kameraraum: die Hände, die der Spieler an seiner Waffe sieht.
##
## ---------------------------------------------------------------------------
## WARUM NICHT DIE ARME DES KÖRPERS
##
## Der Spieler hat einen vollständigen Körper mit Armen, und der greift seine
## Waffe bereits — sichtbar in der dritten Person. Ihn auch in der ersten
## Person zu zeigen, wurde dreimal versucht und scheiterte dreimal am selben:
##
## Es ist die GRÖSSE. Ein Oberarm ist 0,24 m dick und 0,64 m lang — Masse für
## eine Figur, die man aus drei Metern sieht. Aus einer Kamera, die im selben
## Körper steckt, ist er 20 bis 40 cm entfernt. Beim Geradeausschauen liegt er
## unter dem Bildrand, beim kleinsten Schwenk füllt er den halben Schirm.
##
## Diese Arme sind deshalb eigene Geometrie: dünner, kürzer, dicht an der
## Waffe. Genau dafür gibt es in Shootern ein Modell im Kameraraum.
##
## ---------------------------------------------------------------------------
## DIESELBE MECHANIK WIE AM KÖRPER
##
## Die Schultern sitzen fest relativ zur Kamera, die Hände lösen per inverser
## Kinematik auf `grip_point` und `support_point` der Waffe auf — dieselben
## Punkte, die auch die Figur greift, und dieselbe Rechnung wie in
## `CharacterAnimation._solve_arm()`.
##
## Dadurch folgen die Arme der Waffe von allein: Rückstoss, Nachschwingen,
## Anheben beim Nachladen. Kein einziger Winkel steht hier fest.
class_name ViewmodelArms
extends Node3D

## Wo die Schultern sitzen, relativ zur Kamera.
##
## Unterhalb des Auges und seitlich, knapp unter dem Bildrand. Von dort kommen
## die Unterarme schräg ins Bild — genau so sieht man seine Hände, wenn man
## ein Gewehr im Anschlag hat.
const RIGHT_SHOULDER := Vector3(0.160, -0.250, 0.020)
const LEFT_SHOULDER := Vector3(-0.170, -0.230, -0.060)

## Masse der Glieder.
##
## ---------------------------------------------------------------------------
## SCHLANK, ABER NICHT KURZ
##
## Hier standen erst 0,15 und 0,17 m — „Kameragrösse" hatte ich als kürzer
## verstanden. Das war falsch und im Bild sofort zu sehen: Der Vorderschaft
## liegt 0,59 m von der linken Schulter entfernt, der Arm reichte mit 0,32 m
## nicht einmal in die Nähe. Er blieb auf halbem Weg stehen, und man sah bloss
## eine dunkle Ecke am unteren Bildrand.
##
## Ein Arm ist ein Arm — die Länge ergibt sich aus der Waffe, nicht aus dem
## Bildausschnitt. Klein gemacht wird nur die DICKE: Was 30 cm vor dem Auge
## liegt, darf nicht so klobig sein wie ein Glied, das man aus drei Metern
## sieht.
const UPPER_LENGTH := 0.240
const LOWER_LENGTH := 0.300
const UPPER_THICK := 0.062
const LOWER_THICK := 0.052
const HAND_SIZE := Vector3(0.052, 0.055, 0.070)

## Wohin der Ellenbogen ausweicht: nach aussen und nach unten. Ohne diese
## Vorgabe wäre jede Lage auf dem Kreis gleich gut, und der Arm könnte auch
## nach oben abknicken.
const ELBOW_POLE := Vector3(0.85, -0.55, 0.35)

var _right_shoulder: Node3D
var _right_elbow: Node3D
var _left_shoulder: Node3D
var _left_elbow: Node3D


func _ready() -> void:
	_build()


func _build() -> void:
	_right_shoulder = _make_arm("RightArm", RIGHT_SHOULDER, 1.0)
	_left_shoulder = _make_arm("LeftArm", LEFT_SHOULDER, -1.0)
	_right_elbow = _right_shoulder.get_node("Elbow")
	_left_elbow = _left_shoulder.get_node("Elbow")


## Ein Arm: Oberarm am Schultergelenk, Unterarm am Ellenbogen, Hand am Ende.
##
## Die Glieder hängen nach UNTEN (-Y) vom jeweiligen Gelenk, genau wie am
## Weltkörper. Dadurch gilt dieselbe Rechnung, und wer eines von beiden
## versteht, versteht auch das andere.
func _make_arm(arm_name: String, shoulder: Vector3, side: float) -> Node3D:
	var skin := _skin_material()
	var glove := _glove_material()

	var joint := Node3D.new()
	joint.name = arm_name
	joint.position = shoulder
	add_child(joint)

	joint.add_child(ViewmodelParts.box("Upper",
		Vector3(UPPER_THICK, UPPER_LENGTH, UPPER_THICK),
		Vector3(0.0, -UPPER_LENGTH * 0.5, 0.0), skin))

	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0.0, -UPPER_LENGTH, 0.0)
	joint.add_child(elbow)

	elbow.add_child(ViewmodelParts.box("Lower",
		Vector3(LOWER_THICK, LOWER_LENGTH, LOWER_THICK),
		Vector3(0.0, -LOWER_LENGTH * 0.5, 0.0), skin))

	# Die Hand sitzt am Ende des Unterarms und ist leicht nach innen gedreht —
	# eine Faust um einen Griff steht nicht achsparallel.
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0.0, -LOWER_LENGTH, 0.0)
	hand.rotation_degrees = Vector3(0.0, 0.0, -12.0 * side)
	elbow.add_child(hand)
	hand.add_child(ViewmodelParts.box("Fist", HAND_SIZE, Vector3.ZERO, glove))

	return joint


## Richtet beide Arme auf ihre Ziele aus.
##
## `grip` ist der Pistolengriff, `support` der Vorderschaft — beides Knoten am
## Waffenmodell. Fehlt einer, bleibt der Arm, wo er ist: Ein Arm, der ins
## Leere zeigt, sieht schlimmer aus als einer, der stillsteht.
func aim_at(grip: Node3D, support: Node3D) -> void:
	if grip != null:
		_solve(_right_shoulder, _right_elbow, grip.global_position, 1.0)
	if support != null:
		_solve(_left_shoulder, _left_elbow, support.global_position, -1.0)


## Analytische Zweiknochen-Kinematik, wie in CharacterAnimation.
##
## Kosinussatz: Wie weit liegt der Ellenbogen auf der Linie zum Ziel, und wie
## weit daneben? Gerechnet wird im Raum des ELTERNKNOTENS, nicht in
## Weltkoordinaten — dann stimmt die Rechnung unabhängig davon, wohin die
## Kamera gerade schaut.
##
## Diese Unterscheidung hat am Weltkörper einmal 22 cm gekostet: Dort wurde
## die Schulter im Raum des Rumpfes gerechnet und das Ziel im Raum der Figur.
func _solve(shoulder: Node3D, elbow: Node3D, target: Vector3, side: float) -> void:
	var parent := shoulder.get_parent_node_3d()
	if parent == null:
		return

	var goal: Vector3 = parent.global_transform.affine_inverse() * target
	var delta := goal - shoulder.position
	var distance := delta.length()
	if distance < 0.0001:
		return

	# Ein Arm kann sich nicht strecken. Liegt das Ziel ausserhalb, zeigt er
	# wenigstens dorthin, statt sich zu verrenken.
	distance = clampf(distance,
		absf(UPPER_LENGTH - LOWER_LENGTH) + 0.002,
		UPPER_LENGTH + LOWER_LENGTH - 0.002)
	var direction := delta.normalized()

	var along := (UPPER_LENGTH * UPPER_LENGTH - LOWER_LENGTH * LOWER_LENGTH
		+ distance * distance) / (2.0 * distance)
	var offset := sqrt(maxf(0.0, UPPER_LENGTH * UPPER_LENGTH - along * along))

	var pole := Vector3(ELBOW_POLE.x * side, ELBOW_POLE.y, ELBOW_POLE.z)
	pole -= direction * pole.dot(direction)
	if pole.length_squared() < 0.00001:
		pole = Vector3.UP - direction * Vector3.UP.dot(direction)
	pole = pole.normalized()

	var elbow_point := shoulder.position + direction * along + pole * offset

	shoulder.quaternion = _look_down(elbow_point - shoulder.position)
	# Der Unterarm im Raum des Oberarms: erst die Drehung der Schulter
	# herausrechnen, sonst summieren sich beide auf.
	var lower_dir := (goal - elbow_point).normalized()
	elbow.quaternion = shoulder.quaternion.inverse() * _look_down(lower_dir)


## Dreht die -Y-Achse eines Glieds auf die gewünschte Richtung.
static func _look_down(direction: Vector3) -> Quaternion:
	if direction.length_squared() < 0.00001:
		return Quaternion.IDENTITY
	return Quaternion(Vector3.DOWN, direction.normalized())


## Handschuh und Ärmel. Bewusst matt und dunkel: Etwas so dicht vor dem Auge
## darf nicht spiegeln, sonst zieht es den Blick von der Waffe weg.
static func _skin_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.208, 0.226, 0.180)
	mat.metallic = 0.0
	mat.roughness = 0.92
	return mat


static func _glove_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.112, 0.116, 0.120)
	mat.metallic = 0.0
	mat.roughness = 0.88
	return mat
