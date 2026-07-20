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

## Wie hoch über dem Scheitel die Schrift schwebt.
const LABEL_HEIGHT := 0.32

## Wie weit die Figur hin und her geht, in Metern. 0 = sie steht.
##
## Ein bewegliches Ziel ist der ehrlichere Test: Auf ein stehendes Ziel
## trifft man auch mit falschem Vorhalt, und die Flugzeit der Kugel merkt man
## erst, wenn sich etwas bewegt.
@export var patrol_width: float = 0.0

@export var patrol_speed: float = 1.4

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

	part_hit.connect(_on_part_hit)
	_update_label()


## Läuft hin und her, falls patrol_width gesetzt ist.
##
## Die Figur dreht sich in ihre Laufrichtung, statt seitwärts zu schieben.
## Ein Gehzyklus mit vor und zurück schwingenden Beinen sieht bei
## Seitwärtsbewegung sofort falsch aus — das Auge erkennt es, ohne dass man
## benennen könnte, was stört.
func _process(delta: float) -> void:
	if _animation == null:
		return

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
	if health == null:
		return label_text
	if health.is_dead:
		return "%s\nTOT (%d)" % [label_text, _hits]

	var broken := 0
	for part: HealthSystem.Part in VERTICAL:
		if health.is_destroyed(part):
			broken += 1

	if _hits == 0:
		return label_text
	if broken == 0:
		return "%s\n%.0f TP (%d)" % [label_text, health.get_total_hp(), _hits]
	return "%s\n%.0f TP (%d), %d ab" % [label_text, health.get_total_hp(), _hits, broken]


## Was gerade mit der Figur los ist, als Zeile fürs HUD.
func describe() -> String:
	if health == null:
		return label_text
	if health.is_dead:
		return "%s: TOT nach %d Treffern" % [label_text, _hits]

	var broken: Array[String] = []
	for part: HealthSystem.Part in VERTICAL:
		if health.is_destroyed(part):
			broken.append(part_name(part))

	if broken.is_empty():
		return "%s: %.0f TP, %d Treffer" % [label_text, health.get_total_hp(), _hits]
	return "%s: %.0f TP, %d Treffer, ab: %s" % [
		label_text, health.get_total_hp(), _hits, ", ".join(broken)]


func _update_label() -> void:
	if _label == null:
		return
	_label.text = label_lines()
	if health != null and health.is_dead:
		_label.modulate = Color(0.78, 0.30, 0.24)
	else:
		_label.modulate = Color(0.86, 0.88, 0.92)
