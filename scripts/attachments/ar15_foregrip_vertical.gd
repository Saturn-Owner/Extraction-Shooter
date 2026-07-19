## Senkrechter Vordergriff fuer die AR-15.
##
## Man zieht die Waffe in die Schulter statt sie nur zu halten. Das druckt
## den Hochschlag, kostet aber Beweglichkeit beim Schwenken.
class_name Ar15ForegripVertical
extends Ar15GlbPart


func get_model_name() -> String:
	return "ar15_foregrip_vertical"


func _configure() -> void:
	file = "AR15_Foregrip"
