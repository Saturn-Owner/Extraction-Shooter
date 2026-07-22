## Schiessstand mit vielen Dummys zum Üben im Laufen.
##
## Zweck: KEIN Spielinhalt, sondern eine Werkbank wie `testgelaende.tscn` —
## hier geht es nur um Dummy-Vielfalt: manche stehen, manche laufen auf der
## Stelle, manche fallen beim Sterben gegen eine Wand, manche hängen in der
## Luft und fallen herunter. Siehe `RagdollRig` für das Umfallen/Herunter-
## fallen — ein echtes, von Hand aus elf Kästen und zehn Gelenken gebautes
## Ragdoll (kein Skelett-Ragdoll, das hat `BlockyCharacter` bewusst nicht).
##
## Steuerung:
##   WASD/Shift/Strg/Leertaste   wie im Testgelände
##   Linksklick                  Schiessen
##   R                           Nachladen
##   0                           Zurück zum Start, alle Dummys zurücksetzen
##   Esc                         Maus freigeben
extends Node3D

## Startausrüstung — bewusst nur eine Waffe mit reichlich Munition, hier geht
## es um die Dummys, nicht ums Ausrüstungs-Jonglieren.
const LOADOUT := [
	{id = &"weapon_rifle_akm", count = 1},
	{id = &"ammo_762x39_ps", count = 120},
]

## Wanddicke/-größe für die Wand-Dummys. Mittig auf Brusthöhe, breit und hoch
## genug, dass eine ganze Figur wirklich dagegen fällt statt daran vorbei.
const WALL_SIZE := Vector3(3.6, 3.0, 0.3)

## Wie weit die Wand HINTER der Figur steht (mehr negatives Z, siehe unten).
const WALL_SETBACK := 1.6

## Normal stehende Figuren — patrol_width bleibt 0, das ist schon der
## Normalzustand von HumanoidTarget.
const STANDING_PLACES := [
	Vector3(-6.0, 0.0, -8.0),
	Vector3(7.0, 0.0, -14.0),
	Vector3(-9.0, 0.0, -24.0),
	Vector3(8.0, 0.0, -34.0),
	Vector3(-5.0, 0.0, -46.0),
]

## Auf der Stelle laufende Figuren — siehe run_in_place_speed in
## humanoid_target.gd.
const RUNNING_PLACES := [
	Vector3(2.0, 0.0, -10.0),
	Vector3(-3.0, 0.0, -20.0),
	Vector3(5.0, 0.0, -30.0),
	Vector3(-6.0, 0.0, -40.0),
]

## Wand-Dummys: WELTPOSITION der Figur. Die Wand steht automatisch
## WALL_SETBACK Meter weiter im Minus auf Z — also von der Anlaufrichtung des
## Spielers aus gesehen HINTER der Figur.
const WALL_PLACES := [
	Vector3(10.0, 0.0, -18.0),
	Vector3(-10.0, 0.0, -28.0),
	Vector3(10.0, 0.0, -42.0),
]

## Hängende Figuren: Position samt Höhe über dem Boden.
const HANGING_PLACES := [
	Vector3(-2.0, 1.6, -14.0),
	Vector3(3.0, 1.8, -24.0),
	Vector3(-4.0, 1.7, -36.0),
	Vector3(2.0, 1.6, -46.0),
]

## Wie schnell eine "auf der Stelle laufende" Figur die Beine bewegt.
## PlayerController.SPRINT_SPEED, damit der Gehzyklus deutlich als Laufen zu
## erkennen ist, nicht als gemächliches Gehen.
const RUN_IN_PLACE_SPEED := 4.4

@onready var _player: PlayerController = $Player
@onready var _label: Label = $HUD/DebugPanel/DebugLabel

var _spawn: Vector3
var _humanoids: Array[HumanoidTarget] = []
var _rigs: Array[RagdollRig] = []
var _last_hit := "noch kein Treffer"


func _ready() -> void:
	_spawn = _player.global_position
	_place_standing()
	_place_running()
	_place_wall_dummies()
	_place_hanging_dummies()
	_give_loadout()


## Normal stehende Figuren.
func _place_standing() -> void:
	var container := get_node_or_null("Ziele")
	if container == null:
		return

	var number := 0
	for place in STANDING_PLACES:
		number += 1
		var figure := _make_figure("Steht%02d" % number, "#%d steht" % number)
		_spawn_ragdoll(container, "StehtRig%02d" % number, figure, place)
		_humanoids.append(figure)


## Auf der Stelle laufende Figuren.
func _place_running() -> void:
	var container := get_node_or_null("Ziele")
	if container == null:
		return

	var number := 0
	for place in RUNNING_PLACES:
		number += 1
		var figure := _make_figure("Laeuft%02d" % number, "#%d läuft auf der Stelle" % number)
		figure.run_in_place_speed = RUN_IN_PLACE_SPEED
		_spawn_ragdoll(container, "LaeuftRig%02d" % number, figure, place)
		_humanoids.append(figure)


## Figuren, die mit einer Wand hinter sich stehen — als Hindernis fuer den
## Sturz, nicht als vorgegebene Sturzrichtung.
##
## FRUEHER bekamen sie fall_impulse_dir = (0,0,-1) und wurden damit aktiv
## GEGEN die Wand hinter sich gestossen — sah aus, als schmissen sie sich
## selbst hinein, statt zu fallen. Jetzt fallen sie wie die stehenden Dummys
## ganz normal auf der Stelle (siehe RagdollRig._apply_self_topple()); die
## Wand ist nur noch da, falls eine Figur zufaellig nach hinten kippt.
func _place_wall_dummies() -> void:
	var walls := get_node_or_null("Waende")
	var container := get_node_or_null("Ziele")
	if walls == null or container == null:
		return

	var number := 0
	for place: Vector3 in WALL_PLACES:
		number += 1

		var wall_center := place + Vector3(0.0, WALL_SIZE.y * 0.5, -WALL_SETBACK)
		_build_wall(walls, "Wand%02d" % number, wall_center)

		var figure := _make_figure("Wandfigur%02d" % number, "#%d steht vor der Wand" % number)
		_spawn_ragdoll(container, "WandRig%02d" % number, figure, place)
		_humanoids.append(figure)


## Ein einzelnes Wandstück — aus dem Code, wie die Kisten in testgelaende.tscn
## es früher schon vorgemacht haben.
func _build_wall(parent: Node3D, wall_name: String, centre: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.name = wall_name
	wall.collision_layer = 1
	wall.collision_mask = 0
	parent.add_child(wall)
	wall.global_position = centre

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = WALL_SIZE
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.47, 0.44)
	material.roughness = 0.9
	mesh.material_override = material
	wall.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = WALL_SIZE
	shape.shape = box_shape
	wall.add_child(shape)


## Figuren, die in der Luft hängen und beim Sterben herunterfallen.
##
## fall_impulse_dir bleibt Vector3.ZERO — kein bevorzugtes Kippen, nur der
## freie Fall nach unten zählt (siehe RagdollRig._on_died()).
func _place_hanging_dummies() -> void:
	var container := get_node_or_null("Ziele")
	if container == null:
		return

	var number := 0
	for place: Vector3 in HANGING_PLACES:
		number += 1

		var figure := _make_figure("Haengefigur%02d" % number, "#%d hängt" % number)
		_spawn_ragdoll(container, "HaengeRig%02d" % number, figure, place,
			Vector3.ZERO, false)
		_humanoids.append(figure)


## Haengt eine Figur in ein RagdollRig und stellt beides an ihren Platz —
## JEDER Dummy im Schiessstand bekommt das echte Ragdoll beim Sterben, nicht
## nur die Wand-/Hänge-Varianten.
func _spawn_ragdoll(container: Node3D, rig_name: String, figure: HumanoidTarget,
		place: Vector3, fall_impulse_dir: Vector3 = Vector3.ZERO,
		self_topple_when_standing: bool = true) -> RagdollRig:
	var rig := RagdollRig.new()
	rig.name = rig_name
	rig.fall_impulse_dir = fall_impulse_dir
	rig.self_topple_when_standing = self_topple_when_standing
	container.add_child(rig)
	rig.global_position = place
	rig.attach(figure)
	figure.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	rig.remember_spawn()
	_rigs.append(rig)
	return rig


func _make_figure(node_name: String, label: String) -> HumanoidTarget:
	var figure := HumanoidTarget.new()
	figure.name = node_name
	figure.label_text = label
	figure.part_hit.connect(_on_humanoid_hit.bind(figure))
	return figure


## Füllt das Inventar und nimmt die Waffe in die Hand.
func _give_loadout() -> void:
	var inventory := _player.inventory
	if inventory == null:
		return

	for entry in LOADOUT:
		if not inventory.add(entry.id, entry.count):
			push_error("[Schiessstand] Kein Platz für %s — Raster zu klein" % entry.id)

	var weapons := inventory.get_carried_weapons()
	if not weapons.is_empty():
		_player.equip_from_inventory(weapons[0])


func _on_humanoid_hit(part: HealthSystem.Part, result: Ballistics.HitResult,
		figure: HumanoidTarget) -> void:
	_last_hit = "%s — %s: %s" % [
		figure.label_text, BlockyCharacter.part_name(part), result.describe()]


func _reset_all() -> void:
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO

	# Jeder Dummy steckt in einem RagdollRig — reset() dort bringt die
	# jeweilige Figur gleich mit zurueck.
	for rig in _rigs:
		rig.reset()

	_last_hit = "zurückgesetzt"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	if (event as InputEventKey).physical_keycode == KEY_0:
		_reset_all()


func _process(_delta: float) -> void:
	var lines := [
		"Schiessstand — %d Dummys" % _humanoids.size(),
		"Treffer: %s" % _last_hit,
		"",
		"0 Reset   Esc Maus   R Nachladen",
	]
	_label.text = "\n".join(lines)
