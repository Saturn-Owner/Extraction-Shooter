## Rendert die ZIELANSICHT einer Waffe — das, was der Spieler beim Zielen sieht.
##
##   godot --path . --script res://tools/render_sight_picture.gd -- C:\ziel akm
##   godot --path . --script res://tools/render_sight_picture.gd -- C:\ziel akm h=0.083 d=-0.02
##
## Mehrere Paare hintereinander ergeben eine Reihe zum Vergleichen.
##
## WOFUER: Die Zielansicht ist die einzige Ansicht, in der eine Waffe genau
## stimmen muss, und die einzige, die `render_viewmodel.gd` nicht zeigt. Beim
## AKM wurde die Visierhoehe dreimal geraten und dreimal danebengesetzt, weil
## die Rueckmeldung ein Satz im Chat war statt eines Bildes.
##
## Der Aufbau bildet `weapon_view.gd` beim Zielen exakt nach:
##
##   Modell auf (0, -sight_height, -ads_distance), Kamera im Ursprung nach -Z,
##   Bildwinkel `WeaponData.ads_fov` — NICHT die 75 Grad der Spielerkamera.
##
## Wer hier mit 75 Grad rendert, sieht eine Waffe, die im Spiel ganz anders
## im Bild sitzt. Genau daran ist die erste Runde gescheitert.
##
## Die rote Kugel steht weit vorn genau auf der Schussachse. Sitzt sie auf der
## Kornspitze, stimmt die Visierlinie. Sitzt sie daneben, sieht man sofort in
## welche Richtung und um wieviel.
##
## NICHT headless aufrufen: Ohne echtes Renderziel bleiben die Bilder leer.
extends SceneTree

const SIZE := Vector2i(1280, 720)

## Entfernung der Zielkugel. Weit genug, dass sie als Punkt erscheint.
const TARGET_Z := -25.0
const TARGET_RADIUS := 0.11

var _output_dir := ""
var _shots: Array = []
var _index := 0
var _frames := 0

var _scene: Node3D
var _camera: Camera3D
var _model: WeaponViewmodel
var _pose: Node3D
var _label := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Aufruf: -- <zielordner> <waffenkuerzel> [h=.. d=..] ...")
		quit(1)
		return

	_output_dir = args[0]
	var wanted: String = args[1]

	# Ordner selbst anlegen. Sonst schlaegt erst das Speichern fehl, und das
	# steht als beilaeufige Zeile zwischen den Erfolgsmeldungen — man haelt die
	# Bilder fuer geschrieben und wundert sich, dass sie sich nicht aendern.
	DirAccess.make_dir_recursive_absolute(_output_dir)

	ItemRegistry.ensure_loaded()
	var data := _find_weapon(wanted)
	if data == null:
		push_error("Keine Waffe gefunden zu '%s'" % wanted)
		quit(1)
		return

	_build_scene(data)

	# Ohne Vorgabe die eingestellten Werte rendern.
	var pairs := _parse_pairs(args.slice(2))
	if pairs.is_empty():
		pairs.append({h = _model.sight_height, d = _model.ads_distance})
	_shots = pairs

	print("Zielansicht %s — %d Bild(er), Bildwinkel %.1f Grad"
			% [data.display_name, _shots.size(), data.ads_fov])
	_apply(0)


func _find_weapon(wanted: String) -> WeaponData:
	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var data := item as WeaponData
		if data == null or not data.has_own_viewmodel():
			continue
		var probe := data.create_viewmodel()
		var hit := probe.get_model_name().contains(wanted)
		probe.free()
		if hit:
			return data
	return null


## "h=0.083" und "d=-0.02" werden paarweise gesammelt.
## Ein neues h beginnt ein neues Bild; ein d ohne h ergaenzt das laufende.
func _parse_pairs(raw: Array) -> Array:
	var out: Array = []
	var current := {}
	for token in raw:
		var text := String(token)
		var parts := text.split("=")
		if parts.size() != 2:
			continue
		var key := parts[0].strip_edges()
		var value := float(parts[1])
		if current.has(key):
			out.append(current)
			current = {}
		current[key] = value
	if not current.is_empty():
		out.append(current)
	return out


func _build_scene(data: WeaponData) -> void:
	_scene = Node3D.new()
	get_root().add_child(_scene)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	light.light_energy = 1.5
	_scene.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-14.0, 152.0, 0.0)
	fill.light_energy = 0.5
	_scene.add_child(fill)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.68, 0.74)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.74, 0.8)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	_scene.add_child(env)

	# Die Zielkugel auf der Schussachse — der Massstab fuer "stimmt die Linie".
	var target := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = TARGET_RADIUS
	sphere.height = TARGET_RADIUS * 2.0
	target.mesh = sphere
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.12, 0.12)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target.material_override = red
	target.position = Vector3(0.0, 0.0, TARGET_Z)
	_scene.add_child(target)

	_camera = Camera3D.new()
	_camera.fov = data.ads_fov
	# Dieselbe Nahgrenze wie die Spielerkamera in scenes/player/player.tscn.
	# Wer hier kleiner rechnet, sieht das Modell vollstaendig und uebersieht,
	# dass das Spiel alles unter fuenf Zentimetern wegschneidet — bei einer
	# Waffe, die beim Zielen dicht ans Auge kommt, ist genau das der Punkt.
	_camera.near = 0.05
	_camera.position = Vector3.ZERO
	_camera.rotation = Vector3.ZERO
	_scene.add_child(_camera)
	_camera.make_current()

	_pose = Node3D.new()
	_scene.add_child(_pose)

	_model = data.create_viewmodel()
	# Selbst bauen statt auf _ready() zu warten: In _initialize() steht der
	# Baum noch nicht, _ready() liefe erst nach dem ersten Bild — bis dahin
	# waeren sight_height und ads_distance noch die Grundwerte aus
	# WeaponViewmodel und nicht die dieser Waffe.
	_model.build()
	_pose.add_child(_model)

	get_root().size = SIZE
	get_root().transparent_bg = false


func _apply(index: int) -> void:
	_index = index
	var shot: Dictionary = _shots[index]
	var height: float = shot.get("h", _model.sight_height)
	var distance: float = shot.get("d", _model.ads_distance)

	# Genau die Zeile aus weapon_view.gd, die beim Zielen zaehlt.
	_pose.position = Vector3(0.0, -height, -distance)

	_label = "h%+.4f_d%+.4f" % [height, distance]
	print("  %s" % _label)
	_frames = 0


func _process(_delta: float) -> bool:
	_frames += 1
	# Ein paar Bilder verstreichen lassen, sonst fehlen Licht und Texturen.
	if _frames < 4:
		return false

	var image := get_root().get_texture().get_image()
	_draw_crosshair(image)
	var path := "%s/zielansicht_%s.png" % [_output_dir, _label]
	if image.save_png(path) == OK:
		print("  geschrieben: %s" % path)
	else:
		push_error("Konnte nicht schreiben: %s" % path)

	if _index + 1 < _shots.size():
		_apply(_index + 1)
		return false

	quit(0)
	return true


## Markiert die Bildmitte — dorthin fliegt die Kugel.
##
## Ohne Marke schaetzt man die Mitte, und beim Schaetzen verrutscht sie in die
## Richtung, in die man das Ergebnis gern haette. Die Linien lassen in der
## Mitte eine Luecke, damit sie das Korn nicht verdecken.
func _draw_crosshair(image: Image) -> void:
	var mid := Vector2i(image.get_width() / 2, image.get_height() / 2)
	var colour := Color(1.0, 0.25, 0.85)
	const GAP := 14
	const ARM := 70
	for offset in range(GAP, ARM):
		for step in [-offset, offset]:
			image.set_pixel(mid.x + step, mid.y, colour)
			image.set_pixel(mid.x, mid.y + step, colour)
