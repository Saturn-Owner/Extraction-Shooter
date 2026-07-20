## Bausteine fuer Weltgeometrie.
##
## Das Gegenstueck zu ViewmodelParts, nur eine Groessenordnung groeber: Dort
## geht es um Millimeter an einer Waffe, hier um Meter an einer Halle. Deshalb
## KEIN Kantenbruch — bei einem 34 Meter langen Gebaeude sieht man ihn nicht,
## und er kostet das Vierfache an Dreiecken bei hunderten Quadern.
##
## MATERIALIEN: Wie bei den Waffen echte PBR-Werte. Metall braucht eine
## Reflexionsumgebung, sonst rendert es schwarz — jede Szene, die das hier
## benutzt, braucht ein WorldEnvironment mit `ambient_light_source = Sky`.
##
## Warum das ueberhaupt existiert: Weltgeometrie im Code statt in der .tscn.
## Eine grosse Szenendatei laesst sich bei Konflikten nicht mergen, und bei
## zwei Entwicklern an einer Karte waere das eine dauerhafte Konfliktquelle —
## dieselbe Begruendung, die `workbench_station.gd` schon fuer die Werkbank
## angibt.
class_name WorldParts
extends RefCounted

## Kollisionsebene der Welt. Der Spieler tastet danach ab; muss zum bestehenden
## Boden passen, sonst faellt man durch die halbe Karte.
const WORLD_LAYER := 1


## Gemeinsame Palette. Bewusst wenige Farben, damit die Karte zusammenhaelt.
##
## Die Containerfarben sind ausgewaschen, nicht bunt: Ein Hafen im Schnee lebt
## von Grautoenen, und drei kraeftige Farben mitten drin sehen aus wie
## Spielsteine. Sie sollen sich gerade so unterscheiden lassen — genug, um
## "der rote Stapel" sagen zu koennen.
static func materials() -> Dictionary:
	return {
		# korn = wie fein die Struktur ist, tiefe = wie stark sie hervortritt,
		# meter = ueber wie viele Meter sich ein Musterdurchgang zieht.
		"snow": snow_material(),
		"concrete": _surface(Color(0.300, 0.310, 0.330), 0.0, 0.85,
			{korn = 0.18, tiefe = 1.1, meter = 3.0, zellig = false}),
		"steel": _surface(Color(0.340, 0.345, 0.360), 0.90, 0.40,
			{korn = 0.45, tiefe = 0.35, meter = 1.5, zellig = false}),
		# Rost ist fleckig, nicht koernig — deshalb Zellrauschen statt Simplex.
		"rust": _surface(Color(0.240, 0.140, 0.095), 0.20, 0.90,
			{korn = 0.12, tiefe = 1.6, meter = 2.5, zellig = true}),
		"wood": _surface(Color(0.205, 0.140, 0.080), 0.0, 0.92,
			{korn = 0.30, tiefe = 0.9, meter = 2.0, zellig = false}),
		"dark": _surface(Color(0.090, 0.095, 0.105), 0.0, 0.80,
			{korn = 0.35, tiefe = 0.5, meter = 2.0, zellig = false}),
		# Die Container kommen aus container_materials() — sie tragen ein
		# echtes Modell mit eigenen UVs und brauchen weder Triplanar noch
		# prozedurales Rauschen.
		# Wasser: feine, weite Wellen. Kaum Rauigkeitsstreuung, sonst verliert
		# es den Spiegel — und ohne Spiegelung sieht Wasser aus wie Linoleum.
		"water": _surface(Color(0.360, 0.430, 0.480), 0.10, 0.20,
			{korn = 0.09, tiefe = 0.35, meter = 5.0, zellig = false, streuung = 0.06}),
		# Hafenkraene sind gelb, und zwar ueberall auf der Welt. Das ist hier
		# nicht Dekoration: Gelb ist die einzige Farbe auf der Karte, die weder
		# Schnee noch Container noch Beton ist — damit taugt sie als Wegmarke.
		"yellow": _surface(Color(0.620, 0.480, 0.110), 0.40, 0.55,
			{korn = 0.30, tiefe = 0.5, meter = 1.5, zellig = false}),
		"asphalt": _surface(Color(0.175, 0.180, 0.190), 0.0, 0.88,
			{korn = 0.55, tiefe = 1.0, meter = 1.2, zellig = false}),
	}.merged(container_materials())


## Die Containerfarben in fester Reihenfolge — damit ein Stapel an derselben
## Stelle immer gleich aussieht und als Orientierungspunkt taugt.
static func container_colors() -> Array[String]:
	return ["container_red", "container_blue", "container_green",
		"container_yellow", "container_grey"]


# ---------------------------------------------------------------------------
# Schnee
# ---------------------------------------------------------------------------

const SNOW_DIR := "res://assets/textures/snow"

## Ueber wie viele Meter sich ein Durchgang der Schneetextur zieht.
##
## Vier Meter: Gross genug, dass man die Kachelung auf einer 330 m langen
## Flaeche nicht als Muster liest, klein genug, dass die Struktur beim
## Hinuntersehen nicht zu Brei wird. Der Wert ist zum Drehen da.
const SNOW_METRES := 4.0


## Der Boden. Die groesste Flaeche der Karte — und die einzige, bei der eine
## echte Fototextur mehr bringt als jedes prozedurale Rauschen.
##
## Triplanar in Weltkoordinaten ist hier nicht Kuer, sondern Pflicht: Die
## Landflaechen sind bis zu 330 m lang. Nach den UV-Koordinaten der Mesh
## gemappt waere ein Durchgang 330 m breit — also gar keine Struktur mehr,
## nur ein ausgeschmierter Farbverlauf.
##
## Ohne die Texturen faellt es auf prozedurales Rauschen zurueck. Ein frischer
## Clone soll spielbar sein, nicht rot blinken.
static func snow_material() -> BaseMaterial3D:
	if not ResourceLoader.exists("%s/snow_color.jpg" % SNOW_DIR):
		return _surface(Color(0.840, 0.870, 0.900), 0.0, 0.95,
			{korn = 0.05, tiefe = 0.5, meter = 6.0, zellig = false})

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("%s/snow_color.jpg" % SNOW_DIR)

	mat.normal_enabled = true
	# NormalGL, nicht NormalDX: Godot erwartet die OpenGL-Ausrichtung, bei der
	# der Gruenkanal nach oben zeigt. Mit der DirectX-Fassung waeren alle
	# Diese Dellen Buckel und alle Buckel Dellen — es faellt kaum auf und sieht
	# trotzdem dauerhaft falsch aus.
	mat.normal_texture = load("%s/snow_normal.jpg" % SNOW_DIR)
	mat.normal_scale = 1.0

	mat.roughness_texture = load("%s/snow_roughness.jpg" % SNOW_DIR)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE

	mat.ao_enabled = true
	mat.ao_texture = load("%s/snow_ao.jpg" % SNOW_DIR)
	mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE

	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / SNOW_METRES

	return mat


# ---------------------------------------------------------------------------
# Das Containermodell
#
# Lucas' eigener Entwurf, aus tools/build_container.gd. Die Mesh hat zwei
# Flaechen: der Anstrich (0) und der dunkle Stahlrahmen (1). So faerbt jeder
# Container seinen Anstrich um, waehrend der Rahmen immer dunkel bleibt.
# ---------------------------------------------------------------------------

const CONTAINER_MESH := "res://assets/models/world/container.res"


## Masse wie ein 20-Fuss-Container, gerundet auf unser 0,2-m-Raster: L x H x W.
##
## BEWUSST RASTERFREUNDLICH statt masszahlengetreu. Echt waeren es 6,058 x
## 2,591 x 2,438 — lauter krumme Zahlen, an denen zwei Container im Editor
## nie buendig zusammenkommen. 6,0 x 2,6 x 2,4 geht restlos in 0,2 m auf.
const CONTAINER_SIZE := Vector3(6.0, 2.6, 2.4)


## Der Anstrich in fuenf Farben. Der Rahmen ist immer derselbe.
##
## Die Farben sind kraeftig gewaehlt: Im Schnee, unter grauem Himmel, saufen
## zurueckhaltende Toene ab. Das Blau ist Lucas' Originalfarbe aus dem Entwurf
## (#2f6b8f), die anderen dazu abgestimmt.
static func container_materials() -> Dictionary:
	return {
		"container_red": _paint_material(Color(0.62, 0.17, 0.14)),
		"container_blue": _paint_material(Color(0.184, 0.42, 0.56)),
		"container_green": _paint_material(Color(0.20, 0.44, 0.26)),
		"container_yellow": _paint_material(Color(0.80, 0.60, 0.13)),
		"container_grey": _paint_material(Color(0.55, 0.57, 0.60)),
	}


## Das gemeinsame Rahmenmaterial — dunkler Stahl, aus dem Entwurf.
##
## Einmal erzeugt und geteilt: Sonst haette jeder der vierhundert Container sein
## eigenes, identisches Rahmenmaterial im Speicher.
static var _frame_material: StandardMaterial3D = null

static func container_frame_material() -> StandardMaterial3D:
	if _frame_material == null:
		_frame_material = _material(Color(0.29, 0.30, 0.32), 0.40, 0.60)
	return _frame_material


## Ob das Modell ueberhaupt da ist. Ohne faellt container() auf einen Quader
## zurueck, statt rot zu blinken.
static func has_container_model() -> bool:
	return ResourceLoader.exists(CONTAINER_MESH)


## Werte aus dem Entwurf: rauer, halbmatter Anstrich mit etwas Metallglanz.
static func _paint_material(tint: Color) -> StandardMaterial3D:
	return _material(tint, 0.25, 0.78)


## Ein Festkoerper: Mesh und Kollision in einem Knoten.
##
## Der haeufigste Baustein ueberhaupt. Wer nur die Mesh nimmt, baut Kulissen,
## durch die man hindurchlaeuft — und das faellt erst im Spiel auf.
static func solid(node_name: String, size: Vector3, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = rotation_deg
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0

	var mesh := BoxMesh.new()
	mesh.size = size

	var view := MeshInstance3D.new()
	view.name = "Mesh"
	view.mesh = mesh
	view.material_override = mat
	body.add_child(view)

	var shape := BoxShape3D.new()
	shape.size = size

	var collider := CollisionShape3D.new()
	collider.name = "Kollision"
	collider.shape = shape
	body.add_child(collider)

	return body


## Eine flache Flaeche OHNE Kollision — Strassen, Gleise, Wasseroberflaeche.
##
## Bewusst ohne Kollision: Eine Strasse ist nur Farbe auf dem Boden. Als
## Festkoerper waere sie eine zwei Zentimeter hohe Kante, an der man beim
## Darueberlaufen haengenbleibt — und sowas sucht man stundenlang.
static func flat(node_name: String, size: Vector2, pos: Vector3,
		mat: Material, rotation_deg: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.04, size.y)

	var view := MeshInstance3D.new()
	view.name = node_name
	view.mesh = mesh
	view.material_override = mat
	view.position = pos
	view.rotation_degrees = Vector3(0.0, rotation_deg, 0.0)
	return view


## Eine begehbare Rampe.
##
## `rise` ist der Hoehenunterschied, `run` die Strecke am Boden. Daraus faellt
## der Winkel — man denkt beim Bauen in "von hier bis dort hoch", nicht in Grad.
##
## `pos` ist der FUSS der Rampe, mittig auf ihrer Breite. Damit setzt man sie
## dorthin, wo man sie betritt, statt ihren Schwerpunkt auszurechnen.
##
## Godots Standardgrenze fuer begehbaren Boden liegt bei 45 Grad. Wer hier
## steiler baut, bekommt eine Wand, die aussieht wie eine Rampe — der
## unangenehmste Fehler, weil man ihn erst davorstehend bemerkt.
static func ramp(node_name: String, rise: float, run: float, width: float,
		foot: Vector3, mat: Material, facing_deg: float = 0.0) -> StaticBody3D:
	var length := sqrt(rise * rise + run * run)
	var angle := rad_to_deg(atan2(rise, run))

	# Die Rampe ist ein flacher Quader, gekippt um seine Mitte. Deshalb liegt
	# ihr Mittelpunkt auf halber Hoehe und halber Strecke vor dem Fuss.
	var forward := Vector3(sin(deg_to_rad(facing_deg)), 0.0, cos(deg_to_rad(facing_deg)))
	var centre := foot + forward * (run * 0.5) + Vector3(0.0, rise * 0.5, 0.0)

	var body := solid(node_name, Vector3(width, THICKNESS, length), centre, mat,
		Vector3(0.0, facing_deg, 0.0))
	# Erst um die Hochachse ausrichten, dann kippen — in dieser Reihenfolge,
	# sonst kippt sie um die falsche Achse.
	body.rotation_degrees = Vector3(-angle, facing_deg, 0.0)
	return body


## Dicke einer Rampenplatte. Duenn genug, dass man am Fuss nicht anstoesst.
const THICKNESS := 0.30


## Ein Seecontainer.
##
## Als ein Aufruf, weil das Containerfeld aus dutzenden besteht und jeder von
## Hand gebaute drei Zeilen kosten wuerde, die alle gleich aussehen.
##
## KOLLISION BLEIBT EIN QUADER, auch wenn die Mesh geriffelt ist. Zwei Gruende:
## Ein Quader ist um Groessenordnungen billiger als eine Dreiecksform bei
## vierhundert Containern — und an jeder Rippe haengenzubleiben waere im
## Gefecht das Letzte, was man braucht.
##
## `mat` faerbt nur den ANSTRICH (Flaeche 0). Der Rahmen (Flaeche 1) bekommt
## immer das dunkle Stahlmaterial — deshalb wird nicht material_override
## gesetzt (das faerbte alles gleich), sondern je Flaeche einzeln.
static func container(node_name: String, pos: Vector3, mat: Material,
		facing_deg: float = 0.0) -> StaticBody3D:
	# Ohne Modell bleibt der Quader. Ein frischer Clone soll spielbar sein.
	if not has_container_model():
		return solid(node_name, CONTAINER_SIZE,
			pos + Vector3(0.0, CONTAINER_SIZE.y * 0.5, 0.0), mat,
			Vector3(0.0, facing_deg, 0.0))

	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos + Vector3(0.0, CONTAINER_SIZE.y * 0.5, 0.0)
	body.rotation_degrees = Vector3(0.0, facing_deg, 0.0)
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0

	var mesh: Mesh = load(CONTAINER_MESH)
	var view := MeshInstance3D.new()
	view.name = "Mesh"
	view.mesh = mesh
	view.set_surface_override_material(0, mat)
	view.set_surface_override_material(1, container_frame_material())
	body.add_child(view)

	var shape := BoxShape3D.new()
	shape.size = CONTAINER_SIZE

	var collider := CollisionShape3D.new()
	collider.name = "Kollision"
	collider.shape = shape
	body.add_child(collider)

	return body


## Ein Stapel Container uebereinander, von unten nach oben.
## Gibt den Knoten zurueck, der sie alle enthaelt.
static func container_stack(node_name: String, pos: Vector3, height: int,
		mats: Dictionary, facing_deg: float = 0.0, colour_seed: int = 0) -> Node3D:
	var group := Node3D.new()
	group.name = node_name

	var colours := container_colors()
	for level in range(maxi(1, height)):
		var colour: String = colours[(colour_seed + level) % colours.size()]
		group.add_child(container("Ebene%d" % level, pos
			+ Vector3(0.0, float(level) * CONTAINER_SIZE.y, 0.0),
			mats[colour], facing_deg))

	return group


## Ein Gebaeude als vier Waende, Dach und Aussparungen fuer die Zugaenge.
##
## `openings` sind Loecher in der Wand, angegeben als
## {side = "sued"/"nord"/"ost"/"west", offset = float, width = float}.
## Eine Wand mit Loch entsteht als zwei Wandstuecke links und rechts davon —
## ohne Boolesche Operationen geht es nicht anders, und fuer ein Tor genuegt es.
static func building(node_name: String, size: Vector3, pos: Vector3,
		mat: Material, roof_mat: Material, openings: Array) -> Node3D:
	var group := Node3D.new()
	group.name = node_name

	var half := Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.5)

	# Zwei Waende laufen in X (Nord und Sued), zwei in Z (Ost und West).
	# Die Z-Waende werden um die Wandstaerke gekuerzt, damit sich in den Ecken
	# nichts ueberlappt — sonst flackern dort zwei Flaechen ineinander.
	_add_wall(group, "Sued", "sued", Vector3(size.x, size.y, WALL),
		pos + Vector3(0.0, half.y, half.z), true, size.x, mat, openings)
	_add_wall(group, "Nord", "nord", Vector3(size.x, size.y, WALL),
		pos + Vector3(0.0, half.y, -half.z), true, size.x, mat, openings)
	_add_wall(group, "Ost", "ost", Vector3(WALL, size.y, size.z - WALL * 2.0),
		pos + Vector3(half.x, half.y, 0.0), false, size.z - WALL * 2.0, mat, openings)
	_add_wall(group, "West", "west", Vector3(WALL, size.y, size.z - WALL * 2.0),
		pos + Vector3(-half.x, half.y, 0.0), false, size.z - WALL * 2.0, mat, openings)

	group.add_child(solid("Dach", Vector3(size.x, WALL, size.z),
		pos + Vector3(0.0, size.y, 0.0), roof_mat))

	return group


## Wandstaerke fuer Gebaeude.
const WALL := 0.4


## Baut eine Wandseite — am Stueck oder mit Loechern.
static func _add_wall(group: Node3D, node_name: String, side: String,
		size: Vector3, centre: Vector3, runs_in_x: bool, span: float,
		mat: Material, openings: Array) -> void:
	var holes: Array[Dictionary] = []
	for opening: Dictionary in openings:
		if String(opening.get("side", "")) == side:
			holes.append(opening)

	if holes.is_empty():
		group.add_child(solid(node_name, size, centre, mat))
		return

	# Nach Lage sortieren, dann die Stuecke ZWISCHEN den Loechern bauen.
	holes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("offset", 0.0)) < float(b.get("offset", 0.0)))

	var cursor := -span * 0.5
	var piece := 0

	for hole: Dictionary in holes:
		var hole_width := float(hole.get("width", 3.0))
		var hole_start := float(hole.get("offset", 0.0)) - hole_width * 0.5
		if hole_start > cursor:
			_add_wall_piece(group, "%s%d" % [node_name, piece], size, centre,
				runs_in_x, cursor, hole_start, mat)
			piece += 1
		cursor = maxf(cursor, hole_start + hole_width)

	if cursor < span * 0.5:
		_add_wall_piece(group, "%s%d" % [node_name, piece], size, centre,
			runs_in_x, cursor, span * 0.5, mat)


static func _add_wall_piece(group: Node3D, node_name: String, size: Vector3,
		centre: Vector3, runs_in_x: bool, from: float, to: float,
		mat: Material) -> void:
	var width := to - from
	if width <= 0.01:
		return
	var middle := (from + to) * 0.5

	if runs_in_x:
		group.add_child(solid(node_name, Vector3(width, size.y, size.z),
			centre + Vector3(middle, 0.0, 0.0), mat))
	else:
		group.add_child(solid(node_name, Vector3(size.x, size.y, width),
			centre + Vector3(0.0, 0.0, middle), mat))


static func _material(colour: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


## Wie stark die Rauigkeit vom Rauschen gestreut wird, wenn nichts anderes
## dabeisteht. 0.22 heisst: zwischen 78 % und 100 % des eingestellten Werts.
##
## Bewusst schwach. Eine Oberflaeche, die von matt bis spiegelnd durchschlaegt,
## sieht nicht nach Material aus, sondern nach Fehler — man will nur, dass das
## Licht nicht ueberall exakt gleich bricht.
const ROUGHNESS_SPREAD := 0.22

## Kantenlaenge der erzeugten Rauschbilder. 256 genuegt vollauf: Das Muster
## wird ueber Meter gestreckt, feiner wuerde man nie sehen — und nahtlos
## erzeugen kostet mit der Groesse quadratisch.
const NOISE_SIZE := 256


## Eine Oberflaeche mit Struktur.
##
## ---------------------------------------------------------------------------
## WARUM TRIPLANAR, UND ZWAR IN WELTKOORDINATEN
##
## Diese Karte besteht aus Quadern voellig verschiedener Groesse: ein Container
## ist 6 m lang, ein Schiffsrumpf 120 m, die Kaimauer 330 m. Eine Textur nach
## den UV-Koordinaten des Quaders wuerde auf dem Schiff zu Matsch gezogen und
## auf dem Container zu Briefmarken gestaucht — dieselbe Oberflaeche saehe an
## jedem Objekt anders aus.
##
## `uv1_world_triplanar` projiziert stattdessen nach der Position in der Welt.
## Ein Meter Beton sieht ueberall gleich aus, egal wie gross das Teil ist, und
## keine einzige Mesh braucht UV-Koordinaten. Genau deshalb funktioniert das
## hier mit blossen BoxMeshes.
##
## ---------------------------------------------------------------------------
## WAS DAS RAUSCHEN TUT
##
## Es faerbt NICHT. Die Farbe bleibt, wie sie ist — es streut nur Rauigkeit und
## legt eine Normalenkarte darueber. Das ist der Unterschied zwischen Plastik
## und Material: Plastik bricht das Licht ueberall exakt gleich.
##
## Echte Fototexturen waeren mehr, aber das hier kostet keine einzige Datei,
## keine Lizenzfrage und keinen Speicher im Repo.
static func _surface(colour: Color, metallic: float, roughness: float,
		profile: Dictionary) -> StandardMaterial3D:
	var grain: float = profile.get("korn", 0.25)
	var depth: float = profile.get("tiefe", 1.0)
	var metres: float = profile.get("meter", 2.0)
	var cellular: bool = profile.get("zellig", false)
	var spread: float = profile.get("streuung", ROUGHNESS_SPREAD)

	# Der Sollwert liegt in der Mitte der Streuung, damit die Oberflaeche im
	# Schnitt so rau bleibt, wie sie gedacht war. Ohne das waere alles mit
	# Rauschen systematisch glaenzender als ohne.
	var mat := _material(colour, metallic, minf(1.0, roughness / (1.0 - spread * 0.5)))

	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / maxf(0.01, metres)

	mat.roughness_texture = _noise_texture(grain, cellular, spread)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE

	if depth > 0.01:
		mat.normal_enabled = true
		mat.normal_texture = _noise_texture(grain, cellular, 0.0, true)
		mat.normal_scale = depth

	return mat


## Ein nahtloses Rauschbild.
##
## `spread` klemmt den Wertebereich ein: 0.22 gibt Grauwerte zwischen 0.78 und
## 1.0. Fuer Normalenkarten wird nicht geklemmt — dort will man den vollen Hub,
## sonst bleibt die Oberflaeche flach.
static func _noise_texture(frequency: float, cellular: bool, spread: float,
		as_normal: bool = false) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR if cellular \
		else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5

	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = NOISE_SIZE
	texture.height = NOISE_SIZE
	# Nahtlos, sonst sieht man ueber die ganze Karte hinweg die Kachelgrenzen —
	# und bei 330 Metern Kaimauer waeren das viele.
	texture.seamless = true
	texture.generate_mipmaps = true

	if as_normal:
		texture.as_normal_map = true
		texture.bump_strength = 4.0
		return texture

	if spread > 0.0:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0 - spread, 1.0 - spread, 1.0 - spread))
		ramp.set_color(1, Color.WHITE)
		texture.color_ramp = ramp

	return texture
