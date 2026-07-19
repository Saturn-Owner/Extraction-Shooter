## Winkelgriff fuer die AR-15.
##
## Flacher als der senkrechte Griff: Die Hand liegt darauf statt darum. Das
## fuehrt die Waffe seitlich ruhiger und bleibt handlich, hilft aber weniger
## gegen den Hochschlag.
class_name Ar15ForegripAngled
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_foregrip_angled"


func _configure() -> void:
	file = "AR15_AngledForegrip"
