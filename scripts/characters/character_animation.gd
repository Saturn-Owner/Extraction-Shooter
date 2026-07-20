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

## Ob die Figur eine Waffe im Anschlag hat.
##
## Dann schwingen die Arme NICHT mit. Wer ein Gewehr hält, hat beide Hände
## daran — ein Arm, der dabei frei pendelt, sieht sofort falsch aus, und die
## Waffe, die an der Hand hängt, würde mitpendeln.
var holding_weapon: bool = false

## Wohin die Hände greifen sollen. Kommen von der Waffe.
##
## Sind beide gesetzt, wird die Armhaltung GERECHNET statt aus festen Winkeln
## genommen — siehe `_solve_arm()`. Fehlt einer, greift die feste Haltung
## darunter als Rückfallebene.
var grip_target: Node3D
var support_target: Node3D

## Der Magazinschacht der Waffe. Dorthin greift die Stützhand beim Nachladen.
var magwell_target: Node3D

## Der Ladehebel. Zum Schluss des Nachladens zieht die Hand ihn durch.
var charge_target: Node3D

## Die Magazintasche der Weste. Ist sie gesetzt, greift die Hand dorthin
## statt an den festen Punkt POUCH — das Modell bestimmt dann, wo die
## Taschen sitzen.
var pouch_target: Node3D

## Fortschritt des Nachladens, 0 bis 1. Negativ heisst: wird nicht nachgeladen.
var reload_progress: float = -1.0

## ---------------------------------------------------------------------------
## DIE HALTUNG — WAS DIE FIGUR GERADE TUT
##
## Diese Felder sind die ganze Schnittstelle nach aussen. Wer sie füllt, ist
## der Animation egal: heute das Skript einer Zielfigur, morgen die Tasten des
## Spielers, später die Entscheidung eines KI-Gegners.
##
## GENAU DARIN LIEGT DER ZWECK. Stünden Ducken und Zielen als Sonderfälle im
## Dummy-Skript, müsste der Spieler dieselbe Bewegung ein zweites Mal
## bekommen — und die KI ein drittes Mal. Drei Kopien derselben Haltung, die
## ab dem ersten Nachjustieren verschieden aussehen.
##
## Es passt ausserdem zu Grundsatzentscheidung 2: Der Spieler MELDET seinen
## Zustand, er rechnet die Haltung nicht selbst.
##
## `speed` und `holding_weapon` oben gehören fachlich dazu — sie standen nur
## schon da, bevor es diesen Satz gab.
## ---------------------------------------------------------------------------

enum Stance {
	STAND,   ## aufrecht
	CROUCH,  ## geduckt
}

var stance: Stance = Stance.STAND

## Rennt die Figur? Ändert die HALTUNG, nicht das Tempo — das steht in `speed`.
## Wer rennt, beugt sich vor und nimmt die Waffe herunter.
var is_sprinting: bool = false

## Hat die Figur die Waffe im Anschlag am Auge?
var is_aiming: bool = false

## Wohin die Figur schaut, in Grad. Negativ ist nach oben.
##
## ---------------------------------------------------------------------------
## DER OBERKÖRPER DREHT SICH MIT DEM BLICK
##
## Beim Dummy bleibt das null — der schaut geradeaus. Beim Spieler ist es
## seine Blickrichtung, und ohne das zeigte die Waffe stur waagerecht, während
## er nach oben oder unten sieht. In der ersten Person, wo er seine eigene
## Waffe sieht, fällt das sofort auf.
##
## Es geht auf den RUMPF, nicht auf den Kopf: Wer ein Gewehr im Anschlag hat,
## dreht den ganzen Oberkörper mit, nicht nur den Hals. Genau dafür gibt es
## den Rumpfknoten.
var look_pitch: float = 0.0

## Ist die Figur gerade in der Luft?
##
## ---------------------------------------------------------------------------
## OHNE DAS RUDERT SIE IM FLUG WEITER
##
## Der Schrittzyklus haengt am Tempo, und waagerecht ist man beim Springen
## genauso schnell wie vorher. Die Beine liefen also munter weiter, waehrend
## die Figur durch die Luft flog — als wuerde sie auf dem Nichts gehen.
##
## `vertical_speed` unterscheidet Steigen von Fallen: Beim Absprung zieht man
## die Beine an, beim Landen streckt man sie nach vorn.
var is_airborne: bool = false
var vertical_speed: float = 0.0

## Wo die Magazintaschen sitzen: vorn links am Bauch, dicht am Körper.
##
## In Figurkoordinaten, weil die Hand dorthin greift, egal wie die Figur steht
## oder gedreht ist.
##
## DIESER PUNKT IST EINE ZUSAGE AN DAS WESTENMODELL. Wer eine Weste baut, muss
## die Magazintaschen hierher setzen — sonst greift die Hand daneben, und das
## sieht man sofort. Vorher lag er bei x = -0,24, also 6 cm NEBEN dem Rumpf;
## dort haette eine Tasche in der Luft geschwebt.
##
## Der Bauch reicht von y 0,79 bis 1,09 und ist 0,36 breit, seine Vorderseite
## liegt bei z = -0,11. Der Griff geht also an die linke vordere Ecke, eine
## Handbreit unter dem Brustkorb.
const POUCH := Vector3(-0.15, 0.98, -0.16)

## Der Ablauf des Nachladens, als Wegmarken der Stützhand.
##
## ---------------------------------------------------------------------------
## SECHS SCHRITTE, WIE ES WIRKLICH GEHT
##
##   hinreichen  →  greifen  →  herausziehen  →  neues holen
##               →  einschieben  →  Ladehebel durchziehen
##
## Die Zeiten sind auf `WeaponViewmodel._animate_magazine_swap` abgestimmt und
## dürfen nicht frei verschoben werden: Dort fällt das Magazin bis 0,30, ist
## bis 0,45 verschwunden, sitzt bei 0,85 wieder, und ab 0,85 läuft der
## Ladehebel. Wer hier eine Marke verschiebt, muss dort nachsehen — sonst
## greift die Hand ins Leere, während das Magazin woanders ist.
##
## ---------------------------------------------------------------------------
## HERAUSZIEHEN HEISST NICHT HINTERHERFALLEN
##
## Das Magazin fällt 34 cm. So weit reicht kein Arm, und niemand begleitet ein
## fallendes Magazin zu Boden. Die Hand zieht es 8 cm heraus — so weit, dass
## man die Bewegung sieht — und lässt es dann fallen.
const RELOAD_REACH := 0.10   ## vom Schaft zum Schacht
const RELOAD_GRIP := 0.16    ## kurz halten, bevor es losgeht
const RELOAD_PULL := 0.30    ## herausziehen
const RELOAD_FETCH := 0.45   ## zur Tasche, altes weg und neues in die Hand
const RELOAD_CARRY := 0.72   ## neues zurück an den Schacht
const RELOAD_SEAT := 0.85    ## einschieben
const RELOAD_CHARGE := 0.96  ## Ladehebel greifen und durchziehen

## Wie weit die Hand das Magazin herauszieht, bevor sie es loslässt.
const PULL_DISTANCE := 0.08


## Haltung mit Waffe. Werte in Grad.
##
## ---------------------------------------------------------------------------
## WARUM HIER FESTE WINKEL STEHEN UND KEINE IK
##
## Sauber wäre inverse Kinematik: Man gibt an, wo die Hände sein sollen, und
## der Rechner sucht die Gelenkwinkel. Für zwei Gelenke je Arm und eckige
## Gliedmassen ist das aber mit Kanonen auf Spatzen geschossen — man sieht
## dem Ergebnis den Unterschied nicht an, und feste Winkel lassen sich beim
## Betrachten eines Bildes nachjustieren.
##
## Z DREHT DEN ARM ZUR KÖRPERMITTE. Ohne das zeigen beide Unterarme
## kerzengerade nach vorn, 56 cm auseinander — die Waffe ist 5 cm breit, die
## Hände greifen also ins Leere. Der linke Arm braucht positives Z, der rechte
## negatives, damit beide nach innen kommen.
## ACHTUNG BEIM NACHJUSTIEREN: X und Z zusammen verhalten sich nicht so, wie
## man erwartet — Godot wendet Euler-Winkel in der Reihenfolge YXZ an, und
## eine grössere X-Drehung hebt den Arm dann seitlich an, statt ihn weiter
## nach vorn zu bringen. Ein Versuch mit (48, 0, 34) liess den Stützarm nach
## oben zeigen statt an den Vorderschaft. Wer hier dreht, sollte danach
## rendern statt zu rechnen.
const HOLD_LEFT_SHOULDER := Vector3(38.0, 0.0, 26.0)
const HOLD_LEFT_ELBOW := Vector3(62.0, 0.0, 0.0)
const HOLD_RIGHT_SHOULDER := Vector3(22.0, 0.0, -30.0)
const HOLD_RIGHT_ELBOW := Vector3(74.0, 0.0, 0.0)

## Wie stark die Haltung beim Laufen mitatmet. Klein: Ein Anschlag soll
## ruhig wirken, aber nicht wie festgeschraubt.
const HOLD_SWAY := 5.0

## Ab diesem Tempo gilt die volle Ausschlagsweite: das Sprinttempo des
## Spielers.
##
## Hier stand 4,5 mit dem Kommentar „entspricht etwa dem Sprint des Spielers".
## Das stimmte einmal; inzwischen sprintet er 5,2. Die Figur schwang deshalb
## schon bei 4,5 voll aus und legte bis 5,2 nur noch Frequenz zu — sie
## trippelte im Sprint. Jetzt kommt der Wert von dort, wo er hingehört.
const FULL_SWING_SPEED := PlayerController.SPRINT_SPEED

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

## ---------------------------------------------------------------------------
## DUCKEN
##
## Wie tief der Körper sinkt, in Metern. Der EINZIGE Wert, an dem man dreht —
## der Kniewinkel folgt daraus, siehe `_crouch_knee_angle()`.
##
## ---------------------------------------------------------------------------
## DER WERT KOMMT VOM SPIELER, NICHT VON HIER
##
## Die Kollisionskapsel des Spielers schrumpft beim Ducken von 1,80 auf
## 1,20 m. Die Figur sinkt jetzt um genau dieselben 0,60 m — sie soll ja
## darstellen, was der Spieler tut, und spätestens wenn der Spieler einen
## sichtbaren Körper bekommt, wäre jeder Unterschied eine Lüge: Der Körper
## sähe anders geduckt aus, als die Kapsel es ist, und Treffer lägen woanders
## als das Bild sie erwarten lässt.
##
## Hier standen nacheinander 0,32 und 0,22 m — beides von Hand gewählt, weil
## mir 0,60 im Rendering zu tief vorkam. Das war meine Meinung gegen eine
## Zahl, die es schon gab.
##
## PREIS: 0,60 m bei 0,75 m Beinlänge sind 78 Grad Oberschenkelbeugung, also
## eine echte Hocke mit weit vorstehenden Knien. Die Figur hat kein
## Fussgelenk, das davon etwas auffangen könnte. Sieht das falsch aus, ist
## nicht dieser Wert schuld, sondern die Ducktiefe des Spielers — und die
## gehört dann dort geändert, nicht hier.
const CROUCH_DROP := PlayerController.STAND_HEIGHT - PlayerController.CROUCH_HEIGHT

## Wie schnell zwischen Stehen und Ducken gewechselt wird.
const STANCE_SPEED := 7.0

## ---------------------------------------------------------------------------
## RENNEN
##
## Wer rennt, legt sich nach vorn. Das ist der ganze Unterschied zum schnellen
## Gehen — der Schrittzyklus rechnet sich ohnehin schon aus dem Tempo, ein
## eigener „Sprintzyklus" wäre eine zweite Wahrheit über dieselbe Bewegung.
## NEGATIV heisst nach VORN. Das ist nicht dasselbe Vorzeichen wie beim Bein:
## Ein Bein haengt vom Gelenk nach UNTEN, der Rumpf ragt nach OBEN. Dieselbe
## Drehung schwingt das eine nach vorn und das andere nach hinten. Mit +11 hat
## sich die Figur beim Rennen zurueckgelehnt — gemessene 14,7 cm nach hinten.
const SPRINT_LEAN := -11.0
const SPRINT_SPEED_BLEND := 6.0

## Wie weit sich der Oberkörper beim Ducken zusätzlich vorbeugt. Klein — wer
## sich duckt, geht in die Knie, er klappt nicht zusammen.
const CROUCH_LEAN := -4.0

## ---------------------------------------------------------------------------
## SPRINGEN
##
## Beim Steigen die Beine anziehen, beim Fallen nach vorn strecken. Beides
## nimmt der Kniewinkel auf; der Oberschenkel kommt leicht mit.
const JUMP_TUCK_KNEE := -55.0    ## angezogen im Steigen
const JUMP_TUCK_THIGH := 22.0
const JUMP_REACH_KNEE := -12.0   ## fast gestreckt im Fallen
const JUMP_REACH_THIGH := -8.0

## Ab dieser Steiggeschwindigkeit gilt der Absprung als voll ausgeprägt.
const JUMP_FULL_SPEED := 3.5

## Wie schnell in die Sprunghaltung und zurück geblendet wird. Schnell, weil
## ein Sprung kurz ist — bei 6.0 wäre er vorbei, bevor die Beine oben sind.
const AIRBORNE_BLEND := 14.0

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

## Was mitwippt, steht jetzt in `BlockyCharacter.UPPER_BODY` und hängt dort
## unter einem gemeinsamen Rumpfknoten. Hier stand dieselbe Liste ein zweites
## Mal — zwei Listen, die dasselbe meinen, laufen früher oder später
## auseinander.

## Wie geduckt die Figur gerade ist, 0 bis 1. Läuft `stance` weich nach.
var _crouch: float = 0.0

## Wie sehr die Figur gerade rennt, 0 bis 1. Läuft `is_sprinting` weich nach.
var _sprint: float = 0.0

## Wie sehr sie gerade in der Luft ist, 0 bis 1.
var _airborne: float = 0.0

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

	# Haltung weich nachziehen. Ein Sprung von aufrecht zu geduckt sieht aus
	# wie ein Ruckler, nicht wie eine Bewegung. Tote ducken sich nicht mehr.
	var wants_crouch := 1.0 if (alive and stance == Stance.CROUCH) else 0.0
	_crouch = move_toward(_crouch, wants_crouch, STANCE_SPEED * delta)
	var wants_sprint := 1.0 if (alive and is_sprinting) else 0.0
	_sprint = move_toward(_sprint, wants_sprint, SPRINT_SPEED_BLEND * delta)
	var wants_air := 1.0 if (alive and is_airborne) else 0.0
	_airborne = move_toward(_airborne, wants_air, AIRBORNE_BLEND * delta)

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
		var hinge := character.hinge_of(part)
		var entry: Dictionary = SWINGING[part]

		var is_arm := part == HealthSystem.Part.LEFT_ARM \
			or part == HealthSystem.Part.RIGHT_ARM

		if holding_weapon and is_arm:
			_pose_weapon_arm(part, joint, hinge, swing)
			continue

		# Absolut setzen, nie addieren: Bei _intensity = 0 kommt exakt null
		# heraus und der Kanal räumt sich von selbst auf.
		joint.rotation_degrees = Vector3(
			swing * entry.amount * entry.sign * _intensity, 0.0, 0.0)

		if hinge == null:
			continue
		hinge.rotation_degrees.x = _hinge_angle(part, entry.sign)

	# Das Wippen läuft mit der doppelten Schrittfrequenz — bei jedem Auftritt
	# einmal, nicht bei jedem Doppelschritt.
	var bob := absf(sin(_phase)) * BOB_HEIGHT * _intensity
	var breath := 0.0
	if alive:
		breath = sin(_time * BREATH_SPEED) * BREATH_HEIGHT * (1.0 - _intensity)

	# Ein Knoten statt fünf. Vorher wurde jedes Oberkörperteil einzeln
	# angehoben; wer eines vergass, bekam eine Figur, deren Kopf beim Gehen
	# vom Hals abhob. Der Rumpf trägt jetzt auch das Ducken, siehe
	# `_torso_height()`.
	var trunk := character.torso()
	if trunk != null:
		# Von der Hüfthöhe aus, nicht von null: Dort sitzt das Rumpfgelenk.
		trunk.position.y = BlockyCharacter.torso_pivot() + bob + breath + _stance_drop()
		# Beim Rennen nach vorn legen, beim Ducken ebenfalls etwas — wer in
		# die Hocke geht, richtet sich nicht kerzengerade auf.
		trunk.rotation_degrees.x = (SPRINT_LEAN * _sprint + CROUCH_LEAN * _crouch
			+ look_pitch)

	_pose_legs_for_stance()


## Senkt die Hüften ab und beugt die Knie, wenn die Figur duckt.
##
## Die Beine hängen an der FIGUR, nicht am Rumpf — sie tragen den Körper,
## statt von ihm getragen zu werden. Beim Ducken müssen sie deshalb eigens
## mitgenommen werden: Hüfte runter wie der Rumpf, Knie gebeugt, damit der
## Fuss stehen bleibt.
## KEIN vorzeitiges Aussteigen, wenn gerade nicht geduckt wird.
##
## Hier stand `if _crouch <= 0.001: return`. Sobald die Figur wieder stand,
## räumte damit niemand mehr auf, was das letzte geduckte Bild hinterlassen
## hatte: Die Hüften blieben 8,9 mm unter der Ruhelage stehen. Beim
## wiederholten Ducken hätte sich das aufsummiert.
##
## Bei `_crouch = 0` ist die Absenkung null und der Winkel null — es wird also
## die Ruhelage geschrieben, und genau das soll passieren.
func _pose_legs_for_stance() -> void:
	_pose_legs_for_jump()
	var thigh := _crouch_knee_angle()
	for part in [HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG]:
		var joint := character.joint_of(part)
		if joint == null:
			continue
		# Dieselbe Absenkung wie der Rumpf, sonst reisst die Figur in der
		# Mitte auseinander.
		#
		# ABSOLUT VON DER RUHELAGE AUS, NICHT DAZUZÄHLEN. Hier stand erst
		# `position.y += ...`, und weil die Beinposition im Gehzweig sonst
		# nicht zurückgesetzt wird, sank die Figur mit jedem Bild um weitere
		# 32 cm — nach drei Sekunden standen die Füsse 57 Meter unter dem
		# Boden. Dieselbe Falle, vor der der Kommentar beim Ausschlag warnt.
		joint.position = _rest[part] + Vector3(0.0, _stance_drop(), 0.0)
		joint.rotation_degrees.x += thigh

		var knee := character.hinge_of(part)
		if knee != null:
			# Doppelt zurück: Der Unterschenkel steht dann so schräg wie der
			# Oberschenkel, nur andersherum — der Fuss bleibt unter der Hüfte.
			knee.rotation_degrees.x -= thigh * 2.0


## Setzt einen Arm in die Waffenhaltung.
##
## Der Ausschlag geht hier NICHT in die Schulter, sondern nur als kleines
## Mitatmen obendrauf. Beide Hände bleiben an der Waffe.
func _pose_weapon_arm(part: HealthSystem.Part, joint: Node3D, hinge: Node3D,
		swing: float) -> void:
	var left := part == HealthSystem.Part.LEFT_ARM

	# Die linke Hand stützt vorn am Schaft, die rechte hält den Griff.
	# Beim Nachladen wandert die linke zum Magazin — die rechte bleibt am
	# Griff, denn die Waffe hält man dabei fest.
	var anchor := support_target if left else grip_target
	if anchor != null and hinge != null:
		var goal := _support_hand_goal() if left else anchor.global_position
		if _solve_arm(part, joint, hinge, goal):
			return

	# Rückfallebene: feste Winkel, wenn die Waffe keine Griffpunkte nennt.
	var shoulder := HOLD_LEFT_SHOULDER if left else HOLD_RIGHT_SHOULDER
	var elbow := HOLD_LEFT_ELBOW if left else HOLD_RIGHT_ELBOW

	var sway := swing * HOLD_SWAY * _intensity
	joint.rotation_degrees = shoulder + Vector3(sway, 0.0, 0.0)
	if hinge != null:
		hinge.rotation_degrees = elbow


## Ob das Ersatzmagazin gerade in der Hand liegt statt in der Tasche.
##
## Von RELOAD_FETCH an hat die Hand es gegriffen; ab RELOAD_SEAT sitzt es in
## der Waffe und das Modell der Waffe zeigt es selbst.
func carries_spare_magazine() -> bool:
	return reload_progress >= RELOAD_FETCH and reload_progress < RELOAD_SEAT


## Wo die Magazintasche liegt, aus der gezogen wird.
##
## Trägt die Figur eine Weste, kommt der Punkt aus deren Modell. Ohne Weste
## bleibt der feste Punkt am Bauch — sonst könnte eine unbewestete Figur gar
## nicht nachladen.
func pouch_position() -> Vector3:
	if pouch_target != null:
		return pouch_target.global_position
	return character.global_transform * POUCH


## Wohin die Stützhand gerade greift.
##
## Ausserhalb des Nachladens ist das schlicht der Vorderschaft. Während des
## Wechsels läuft sie die Wegmarken oben ab — siehe deren Kommentar.
func _support_hand_goal() -> Vector3:
	var handguard := support_target.global_position
	if reload_progress < 0.0 or magwell_target == null:
		return handguard

	var magwell := magwell_target.global_position
	var pouch := pouch_position()
	var p := reload_progress

	# Herausgezogen wird nach unten aus der Waffe heraus, nicht nach
	# Weltkoordinaten unten: Die Waffe ist beim Nachladen gekippt.
	var down := -magwell_target.global_basis.y.normalized()
	var pulled := magwell + down * PULL_DISTANCE

	# 1. Hinreichen. smoothstep statt lerp, damit die Hand anfährt und
	#    abbremst, statt ruckartig loszuschnellen.
	if p < RELOAD_REACH:
		return handguard.lerp(magwell, smoothstep(0.0, RELOAD_REACH, p))

	# 2. Greifen — kurz stillhalten. Ohne diese Pause liest sich das
	#    Herausziehen nicht als Griff, sondern als Durchwischen.
	if p < RELOAD_GRIP:
		return magwell

	# 3. Herausziehen.
	if p < RELOAD_PULL:
		return magwell.lerp(pulled, smoothstep(RELOAD_GRIP, RELOAD_PULL, p))

	# 4. Altes fallen lassen, neues aus der Tasche holen.
	if p < RELOAD_FETCH:
		return pulled.lerp(pouch, smoothstep(RELOAD_PULL, RELOAD_FETCH, p))

	# 5. Neues heranführen und einschieben.
	if p < RELOAD_CARRY:
		return pouch.lerp(pulled, smoothstep(RELOAD_FETCH, RELOAD_CARRY, p))
	if p < RELOAD_SEAT:
		return pulled.lerp(magwell, smoothstep(RELOAD_CARRY, RELOAD_SEAT, p))

	# 6. Ladehebel. Das Modell zieht ihn ab 0,85 nach hinten — die Hand
	#    folgt ihm einfach, statt eine eigene Bahn zu laufen.
	var handle := charge_target.global_position if charge_target != null else magwell
	if p < RELOAD_CHARGE:
		return magwell.lerp(handle, smoothstep(RELOAD_SEAT, RELOAD_CHARGE, p))

	# Zurück an den Schaft.
	return handle.lerp(handguard, smoothstep(RELOAD_CHARGE, 1.0, p))


## Stellt einen Arm so, dass die Hand auf dem Zielpunkt liegt.
##
## ---------------------------------------------------------------------------
## ZWEI KNOCHEN, ANALYTISCH GELÖST — KEINE ITERATION
##
## Feste Winkel für die Waffenhaltung waren ein Irrweg: Man dreht an X, der Arm
## hebt sich seitlich, man dreht an Z, er dreht sich um sich selbst, und nach
## drei Versuchen greift die Hand immer noch daneben. Godot wendet Euler-Winkel
## als YXZ an, und damit tut jede Änderung etwas anderes als erwartet.
##
## Rückwärts ist es dagegen eindeutig. Ober- und Unterarm sind zwei Strecken
## fester Länge; wo die Hand liegen soll, ist bekannt. Damit liegt der
## Ellenbogen auf einem KREIS um die Verbindungslinie Schulter–Ziel, und der
## Kosinussatz gibt Radius und Abstand davon. Welcher Punkt auf dem Kreis es
## wird, entscheidet der Polvektor — also die Richtung, in die der Ellenbogen
## zeigen soll. Beim Menschen: nach aussen und nach hinten.
##
## Ergebnis: Man sagt, wo die Hand hin soll, und muss nie wieder an einem
## Winkel drehen. Ändert sich die Waffe, wandern die Hände von selbst mit.
##
## Gibt false zurück, wenn der Arm zu kurz ist — dann greift die feste Haltung.
func _solve_arm(part: HealthSystem.Part, joint: Node3D, hinge: Node3D,
		target: Vector3) -> bool:
	if character == null:
		return false

	var size := character.size_of(part)
	var upper: float = size.y * float(BlockyCharacter.HINGES[part].at)
	var lower: float = size.y - upper

	# Im Raum des ELTERNKNOTENS rechnen, nicht in Weltkoordinaten: Dann ist
	# die Rechnung unabhängig davon, wo und wie gedreht die Figur steht.
	#
	# ---------------------------------------------------------------------
	# WARUM DER ELTERNKNOTEN UND NICHT DIE FIGUR
	#
	# `shoulder` ist `joint.position`, also die Lage RELATIV ZUM ELTERN-
	# KNOTEN. Hier stand `character.global_transform` — und solange die Arme
	# direkt an der Figur hingen, war das derselbe Raum.
	#
	# Seit der Oberkörper unter `Rumpf` hängt, ist er es nicht mehr. Beim
	# aufrechten Stehen fällt das nicht auf, weil der Rumpf dann auf null
	# steht und ungedreht ist; die Hände sassen weiter auf 6 mm genau. Sobald
	# sich die Figur duckte oder rannte, wanderte der Rumpf — und die Hände
	# griffen 22 cm neben die Waffe, während die Waffe selbst richtig sass.
	#
	# Mit dem Elternknoten stimmt die Rechnung unabhängig davon, wieviele
	# Knoten zwischen Figur und Schulter liegen.
	var parent := joint.get_parent_node_3d()
	if parent == null:
		return false
	var to_local := parent.global_transform.affine_inverse()
	var shoulder := joint.position
	var goal := to_local * target

	var delta := goal - shoulder
	var distance := delta.length()
	if distance < 0.001:
		return false

	# Ein Arm kann sich nicht strecken. Liegt das Ziel ausserhalb der
	# Reichweite, zeigt der Arm wenigstens dorthin, statt sich zu verrenken.
	distance = clampf(distance, absf(upper - lower) + 0.005, upper + lower - 0.005)
	var direction := delta.normalized()

	# Kosinussatz: Wie weit liegt der Ellenbogen auf der Linie, und wie weit
	# daneben?
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var offset := sqrt(maxf(0.0, upper * upper - along * along))

	# Der Ellenbogen zeigt nach aussen und nach hinten — so hält ein Mensch
	# ein Gewehr. Ohne diese Vorgabe wäre jede Lage auf dem Kreis gleich gut,
	# und der Arm könnte auch nach oben abknicken.
	var side := signf(shoulder.x)
	var pole := Vector3(side * 0.7, -0.3, 0.65)
	pole -= direction * pole.dot(direction)
	if pole.length() < 0.001:
		pole = Vector3.UP
	pole = pole.normalized()

	var elbow := shoulder + direction * along + pole * offset

	# Beide Glieder hängen entlang -Y. Gesucht ist je die Drehung, die -Y auf
	# die Richtung des Glieds legt.
	var upper_dir := (elbow - shoulder).normalized()
	var lower_dir := (goal - elbow).normalized()

	joint.basis = Basis(Quaternion(Vector3.DOWN, upper_dir))
	# Der Ellenbogen sitzt im Raum der Schulter, seine Richtung muss also
	# dorthin umgerechnet werden.
	hinge.basis = Basis(Quaternion(Vector3.DOWN, joint.basis.inverse() * lower_dir))
	return true


## Winkel eines Zwischengelenks — Knie oder Ellenbogen.
##
## Beide beugen sich nur in EINE Richtung, deshalb kommt hier nie ein
## Vorzeichenwechsel heraus. Ein Knie zeigt nach hinten (negativ), ein
## Ellenbogen nach vorn (positiv) — die Figur schaut nach -Z, ein positiver
## Ausschlag führt das untere Ende also nach vorn.
## Zieht die Beine an, solange die Figur in der Luft ist.
##
## Ueberlagert den Gehzyklus, statt ihn zu ersetzen: Wer im Lauf abspringt,
## behaelt seine Schrittstellung und zieht sie nur an. Deshalb wird hier
## dazugerechnet und nicht gesetzt — beide Werte stehen kurz vorher absolut,
## also gibt es keinen Aufsummierungsfehler wie beim Ducken.
func _pose_legs_for_jump() -> void:
	if _airborne <= 0.001:
		return

	# Steigen oder Fallen? Beim Absprung angezogen, beim Landen gestreckt.
	var rising := clampf(vertical_speed / JUMP_FULL_SPEED, 0.0, 1.0)
	var knee := lerpf(JUMP_REACH_KNEE, JUMP_TUCK_KNEE, rising) * _airborne
	var thigh := lerpf(JUMP_REACH_THIGH, JUMP_TUCK_THIGH, rising) * _airborne

	for part in [HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG]:
		var joint := character.joint_of(part)
		if joint == null:
			continue
		joint.rotation_degrees.x += thigh
		var hinge := character.hinge_of(part)
		if hinge != null:
			hinge.rotation_degrees.x += knee


## Wie weit der Oberkörper gerade abgesenkt ist. Negativ heisst nach unten.
func _stance_drop() -> float:
	return -CROUCH_DROP * _crouch


## Um wieviel Grad der Oberschenkel beim Ducken nach vorn kippt.
##
## ---------------------------------------------------------------------------
## GERECHNET, DAMIT DIE FÜSSE AUF DEM BODEN BLEIBEN
##
## Ein Bein ist ein Zweigelenker. Kippt der Oberschenkel um a nach vorn und
## knickt das Knie um 2a zurück, steht der Unterschenkel wieder so schräg wie
## der Oberschenkel — nur andersherum. Der Fuss bleibt dadurch unter der
## Hüfte, und der ganze Körper sinkt um
##
##     Absenkung = Beinlänge × (1 − cos a)
##
## Nach a aufgelöst ergibt sich der Winkel unten. Wer CROUCH_DROP ändert,
## bekommt den passenden Kniewinkel damit geschenkt.
##
## Ein geschätzter Winkel hätte die Füsse je nach Tiefe in den Boden gedrückt
## oder in der Luft hängen lassen — und das fällt bei einer geduckten Figur
## erst auf, wenn jemand genau hinsieht.
func _crouch_knee_angle() -> float:
	var leg := character.size_of(HealthSystem.Part.LEFT_LEG).y
	if leg <= 0.0:
		return 0.0
	# clampf, weil eine Absenkung grösser als die Beinlänge keinen Winkel hat.
	var cosine := clampf(1.0 - (CROUCH_DROP * _crouch) / leg, -1.0, 1.0)
	return rad_to_deg(acos(cosine))


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
		var hinge := character.hinge_of(part)

		if holding_weapon and (part == HealthSystem.Part.LEFT_ARM
				or part == HealthSystem.Part.RIGHT_ARM):
			joint.position = _rest[part]
			_pose_weapon_arm(part, joint, hinge, 0.0)
			continue

		joint.position = _rest[part]
		joint.rotation_degrees = Vector3.ZERO

		if hinge != null:
			# Nicht auf null: Der Ellenbogen hat auch im Stand seinen
			# Grundwinkel, sonst hängen die Arme kerzengerade herunter.
			hinge.rotation_degrees.x = _hinge_angle(part, 1.0)
