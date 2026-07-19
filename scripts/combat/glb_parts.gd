## Hilfsmittel für Waffenteile, die als .glb aus Blender kommen.
##
## GRUND FÜR DIESE DATEI: Die Modelle stehen in einem anderen Achsensystem als
## das Spiel, und jede Waffe müsste sonst dieselbe Umrechnung selbst schreiben.
## Genau ein Rechenweg an genau einer Stelle — verrechnet er sich, sitzt alles
## gleich falsch und fällt sofort auf, statt sich über zwölf Dateien zu
## verteilen.
##
## ACHSEN:
##   Blender-Export:  +X = Mündung,  +Y = oben,  Z = seitlich
##   Godot-Viewmodel: -Z = Mündung,  +Y = oben, +X = rechts
##
## Eine Drehung um +90° um die Y-Achse bildet +X auf -Z ab. Deshalb bekommt
## jedes eingehängte Modell diese Drehung, und Positionen werden über
## to_view() umgerechnet.
##
## EINBAUSTELLE STECKT IN DER DATEI: Jede Teildatei ist so exportiert, dass
## ihr Wurzelknoten die umgekehrte Verschiebung ihrer Einbaustelle trägt und
## die Geometrie selbst um den Ursprung liegt. Damit weiß das Teil, wo es an
## der Waffe sitzt — wir müssen es nicht abtippen, und wenn der Modellierer
## etwas verschiebt, stimmt es ohne Codeänderung weiter.
class_name GlbParts
extends RefCounted

const DIR := "res://assets/models/weapons/ar15/"

## Drehung, die Modellachsen auf Spielachsen bringt.
const TURN := Vector3(0.0, 90.0, 0.0)

## Verschiebung vom Modellursprung auf den Viewmodel-Ursprung, in MODELLACHSEN.
##
## Gemessen, nicht geschätzt (tools/inspect_viewmodel.gd):
##   X  so, dass der Pistolengriff dort sitzt, wo er beim alten Modell sass —
##      damit Haltung und Nachladepose weiter passen
##   Y  so, dass die Laufachse auf Höhe 0.012 liegt, wie bei allen Waffen
##   Z  so, dass die Laufachse mittig sitzt statt 4 mm nach links versetzt
const ORIGIN_SHIFT := Vector3(0.27315, -0.0475, 0.0039)

## Der Wurzelknoten der Basisdatei trägt selbst eine Verschiebung. Positionen
## aus Teildateien müssen sie mitbekommen, sonst sitzen sie um diesen Betrag
## daneben.
const BASE_ROOT_SHIFT := Vector3(-0.077, -0.0304, 0.0156)


## Rechnet einen Punkt aus Modellachsen in Viewmodel-Achsen um.
static func to_view(model_point: Vector3) -> Vector3:
	var p := model_point + ORIGIN_SHIFT
	return Vector3(p.z, p.y, -p.x)


## Lädt eine Teildatei und gibt sie fertig gedreht zurück.
static func load_part(file_name: String, node_name: String) -> Node3D:
	var packed: PackedScene = load(DIR + file_name + ".glb")
	if packed == null:
		push_error("[GlbParts] Modell fehlt: %s" % file_name)
		return null

	var holder := Node3D.new()
	holder.name = node_name
	holder.rotation_degrees = TURN
	holder.add_child(packed.instantiate())
	return holder


## Wo dieses Teil an der Waffe sitzt, in Viewmodel-Achsen.
##
## Liest die Verschiebung aus dem Wurzelknoten der Datei — siehe Klassenkopf.
static func mount_point(file_name: String) -> Vector3:
	var packed: PackedScene = load(DIR + file_name + ".glb")
	if packed == null:
		push_error("[GlbParts] Modell fehlt: %s" % file_name)
		return Vector3.ZERO

	var scene := packed.instantiate() as Node3D
	if scene == null:
		push_error("[GlbParts] %s hat keinen 3D-Wurzelknoten" % file_name)
		return Vector3.ZERO

	# ACHTUNG, DAS IST DIE FALLE AN DIESER STELLE: Godot legt beim Import eine
	# leere "AuxScene" als Wurzel darueber und schiebt die Verschiebung der
	# Datei auf deren Kind. `scene.position` ist deshalb IMMER null. Wer sie
	# ausliest, bekommt fuer jedes Teil denselben Punkt — und alle Teile landen
	# uebereinander an derselben Stelle.
	var carrier := _first_node_3d(scene)
	if carrier == null:
		push_error("[GlbParts] %s hat keinen Traegerknoten" % file_name)
		scene.free()
		return Vector3.ZERO

	var model_position: Vector3 = -carrier.position + BASE_ROOT_SHIFT
	scene.free()
	return to_view(model_position)


static func _first_node_3d(node: Node) -> Node3D:
	for child in node.get_children():
		if child is Node3D:
			return child as Node3D
	return null


## Ein leerer Drehpunkt, wie ihn ViewmodelParts.pivot() liefert.
static func pivot(node_name: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	return node
