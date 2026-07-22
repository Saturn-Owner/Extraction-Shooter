## Holografisches Visier fuer die AR-15 — das EOtech EXPS-2 aus dem
## Waffenmodell (siehe ar15_glb_part.gd, Sorte 1).
##
## Groesseres Fenster als der Rotpunkt, dafuer schwerer und sperriger. Das
## breite Sichtfeld ist der Grund, warum man es trotzdem nimmt.
class_name Ar15Holo
extends Ar15GlbPart

## Zielpunkt im MODELLRAUM — als Konstante, weil das Sketchfab-EOtech nur ein
## Sammelmaterial ("eotech") hat und sich der Leuchtpunkt nicht per
## Materialname finden laesst (siehe aim_centre in der Basisklasse).
##
## GEMESSEN: Das Gehaeuse reicht von y 0.4823 bis 1.1782 (Messprotokoll des
## Konverters). Beim echten EXPS-2 liegt die optische Achse gut auf halber
## Gehaeusehoehe — das ergibt y ≈ 0.88. Die Fensterfront sitzt bei x ≈ 0.3,
## seitlich mittig (z ≈ 0). Ob der Punkt im Fenster mittig WIRKT, muss ein
## Mensch beim Zielen pruefen — dann hier nachziehen.
const AIM_MODEL := Vector3(0.3, 0.88, 0.0)


func get_model_name() -> String:
	return "ar15_holo"


func _configure() -> void:
	extract_node = "EOtech EXPS-2"


func _build_parts() -> void:
	super()
	# Relativ zum Teil: Die Lage des Teils steckt schon in `position`, uebrig
	# bleibt der Weg vom Teil-Ursprung zum Fenster.
	var fit := AR15Viewmodel.fit_transform_for(AR15Viewmodel.MUZZLE_Z)
	add_child(ViewmodelParts.pivot("AimPoint", fit * AIM_MODEL - position))
