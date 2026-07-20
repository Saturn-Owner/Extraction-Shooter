## Die taktische Weste, die eine Figur trägt.
##
## ---------------------------------------------------------------------------
## DIE TASCHEN STEHEN IM MODELL, NICHT IM CODE
##
## Die `.glb` bringt vier benannte Knoten mit — `mag_pouch_1` bis `_4`. Diese
## Klasse liest ihre Lage aus der Datei aus, und die Nachladeanimation greift
## an den vordersten.
##
## Damit verschiebt man eine Tasche in Blender und die Hand geht mit. Stünde
## der Griffpunkt im Code, müsste man ihn nach jeder Modelländerung von Hand
## nachziehen — und wenn es einmal vergessen wird, greift die Figur ins Leere,
## ohne dass ein Test das merkt.
##
## Dieselbe Überlegung steht hinter `GripPoint` und `SupportPoint` an den
## Waffen: Das Modell weiss, wo es angefasst wird.
##
## ---------------------------------------------------------------------------
## ACHSEN
##
## Wie bei den Waffen: Das Modell schaut entlang +X, das Spiel erwartet -Z.
## Die Drehung um 90 Grad passiert hier an einer Stelle.
class_name CharacterVest
extends Node3D

const MODEL := "res://assets/models/gear/taktische_weste.glb"

## Blender/glTF liefert +X als Vorderseite, Godot erwartet -Z.
const TURN := Vector3(0.0, 90.0, 0.0)

## Wie viele Magazintaschen die Weste hat.
const POUCH_COUNT := 4

var _pouches: Array[Node3D] = []


func _ready() -> void:
	rotation_degrees = TURN
	_build()


func _build() -> void:
	if not ResourceLoader.exists(MODEL):
		push_error("[CharacterVest] Modell fehlt: %s" % MODEL)
		return

	var scene := (load(MODEL) as PackedScene).instantiate()
	add_child(scene)

	# ACHTUNG, GODOT-EIGENHEIT: Beim Import liegt eine leere "AuxScene" ueber
	# der Datei, und die Wurzeltransformation wandert aufs Kind. Wer hier
	# `scene` statt seines ersten Node3D-Kindes durchsucht, findet die Knoten
	# zwar, bekommt aber falsche Positionen. Dieselbe Falle wie bei den
	# AR-15-Teilen, siehe GlbParts.
	for i in range(POUCH_COUNT):
		var pouch := _find(scene, "mag_pouch_%d" % (i + 1))
		if pouch != null:
			_pouches.append(pouch)

	if _pouches.size() != POUCH_COUNT:
		push_warning("[CharacterVest] Nur %d von %d Magazintaschen gefunden"
			% [_pouches.size(), POUCH_COUNT])


## Die Tasche, aus der als Nächstes gezogen wird.
##
## Von links nach rechts: `mag_pouch_1` sitzt auf der linken Körperseite und
## ist damit die, an die die linke Hand am kürzesten greift.
func front_pouch() -> Node3D:
	return _pouches[0] if not _pouches.is_empty() else null


func pouch(index: int) -> Node3D:
	return _pouches[index] if index >= 0 and index < _pouches.size() else null


func pouch_count() -> int:
	return _pouches.size()


static func _find(node: Node, wanted: String) -> Node3D:
	if node.name == wanted and node is Node3D:
		return node as Node3D
	for child in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null
