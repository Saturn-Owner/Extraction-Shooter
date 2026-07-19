## AKM — Sturmgewehr, Langhubkolben, Holzschaft, 7,62x39.
##
## Charakter: schwerer und stumpfer als die AR-15. Kraeftiger Rueckstoss,
## traegeres Handling — dafuer unempfindlich. Wer von der AR-15 umsteigt,
## soll den Unterschied sofort spueren, nicht erst im Datenblatt lesen.
##
## EIGENE MECHANIK: Der Ladehebel sitzt fest am Verschlusstraeger und fliegt
## bei JEDEM Schuss mit nach hinten. Das ist der auffaelligste Unterschied zur
## AR-15, wo der Ladehebel stehen bleibt — und genau deshalb bekommt jede
## Waffe eine eigene Datei statt eines gemeinsamen Platzhalters.
class_name AKMViewmodel
extends WeaponViewmodel

const BORE_Y := 0.014

var _mats: Dictionary


func get_model_name() -> String:
	return "akm"


func _configure() -> void:
	# Die AK-Visierung baut hoeher als die der AR-15.
	sight_height = 0.074
	muzzle_z = -0.560
	# Schwerer, stumpfer, kickt spuerbar mehr.
	recoil_scale = 1.35
	action_travel = 0.090
	action_cycle_time = 0.062
	# Das lange 7,62er-Magazin faellt weiter.
	magazine_drop = 0.40
	# Liegt etwas tiefer und schwerer in der Hand.
	hip_position = Vector3(0.118, -0.135, -0.215)
	hip_rotation_degrees = Vector3(0.0, -3.0, 0.0)


func _build_parts() -> void:
	_mats = ViewmodelParts.materials()
	_build_receiver()
	_build_barrel()
	_build_furniture()
	_build_sights()
	_build_moving_parts()

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	add_child(ViewmodelParts.pivot("EjectPoint", Vector3(0.028, 0.030, -0.120)))


## Kastenfoermiges Blechgehaeuse mit aufgesetztem Deckel — die Form, an der
## man eine Kalaschnikow auf hundert Meter erkennt.
func _build_receiver() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]
	var blued: Material = _mats["blued"]

	add_child(ViewmodelParts.box("Receiver", Vector3(0.036, 0.054, 0.195), Vector3(0.0, 0.014, -0.130), steel))
	# Der gewoelbte Deckel: zwei Platten im Winkel statt eines flachen Kastens.
	add_child(ViewmodelParts.box("TopCoverL", Vector3(0.024, 0.008, 0.185), Vector3(-0.010, 0.044, -0.130),
		blued, Vector3(0.0, 0.0, 26.0)))
	add_child(ViewmodelParts.box("TopCoverR", Vector3(0.024, 0.008, 0.185), Vector3(0.010, 0.044, -0.130),
		blued, Vector3(0.0, 0.0, -26.0)))
	add_child(ViewmodelParts.box("CoverRidge", Vector3(0.014, 0.007, 0.185), Vector3(0.0, 0.050, -0.130), blued))

	# Auswurffenster rechts, deutlich groesser als bei der AR-15.
	add_child(ViewmodelParts.box("EjectionPort", Vector3(0.005, 0.026, 0.070), Vector3(0.019, 0.030, -0.120), black))

	# Der Sicherungshebel: das grosse Blech rechts aussen, unverwechselbar.
	add_child(ViewmodelParts.box("SafetyPlate", Vector3(0.005, 0.070, 0.026), Vector3(0.020, 0.006, -0.086),
		blued, Vector3(12.0, 0.0, 0.0)))

	add_child(ViewmodelParts.box("Magwell", Vector3(0.032, 0.020, 0.052), Vector3(0.0, -0.020, -0.150), steel))

	# Abzugsbuegel.
	add_child(ViewmodelParts.box("GuardFront", Vector3(0.009, 0.028, 0.006), Vector3(0.0, -0.038, -0.108), steel))
	add_child(ViewmodelParts.box("GuardBottom", Vector3(0.009, 0.006, 0.056), Vector3(0.0, -0.050, -0.082), steel))


func _build_barrel() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]

	add_child(ViewmodelParts.cylinder("Barrel", 0.0105, 0.320, Vector3(0.0, BORE_Y, -0.375), steel))
	# Gasblock und Gasrohr sitzen beim AK offen ueber dem Lauf.
	add_child(ViewmodelParts.cylinder("GasTube", 0.0115, 0.150, Vector3(0.0, BORE_Y + 0.030, -0.310), steel))
	add_child(ViewmodelParts.box("GasBlock", Vector3(0.028, 0.056, 0.034), Vector3(0.0, BORE_Y + 0.018, -0.392),
		black, Vector3(-14.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("FrontSightTower", Vector3(0.026, 0.050, 0.026), Vector3(0.0, BORE_Y + 0.020, -0.470), black))

	# Schraege Muendungsbremse — beim AKM oben offen, damit der Lauf
	# beim Dauerfeuer unten bleibt.
	add_child(ViewmodelParts.cylinder("MuzzleBrake", 0.0145, 0.052, Vector3(0.0, BORE_Y, -0.528), black))
	add_child(ViewmodelParts.box("BrakeSlant", Vector3(0.026, 0.026, 0.030), Vector3(0.0, BORE_Y + 0.010, -0.545),
		black, Vector3(-28.0, 0.0, 0.0)))


## Holz. Der zweite grosse Unterschied zur AR-15 — und der Grund, warum die
## Waffe im Bild waermer wirkt.
func _build_furniture() -> void:
	var wood: Material = _mats["wood"]
	var polymer: Material = _mats["polymer"]
	var steel: Material = _mats["steel"]

	# Unterer Handschutz, nach vorn leicht verjuengt.
	add_child(ViewmodelParts.box("LowerHandguard", Vector3(0.046, 0.042, 0.150), Vector3(0.0, BORE_Y - 0.020, -0.300), wood))
	add_child(ViewmodelParts.box("HandguardGripL", Vector3(0.008, 0.030, 0.140), Vector3(-0.024, BORE_Y - 0.020, -0.300),
		wood, Vector3(0.0, 0.0, 14.0)))
	add_child(ViewmodelParts.box("HandguardGripR", Vector3(0.008, 0.030, 0.140), Vector3(0.024, BORE_Y - 0.020, -0.300),
		wood, Vector3(0.0, 0.0, -14.0)))
	# Oberer Handschutz auf dem Gasrohr.
	add_child(ViewmodelParts.box("UpperHandguard", Vector3(0.036, 0.026, 0.130), Vector3(0.0, BORE_Y + 0.036, -0.305), wood))
	add_child(ViewmodelParts.box("RetainerRing", Vector3(0.040, 0.048, 0.014), Vector3(0.0, BORE_Y + 0.008, -0.232), steel))

	# Pistolengriff, steiler als bei der AR-15.
	add_child(ViewmodelParts.box("PistolGrip", Vector3(0.032, 0.086, 0.044), Vector3(0.0, -0.062, -0.036),
		polymer, Vector3(-14.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("GripCap", Vector3(0.034, 0.010, 0.046), Vector3(0.0, -0.104, -0.026),
		polymer, Vector3(-14.0, 0.0, 0.0)))

	# Fester Holzschaft mit abfallendem Ruecken — kein ausziehbares Rohr.
	add_child(ViewmodelParts.box("StockNeck", Vector3(0.034, 0.044, 0.070), Vector3(0.0, -0.008, 0.010),
		wood, Vector3(6.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("StockBody", Vector3(0.038, 0.062, 0.120), Vector3(0.0, -0.020, 0.090),
		wood, Vector3(6.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("ButtPlate", Vector3(0.040, 0.070, 0.012), Vector3(0.0, -0.030, 0.150),
		_mats["black"], Vector3(6.0, 0.0, 0.0)))


func _build_sights() -> void:
	var black: Material = _mats["black"]

	# Kimme: offener Kerbeneinschnitt, keine Lochblende wie bei der AR-15.
	var rear := ViewmodelParts.pivot("RearSight", Vector3(0.0, sight_height, -0.228))
	rear.add_child(ViewmodelParts.box("RearBlockL", Vector3(0.009, 0.016, 0.018), Vector3(-0.011, -0.004, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearBlockR", Vector3(0.009, 0.016, 0.018), Vector3(0.011, -0.004, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearBase", Vector3(0.032, 0.010, 0.030), Vector3(0.0, -0.014, 0.0), black))
	add_child(rear)

	# Korn: Pfosten in einem geschlossenen Ring — typisch AK.
	var front := ViewmodelParts.pivot("FrontSight", Vector3(0.0, sight_height, -0.478))
	front.add_child(ViewmodelParts.box("FrontPost", Vector3(0.004, 0.020, 0.004), Vector3(0.0, -0.002, 0.0), black))
	front.add_child(ViewmodelParts.box("HoodL", Vector3(0.005, 0.028, 0.012), Vector3(-0.011, 0.0, 0.0), black))
	front.add_child(ViewmodelParts.box("HoodR", Vector3(0.005, 0.028, 0.012), Vector3(0.011, 0.0, 0.0), black))
	front.add_child(ViewmodelParts.box("HoodTop", Vector3(0.026, 0.005, 0.012), Vector3(0.0, 0.014, 0.0), black))
	add_child(front)


func _build_moving_parts() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]
	var mag_mat: Material = _mats["magazine"]

	# Das gekruemmte 7,62er-Magazin — die Sichel, die dem Gewehr sein Profil
	# gibt. Deutlich staerker gebogen als das gerade STANAG der AR-15.
	var mag := ViewmodelParts.pivot("Magazine", Vector3(0.0, -0.030, -0.150))
	for i in range(5):
		var t := float(i)
		mag.add_child(ViewmodelParts.box(
			"MagSegment%d" % i,
			Vector3(0.026, 0.038, 0.052 - t * 0.002),
			Vector3(0.0, -0.018 - t * 0.033, -0.002 - t * 0.0075),
			mag_mat,
			Vector3(-t * 5.5, 0.0, 0.0)
		))
	mag.add_child(ViewmodelParts.box("MagFloor", Vector3(0.030, 0.012, 0.046), Vector3(0.0, -0.156, -0.032),
		black, Vector3(-27.5, 0.0, 0.0)))
	add_child(mag)

	# Verschlusstraeger mit fest angesetztem Ladehebel rechts.
	var carrier := ViewmodelParts.pivot("Action", Vector3(0.019, 0.030, -0.120))
	carrier.add_child(ViewmodelParts.box("BoltCarrier", Vector3(0.006, 0.024, 0.066), Vector3.ZERO, steel))
	carrier.add_child(ViewmodelParts.box("ChargingKnob", Vector3(0.016, 0.014, 0.020), Vector3(0.010, 0.0, 0.026), steel))
	add_child(carrier)

	var trigger_pivot := ViewmodelParts.pivot("Trigger", Vector3(0.0, -0.020, -0.086))
	trigger_pivot.add_child(ViewmodelParts.box("TriggerBlade", Vector3(0.006, 0.024, 0.008), Vector3(0.0, -0.012, 0.0),
		steel, Vector3(8.0, 0.0, 0.0)))
	add_child(trigger_pivot)

	# Der Feuerwahlhebel ist beim AK das grosse Blech rechts.
	var selector_pivot := ViewmodelParts.pivot("Selector", Vector3(0.021, 0.020, -0.062))
	selector_pivot.add_child(ViewmodelParts.box("SelectorLever", Vector3(0.005, 0.048, 0.016),
		Vector3(0.0, -0.020, 0.0), _mats["blued"]))
	add_child(selector_pivot)


## AK-EIGENHEIT: Der Ladehebel sitzt am Verschlusstraeger. Er fliegt bei
## jedem Schuss mit — bei der AR-15 bleibt er stehen. Deshalb wird hier kein
## eigener ChargingHandle-Knoten gefuehrt, sondern der Griff ist Teil von
## "Action" und bewegt sich automatisch mit.
##
## Beim Nachladen und beim Beheben einer Hemmung zieht der Spieler stattdessen
## den ganzen Traeger zurueck.
func update_mechanics(delta: float) -> void:
	super(delta)
	if action == null or _handle_pull <= 0.0:
		return
	# Handzug ueberlagert den Zyklus: Was weiter hinten ist, gewinnt.
	var pulled := _handle_pull * action_travel
	action.position.z = maxf(action.position.z, _action_home.z + pulled)
