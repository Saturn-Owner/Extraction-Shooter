## Aufsteigende Schadenszahl an der Trefferstelle.
##
## Reines Entwickler-Werkzeug: Im fertigen Spiel gehören Schadenszahlen
## nicht in einen realistischen Survival-Shooter — sie zerstören die
## Atmosphäre. Zum Abstimmen der Ballistik sind sie aber unverzichtbar,
## weil man sonst nur raten kann, ob ein Treffer wirklich ankam.
##
## Später über eine Einstellung abschaltbar machen, nicht ersatzlos löschen.
class_name DamageNumber
extends Label3D

const LIFETIME := 1.0
const RISE_SPEED := 1.1


## Position wird gemerkt und erst in _ready() gesetzt — global_position
## funktioniert nur bei einem Knoten, der im Szenenbaum haengt.
static func spawn(parent: Node, at: Vector3, result: Ballistics.HitResult) -> DamageNumber:
	var number := DamageNumber.new()
	number._spawn_position = at
	number.setup(result)
	parent.add_child(number)
	return number


var _age: float = 0.0
var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	global_position = _spawn_position


func setup(result: Ballistics.HitResult) -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pixel_size = 0.004
	font_size = 64
	outline_size = 20
	no_depth_test = true

	if not result.was_armored:
		text = "%.0f" % result.damage_to_target
		modulate = Color(1.0, 0.35, 0.3)
	elif result.penetrated:
		text = "%.0f !" % result.damage_to_target
		modulate = Color(1.0, 0.55, 0.2)
	else:
		# Gestoppt: die Zahl in Klammern macht klar, dass die Platte hielt.
		text = "(%.0f)" % result.damage_to_target
		modulate = Color(1.0, 0.88, 0.4)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	global_position.y += RISE_SPEED * delta
	modulate.a = 1.0 - (_age / LIFETIME)
