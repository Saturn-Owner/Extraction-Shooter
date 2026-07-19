## Glock 17 — Pistole, 9x19, Schlittenverschluss, Magazin im Griff.
##
## Charakter: klein, schnell, wenig Reserve. Die Waffe fuer den Moment, in dem
## das Gewehr leer ist. Sie liegt weiter vom Auge entfernt als ein Gewehr,
## weil der Arm ausgestreckt wird — das allein aendert das Bild deutlich.
##
## EIGENE MECHANIK gegenueber den Gewehren:
##   - Ein Schlitten laeuft ueber die ganze Waffe, kein Verschluss im Fenster
##   - Kein Feuerwahlhebel, kein Ladehebel
##   - Das Magazin faellt aus dem GRIFF, nicht aus einem Schacht davor —
##     der Weg ist kuerzer und die Bewegung eine andere
class_name Glock17Viewmodel
extends WeaponViewmodel

const BORE_Y := 0.012

var _mats: Dictionary


func get_model_name() -> String:
	return "glock17"


func _configure() -> void:
	# Die Visierung sitzt flach auf dem Schlitten, viel tiefer als bei einem
	# Gewehr. Ohne diesen Wert wuerde die Pistole beim Zielen im Bild kleben.
	sight_height = 0.032
	muzzle_z = -0.205
	# Kleine Waffe, harter Stoss im Verhaeltnis zur Masse.
	recoil_scale = 1.15
	action_travel = 0.048
	action_cycle_time = 0.045
	# Kurzer Weg aus dem Griff.
	magazine_drop = 0.20
	# Ausgestreckter Arm: weiter vom Auge weg als ein Gewehr, dafuer mittiger.
	hip_position = Vector3(0.085, -0.115, -0.315)
	hip_rotation_degrees = Vector3(0.0, -2.5, 0.0)
	ads_distance = 0.30
	# Beim Nachladen dreht die Pistole staerker ein — der Griff muss sichtbar
	# werden, und der ist bei ihr das Magazingehaeuse.
	reload_position = Vector3(0.060, -0.135, -0.255)
	reload_rotation_degrees = Vector3(18.0, 26.0, -42.0)


func _build_parts() -> void:
	_mats = ViewmodelParts.materials()
	_build_frame()
	_build_slide()
	_build_sights()
	_build_moving_parts()

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	add_child(ViewmodelParts.pivot("EjectPoint", Vector3(0.016, 0.026, -0.120)))

	# Aufnahmen. Die Pistole hat bewusst nur zwei: Ihr Griff ist Teil des
	# Griffstuecks und laesst sich nicht tauschen, und ein Vordergriff waere
	# an einer Waffe ohne Vorderschaft sinnlos.
	# Ausfraesung im Schlitten, hinten oben.
	add_child(ViewmodelParts.pivot("MountSight", Vector3(0.0, 0.036, -0.030)))
	add_child(ViewmodelParts.pivot("MountMuzzle", Vector3(0.0, BORE_Y, -0.196)))


## Polymergriffstueck mit Abzugsbuegel.
func _build_frame() -> void:
	var polymer: Material = _mats["polymer"]
	var black: Material = _mats["black"]
	var steel: Material = _mats["steel"]

	add_child(ViewmodelParts.box("Frame", Vector3(0.026, 0.026, 0.150), Vector3(0.0, -0.014, -0.080), polymer))
	add_child(ViewmodelParts.box("DustCover", Vector3(0.022, 0.018, 0.070), Vector3(0.0, -0.010, -0.140), polymer))
	add_child(ViewmodelParts.box("AccessoryRail", Vector3(0.014, 0.006, 0.038), Vector3(0.0, -0.021, -0.150), black))

	# Griff mit dem typisch steilen Winkel.
	# Griff als Baugruppe, damit die Riffelung die Neigung mitmacht.
	var grip := ViewmodelParts.pivot("GripAssembly", Vector3(0.0, -0.076, -0.018))
	grip.rotation_degrees = Vector3(-11.0, 0.0, 0.0)
	grip.add_child(ViewmodelParts.box("Grip", Vector3(0.028, 0.098, 0.038), Vector3.ZERO, polymer))
	grip.add_child(ViewmodelParts.box("Backstrap", Vector3(0.024, 0.090, 0.010), Vector3(0.0, 0.004, 0.022), polymer))
	# Die grobe Griffnarbung der Glock, angedeutet durch waagerechte Rippen
	# vorn und hinten. Bei einer Pistole ist der Griff das groesste sichtbare
	# Bauteil — bleibt er glatt, sieht die ganze Waffe unfertig aus.
	grip.add_child(ViewmodelParts.ribs("GripFront", 10, Vector3(0.025, 0.0035, 0.0022),
		Vector3(0.0, -0.040, -0.0190), Vector3(0.0, 0.0086, 0.0), polymer))
	grip.add_child(ViewmodelParts.ribs("GripBack", 10, Vector3(0.021, 0.0035, 0.0022),
		Vector3(0.0, -0.040, 0.0270), Vector3(0.0, 0.0086, 0.0), polymer))
	add_child(grip)
	add_child(ViewmodelParts.box("Beavertail", Vector3(0.024, 0.012, 0.024), Vector3(0.0, -0.028, 0.006), polymer))
	add_child(ViewmodelParts.box("MagFunnel", Vector3(0.030, 0.010, 0.040), Vector3(0.0, -0.124, -0.006),
		polymer, Vector3(-11.0, 0.0, 0.0)))

	# Abzugsbuegel.
	add_child(ViewmodelParts.box("GuardFront", Vector3(0.008, 0.026, 0.006), Vector3(0.0, -0.040, -0.086), polymer))
	add_child(ViewmodelParts.box("GuardBottom", Vector3(0.008, 0.006, 0.042), Vector3(0.0, -0.051, -0.066), polymer))

	add_child(ViewmodelParts.box("MagRelease", Vector3(0.008, 0.012, 0.010), Vector3(0.016, -0.036, -0.038), black))
	add_child(ViewmodelParts.box("SlideStop", Vector3(0.005, 0.008, 0.030), Vector3(-0.015, -0.016, -0.062), steel))


## Der Schlitten ist als "Action" gefuehrt und laeuft bei jedem Schuss
## ueber die ganze Waffe zurueck.
func _build_slide() -> void:
	var blued: Material = _mats["blued"]
	var black: Material = _mats["black"]

	var slide := ViewmodelParts.pivot("Action", Vector3(0.0, 0.0, 0.0))
	slide.add_child(ViewmodelParts.box("SlideBody", Vector3(0.026, 0.032, 0.180), Vector3(0.0, 0.014, -0.092), blued))
	# Abgeflachte Oberkante — sonst ist es nur ein Riegel.
	slide.add_child(ViewmodelParts.box("SlideTop", Vector3(0.018, 0.008, 0.180), Vector3(0.0, 0.031, -0.092), blued))
	slide.add_child(ViewmodelParts.box("EjectionPort", Vector3(0.006, 0.016, 0.038), Vector3(0.013, 0.020, -0.118), black))

	# Griffrillen hinten. Wiederholung ist auch hier das billigste Detail.
	#
	# Schmaler als der Schlitten (0.026): Vorher waren sie mit 0.028 BREITER
	# und standen auf beiden Seiten ueber — von links sah der Schlitten aus,
	# als haette er Zaehne. Rillen sind eingefraest, nicht aufgesetzt.
	for i in range(7):
		slide.add_child(ViewmodelParts.box(
			"SlideSerration%d" % i,
			Vector3(0.0235, 0.024, 0.0035),
			Vector3(0.0, 0.014, -0.014 - float(i) * 0.0075),
			_mats["recess"]
		))

	slide.add_child(ViewmodelParts.cylinder("Barrel", 0.0075, 0.030, Vector3(0.0, BORE_Y, -0.192), _mats["steel"]))
	add_child(slide)


## Kimme und Korn sitzen in Wirklichkeit auf dem Schlitten und laufen beim
## Schuss mit. Hier haengen sie am Rahmen: Der Zyklus dauert 45 Millisekunden,
## in denen der Spieler ohnehin nichts anvisiert — dafuer bleibt die
## Visierlinie fuer das Zielen zuverlaessig an ihrem Platz.
func _build_sights() -> void:
	var black: Material = _mats["black"]

	var rear := ViewmodelParts.pivot("RearSight", Vector3(0.0, sight_height, -0.026))
	rear.add_child(ViewmodelParts.box("RearBlockL", Vector3(0.007, 0.011, 0.008), Vector3(-0.008, 0.0, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearBlockR", Vector3(0.007, 0.011, 0.008), Vector3(0.008, 0.0, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearBase", Vector3(0.023, 0.005, 0.008), Vector3(0.0, -0.006, 0.0), black))
	add_child(rear)

	var front := ViewmodelParts.pivot("FrontSight", Vector3(0.0, sight_height, -0.176))
	front.add_child(ViewmodelParts.box("FrontPost", Vector3(0.004, 0.010, 0.004), Vector3.ZERO, black))
	add_child(front)


func _build_moving_parts() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]
	var mag_mat: Material = _mats["magazine"]

	# Das Magazin steckt im Griff und ist von aussen nur unten zu sehen.
	# Beim Wechsel faellt es entlang der Griffachse heraus, nicht senkrecht.
	var mag := ViewmodelParts.pivot("Magazine", Vector3(0.0, -0.072, -0.016))
	mag.add_child(ViewmodelParts.box("MagBody", Vector3(0.024, 0.092, 0.032), Vector3(0.0, 0.0, 0.0),
		mag_mat, Vector3(-11.0, 0.0, 0.0)))
	mag.add_child(ViewmodelParts.box("MagFloor", Vector3(0.028, 0.010, 0.038), Vector3(0.0, -0.050, 0.010),
		black, Vector3(-11.0, 0.0, 0.0)))
	add_child(mag)

	var trigger_pivot := ViewmodelParts.pivot("Trigger", Vector3(0.0, -0.030, -0.070))
	trigger_pivot.add_child(ViewmodelParts.box("TriggerBlade", Vector3(0.006, 0.020, 0.007), Vector3(0.0, -0.010, 0.0),
		black, Vector3(6.0, 0.0, 0.0)))
	trigger_pivot.add_child(ViewmodelParts.box("TriggerSafety", Vector3(0.003, 0.016, 0.004), Vector3(0.0, -0.010, -0.004), steel))
	add_child(trigger_pivot)


## Das Magazin faellt beim Nachladen entlang der Griffachse nach unten und
## vorn, nicht senkrecht wie bei einem Gewehr. Ohne das sieht es aus, als
## wuerde es durch den Griff hindurchfallen.
func _animate_magazine_swap(progress: float) -> void:
	if magazine == null:
		return

	# Griffwinkel: Der Auswurf folgt dieser Richtung.
	var along_grip := Vector3(0.0, -1.0, -0.19).normalized()

	if progress < 0.28:
		var t := _ramp(progress, 0.0, 0.28)
		magazine.visible = true
		magazine.position = _magazine_home + along_grip * magazine_drop * t
		magazine.rotation_degrees = Vector3(10.0 * t, 0.0, 4.0 * t)
	elif progress < 0.44:
		magazine.visible = false
	else:
		var t := _ramp(progress, 0.44, 0.86)
		magazine.visible = true
		magazine.position = _magazine_home + along_grip * magazine_drop * 0.9 * (1.0 - t)
		magazine.rotation_degrees = Vector3(8.0 * (1.0 - t), 0.0, 0.0)


## Bei leerer Pistole bleibt der Schlitten hinten. Nachladen endet damit,
## dass er per Schlittenfang vorschnellt — deshalb hier kein Ladehebelzug
## wie bei den Gewehren.
func notify_reload(progress: float, from_empty: bool) -> void:
	_animate_magazine_swap(progress)
	_handle_pull = 0.0
	if from_empty and progress > 0.90:
		notify_action_locked(false)
