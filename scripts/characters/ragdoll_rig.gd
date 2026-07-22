## Haengt eine Figur ein, die beim Sterben wirklich als Ragdoll auseinanderfaellt.
##
## ---------------------------------------------------------------------------
## WARUM VON HAND GEBAUT UND NICHT GODOTS EIGENES RAGDOLL
##
## Godots eingebautes Ragdoll-Werkzeug braucht `Skeleton3D` und
## `PhysicalBone3D` — `BlockyCharacter` hat bewusst keins (siehe dessen
## Kopfkommentar "KEIN SKELETT"): Arme und Beine sind eigene Kaesten mit
## festen Gelenkpunkten, keine Knochen mit weicher Verformung.
##
## Genau das laesst sich aber direkt als Ragdoll verwenden: Die Figur besteht
## bereits aus elf Kaesten (Kopf, Brust, Bauch, je zwei Segmente pro Arm und
## Bein — siehe `BlockyCharacter.HINGES`/`VERTICAL`), verbunden an genau
## definierten Punkten (`joint_of()`/`hinge_of()`). Diese Klasse baut daraus
## beim Tod elf unabhaengige `RigidBody3D` und verbindet sie mit
## `Generic6DOFJoint3D`-Gelenken an denselben Punkten — dieselbe Anatomie,
## jetzt mit echter Physik dazwischen statt starrer Elternschaft.
##
## ---------------------------------------------------------------------------
## DIE FIGUR WIRD NICHT ZERLEGT, NUR VERSTECKT
##
## `BlockyCharacter`, `HumanoidTarget` und `HealthSystem` bleiben unangetastet.
## Die Originalfigur liefert nur die Maße, Farben und Gelenkpunkte (alles
## bereits am lebenden Koerper vorhanden) und wird danach unsichtbar und
## unkollidierbar gemacht — sie bleibt als Datenobjekt bestehen (Gesundheit,
## `reset()`), nur ihre starre Darstellung weicht den beweglichen Kaesten.
class_name RagdollRig
extends Node3D

## Grobe Dichte fuer die Masse eines Kastens (kg je Kubikmeter Boxvolumen).
## Reine Gefuehlssache — siehe CLAUDE.md: Das kann nur ein Mensch im Spiel
## beurteilen, nicht Claude.
##
## War vorher 12.0 — das ist Styropor-Dichte, kein Koerper. Ein Mensch liegt
## eher bei Wasserdichte (~1000 kg/m³); mit rechteckigen Kaesten statt runder
## Glieder (die mehr Volumen als echte Gliedmassen einnehmen) liegt ein
## glaubwuerdiger Wert etwas darunter.
const PIECE_DENSITY := 200.0

const AXES := ["x", "y", "z"]

## Gelenktypen: ELBOW/KNEE biegen nur um eine Achse — und zwar in
## ENTGEGENGESETZTE Richtungen (ein Ellbogen biegt nach vorn, ein Knie nach
## hinten; siehe _joint()). Die uebrigen sind kugelgelenkartig mit
## unterschiedlich weiten Grenzen.
enum JointKind { ELBOW, KNEE, NECK, WAIST, SHOULDER, HIP }

## Wohin der Brustkasten beim Sterben gestossen wird — RICHTUNG IM EIGENEN
## RAUM dieses Rigs, nicht in Weltkoordinaten (das Rig selbst steht meist
## ungedreht, siehe schiessstand.gd). Vector3.ZERO = kein bevorzugter Stoss,
## nur die Gelenkphysik und die Schwerkraft entscheiden.
@export var fall_impulse_dir: Vector3 = Vector3.ZERO

## Wie kraeftig der Stoss ist.
@export var fall_impulse_strength: float = 1.4

## Die Figur, die in diesem Rig haengt.
var figure: BlockyCharacter

## Die Lage beim Aufstellen — reset() kehrt genau hierhin zurueck.
var _spawn_transform: Transform3D

## Koerperteil -> Array[RigidBody3D], ein- oder zweiteilig wie figure.meshes_of().
var _pieces: Dictionary = {}

var _joints: Array[Generic6DOFJoint3D] = []

var _ragdolling: bool = false


## Haengt die Figur ein. Sie steht danach exakt dort, wo dieses Rig steht.
func attach(target: BlockyCharacter) -> void:
	figure = target
	add_child(figure)
	figure.position = Vector3.ZERO
	if not figure.died.is_connected(_on_died):
		figure.died.connect(_on_died)


## Muss NACH dem Setzen von global_position/global_rotation im Level-Skript
## aufgerufen werden — reset() kehrt sonst an die falsche (Ursprungs-)Stelle
## zurueck, weil dieser Aufruf vor dem Platzieren im Level laeuft.
func remember_spawn() -> void:
	_spawn_transform = global_transform


func _on_died() -> void:
	if _ragdolling:
		return
	_ragdolling = true

	for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
		var built: Array[RigidBody3D] = []
		for mesh in figure.meshes_of(part):
			built.append(_build_piece(mesh as MeshInstance3D))
		_pieces[part] = built

		for hitbox in figure.hitboxes_of(part):
			(hitbox as CharacterHitbox).collision_layer = 0

	figure.visible = false

	_build_joints()
	_buckle_legs()

	if fall_impulse_dir.length_squared() > 0.0001:
		var chest: Array = _pieces.get(HealthSystem.Part.CHEST, [])
		if not chest.is_empty():
			var body: RigidBody3D = chest[0]
			var world_dir: Vector3 = global_transform.basis * fall_impulse_dir.normalized()
			body.apply_central_impulse(world_dir * fall_impulse_strength * body.mass)


## Wie kraeftig Knie und Hueften beim Sterben angestossen werden, damit die
## Beine sofort einknicken. Reine Gefuehlssache — siehe CLAUDE.md.
const KNEE_BUCKLE_IMPULSE := 2.2
const HIP_BUCKLE_IMPULSE := 1.6

## OHNE DAS BLEIBT EIN GERADES BEIN EINFACH STEHEN.
##
## Ein senkrechtes Bein traegt sein eigenes Gewicht rein strukturell, wie ein
## Stapel Kisten — die Physik hat von sich aus keinen Grund, es umzuwerfen,
## und manche Figuren blieben deshalb spuerbar laenger stehen, bevor sie
## endlich kippten. Ein echter Toter haelt sich aber nicht selbst aufrecht.
##
## Ein Stoss GENAU IN DIE ERLAUBTE KNIERICHTUNG (siehe JointKind.KNEE:
## negative Drehung um die lokale X-Achse) reicht, damit das Knie sofort
## nachgibt, statt zufaellig auf der Stelle zu balancieren — dieselbe Drehung
## bekommt zusaetzlich die Huefte, damit das GANZE Bein zusammensackt, nicht
## nur der Unterschenkel abknickt, waehrend der Oberschenkel steif bleibt.
##
## NUR DIE BEINE, SONST NICHTS: Ein Stoss auf Brust/Arme saehe aus wie ein
## Schlag von aussen, nicht wie ein Zusammensacken aus eigener Schwaeche —
## deshalb bleibt der Rest der Figur hier unangetastet.
func _buckle_legs() -> void:
	for part in [HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG]:
		var pieces: Array = _pieces.get(part, [])
		if pieces.size() < 2:
			continue
		var upper: RigidBody3D = pieces[0]
		var lower: RigidBody3D = pieces[1]
		var bend_axis: Vector3 = lower.global_transform.basis.x
		upper.apply_torque_impulse(-bend_axis * HIP_BUCKLE_IMPULSE * upper.mass)
		lower.apply_torque_impulse(-bend_axis * KNEE_BUCKLE_IMPULSE * lower.mass)


## Baut einen einzelnen Ragdoll-Kasten aus einem bestehenden Mesh der Figur —
## Groesse, Lage und Farbe stehen dort schon, nichts muss neu ausgerechnet
## werden.
func _build_piece(mesh: MeshInstance3D) -> RigidBody3D:
	var box_mesh := mesh.mesh as BoxMesh
	var size := box_mesh.size if box_mesh != null else Vector3.ONE * 0.2

	var body := RigidBody3D.new()
	body.mass = maxf(0.5, size.x * size.y * size.z * PIECE_DENSITY)
	# Nur wenig Daempfung — eine Leiche wehrt sich nicht, sie faellt sofort und
	# ganz in sich zusammen. Die eigentliche Bremse gegen wildes Herumschlagen
	# sind die Gelenkgrenzen in _joint() (siehe deren Kommentar zum vorherigen
	# Softness-Fehler); zu viel Daempfung hier liess den Koerper dagegen
	# schweben/bremsen statt schwer herunterzufallen.
	body.angular_damp = 0.4
	body.linear_damp = 0.05
	# Wenig Reibung — sonst kann sich ein Fuss am Boden "festkrallen" und die
	# Figur bleibt auf einem geraden Bein stehen, statt wegzurutschen.
	var material := PhysicsMaterial.new()
	material.friction = 0.3
	body.physics_material_override = material
	# Dieselbe Ebene wie Boden und Waende ("Welt") — die Trefferzonen der
	# lebenden Figur liegen auf einer eigenen Ebene und sind davon unberuehrt.
	body.collision_layer = 1
	body.collision_mask = 1
	# ERST einhaengen, DANN global_transform setzen: Ohne Elternknoten wuerde
	# der Setter die Weltlage als lokale Lage uebernehmen, und beim
	# nachtraeglichen Einhaengen unter dieses (versetzte) Rig stuende der
	# Kasten an der falschen Stelle.
	add_child(body)
	body.global_transform = mesh.global_transform

	var visual := MeshInstance3D.new()
	# Dieselbe Box-Ressource — sie aendert sich nicht mehr, ein Duplikat waere
	# nur ueberfluessiger Ballast.
	visual.mesh = box_mesh
	var source_material := mesh.material_override as StandardMaterial3D
	if source_material != null:
		# Die Farbe WIRD dupliziert: Ohne das teilten sich totes Ragdoll-Stueck
		# und die (nur versteckte, nicht geloeschte) Originalfigur dieselbe
		# Material-Ressource — faerbt refresh_colors() die Figur nach einem
		# reset() um, faerbte es hier rueckwirkend mit, obwohl der Kasten
		# laengst durch einen neuen ersetzt sein sollte.
		visual.material_override = source_material.duplicate()
	body.add_child(visual)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	return body


## Zehn Gelenke an genau den Punkten, die die Figur schon kennt.
func _build_joints() -> void:
	_joint(HealthSystem.Part.HEAD, 0, HealthSystem.Part.CHEST, 0,
		figure.joint_of(HealthSystem.Part.HEAD).global_position, JointKind.NECK)
	_joint(HealthSystem.Part.CHEST, 0, HealthSystem.Part.STOMACH, 0,
		figure.joint_of(HealthSystem.Part.STOMACH).global_position, JointKind.WAIST)
	_joint(HealthSystem.Part.CHEST, 0, HealthSystem.Part.LEFT_ARM, 0,
		figure.joint_of(HealthSystem.Part.LEFT_ARM).global_position, JointKind.SHOULDER)
	_joint(HealthSystem.Part.CHEST, 0, HealthSystem.Part.RIGHT_ARM, 0,
		figure.joint_of(HealthSystem.Part.RIGHT_ARM).global_position, JointKind.SHOULDER)
	_joint(HealthSystem.Part.STOMACH, 0, HealthSystem.Part.LEFT_LEG, 0,
		figure.joint_of(HealthSystem.Part.LEFT_LEG).global_position, JointKind.HIP)
	_joint(HealthSystem.Part.STOMACH, 0, HealthSystem.Part.RIGHT_LEG, 0,
		figure.joint_of(HealthSystem.Part.RIGHT_LEG).global_position, JointKind.HIP)
	_joint(HealthSystem.Part.LEFT_ARM, 0, HealthSystem.Part.LEFT_ARM, 1,
		figure.hinge_of(HealthSystem.Part.LEFT_ARM).global_position, JointKind.ELBOW)
	_joint(HealthSystem.Part.RIGHT_ARM, 0, HealthSystem.Part.RIGHT_ARM, 1,
		figure.hinge_of(HealthSystem.Part.RIGHT_ARM).global_position, JointKind.ELBOW)
	_joint(HealthSystem.Part.LEFT_LEG, 0, HealthSystem.Part.LEFT_LEG, 1,
		figure.hinge_of(HealthSystem.Part.LEFT_LEG).global_position, JointKind.KNEE)
	_joint(HealthSystem.Part.RIGHT_LEG, 0, HealthSystem.Part.RIGHT_LEG, 1,
		figure.hinge_of(HealthSystem.Part.RIGHT_LEG).global_position, JointKind.KNEE)


func _joint(part_a: HealthSystem.Part, index_a: int, part_b: HealthSystem.Part, index_b: int,
		anchor: Vector3, kind: JointKind) -> void:
	var pieces_a: Array = _pieces.get(part_a, [])
	var pieces_b: Array = _pieces.get(part_b, [])
	if index_a >= pieces_a.size() or index_b >= pieces_b.size():
		return
	var body_a: RigidBody3D = pieces_a[index_a]
	var body_b: RigidBody3D = pieces_b[index_b]

	var joint := Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_position = anchor
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)

	# Linear komplett gesperrt auf allen drei Achsen — die Kaesten bleiben am
	# Drehpunkt zusammen. Nur die Drehung selbst ist je nach Gelenktyp begrenzt
	# frei.
	#
	# ---------------------------------------------------------------------
	# KEINE SOFTNESS/DAEMPFUNG/RESTITUTION HIER SETZEN — GEPRUEFT, NICHT GERATEN
	#
	# Ein frueherer Versuch setzte PARAM_*_LIMIT_SOFTNESS auf 1.0 in der
	# Annahme "1.0 = steif". Eine gezielte Diagnose (zwei Kaesten, ein Gelenk,
	# ein Stoss, siehe Git-Historie von tools/check_hinge_direction.gd) zeigte
	# das Gegenteil: Mit softness=1.0 blieb das Gelenk nach einem Stoss WEIT
	# AUSSERHALB seiner eigentlichen Grenze haengen (bis zu 120 Grad daneben),
	# ohne Softness/Restitution/Daempfung am Gelenk kehrte es dagegen zuverlaes-
	# sig in die erlaubte Spanne zurueck. Godots Vorgabewerte fuer diese drei
	# Parameter sind also die richtigen — nicht anfassen.
	for axis in AXES:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	# Alle Gradzahlen hier sind ein erster, vernuenftiger Anfang — Gefuehls-
	# sache, siehe CLAUDE.md. Nach dem ersten Ansehen im Spiel angepasst.
	#
	# ---------------------------------------------------------------------
	# EIN ARM/BEIN BEWEGT SICH NICHT IN JEDE RICHTUNG
	#
	# Ein Kugelgelenk mit drei weit offenen Achsen (frueherer Stand: bis zu
	# 90 Grad auf allen dreien gleichzeitig) sieht aus wie ein Arm ohne
	# Schulter — er kann buchstaeblich ueberallhin zeigen. Ein echtes
	# Schulter-/Huftgelenk hat EINE HAUPTACHSE (vor/zurueck schwingen) und
	# bleibt auf den anderen beiden eng: kaum Drehung um die eigene Laengs-
	# achse, nur wenig seitliches Abspreizen. Deshalb ist hier nur noch eine
	# Achse pro Gelenk grosszuegig, die uebrigen bewusst eng.
	match kind:
		JointKind.ELBOW:
			# Scharnier: eine Achse offen (Beugen), die anderen beiden starr.
			# Ein Ellbogen biegt nach VORN (positive Drehung um die lokale
			# X-Achse schwingt den Unterarm in Blickrichtung, also -Z, siehe
			# obige Diagnose) — 0 bis 120 Grad ist deshalb genau richtig.
			_limit_angular(joint, "x", 0.0, 120.0)
			_limit_angular(joint, "y", 0.0, 0.0)
			_limit_angular(joint, "z", 0.0, 0.0)
		JointKind.KNEE:
			# Ein Knie biegt GENAU ANDERSHERUM als ein Ellbogen: nach HINTEN
			# (der Unterschenkel schwingt entgegen der Blickrichtung, also
			# +Z) — das ist NEGATIVE Drehung um die lokale X-Achse. Beide
			# Gelenke mit derselben Spanne zu behandeln (frueherer Stand)
			# liess Knie nach vorn statt nach hinten durchbrechen.
			_limit_angular(joint, "x", -120.0, 0.0)
			_limit_angular(joint, "y", 0.0, 0.0)
			_limit_angular(joint, "z", 0.0, 0.0)
		JointKind.NECK:
			_limit_angular(joint, "x", -20.0, 20.0)
			_limit_angular(joint, "y", -20.0, 20.0)
			_limit_angular(joint, "z", -12.0, 12.0)
		JointKind.WAIST:
			_limit_angular(joint, "x", -12.0, 12.0)
			_limit_angular(joint, "y", -15.0, 15.0)
			_limit_angular(joint, "z", -8.0, 8.0)
		JointKind.SHOULDER:
			# Hauptachse: vor/zurueck schwingen. Die anderen beiden eng, damit
			# der Arm nicht seitlich wegklappt oder sich um sich selbst dreht.
			_limit_angular(joint, "x", -70.0, 70.0)
			_limit_angular(joint, "y", -15.0, 15.0)
			_limit_angular(joint, "z", -20.0, 20.0)
		JointKind.HIP:
			_limit_angular(joint, "x", -55.0, 55.0)
			_limit_angular(joint, "y", -10.0, 10.0)
			_limit_angular(joint, "z", -15.0, 15.0)

	# Ohne das ringen Gelenk und die sich am selben Drehpunkt ueberlappenden
	# Kollisionsformen gegeneinander — das Gelenk will sie zusammenhalten,
	# die Kollision will sie auseinanderdruecken.
	body_a.add_collision_exception_with(body_b)
	body_b.add_collision_exception_with(body_a)

	_joints.append(joint)


## Setzt eine Drehgrenze auf einer Achse — NUR die Grenze selbst. Godots
## Vorgabewerte fuer Softness/Daempfung/Restitution an der Grenze bleiben
## unangetastet, siehe die lange Anmerkung in _joint().
func _limit_angular(joint: Generic6DOFJoint3D, axis: String, lower_deg: float, upper_deg: float) -> void:
	joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(lower_deg))
	joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(upper_deg))


## Setzt Figur UND Rig zurueck — Ragdoll-Kaesten und Gelenke verschwinden,
## die Originalfigur steht wieder unversehrt an ihrem Platz.
func reset() -> void:
	for joint in _joints:
		if is_instance_valid(joint):
			joint.queue_free()
	_joints.clear()

	for part in _pieces:
		for body in _pieces[part]:
			if is_instance_valid(body):
				(body as RigidBody3D).queue_free()
	_pieces.clear()

	if figure != null:
		for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
			for hitbox in figure.hitboxes_of(part):
				(hitbox as CharacterHitbox).collision_layer = figure.hit_layer
		figure.visible = true
		figure.reset()

	global_transform = _spawn_transform
	_ragdolling = false
