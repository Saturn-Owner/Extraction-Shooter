## Basisklasse für alle sichtbaren Anbauteile.
##
## Gegenstück zu WeaponViewmodel und nach demselben Grundsatz gebaut: Jedes
## Teil hat sein eigenes Modell in einer eigenen Datei unter
## scripts/attachments/. Ein Rotpunkt und ein Zielfernrohr sind nicht
## dieselbe Form in anderer Grösse — sie sitzen anders, wiegen anders und
## man schaut anders hindurch.
##
## Eine Unterklasse überschreibt:
##   _configure()    Kennwerte des Teils
##   _build_parts()  die Geometrie
##
## DER WICHTIGE TEIL IST `aim_point`. Bei einem Visier ist das der Punkt, durch
## den der Spieler schaut. weapon_view.gd senkt die Waffe beim Zielen um genau
## diese Höhe ab, damit die Visierlinie auf der Kameramitte landet. Wer hier
## danebenliegt, baut ein Visier, an dem die Waffe vorbeischiesst.
class_name AttachmentViewmodel
extends Node3D

## Zielpunkt bei Visieren: der Knoten, durch den geschaut wird.
## Bleibt null bei allem, was kein Visier ist.
var aim_point: Node3D

## Neue Mündung bei Mündungsaufsätzen.
##
## Ein Schalldämpfer verlängert den Lauf, und das Mündungsfeuer muss an seine
## Spitze wandern. Bewusst als Knoten und nicht als Zahl: Die Länge steht dann
## an genau einer Stelle — dort, wo das Teil gebaut wird — statt zusätzlich als
## Wert gepflegt zu werden, der irgendwann nicht mehr zur Geometrie passt.
var muzzle_point: Node3D

var _mats: Dictionary

## Verhindert doppeltes Bauen, wenn build() von Hand aufgerufen wird und der
## Knoten danach in den Baum kommt — dann liefe _ready() ein zweites Mal
## darueber und jedes Teil waere doppelt vorhanden.
var _built: bool = false


func _ready() -> void:
	build()


## Modell aufbauen. Wird auch vom Renderwerkzeug ausserhalb des Spiels genutzt.
func build() -> void:
	if _built:
		return
	_built = true
	_mats = ViewmodelParts.materials()
	_configure()
	_build_parts()
	aim_point = get_node_or_null("AimPoint") as Node3D
	muzzle_point = get_node_or_null("MuzzlePoint") as Node3D


# --- Von Unterklassen zu überschreiben ---

func _configure() -> void:
	pass


func _build_parts() -> void:
	pass


## Kurzname für Renderbilder und Fehlermeldungen.
func get_model_name() -> String:
	return "unbenannt"


## Wie hoch der Zielpunkt über der Aufnahme liegt.
## 0.0 bei Teilen ohne Visier.
func get_aim_height() -> float:
	return aim_point.position.y if aim_point != null else 0.0
