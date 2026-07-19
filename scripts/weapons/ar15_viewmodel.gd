## AR-15 — Sturmgewehr, Direktgassystem, abnehmbares Stangenmagazin.
##
## Charakter: leicht, handlich, wenig Rueckstoss. Die Waffe soll sich im Bild
## ruhig und praezise anfuehlen — sie ist die Referenz, an der sich alle
## anderen messen.
##
## KOORDINATEN: -Z ist vorne, +Y oben, +X rechts. Der Ursprung liegt hinten
## am Gehaeuse, dort wo der Puffer ansetzt. Masse an einer echten AR-15 mit
## 14,5-Zoll-Lauf orientiert.
class_name AR15Viewmodel
extends WeaponViewmodel

## Hoehe der Laufachse. Alles Runde sitzt auf dieser Linie.
const BORE_Y := 0.014

## Oberkante der Schiene. Kimme und Korn bauen darauf auf.
const RAIL_Y := 0.050

var _mats: Dictionary


func get_model_name() -> String:
	return "ar15"


func _configure() -> void:
	sight_height = 0.068
	muzzle_z = -0.575
	# Leichte, gut ausbalancierte Waffe: liegt ruhig und kickt wenig.
	recoil_scale = 0.9
	action_travel = 0.075
	action_cycle_time = 0.055


func _build_parts() -> void:
	_mats = ViewmodelParts.materials()
	_build_upper_receiver()
	_build_lower_receiver()
	_build_handguard()
	_build_barrel()
	_build_sights()
	_build_stock()
	_build_moving_parts()

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	add_child(ViewmodelParts.pivot("EjectPoint", Vector3(0.030, 0.026, -0.098)))
	_build_mounts()


## Aufnahmen fuer Anbauteile.
##
## Bewusst ungedrehte, direkte Kinder des Modells: weapon_viewmodel.gd rechnet
## Visierhoehe und Muendung durch schlichtes Addieren der Positionen aus. Mit
## verschachtelten oder gedrehten Aufnahmen muesste dort ueber Transformationen
## gerechnet werden — mehr Aufwand fuer nichts.
func _build_mounts() -> void:
	# Auf der Schiene, knapp ueber deren Zaehnen.
	add_child(ViewmodelParts.pivot("MountSight", Vector3(0.0, RAIL_Y + 0.007, -0.100)))
	# Am Laufgewinde, dort wo sonst die Muendungsbremse sitzt.
	add_child(ViewmodelParts.pivot("MountMuzzle", Vector3(0.0, BORE_Y, -0.520)))
	# Exakt dort, wo der eingebaute Griff haengt.
	add_child(ViewmodelParts.pivot("MountGrip", Vector3(0.0, -0.082, -0.030)))
	# Unterseite des Handschutzes.
	add_child(ViewmodelParts.pivot("MountForegrip", Vector3(0.0, BORE_Y - 0.026, -0.330)))


## Oberes Gehaeuse mit Picatinny-Schiene, Auswurffenster und Huelsenabweiser.
func _build_upper_receiver() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]

	add_child(ViewmodelParts.box("UpperReceiver", Vector3(0.038, 0.050, 0.200), Vector3(0.0, 0.020, -0.125), steel))
	# Schmalerer Streifen obendrauf. Faked eine Fase — die Kante bricht das
	# Licht anders und der Quader wirkt weniger wie ein Quader.
	add_child(ViewmodelParts.box("UpperTop", Vector3(0.030, 0.008, 0.200), Vector3(0.0, 0.045, -0.125), steel))
	add_child(ViewmodelParts.box("RailBase", Vector3(0.022, 0.006, 0.198), Vector3(0.0, RAIL_Y - 0.003, -0.126), black))
	ViewmodelParts.rail(self, "UpperRail", -0.030, -0.222, RAIL_Y + 0.003, black)

	# Auswurffenster mit Staubschutzklappe (rechts).
	add_child(ViewmodelParts.box("EjectionPort", Vector3(0.005, 0.028, 0.058), Vector3(0.0205, 0.026, -0.100), black))
	add_child(ViewmodelParts.box("PortHinge", Vector3(0.004, 0.007, 0.062), Vector3(0.0205, 0.010, -0.100), steel))
	add_child(ViewmodelParts.box("BrassDeflector", Vector3(0.010, 0.020, 0.022), Vector3(0.021, 0.032, -0.068),
		steel, Vector3(0.0, 0.0, -28.0)))
	add_child(ViewmodelParts.cylinder("ForwardAssist", 0.0075, 0.026, Vector3(0.021, 0.012, -0.058), steel))
	add_child(ViewmodelParts.cylinder("ForwardAssistCap", 0.0095, 0.008, Vector3(0.021, 0.012, -0.046), black))


func _build_lower_receiver() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]
	var polymer: Material = _mats["polymer"]

	add_child(ViewmodelParts.box("LowerReceiver", Vector3(0.032, 0.046, 0.140), Vector3(0.0, -0.029, -0.098), steel))
	add_child(ViewmodelParts.box("Magwell", Vector3(0.036, 0.034, 0.054), Vector3(0.0, -0.050, -0.130), steel))
	add_child(ViewmodelParts.box("MagwellFlare", Vector3(0.040, 0.008, 0.058), Vector3(0.0, -0.068, -0.131), steel))

	# Bedienelemente. Winzig, aber genau die Dinger sucht das Auge.
	add_child(ViewmodelParts.cylinder("MagRelease", 0.0055, 0.012, Vector3(0.019, -0.024, -0.146), black,
		Vector3(0.0, 0.0, 90.0)))
	add_child(ViewmodelParts.box("BoltCatch", Vector3(0.006, 0.013, 0.030), Vector3(-0.018, -0.024, -0.140), black))
	add_child(ViewmodelParts.box("TakedownPin", Vector3(0.006, 0.010, 0.010), Vector3(-0.018, -0.012, -0.038), steel))

	# Abzugsbuegel als geschlossene Schlaufe aus drei Teilen.
	add_child(ViewmodelParts.box("GuardFront", Vector3(0.009, 0.030, 0.006), Vector3(0.0, -0.068, -0.098), steel))
	add_child(ViewmodelParts.box("GuardBottom", Vector3(0.009, 0.006, 0.052), Vector3(0.0, -0.081, -0.074), steel))
	add_child(ViewmodelParts.box("GuardRear", Vector3(0.009, 0.016, 0.006), Vector3(0.0, -0.074, -0.050), steel,
		Vector3(24.0, 0.0, 0.0)))

	# Griff als eigene Baugruppe, damit die Riffelung die Neigung des Griffs
	# mitmacht, statt sie an jedem einzelnen Teil wiederholen zu muessen.
	var grip := ViewmodelParts.pivot("GripAssembly", Vector3(0.0, -0.082, -0.030))
	grip.rotation_degrees = Vector3(-17.0, 0.0, 0.0)
	grip.add_child(ViewmodelParts.box("PistolGrip", Vector3(0.032, 0.074, 0.042), Vector3.ZERO, polymer))
	grip.add_child(ViewmodelParts.box("GripFlare", Vector3(0.035, 0.010, 0.046), Vector3(0.0, -0.038, 0.006), polymer))
	# Riffelung vorn und hinten. Das ist die Stelle, die der Spieler beim
	# Nachladen aus naechster Naehe sieht.
	# Bewusst flach und dicht: Zu dicke Rippen mit grossen Luecken sehen aus
	# wie eine angeschraubte Leiter, nicht wie eine gegriffige Oberflaeche.
	grip.add_child(ViewmodelParts.ribs("GripFront", 8, Vector3(0.029, 0.0035, 0.0022),
		Vector3(0.0, -0.029, -0.0210), Vector3(0.0, 0.0082, 0.0), polymer))
	grip.add_child(ViewmodelParts.ribs("GripBack", 8, Vector3(0.029, 0.0035, 0.0022),
		Vector3(0.0, -0.029, 0.0210), Vector3(0.0, 0.0082, 0.0), polymer))
	add_child(grip)

	add_child(ViewmodelParts.box("GripTang", Vector3(0.028, 0.016, 0.024), Vector3(0.0, -0.052, -0.036), polymer))

	# Die beiden Verschlussbolzen. Winzig, aber das Auge sucht solche Punkte —
	# eine Flaeche mit einem Bolzen wirkt gebaut, eine glatte wirkt gegossen.
	for side in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		add_child(ViewmodelParts.screw("PivotPin" + tag, 0.0055, 0.004,
			Vector3(side * 0.017, -0.014, -0.148), steel))
		add_child(ViewmodelParts.screw("TakedownPin" + tag, 0.0055, 0.004,
			Vector3(side * 0.017, -0.014, -0.040), steel))


## Achteckiger Handschutz mit durchlaufender Schiene bis kurz vor die Muendung.
func _build_handguard() -> void:
	var furniture: Material = _mats["furniture"]
	var black: Material = _mats["black"]
	var center_z := -0.345

	add_child(ViewmodelParts.octagon_tube("Handguard", 0.025, 0.225,
		Vector3(0.0, BORE_Y, center_z), furniture))
	add_child(ViewmodelParts.cylinder("HandguardCollar", 0.028, 0.014, Vector3(0.0, BORE_Y, -0.232), black))
	add_child(ViewmodelParts.cylinder("HandguardCap", 0.027, 0.010, Vector3(0.0, BORE_Y, -0.456), black))

	# Eine durchgehende Oberkante ist das, was moderne Gewehre ausmacht.
	add_child(ViewmodelParts.box("HandguardRailBase", Vector3(0.022, 0.006, 0.220),
		Vector3(0.0, RAIL_Y - 0.003, center_z), black))
	ViewmodelParts.rail(self, "HandguardRail", -0.232, -0.452, RAIL_Y + 0.003, black)

	# M-LOK-Schlitze an beiden Seiten und unten. Ein glatter Handschutz ist
	# die groesste zusammenhaengende Flaeche der Waffe — bleibt sie leer,
	# faellt genau dort auf, dass das Modell unfertig ist.
	# Mattes, sehr dunkles Material statt des metallischen: Metall spiegelt
	# den Himmel und leuchtet heller als der Handschutz — die Schlitze sahen
	# dadurch aus wie aufgesetzte Chromplaettchen statt wie Loecher.
	var recess: Material = _mats["recess"]
	for side in [-1.0, 1.0]:
		add_child(ViewmodelParts.ribs("Mlok%s" % ("L" if side < 0.0 else "R"), 6,
			Vector3(0.004, 0.009, 0.024),
			Vector3(side * 0.0245, BORE_Y, -0.268), Vector3(0.0, 0.0, -0.030), recess))
	add_child(ViewmodelParts.ribs("MlokBottom", 6, Vector3(0.009, 0.004, 0.024),
		Vector3(0.0, BORE_Y - 0.0245, -0.268), Vector3(0.0, 0.0, -0.030), recess))


func _build_barrel() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]

	add_child(ViewmodelParts.cylinder("Barrel", 0.0095, 0.310, Vector3(0.0, BORE_Y, -0.395), steel))
	# Flacher Gasblock, sitzt unter dem Handschutz.
	add_child(ViewmodelParts.box("GasBlock", Vector3(0.022, 0.018, 0.026), Vector3(0.0, BORE_Y + 0.008, -0.400), black))
	add_child(ViewmodelParts.cylinder("GasTube", 0.0032, 0.165, Vector3(0.0, BORE_Y + 0.016, -0.325), steel))

	# Muendungsbremse als abgesetzter Zylinder. Abstehende Zinken sahen in
	# einer frueheren Fassung aus wie Antennen.
	add_child(ViewmodelParts.taper("FlashHider", 0.0115, 0.0130, 0.050, Vector3(0.0, BORE_Y, -0.546), black))
	add_child(ViewmodelParts.cylinder("HiderRingFront", 0.0140, 0.008, Vector3(0.0, BORE_Y, -0.566), black))
	add_child(ViewmodelParts.cylinder("HiderRingRear", 0.0135, 0.007, Vector3(0.0, BORE_Y, -0.524), black))
	add_child(ViewmodelParts.cylinder("BarrelNut", 0.0165, 0.018, Vector3(0.0, BORE_Y, -0.240), steel))


## Kimme und Korn sitzen mit ihrem Ursprung exakt auf sight_height.
## Nur dann ist die Visierlinie eine Gerade — verify_weapon_handling.gd
## prueft das fuer jede Waffe im Arsenal.
func _build_sights() -> void:
	var black: Material = _mats["black"]

	var rear := ViewmodelParts.pivot("RearSight", Vector3(0.0, sight_height, -0.048))
	rear.add_child(ViewmodelParts.torus("Aperture", 0.005, 0.010, Vector3.ZERO, black, Vector3(90.0, 0.0, 0.0)))
	rear.add_child(ViewmodelParts.box("RearBase", Vector3(0.026, 0.016, 0.020), Vector3(0.0, -0.014, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearWingL", Vector3(0.005, 0.020, 0.014), Vector3(-0.013, -0.002, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearWingR", Vector3(0.005, 0.020, 0.014), Vector3(0.013, -0.002, 0.0), black))
	add_child(rear)

	var front := ViewmodelParts.pivot("FrontSight", Vector3(0.0, sight_height, -0.444))
	front.add_child(ViewmodelParts.box("FrontPost", Vector3(0.004, 0.022, 0.004), Vector3(0.0, -0.003, 0.0), black))
	front.add_child(ViewmodelParts.box("FrontWingL", Vector3(0.0045, 0.026, 0.013), Vector3(-0.0085, -0.002, 0.0), black))
	front.add_child(ViewmodelParts.box("FrontWingR", Vector3(0.0045, 0.026, 0.013), Vector3(0.0085, -0.002, 0.0), black))
	front.add_child(ViewmodelParts.box("FrontBase", Vector3(0.022, 0.013, 0.019), Vector3(0.0, -0.017, 0.0), black))
	add_child(front)


func _build_stock() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]
	var polymer: Material = _mats["polymer"]

	add_child(ViewmodelParts.cylinder("BufferTube", 0.0150, 0.120, Vector3(0.0, 0.012, 0.040), steel))
	add_child(ViewmodelParts.cylinder("CastleNut", 0.0205, 0.014, Vector3(0.0, 0.012, -0.014), black))
	# Rastkerben nur auf dem freiliegenden Stueck zwischen Gehaeuse und Schaft.
	# Weiter hinten steckt das Rohr im Schaft und die Ringe waeren nur
	# Dreiecke, die niemand sieht — oder schlimmer, sie stechen durch.
	for i in range(2):
		add_child(ViewmodelParts.cylinder("TubeRing%d" % i, 0.0168, 0.005,
			Vector3(0.0, 0.012, 0.002 + float(i) * 0.012), black))

	# Der Schaft muss das Pufferrohr wirklich umschliessen. Vorher war er
	# niedriger als das Rohr dick ist — die Rastringe stachen hindurch und
	# von aussen sah man ein nacktes Rohr statt eines Schafts.
	add_child(ViewmodelParts.box("StockBody", Vector3(0.038, 0.054, 0.086), Vector3(0.0, 0.012, 0.062), polymer))
	add_child(ViewmodelParts.box("StockCheek", Vector3(0.028, 0.014, 0.078), Vector3(0.0, 0.043, 0.060), polymer))
	# Buendig mit dem Schaft. Vorher stand die Kappe ringsum ueber und bildete
	# einen Rand — der Schaft sah dadurch aus wie eine offene Wanne, in der
	# das Pufferrohr liegt.
	add_child(ViewmodelParts.box("ButtPad", Vector3(0.038, 0.054, 0.012), Vector3(0.0, 0.012, 0.108), black))
	add_child(ViewmodelParts.box("StockLever", Vector3(0.018, 0.012, 0.024), Vector3(0.0, -0.018, 0.056), polymer))


func _build_moving_parts() -> void:
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]
	var mag_mat: Material = _mats["magazine"]

	# Magazin aus vier Segmenten mit sanfter Kruemmung. Ein gerader Kasten
	# sieht sofort nach Platzhalter aus; zu viel Kruemmung nach Banane.
	# Magazin als durchgezogener, leicht gekruemmter Koerper.
	# Frueher vier gestapelte Quader — das sah man erst, als die Kanten
	# gebrochen wurden und jede Segmentgrenze zu einer Stufe wurde.
	var mag := ViewmodelParts.pivot("Magazine", Vector3(0.0, -0.052, -0.130))
	mag.add_child(ViewmodelParts.curved_body("MagBody", 0.025, 0.046, 0.132, 9.0,
		Vector3.ZERO, mag_mat))
	mag.add_child(ViewmodelParts.box("MagFloor", Vector3(0.029, 0.010, 0.050),
		Vector3(0.0, -0.133, -0.011), black, Vector3(-9.0, 0.0, 0.0)))
	add_child(mag)

	# Verschluss im Auswurffenster.
	var bolt := ViewmodelParts.pivot("Action", Vector3(0.019, 0.026, -0.098))
	bolt.add_child(ViewmodelParts.box("BoltFace", Vector3(0.006, 0.026, 0.058), Vector3.ZERO, steel))
	add_child(bolt)

	# Ladehebel mit Sperrklinke links.
	var handle := ViewmodelParts.pivot("ChargingHandle", Vector3(0.0, 0.040, -0.028))
	handle.add_child(ViewmodelParts.box("HandleBar", Vector3(0.046, 0.010, 0.036), Vector3.ZERO, steel))
	handle.add_child(ViewmodelParts.box("HandleLatch", Vector3(0.022, 0.013, 0.014), Vector3(-0.030, 0.0, 0.006), steel))
	add_child(handle)

	var trigger_pivot := ViewmodelParts.pivot("Trigger", Vector3(0.0, -0.048, -0.072))
	trigger_pivot.add_child(ViewmodelParts.box("TriggerBlade", Vector3(0.006, 0.024, 0.008), Vector3(0.0, -0.012, 0.0),
		steel, Vector3(10.0, 0.0, 0.0)))
	add_child(trigger_pivot)

	var selector_pivot := ViewmodelParts.pivot("Selector", Vector3(-0.017, -0.026, -0.052))
	selector_pivot.add_child(ViewmodelParts.cylinder("SelectorPin", 0.0065, 0.014, Vector3(-0.006, 0.0, 0.0), black,
		Vector3(0.0, 0.0, 90.0)))
	selector_pivot.add_child(ViewmodelParts.box("SelectorLever", Vector3(0.018, 0.008, 0.024), Vector3(-0.012, 0.0, 0.009), black))
	add_child(selector_pivot)
