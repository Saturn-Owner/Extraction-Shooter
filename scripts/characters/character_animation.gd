## Bewegung der Figur: Gehen, Laufen, Stehen.
##
## ---------------------------------------------------------------------------
## GERECHNET, NICHT ABGESPIELT
##
## Kein AnimationPlayer und keine aufgezeichneten Kurven, sondern eine Formel
## pro Gelenk. Das ist dieselbe Entscheidung wie bei `WeaponView`, wo
## Laufwackeln und Nachschwingen ebenfalls gerechnet werden.
##
## Der Grund ist nicht Bequemlichkeit, sondern dass die Bewegung sich der
## GESCHWINDIGKEIT anpassen muss. Eine aufgezeichnete Gehschleife läuft immer
## gleich schnell; wer langsamer geht, rutscht dann mit den Füssen über den
## Boden, weil Schrittlänge und zurückgelegte Strecke nicht mehr
## zusammenpassen. Hier ergibt sich die Schrittfrequenz aus dem Tempo, und das
## Problem entsteht gar nicht erst.
##
## ---------------------------------------------------------------------------
## WARUM ES OHNE SKELETT GEHT
##
## Jedes Körperteil hängt an einem Gelenkknoten, der OBEN am Teil sitzt — der
## Arm an der Schulter, das Bein an der Hüfte. Ein Ausschlag um die X-Achse
## schwingt das Glied damit wie ein Pendel, und mehr braucht ein eckiger
## Charakter nicht. Ein Skelett mit weicher Verformung würde die Kanten
## rundziehen und genau das kaputtmachen, was an der Figur gefällt.
##
## Die Trefferzonen hängen unter denselben Gelenken und schwingen mit. Ein
## vorgestrecktes Bein ist damit auch dort, wo es aussieht — ohne dass hier
## eine Zeile dafür steht.
class_name CharacterAnimation
extends Node

## Die Figur, deren Gelenke bewegt werden.
var character: BlockyCharacter

## Tempo in Metern je Sekunde. Setzt, wer die Figur bewegt.
var speed: float = 0.0

## Ab diesem Tempo gilt die volle Ausschlagsweite. Entspricht etwa dem
## Sprint des Spielers.
const FULL_SWING_SPEED := 4.5

## Wie weit die Figur bei einem vollen Doppelschritt kommt.
##
## DARAN HÄNGT, OB DIE FÜSSE RUTSCHEN. Zu kurz gewählt, trippelt die Figur
## hektisch; zu lang, gleitet sie.
##
## DER WERT IST NICHT FREI, sondern folgt aus dem Ausschlag: Ein Bein von
## 0,75 m Länge, das um SWING_LEG nach vorn und ebenso weit nach hinten
## schwingt, überstreicht je Schritt 2 × 0,75 × sin(SWING_LEG), und ein
## Doppelschritt sind zwei davon:
##
##     STRIDE_LENGTH ≈ 4 × 0,75 × sin(SWING_LEG)
##
## Wer SWING_LEG ändert, muss diesen Wert mitziehen — sonst rutschen die
## Füsse, und das sieht man sofort, ohne sagen zu können, was stört.
const STRIDE_LENGTH := 1.7

## Grösster Ausschlag in Grad.
##
## Bei 26 Grad wirkten die Schritte zu klein — die Figur lief, aber
## trippelig. 34 Grad ergeben einen raumgreifenden Schritt, ohne dass es nach
## Stechschritt aussieht.
const SWING_LEG := 34.0
const SWING_ARM := 22.0

## Wie weit sich das Knie beim Vorschwingen anwinkelt.
##
## ---------------------------------------------------------------------------
## EIN KNIE BEUGT SICH NUR IN EINE RICHTUNG
##
## Deshalb ist das hier keine Schwingung um null, sondern eine Beugung, die
## zwischen null und dem Höchstwert pendelt. Ein Knie, das nach vorn
## durchknickt, sieht nicht nach Fehler aus, sondern nach gebrochenem Bein —
## und genau das würde ein einfaches sin() erzeugen.
##
## Gebeugt wird in der SCHWUNGPHASE, also wenn das Bein von hinten nach vorn
## kommt und der Fuss vom Boden ab ist. In der Standphase bleibt es fast
## gerade, sonst würde die Figur einsinken.
const BEND_KNEE := 42.0

## Grundbeugung der Ellenbogen, auch im Stand.
##
## Ein Mensch lässt die Arme nicht kerzengerade hängen. Ohne diesen Winkel
## wirkt die Figur wie eine Puppe, die man an den Schultern aufgehängt hat.
const BEND_ELBOW_REST := 12.0

## Wieviel Beugung beim Laufen dazukommt. Wer rennt, winkelt die Arme an.
const BEND_ELBOW_MOVING := 38.0

## Wie hoch der Oberkörper beim Gehen wippt, in Metern.
##
## NUR DER OBERKÖRPER. Die Beine bleiben, wo sie sind — hübe man die ganze
## Figur, hingen die Füsse in der Luft.
const BOB_HEIGHT := 0.022

## Atmen im Stand. Sehr klein, aber ohne das wirkt die Figur wie eingefroren.
const BREATH_HEIGHT := 0.006
const BREATH_SPEED := 1.6

## Wie schnell die Glieder in die Ruhelage zurückfinden, wenn jemand stehen
## bleibt. Ohne das friert die Figur mitten im Schritt ein.
const SETTLE_SPEED := 6.0

## Welche Teile schwingen, und mit welchem Vorzeichen.
##
## Arme gegen die Beine derselben Seite: Wer rechts vortritt, schwingt den
## linken Arm vor. So geht ein Mensch, und andersherum sieht es sofort falsch
## aus, ohne dass man sagen könnte warum.
const SWINGING := {
	HealthSystem.Part.LEFT_LEG: {amount = SWING_LEG, sign = 1.0},
	HealthSystem.Part.RIGHT_LEG: {amount = SWING_LEG, sign = -1.0},
	HealthSystem.Part.LEFT_ARM: {amount = SWING_ARM, sign = -1.0},
	HealthSystem.Part.RIGHT_ARM: {amount = SWING_ARM, sign = 1.0},
}

## Was mitwippt, statt zu schwingen.
const UPPER_BODY := [
	HealthSystem.Part.HEAD,
	HealthSystem.Part.CHEST,
	HealthSystem.Part.STOMACH,
	HealthSystem.Part.LEFT_ARM,
	HealthSystem.Part.RIGHT_ARM,
]

## Schrittphase in Radiant.
var _phase: float = 0.0

## Wie stark gerade geschwungen wird, 0 bis 1. Läuft dem Tempo weich nach.
var _intensity: float = 0.0

var _time: float = 0.0

## Ruhelage der Gelenke, einmal beim Anhängen gemerkt.
var _rest: Dictionary = {}


## Hängt sich an eine Figur. Muss gerufen werden, nachdem deren build() lief.
func attach(target: BlockyCharacter) -> void:
	character = target
	_rest.clear()
	if character == null:
		return
	for part: HealthSystem.Part in BlockyCharacter.VERTICAL:
		var joint := character.joint_of(part)
		if joint != null:
			_rest[part] = joint.position


func _process(delta: float) -> void:
	if character == null or _rest.is_empty():
		return

	_time += delta

	# Tote Figuren bewegen sich nicht. Ohne das atmet eine Leiche weiter,
	# und das ist der Sorte Fehler, die man beim Spielen sofort sieht.
	var alive := character.health == null or not character.health.is_dead
	var target_intensity := 0.0
	if alive:
		# WURZEL STATT LINEAR, und das ist kein Feinschliff.
		#
		# Linear gerechnet bekam ein normaler Gang (1,6 m/s) bei einem
		# Sprinttempo von 4,5 nur ein Drittel des Ausschlags — gemessene 7
		# Grad. Die Figur schlurfte damit über den Platz, als hätte sie die
		# Beine zusammengebunden.
		#
		# So geht ein Mensch auch nicht: Vom Stand zum Gehen ändert sich die
		# Schrittweite stark, vom Gehen zum Rennen kaum noch — dort wird
		# vor allem die Frequenz höher, und die kommt ohnehin aus dem Tempo.
		target_intensity = sqrt(clampf(speed / FULL_SWING_SPEED, 0.0, 1.0))
	_intensity = move_toward(_intensity, target_intensity, SETTLE_SPEED * delta)

	# Die Schrittfrequenz ergibt sich aus dem Tempo, nicht aus einer festen
	# Zahl — siehe Klassenkopf.
	if speed > 0.01 and alive:
		_phase += TAU * (speed / STRIDE_LENGTH) * delta
		_phase = fposmod(_phase, TAU)
	elif _intensity <= 0.001:
		# Erst wenn wirklich nichts mehr schwingt, die Phase zurücksetzen.
		# Vorher wäre es ein Sprung mitten in der Bewegung.
		_phase = 0.0

	var swing := sin(_phase)

	for part: HealthSystem.Part in SWINGING:
		var joint := character.joint_of(part)
		if joint == null:
			continue
		var entry: Dictionary = SWINGING[part]
		# Absolut setzen, nie addieren: Bei _intensity = 0 kommt exakt null
		# heraus und der Kanal räumt sich von selbst auf.
		joint.rotation_degrees.x = swing * entry.amount * entry.sign * _intensity

		var hinge := character.hinge_of(part)
		if hinge == null:
			continue
		hinge.rotation_degrees.x = _hinge_angle(part, entry.sign)

	# Das Wippen läuft mit der doppelten Schrittfrequenz — bei jedem Auftritt
	# einmal, nicht bei jedem Doppelschritt.
	var bob := absf(sin(_phase)) * BOB_HEIGHT * _intensity
	var breath := 0.0
	if alive:
		breath = sin(_time * BREATH_SPEED) * BREATH_HEIGHT * (1.0 - _intensity)

	for part: HealthSystem.Part in UPPER_BODY:
		var joint := character.joint_of(part)
		if joint == null:
			continue
		joint.position = _rest[part] + Vector3(0.0, bob + breath, 0.0)


## Winkel eines Zwischengelenks — Knie oder Ellenbogen.
##
## Beide beugen sich nur in EINE Richtung, deshalb kommt hier nie ein
## Vorzeichenwechsel heraus. Ein Knie zeigt nach hinten (negativ), ein
## Ellenbogen nach vorn (positiv) — die Figur schaut nach -Z, ein positiver
## Ausschlag führt das untere Ende also nach vorn.
func _hinge_angle(part: HealthSystem.Part, swing_sign: float) -> float:
	var is_leg := part == HealthSystem.Part.LEFT_LEG or part == HealthSystem.Part.RIGHT_LEG

	if is_leg:
		# Gebeugt wird, solange das Bein nach VORN unterwegs ist. Das ist
		# genau dann, wenn die Ableitung des Ausschlags positiv ist — und die
		# Ableitung von sin ist cos. Ohne diese Kopplung an die Phase beugte
		# sich das Knie auch im Stand auf dem Standbein, und die Figur würde
		# bei jedem Schritt einknicken.
		var lifting := maxf(0.0, cos(_phase) * swing_sign)
		return -BEND_KNEE * lifting * _intensity

	# Der Ellenbogen hält einen Grundwinkel und winkelt beim Laufen weiter an.
	return BEND_ELBOW_REST + BEND_ELBOW_MOVING * _intensity


## Stellt die Ruhelage wieder her.
func reset() -> void:
	_phase = 0.0
	_intensity = 0.0
	speed = 0.0
	if character == null:
		return
	for part: HealthSystem.Part in _rest:
		var joint := character.joint_of(part)
		if joint == null:
			continue
		joint.position = _rest[part]
		joint.rotation_degrees.x = 0.0

		var hinge := character.hinge_of(part)
		if hinge != null:
			# Nicht auf null: Der Ellenbogen hat auch im Stand seinen
			# Grundwinkel, sonst hängen die Arme kerzengerade herunter.
			hinge.rotation_degrees.x = _hinge_angle(part, 1.0)
