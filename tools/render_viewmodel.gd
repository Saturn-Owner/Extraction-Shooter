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
## ALLE SEITEN, nicht nur rechts.
##
## Vorher kamen saemtliche Ansichten von +X. Dadurch waren die Waffen rechts
## ausgearbeitet und links unfertig — Auswurffenster und Ladehebel liegen
## rechts, aber Feuerwahlhebel, Magazinhalter und Verschlussfang sitzen links.
## Was man nie ansieht, baut man auch nicht.
##
## up: Fuer Ansichten von oben und unten muss eine andere Hochachse her,
## sonst faellt die Kamerarechnung auf eine parallele Achse herein.
const VIEWS := [
	{name = "a_perspektive_rechts", dir = Vector3(0.62, 0.34, 0.71), margin = 1.16, focus = "alles", up = Vector3.UP},
	{name = "b_perspektive_links", dir = Vector3(-0.62, 0.34, 0.71), margin = 1.16, focus = "alles", up = Vector3.UP},
	{name = "c_seite_rechts", dir = Vector3(1.0, 0.04, 0.0), margin = 1.12, focus = "alles", up = Vector3.UP},
	{name = "d_seite_links", dir = Vector3(-1.0, 0.04, 0.0), margin = 1.12, focus = "alles", up = Vector3.UP},
	{name = "e_oben", dir = Vector3(0.0, 1.0, 0.02), margin = 1.12, focus = "alles", up = Vector3.FORWARD},
	{name = "f_unten", dir = Vector3(0.0, -1.0, 0.02), margin = 1.12, focus = "alles", up = Vector3.FORWARD},
	{name = "g_vorne", dir = Vector3(0.10, 0.22, -1.0), margin = 1.20, focus = "alles", up = Vector3.UP},
	{name = "h_nah_rechts", dir = Vector3(0.70, 0.34, 0.63), margin = 1.08, focus = "hinten", up = Vector3.UP},
	{name = "i_nah_links", dir = Vector3(-0.70, 0.34, 0.63), margin = 1.08, focus = "hinten", up = Vector3.UP},
]

var _output_dir := ""
var _filter := ""

## Ob die Waffen voll bestueckt gerendert werden.
var _kitted := false
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
	_kitted = args.has("bestueckt")
	if _kitted and _filter == "bestueckt":
		_filter = ""

	ItemRegistry.ensure_loaded()
	_collect_weapons()

	if _jobs.is_empty():
		push_error("Keine passende Waffe gefunden (Filter: '%s')" % _filter)
		quit(1)
		return

	print("Rendere %d Waffen nach: %s" % [_weapons.size(), _output_dir])
	_build_scene()
	_apply_job(0)


## Die Waffen, an denen gerade gearbeitet wird.
##
## Bewusst eine feste Liste und nicht "alle mit eigenem Modell": Die AKM hat
## zwar ein Modell, gehoert aber nicht zum aktuellen Arbeitsstand und liegt
## auch nicht im Inventar. Wer sie mitrendert, bekommt bei jedem Durchlauf
## Bilder, die niemand angefordert hat.
##
## Kommt eine Waffe dazu, hier eintragen.
const IN_ARBEIT := [
	&"weapon_rifle_ar15",
	&"weapon_pistol_g17",
	&"weapon_shotgun_m870",
]


func _collect_weapons() -> void:
	for id in IN_ARBEIT:
		var weapon_data := ItemRegistry.get_item(id) as WeaponData
		if weapon_data == null:
			push_error("Waffe aus IN_ARBEIT nicht gefunden: %s" % id)
			continue
		if not weapon_data.has_own_viewmodel():
			push_error("%s hat kein eigenes Modell" % id)
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


## Alles anbauen, was an diese Waffe passt — je Steckplatz das erste passende
## Teil. Zum Begutachten reicht das: Man sieht auf einen Blick, ob irgendwo
## etwas durchsticht oder in der Luft haengt.
func _full_kit(weapon: WeaponData) -> Dictionary:
	var kit := {}
	for item in ItemRegistry.get_by_category(ItemData.Category.ATTACHMENT):
		var attachment := item as AttachmentData
		if attachment == null or not weapon.accepts_attachment(attachment):
			continue
		if not kit.has(int(attachment.slot)):
			kit[int(attachment.slot)] = attachment.id
	return kit


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
		var weapon_data := _weapons[weapon_index]
		_model = weapon_data.create_viewmodel()
		# Bestueckung MUSS vor add_child() stehen: _ready() baut das Modell,
		# und danach gesetzte Anbauteile kaemen zu spaet.
		_model.weapon_data = weapon_data
		if _kitted:
			_model.attachments = _full_kit(weapon_data)
		_scene.add_child(_model)
		# Ausdruecklich bauen: _ready() laeuft erst im naechsten Frame, der
		# Bildausschnitt wird aber sofort aus den Meshes berechnet. Der
		# _built-Schutz im Viewmodel verhindert, dass dabei doppelt gebaut wird.
		_model.build()
		_model_weapon = weapon_index

	var view: Dictionary = VIEWS[job["view"]]
	var bounds := _model_bounds(_model, view["focus"] == "hinten")
	var centre := bounds.get_center()
	var direction: Vector3 = (view["dir"] as Vector3).normalized()
	var up: Vector3 = view["up"]
	var distance := _fit_distance(bounds, centre, direction, float(view["margin"]), up)
	_camera.look_at_from_position(centre + direction * distance, centre, up)


## Kameraabstand, bei dem die Waffe genau ins Bild passt.
##
## Ueber die Umkugel gerechnet passt zwar alles hinein, aber eine lange
## schmale Waffe fuellt dann nur die Haelfte des Bildes — die Kugel misst die
## Diagonale, nicht das, was man tatsaechlich sieht. Deshalb werden hier die
## acht Ecken des Kastens einzeln in den Kameraraum gelegt und der Abstand
## gesucht, bei dem die aeusserste Ecke gerade noch im Bild liegt. Das
## breitere waagerechte Sichtfeld wird dabei mitgerechnet.
func _fit_distance(bounds: AABB, centre: Vector3, direction: Vector3, margin: float,
		up: Vector3) -> float:
	var basis := Basis.looking_at(-direction, up)
	var right := basis.x
	var camera_up := basis.y
	var forward := -basis.z

	var vertical_tan := tan(deg_to_rad(_camera.fov) * 0.5)
	var horizontal_tan := vertical_tan * (float(SIZE.x) / float(SIZE.y))

	var distance := 0.0
	for i in range(8):
		var corner := bounds.get_endpoint(i) - centre
		# Tiefe der Ecke relativ zur Bildmitte: weiter vorn liegende Ecken
		# brauchen mehr Abstand als weiter hinten liegende.
		var depth := corner.dot(forward)
		distance = maxf(distance, absf(corner.dot(right)) / horizontal_tan - depth)
		distance = maxf(distance, absf(corner.dot(camera_up)) / vertical_tan - depth)

	return maxf(0.05, distance * margin)


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
