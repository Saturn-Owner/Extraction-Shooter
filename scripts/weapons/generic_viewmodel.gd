## Platzhalter fuer Waffen, die noch kein eigenes Modell haben.
##
## Bewusst schlicht und erkennbar unfertig: Diese Form soll niemand mit einem
## fertigen Modell verwechseln. Sie existiert nur, damit eine Waffe ohne
## eigenes Viewmodel trotzdem spielbar bleibt, statt unsichtbar zu sein.
##
## Sobald eine Waffe ihr eigenes Modell bekommt, verschwindet sie aus dieser
## Notloesung — der Grundsatz bleibt: jede Waffe eigene Datei, eigene
## Mechanik. Welche noch fehlen, listet verify_arsenal_viewmodels auf.
class_name GenericViewmodel
extends WeaponViewmodel

const BORE_Y := 0.014


func get_model_name() -> String:
	return "platzhalter"


func _configure() -> void:
	sight_height = 0.062
	muzzle_z = -0.480


func _build_parts() -> void:
	var mats := ViewmodelParts.materials()
	var steel: Material = mats["steel"]
	var black: Material = mats["black"]
	var polymer: Material = mats["polymer"]

	add_child(ViewmodelParts.box("Receiver", Vector3(0.038, 0.052, 0.200), Vector3(0.0, 0.014, -0.120), steel))
	add_child(ViewmodelParts.cylinder("Barrel", 0.0095, 0.240, Vector3(0.0, BORE_Y, -0.340), steel))
	add_child(ViewmodelParts.box("Handguard", Vector3(0.040, 0.040, 0.150), Vector3(0.0, BORE_Y, -0.300), polymer))
	add_child(ViewmodelParts.box("Stock", Vector3(0.038, 0.056, 0.130), Vector3(0.0, 0.004, 0.070), polymer))
	add_child(ViewmodelParts.box("PistolGrip", Vector3(0.030, 0.080, 0.040), Vector3(0.0, -0.062, -0.026),
		polymer, Vector3(-18.0, 0.0, 0.0)))

	var rear := ViewmodelParts.pivot("RearSight", Vector3(0.0, sight_height, -0.046))
	rear.add_child(ViewmodelParts.box("RearBlock", Vector3(0.022, 0.014, 0.014), Vector3.ZERO, black))
	add_child(rear)

	var front := ViewmodelParts.pivot("FrontSight", Vector3(0.0, sight_height, -0.420))
	front.add_child(ViewmodelParts.box("FrontPost", Vector3(0.005, 0.016, 0.005), Vector3.ZERO, black))
	add_child(front)

	var mag := ViewmodelParts.pivot("Magazine", Vector3(0.0, -0.052, -0.128))
	mag.add_child(ViewmodelParts.box("MagBody", Vector3(0.026, 0.110, 0.046), Vector3(0.0, -0.055, 0.0), mats["magazine"]))
	add_child(mag)

	var action := ViewmodelParts.pivot("Action", Vector3(0.019, 0.026, -0.098))
	action.add_child(ViewmodelParts.box("BoltFace", Vector3(0.006, 0.026, 0.056), Vector3.ZERO, steel))
	add_child(action)

	var trigger_pivot := ViewmodelParts.pivot("Trigger", Vector3(0.0, -0.044, -0.070))
	trigger_pivot.add_child(ViewmodelParts.box("TriggerBlade", Vector3(0.006, 0.022, 0.008), Vector3(0.0, -0.011, 0.0), steel))
	add_child(trigger_pivot)

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	add_child(ViewmodelParts.pivot("EjectPoint", Vector3(0.028, 0.026, -0.098)))
