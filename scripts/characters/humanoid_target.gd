## Eine Figur zum Draufschiessen, mit Beschriftung darüber.
##
## ---------------------------------------------------------------------------
## WOZU
##
## `HealthSystem` führt sieben Körperteile mit eigenen Trefferpunkten, und bis
## zur Figur gab es keinen Weg, eines davon zu treffen. Damit war das ganze
## System unprüfbar: Man konnte weder sehen, ob ein Kopfschuss tötet, noch ob
## ein zerschossenes Bein wirklich auf die Brust überläuft.
##
## Diese Klasse macht daraus etwas, worauf man schiessen kann. Sie ist das
## Gegenstück zu `TargetDummy` — die flache Scheibe zeigt, was Munition gegen
## Platten anrichtet, die Figur zeigt, was sie gegen einen Körper anrichtet.
##
## ---------------------------------------------------------------------------
## KEIN GEGNER
##
## Sie steht still, wehrt sich nicht und denkt nicht. Sobald es echte Gegner
## gibt, erben die von `BlockyCharacter` genau wie sie — was hier steht, ist
## nur Beschriftung und Zurücksetzen.
class_name HumanoidTarget
extends BlockyCharacter

## Beschriftung über dem Kopf.
@export var label_text: String = "Figur"

## Kurze Kennzeichnung, meist eine Nummer.
##
## ---------------------------------------------------------------------------
## EIGENES FELD, KEIN UMBRUCH IN label_text
##
## Naheliegend waere, die Nummer einfach vorne an `label_text` zu haengen. Das
## geht schief: Ueber dem Kopf steht die Beschriftung ZWEIZEILIG, im HUD
## dagegen EINZEILIG — siehe `label_lines()` gegen `describe()`. Ein
## Zeilenumbruch in `label_text` landet in beiden und reisst die HUD-Zeile
## auseinander.
##
## Als eigenes Feld kann jede der beiden Darstellungen selbst entscheiden, wo
## die Kennzeichnung hingehoert: oben in eine eigene Zeile, im HUD davor.
@export var marking: String = ""

## Wie hoch über dem Scheitel die Schrift schwebt.
const LABEL_HEIGHT := 0.32

## Wie weit die Figur hin und her geht, in Metern. 0 = sie steht.
##
## Ein bewegliches Ziel ist der ehrlichere Test: Auf ein stehendes Ziel
## trifft man auch mit falschem Vorhalt, und die Flugzeit der Kugel merkt man
## erst, wenn sich etwas bewegt.
@export var patrol_width: float = 0.0

@export var patrol_speed: float = 1.4

## Ob und wie die Figur eine Waffe führt. Leer = keine.
@export var weapon_id: StringName = &""

@export var weapon_attachments: Array[StringName] = []

@export var weapon_behaviour: CharacterWeapon.Behaviour = CharacterWeapon.Behaviour.HOLD

## Ob die Figur eine taktische Weste traegt. Aus ihr holt sie beim Nachladen
## die Magazine.
@export var wears_vest: bool = false

## ---------------------------------------------------------------------------
## HALTUNG
##
## Dieselben drei Zustaende, die der Spieler laengst kennt: is_crouching,
## is_sprinting, is_aiming in player_controller.gd. Hier sind sie Schalter zum
## Vorfuehren; beim Spieler haengen sie an Tasten, bei einem KI-Gegner spaeter
## an dessen Entscheidung.
##
## Weitergereicht werden sie in `_apply_stance()` — an die Animation fuer den
## Koerper und an die Waffe fuer deren Haltung. Beide bekommen sie aus DIESER
## einen Quelle, damit Koerper und Waffe nicht auseinanderlaufen koennen.
@export var crouching: bool = false:
	set(value):
		crouching = value
		_apply_stance()

@export var sprinting: bool = false:
	set(value):
		sprinting = value
		_apply_stance()

@export var aiming: bool = false:
	set(value):
		aiming = value
		_apply_stance()

var weapon: CharacterWeapon
var vest: CharacterVest

var _spare_magazine: Node3D

var _label: Label3D
var _hits: int = 0
var _animation: CharacterAnimation
var _patrol_origin: Vector3
var _patrol_ready: bool = false
var _patrol_time: float = 0.0


func _ready() -> void:
	super()

	_animation = CharacterAnimation.new()
	_animation.name = "Bewegung"
	add_child(_animation)
	# Erst nach super(), denn attach() liest die Ruhelage der Gelenke —
	# und die gibt es erst, nachdem BlockyCharacter.build() gelaufen ist.
	_animation.attach(self)

	_label = Label3D.new()
	_label.name = "Beschriftung"
	_label.position = Vector3(0.0, HEIGHT + LABEL_HEIGHT, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Ohne das verschwindet die Schrift bei 300 m in der Figur, weil der
	# Tiefentest sie gegen den Kopf verliert.
	_label.no_depth_test = true
	_label.font_size = 64
	_label.pixel_size = 0.0016
	_label.modulate = Color(0.86, 0.88, 0.92)
	_label.outline_size = 18
	add_child(_label)

	# Die Weste zuerst: Sie bringt die Magazintaschen mit, und die braucht die
	# Waffe gleich fuer den Griffpunkt.
	if wears_vest:
		_put_on_vest()

	if weapon_id != &"":
		_arm_with_weapon()

	part_hit.connect(_on_part_hit)
	_apply_stance()
	_update_label()


## Reicht die Haltung an Körper und Waffe weiter.
##
## Wird auch aus den Settern gerufen, also unter Umständen bevor `_ready()`
## gelaufen ist — deshalb die Prüfungen auf null. Ohne die stürzt die Szene
## beim Setzen eines Hakens im Editor ab.
func _apply_stance() -> void:
	if _animation != null:
		_animation.stance = (CharacterAnimation.Stance.CROUCH if crouching
			else CharacterAnimation.Stance.STAND)
		_animation.is_sprinting = sprinting
		_animation.is_aiming = aiming
	# An die Waffe geht nichts: Sie wird in jeder Haltung gleich gefasst,
	# siehe den Kommentar in CharacterWeapon. Ducken und Rennen zeigen sich
	# am Körper.


## Zieht der Figur die Weste an.
##
## Aufgehaengt am Brustgelenk: Dort sitzt der Punkt, auf den das Modell
## ausgelegt ist — mittig auf Hoehe der Brust-Oberkante, die Geometrie haengt
## von dort nach unten. Und wenn der Oberkoerper sich spaeter bewegt, geht die
## Weste von selbst mit.
func _put_on_vest() -> void:
	var chest := joint_of(HealthSystem.Part.CHEST)
	if chest == null:
		push_warning("[HumanoidTarget] Kein Brustgelenk — Weste entfaellt")
		return

	vest = CharacterVest.new()
	vest.name = "Weste"
	chest.add_child(vest)

	# Der Griffpunkt kommt jetzt aus dem Modell statt aus einer Konstante.
	# Wer eine Tasche in Blender verschiebt, verschiebt damit auch, wohin die
	# Hand greift.
	if _animation != null:
		_animation.pouch_target = vest.front_pouch()

	_add_spare_magazine()


## Ein sichtbares Ersatzmagazin, das in der Tasche steckt und beim Nachladen
## mitwandert.
##
## ---------------------------------------------------------------------------
## OHNE DAS ERSCHEINT DAS MAGAZIN AUS DEM NICHTS
##
## Die Hand ging bisher zur Tasche und zurueck, trug aber nichts. An der Waffe
## tauchte dann ein neues Magazin auf. Man sah die Geste, aber nicht den
## Gegenstand — und damit sah es aus, als griffe die Figur ins Leere.
##
## Es ist DASSELBE Modell, das auch in der Waffe steckt: AR15_Magazin.glb.
## Ein zweites, aehnliches waere eine Kopie, die beim naechsten Aendern
## zurueckbleibt.
func _add_spare_magazine() -> void:
	_spare_magazine = Node3D.new()
	_spare_magazine.name = "Ersatzmagazin"
	add_child(_spare_magazine)

	# Seit dem Sketchfab-Modell aus ar15.glb herausgelöst statt aus einer
	# Einzeldatei — der Helfer liefert dasselbe PMAG wie in der Waffe.
	_spare_magazine.add_child(AR15Viewmodel.spare_magazine_model())
	# Das Magazin ist ein Waffenteil und schaut entlang +X, das Spiel erwartet
	# -Z. Die Drehung kommt deshalb von GlbParts, nicht von der Weste: Hier
	# stand frueher CharacterVest.TURN, was nur zufaellig stimmte, solange
	# beide Modelle dieselbe Achse hatten. Seit die Weste schon richtig herum
	# exportiert wird, laege das Magazin damit quer.
	_spare_magazine.rotation_degrees = GlbParts.TURN


## Gibt der Figur eine Waffe.
func _arm_with_weapon() -> void:
	var mount := weapon_mount()
	if mount == null:
		push_warning("[HumanoidTarget] Kein Waffenpunkt gefunden — Waffe entfällt")
		return

	weapon = CharacterWeapon.new()
	weapon.name = "Waffe"
	weapon.weapon_id = weapon_id
	weapon.attachment_ids = weapon_attachments
	weapon.behaviour = weapon_behaviour
	mount.add_child(weapon)

	# Die Arme gehören jetzt an die Waffe, nicht in den Gehzyklus.
	_animation.holding_weapon = true

	# Die Griffpunkte kommen aus dem Waffenmodell — jede Waffe sagt selbst,
	# wo sie angefasst wird.
	#
	# Kein Warten nötig: Der Waffenpunkt hängt bereits im Baum, also läuft
	# das _ready() der Waffe und danach das des Modells noch innerhalb von
	# add_child(). Die Punkte stehen hier schon.
	if weapon.viewmodel != null:
		_animation.grip_target = weapon.viewmodel.grip_point
		_animation.support_target = weapon.viewmodel.support_point
		_animation.magwell_target = weapon.viewmodel.magwell_point
		_animation.charge_target = weapon.viewmodel.charging_handle


## Setzt das Ersatzmagazin dorthin, wo es gerade sein muss.
##
## In der Tasche, solange nicht nachgeladen wird — beim Tragen an der Hand,
## und sobald es in der Waffe sitzt, verschwindet es hier und die Waffe zeigt
## ihr eigenes.
func _update_spare_magazine() -> void:
	if _spare_magazine == null or vest == null:
		return

	var pouch := vest.front_pouch()
	if pouch == null:
		return

	if _animation.carries_spare_magazine():
		var hand := hand_of(HealthSystem.Part.LEFT_ARM)
		if hand != null:
			_spare_magazine.visible = true
			_spare_magazine.global_position = hand.global_position
			return

	# Waehrend das Magazin in die Waffe geht, zeigt die Waffe es selbst —
	# zwei gleichzeitig sichtbare waeren einer zu viel.
	var in_weapon := _animation.reload_progress >= CharacterAnimation.RELOAD_SEAT
	_spare_magazine.visible = not in_weapon
	_spare_magazine.global_position = pouch.global_position


## Läuft hin und her, falls patrol_width gesetzt ist.
##
## Die Figur dreht sich in ihre Laufrichtung, statt seitwärts zu schieben.
## Ein Gehzyklus mit vor und zurück schwingenden Beinen sieht bei
## Seitwärtsbewegung sofort falsch aus — das Auge erkennt es, ohne dass man
## benennen könnte, was stört.
func _process(delta: float) -> void:
	if _animation == null:
		return

	# Vor allem anderen: Die Hand muss dem Magazin folgen, auch wenn die
	# Figur stillsteht. Stünde das weiter unten, bekämen genau die drei
	# bewaffneten Figuren nie einen Wert — sie patrouillieren nicht, und die
	# Funktion steigt gleich darunter aus.
	if weapon != null:
		_animation.reload_progress = weapon.reload_progress()

	_update_spare_magazine()

	# DIE AUSGANGSPOSITION ERST HIER MERKEN, NICHT IN _ready().
	#
	# Wer einen Knoten einhängt, setzt seine Position üblicherweise DANACH —
	# global_position braucht den Baum. In _ready() stünde hier also noch
	# (0,0,0), und die Figur spränge beim ersten Schritt in den Weltursprung.
	if not _patrol_ready:
		_patrol_origin = position
		_patrol_ready = true

	if patrol_width <= 0.0 or (health != null and health.is_dead):
		_animation.speed = 0.0
		return

	_patrol_time += delta

	# Kosinus statt Sägezahn: An den Umkehrpunkten wird die Figur langsamer
	# und dreht dort, statt schlagartig die Richtung zu wechseln.
	var half := patrol_width * 0.5
	var omega := patrol_speed / maxf(0.01, half)
	var offset := cos(_patrol_time * omega) * half
	var velocity := -sin(_patrol_time * omega) * half * omega

	position = _patrol_origin + Vector3(offset, 0.0, 0.0)

	# BLICKRICHTUNG = LAUFRICHTUNG, über look_at statt über einen Winkel.
	#
	# Vorher stand hier `rotation_degrees.y = 90.0 if velocity >= 0.0 else
	# -90.0`, und das war genau falsch herum: Bei +90 Grad zeigt die
	# Blickachse -Z auf -X, die Figur schaute also nach links, während sie
	# nach rechts lief. Sie ging rückwärts — im Spiel sah das aus, als liefe
	# die Animation spiegelverkehrt.
	#
	# look_at kann das nicht: Die Funktion dreht die -Z-Achse auf den
	# Zielpunkt, und ein Vorzeichenfehler ist damit nicht mehr möglich.
	if absf(velocity) > 0.01:
		look_at(global_position + Vector3(signf(velocity), 0.0, 0.0), Vector3.UP)

	_animation.speed = absf(velocity)


func _on_part_hit(_part: HealthSystem.Part, _result: Ballistics.HitResult) -> void:
	_hits += 1
	_update_label()


## Stellt die Figur wieder her — dieselbe Schnittstelle wie TargetDummy.reset(),
## damit das Testgelände beide über denselben Aufruf zurücksetzen kann.
func reset() -> void:
	_hits = 0
	_patrol_time = 0.0
	position = _patrol_origin
	if _animation != null:
		_animation.reset()
	if weapon != null:
		weapon.reset()
	if health != null:
		health.reset()
	plate_durability = plate.max_durability if plate != null else 0.0
	refresh_colors()
	_update_label()


## Kurzform für die Schrift über dem Kopf.
##
## GETRENNT VON describe(), UND ZWAR AUS EINEM SICHTBAREN GRUND: Die lange
## Fassung stand zuerst auch über der Figur und war rund viermal so breit wie
## die Beschriftung der flachen Scheiben. Auf 25 m überlappten sich dadurch
## alle drei Schilder der Reihe zu einem grauen Brei — lesbar war keines mehr.
##
## Zwei kurze Zeilen sind schmaler als eine lange, und solange nichts kaputt
## ist, steht in der zweiten gar nichts.
func label_lines() -> String:
	# Die Kennzeichnung bekommt eine eigene erste Zeile: Auf 300 m ist die
	# Schrift klein, und eine Zahl allein liest man dort noch.
	var head := "%s\n%s" % [marking, label_text] if marking != "" else label_text
	if health == null:
		return head
	if health.is_dead:
		return "%s\nTOT (%d)" % [head, _hits]

	var broken := 0
	for part: HealthSystem.Part in VERTICAL:
		if health.is_destroyed(part):
			broken += 1

	if _hits == 0:
		return head
	if broken == 0:
		return "%s\n%.0f TP (%d)" % [head, health.get_total_hp(), _hits]
	return "%s\n%.0f TP (%d), %d ab" % [head, health.get_total_hp(), _hits, broken]


## Was gerade mit der Figur los ist, als Zeile fürs HUD.
func describe() -> String:
	# Im HUD bleibt alles auf EINER Zeile, die Kennzeichnung steht davor.
	var named := "%s %s" % [marking, label_text] if marking != "" else label_text
	if health == null:
		return named
	if health.is_dead:
		return "%s: TOT nach %d Treffern" % [named, _hits]

	var broken: Array[String] = []
	for part: HealthSystem.Part in VERTICAL:
		if health.is_destroyed(part):
			broken.append(part_name(part))

	if broken.is_empty():
		return "%s: %.0f TP, %d Treffer" % [named, health.get_total_hp(), _hits]
	return "%s: %.0f TP, %d Treffer, ab: %s" % [
		named, health.get_total_hp(), _hits, ", ".join(broken)]


func _update_label() -> void:
	if _label == null:
		return
	_label.text = label_lines()
	if health != null and health.is_dead:
		_label.modulate = Color(0.78, 0.30, 0.24)
	else:
		_label.modulate = Color(0.86, 0.88, 0.92)
