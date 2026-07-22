## Setzt ein Sketchfab-Haus in die Welt — mit Kollision, die WIRKLICH der
## Modellform folgt, nicht nur einer groben Box.
##
## ---------------------------------------------------------------------------
## TRIMESH STATT BOX — WARUM DAS HIER GEHT
##
## Eine Box-Kollision kennt keine Tueren: Wer eine begehbare Oeffnung will,
## muesste sie von Hand nachbauen (siehe die Ausnahme fuer Lake Hawea House,
## das deshalb aus dem Generator geflogen ist — 652.000 Dreiecke waeren als
## Trimesh zu teuer). Die sechs Haeuser, die tatsaechlich verwendet werden,
## liegen alle zwischen 600 und 55.000 Dreiecken — fuer EINEN StaticBody3D
## (nicht bewegte Kollision, das ist der Godot-typische Anwendungsfall fuer
## `ConcavePolygonShape3D`) ist das unproblematisch. `Mesh.create_trimesh_
## shape()` baut die Kollisionsform direkt aus der sichtbaren Geometrie —
## eine Tuer, die im Modell eine echte Luecke ist, ist es damit auch in der
## Kollision. Ob das bei jedem der sechs Haeuser tatsaechlich der Fall ist
## (manche Sketchfab-Scans haben zugemauerte oder gar keine Tueren), muss ein
## Mensch im Spiel nachsehen — das kann dieses Skript nicht wissen.
class_name WorldHouse
extends RefCounted

const WORLD_LAYER := 1

const HOUSES_DIR := "res://assets/models/world/houses/"

## Alle sechs verfuegbaren Haeuser, mit ihrer gemessenen Grundflaeche (X, Z in
## Metern, aus tools/convert_world_assets.gd) — der Karten-Generator braucht
## das, um Haeuser so weit auseinanderzustellen, dass sie sich nicht
## ueberlappen, ohne jedes Modell selbst laden zu muessen.
const CATALOGUE := [
	{file = "house_home.glb", footprint = Vector2(11.04, 21.74)},
	{file = "old_house.glb", footprint = Vector2(7.22, 6.83)},
	{file = "old_wooden_barn_house.glb", footprint = Vector2(3.99, 9.04)},
	{file = "old_wooden_watchtower_house.glb", footprint = Vector2(2.19, 2.19)},
	{file = "psx_abandoned_house.glb", footprint = Vector2(6.79, 7.56)},
	{file = "windmill.glb", footprint = Vector2(19.08, 8.13)},
]


## Laedt EIN BELIEBIGES Modell (Haus oder Baumgruppe, siehe schneekarte.gd)
## und setzt es an `pos`, um `rotation_deg` um die Hochachse gedreht. Faellt
## die Datei aus, kommt ein leerer Knoten zurueck — ein frischer Clone soll
## spielbar bleiben, nicht abstuerzen.
##
## `model_path` ist der VOLLE res://-Pfad, nicht nur ein Dateiname — diese
## Funktion kennt HOUSES_DIR nicht mehr, damit sie genauso gut fuer
## trees/snow_pine_pack.glb taugt wie fuer ein Haus.
static func place(node_name: String, model_path: String, pos: Vector3,
		rotation_deg: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = pos
	root.rotation_degrees = Vector3(0.0, rotation_deg, 0.0)

	var scene := load(model_path) as PackedScene
	if scene == null:
		push_warning("[WorldHouse] Modell fehlt: %s" % model_path)
		return root

	var visual := scene.instantiate()
	visual.name = "Mesh"
	root.add_child(visual)

	var body := StaticBody3D.new()
	body.name = "Kollision"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	root.add_child(body)

	for mesh_instance in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mesh_instance as MeshInstance3D).mesh
		if mesh == null:
			continue
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			continue

		var collider := CollisionShape3D.new()
		collider.shape = shape
		# Trimesh-Kollisionen tragen keine eigene Skalierung — die Form muss
		# deshalb schon MIT der vollen Kette aus Position/Drehung/Skalierung
		# vom Szenenwurzelknoten bis zu diesem Mesh gebaut sein (die
		# Vertices selbst tragen die Skalierung, nicht der Knoten).
		collider.transform = _accumulated_transform(visual, mesh_instance)
		body.add_child(collider)

	return root


## Transform von der Szenenwurzel bis EINSCHLIESSLICH des Zielknotens —
## dieselbe Rechnung wie in tools/convert_world_assets.gd, hier aber zur
## Laufzeit auf dem geladenen (schon fertig konvertierten) Modell.
static func _accumulated_transform(root_node: Node, target: Node) -> Transform3D:
	var chain: Array[Transform3D] = []
	var walker := target
	while walker != null and walker != root_node:
		if walker is Node3D:
			chain.append((walker as Node3D).transform)
		walker = walker.get_parent()
	if root_node is Node3D:
		chain.append((root_node as Node3D).transform)
	var result := Transform3D.IDENTITY
	for i in range(chain.size() - 1, -1, -1):
		result = result * chain[i]
	return result
