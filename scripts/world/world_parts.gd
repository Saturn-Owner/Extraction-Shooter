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
		"snow": _material(Color(0.840, 0.870, 0.900), 0.0, 0.95),
		"concrete": _material(Color(0.300, 0.310, 0.330), 0.0, 0.85),
		"steel": _material(Color(0.340, 0.345, 0.360), 0.90, 0.40),
		"rust": _material(Color(0.240, 0.140, 0.095), 0.20, 0.90),
		"wood": _material(Color(0.205, 0.140, 0.080), 0.0, 0.92),
		"dark": _material(Color(0.090, 0.095, 0.105), 0.0, 0.80),
		"container_red": _material(Color(0.320, 0.130, 0.115), 0.30, 0.75),
		"container_blue": _material(Color(0.130, 0.190, 0.270), 0.30, 0.75),
		"container_green": _material(Color(0.145, 0.215, 0.160), 0.30, 0.75),
		"container_grey": _material(Color(0.250, 0.255, 0.265), 0.30, 0.78),
	}


## Die Containerfarben in fester Reihenfolge — damit ein Stapel an derselben
## Stelle immer gleich aussieht und als Orientierungspunkt taugt.
static func container_colors() -> Array[String]:
	return ["container_red", "container_blue", "container_green", "container_grey"]


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


## Ein Seecontainer. Masse wie ein 20-Fuss-Container.
##
## Als ein Aufruf, weil das Containerfeld aus dutzenden besteht und jeder von
## Hand gebaute drei Zeilen kosten wuerde, die alle gleich aussehen.
const CONTAINER_SIZE := Vector3(6.06, 2.59, 2.44)


static func container(node_name: String, pos: Vector3, mat: Material,
		facing_deg: float = 0.0) -> StaticBody3D:
	return solid(node_name, CONTAINER_SIZE,
		pos + Vector3(0.0, CONTAINER_SIZE.y * 0.5, 0.0), mat,
		Vector3(0.0, facing_deg, 0.0))


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
