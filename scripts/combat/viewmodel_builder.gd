## Baut ein Blockout-Modell der AR-15 aus Godot-Primitiven.
##
## WARUM IM CODE UND NICHT ALS .tscn?
## Szenen lassen sich bei Konflikten praktisch nicht mergen (siehe CLAUDE.md).
## Ein Modell aus ~20 Teilen, an dem beide schrauben, waere eine dauerhafte
## Konfliktquelle. Als Code ist es mergebar, parametrisch und in einer Zeile
## aenderbar.
##
## Das hier ist ausdruecklich ein PLATZHALTER. Sobald ein echtes Modell
## vorliegt, faellt diese Datei weg — weapon_view.gd bleibt unveraendert,
## weil es die Teile ausschliesslich ueber ihre Namen findet.
##
## KOORDINATEN: -Z ist vorne (Blickrichtung), +Y oben, +X rechts.
## Der Ursprung liegt hinten am Gehaeuse, dort wo der Puffer ansetzt.
## Alle Masse in Metern und grob an einer echten AR-15 orientiert.
class_name ViewmodelBuilder
extends RefCounted

## Hoehe der Visierlinie ueber dem Modellursprung.
##
## weapon_view.gd braucht diesen Wert, um die Zielpose auszurechnen: Beim
## Zielen muss die Visierlinie exakt auf die Kameramitte wandern, sonst
## schiesst der Spieler an seinem eigenen Korn vorbei.
const SIGHT_HEIGHT := 0.068

## Wo die Muendung sitzt — Ansatzpunkt fuer Muendungsfeuer.
const MUZZLE_Z := -0.575


## Baut das komplette Modell und gibt den Wurzelknoten zurueck.
static func build_ar15() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"

	var metal := _material(Color(0.13, 0.13, 0.15), 0.85, 0.42)
	var polymer := _material(Color(0.08, 0.08, 0.09), 0.0, 0.78)
	var mag_mat := _material(Color(0.11, 0.13, 0.11), 0.1, 0.65)

	# --- Gehaeuse ---
	root.add_child(_box("UpperReceiver", Vector3(0.038, 0.055, 0.21), Vector3(0.0, 0.020, -0.130), metal))
	root.add_child(_box("LowerReceiver", Vector3(0.032, 0.050, 0.135), Vector3(0.0, -0.022, -0.095), metal))

	# --- Lauf und Handschutz ---
	root.add_child(_box("Handguard", Vector3(0.048, 0.048, 0.190), Vector3(0.0, 0.014, -0.330), polymer))
	root.add_child(_cylinder("Barrel", 0.009, 0.300, Vector3(0.0, 0.014, -0.390), metal))
	root.add_child(_box("GasBlock", Vector3(0.030, 0.034, 0.030), Vector3(0.0, 0.030, -0.432), metal))
	root.add_child(_cylinder("MuzzleDevice", 0.014, 0.052, Vector3(0.0, 0.014, -0.548), metal))

	# --- Visierung ---
	# Kimme und Korn sitzen mit ihrem MITTELPUNKT exakt auf SIGHT_HEIGHT.
	# Nur dann ist die Visierlinie eine Gerade, und nur dann trifft die Waffe
	# beim Zielen wirklich dorthin, wo die Kameramitte hinzeigt.
	# verify_weapon_handling.gd prueft genau das — wer hier etwas verschiebt,
	# bekommt einen roten Test statt eines stillen Zielfehlers.
	root.add_child(_box("RearSight", Vector3(0.024, 0.040, 0.028), Vector3(0.0, SIGHT_HEIGHT, -0.048), metal))
	root.add_child(_box("FrontSight", Vector3(0.012, 0.048, 0.012), Vector3(0.0, SIGHT_HEIGHT, -0.432), metal))

	# --- Schaft und Griff ---
	root.add_child(_cylinder("BufferTube", 0.016, 0.115, Vector3(0.0, 0.018, 0.048), metal))
	root.add_child(_box("Stock", Vector3(0.040, 0.078, 0.130), Vector3(0.0, 0.006, 0.100), polymer))
	root.add_child(_box("PistolGrip", Vector3(0.030, 0.098, 0.042), Vector3(0.0, -0.078, -0.024),
		polymer, Vector3(-22.0, 0.0, 0.0)))
	root.add_child(_box("TriggerGuard", Vector3(0.022, 0.006, 0.058), Vector3(0.0, -0.062, -0.070), metal))

	# --- Bewegliche Teile ---
	# Jedes bekommt einen eigenen Drehpunkt, damit weapon_view.gd es
	# unabhaengig bewegen kann. Der Pivot sitzt dort, wo sich das Teil
	# im echten Leben dreht bzw. verschiebt.
	root.add_child(_pivot("Magazine", Vector3(0.0, -0.048, -0.128), [
		_box("MagBody", Vector3(0.026, 0.150, 0.048), Vector3(0.0, -0.078, 0.006), mag_mat, Vector3(6.0, 0.0, 0.0)),
	]))

	root.add_child(_pivot("Bolt", Vector3(0.020, 0.026, -0.098), [
		_box("BoltFace", Vector3(0.006, 0.030, 0.062), Vector3.ZERO, metal),
	]))

	root.add_child(_pivot("ChargingHandle", Vector3(0.0, 0.046, -0.024), [
		_box("HandleBar", Vector3(0.052, 0.010, 0.040), Vector3.ZERO, metal),
	]))

	root.add_child(_pivot("Trigger", Vector3(0.0, -0.046, -0.072), [
		_box("TriggerBlade", Vector3(0.007, 0.024, 0.008), Vector3(0.0, -0.012, 0.0), metal),
	]))

	root.add_child(_pivot("Selector", Vector3(-0.018, -0.028, -0.052), [
		_cylinder("SelectorLever", 0.007, 0.022, Vector3(-0.008, 0.0, 0.0), metal, Vector3(0.0, 0.0, 90.0)),
		_box("SelectorTip", Vector3(0.020, 0.008, 0.026), Vector3(-0.012, 0.0, 0.010), metal),
	]))

	# --- Markierungspunkte (unsichtbar) ---
	root.add_child(_marker("MuzzlePoint", Vector3(0.0, 0.014, MUZZLE_Z)))
	root.add_child(_marker("EjectPoint", Vector3(0.030, 0.026, -0.098)))

	return root


## Ein Quader mit Material.
static func _box(name: String, size: Vector3, pos: Vector3, mat: Material,
		rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size

	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation_degrees = rotation_deg
	return node


## Ein Zylinder. Godot legt Zylinder entlang Y an — fuer Laeufe drehen wir
## sie um 90 Grad, damit sie entlang Z zeigen.
static func _cylinder(name: String, radius: float, length: float, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12

	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation_degrees = rotation_deg
	return node


## Leerer Knoten als Drehpunkt fuer bewegliche Teile.
static func _pivot(name: String, pos: Vector3, children: Array) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = pos
	for child in children:
		node.add_child(child)
	return node


static func _marker(name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = pos
	return node


static func _material(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
