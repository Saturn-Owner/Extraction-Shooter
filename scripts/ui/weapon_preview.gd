## Drehbare 3D-Vorschau der Waffe an der Werkbank.
##
## Baut ihr Modell über GENAU DENSELBEN WEG wie die Waffe in der Hand:
## `WeaponData.create_viewmodel()`, dann `attachments` setzen, dann in den
## Baum hängen. Dadurch *kann* die Vorschau nicht von der echten Waffe
## abweichen — sie ist keine Nachbildung, sondern dasselbe Modell.
##
## Eigene Welt (`own_world_3d`), damit weder das Level in die Vorschau
## hineinleuchtet noch die Vorschaulampen ins Level fallen. Die Beleuchtung
## ist bewusst dieselbe wie im Renderwerkzeug: Was hier gut aussieht, sieht
## auch auf den PNGs gut aus.
class_name WeaponPreview
extends SubViewportContainer

## Wie schnell sich die Waffe dreht (Grad pro Sekunde).
const TURN_SPEED := 22.0

## Etwas Luft um das Modell, sonst klebt es am Bildrand.
const MARGIN := 1.10

## Groesse des Ausschnitts. Breiter als hoch, weil Waffen laenglich sind.
const SIZE := Vector2i(460, 300)

var _viewport: SubViewport
var _camera: Camera3D
var _turntable: Node3D
var _model: WeaponViewmodel = null
var _angle: float = 35.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	stretch = true
	custom_minimum_size = Vector2(SIZE)
	# NICHT in die Breite ziehen lassen. Als Fuellelement wurde der Ausschnitt
	# doppelt so breit wie hoch, und weil dann die Bildhoehe das Einpassen
	# bestimmt, schrumpfte die Waffe auf ein Drittel des Bildes zusammen.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = SIZE
	add_child(_viewport)

	# Der Ausschnitt bekommt seine endgueltige Groesse erst, wenn das Layout
	# steht. Passiert das nach dem Einpassen, stimmt das Seitenverhaeltnis
	# nicht mehr und die Waffe sitzt schief im Bild.
	resized.connect(_on_resized)

	_build_environment()

	_turntable = Node3D.new()
	_turntable.name = "Drehteller"
	_viewport.add_child(_turntable)

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.near = 0.01
	_viewport.add_child(_camera)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.40, 0.44, 0.50)
	sky_material.sky_horizon_color = Color(0.58, 0.61, 0.65)
	sky_material.ground_bottom_color = Color(0.20, 0.21, 0.23)
	sky_material.ground_horizon_color = Color(0.40, 0.41, 0.44)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Metallische Teile brauchen etwas zum Spiegeln, sonst werden sie schwarz.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.85
	environment.ambient_light_energy = 1.1
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.06
	environment.ssao_intensity = 2.5

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	_add_light(Vector3(-0.6, -0.9, -0.45), Color(1.0, 0.97, 0.92), 2.2, true)
	_add_light(Vector3(0.7, -0.2, 0.5), Color(0.72, 0.78, 0.92), 0.5, false)


func _add_light(direction: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	# Ein Viewmodel ist eine Handbreit gross — ohne engen Schattenbereich
	# fallen die Schatten in die Aufloesung eines halben Levels.
	light.directional_shadow_max_distance = 4.0
	light.shadow_normal_bias = 0.4
	_viewport.add_child(light)
	light.look_at_from_position(Vector3.ZERO, direction.normalized(), Vector3.UP)


## Zeigt diese Waffe mit dieser Bestückung.
func show_weapon(weapon_data: WeaponData, attachments: Dictionary) -> void:
	if _model != null:
		_turntable.remove_child(_model)
		_model.queue_free()
		_model = null

	if weapon_data == null:
		return

	_model = weapon_data.create_viewmodel()
	if _model == null:
		return

	# REIHENFOLGE: WeaponViewmodel._ready() baut das Modell. Die Bestückung
	# muss vorher stehen, sonst wird ohne sie gebaut.
	_model.weapon_data = weapon_data
	_model.attachments = attachments.duplicate()
	_turntable.add_child(_model)

	_frame_model()


## Kamera so stellen, dass das ganze Modell ins Bild passt.
##
## Wird nach jedem Umbau neu gerechnet: Ein Schalldämpfer macht die Waffe
## deutlich länger, und ohne Nachrechnen würde die Mündung aus dem Bild
## wandern — ausgerechnet das Teil, das man begutachten will.
func _frame_model() -> void:
	var bounds := _model_bounds(_model)
	var centre := bounds.get_center()

	# Das Modell so verschieben, dass seine Mitte auf der Drehachse liegt.
	# Sonst eiert die Waffe um einen Punkt irgendwo neben sich.
	_model.position = -centre
	_turntable.position = Vector3.ZERO

	var vertical_tan := tan(deg_to_rad(_camera.fov) * 0.5)
	var horizontal_tan := vertical_tan * (float(_viewport.size.x) / float(_viewport.size.y))

	# Beim Drehen kommt jede Seite einmal nach vorn. Gerechnet wird deshalb
	# mit dem Kreis, den die Waffe beim Drehen ueberstreicht — nicht mit der
	# aktuellen Ansicht, sonst passt das Bild in einer Stellung und schneidet
	# in der naechsten ab.
	#
	# Die Raumdiagonale waere dafuer zu grob: Die Hoehe dreht sich gar nicht
	# mit, und sie mitzurechnen hat die Waffe unnoetig weit weggeschoben.
	var swept_radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5
	var half_height := bounds.size.y * 0.5

	# Der vordere Rand des Kreises steht naeher an der Kamera als die Mitte —
	# ohne diesen Zuschlag schneidet die Muendung in der Seitenansicht an.
	var distance := maxf(swept_radius / horizontal_tan, half_height / vertical_tan) + swept_radius

	var direction := Vector3(0.35, 0.22, 1.0).normalized()
	_camera.look_at_from_position(direction * distance * MARGIN, Vector3.ZERO, Vector3.UP)


func _on_resized() -> void:
	if _model != null:
		_frame_model()


func _model_bounds(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_boxes(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE * 0.3)

	var bounds := boxes[0]
	for i in range(1, boxes.size()):
		bounds = bounds.merge(boxes[i])
	return bounds


func _collect_boxes(node: Node, transform: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			boxes.append(transform * mesh_instance.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect_boxes(child, transform * (child as Node3D).transform, boxes)


func _process(delta: float) -> void:
	if _model == null or not visible:
		return
	_angle = fmod(_angle + TURN_SPEED * delta, 360.0)
	_turntable.rotation_degrees.y = _angle
