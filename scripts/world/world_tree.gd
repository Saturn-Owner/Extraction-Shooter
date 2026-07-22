## Einzelne Pflanzen aus dem Kiefernpack — jede fuer sich platzierbar, nicht
## immer alle zusammen als derselbe Dreier-Klumpen.
##
## ---------------------------------------------------------------------------
## WARUM NICHT EINFACH WorldHouse.place() MIT DER GANZEN DATEI
##
## `assets/models/world/trees/snow_pine_pack.glb` ist als KIT gebaut: mehrere
## eigenstaendige Pflanzengruppen (ein Busch, zwei Kiefernarten) sitzen an
## verschiedenen Stellen INNERHALB DERSELBEN Datei, dazu eine 2x2-m-
## Vorschau-Bodenplatte ("Plane"), auf der sie im Sketchfab-Bild stehen. Wer
## die ganze Datei einmal instanziert, bekommt IMMER denselben Klumpen aus
## allen Pflanzen zusammen — auf einer grossen Karte sieht man dann denselben
## Dreier-Haufen hundertfach wiederholt, statt eines echten Waldes.
##
## Diese Klasse loest deshalb JEDE Pflanzengruppe einzeln heraus (wie
## AR15Viewmodel das mit Anbauteilen aus dem Waffenmodell macht) und cached
## sie als Vorlage — der Karten-Generator platziert danach EINZELNE Kopien
## an unabhaengig verteilten Stellen.
class_name WorldTree
extends RefCounted

const MODEL := "res://assets/models/world/trees/snow_pine_pack.glb"

## Namen der Pflanzengruppen in der Datei — gemessen (siehe Kopfkommentar
## dieser Klasse), nicht geraten. "Plane" (die Bodenplatte) gehoert bewusst
## nicht dazu.
const PLANT_NAMES := ["BushBare1", "SnowTree1", "SnowTree1_001", "SnowTree2"]

## Pflanzenname -> losgeloester Vorlagenknoten. Einmal aus der Datei
## herausgetrennt, danach nur noch dupliziert — sonst wuerde jede der
## hunderten Platzierungen die ganze Datei neu laden und instanzieren, nur
## um wieder alles bis auf einen Ast wegzuwerfen.
static var _templates: Dictionary = {}


## Platziert eine einzelne Pflanze an `pos`. Rein dekorativ (keine
## Kollision) — duenne, sich kreuzende Blattebenen ohne Innenraum liessen den
## Spieler im Spiel darin haengen bleiben (siehe WorldHouse.place()).
##
## `scale` streut die Groesse ein wenig (z.B. 0.85 bis 1.2) — sonst sehen
## alle Baeume derselben Art wie identische Kopien aus, was bei Pflanzen
## staerker auffaellt als bei Haeusern.
static func place(node_name: String, plant_name: String, pos: Vector3,
		rotation_deg: float, scale: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = pos
	root.rotation_degrees = Vector3(0.0, rotation_deg, 0.0)
	if not is_equal_approx(scale, 1.0):
		root.scale = Vector3.ONE * scale

	var template := _template_for(plant_name)
	if template == null:
		push_warning("[WorldTree] Pflanze '%s' nicht im Paket gefunden" % plant_name)
		return root

	var instance: Node = template.duplicate()
	instance.name = "Mesh"
	root.add_child(instance)
	return root


static func _template_for(plant_name: String) -> Node:
	if _templates.has(plant_name):
		return _templates[plant_name]

	var scene := load(MODEL) as PackedScene
	if scene == null:
		_templates[plant_name] = null
		return null

	var instance := scene.instantiate()
	var found := instance.get_node_or_null(NodePath(plant_name))
	if found == null:
		instance.free()
		_templates[plant_name] = null
		return null

	instance.remove_child(found)
	found.owner = null
	instance.free()
	_templates[plant_name] = found
	return found
