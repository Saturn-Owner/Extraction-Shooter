## Bausteine fuer Waffenmodelle.
##
## Reine Werkzeugsammlung ohne eigenen Zustand: Quader, Zylinder, Ringe,
## Materialien. Damit bleibt in den einzelnen Waffendateien nur das stehen,
## was die jeweilige Waffe ausmacht — nicht der immer gleiche Kleinkram.
##
## MATERIALIEN: Echte PBR-Werte. Metall bekommt hohe metallic-Werte und eine
## helle Grundfarbe — bei Metall ist die Albedo die Farbe der Spiegelung, nicht
## die Oberflaechenfarbe. Das funktioniert nur, weil das Testgelaende einen
## Himmel als Reflexionsquelle hat (WorldEnvironment, ambient_light_source =
## Sky). Ohne Reflexionsumgebung rendert Metall schwarz — wer eine neue Szene
## ohne Himmel baut, muss das mitbedenken.
class_name ViewmodelParts
extends RefCounted

## Standard-Kantenbruch in Metern.
##
## DER GROESSTE EINZELNE OPTIK-GEWINN: Eine gebrochene Kante fangt Licht in
## einem schmalen Streifen und macht daraus einen Glanzrand. Genau daran
## erkennt das Auge gefertigtes Metall statt eines Klotzes. Ein Wuerfel mit
## scharfen Kanten sieht immer nach Platzhalter aus, egal wie gut das Material
## ist. Kostet knapp das Vierfache an Dreiecken — bei einer Waffe irrelevant.
const BEVEL := 0.0016


## Gemeinsame Materialpalette. Jede Waffe darf eigene ergaenzen, aber diese
## halten das Arsenal optisch zusammen.
static func materials() -> Dictionary:
	return {
		"steel": _material(Color(0.340, 0.345, 0.360), 0.95, 0.34),
		"black": _material(Color(0.145, 0.147, 0.155), 0.88, 0.42),
		# Kunststoff bewusst nicht zu dunkel: Rein rechnerisch waere schwarzes
		# Polymer noch dunkler, aber dann verschwinden Schaft und Griff im
		# Spiel komplett und die Waffe verliert ihre Form.
		"polymer": _material(Color(0.098, 0.098, 0.105), 0.0, 0.50),
		"furniture": _material(Color(0.118, 0.118, 0.126), 0.0, 0.44),
		"magazine": _material(Color(0.170, 0.178, 0.170), 0.80, 0.48),
		"wood": _material(Color(0.205, 0.112, 0.048), 0.0, 0.50),
		"blued": _material(Color(0.215, 0.222, 0.245), 0.96, 0.20),
		# Fuer Schlitze, Nuten und Bohrungen. Ohne Boolesche Operationen kann
		# nichts wirklich ausgeschnitten werden — ein sehr dunkles, mattes
		# Teil buendig in der Oberflaeche liest sich aber als Vertiefung.
		# Metallisch darf es dabei NICHT sein: Metall spiegelt den Himmel und
		# leuchtet dann heller als seine Umgebung, wodurch aus dem Loch eine
		# aufgesetzte Platte wird. Genau so sahen die M-LOK-Schlitze aus.
		"recess": _material(Color(0.018, 0.018, 0.020), 0.0, 0.95),
	}


## Quader mit gebrochenen Kanten.
##
## bevel = 0.0 gibt einen scharfkantigen Quader — nur sinnvoll fuer Teile, die
## ohnehin verdeckt sind. Der Kantenbruch begrenzt sich selbst, damit auch
## duenne Bleche wie Schienenzaehne nicht in sich zusammenfallen.
static func box(name: String, size: Vector3, pos: Vector3, mat: Material,
		rotation_deg: Vector3 = Vector3.ZERO, bevel: float = BEVEL) -> MeshInstance3D:
	var mesh := beveled_box_mesh(size, bevel)
	return instance(name, mesh, pos, mat, rotation_deg)


## Erzeugt einen Quader mit umlaufender Fase.
##
## Aufbau: sechs verkleinerte Flaechen, zwoelf Fasenstreifen an den Kanten,
## acht Dreiecke in den Ecken. Die Ausrichtung der Dreiecke wird nicht von Hand
## festgelegt, sondern hinterher geprueft — der Koerper ist konvex und um den
## Ursprung zentriert, also zeigt jede Normale nach aussen, wenn sie in
## dieselbe Richtung wie der Schwerpunkt des Dreiecks weist. Das ist deutlich
## weniger fehleranfaellig als 44 Dreiecke von Hand richtig herum zu wickeln.
static func beveled_box_mesh(size: Vector3, bevel: float = BEVEL) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	# Fase deutlich kleiner als die duennste Seite.
	#
	# Vorher waren 70 % erlaubt. Bei einem Schienenzahn von 6 mm Tiefe frass
	# die Fase ueber die Haelfte der Materialstaerke — aus einem scharfen Zahn
	# wurde ein weiches Kloesschen, und die ganze Waffe sah rundgelutscht und
	# unfertig aus. Eine Fase soll die Kante brechen, nicht das Teil auffressen:
	# grosse Teile bekommen den vollen Wert, duenne nur einen Bruchteil.
	var b: float = minf(bevel, minf(hx, minf(hy, hz)) * 0.22)

	if b <= 0.0001:
		var plain := BoxMesh.new()
		plain.size = size
		return _to_array_mesh(plain)

	# Je Ecke drei Punkte, einer je angrenzender Flaeche.
	var on_x := func(sx: float, sy: float, sz: float) -> Vector3:
		return Vector3(sx * hx, sy * (hy - b), sz * (hz - b))
	var on_y := func(sx: float, sy: float, sz: float) -> Vector3:
		return Vector3(sx * (hx - b), sy * hy, sz * (hz - b))
	var on_z := func(sx: float, sy: float, sz: float) -> Vector3:
		return Vector3(sx * (hx - b), sy * (hy - b), sz * hz)

	var quads: Array = []
	var tris: Array = []

	for s in [-1.0, 1.0]:
		# Die sechs Hauptflaechen.
		quads.append([on_x.call(s, -1, -1), on_x.call(s, 1, -1), on_x.call(s, 1, 1), on_x.call(s, -1, 1)])
		quads.append([on_y.call(-1, s, -1), on_y.call(1, s, -1), on_y.call(1, s, 1), on_y.call(-1, s, 1)])
		quads.append([on_z.call(-1, -1, s), on_z.call(1, -1, s), on_z.call(1, 1, s), on_z.call(-1, 1, s)])

	for sa in [-1.0, 1.0]:
		for sb in [-1.0, 1.0]:
			# Die zwoelf Fasenstreifen, vier je Achsrichtung.
			quads.append([on_x.call(sa, sb, -1), on_x.call(sa, sb, 1), on_y.call(sa, sb, 1), on_y.call(sa, sb, -1)])
			quads.append([on_x.call(sa, -1, sb), on_x.call(sa, 1, sb), on_z.call(sa, 1, sb), on_z.call(sa, -1, sb)])
			quads.append([on_y.call(-1, sa, sb), on_y.call(1, sa, sb), on_z.call(1, sa, sb), on_z.call(-1, sa, sb)])

	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				# Die acht Eckdreiecke.
				tris.append([on_x.call(sx, sy, sz), on_y.call(sx, sy, sz), on_z.call(sx, sy, sz)])

	for quad in quads:
		tris.append([quad[0], quad[1], quad[2]])
		tris.append([quad[0], quad[2], quad[3]])

	# Flache Normalen: harte Kanten sind bei Metall richtig, weiche wuerden
	# die Fase wieder wegbuegeln. Der Quader ist um den Ursprung zentriert,
	# also ist der Nullpunkt der Innenpunkt fuer die Ausrichtungspruefung.
	return _mesh_from_triangles(tris, Vector3.ZERO)


## Gekruemmter Koerper mit rechteckigem Querschnitt — fuer Magazine.
##
## WARUM NICHT GESTAPELTE QUADER: Genau so war es vorher, und solange die
## Kanten scharf waren, fiel es nicht auf. Mit gebrochenen Kanten faengt jede
## Segmentgrenze Licht und aus der Kruemmung wird eine sichtbare Treppe.
## Ein durchgezogener Koerper hat diese Grenzen nicht.
##
## Der Querschnitt wandert von oben nach unten (-Y) und dreht sich dabei
## schrittweise um die X-Achse nach vorn. Genau so ist ein Stangenmagazin
## gebaut: gleichbleibender Querschnitt entlang eines Kreisbogens.
static func curved_body(name: String, width: float, depth: float, length: float,
		curve_degrees: float, pos: Vector3, mat: Material,
		rotation_deg: Vector3 = Vector3.ZERO, segments: int = 10) -> MeshInstance3D:
	var mesh := curved_body_mesh(width, depth, length, curve_degrees, segments)
	return instance(name, mesh, pos, mat, rotation_deg)


static func curved_body_mesh(width: float, depth: float, length: float,
		curve_degrees: float, segments: int = 10) -> ArrayMesh:
	segments = maxi(1, segments)
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var step_length := length / float(segments)
	var step_angle := deg_to_rad(curve_degrees) / float(segments)

	var profile := [
		Vector3(-half_w, 0.0, -half_d),
		Vector3(half_w, 0.0, -half_d),
		Vector3(half_w, 0.0, half_d),
		Vector3(-half_w, 0.0, half_d),
	]

	var rings: Array = []
	var point := Vector3.ZERO
	var frame := Basis.IDENTITY

	for i in range(segments + 1):
		var ring: Array = []
		for corner in profile:
			ring.append(point + frame * corner)
		rings.append(ring)
		if i < segments:
			point += frame * Vector3(0.0, -step_length, 0.0)
			frame = frame.rotated(Vector3.RIGHT, step_angle)

	var tris: Array = []

	# Mantel: vier Laengsseiten.
	for i in range(segments):
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in range(4):
			var n := (k + 1) % 4
			tris.append([a[k], a[n], b[n]])
			tris.append([a[k], b[n], b[k]])

	# Deckel oben und unten.
	var top: Array = rings[0]
	var bottom: Array = rings[segments]
	tris.append([top[0], top[1], top[2]])
	tris.append([top[0], top[2], top[3]])
	tris.append([bottom[0], bottom[1], bottom[2]])
	tris.append([bottom[0], bottom[2], bottom[3]])

	# Der Koerper ist gekruemmt, also ist der Ursprung kein verlaesslicher
	# Innenpunkt — die Wicklung wird deshalb gegen den Schwerpunkt des
	# gesamten Koerpers geprueft statt gegen den Nullpunkt.
	var centre := Vector3.ZERO
	for ring in rings:
		for corner in ring:
			centre += corner
	centre /= float(rings.size() * 4)

	return _mesh_from_triangles(tris, centre)


## Baut aus einer Dreiecksliste ein Mesh mit flachen Normalen und dreht dabei
## jedes Dreieck nach aussen. Spart es, 100 Dreiecke von Hand richtig herum zu
## wickeln — der haeufigste und am schwersten zu findende Fehler dabei.
static func _mesh_from_triangles(tris: Array, centre: Vector3) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()

	for tri in tris:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var normal := (b - a).cross(c - a)
		# Schwelle sehr niedrig ansetzen. Das Kreuzprodukt waechst mit dem
		# QUADRAT der Kantenlaenge: Bei einer Fase von 0,4 mm sind die acht
		# Eckdreiecke voellig in Ordnung, ihr Kreuzprodukt liegt aber schon bei
		# 2e-7. Mit einer zu groben Schwelle fliegen genau diese Dreiecke raus
		# und der Koerper bekommt acht Loecher in den Ecken.
		if normal.length_squared() < 1e-20:
			continue
		normal = normal.normalized()
		if normal.dot((a + b + c) / 3.0 - centre) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal

		# UMLAUFRICHTUNG, NICHT NORMALE: Godot entscheidet ueber Vorder- und
		# Rueckseite anhand der Reihenfolge der Eckpunkte, die Normale dient
		# nur der Beleuchtung. Godots eigene Meshes sind so gewickelt, dass
		# (b-a) x (c-a) der Normalen ENTGEGEN zeigt — deshalb hier b und c
		# vertauscht ausgeben.
		#
		# Vorher stimmten die Normalen, aber die Wicklung war spiegelverkehrt:
		# Jede zugewandte Flaeche wurde weggeschnitten und man sah von aussen
		# ins Innere der Waffe. Im Spiel blickt man auf die linke Seite der
		# Waffe, und genau dort fiel es auf.
		#
		# verify_weapon_handling prueft das gegen einen echten Godot-BoxMesh,
		# damit hier niemand eine Konvention aus der Doku abschreiben und
		# hoffen muss.
		vertices.append(a)
		vertices.append(c)
		vertices.append(b)
		for i in range(3):
			normals.append(normal)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _to_array_mesh(source: PrimitiveMesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.get_mesh_arrays())
	return mesh


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
	# Laeufe und Rohre sind das Runde an einer Waffe. Mit 14 Segmenten sieht
	# man die Facetten, mit 24 nicht mehr — und ein paar hundert Dreiecke mehr
	# fallen bei einem Viewmodel nicht ins Gewicht.
	mesh.radial_segments = 24
	mesh.rings = 1
	return instance(name, mesh, pos, mat, rotation_deg)


## Ring — fuer Lochblenden und Trommeln.
static func torus(name: String, inner: float, outer: float, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 10
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


## Reihe paralleler Rippen.
##
## Griffriffelung, Schlittenrillen, Pumpenprofil, Kuehlrippen — alles dasselbe
## Muster. Aus zwei Metern liest das Auge daraus "gefraeste Oberflaeche",
## obwohl es ein Dutzend duenner Quader sind. Derselbe Trick wie bei der
## Picatinny-Schiene, und der billigste Weg zu wahrgenommenem Detail.
static func ribs(name: String, count: int, size: Vector3, start: Vector3, step: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = name
	for i in range(count):
		node.add_child(box(
			"%sRib%d" % [name, i],
			size,
			start + step * float(i),
			mat,
			rotation_deg
		))
	return node


## Schraubenkopf oder Haltebolzen. Standardmaessig quer eingesetzt, also
## entlang X — so sitzen die meisten Bolzen an einem Gehaeuse.
static func screw(name: String, radius: float, depth: float, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3(0.0, 0.0, 90.0)) -> MeshInstance3D:
	return cylinder(name, radius, depth, pos, mat, rotation_deg)


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
