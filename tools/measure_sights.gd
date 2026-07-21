## Vermisst die Visierung einer Waffe an der Geometrie statt am Augenmass.
##
##   godot --headless --path . --script res://tools/measure_sights.gd -- akm
##
## WOFUER: Beim AKM wurde die Visierhoehe dreimal geraten und dreimal falsch
## gesetzt. Ein Bild zeigt, dass es nicht stimmt, aber nicht um wieviel.
##
## Ausgegeben wird ein Hoehenprofil ueber die Laufachse (1-cm-Scheiben) und
## darin die oertlichen Gipfel. Korn und Kimme sind genau das: die beiden
## hoechsten Punkte, die aus dem Gehaeuse herausragen — vorn der duenne
## Kornhalter, hinten das breitere Visierblatt.
##
## Zusaetzlich wird der Querschnitt einer Scheibe gedruckt (Hoehe ueber x).
## Daran erkennt man die Kimme: Sie hat in der Mitte eine Kerbe, das Korn
## nicht.
extends SceneTree

const SLICE := 0.01

## Halbe Dicke der untersuchten Scheibe. Duenn genug, und einzelne Teile
## stehen fuer sich; zu dick, und Korn, Buegel und Gasblock verschmelzen zu
## einem Klumpen, aus dem nichts mehr abzulesen ist.
var _slab := 0.01


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	var args := OS.get_cmdline_user_args()
	var wanted: String = args[0] if args.size() > 0 else "akm"

	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var data := item as WeaponData
		if data == null or not data.has_own_viewmodel():
			continue

		var model := data.create_viewmodel()
		model.build()
		if not model.get_model_name().contains(wanted):
			model.free()
			continue

		print("\n=== %s ===" % data.display_name)
		print("eingestellt: sight_height %.4f   ads_distance %.4f   muzzle_z %.4f"
				% [model.sight_height, model.ads_distance, model.muzzle_z])

		var points: Array[Vector3] = []
		_collect(model, Transform3D.IDENTITY, points)
		print("%d Punkte" % points.size())
		_profile(points)
		_skyline(points, model.sight_height, model.ads_distance)

		if args.size() > 2:
			_slab = float(args[2])
		if args.size() > 1:
			_cross_section(points, float(args[1]))
			_slice_map(points, float(args[1]))

		model.free()

	quit(0)


## Sammelt alle Modellpunkte im Kameraraum.
func _collect(node: Node, transform: Transform3D, into: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					into.append(transform * v)

	for child in node.get_children():
		if child is Node3D:
			_collect(child, transform * (child as Node3D).transform, into)


## Hoechster Punkt je Laengsscheibe, dazu die oertlichen Gipfel.
func _profile(points: Array[Vector3]) -> void:
	var top := {}
	for p in points:
		var key := int(floor(p.z / SLICE))
		if not top.has(key) or p.y > top[key]:
			top[key] = p.y

	var keys := top.keys()
	keys.sort()

	print("\n%-10s %10s %s" % ["z (m)", "hoechstes y", ""])
	for i in keys.size():
		var key: int = keys[i]
		var y: float = top[key]
		var mark := ""
		if i > 0 and i < keys.size() - 1 \
				and y > top[keys[i - 1]] and y >= top[keys[i + 1]]:
			mark = "  <-- Gipfel"
		print("%-10.3f %10.4f%s" % [key * SLICE, y, mark])


## Was beim Zielen die Oberkante bildet — in GRAD ueber der Bildmitte.
##
## Ein Millimeter dicht am Auge verdeckt mehr als ein Zentimeter an der
## Muendung. Deshalb sagt eine Hoehentabelle in Metern nichts darueber, was
## man am Ende sieht; erst der Winkel tut das. Was hier ganz oben steht,
## verdeckt alles dahinter — und wenn das nicht die Visierung ist, schaut man
## gegen ein Bauteil statt durch die Kerbe.
##
## Nur der Bereich vor dem Auge zaehlt: Was hinter der Kamera liegt, wird
## nicht gezeichnet.
func _skyline(points: Array[Vector3], height: float, distance: float) -> void:
	var top := {}
	for p in points:
		var z := p.z - distance
		if z > -0.03:
			continue
		var angle := rad_to_deg(atan2(p.y - height, -z))
		var key := int(floor(z / SLICE))
		if not top.has(key) or angle > top[key]:
			top[key] = angle

	var keys := top.keys()
	keys.sort()
	var best_key: int = keys[0]
	for key in keys:
		if top[key] > top[best_key]:
			best_key = key

	print("\nOberkante beim Zielen (h %.4f, d %.4f):" % [height, distance])
	print("%-12s %10s %s" % ["z zur Kamera", "Grad", ""])
	for key in keys:
		var mark := "  <-- verdeckt alles dahinter" if key == best_key else ""
		print("%-12.3f %10.3f%s" % [key * SLICE, top[key], mark])


## Hoehe ueber Breite in einer Scheibe — zeigt die Kerbe der Kimme.
func _cross_section(points: Array[Vector3], centre_z: float) -> void:
	print("\nQuerschnitt bei z = %.3f (+/- 1 cm):" % centre_z)
	var top := {}
	for p in points:
		if absf(p.z - centre_z) > _slab:
			continue
		var key := int(round(p.x / 0.002))
		if not top.has(key) or p.y > top[key]:
			top[key] = p.y

	var keys := top.keys()
	keys.sort()
	for key in keys:
		print("  x %7.4f   y %7.4f" % [key * 0.002, top[key]])


## Zeichnet die Scheibe als Raster — daran sieht man einen Ring als Ring.
##
## Eine Zahlenkolonne verraet nur die Oberkante. Ob das Korn in einem Buegel
## sitzt und wo dessen Mitte liegt, sieht man erst, wenn die Scheibe als Bild
## dasteht.
func _slice_map(points: Array[Vector3], centre_z: float) -> void:
	const CELL := 0.0015
	var filled := {}
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for p in points:
		if absf(p.z - centre_z) > _slab:
			continue
		var cx := int(round(p.x / CELL))
		var cy := int(round(p.y / CELL))
		filled[Vector2i(cx, cy)] = true
		min_x = minf(min_x, cx)
		max_x = maxf(max_x, cx)
		min_y = minf(min_y, cy)
		max_y = maxf(max_y, cy)

	if filled.is_empty():
		return

	print("\nScheibe bei z = %.3f, Raster %.1f mm:" % [centre_z, CELL * 1000.0])
	for cy in range(int(max_y), int(min_y) - 1, -1):
		var line := ""
		for cx in range(int(min_x), int(max_x) + 1):
			line += "#" if filled.has(Vector2i(cx, cy)) else "."
		print("y %7.4f  %s" % [cy * CELL, line])
	print("           x von %.4f bis %.4f" % [min_x * CELL, max_x * CELL])
