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
const FIT_OFFSET := Vector3(0.008, 0.0, 0.0)


func get_model_name() -> String:
	return "akm"


func _configure() -> void:
	# GEMESSEN, nicht geschaetzt: Das Modell reicht im Viewmodel-Raum bis
	# y = 0.088 hinauf, die Visierung sitzt knapp darunter. Genau um diesen
	# Wert senkt `weapon_view` die Waffe beim Zielen ab, damit die Kimme in der
	# Bildmitte landet. Wer hier danebenliegt, zielt an der eigenen Visierung
	# vorbei.
	sight_height = 0.082

	# Beim Zielen dicht ans Auge statt nach vorn geschoben (Grundwert 0.16).
	#
	# Der Grund ist der Kolben: Je weiter die Waffe beim Zielen vom Auge weg
	# steht, desto weiter rutscht ihr hinteres Ende von unten ins Bild. Nah am
	# Auge faellt alles unterhalb der Visierlinie aus dem Bildrand — man sieht
	# Kimme und Lauf, sonst nichts. Dieses Modell ist laenger als die anderen
	# und braucht das deutlicher.
	ads_distance = -0.11
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
