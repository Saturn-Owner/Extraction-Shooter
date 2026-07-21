## Drehbare 3D-Vorschau der Spielerfigur im Hauptmenü.
##
## Baut denselben Weg wie WeaponPreview (siehe scripts/ui/weapon_preview.gd):
## eigene Welt, eigene Beleuchtung, automatisches Einpassen der Kamera.
##
## PLATZHALTER-FIGUR: Es gibt noch kein Charaktermodell im Projekt (siehe
## CharacterWindow — dort wird die Figur aus demselben Grund nur gezeichnet,
## nicht als 3D-Modell gezeigt). Die Klötze hier sind bewusst grob, wie
## GenericViewmodel bei Waffen ohne eigenes Modell: eine Notlösung, die
## sichtbar macht, wo später ein echtes Modell hingehört, statt einen leeren
## Ausschnitt zu zeigen.
class_name CharacterPreview
extends SubViewportContainer

## Grad pro Sekunde. Langsamer als WeaponPreview — hier soll man die Silhouette
## erkennen, nicht ein Detail begutachten.
const TURN_SPEED := 14.0

const MARGIN := 1.25
const SIZE := Vector2i(520, 640)

## Grobe Körpermaße in Metern, Füße auf y = 0.
const HEIGHT := 1.80
const HEAD_SIZE := Vector3(0.20, 0.22, 0.20)
const TORSO_SIZE := Vector3(0.36, 0.52, 0.20)
const ARM_SIZE := Vector3(0.11, 0.50, 0.11)
const LEG_SIZE := Vector3(0.16, 1.05, 0.16)

var _viewport: SubViewport
var _camera: Camera3D
var _turntable: Node3D
var _angle: float = 35.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	stretch = true
	custom_minimum_size = Vector2(SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = SIZE
	add_child(_viewport)

	resized.connect(_on_resized)

	_build_environment()

	_turntable = Node3D.new()
	_turntable.name = "Drehteller"
	_viewport.add_child(_turntable)
	_build_placeholder_figure()

	_camera = Camera3D.new()
	_camera.fov = 32.0
	_camera.near = 0.01
	_viewport.add_child(_camera)

	_frame_figure()


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.10, 0.12, 0.11)
	sky_material.sky_horizon_color = Color(0.20, 0.22, 0.19)
	sky_material.ground_bottom_color = Color(0.05, 0.05, 0.05)
	sky_material.ground_horizon_color = Color(0.14, 0.15, 0.13)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.8
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	_add_light(Vector3(-0.5, -0.9, -0.35), Color(0.85, 0.90, 0.80), 1.8, true)
	_add_light(Vector3(0.7, -0.15, 0.6), Color(0.45, 0.55, 0.60), 0.6, false)


func _add_light(direction: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.directional_shadow_max_distance = 4.0
	light.shadow_normal_bias = 0.4
	_viewport.add_child(light)
	light.look_at_from_position(Vector3.ZERO, direction.normalized(), Vector3.UP)


## Kopf, Rumpf, Arme, Beine — dieselbe grobe Aufteilung wie die sieben
## Rechtecke in CharacterWindow (scripts/ui/character_window.gd), nur in 3D.
func _build_placeholder_figure() -> void:
	var mat: Material = ViewmodelParts.materials()["furniture"]

	var legs_top := LEG_SIZE.y
	var torso_top := legs_top + TORSO_SIZE.y
	var head_centre_y := torso_top + HEAD_SIZE.y * 0.5

	_turntable.add_child(ViewmodelParts.box(
		"Kopf", HEAD_SIZE, Vector3(0.0, head_centre_y, 0.0), mat))
	_turntable.add_child(ViewmodelParts.box(
		"Rumpf", TORSO_SIZE, Vector3(0.0, legs_top + TORSO_SIZE.y * 0.5, 0.0), mat))

	var arm_x := TORSO_SIZE.x * 0.5 + ARM_SIZE.x * 0.5
	var arm_centre_y := legs_top + TORSO_SIZE.y - ARM_SIZE.y * 0.5
	_turntable.add_child(ViewmodelParts.box(
		"ArmLinks", ARM_SIZE, Vector3(-arm_x, arm_centre_y, 0.0), mat))
	_turntable.add_child(ViewmodelParts.box(
		"ArmRechts", ARM_SIZE, Vector3(arm_x, arm_centre_y, 0.0), mat))

	var leg_x := TORSO_SIZE.x * 0.25
	_turntable.add_child(ViewmodelParts.box(
		"BeinLinks", LEG_SIZE, Vector3(-leg_x, legs_top * 0.5, 0.0), mat))
	_turntable.add_child(ViewmodelParts.box(
		"BeinRechts", LEG_SIZE, Vector3(leg_x, legs_top * 0.5, 0.0), mat))


## Kamera so stellen, dass die ganze Figur beim Drehen im Bild bleibt —
## dieselbe Rechnung wie WeaponPreview._frame_model().
func _frame_figure() -> void:
	var centre := Vector3(0.0, HEIGHT * 0.5, 0.0)

	var vertical_tan := tan(deg_to_rad(_camera.fov) * 0.5)
	var horizontal_tan := vertical_tan * (float(_viewport.size.x) / float(_viewport.size.y))

	var swept_radius := maxf(TORSO_SIZE.x, ARM_SIZE.x * 2.0 + TORSO_SIZE.x) * 0.6
	var half_height := HEIGHT * 0.5

	var distance := maxf(swept_radius / horizontal_tan, half_height / vertical_tan) + swept_radius

	var direction := Vector3(0.25, 0.05, 1.0).normalized()
	_camera.look_at_from_position(centre + direction * distance * MARGIN, centre, Vector3.UP)


func _on_resized() -> void:
	if _camera != null:
		_frame_figure()


func _process(delta: float) -> void:
	if not visible:
		return
	_angle = fmod(_angle + TURN_SPEED * delta, 360.0)
	_turntable.rotation_degrees.y = _angle
