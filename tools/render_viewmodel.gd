## Rendert die Waffenmodelle in PNG-Dateien.
##
##   godot --path . --script res://tools/render_viewmodel.gd -- C:\ziel\ordner
##   godot --path . --script res://tools/render_viewmodel.gd -- C:\ziel ar15
##
## Ohne zweites Argument werden alle Waffen gerendert, sonst nur die, deren
## Kurzname passt.
##
## WOFUER: Claude kann Godot-Code schreiben, aber nicht sehen, wie das
## Ergebnis aussieht. Gerenderte Bilder kann Claude dagegen lesen. Damit
## entsteht eine Rueckkopplung — bauen, rendern, anschauen, korrigieren —
## statt bei jeder Proportion nachfragen zu muessen.
##
## Weil jede Waffe ihr eigenes Modell hat, muss auch jede einzeln nachgesehen
## werden. Ein Fehler in der Flinte faellt an der AR-15 nicht auf.
##
## NICHT headless aufrufen: Ohne echtes Renderziel bleiben die Bilder leer.
extends SceneTree

const SIZE := Vector2i(1280, 720)

## Blickrichtungen, nicht feste Positionen.
##
## Vorher standen hier absolute Kamerapunkte, die auf ein Gewehr ausgelegt
## waren, plus ein Streckfaktor aus der Lauflaenge. Bei der Pistole ging das
## schief: Sie hat andere Proportionen als ein Gewehr, war halb aus dem Bild
## und der Griff abgeschnitten. Jetzt wird die tatsaechliche Ausdehnung des
## Modells gemessen und die Kamera daraus gesetzt — das passt fuer jede Waffe,
## auch fuer die acht, die noch kommen.
##
## focus = "hinten" rueckt auf das hintere Stueck: Gehaeuse, Griff, Schaft.
## Genau dort sitzen die Fehler, die man in der Gesamtansicht nicht sieht.
const VIEWS := [
	{name = "perspektive", dir = Vector3(0.62, 0.34, 0.71), margin = 1.18, focus = "alles"},
	{name = "seite", dir = Vector3(1.0, 0.04, 0.0), margin = 1.15, focus = "alles"},
	{name = "nah_gehaeuse", dir = Vector3(0.70, 0.34, 0.63), margin = 1.10, focus = "hinten"},
]

var _output_dir := ""
var _filter := ""
var _frames := 0
var _job_index := 0

var _scene: Node3D
var _camera: Camera3D
var _model: WeaponViewmodel
var _model_weapon := -1

## Jede Aufgabe ist ein Paar aus Waffe und Ansicht.
var _weapons: Array[WeaponData] = []
var _jobs: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_output_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_filter = args[1] if args.size() > 1 else ""

	ItemRegistry.ensure_loaded()
	_collect_weapons()

	if _jobs.is_empty():
		push_error("Keine passende Waffe gefunden (Filter: '%s')" % _filter)
		quit(1)
		return

	print("Rendere %d Waffen nach: %s" % [_weapons.size(), _output_dir])
	_build_scene()
	_apply_job(0)


func _collect_weapons() -> void:
	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var weapon_data := item as WeaponData
		if weapon_data == null:
			continue
		# Platzhalter interessieren beim Ansehen nicht — die sehen alle gleich
		# aus und lenken nur von den echten Modellen ab.
		if not weapon_data.has_own_viewmodel():
			continue
		_weapons.append(weapon_data)

	for i in range(_weapons.size()):
		for v in range(VIEWS.size()):
			_jobs.append({weapon = i, view = v})

	if _filter != "":
		var kept: Array = []
		for job in _jobs:
			var probe := _weapons[job["weapon"]].create_viewmodel()
			if probe.get_model_name().contains(_filter):
				kept.append(job)
			probe.free()
		_jobs = kept


func _build_scene() -> void:
	root.size = SIZE

	_scene = Node3D.new()
	root.add_child(_scene)

	# DIE UMGEBUNG MUSS DER DES SPIELS ENTSPRECHEN.
	#
	# Vorher stand hier ein flacher Farbhintergrund ohne Reflexionsquelle.
	# Metall rendert darin schwarz — und die Materialien wurden daraufhin
	# "korrigiert", bis sie in der Vorschau stimmten und im Spiel falsch waren.
	# Eine Vorschau, die etwas anderes zeigt als das Spiel, ist schlimmer als
	# gar keine. Deshalb hier dieselben Werte wie in testgelaende.tscn.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.52, 0.58, 0.66)
	sky_material.sky_horizon_color = Color(0.78, 0.81, 0.84)
	# Der Standardboden ist braun und faerbt ueber die Himmelsbeleuchtung die
	# ganze Waffe warm ein. Neutral halten, sonst beurteilt man Farben falsch.
	sky_material.ground_bottom_color = Color(0.26, 0.27, 0.29)
	sky_material.ground_horizon_color = Color(0.46, 0.47, 0.50)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(0.75, 0.79, 0.85)
	environment.ambient_light_sky_contribution = 0.85
	environment.ambient_light_energy = 1.1
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Kantenverdunkelung: laesst Spalten und Absaetze hervortreten, die sonst
	# in der gleichmaessigen Himmelsbeleuchtung verschwinden.
	environment.ssao_enabled = true
	environment.ssao_radius = 0.06
	environment.ssao_intensity = 2.5

	var env := WorldEnvironment.new()
	env.environment = environment
	_scene.add_child(env)

	# Eine Sonne mit Schatten wie im Spiel, dazu eine schwache Aufhellung von
	# der Gegenseite, damit die Schattenseite nicht komplett zulaeuft.
	_add_light(Vector3(-0.6, -0.9, -0.45), Color(1.0, 0.97, 0.92), 2.2, true)
	_add_light(Vector3(0.7, -0.2, 0.5), Color(0.72, 0.78, 0.92), 0.5, false)

	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.near = 0.01
	_scene.add_child(_camera)


func _add_light(direction: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	# Ein Viewmodel ist eine Handbreit gross — ohne engen Schattenbereich
	# fallen die Schatten in die Aufloesung des halben Levels und verschwinden.
	light.directional_shadow_max_distance = 4.0
	light.shadow_normal_bias = 0.4
	_scene.add_child(light)
	light.look_at_from_position(Vector3.ZERO, direction.normalized(), Vector3.UP)


## Modell und Kamera fuer eine Aufgabe herrichten.
func _apply_job(index: int) -> void:
	var job: Dictionary = _jobs[index]
	var weapon_index: int = job["weapon"]

	if weapon_index != _model_weapon:
		if _model != null:
			_model.queue_free()
		_model = _weapons[weapon_index].create_viewmodel()
		_scene.add_child(_model)
		_model.build()
		_model_weapon = weapon_index

	var view: Dictionary = VIEWS[job["view"]]
	var bounds := _model_bounds(_model, view["focus"] == "hinten")
	var centre := bounds.get_center()
	# Umkugel des Kastens als Mass, damit die Waffe aus jeder Richtung
	# vollstaendig ins Bild passt.
	var radius: float = maxf(0.02, bounds.size.length() * 0.5)
	var distance: float = radius / tan(deg_to_rad(_camera.fov) * 0.5) * float(view["margin"])
	var direction: Vector3 = (view["dir"] as Vector3).normalized()
	_camera.look_at_from_position(centre + direction * distance, centre, Vector3.UP)


## Ausdehnung des Modells, gemessen an den tatsaechlichen Meshes.
##
## rear_only beschraenkt auf die hintere Haelfte. -Z ist vorne, das hintere
## Ende liegt also bei den groesseren Z-Werten.
func _model_bounds(node: Node3D, rear_only: bool) -> AABB:
	var boxes: Array[AABB] = []
	_collect_boxes(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		push_error("Modell hat keine sichtbaren Meshes")
		return AABB(Vector3.ZERO, Vector3.ONE * 0.1)

	var bounds := boxes[0]
	for i in range(1, boxes.size()):
		bounds = bounds.merge(boxes[i])

	if not rear_only:
		return bounds

	var split := bounds.get_center().z
	return AABB(
		Vector3(bounds.position.x, bounds.position.y, split),
		Vector3(bounds.size.x, bounds.size.y, bounds.end.z - split)
	)


func _collect_boxes(node: Node, transform: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			boxes.append(transform * mesh_instance.mesh.get_aabb())

	for child in node.get_children():
		if child is Node3D:
			_collect_boxes(child, transform * (child as Node3D).transform, boxes)


func _process(_delta: float) -> bool:
	_frames += 1
	# Ein paar Frames warten, sonst ist der Puffer beim ersten Zugriff leer.
	if _frames < 4:
		return false

	var job: Dictionary = _jobs[_job_index]
	var view: Dictionary = VIEWS[job["view"]]
	var path := "%s/%s_%s.png" % [_output_dir, _model.get_model_name(), view["name"]]

	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Konnte %s nicht speichern (Fehler %d)" % [path, error])
	else:
		print("  geschrieben: ", path)

	_job_index += 1
	if _job_index >= _jobs.size():
		return true

	_apply_job(_job_index)
	_frames = 0
	return false
