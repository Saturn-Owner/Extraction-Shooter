## Bausteine fuer Waffenmodelle.
##
## Reine Werkzeugsammlung ohne eigenen Zustand: Quader, Zylinder, Ringe,
## Materialien. Damit bleibt in den einzelnen Waffendateien nur das stehen,
## was die jeweilige Waffe ausmacht — nicht der immer gleiche Kleinkram.
##
## MATERIALIEN: Alle bewusst mit niedrigem metallic-Wert. Hohe metallic-Werte
## rendern ohne Reflexionsumgebung fast schwarz, waehrend Kunststoff hell
## bleibt — das Ergebnis ist dann genau verkehrt herum. Der Unterschied
## zwischen Metall und Kunststoff kommt hier ueber die Rauheit.
class_name ViewmodelParts
extends RefCounted


## Gemeinsame Materialpalette. Jede Waffe darf eigene ergaenzen, aber diese
## fuenf halten das Arsenal optisch zusammen.
static func materials() -> Dictionary:
	return {
		"steel": _material(Color(0.215, 0.215, 0.232), 0.35, 0.36),
		"black": _material(Color(0.072, 0.072, 0.080), 0.25, 0.45),
		"polymer": _material(Color(0.086, 0.086, 0.092), 0.0, 0.85),
		"furniture": _material(Color(0.105, 0.105, 0.113), 0.08, 0.64),
		"magazine": _material(Color(0.094, 0.099, 0.094), 0.05, 0.72),
		"wood": _material(Color(0.135, 0.082, 0.042), 0.0, 0.72),
		"blued": _material(Color(0.145, 0.148, 0.160), 0.40, 0.28),
	}


static func box(name: String, size: Vector3, pos: Vector3, mat: Material,
		rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return instance(name, mesh, pos, mat, rotation_deg)


## Zylinder. Godot legt sie entlang Y an — fuer Laeufe drehen wir sie um
## 90 Grad, damit sie entlang Z zeigen.
static func cylinder(name: String, radius: float, length: float, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
	return taper(name, radius, radius, length, pos, mat, rotation_deg)


## Konischer Zylinder — fuer Muendungsbremsen und alles, was sich verjuengt.
static func taper(name: String, top_radius: float, bottom_radius: float, length: float,
		pos: Vector3, mat: Material, rotation_deg: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = length
	mesh.radial_segments = 14
	mesh.rings = 1
	return instance(name, mesh, pos, mat, rotation_deg)


## Ring — fuer Lochblenden und Trommeln.
static func torus(name: String, inner: float, outer: float, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 8
	return instance(name, mesh, pos, mat, rotation_deg)


## Leerer Knoten als Drehpunkt fuer bewegliche Teile oder als Markierung.
static func pivot(name: String, pos: Vector3, children: Array = []) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = pos
	for child in children:
		node.add_child(child)
	return node


## Querstege einer Picatinny-Schiene zwischen zwei Z-Positionen.
##
## Wiederholung ist der billigste Weg zu wahrgenommenem Detail: Aus der
## Entfernung liest sich die Zahnung als "modernes Gewehr", obwohl es nur
## ein Dutzend Quader sind.
static func rail(parent: Node3D, prefix: String, from_z: float, to_z: float,
		y: float, mat: Material, width: float = 0.021) -> void:
	var spacing := 0.0115
	var count := int(absf(to_z - from_z) / spacing)
	for i in range(count):
		parent.add_child(box(
			"%sTooth%d" % [prefix, i],
			Vector3(width, 0.007, 0.0062),
			Vector3(0.0, y, from_z - float(i) * spacing - 0.004),
			mat
		))


## Achteckige Roehre aus acht Platten — fuer Handschuetze und Vorderschaefte.
## Kanten in mehreren Winkeln lesen sich als Rundung, ein Kasten nicht.
static func octagon_tube(name: String, radius: float, length: float, center: Vector3,
		mat: Material, panel_width: float = 0.021) -> Node3D:
	var node := Node3D.new()
	node.name = name
	for i in range(8):
		var angle := deg_to_rad(float(i) * 45.0)
		node.add_child(box(
			"Panel%d" % i,
			Vector3(panel_width, 0.007, length),
			Vector3(center.x + sin(angle) * radius, center.y + cos(angle) * radius, center.z),
			mat,
			Vector3(0.0, 0.0, -rad_to_deg(angle))
		))
	return node


static func instance(name: String, mesh: Mesh, pos: Vector3, mat: Material,
		rotation_deg: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation_degrees = rotation_deg
	return node


static func _material(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
