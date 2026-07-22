## Winkelgriff fuer die AR-15.
##
## Flacher als der senkrechte Griff: Die Hand liegt darauf statt darum. Das
## fuehrt die Waffe seitlich ruhiger und bleibt handlich, hilft aber weniger
## gegen den Hochschlag.
##
## UEBERGANG: Im Sketchfab-Modell gibt es keinen Winkelgriff, deshalb bleibt
## die alte Blender-Datei — gesetzt an die GEMESSENE Unterkante des neuen
## Handschutzes (ar15_glb_part.gd, Sorte 2). Ein eigenes Modell darf sie
## abloesen.
class_name Ar15ForegripAngled
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_foregrip_angled"


func _configure() -> void:
	file = "AR15_AngledForegrip"
	# Unterkante des Handschutzes (Modell: y -0.0534), vorderes Drittel —
	# minus die halbe Griffhoehe: Die Datei ist um ihren Mittelpunkt
	# zentriert, die Oberkante soll am Handschutz anliegen. Der Wert ist am
	# RENDER nachjustiert (rechnerisch 0.048, aber der Griffkopf ragt in die
	# Schiene hinein wie beim alten Modell auch): 0.018 schliesst die Luecke.
	place = AR15Viewmodel.fit_transform_for(AR15Viewmodel.MUZZLE_Z) \
		* Vector3(2.6, -0.0534, 0.0) \
		- Vector3(0.0, 0.018, 0.0)
