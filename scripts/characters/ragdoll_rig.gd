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
## War vorher 12.0 (Styropor), dann 200.0 — immer noch spuerbar leichter als
## ein echter Koerper (~1000 kg/m³ bei Wasserdichte). Gilt fuer JEDEN Kasten
## gleich, Oberkoerper UND Beine: Der Brustkasten ist durch sein groesseres
## Boxvolumen schon jetzt absolut schwerer als ein Beinstueck, eine hoehere
## gemeinsame Dichte macht beide spuerbar schwerer, ohne die Proportion
## zwischen ihnen zu verschieben.
const PIECE_DENSITY := 420.0

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

## Ob eine Figur OHNE fall_impulse_dir zusaetzlich per Zufallsstoss nach vorn
## oder hinten umkippt (siehe _apply_self_topple()). Fuer stehende/laufende
## Dummys gedacht, die wirklich auf eigenen Beinen stehen. Haengende Dummys
## in schiessstand.gd setzen das bewusst aus — die sollen wie vorher OHNE
## Vorzugsrichtung frei nach unten fallen, kein zusaetzlicher Dreh.
@export var self_topple_when_standing: bool = true

## Die Figur, die in diesem Rig haengt.
var figure: BlockyCharacter

## Die Lage beim Aufstellen — reset() kehrt genau hierhin zurueck.
var _spawn_transform: Transform3D

## Koerperteil -> Array[RigidBody3D], ein- oder zweiteilig wie figure.meshes_of().
var _pieces: Dictionary = {}

var _joints: Array[Generic6DOFJoint3D] = []

## Huefte/Knie je Bein einzeln greifbar, damit _buckle_legs() sie gezielt
## per Motor drehen kann, statt alle zehn Gelenke durchsuchen zu muessen.
var _leg_hip_joints: Dictionary = {}
var _leg_knee_joints: Dictionary = {}

## Schulter/Ellbogen je Arm einzeln greifbar, damit _play_wound_collapse()
## die Haende zur Wunde ziehen kann. Siehe _leg_hip_joints/_leg_knee_joints
## fuer denselben Trick bei den Beinen.
var _arm_shoulder_joints: Dictionary = {}
var _arm_elbow_joints: Dictionary = {}

## Chest-Stomach-Gelenk, damit sich der Rumpf beim Wundgriff nach vorn beugen
## kann (siehe _start_wound_waist_bend()) — als wuerde sich die Figur vor
## Schmerz kruemmen.
var _waist_joint: Generic6DOFJoint3D

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


func _on_died(killing_part: HealthSystem.Part, hit_point: Vector3) -> void:
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

	# Toedlicher Treffer in Brust ODER Bauch: eigene Reaktion (Wunde greifen,
	# steif umkippen, siehe _play_wound_collapse()) statt des generischen
	# Knie-Einknickens. Alles andere (vor allem Kopfschuss) bleibt beim
	# bisherigen Ablauf.
	if killing_part == HealthSystem.Part.CHEST or killing_part == HealthSystem.Part.STOMACH:
		_play_wound_collapse(killing_part, hit_point)
		return

	_buckle_legs()

	if fall_impulse_dir.length_squared() > 0.0001:
		var chest: Array = _pieces.get(HealthSystem.Part.CHEST, [])
		if not chest.is_empty():
			var body: RigidBody3D = chest[0]
			var world_dir: Vector3 = global_transform.basis * fall_impulse_dir.normalized()
			body.apply_central_impulse(world_dir * fall_impulse_strength * body.mass)
	elif self_topple_when_standing:
		# Kein vorgegebener Sturzweg (Haenge-Dummys wollen bewusst keinen,
		# siehe self_topple_when_standing) — ohne Anstoss knicken beide Knie
		# SYMMETRISCH gleichzeitig ein (siehe _buckle_legs()), und die Figur
		# sackt nur senkrecht in sich zusammen wie eine Kniebeuge, statt vom
		# Gewicht des Oberkoerpers tatsaechlich nach vorn oder hinten
		# umgerissen zu werden. Ein Zufalls-Drehstoss auf den Brustkasten
		# bricht diese Balance gezielt in eine der beiden Richtungen.
		_apply_self_topple()


## Staerke des Zufalls-Drehstosses aus _apply_self_topple(). Reine
## Gefuehlssache — siehe CLAUDE.md.
const SELF_TOPPLE_TORQUE := 2.6


## Kippt eine Figur ohne vorgegebene Sturzrichtung zufaellig nach vorn oder
## hinten, statt dass sie beim symmetrischen Einknicken beider Knie nur
## senkrecht in sich zusammensackt (siehe Aufrufstelle oben). Dreht um die
## X-Achse dieses Rigs — dieselbe Achse, um die auch Huefte und Knie beim
## Einknicken drehen (siehe JointKind.KNEE/HIP), also garantiert vorn/hinten
## und nicht seitlich.
func _apply_self_topple() -> void:
	var chest: Array = _pieces.get(HealthSystem.Part.CHEST, [])
	if chest.is_empty():
		return
	var body: RigidBody3D = chest[0]
	var direction := -1.0 if randf() < 0.5 else 1.0
	var pitch_axis: Vector3 = global_transform.basis.x
	body.apply_torque_impulse(pitch_axis * direction * SELF_TOPPLE_TORQUE * body.mass)


## Zieldrehgeschwindigkeit (rad/s) fuer den Griff zur Wunde.
const WOUND_CLUTCH_SPEED := 6.0

## Kraft des Klutch-Motors an Schulter/Ellbogen.
const WOUND_CLUTCH_FORCE := 40.0

## Verzoegerung, bevor der Kippstoss kommt. War 0.18 — das kippte die Figur
## praktisch im selben Moment, in dem der Griff zur Wunde erst anfing sich zu
## bewegen. Der ganze Koerpersturz ueberdeckte den Griff dadurch fast
## vollstaendig; man sah vor allem das Umfallen, kaum das Greifen. Jetzt
## bekommt der Griff eine eigene, klar sichtbare Phase, bevor der Sturz
## ueberhaupt beginnt.
const WOUND_TOPPLE_DELAY := 0.55

## Staerke des Kippstosses bei einer Wunde. War 4.2 — schleuderte die Figur
## sichtbar weg statt sie kippen zu lassen, siehe unten.
const WOUND_TOPPLE_TORQUE := 1.8


## Wie weit der Ellbogen bei einem Bauchtreffer hoechstens einknicken darf.
## Kleiner als das normale Ellbogen-Limit (0 bis 120 Grad, siehe JointKind.
## ELBOW): Falten sich Schulter UND Ellbogen beide bis zum Anschlag, wandert
## die Hand nach OBEN in Richtung Brust statt an der tieferen Bauchwunde zu
## bleiben.
const WOUND_STOMACH_ELBOW_LIMIT := 55.0


## Reaktion auf einen toedlichen Treffer in Brust oder Bauch: Die Figur greift
## sich mit der Hand auf der GETROFFENEN SEITE an die genaue Einschlagstelle,
## WAEHREND die Beine steif bleiben (siehe Aufrufstelle in _on_died() — hier
## laeuft bewusst KEIN _buckle_legs()), und kippt kurz darauf wie ein
## gefaellter Baum um, statt in die Knie zu sacken.
##
## NUR EIN ARM, NICHT BEIDE: Vorher griffen immer beide Arme symmetrisch zur
## Mitte — das sah nach einer generischen Pose aus, nicht nach einer Reaktion
## auf EINEN Treffer an EINER Stelle. hit_point (die echte Einschlagsposition
## aus BlockyCharacter._last_hit_point) entscheidet per Vorzeichen der lokalen
## X-Koordinate, welche Seite getroffen wurde — LINKS ist die linke Hand der
## FIGUR bei -X, siehe BlockyCharacter.HORIZONTAL. Der andere Arm bleibt
## passiv und faellt frei mit.
##
## HOEHE UEBER killing_part, NICHT UEBER hit_point.y: Ein Motor kann nur bis
## zu einer Gelenkgrenze drehen, nicht auf einen 3D-Punkt zielen (kein
## Skelett, keine inverse Kinematik, siehe Kopfkommentar dieser Datei) — die
## grobe Unterscheidung Brust/Bauch per Ellbogengrenze (siehe
## WOUND_STOMACH_ELBOW_LIMIT) ist die Naeherung, die diese Anatomie hergibt.
##
## DER GRIFF BLEIBT, BIS DIE FIGUR LIEGT — kein Timer, der den Motor wieder
## abschaltet. Vorher liessen die Arme die Wunde nach kurzer Zeit wieder los
## und flogen beim Umkippen frei mit, was aussah, als liesse die Figur mitten
## im Sterben wieder los.
##
## EIN MOTOR, KEINE FEST GESETZTE ROTATION: Die Arm-Kaesten sind an dieser
## Stelle schon echte RigidBody3D mit Gelenkgrenzen (siehe _build_joints()) —
## ein Motor bewegt sie INNERHALB dieser Grenzen dorthin und HAELT sie danach
## gegen die Grenze, solange er an bleibt. Eine hart gesetzte Rotation koennte
## ausserhalb der Gelenkgrenze landen und wuerde von der Physik im naechsten
## Schritt zurueckgerissen, statt sich wie ein Griff anzufuehlen.
func _play_wound_collapse(killing_part: HealthSystem.Part, hit_point: Vector3) -> void:
	var local_hit := global_transform.affine_inverse() * hit_point
	var reaching_arm := HealthSystem.Part.LEFT_ARM if local_hit.x < 0.0 \
		else HealthSystem.Part.RIGHT_ARM

	var elbow: Generic6DOFJoint3D = _arm_elbow_joints.get(reaching_arm)
	if killing_part == HealthSystem.Part.STOMACH and elbow != null:
		_limit_angular(elbow, "x", 0.0, WOUND_STOMACH_ELBOW_LIMIT)

	_start_wound_clutch_motor(_arm_shoulder_joints.get(reaching_arm))
	_start_wound_clutch_motor(elbow)
	_start_wound_adduction(reaching_arm)
	_start_wound_waist_bend()
	_highlight_reaching_arm(reaching_arm)

	get_tree().create_timer(WOUND_TOPPLE_DELAY).timeout.connect(_apply_wound_topple)


## Wie weit sich der Rumpf beim Wundgriff nach vorn beugt (Grad), und wie
## schnell/kraeftig.
const WOUND_WAIST_BEND_LIMIT := 60.0
const WOUND_WAIST_BEND_SPEED := 3.0
const WOUND_WAIST_BEND_FORCE := 60.0

## Beugt die Brust nach vorn ueber den Bauch — als wuerde sich die Figur vor
## Schmerz kruemmen, zusaetzlich zur greifenden Hand. Funktioniert viel
## zuverlaessiger als die Schulter-Adduktion (siehe _start_wound_adduction()):
## Hier haengt nur EIN einzelnes Gelenk zwischen zwei direkt verbundenen
## Kaesten, kein Doppelpendel aus Ober- und Unterarm mit einem lose
## mitschwingenden Ellbogen — gemessen haelt der Rumpf sein Ziel nach einer
## Sekunde auf 0,000 m genau, ohne jedes Nachpendeln.
func _start_wound_waist_bend() -> void:
	if _waist_joint == null:
		return
	_waist_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	_waist_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
		deg_to_rad(-WOUND_WAIST_BEND_LIMIT))
	_waist_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	_waist_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	# Negative Drehung um die lokale X-Achse beugt die Brust nach VORN
	# (Blickrichtung -Z) — gemessen, nicht hergeleitet, siehe _start_wound_
	# adduction() fuer denselben Vorbehalt bei einer anderen Achse.
	_waist_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,
		-WOUND_WAIST_BEND_SPEED)
	_waist_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT,
		WOUND_WAIST_BEND_FORCE)


## Wie weit die Schulter beim Wundgriff zusaetzlich zur Seite hin NACH INNEN
## ziehen darf (Grad).
##
## War zuerst 75 — mehr, als der Arm unter dem eigenen Gewicht und dem
## Gegenzug des lose mitschwingenden Unterarms tatsaechlich erreichen konnte
## (gemessen: er blieb bei rund 25-35 Grad haengen). Ein Motor, der WEITER als
## das physikalisch Erreichbare drehen will, findet nie eine Ruhelage — er
## drueckt endlos gegen den Widerstand und die Figur "haelt" die Wunde nicht,
## sondern zittert sichtbar (genau das wurde bemaengelt: "alles andere
## ragdollt, ausser der Arm"). 28 Grad ist ein Wert, den der Motor wirklich
## erreicht — er trifft dort auf die eigene Gelenkgrenze wie eine Wand und
## bleibt stehen, statt gegen ein unerreichbares Ziel zu kaempfen. Gemessen
## haelt sich der Abstand danach auf 0,04 m genau, keine 0,08 m Pendeln mehr.
const WOUND_ADDUCTION_LIMIT := 28.0
const WOUND_ADDUCTION_SPEED := 4.0
const WOUND_ADDUCTION_FORCE := 45.0

## Zieht die greifende Schulter nach INNEN, damit die Hand nicht nur vor der
## eigenen Schulter haengt (wo reines Vorschwingen sie belaesst), sondern
## sichtbar zur Mitte von Brust oder Bauch wandert.
##
## WARUM DAS NICHT SCHON DIE X-ACHSE MACHT — GEMESSEN, NICHT VERMUTET: Eine
## Drehung um die lokale X-Achse (siehe _start_wound_clutch_motor()) bewegt
## jeden Punkt des Arms nur in der Y-Z-Ebene. Seine seitliche (X-)Position
## bleibt dabei GENAU auf Hoehe der eigenen Schulter, egal wie weit man
## schwingt — ein reiner Test mit eingefrorenem Rumpf zeigte über zwei
## Sekunden praktisch keine Veraenderung. Nur die Z-Achse ("seitliches
## Abspreizen", siehe JointKind.SHOULDER) bewegt die Hand ueberhaupt seitwaerts
## — hier umgekehrt zum ADDUZIEREN (nach innen) statt zum Abspreizen benutzt.
##
## OHNE KOLLISIONSAUSNAHME MIT DEM RUMPF KOMMT DIE HAND KAUM VOM FLECK: Der
## Oberarm stoesst nach wenigen Grad gegen Brust oder Bauch und bleibt haengen
## (ebenfalls gemessen, nicht vermutet). Eine Hand, die man sich an die
## eigene Brust legt, UEBERLAPPT diese im echten Leben auch — die Ausnahme ist
## also die richtige Antwort auf eine Kollision, die so nicht vorkommen sollte,
## keine Abkuerzung.
func _start_wound_adduction(reaching_arm: HealthSystem.Part) -> void:
	var shoulder: Generic6DOFJoint3D = _arm_shoulder_joints.get(reaching_arm)
	if shoulder == null:
		return

	var torso: Array = _pieces.get(HealthSystem.Part.CHEST, []) + _pieces.get(HealthSystem.Part.STOMACH, [])
	for arm_body: RigidBody3D in _pieces.get(reaching_arm, []):
		for torso_body: RigidBody3D in torso:
			arm_body.add_collision_exception_with(torso_body)
			torso_body.add_collision_exception_with(arm_body)

	# Vorzeichen GEMESSEN, nicht hergeleitet (derselbe Grund wie beim
	# Kniekommentar oben): NEGATIVE Z-Drehung zieht LEFT_ARM zur Mitte,
	# RIGHT_ARM braucht dafuer das genau entgegengesetzte Vorzeichen.
	var sign := -1.0 if reaching_arm == HealthSystem.Part.LEFT_ARM else 1.0
	shoulder.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	shoulder.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
		deg_to_rad(minf(0.0, sign * WOUND_ADDUCTION_LIMIT)))
	shoulder.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,
		deg_to_rad(maxf(0.0, sign * WOUND_ADDUCTION_LIMIT)))
	shoulder.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	shoulder.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, sign * WOUND_ADDUCTION_SPEED)
	shoulder.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, WOUND_ADDUCTION_FORCE)


## Blutrot statt der ueblichen Gesundheitsfarbe — sonst ist der greifende Arm
## im liegenden Haufen nicht von den uebrigen, gleichfarbigen Kaesten zu
## unterscheiden. Haende haben zudem kein eigenes Mesh (siehe
## BlockyCharacter._add_segment()), es gibt also sonst ueberhaupt kein
## sichtbares Zeichen dafuer, WO die Hand liegt.
const WOUND_CLUTCH_COLOR := Color(0.5, 0.08, 0.08)

func _highlight_reaching_arm(reaching_arm: HealthSystem.Part) -> void:
	for body: RigidBody3D in _pieces.get(reaching_arm, []):
		var visual := body.get_child(0) as MeshInstance3D
		var material := visual.material_override as StandardMaterial3D if visual != null else null
		if material != null:
			material.albedo_color = WOUND_CLUTCH_COLOR


## Positive Drehung um die lokale X-Achse ist bei Schulter UND Ellbogen die
## Richtung nach VORN (siehe JointKind.ELBOW oben) — dieselbe Achse und
## Richtung, mit der auch CharacterAnimation die Arme haelt.
func _start_wound_clutch_motor(joint: Generic6DOFJoint3D) -> void:
	if joint == null:
		return
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, WOUND_CLUTCH_SPEED)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, WOUND_CLUTCH_FORCE)


func _apply_wound_topple() -> void:
	var chest: Array = _pieces.get(HealthSystem.Part.CHEST, [])
	if chest.is_empty():
		return
	var body: RigidBody3D = chest[0]
	var direction := -1.0 if randf() < 0.5 else 1.0
	var pitch_axis: Vector3 = global_transform.basis.x
	body.apply_torque_impulse(pitch_axis * direction * WOUND_TOPPLE_TORQUE * body.mass)


## Wie lange Huefte und Knie aktiv in die Einknick-Richtung gedreht werden,
## bevor der Motor sich abschaltet und der Rest des Sturzes wieder komplett
## passive Ragdoll-Physik ist. Reine Gefuehlssache — siehe CLAUDE.md.
const BUCKLE_MOTOR_DURATION := 0.3

## Zieldrehgeschwindigkeit (rad/s) waehrend der Motor aktiv ist. Huefte war
## 5.0 — bei der jetzt breiteren Gelenkgrenze (siehe JointKind.HIP) reichte
## das nicht mehr, um sie sichtbar mitzunehmen, bevor der Motor abschaltet.
const HIP_BUCKLE_SPEED := 8.0
const KNEE_BUCKLE_SPEED := 7.0

## Wie viel Drehmoment der Motor dafuer aufbringen darf — hoch genug, dass es
## GARANTIERT gewinnt (siehe unten, warum ein Impuls das nicht war).
const BUCKLE_MOTOR_FORCE := 60.0

## OHNE DAS BLEIBT EIN GERADES BEIN EINFACH STEHEN.
##
## Ein senkrechtes Bein traegt sein eigenes Gewicht rein strukturell, wie ein
## Stapel Kisten — die Physik hat von sich aus keinen Grund, es umzuwerfen.
## Ein echter Toter haelt sich aber nicht selbst aufrecht: das Gewicht des
## Oberkoerpers soll die Beine zuverlaessig unter sich zusammenklappen lassen.
##
## FRUEHERER STAND: ein einmaliger apply_torque_impulse() auf Huefte und Knie.
## Das reichte manchmal nicht — ein senkrechtes Bein steht an der aeussersten
## Grenze seines Bewegungsspielraums (0 Grad bei JointKind.KNEE/HIP), praktisch
## wie eine Saeule. Ein einzelner Stoss kann von der Traegheit des gerade in
## diesem Moment noch senkrecht aufliegenden Oberkoerpers wieder aufgefangen
## werden, bevor das Knie sichtbar nachgibt — manche Figuren blieben dadurch
## einfach zufaellig stehen.
##
## JETZT: ein ANGULAR MOTOR an Huefte und Knie (Generic6DOFJoint3D kann das
## direkt, siehe _start_buckle_motor()), der BUCKLE_MOTOR_DURATION Sekunden
## lang aktiv in die Einknick-Richtung dreht statt nur einmal anzuschubsen —
## das gewinnt zuverlaessig gegen das Gewicht des Oberkoerpers, egal wie die
## Figur gerade steht. Danach schaltet sich der Motor wieder ab (siehe
## _stop_buckle_motors()), damit der Rest des Sturzes echte, passive
## Ragdoll-Physik bleibt und nicht wie ein Skript aussieht.
##
## NUR DIE BEINE, SONST NICHTS: Ein Motor an Brust/Armen saehe aus wie ein
## Schlag von aussen, nicht wie ein Zusammensacken aus eigener Schwaeche —
## deshalb bleibt der Rest der Figur hier unangetastet.
func _buckle_legs() -> void:
	for part in [HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG]:
		_start_buckle_motor(_leg_hip_joints.get(part), HIP_BUCKLE_SPEED)
		_start_buckle_motor(_leg_knee_joints.get(part), KNEE_BUCKLE_SPEED)

	get_tree().create_timer(BUCKLE_MOTOR_DURATION).timeout.connect(_stop_buckle_motors)


## Negative Drehung um die lokale X-Achse ist bei Huefte UND Knie die
## Einknick-Richtung (siehe JointKind.KNEE/HIP oben) — dieselbe Achse und
## dasselbe Vorzeichen, das vorher schon beim Impuls verwendet wurde.
func _start_buckle_motor(joint: Generic6DOFJoint3D, speed: float) -> void:
	if joint == null:
		return
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, -speed)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, BUCKLE_MOTOR_FORCE)


func _stop_buckle_motors() -> void:
	for dict in [_leg_hip_joints, _leg_knee_joints]:
		for joint: Generic6DOFJoint3D in dict.values():
			if is_instance_valid(joint):
				joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)


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
	#
	# War 0.05 — seit die Kaesten mit hoeherer Dichte (siehe PIECE_DENSITY)
	# auch mehr wiegen, kam auf dem Boden ein zu harter Knall an. Etwas mehr
	# Daempfung bremst genau diesen Aufprall, ohne dass der Koerper vorher
	# spuerbar schwebt.
	body.angular_damp = 0.4
	body.linear_damp = 0.18
	# Wenig Reibung — sonst kann sich ein Fuss am Boden "festkrallen" und die
	# Figur bleibt auf einem geraden Bein stehen, statt wegzurutschen.
	var material := PhysicsMaterial.new()
	material.friction = 0.3
	# Explizit KEIN Abprallen, und zwar auch dann nicht, wenn Boden oder Wand
	# selbst einmal einen Bounce-Wert bekommen sollten — absorbent sorgt
	# dafuer, dass der KLEINERE der beiden Werte gilt, nicht der groessere.
	material.bounce = 0.0
	material.absorbent = true
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
	_waist_joint = _joint(HealthSystem.Part.CHEST, 0, HealthSystem.Part.STOMACH, 0,
		figure.joint_of(HealthSystem.Part.STOMACH).global_position, JointKind.WAIST)
	_arm_shoulder_joints[HealthSystem.Part.LEFT_ARM] = _joint(
		HealthSystem.Part.CHEST, 0, HealthSystem.Part.LEFT_ARM, 0,
		figure.joint_of(HealthSystem.Part.LEFT_ARM).global_position, JointKind.SHOULDER)
	_arm_shoulder_joints[HealthSystem.Part.RIGHT_ARM] = _joint(
		HealthSystem.Part.CHEST, 0, HealthSystem.Part.RIGHT_ARM, 0,
		figure.joint_of(HealthSystem.Part.RIGHT_ARM).global_position, JointKind.SHOULDER)
	_leg_hip_joints[HealthSystem.Part.LEFT_LEG] = _joint(
		HealthSystem.Part.STOMACH, 0, HealthSystem.Part.LEFT_LEG, 0,
		figure.joint_of(HealthSystem.Part.LEFT_LEG).global_position, JointKind.HIP)
	_leg_hip_joints[HealthSystem.Part.RIGHT_LEG] = _joint(
		HealthSystem.Part.STOMACH, 0, HealthSystem.Part.RIGHT_LEG, 0,
		figure.joint_of(HealthSystem.Part.RIGHT_LEG).global_position, JointKind.HIP)
	_arm_elbow_joints[HealthSystem.Part.LEFT_ARM] = _joint(
		HealthSystem.Part.LEFT_ARM, 0, HealthSystem.Part.LEFT_ARM, 1,
		figure.hinge_of(HealthSystem.Part.LEFT_ARM).global_position, JointKind.ELBOW)
	_arm_elbow_joints[HealthSystem.Part.RIGHT_ARM] = _joint(
		HealthSystem.Part.RIGHT_ARM, 0, HealthSystem.Part.RIGHT_ARM, 1,
		figure.hinge_of(HealthSystem.Part.RIGHT_ARM).global_position, JointKind.ELBOW)
	_leg_knee_joints[HealthSystem.Part.LEFT_LEG] = _joint(
		HealthSystem.Part.LEFT_LEG, 0, HealthSystem.Part.LEFT_LEG, 1,
		figure.hinge_of(HealthSystem.Part.LEFT_LEG).global_position, JointKind.KNEE)
	_leg_knee_joints[HealthSystem.Part.RIGHT_LEG] = _joint(
		HealthSystem.Part.RIGHT_LEG, 0, HealthSystem.Part.RIGHT_LEG, 1,
		figure.hinge_of(HealthSystem.Part.RIGHT_LEG).global_position, JointKind.KNEE)


func _joint(part_a: HealthSystem.Part, index_a: int, part_b: HealthSystem.Part, index_b: int,
		anchor: Vector3, kind: JointKind) -> Generic6DOFJoint3D:
	var pieces_a: Array = _pieces.get(part_a, [])
	var pieces_b: Array = _pieces.get(part_b, [])
	if index_a >= pieces_a.size() or index_b >= pieces_b.size():
		return null
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
			# War -55/55/-10/10/-15/15 — spuerbar enger als die Schulter, obwohl
			# eine Huefte anatomisch mindestens genauso viel Spielraum hat. Beim
			# Einknicken (siehe _buckle_legs()) wirkte das Bein dadurch steifer,
			# als es sollte.
			_limit_angular(joint, "x", -75.0, 75.0)
			_limit_angular(joint, "y", -18.0, 18.0)
			_limit_angular(joint, "z", -22.0, 22.0)

	# Ohne das ringen Gelenk und die sich am selben Drehpunkt ueberlappenden
	# Kollisionsformen gegeneinander — das Gelenk will sie zusammenhalten,
	# die Kollision will sie auseinanderdruecken.
	body_a.add_collision_exception_with(body_b)
	body_b.add_collision_exception_with(body_a)

	_joints.append(joint)
	return joint


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
	_leg_hip_joints.clear()
	_leg_knee_joints.clear()
	_arm_shoulder_joints.clear()
	_arm_elbow_joints.clear()
	_waist_joint = null

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
