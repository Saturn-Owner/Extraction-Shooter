## AKM — Sturmgewehr, Langhubkolben, 7,62x39.
##
## Charakter: schwerer und stumpfer als die AR-15. Kraeftiger Rueckstoss,
## traegeres Handling — dafuer unempfindlich.
##
## ---------------------------------------------------------------------------
## DIESES MODELL KOMMT ALS .glb, NICHT AUS QUADERN
##
## Frueher war die AKM prozedural aus Quadern gebaut. Jetzt liegt ein echtes
## Modell unter assets/models/weapons/akm/ (Lucas' Vorlage, CC0 von Sketchfab).
## Es kommt als EIN Stueck — Verschluss und Magazin bewegen sich also nicht
## einzeln. Rueckstoss und Schwingen macht weapon_view.gd auf der ganzen Waffe,
## das bleibt.
##
## Das Modell wird beim Laden VERMESSEN und selbst passend gesetzt: Sketchfab-
## Modelle kommen in beliebiger Groesse und Ausrichtung. Kommt es verdreht oder
## zu gross, dreht man an den drei Konstanten unten — kein Rechnen im Kopf.
class_name AKMViewmodel
extends WeaponViewmodel

const MODEL := "res://assets/models/weapons/akm/akm.glb"

## Hoehe der Laufachse ueber dem Modellursprung.
const BORE_Y := 0.014

## Hoehe der Visierlinie ueber dem Modellursprung — GEMESSEN, nicht geraten.
##
## Diese Zahl ist nach oben UND nach unten eingeklemmt, und beide Grenzen
## liegen nur drei Millimeter auseinander:
##
##   oben   Das Korn endet bei y = 0.0880. Wer die Linie hoeher legt, zielt
##          ueber die eigene Visierung hinweg.
##   unten  Zwischen den Visieren sitzt bei z = -0.32 ein Aufbau am Gehaeuse,
##          der bis y = 0.0858 reicht — und der steht dem Auge dreissig
##          Zentimeter naeher als das Korn. Liegt die Linie tiefer als 0.0855,
##          verdeckt dieser Aufbau das Korn vollstaendig.
##
## Diese Enge ist keine Schlamperei, sondern liegt am Modell: Es ist ein AK mit
## durchgehender Schiene, gebaut fuer eine Optik. Wer wirklich ein AK-Zielbild
## will, braucht in Blender ein hoeheres Korn — dann wird hier eine Zahl
## geaendert und sonst nichts.
const SIGHT_LINE := 0.0865

## Hinteres Ende der Visierlinie: die Schienenoberkante (gemessen y = 0.0824)
## kurz vor dem Schaft. Dort laege eine Kimme, wenn die Waffe eine haette.
const REAR_SIGHT_Z := -0.205

## Wo das Korn im Modell steckt — gemessen am hoechsten Punkt der Waffe.
const FRONT_SIGHT_Z := -0.530

## Gemessen mit einem Godot-Skript (nicht geschaetzt): Groesse und Mittelpunkt
## des Modells in seinem eigenen Raum. Daraus faellt die Lage in der Hand.
## Wird eine ANDERE Waffe exportiert, hier neu vermessen und eintragen.
const MODEL_SIZE := Vector3(0.071, 0.268, 1.017)
const MODEL_CENTRE := Vector3(-0.009, 0.106, -0.163)

# --- Anpassung, falls das Modell verdreht oder falsch gross sitzt ------------

## Gewuenschte Gesamtlaenge im Kameraraum. Das Modell wird darauf skaliert,
## egal wie gross es aus Blender kam.
const FIT_LENGTH := 0.56

## Neigt die Waffe um die Querachse. Zeigt der Lauf nach UNTEN oder OBEN statt
## nach vorn, hier drehen. Das Modell kam mit dem Lauf nach unten.
const FIT_PITCH_DEG := 0.0

## Dreht die Waffe um die Hochachse. Zeigt der Lauf nach HINTEN statt nach
## vorn, hier auf 180 stellen.
const FIT_YAW_DEG := 180.0

## Rollt die Waffe um die Laufachse. Steht sie auf dem Kopf oder auf der Seite,
## hier 180 oder 90 eintragen.
const FIT_ROLL_DEG := 0.0

## Verschiebt das Modell im Kameraraum, NACHDEM es gedreht und gesetzt wurde.
##
## Rueckt die VISIERUNG auf die Bildmitte — und sonst nichts.
##
## `weapon_view` zieht die Waffe beim Zielen auf x = 0 und senkt sie um
## `sight_height`. Das setzt voraus, dass die Visierung im Modell genau dort
## sitzt. Tut sie es nicht — weil das Modell sie leicht neben der Mitte hat —,
## wird der Versatz hier ausgeglichen.
##
## NICHT fuer den Bildausschnitt benutzen: Diese Verschiebung wirkt in JEDER
## Haltung, auch beim Zielen. Wie die Waffe im Hueftanschlag sitzt, gehoert in
## `hip_position`, die beim Zielen weggeblendet wird.
## GEMESSEN: Die Waffe steht in ihrer eigenen Datei nicht mittig. Ihre
## Laengsachse — Lauf, Schiene, Kornring — liegt bei x = -0.0053. Zentriert
## wurde beim Einpassen die HUELLE des Modells, und die ist unsymmetrisch,
## weil Ladehebel und Auswurffenster rechts sitzen.
##
## Ohne diesen Ausgleich zielt man 5 mm neben der eigenen Waffe vorbei: Die
## Kamera steht auf x = 0, die Visierung auf x = -0.0053.
const FIT_OFFSET := Vector3(0.0053, 0.0, 0.0)


func get_model_name() -> String:
	return "akm"


func _configure() -> void:
	# Dieselbe Zahl, auf der die Kerbe der Kimme steht. `weapon_view` senkt die
	# Waffe beim Zielen um genau diesen Wert ab — damit landet die Visierlinie
	# auf der Bildmitte, und zwar ohne dass hier irgendetwas nachjustiert
	# werden muesste. Wer SIGHT_LINE aendert, aendert beides zugleich.
	sight_height = SIGHT_LINE

	# Wie weit die Waffe beim Zielen vor dem Auge steht.
	#
	# Vorher stand hier 0.015 — die Waffe lag damit im Auge. Das hintere Ende
	# des Schaftes sass anderthalb Zentimeter vor der Kamera und fuellte den
	# halben Bildschirm; vom Zielbild war nichts uebrig. Naeher heisst hier
	# NICHT besser: Was dicht vor dem Auge steht, wird riesig, und die Waffe
	# ist von der Muendung bis zum Schaftende ueber einen halben Meter lang.
	#
	# Bei 0.06 sitzt das hintere Ende der Visierlinie gut zwei Handbreit vor
	# dem Auge — dort, wo es beim Anschlag auch waere.
	ads_distance = 0.06
	muzzle_z = -0.560
	# Schwerer, stumpfer, kickt spuerbar mehr.
	recoil_scale = 1.35
	action_travel = 0.090
	action_cycle_time = 0.062
	magazine_drop = 0.40

	# Der Bildausschnitt im Hueftanschlag gehoert HIERHER und nicht in die
	# Modellverschiebung: `weapon_view` blendet die Hueftposition beim Zielen
	# aus, die Modellverschiebung nicht. Wer die Waffe ueber das Modell
	# zurechtruecht, verschiebt die Visierung mit und zielt daneben.
	#
	# Weiter zur Mitte als die AR-15 (0.115) und nach hinten statt nach vorn
	# (die Grundwerte schieben um -0.22 nach vorn): Dieses Modell ist laenger
	# und ragt sonst mit dem Kolben ins Bild.
	hip_position = Vector3(0.075, -0.125, 0.06)


func _build_parts() -> void:
	_build_body()
	_build_sight_points()

	# Die Mündung sitzt am vorderen Ende der Laufachse — daran haengen
	# Muendungsfeuer und der Ausgangspunkt der Kugel.
	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	# Wo die Huelse ausgeworfen wird: rechts am Gehaeuse.
	add_child(ViewmodelParts.pivot("EjectPoint", Vector3(0.028, 0.030, -0.120)))

	# Leere Ankerpunkte fuer Verschluss und Abzug.
	#
	# Das Modell ist EIN Stueck — es gibt hier nichts, was sich einzeln bewegt.
	# Die Punkte existieren trotzdem: `_collect_parts()` findet sie, die
	# Zusage "jede Waffe hat diese Teile" bleibt wahr, und wenn das Modell
	# spaeter in Blender zerlegt wird, haengt der Verschluss genau hier.
	# Solange sie leer sind, bewegt die Mechanik nur Luft — ohne Schaden.
	add_child(ViewmodelParts.pivot("Action", Vector3(0.019, 0.030, -0.120)))
	add_child(ViewmodelParts.pivot("Trigger", Vector3(0.0, -0.020, -0.086)))


## Setzt die beiden Punkte, ueber die gezielt wird — ohne Geometrie.
##
## ---------------------------------------------------------------------------
## HIER STEHT ABSICHTLICH NICHTS IM BILD
##
## Diese Waffe hat keine sichtbare Kimme. Sie ist ein umgebautes AK mit
## durchgehender Schiene: vorn ein Korn im Ring, hinten eine leere Schiene.
## Gezielt wird ueber die Schiene, so wie bei der AR-15 auch.
##
## Es gab hier einmal eine aus Quadern gebaute Kimme. Sie hat getan, was sie
## sollte, und wurde trotzdem wieder entfernt: Lucas will die Waffe so sehen,
## wie sie aus Blender kommt. Die Zahlen, die sie hinterlassen hat, bleiben —
## an ihnen haengt die Zielhaltung, und sie sind gemessen, nicht geraten.
##
## Die Punkte selbst sind leer und im Spiel unsichtbar. Sie stehen trotzdem
## hier, weil `verify_weapon_handling` an ihnen die Visierlinie nachrechnet:
## gleiche Hoehe, mittig, Korn vor Kimme — und vor allem, ob zwischen beiden
## ueberhaupt freie Sicht besteht. Genau diese Pruefung haette den Fehler
## gefunden, an dem hier zwei Nachmittage draufgegangen sind.
func _build_sight_points() -> void:
	# Das Korn steckt im Modell und ist kein eigener Knoten. Dieser Punkt sagt,
	# wo es sitzt — gemessen, nicht gesetzt: Der Kornring endet bei y = 0.0880,
	# z = -0.53. Wer das Modell austauscht, sieht hier, welche Zahl nachgemessen
	# gehoert.
	add_child(ViewmodelParts.pivot("FrontSight",
			Vector3(0.0, SIGHT_LINE, FRONT_SIGHT_Z)))

	# Das hintere Ende der Visierlinie: die Schienenoberkante kurz vor dem
	# Schaft. Dort laege eine Kimme, wenn die Waffe eine haette.
	add_child(ViewmodelParts.pivot("RearSight",
			Vector3(0.0, SIGHT_LINE, REAR_SIGHT_Z)))


## Laedt das Modell, vermisst es und setzt es passend in die Hand.
##
## Faellt das Modell aus (fehlt die Datei nach einem frischen Clone), bleibt die
## Waffe unsichtbar statt mit einem Fehler abzustuerzen — spielbar ist sie ueber
## die Werte in _configure() weiterhin.
func _build_body() -> void:
	var scene := load(MODEL) as PackedScene
	if scene == null:
		push_warning("[AKM] Modell fehlt: %s" % MODEL)
		return

	var body := Node3D.new()
	body.name = "Body"
	body.add_child(scene.instantiate())
	body.transform = _fit_transform()
	add_child(body)


## Rechnet aus der gemessenen Groesse die Lage in der Hand.
##
## Der Lauf ist die laengste Achse. Skaliert auf FIT_LENGTH, um die eigene Mitte
## zentriert, gedreht — und so verschoben, dass die Muendung vorn auf muzzle_z
## und die Laufachse auf Borehoehe sitzt.
##
## Weil die AABB symmetrisch ums Zentrum liegt, stimmt die Muendungslage
## unabhaengig von FIT_YAW: Dreht man die Waffe, wechselt nur, WELCHES Ende
## vorn sitzt — vorn bleibt vorn.
func _fit_transform() -> Transform3D:
	var longest := maxf(MODEL_SIZE.x, maxf(MODEL_SIZE.y, MODEL_SIZE.z))
	var scale := FIT_LENGTH / maxf(0.0001, longest)

	var basis := Basis.from_euler(Vector3(
		deg_to_rad(FIT_PITCH_DEG), deg_to_rad(FIT_YAW_DEG), deg_to_rad(FIT_ROLL_DEG))) \
		* Basis().scaled(Vector3.ONE * scale)

	var half_length := longest * scale * 0.5
	var place := Vector3(0.0, BORE_Y, muzzle_z + half_length) + FIT_OFFSET

	# Erst um die eigene Mitte zentrieren, dann drehen/skalieren und an die
	# Einbaustelle schieben.
	return Transform3D(basis, place) * Transform3D(Basis.IDENTITY, -MODEL_CENTRE)
