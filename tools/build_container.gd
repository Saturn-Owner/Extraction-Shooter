## Baut den Container aus Lucas' eigenem Entwurf in eine Mesh.
##
##   godot --headless --path . --script res://tools/build_container.gd
##
## ---------------------------------------------------------------------------
## WOHER DER ENTWURF KOMMT
##
## Lucas hat den Container in einer three.js-Seite entworfen: geriffelte Waende,
## dunkler Stahlrahmen mit Eckbeschlaegen, kraeftige Farbe. Diese Datei baut
## GENAU DAS in Godot nach — dieselben Masse, dieselbe Rippenzahl, dieselben
## Farbrollen.
##
## Damit faellt das fremde Modell weg, an dem die Lizenzfrage hing: Der
## Container ist jetzt Lucas' eigener Entwurf, im Code reproduziert, ohne einen
## einzigen fremden Baustein.
##
## ---------------------------------------------------------------------------
## WARUM EINE EINZIGE MESH
##
## Der Container besteht aus ueber hundert Quadern — Rippen, Rahmen, Beschlaege.
## Als einzelne Knoten waeren das bei vierhundert Containern zehntausende, und
## das Spiel wuerde stehen. Alle Quader werden deshalb in EINE Mesh
## zusammengefuegt (SurfaceTool), und die liegt vierhundertmal als dieselbe
## Ressource im Spiel — ein Objekt, nicht hundert.
##
## Die Mesh hat ZWEI Flaechen: der Anstrich (Flaeche 0) und der Rahmen
## (Flaeche 1). So kann jeder Container seinen Anstrich umfaerben — rot, gelb,
## blau — waehrend der Rahmen immer dunkel bleibt.
extends SceneTree

const OUT := "res://assets/models/world/container.res"

## Masse wie ein echter 20-Fuss-Container, aber auf unser 0,2-m-Raster gerundet:
## L x H x W. Genau die Groesse, mit der das Layout rechnet.
const L := 6.0
const H := 2.6
const W := 2.4

## Rippen je Wand — aus dem Entwurf uebernommen.
const RIBS_LONG := 42
const RIBS_END := 14

## Wie tief die Rippen aus der Wand stehen und wie breit sie im Verhaeltnis
## zum Rippenabstand sind. Beides aus dem Entwurf.
const RIB_DEPTH := 0.05
const RIB_WIDTH_RATIO := 0.62
const PANEL_DEPTH := 0.03

## Rahmenstaerken.
const RAIL := 0.14
const POST := 0.12
const CASTING := 0.18

## Die Wandflaeche laesst oben und unten Platz fuer die Rahmenschienen.
const PANEL_HEIGHT := H - 0.36

var _paint := SurfaceTool.new()
var _frame := SurfaceTool.new()


func _initialize() -> void:
	_paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	_frame.begin(Mesh.PRIMITIVE_TRIANGLES)

	_build_walls()
	_build_frame()

	# Erst der Anstrich als Flaeche 0, dann der Rahmen als Flaeche 1 in
	# dieselbe Mesh.
	var mesh: ArrayMesh = _paint.commit()
	mesh = _frame.commit(mesh)
	mesh.surface_set_name(0, "Anstrich")
	mesh.surface_set_name(1, "Rahmen")

	var box := mesh.get_aabb()
	print("Container gebaut:")
	print("  Masse:    %.2f x %.2f x %.2f" % [box.size.x, box.size.y, box.size.z])
	print("  Flaechen: %d (%s, %s)" % [mesh.get_surface_count(),
		mesh.surface_get_name(0), mesh.surface_get_name(1)])
	print("  Dreiecke: %d" % (_count_indices(mesh) / 3))

	if ResourceSaver.save(mesh, OUT) != OK:
		printerr("Speichern fehlgeschlagen: ", OUT)
		quit(1)
		return

	var kb := FileAccess.open(OUT, FileAccess.READ).get_length() / 1024.0
	print("\nGeschrieben: %s   %.0f KB" % [OUT, kb])
	quit(0)


# ---------------------------------------------------------------------------
# Waende
# ---------------------------------------------------------------------------

## Vier geriffelte Waende. Die Rippen zeigen nach aussen — deshalb steht jede
## Wand an ihrer Seite und ist zur Mitte hin gedreht.
func _build_walls() -> void:
	var half_l := L * 0.5
	var half_w := W * 0.5
	var centre_y := H * 0.5

	# Lang: Vorder- und Rueckwand entlang X, an den +Z/-Z-Flaechen.
	_wall(L - 0.24, PANEL_HEIGHT, RIBS_LONG,
		Vector3(0.0, centre_y, half_w - 0.02), 0.0)
	_wall(L - 0.24, PANEL_HEIGHT, RIBS_LONG,
		Vector3(0.0, centre_y, -half_w + 0.02), 180.0)

	# Stirn: die beiden Enden entlang Z, an den +X/-X-Flaechen.
	_wall(W - 0.2, PANEL_HEIGHT, RIBS_END,
		Vector3(half_l - 0.02, centre_y, 0.0), 90.0)
	_wall(W - 0.2, PANEL_HEIGHT, RIBS_END,
		Vector3(-half_l + 0.02, centre_y, 0.0), 270.0)


## Eine geriffelte Wand: eine glatte Ruecktafel plus senkrechte Rippen davor.
##
## `facing` dreht die Wand um die Hochachse, damit die Rippen nach aussen
## zeigen. Gebaut wird flach in der XY-Ebene und dann gedreht — so muss man
## nur an einer Stelle richtig rechnen.
func _wall(length: float, height: float, ribs: int,
		pos: Vector3, facing: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(facing))
	var origin := pos

	# Ruecktafel.
	_add_box(_paint, Vector3(length, height, PANEL_DEPTH),
		Transform3D(basis, origin))

	# Rippen.
	var rib_w := length / float(ribs)
	var rib_geo := Vector3(rib_w * RIB_WIDTH_RATIO, height, RIB_DEPTH)
	for i in range(ribs):
		var x := -length * 0.5 + rib_w * (float(i) + 0.5)
		var local := Vector3(x, 0.0, PANEL_DEPTH * 0.5 + RIB_DEPTH * 0.5)
		_add_box(_paint, rib_geo, Transform3D(basis, origin + basis * local))


# ---------------------------------------------------------------------------
# Rahmen
# ---------------------------------------------------------------------------

## Der dunkle Stahlrahmen: umlaufende Schienen oben und unten, vier Eckpfosten,
## acht Eckbeschlaege. Das ist die Silhouette, an der man einen Container auch
## im Nebel als Container erkennt.
func _build_frame() -> void:
	var half_l := L * 0.5
	var half_w := W * 0.5

	for y: float in [RAIL * 0.5, H - RAIL * 0.5]:
		# Schienen entlang der Langseiten.
		for z: float in [half_w - RAIL * 0.5, -half_w + RAIL * 0.5]:
			_add_box(_frame, Vector3(L, RAIL, RAIL),
				Transform3D(Basis(), Vector3(0.0, y, z)))
		# Schienen entlang der Stirnseiten.
		for x: float in [half_l - RAIL * 0.5, -half_l + RAIL * 0.5]:
			_add_box(_frame, Vector3(RAIL, RAIL, W - RAIL * 2.0),
				Transform3D(Basis(), Vector3(x, y, 0.0)))

	# Vier Eckpfosten.
	for sx: float in [1.0, -1.0]:
		for sz: float in [1.0, -1.0]:
			var x := sx * (half_l - POST * 0.5)
			var z := sz * (half_w - POST * 0.5)
			_add_box(_frame, Vector3(POST, H - RAIL * 2.0, POST),
				Transform3D(Basis(), Vector3(x, H * 0.5, z)))

	# Acht Eckbeschlaege.
	for sx: float in [1.0, -1.0]:
		for sy: float in [1.0, -1.0]:
			for sz: float in [1.0, -1.0]:
				var x := sx * (half_l - CASTING * 0.5)
				var y := CASTING * 0.5 if sy > 0.0 else H - CASTING * 0.5
				var z := sz * (half_w - CASTING * 0.5)
				_add_box(_frame, Vector3(CASTING, CASTING, CASTING),
					Transform3D(Basis(), Vector3(x, y, z)))


# ---------------------------------------------------------------------------
# Helfer
# ---------------------------------------------------------------------------

## Haengt einen Quader an einen SurfaceTool. Nutzt BoxMesh als Quelle, damit
## Normalen und Kanten stimmen, statt sechsunddreissig Dreiecke von Hand zu
## wickeln.
func _add_box(into: SurfaceTool, size: Vector3, transform: Transform3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	into.append_from(box, 0, transform)


func _count_indices(mesh: ArrayMesh) -> int:
	var total := 0
	for i in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(i)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += indices.size()
	return total
