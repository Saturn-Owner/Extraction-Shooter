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

## Hals-Gelenk, damit der Kopf beim Nachzucken noch kurz aufrecht gehalten
## werden kann (siehe _start_neck_hold()).
var _neck_joint: Generic6DOFJoint3D

## Blutlache dieses Todes, falls eine entstanden ist — siehe
## _spawn_blood_pool(). Haengt an der Weltszene, nicht an dieser Figur,
## darum haelt reset() sie hier fest, um sie gezielt wieder zu entfernen.
var _blood_pool: BloodPool

## Zusaetzliche freie Kastenstuecke, die es an der lebenden Figur gar nicht
## gibt (weggerissenes Schaedelstueck — siehe _burst_skull_side()). Eigene
## Liste, weil sie zu KEINEM HealthSystem.Part gehoeren und darum nicht schon
## durch die _pieces-Bereinigung in reset() erfasst werden.
var _debris: Array[RigidBody3D] = []

## Das Gelenk eines noch haengenden Schaedelstuecks (siehe _burst_skull_
## side()) — BEWUSST NICHT in _joints: Diese Liste zaehlt die zehn festen
## Gelenke der normalen Anatomie (siehe _build_joints()), auf die sich
## verify_character.gd verlaesst ("zehn Gelenke"). Ein zusaetzliches
## Kopftrauma-Gelenk wuerde diese Zahl auf elf springen lassen.
var _debris_joints: Array[Generic6DOFJoint3D] = []

var _ragdolling: bool = false

## Zaehlt bei jedem Tod UND jedem reset() hoch. _buckle_legs() und
## _play_wound_collapse() planen verzoegerte Timer (Motor abschalten,
## Kippstoss) — wird zwischendurch zurueckgesetzt und die Figur stirbt erneut
## (z. B. Taste 0 kurz nach dem Tod gedrueckt), wuerde ein solcher Timer sonst
## noch auf das NEUE Leben wirken, weil er nicht weiss, dass er zu einem
## laengst vorbeigegangenen Tod gehoert. Jeder Timer merkt sich beim Planen
## den aktuellen Stand und wirkt nur, wenn der beim Ausloesen noch derselbe ist.
var _death_generation: int = 0

## ---------------------------------------------------------------------------
## NACHZUCKEN OHNE KOPFSCHUSS
##
## Ein Kopfschuss schaltet das Nervensystem sofort ab — kein Zucken. Jeder
## andere toedliche Treffer laesst den Koerper noch eine kurze Weile
## unwillkuerlich zittern (siehe _start_death_twitch()/_physics_process()):
##   - der Nacken haelt den Kopf noch ein Stueck aufrecht (_start_neck_hold())
##   - die Beine strampeln IMMER (_twitch_legs_kick, siehe _apply_leg_kick_
##     tick()) — ausdruecklich gefordert, kein Zufall mehr
##   - UND zusaetzlich, mit Zufallschance, versucht eine Hand sich von der
##     Wunde wegzuziehen (_twitch_arm_recoil, siehe _apply_arm_recoil_tick())
## NICHT bei Brust-/Bauchtreffern: _play_wound_collapse() laesst dort schon
## gezielt eine Hand zur Wunde greifen und HAELT sie dauerhaft, UND laesst die
## Beine absichtlich STEIF (siehe dortigen Kommentar, "kippt... wie ein
## gefaellter Baum") — Strampeln/Wegziehen wuerden genau diese Choreografie
## durcheinanderbringen.
## Der Nacken-Halt laeuft ohne eigenen Timer aus (schwach genug, dass der
## Sturz ihn von selbst ueberwaeltigt); Strampeln/Wegziehen laufen dagegen
## als WIEDERHOLTE Stoesse im selben Takt wie das allgemeine Zittern (siehe
## _twitch_timer) — ein einzelner Motor-Halt war zu schwach, um sichtbar zu
## sein (siehe Git-Historie der fruehreren TWITCH_REACH-Variante).
## ---------------------------------------------------------------------------

## Wie lange nach dem Tod noch gezuckt wird.
const TWITCH_DURATION := 1.6

## Wie oft (Sekunden, mit Zufallsstreuung) ein neuer Zuck-Stoss kommt.
const TWITCH_INTERVAL_MIN := 0.08
const TWITCH_INTERVAL_MAX := 0.22

## Wie kraeftig ein einzelner Zuck ist — war 0.35/0.12, kaum zu sehen. Deutlich
## angehoben, damit das allgemeine Zittern tatsaechlich auffaellt, ohne die
## schon liegende Leiche gleich wieder durch die Gegend zu werfen.
const TWITCH_IMPULSE := 0.7
const TWITCH_TORQUE := 0.25

## Wie viele Kaesten bei einem einzelnen Zuck gleichzeitig mitzucken.
const TWITCH_PIECES_MIN := 1
const TWITCH_PIECES_MAX := 4

## Wie kraeftig der Nacken den Kopf noch haelt — deutlich schwaecher als ein
## lebendiger Hals, ein letztes bisschen Spannung, kein echter Widerstand
## gegen den Sturz.
const NECK_HOLD_FORCE := 10.0

## Wie kraeftig ein einzelner Strampel-Stoss pro Bein ist. Ober- und
## Unterschenkel bekommen GEGENSAETZLICHEN Dreh (siehe _apply_leg_kick_tick())
## — genau wie beim Knie-Einknicken selbst biegt ein Knie nur in eine
## Richtung, ein wild schlenkerndes Bein braucht darum unterschiedliche
## Drehungen an Ober- und Unterschenkel, sonst dreht sich das ganze Bein nur
## steif als ein Stueck.
##
## KLEIN GEHALTEN UND ZUSAETZLICH GEDECKELT (siehe MAX_TWITCH_ANGULAR_SPEED):
## Ein Drehimpuls mal Masse (wie bei SELF_TOPPLE_TORQUE etc.) geht am
## TRAEGHEITSMOMENT vorbei, nicht nur an der Masse — ein duennes Bein-Stueck
## hat bei aehnlicher Masse ein VIEL kleineres Traegheitsmoment als der
## Brustkasten, fuer den diese Formel anderswo bereits taugt. Gemessen drehte
## ein Wert von 1.1 das Bein mit ueber 100 rad/s — mehrere Umdrehungen pro
## Sekunde, sichtbar kaputt statt wie ein Zucken.
const LEG_KICK_TORQUE := 0.22
const LEG_KICK_LOWER_TORQUE := 0.16

## Wie kraeftig ein einzelner Wegzieh-Stoss der Hand ist. Linearer Impuls
## (siehe apply_central_impulse()) skaliert im Gegensatz zum Drehimpuls oben
## sauber mit der Masse — kein Deckel noetig.
const ARM_RECOIL_IMPULSE := 0.9

## Haerte Obergrenze fuer die Drehgeschwindigkeit nach einem Zuck-Drehstoss —
## ein zusaetzliches Sicherheitsnetz gegen genau das oben beschriebene
## Traegheitsmoment-Problem, falls ein Koerperteil (z. B. nach individueller
## Anpassung der Masse) wieder unerwartet leicht/duenn ausfaellt.
const MAX_TWITCH_ANGULAR_SPEED := 6.0

## Countdown bis das Zucken aufhoert — 0 oder kleiner heisst "kein Zucken".
var _twitch_time_left: float = 0.0

## Countdown bis zum naechsten einzelnen Zuck-Stoss.
var _twitch_timer: float = 0.0

## Ob die Beine gerade strampeln — IMMER an, ausser bei Kopf- oder Brust-/
## Bauchtreffern (siehe Klassenkopf-Kommentar).
var _twitch_legs_kick: bool = false

## Ob zusaetzlich eine Hand versucht, sich von der Wunde wegzuziehen — mit
## Zufallschance, siehe _start_death_twitch().
var _twitch_arm_recoil: bool = false

## Welcher Arm wegzieht, wenn _twitch_arm_recoil an ist — die der Wunde
## naehere Seite, siehe _start_death_twitch().
var _twitch_recoil_arm: HealthSystem.Part = HealthSystem.Part.LEFT_ARM


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
	_death_generation += 1

	for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
		var built: Array[RigidBody3D] = []
		for mesh in figure.meshes_of(part):
			built.append(_build_piece(mesh as MeshInstance3D, part))
		_pieces[part] = built

		for hitbox in figure.hitboxes_of(part):
			(hitbox as CharacterHitbox).collision_layer = 0

	_transfer_blood_marks()
	_schedule_blood_pool(killing_part, hit_point)
	figure.visible = false

	_build_joints()

	if killing_part == HealthSystem.Part.HEAD:
		_apply_head_trauma(hit_point)
	else:
		# Kein Kopfschuss: das Nervensystem ist nicht sofort abgeschaltet,
		# der Koerper zuckt noch eine Weile nach (siehe _process()).
		_start_death_twitch(killing_part, hit_point)

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


## Startet den Nachzuck-Countdown — siehe Klassenkopf-Kommentar "NACHZUCKEN
## OHNE KOPFSCHUSS". _physics_process() macht den Rest, per wiederholtem
## Stoss im _twitch_timer-Takt (siehe _apply_twitch()).
func _start_death_twitch(killing_part: HealthSystem.Part, hit_point: Vector3) -> void:
	_twitch_time_left = TWITCH_DURATION
	_twitch_timer = 0.0
	_twitch_legs_kick = false
	_twitch_arm_recoil = false

	_start_neck_hold()

	# NICHT bei Brust-/Bauchtreffern: _play_wound_collapse() haelt dort schon
	# gezielt eine Hand an der Wunde fest UND laesst die Beine absichtlich
	# STEIF (siehe dortigen Kommentar, "hier laeuft bewusst KEIN
	# _buckle_legs()") — Strampeln oder ein zweiter Wegzieh-Griff wuerden
	# genau diese Choreografie durcheinanderbringen.
	if killing_part == HealthSystem.Part.CHEST or killing_part == HealthSystem.Part.STOMACH:
		return

	# Strampelt IMMER, ausdruecklich gefordert — kein Zufall mehr.
	_twitch_legs_kick = true

	# Zusaetzlich, mit Zufallschance, zieht eine Hand von der Wunde weg.
	if randf() < 0.5:
		_twitch_arm_recoil = true
		var local_hit := global_transform.affine_inverse() * hit_point
		_twitch_recoil_arm = HealthSystem.Part.LEFT_ARM if local_hit.x < 0.0 \
			else HealthSystem.Part.RIGHT_ARM


## Der Nacken haelt den Kopf noch ein Stueck aufrecht — ein Motor mit
## Zielgeschwindigkeit NULL wirkt wie eine Bremse: Er drueckt jeder Drehung
## entgegen, bis zur Kraftgrenze, haelt aber KEIN festes Ziel (kein starrer
## Hals, siehe JointKind.NECK fuer die weiterhin engen Grenzwinkel). Ohne
## eigenen Timer — die schwache Kraft (siehe NECK_HOLD_FORCE) verliert von
## selbst gegen den Sturz, sobald der Koerper genug Schwung aufgenommen hat.
func _start_neck_hold() -> void:
	if _neck_joint == null:
		return
	_neck_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	_neck_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0.0)
	_neck_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, NECK_HOLD_FORCE)


## Ein einzelner Strampel-Stoss: beide Beine bekommen einen Dreh um dieselbe
## Achse wie das Knie-Einknicken (siehe JointKind.KNEE/HIP), mit
## ENTGEGENGESETZTEM Vorzeichen an Ober- und Unterschenkel, damit das Bein
## sich sichtbar knickt statt nur steif als Ganzes zu schwenken. Jeder Tick
## wuerfelt eine neue, unabhaengige Richtung pro Bein — kein gleichmaessiges
## Treten, sondern wirres Zucken.
func _apply_leg_kick_tick() -> void:
	var axis: Vector3 = global_transform.basis.x
	for leg in [HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG]:
		var pieces: Array = _pieces.get(leg, [])
		if pieces.is_empty():
			continue
		var kick_sign := -1.0 if randf() < 0.5 else 1.0
		var upper: RigidBody3D = pieces[0]
		if is_instance_valid(upper):
			upper.apply_torque_impulse(axis * kick_sign * LEG_KICK_TORQUE * upper.mass)
			_clamp_angular_speed(upper)
		if pieces.size() > 1:
			var lower: RigidBody3D = pieces[1]
			if is_instance_valid(lower):
				lower.apply_torque_impulse(axis * -kick_sign * LEG_KICK_LOWER_TORQUE * lower.mass)
				_clamp_angular_speed(lower)


## Sicherheitsnetz gegen zu schnelle Drehung nach einem Zuck-Drehstoss —
## siehe MAX_TWITCH_ANGULAR_SPEED fuer die Begruendung (Traegheitsmoment).
func _clamp_angular_speed(body: RigidBody3D) -> void:
	if body.angular_velocity.length() > MAX_TWITCH_ANGULAR_SPEED:
		body.angular_velocity = body.angular_velocity.normalized() * MAX_TWITCH_ANGULAR_SPEED


## Ein einzelner Wegzieh-Stoss: der ganze Arm auf der Wund-Seite (siehe
## _start_death_twitch()) bekommt einen Stoss vom Koerper weg und leicht nach
## oben — als risse die Figur die Hand reflexartig von der schmerzenden
## Stelle weg, statt sie wie beim bewussten Wundgriff dort festzuhalten.
func _apply_arm_recoil_tick() -> void:
	var pieces: Array = _pieces.get(_twitch_recoil_arm, [])
	if pieces.is_empty():
		return
	var side := -1.0 if _twitch_recoil_arm == HealthSystem.Part.LEFT_ARM else 1.0
	var basis := global_transform.basis
	var away: Vector3 = (basis.x * side + basis.y * 0.4).normalized()
	for body: RigidBody3D in pieces:
		if is_instance_valid(body):
			body.apply_central_impulse(away * ARM_RECOIL_IMPULSE * body.mass)


## Laeuft nur waehrend des Nachzuckens (siehe _twitch_time_left) — sonst tut
## diese Funktion jeden Physikschritt nichts weiter als eine einzelne
## Zahlenpruefung.
##
## _physics_process(), NICHT _process(): Godot ruft _process() einmal pro
## GEZEICHNETEM Bild auf, _physics_process() dagegen GARANTIERT genau einmal
## pro Physikschritt. Mit _process() konnten bei hoher Bildrate (oder im
## Headless-Test ganz ohne Bildratenbremse) MEHRERE Zuck-Stoesse anfallen,
## bevor die Physik ueberhaupt einen einzigen Schritt gerechnet hat — die
## Impulse stapelten sich unbeobachtet, bevor der naechste Physikschritt sie
## verarbeitete. Gemessen kam dadurch trotz gedeckeltem Einzelstoss (siehe
## _clamp_angular_speed()) noch eine Drehung von ueber 40 rad/s durch. Mit
## _physics_process() kann das nicht mehr passieren: hoechstens ein Zuck-Stoss
## pro Physikschritt, und die Deckelung unten faengt selbst den zuverlaessig ab.
func _physics_process(delta: float) -> void:
	if _twitch_time_left <= 0.0:
		return

	_twitch_time_left -= delta
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(TWITCH_INTERVAL_MIN, TWITCH_INTERVAL_MAX)
		_apply_twitch()

	for part in _pieces:
		for body: RigidBody3D in _pieces[part]:
			if is_instance_valid(body):
				_clamp_angular_speed(body)


## Stoesst ein paar zufaellige Kaesten der Leiche kurz an — kein gezielter
## Effekt an einer bestimmten Stelle wie beim Wundgriff, sondern unwillkuer-
## liches, koerperweites Zittern, wie es echte Muskelkraempfe nach dem Tod
## auch nicht auf eine Stelle beschraenken.
func _apply_twitch() -> void:
	var all_pieces: Array[RigidBody3D] = []
	for part in _pieces:
		for body: RigidBody3D in _pieces[part]:
			if is_instance_valid(body):
				all_pieces.append(body)
	if all_pieces.is_empty():
		return

	var count := randi_range(TWITCH_PIECES_MIN, TWITCH_PIECES_MAX)
	for i in range(count):
		var body: RigidBody3D = all_pieces[randi() % all_pieces.size()]
		var direction := Vector3(
			randf_range(-1.0, 1.0), randf_range(-0.3, 1.0), randf_range(-1.0, 1.0)).normalized()
		body.apply_central_impulse(direction * TWITCH_IMPULSE * body.mass)
		var torque_axis := Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		body.apply_torque_impulse(torque_axis * TWITCH_TORQUE * body.mass)
		_clamp_angular_speed(body)

	if _twitch_legs_kick:
		_apply_leg_kick_tick()
	if _twitch_arm_recoil:
		_apply_arm_recoil_tick()


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

	var generation := _death_generation
	get_tree().create_timer(WOUND_TOPPLE_DELAY).timeout.connect(
		func(): _apply_wound_topple_if_current(generation))


## Wirkt nur, wenn seit dem Planen dieses Timers weder zurueckgesetzt noch
## erneut gestorben wurde — siehe _death_generation.
func _apply_wound_topple_if_current(generation: int) -> void:
	if generation != _death_generation:
		return
	_apply_wound_topple()


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
		var visual := body.get_node_or_null("Mesh") as MeshInstance3D
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

	var generation := _death_generation
	get_tree().create_timer(BUCKLE_MOTOR_DURATION).timeout.connect(
		func(): _stop_buckle_motors_if_current(generation))


## Wirkt nur, wenn seit dem Planen dieses Timers weder zurueckgesetzt noch
## erneut gestorben wurde — siehe _death_generation.
func _stop_buckle_motors_if_current(generation: int) -> void:
	if generation != _death_generation:
		return
	_stop_buckle_motors()


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


## Wie weit eine Blutlache nach unten suchen darf, bevor sie aufgibt — z. B.
## eine haengende Figur ohne Boden in erreichbarer Naehe.
const BLOOD_POOL_SEARCH := 3.0

## Wie lange nach dem Tod gewartet wird, bevor die Blutlache erscheint — die
## Figur soll erst richtig LIEGEN, bevor der Strahl nach unten gesucht wird.
## Ohne Wartezeit traefe der Strahl die Bodenstelle unter der Wunde IM MOMENT
## DES TODES (meist noch stehend), nicht dort, wo die Wunde tatsaechlich
## liegt, sobald der Koerper zur Ruhe gekommen ist — genau das wurde
## bemaengelt ("nicht wo er gestorben ist, sondern wo er im Liegen die Wunde
## hat").
const BLOOD_POOL_DELAY := 2.0

## Merkt sich die toedliche Wunde (siehe _find_wound_mark_near()) und plant
## die Blutlache erst nach BLOOD_POOL_DELAY. Die Wunde HAENGT ALS KIND AM
## RAGDOLL-KASTEN (siehe _transfer_blood_marks(), laeuft direkt davor) und
## bewegt sich darum mit dem fallenden/liegenden Koerper mit — global_position
## im Timer-Callback ist also die Stelle, an der die Wunde WIRKLICH liegt,
## nicht die vom Todesmoment eingefrorene.
func _schedule_blood_pool(killing_part: HealthSystem.Part, hit_point: Vector3) -> void:
	var wound := _find_wound_mark_near(killing_part, hit_point)
	if wound == null:
		return

	var generation := _death_generation
	get_tree().create_timer(BLOOD_POOL_DELAY).timeout.connect(
		func(): _spawn_blood_pool_if_current(wound, generation))


## Wirkt nur, wenn seit dem Planen dieses Timers weder zurueckgesetzt noch
## erneut gestorben wurde — siehe _death_generation — und die Wunde noch
## existiert (clear_blood()/reset() koennte sie zwischenzeitlich entfernt
## haben).
func _spawn_blood_pool_if_current(wound: Node3D, generation: int) -> void:
	if generation != _death_generation:
		return
	if not is_instance_valid(wound):
		return
	_spawn_blood_pool(wound.global_position)


## Findet unter den (bereits auf den Ragdoll-Kasten uebertragenen) Wund-
## marken von `part` diejenige, die der toedlichen Einschlagstelle am
## naechsten liegt — falls die Figur schon mehrere Treffer auf demselben
## Koerperteil hatte, ist das zuverlaessig die JUENGSTE (die toedliche), da
## `hit_point` exakt deren Einschlagpunkt ist. Direkt nach _transfer_blood_
## marks() aufgerufen, solange Wunde und hit_point noch an derselben Stelle
## stehen, bevor die Ragdoll-Physik ueberhaupt einen Schritt gemacht hat.
func _find_wound_mark_near(part: HealthSystem.Part, hit_point: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for body: RigidBody3D in _pieces.get(part, []):
		var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null:
			continue
		for mark in mesh.get_children():
			if not (mark is WoundBleed):
				continue
			var distance := (mark as Node3D).global_position.distance_squared_to(hit_point)
			if distance < best_distance:
				best_distance = distance
				best = mark
	return best


## Setzt eine wachsende Blutlache auf den Boden unter der aktuellen Lage der
## Wunde (siehe BloodPool) — per Strahl nach unten gesucht, damit sie wirklich
## darunter liegt, nicht pauschal unter der Figurenmitte.
func _spawn_blood_pool(wound_point: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var query := PhysicsRayQueryParameters3D.create(
		wound_point, wound_point + Vector3.DOWN * BLOOD_POOL_SEARCH)
	# Nur feste Welt (Boden), siehe hit_layer-Konvention in BlockyCharacter.
	query.collision_mask = 1
	query.collide_with_areas = false

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	var scene := get_tree().current_scene
	if scene == null:
		return

	_blood_pool = BloodPool.spawn(scene, hit.position, hit.get("normal", Vector3.UP))


## Uebertraegt alle Blut-/Wundmarken (WoundHole, WoundBleed) von der lebenden
## Figur auf die gerade gebauten Ragdoll-Kaesten — OHNE DAS verschwindet
## jede Wunde einfach mit der gleich unsichtbar geschalteten Originalfigur
## (siehe figure.visible = false an der Aufrufstelle), statt am toten Koerper
## sichtbar zu bleiben und mit ihm zu fallen/liegen.
##
## Die lokale Position/Drehung eines Flecks bleibt beim Umhaengen
## UNVERAENDERT: Im Moment des Uebertrags stehen Quell- (figure) und
## Zielmesh (Ragdoll-Kasten) an EXAKT derselben Weltstelle — _build_piece()
## hat den Kasten gerade erst aus genau diesem Mesh gebaut (`body.
## global_transform = mesh.global_transform`, siehe dort). Derselbe lokale
## Wert unter dem neuen Elternknoten landet also automatisch wieder an der
## richtigen Stelle, keine Umrechnung noetig.
##
## EIN NOCH TROPFENDER WoundBleed LAEUFT EINFACH WEITER: Er ist derselbe
## Knoten, nur mit neuem Elternteil — sein Wachstums-/Tropf-Zustand
## (_length, _drips_left, _drip_timer) bleibt erhalten. Die Figur blutet
## also auch tot noch weiter, bis die Wunde von sich aus aufhoert.
func _transfer_blood_marks() -> void:
	for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
		var source_meshes := figure.meshes_of(part)
		var pieces: Array = _pieces.get(part, [])
		for i in range(source_meshes.size()):
			if i >= pieces.size():
				continue
			var source_mesh := source_meshes[i] as MeshInstance3D
			var target_mesh := (pieces[i] as RigidBody3D).get_node_or_null("Mesh") as MeshInstance3D
			if source_mesh == null or target_mesh == null:
				continue

			for mark in source_mesh.get_children().duplicate():
				if not (mark is WoundHole or mark is WoundBleed):
					continue
				var local_position: Vector3 = (mark as Node3D).position
				var local_rotation: Vector3 = (mark as Node3D).rotation
				source_mesh.remove_child(mark)
				target_mesh.add_child(mark)
				(mark as Node3D).position = local_position
				(mark as Node3D).rotation = local_rotation


## Baut einen einzelnen Ragdoll-Kasten aus einem bestehenden Mesh der Figur —
## Groesse, Lage und Farbe stehen dort schon, nichts muss neu ausgerechnet
## werden.
func _build_piece(mesh: MeshInstance3D, part: HealthSystem.Part) -> RigidBody3D:
	var box_mesh := mesh.mesh as BoxMesh
	var size := box_mesh.size if box_mesh != null else Vector3.ONE * 0.2

	# RagdollHitbox statt eines nackten RigidBody3D: nur so kann ein Schuss
	# auf die bereits tote Figur noch etwas bewirken (siehe dortigen
	# Klassenkommentar) — ein Treffer nach dem Tod soll nicht wirkungslos
	# abprallen wie gegen eine Wand.
	var body := RagdollHitbox.new()
	body.rig = self
	body.part = part
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
	# Name statt Kindindex, damit _highlight_reaching_arm() ihn sicher findet —
	# auch wenn hier je einmal die Reihenfolge von Mesh/Kollisionsform vertauscht wird.
	visual.name = "Mesh"
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


## ---------------------------------------------------------------------------
## KOPFTRAUMA BEI KOPFSCHUSS
##
## Jeder toedliche KOPFtreffer (kein Zufall mehr, siehe Git-Historie fuer die
## fruehere Kiefer-Variante — durch diese ersetzt) reisst auf der
## AUSTRITTSSEITE ein Stueck des Schaedels weg: dort spritzt viel Blut heraus,
## der Schaedel verformt sich sichtbar, und am Boden/an anderen Koerperteilen
## in der Naehe bleiben Blutspritzer genau dort zurueck, wo das Blut
## tatsaechlich hinfliegt.
##
## EINTRITT/AUSTRITT NUR ALS LINKS/RECHTS-NAEHERUNG: Genau wie _play_wound_
## collapse() bei einem Brust-/Bauchtreffer nur das Vorzeichen der lokalen
## X-Koordinate des Trefferpunkts auswertet, um links/rechts zu unterscheiden
## (kein echter Durchschussweg, keine Ballistik durch den Schaedel) — die
## Austrittsseite ist einfach die dem Eintritt gegenueberliegende Kopfhaelfte.
##
## KEIN EIGENES MODELL: Der Kopf ist wie der Rest der Figur nur eine Box
## (siehe BlockyCharacter.HORIZONTAL/VERTICAL) — das wegfliegende Stueck ist
## darum ebenfalls nur ein Kasten, im selben Stil wie die uebrigen Ragdoll-
## Teile gebaut (siehe _build_debris_piece(), die eigene Variante von
## _build_piece() ohne Vorlage-Mesh), keine neue Geometrie oder Textur.
## ---------------------------------------------------------------------------

## Wie viel von der vollen Kopfhoehe/-tiefe das Stueck einnimmt — fast
## alles, damit es wie eine wirkliche Kopfhaelfte aussieht, siehe
## _burst_skull_side() fuer die genaue Breite (die entspricht exakt der
## Luecke, die _deform_head() im Kopf hinterlaesst).
const SKULL_CHUNK_HEIGHT_FRACTION := 0.92
const SKULL_CHUNK_DEPTH_FRACTION := 0.92

## Wie weit das Stueck an seinem oberen Rand nach unten aufklappen darf,
## bevor die Gelenkgrenze es haelt — siehe _burst_skull_side(), es reisst
## nicht ganz ab, sondern haengt an dieser Kante weiter fest.
const SKULL_HANG_LIMIT_DEG := 80.0

## Wie viel groesser die Wundmarke an der Bruchstelle ist als ein normaler
## Einschuss (WoundHole.SIZE_METRES) — eine aufgerissene Schaedelseite ist
## kein kleines Loch, sondern fast die halbe Kopfbreite (siehe Kopfmasse in
## BlockyCharacter.HORIZONTAL).
const SKULL_WOUND_SCALE := 3.2

## Wie stark der Schaedel auf der Austrittsseite sichtbar einsackt, als
## Anteil der Kopfbreite — siehe _deform_head().
const SKULL_CAVE_IN_FRACTION := 0.3

## Wie viele Spritzer der Austrittspunkt zusaetzlich zum Blutstreifen wirft —
## deutlich mehr als ein gewoehnlicher Trefferspritzer (siehe BlockyCharacter.
## SPLATTER_COUNT = 10), weil "viel Blut" ausdruecklich verlangt war.
const HEAD_SPRAY_COUNT := 18
const HEAD_SPRAY_DISTANCE := 1.6


## Bestimmt Ein-/Austrittsseite aus dem Trefferpunkt und loest das komplette
## Kopftrauma aus: Schaedelstueck wegreissen, Kopf verformen, Blut spritzen
## und laufen lassen.
func _apply_head_trauma(hit_point: Vector3) -> void:
	var heads: Array = _pieces.get(HealthSystem.Part.HEAD, [])
	if heads.is_empty():
		return
	var head_body: RigidBody3D = heads[0]
	var head_size := figure.size_of(HealthSystem.Part.HEAD)

	# Dieselbe Vorzeichen-Naeherung wie in _play_wound_collapse(): negative
	# lokale X-Koordinate ist die linke Kopfhaelfte.
	var local_hit := head_body.global_transform.affine_inverse() * hit_point
	var entry_side := -1.0 if local_hit.x < 0.0 else 1.0
	var exit_side := -entry_side

	_burst_skull_side(head_body, head_size, exit_side)


## Klappt ein Stueck der Austrittsseite auf: ein Kasten, der an seiner
## Oberkante noch am Kopf HAENGT (siehe Gelenk unten — es reisst NICHT
## komplett ab und fliegt nicht weg), an der Bruchstelle bleibt eine grosse
## Wundmarke zurueck (dieselbe Textur wie ein normaler Einschuss, siehe
## WoundHole — nur deutlich groesser, keine eigene Textur noetig), der
## Schaedel verformt sich sichtbar (siehe _deform_head()), und aus der
## Bruchstelle spritzt und laeuft Blut (siehe _spawn_head_exit_spray()/
## WoundBleed).
func _burst_skull_side(head_body: RigidBody3D, head_size: Vector3, exit_side: float) -> void:
	# Das Stueck ist die GENAUE Ergaenzung zu der Luecke, die _deform_head()
	# im Kopf hinterlaesst: exakt so breit wie dort abgezogen wird (dieselbe
	# SKULL_CAVE_IN_FRACTION), fast so hoch und tief wie der ganze Kopf. Vorher
	# war das Stueck unabhaengig davon nur ein kleiner Wuerfel (40% in jede
	# Richtung) — sah neben dem echten Kopfmass winzig und unpassend aus.
	var shrink := head_size.x * SKULL_CAVE_IN_FRACTION
	var chunk_size := Vector3(
		shrink,
		head_size.y * SKULL_CHUNK_HEIGHT_FRACTION,
		head_size.z * SKULL_CHUNK_DEPTH_FRACTION)

	# Genau an der Stelle, wo nach der Verformung die Luecke im Kopf klafft —
	# dieselbe Rechnung wie in _deform_head(), nur von der Aussenkante her
	# statt vom Mittelpunkt aus gedacht.
	var chunk_local := Vector3(
		exit_side * (head_size.x * 0.5 - shrink * 0.5), 0.0, 0.0)
	var chunk_transform := head_body.global_transform * Transform3D(Basis(), chunk_local)
	var chunk := _build_debris_piece(
		chunk_size, _piece_colour(head_body).darkened(0.35), chunk_transform)

	head_body.add_collision_exception_with(chunk)
	chunk.add_collision_exception_with(head_body)

	# HAENGT NOCH DRAN: ein Gelenk OHNE Motor an der UNTERKANTE des Stuecks,
	# genau wie ein Knie/eine Huefte ohne Motor unter der Schwerkraft bis zu
	# ihrer Grenze durchsackt (siehe JointKind.KNEE) — kein Stoss, der es
	# wegschleudert. Die Schwerkraft allein klappt es auf und haelt es dort,
	# sobald die Grenze erreicht ist.
	#
	# UNTEN, NICHT OBEN: Ein Gelenk an der Oberkante liess das Stueck beim
	# Aufklappen in einem weiten Bogen VOM Kopf weg nach vorn schwingen — bei
	# fast voller Kopfhoehe/-tiefe (siehe SKULL_CHUNK_HEIGHT_FRACTION/DEPTH_
	# FRACTION) ein grosser Hebelarm, der das Stueck sichtbar abgeloest neben
	# der Figur schweben liess. An der Unterkante haengend bleibt der
	# angeschlagene Rand naeher am Kopf bzw. Hals, der Bogen zeigt nach unten
	# statt seitlich weg.
	var anchor := head_body.global_transform * (
		chunk_local + Vector3(0.0, -chunk_size.y * 0.5, 0.0))
	var joint := Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_position = anchor
	joint.node_a = joint.get_path_to(head_body)
	joint.node_b = joint.get_path_to(chunk)
	for axis in AXES:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	_limit_angular(joint, "x", 0.0, SKULL_HANG_LIMIT_DEG)
	_limit_angular(joint, "y", 0.0, 0.0)
	_limit_angular(joint, "z", 0.0, 0.0)
	_debris_joints.append(joint)

	var basis := head_body.global_transform.basis
	var outward: Vector3 = (basis.x * exit_side + basis.y * 0.5).normalized()

	var head_mesh := head_body.get_node_or_null("Mesh") as MeshInstance3D
	if head_mesh == null:
		return

	# GENAU AUF DER OBERFLAECHE, auf halber Kopfhoehe (derselben Hoehe wie die
	# Mitte des Stuecks jetzt) — nicht am weiter innen liegenden Mittelpunkt
	# des Stuecks selbst, sonst projiziert das Decal zu tief und erscheint gar
	# nicht sichtbar auf der Aussenseite.
	var wound_local := Vector3(exit_side * head_size.x * 0.5, 0.0, 0.0)
	var wound_point := head_body.global_transform * wound_local
	var normal: Vector3 = (basis.x * exit_side).normalized()
	var mark := WoundHole.spawn(head_mesh, wound_point, normal)
	if mark != null:
		var size := WoundHole.SIZE_METRES * SKULL_WOUND_SCALE
		mark.size = Vector3(size, mark.size.y, size)

	_deform_head(head_mesh, head_size, exit_side)
	_spawn_head_bleed(head_mesh, head_size, wound_local)
	_spawn_head_exit_spray(head_body, wound_point, outward)


## Verformt den Kopf sichtbar: Die Austrittsseite sackt nach innen ein, als
## waere dort wirklich ein Stueck herausgerissen — die Eintrittsseite bleibt
## an ihrer Stelle stehen. NUR DIE ANZEIGE wird verschoben/verkleinert, die
## Kollisionsbox (siehe _build_piece()) bleibt unangetastet, damit die
## Ragdoll-Physik (Gelenkabstaende, Kollisionsform) unveraendert stabil
## bleibt — dieselbe Trennung wie bei jedem Decal hier: Optik und Physik sind
## zwei verschiedene Dinge.
##
## DIE BOX WIRD VOR DEM AENDERN DUPLIZIERT: Ohne das ist `head_mesh.mesh`
## dieselbe BoxMesh-Ressource wie am (nur unsichtbaren, nicht geloeschten)
## Original-Koerperteil der lebenden Figur (siehe _build_piece(), "Dieselbe
## Box-Ressource"). Eine Groessenaenderung hier wuerde sonst auch den
## Lebendkoerper dauerhaft verformen, sobald reset() ihn wieder sichtbar macht.
func _deform_head(head_mesh: MeshInstance3D, head_size: Vector3, exit_side: float) -> void:
	var original_box := head_mesh.mesh as BoxMesh
	if original_box == null:
		return
	var box := original_box.duplicate() as BoxMesh
	head_mesh.mesh = box

	var shrink := head_size.x * SKULL_CAVE_IN_FRACTION
	box.size.x = maxf(0.02, head_size.x - shrink)
	# Die Eintrittsseite soll an ihrer Stelle bleiben, nur die Austrittsseite
	# sackt ein — der Mittelpunkt der jetzt schmaleren Box verschiebt sich
	# darum um die halbe Differenz zur Eintrittsseite hin.
	head_mesh.position.x = -exit_side * shrink * 0.5
	# Leichte Stauchung insgesamt, als haette der Einschlag den ganzen
	# Schaedel gequetscht, nicht nur die eine Seite.
	head_mesh.scale.y = 0.88


## Setzt einen schweren Blutstreifen an die Bruchstelle — laeuft wie eine
## normale Wunde (siehe WoundBleed) den Kopf herunter und tropft, sobald der
## untere Rand erreicht ist. "Viel Blut" heisst hier: dieselbe Mechanik wie
## ein Koerpertreffer, aber IMMER heavy=true statt von der Munition abhaengig.
func _spawn_head_bleed(head_mesh: MeshInstance3D, head_size: Vector3, wound_local: Vector3) -> void:
	var bleed := WoundBleed.new()
	bleed.heavy = true
	bleed.target_length = maxf(0.03, wound_local.y + head_size.y * 0.5)
	head_mesh.add_child(bleed)
	bleed.position = wound_local


## Wirft viele kleine Spritzer von der Bruchstelle weg, bevorzugt in
## `direction` (die Austrittsrichtung) und nach unten — landen sie auf einer
## festen Flaeche (Boden, Wand, oder ein anderes Ragdoll-Stueck derselben
## Leiche), bleibt dort GENAU AN DIESER STELLE ein Fleck zurueck (siehe
## BlockyCharacter._spawn_splatter() fuer dieselbe Grundidee bei einem
## normalen Treffer waehrend die Figur noch lebt).
func _spawn_head_exit_spray(head_body: RigidBody3D, origin: Vector3, direction: Vector3) -> void:
	_spawn_blood_spray(head_body, origin, direction, HEAD_SPRAY_COUNT, HEAD_SPRAY_DISTANCE)


## Wirft viele kleine Spritzer von `origin` weg, bevorzugt in `direction` und
## nach unten — landen sie auf einer festen Flaeche (Boden, Wand, oder ein
## anderes Ragdoll-Stueck derselben Leiche), bleibt dort GENAU AN DIESER
## STELLE ein Fleck zurueck (dieselbe Grundidee wie BlockyCharacter._spawn_
## splatter() bei einem normalen Treffer waehrend die Figur noch lebt).
## `exclude_body` wird von der Strahlpruefung ausgenommen, sonst faengt sich
## der erste Strahl schon im eigenen Kasten, an dem `origin` liegt.
func _spawn_blood_spray(exclude_body: RigidBody3D, origin: Vector3, direction: Vector3,
		count: int, distance: float) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var away := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	var exclude: Array = [exclude_body.get_rid()] if exclude_body != null else []

	for i in range(count):
		var random_dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, -0.1),
			randf_range(-1.0, 1.0))
		var spread := (random_dir + away * 1.2).normalized()
		var to := origin + spread * randf_range(0.2, distance)

		var query := PhysicsRayQueryParameters3D.create(origin, to)
		# Welt UND die eigenen Ragdoll-Kaesten liegen beide auf Ebene 1 (siehe
		# _build_piece()) — ein Spritzer kann also sowohl auf dem Boden als
		# auch auf einem anderen Koerperteil derselben Leiche landen.
		query.collision_mask = 1
		query.collide_with_areas = false
		query.exclude = exclude

		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue

		var collider: Object = hit.get("collider")
		var landing_parent: Node = get_tree().current_scene
		if collider is RigidBody3D and (collider as RigidBody3D).get_parent() == self:
			var mesh := (collider as RigidBody3D).get_node_or_null("Mesh")
			if mesh != null:
				landing_parent = mesh
		if landing_parent == null:
			continue

		var splatter := WoundHole.spawn(landing_parent, hit.position, hit.get("normal", Vector3.UP))
		if splatter != null:
			splatter.size *= 0.8


## ---------------------------------------------------------------------------
## TREFFER NACH DEM TOD
##
## Ein Schuss auf die bereits tote Figur soll nicht wirkungslos wie gegen eine
## Wand abprallen (siehe RagdollHitbox fuer die technische Begruendung),
## sondern weiterhin eine Wunde und Blut hinterlassen. KEINE Ruestung mehr:
## eine Leiche traegt ihre Platte nicht mehr aktiv, jeder Treffer erreicht
## direkt das Fleisch (siehe Ballistics.resolve_hit() mit plate=null).
## ---------------------------------------------------------------------------

## Deutlich weniger Spritzer als beim dramatischen Kopftrauma (siehe
## HEAD_SPRAY_COUNT) — ein gewoehnlicher Nachschuss auf die Leiche, kein
## Platzen des Schaedels.
const CORPSE_SPRAY_COUNT := 6
const CORPSE_SPRAY_DISTANCE := 0.5

func take_hit_on_corpse(body: RagdollHitbox, ammo: AmmoData, distance: float,
		point: Vector3, direction: Vector3) -> Ballistics.HitResult:
	var result := Ballistics.resolve_hit(ammo, distance, null, 0.0)
	_spawn_corpse_wound(body, point, direction, result.caused_heavy_bleeding)
	return result


## Setzt Wunde, Blutstreifen und ein paar Spritzer direkt an den getroffenen
## Ragdoll-Kasten — dieselbe Grundidee wie BlockyCharacter._spawn_wound(),
## nur ohne dessen Mesh-Auswahl-Schritt: Ein Ragdoll-Kasten hat immer genau
## EIN Mesh, keine zwei Segmente wie ein lebender Arm/Bein.
func _spawn_corpse_wound(body: RagdollHitbox, point: Vector3, direction: Vector3, heavy: bool) -> void:
	var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return

	var local_point := mesh.global_transform.affine_inverse() * point
	var normal := -direction if direction.length_squared() > 0.0001 else Vector3.FORWARD
	WoundHole.spawn(mesh, point, normal)

	var bleed := WoundBleed.new()
	bleed.heavy = heavy
	var box := mesh.mesh as BoxMesh
	bleed.target_length = maxf(0.03, local_point.y + box.size.y * 0.5) if box != null else 0.16
	mesh.add_child(bleed)
	bleed.position = local_point

	_spawn_blood_spray(body, point, -direction, CORPSE_SPRAY_COUNT, CORPSE_SPRAY_DISTANCE)


## Liest die Kastenfarbe eines bereits gebauten Ragdoll-Stuecks von seinem
## "Mesh"-Kind ab — fuer Truemmerstuecke, die farblich zum Koerperteil
## passen sollen, von dem sie abgerissen wurden.
func _piece_colour(body: RigidBody3D) -> Color:
	var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	var material := mesh.material_override as StandardMaterial3D if mesh != null else null
	return material.albedo_color if material != null else Color.WHITE


## Baut ein zusaetzliches, freies Kastenstueck OHNE Vorlage-Mesh — fuer
## Kopftrauma-Truemmer (Kiefer, Schaedelstueck), die es an der lebenden Figur
## gar nicht gibt. Sonst derselbe Aufbau wie _build_piece() (Daempfung,
## Reibung, kein Abprallen, Kollisionsebene — siehe dortige Begruendung),
## nur mit expliziter Groesse/Farbe/Lage statt von einem Mesh abgeleitet.
## HAENGT SICH SELBST IN _debris EIN, damit reset() es wiederfindet — die
## Truemmer gehoeren zu KEINEM HealthSystem.Part und werden darum NICHT
## schon von der _pieces-Bereinigung erfasst.
func _build_debris_piece(size: Vector3, colour: Color, world_transform: Transform3D) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = maxf(0.15, size.x * size.y * size.z * PIECE_DENSITY)
	body.angular_damp = 0.4
	body.linear_damp = 0.18
	var material := PhysicsMaterial.new()
	material.friction = 0.3
	material.bounce = 0.0
	material.absorbent = true
	body.physics_material_override = material
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	body.global_transform = world_transform

	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	visual.mesh = box_mesh
	var visual_material := StandardMaterial3D.new()
	visual_material.albedo_color = colour
	visual.material_override = visual_material
	body.add_child(visual)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	_debris.append(body)
	return body


## Zehn Gelenke an genau den Punkten, die die Figur schon kennt.
func _build_joints() -> void:
	_neck_joint = _joint(HealthSystem.Part.HEAD, 0, HealthSystem.Part.CHEST, 0,
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
	_death_generation += 1
	_twitch_time_left = 0.0
	_twitch_legs_kick = false
	_twitch_arm_recoil = false

	if is_instance_valid(_blood_pool):
		_blood_pool.queue_free()
	_blood_pool = null

	for joint in _joints:
		if is_instance_valid(joint):
			joint.queue_free()
	_joints.clear()

	for joint in _debris_joints:
		if is_instance_valid(joint):
			joint.queue_free()
	_debris_joints.clear()

	_leg_hip_joints.clear()
	_leg_knee_joints.clear()
	_arm_shoulder_joints.clear()
	_arm_elbow_joints.clear()
	_waist_joint = null
	_neck_joint = null

	for part in _pieces:
		for body in _pieces[part]:
			if is_instance_valid(body):
				(body as RigidBody3D).queue_free()
	_pieces.clear()

	for body in _debris:
		if is_instance_valid(body):
			body.queue_free()
	_debris.clear()

	if figure != null:
		for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
			for hitbox in figure.hitboxes_of(part):
				(hitbox as CharacterHitbox).collision_layer = figure.hit_layer
		figure.visible = true
		figure.reset()

	global_transform = _spawn_transform
	_ragdolling = false
