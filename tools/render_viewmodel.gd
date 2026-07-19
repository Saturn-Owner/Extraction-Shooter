## Rendert das Waffenmodell in PNG-Dateien.
##
##   godot --path . --script res://tools/render_viewmodel.gd -- C:\ziel\ordner
##
## WOFUER: Claude kann Godot-Code schreiben, aber nicht sehen, wie das
## Ergebnis aussieht. Gerenderte Bilder kann Claude dagegen lesen. Damit
## entsteht eine Rueckkopplung — bauen, rendern, anschauen, korrigieren —
## statt bei jeder Proportion nachfragen zu muessen.
##
## NICHT headless aufrufen: Ohne echtes Renderziel bleiben die Bilder leer.
extends SceneTree

const SIZE := Vector2i(1280, 720)

## Kameraposition und Blickziel je Ansicht.
const VIEWS := [
	{name = "perspektive", from = Vector3(0.48, 0.26, 0.30), look_at = Vector3(0.0, -0.01, -0.24)},
	{name = "seite", from = Vector3(0.95, 0.02, -0.22), look_at = Vector3(0.0, 0.0, -0.22)},
	{name = "vorne_schraeg", from = Vector3(0.30, 0.18, -0.95), look_at = Vector3(0.0, 0.01, -0.30)},
]

var _output_dir := ""
var _frames := 0
var _view_index := 0
var _model: Node3D
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_output_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	print("Rendere nach: ", _output_dir)

	var window := root
	window.size = SIZE
	# Ohne eigenen Hintergrund steht das Modell vor Schwarz und man sieht
	# an den dunklen Teilen keine Kanten mehr.
	window.transparent_bg = false

	var scene := Node3D.new()
	root.add_child(scene)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.22, 0.23, 0.26)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.48, 0.55)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	scene.add_child(env)

	# Drei Lichter: Hauptlicht von schraeg oben, Aufhellung von der
	# Gegenseite, Kante von hinten. Ohne das dritte verschwindet die
	# Silhouette vor dem Hintergrund.
	_add_light(scene, Vector3(-0.6, -0.8, -0.5), Color(1.0, 0.97, 0.92), 2.6)
	_add_light(scene, Vector3(0.8, -0.3, 0.4), Color(0.6, 0.7, 0.9), 1.1)
	_add_light(scene, Vector3(0.2, 0.6, 0.9), Color(0.9, 0.9, 1.0), 1.4)

	_model = ViewmodelBuilder.build_ar15()
	scene.add_child(_model)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 42.0
	_camera.near = 0.01
	scene.add_child(_camera)
	_apply_view(_camera, 0)


func _add_light(parent: Node3D, direction: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = false
	parent.add_child(light)
	light.look_at_from_position(Vector3.ZERO, direction.normalized(), Vector3.UP)


## look_at() setzt einen Knoten im Baum voraus. Beim Aufbau ist der Baum
## noch nicht bereit, deshalb durchgehend die positionsbasierte Variante.
func _apply_view(camera: Camera3D, index: int) -> void:
	var view: Dictionary = VIEWS[index]
	camera.look_at_from_position(view["from"], view["look_at"], Vector3.UP)


func _process(_delta: float) -> bool:
	_frames += 1
	# Ein paar Frames warten, sonst ist der Puffer beim ersten Zugriff leer.
	if _frames < 4:
		return false

	var image := root.get_texture().get_image()
	var view: Dictionary = VIEWS[_view_index]
	var path := "%s/ar15_%s.png" % [_output_dir, view["name"]]
	var error := image.save_png(path)
	if error != OK:
		push_error("Konnte %s nicht speichern (Fehler %d)" % [path, error])
	else:
		print("  geschrieben: ", path)

	_view_index += 1
	if _view_index >= VIEWS.size():
		return true

	_apply_view(_camera, _view_index)
	_frames = 0
	return false
