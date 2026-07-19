## Baut ein Modell der AR-15 aus Godot-Primitiven.
##
## WARUM IM CODE UND NICHT ALS .tscn?
## Szenen lassen sich bei Konflikten praktisch nicht mergen (siehe CLAUDE.md).
## Ein Modell aus ueber 100 Teilen, an dem beide schrauben, waere eine
## dauerhafte Konfliktquelle. Als Code ist es mergebar und parametrisch.
##
## Das bleibt ein PLATZHALTER, aber ein sorgfaeltiger: Die Silhouette stimmt,
## und das ist in einem Shooter das, was man 90 % der Zeit sieht. Sobald ein
## echtes Modell vorliegt, faellt diese Datei weg — weapon_view.gd bleibt
## unveraendert, weil es die Teile ausschliesslich ueber ihre Namen findet.
##
## WAS DEN UNTERSCHIED MACHT: nicht mehr Kanten, sondern Wiederholung und
## Materialwechsel. Die Picatinny-Schiene, der achteckige Handschutz und das
## gekruemmte Magazin lesen sich aus der Entfernung als "Detail", obwohl es
## nur Quader sind. Deshalb stecken die Schleifen genau dort.
##
## KOORDINATEN: -Z ist vorne (Blickrichtung), +Y oben, +X rechts.
## Der Ursprung liegt hinten am Gehaeuse, dort wo der Puffer ansetzt.
## Alle Masse in Metern und an einer echten AR-15 mit 14,5-Zoll-Lauf orientiert.
class_name ViewmodelBuilder
extends RefCounted

## Hoehe der Visierlinie ueber dem Modellursprung.
##
## weapon_view.gd braucht diesen Wert, um die Zielpose auszurechnen: Beim
## Zielen muss die Visierlinie exakt auf die Kameramitte wandern, sonst
## schiesst der Spieler an seinem eigenen Korn vorbei.
const SIGHT_HEIGHT := 0.068

## Wo die Muendung sitzt — Ansatzpunkt fuer Muendungsfeuer.
const MUZZLE_Z := -0.575

## Hoehe der Laufachse. Alles Runde sitzt auf dieser Linie.
const BORE_Y := 0.014

## Oberkante der Schiene. Kimme und Korn bauen darauf auf.
const RAIL_Y := 0.050


## Baut das komplette Modell und gibt den Wurzelknoten zurueck.
static func build_ar15() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"

	# MATERIALIEN — hier steckte der groesste Fehler der ersten Fassung:
	# Hohe metallic-Werte ohne Reflexionsumgebung rendern fast schwarz, waehrend
	# Kunststoff mit metallic 0 hell bleibt. Das Ergebnis war genau verkehrt —
	# Griff und Magazin leuchteten beige, das Gehaeuse verschwand im Schwarz.
	# Deshalb durchgehend niedrige metallic-Werte; der Unterschied zwischen
	# Metall und Kunststoff kommt ueber die Rauheit, nicht ueber metallic.
	# Zweiter Punkt nach dem metallic-Fehler: Wenn alle Teile denselben Hellwert
	# haben, verschmilzt die Waffe zu einem grauen Block, egal wie viele Teile
	# es sind. Deshalb bewusste Trennung — Gehaeuse und Lauf hell, Kunststoff
	# deutlich dunkler, Kleinteile fast schwarz. Echte Gewehre sind zwar
	# durchgehend schwarz, aber im Spiel muss man die Form lesen koennen.
	var mats := {
		"steel": _material(Color(0.215, 0.215, 0.232), 0.35, 0.36),
		"black": _material(Color(0.072, 0.072, 0.080), 0.25, 0.45),
		"polymer": _material(Color(0.086, 0.086, 0.092), 0.0, 0.85),
		"handguard": _material(Color(0.105, 0.105, 0.113), 0.08, 0.64),
		"magazine": _material(Color(0.094, 0.099, 0.094), 0.05, 0.72),
	}

	_build_upper_receiver(root, mats)
	_build_lower_receiver(root, mats)
	_build_handguard(root, mats)
	_build_barrel(root, mats)
	_build_sights(root, mats)
	_build_stock(root, mats)
	_build_moving_parts(root, mats)

	root.add_child(_marker("MuzzlePoint", Vector3(0.0, BORE_Y, MUZZLE_Z)))
	root.add_child(_marker("EjectPoint", Vector3(0.030, 0.026, -0.098)))

	return root


## Oberes Gehaeuse mit Picatinny-Schiene, Auswurffenster und Huelsenabweiser.
static func _build_upper_receiver(root: Node3D, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var black: Material = mats["black"]

	root.add_child(_box("UpperReceiver", Vector3(0.038, 0.050, 0.200), Vector3(0.0, 0.020, -0.125), steel))
	# Schmalerer Streifen obendrauf. Faked eine Fase — die Kante bricht das
	# Licht anders und der Quader wirkt weniger wie ein Quader.
	root.add_child(_box("UpperTop", Vector3(0.030, 0.008, 0.200), Vector3(0.0, 0.045, -0.125), steel))
	root.add_child(_box("RailBase", Vector3(0.022, 0.006, 0.198), Vector3(0.0, RAIL_Y - 0.003, -0.126), black))

	# Die Schiene selbst: 17 Querstege. Das ist der Trick, der aus einem
	# Kasten ein Gewehr macht.
	_add_rail_teeth(root, "UpperRail", -0.030, -0.222, RAIL_Y + 0.003, black)

	# Auswurffenster mit Staubschutzklappe (rechts).
	root.add_child(_box("EjectionPort", Vector3(0.005, 0.028, 0.058), Vector3(0.0205, 0.026, -0.100), black))
	root.add_child(_box("PortHinge", Vector3(0.004, 0.007, 0.062), Vector3(0.0205, 0.010, -0.100), steel))
	# Huelsenabweiser — der kleine Keil hinter dem Fenster.
	root.add_child(_box("BrassDeflector", Vector3(0.010, 0.020, 0.022), Vector3(0.021, 0.032, -0.068),
		steel, Vector3(0.0, 0.0, -28.0)))
	# Nachschiebehilfe.
	root.add_child(_cylinder("ForwardAssist", 0.0075, 0.026, Vector3(0.021, 0.012, -0.058), steel))
	root.add_child(_cylinder("ForwardAssistCap", 0.0095, 0.008, Vector3(0.021, 0.012, -0.046), black))


## Unteres Gehaeuse mit Magazinschacht, Griff und Abzugsbuegel.
static func _build_lower_receiver(root: Node3D, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var black: Material = mats["black"]
	var polymer: Material = mats["polymer"]

	root.add_child(_box("LowerReceiver", Vector3(0.032, 0.046, 0.140), Vector3(0.0, -0.029, -0.098), steel))
	# Magazinschacht, unten leicht ausgestellt.
	root.add_child(_box("Magwell", Vector3(0.036, 0.034, 0.054), Vector3(0.0, -0.050, -0.130), steel))
	root.add_child(_box("MagwellFlare", Vector3(0.040, 0.008, 0.058), Vector3(0.0, -0.068, -0.131), steel))

	# Bedienelemente. Winzig, aber genau die Dinger sucht das Auge.
	root.add_child(_cylinder("MagRelease", 0.0055, 0.012, Vector3(0.019, -0.024, -0.146), black,
		Vector3(0.0, 0.0, 90.0)))
	root.add_child(_box("BoltCatch", Vector3(0.006, 0.013, 0.030), Vector3(-0.018, -0.024, -0.140), black))
	root.add_child(_box("TakedownPin", Vector3(0.006, 0.010, 0.010), Vector3(-0.018, -0.012, -0.038), steel))

	# Abzugsbuegel als geschlossene Schlaufe aus drei Teilen.
	root.add_child(_box("GuardFront", Vector3(0.009, 0.030, 0.006), Vector3(0.0, -0.068, -0.098), steel))
	root.add_child(_box("GuardBottom", Vector3(0.009, 0.006, 0.052), Vector3(0.0, -0.081, -0.074), steel))
	root.add_child(_box("GuardRear", Vector3(0.009, 0.016, 0.006), Vector3(0.0, -0.074, -0.050), steel,
		Vector3(24.0, 0.0, 0.0)))

	# Pistolengriff. Kuerzer und dicker als in der ersten Fassung — der wirkte
	# wie ein duenner Stab und zog das ganze Profil in die Laenge.
	root.add_child(_box("PistolGrip", Vector3(0.032, 0.074, 0.042), Vector3(0.0, -0.082, -0.030),
		polymer, Vector3(-17.0, 0.0, 0.0)))
	root.add_child(_box("GripFlare", Vector3(0.035, 0.010, 0.046), Vector3(0.0, -0.116, -0.020),
		polymer, Vector3(-17.0, 0.0, 0.0)))
	root.add_child(_box("GripTang", Vector3(0.028, 0.016, 0.024), Vector3(0.0, -0.052, -0.036), polymer))


## Achteckiger Handschutz mit durchlaufender Schiene.
##
## Acht Platten im Kreis statt eines Kastens: Das ergibt Kanten in mehreren
## Winkeln, und genau daran erkennt das Auge eine Roehre statt eines Balkens.
static func _build_handguard(root: Node3D, mats: Dictionary) -> void:
	var handguard: Material = mats["handguard"]
	var black: Material = mats["black"]

	# Langer Handschutz bis kurz vor die Muendung. In der ersten Fassung ragte
	# ein duenner Lauf weit heraus — das laesst jedes Gewehr billig wirken.
	var length := 0.225
	var center_z := -0.345
	var radius := 0.025

	var panels := Node3D.new()
	panels.name = "Handguard"
	for i in range(8):
		var angle := deg_to_rad(float(i) * 45.0)
		var panel := _box(
			"Panel%d" % i,
			Vector3(0.021, 0.007, length),
			Vector3(sin(angle) * radius, BORE_Y + cos(angle) * radius, center_z),
			handguard,
			Vector3(0.0, 0.0, -rad_to_deg(angle))
		)
		panels.add_child(panel)
	root.add_child(panels)

	# Endkappen, damit der Handschutz nicht offen ausfranst.
	root.add_child(_cylinder("HandguardCollar", 0.028, 0.014, Vector3(0.0, BORE_Y, -0.232), black))
	root.add_child(_cylinder("HandguardCap", 0.027, 0.010, Vector3(0.0, BORE_Y, -0.456), black))

	# Die Schiene laeuft ueber den Handschutz weiter — eine durchgehende
	# Oberkante ist das, was moderne Gewehre ausmacht.
	root.add_child(_box("HandguardRailBase", Vector3(0.022, 0.006, 0.220), Vector3(0.0, RAIL_Y - 0.003, center_z), black))
	_add_rail_teeth(root, "HandguardRail", -0.232, -0.452, RAIL_Y + 0.003, black)


static func _build_barrel(root: Node3D, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var black: Material = mats["black"]

	root.add_child(_cylinder("Barrel", 0.0095, 0.310, Vector3(0.0, BORE_Y, -0.395), steel))
	# Flacher Gasblock, sitzt unter dem Handschutz — deshalb bewusst so
	# niedrig, dass er nicht durch die Verkleidung sticht.
	root.add_child(_box("GasBlock", Vector3(0.022, 0.018, 0.026), Vector3(0.0, BORE_Y + 0.008, -0.400), black))
	root.add_child(_cylinder("GasTube", 0.0032, 0.165, Vector3(0.0, BORE_Y + 0.016, -0.325), steel))

	# Muendungsbremse als abgesetzter Zylinder mit zwei Ringen.
	# Erste Fassung hatte vier abstehende Zinken — die sahen aus wie Antennen.
	# Absaetze lesen sich als Muendungsbremse, ohne aus der Silhouette zu ragen.
	root.add_child(_cylinder_taper("FlashHider", 0.0115, 0.0130, 0.050, Vector3(0.0, BORE_Y, -0.546), black))
	root.add_child(_cylinder("HiderRingFront", 0.0140, 0.008, Vector3(0.0, BORE_Y, -0.566), black))
	root.add_child(_cylinder("HiderRingRear", 0.0135, 0.007, Vector3(0.0, BORE_Y, -0.524), black))
	root.add_child(_cylinder("BarrelNut", 0.0165, 0.018, Vector3(0.0, BORE_Y, -0.240), steel))


## Kimme und Korn.
##
## Beide sitzen mit ihrem Ursprung exakt auf SIGHT_HEIGHT. Nur dann ist die
## Visierlinie eine Gerade, und nur dann trifft die Waffe beim Zielen dorthin,
## wo die Kameramitte hinzeigt. verify_weapon_handling.gd prueft genau das —
## wer hier etwas verschiebt, bekommt einen roten Test statt eines stillen
## Zielfehlers.
static func _build_sights(root: Node3D, mats: Dictionary) -> void:
	var black: Material = mats["black"]

	# --- Kimme: Lochblende in einem Gehaeuse ---
	var rear := Node3D.new()
	rear.name = "RearSight"
	rear.position = Vector3(0.0, SIGHT_HEIGHT, -0.048)
	rear.add_child(_torus("Aperture", 0.005, 0.010, Vector3.ZERO, black, Vector3(90.0, 0.0, 0.0)))
	rear.add_child(_box("RearBase", Vector3(0.026, 0.016, 0.020), Vector3(0.0, -0.014, 0.0), black))
	rear.add_child(_box("RearWingL", Vector3(0.005, 0.020, 0.014), Vector3(-0.013, -0.002, 0.0), black))
	rear.add_child(_box("RearWingR", Vector3(0.005, 0.020, 0.014), Vector3(0.013, -0.002, 0.0), black))
	root.add_child(rear)

	# --- Korn: Pfosten zwischen zwei Schutzbacken ---
	var front := Node3D.new()
	front.name = "FrontSight"
	# Sitzt vorn auf der Schiene, nicht mehr auf dem Gasblock — der ist jetzt
	# flach und steckt unter dem Handschutz.
	front.position = Vector3(0.0, SIGHT_HEIGHT, -0.444)
	# Backen bewusst senkrecht und dicht am Pfosten. Angeschraegt sahen sie
	# aus wie eine abgebrochene Antenne statt wie eine Kornschutzbacke.
	front.add_child(_box("FrontPost", Vector3(0.004, 0.022, 0.004), Vector3(0.0, -0.003, 0.0), black))
	front.add_child(_box("FrontWingL", Vector3(0.0045, 0.026, 0.013), Vector3(-0.0085, -0.002, 0.0), black))
	front.add_child(_box("FrontWingR", Vector3(0.0045, 0.026, 0.013), Vector3(0.0085, -0.002, 0.0), black))
	front.add_child(_box("FrontBase", Vector3(0.022, 0.013, 0.019), Vector3(0.0, -0.017, 0.0), black))
	root.add_child(front)


static func _build_stock(root: Node3D, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var black: Material = mats["black"]
	var polymer: Material = mats["polymer"]

	root.add_child(_cylinder("BufferTube", 0.0150, 0.120, Vector3(0.0, 0.012, 0.040), steel))
	root.add_child(_cylinder("CastleNut", 0.0205, 0.014, Vector3(0.0, 0.012, -0.014), black))
	# Rastkerben am Puffer — die Ringe geben dem Rohr Massstab.
	for i in range(3):
		root.add_child(_cylinder("TubeRing%d" % i, 0.0170, 0.005,
			Vector3(0.0, 0.012, 0.014 + float(i) * 0.024), black))

	# SCHAFT — in der ersten Fassung ein Klotz, der ein Drittel der Waffe
	# einnahm und hinten von einer noch groesseren Platte abgeschlossen wurde.
	# Jetzt schmaler als das Rohr hoch ist, nach hinten leicht auslaufend.
	root.add_child(_box("StockBody", Vector3(0.036, 0.046, 0.088), Vector3(0.0, 0.010, 0.058), polymer))
	root.add_child(_box("StockCheek", Vector3(0.026, 0.012, 0.080), Vector3(0.0, 0.034, 0.056), polymer))
	root.add_child(_box("ButtPad", Vector3(0.038, 0.054, 0.013), Vector3(0.0, 0.008, 0.106), black))
	root.add_child(_box("StockLever", Vector3(0.018, 0.012, 0.026), Vector3(0.0, -0.019, 0.052), polymer))


## Alles, was sich bewegt, bekommt einen eigenen Drehpunkt.
## Der Pivot sitzt dort, wo sich das Teil im echten Leben dreht bzw. schiebt.
static func _build_moving_parts(root: Node3D, mats: Dictionary) -> void:
	var steel: Material = mats["steel"]
	var black: Material = mats["black"]
	var magazine: Material = mats["magazine"]

	# --- Magazin: gekruemmt aus fuenf Segmenten ---
	# Ein gerader Kasten sieht sofort nach Platzhalter aus. Die Kruemmung
	# kostet vier Zeilen und ist das, was man als Erstes wiedererkennt.
	# --- Magazin: leicht gekruemmt aus vier Segmenten ---
	# Erste Fassung kruemmte sich um 14 Grad und sah aus wie eine Banane, die
	# nach vorn zeigt. Ein STANAG-Magazin steht fast senkrecht und faellt zum
	# Boden hin nur sanft nach vorn ab — deshalb jetzt 1,5 Grad pro Segment.
	var mag := Node3D.new()
	mag.name = "Magazine"
	mag.position = Vector3(0.0, -0.058, -0.132)
	for i in range(4):
		var t := float(i)
		mag.add_child(_box(
			"MagSegment%d" % i,
			Vector3(0.025, 0.036, 0.046),
			Vector3(0.0, -0.015 - t * 0.032, -0.001 - t * 0.0022),
			magazine,
			Vector3(-t * 1.5, 0.0, 0.0)
		))
	mag.add_child(_box("MagFloor", Vector3(0.029, 0.011, 0.050), Vector3(0.0, -0.128, -0.008),
		black, Vector3(-6.0, 0.0, 0.0)))
	root.add_child(mag)

	# --- Verschluss im Auswurffenster ---
	var bolt := Node3D.new()
	bolt.name = "Bolt"
	bolt.position = Vector3(0.019, 0.026, -0.098)
	bolt.add_child(_box("BoltFace", Vector3(0.006, 0.026, 0.058), Vector3.ZERO, steel))
	root.add_child(bolt)

	# --- Ladehebel mit Sperrklinke links ---
	var handle := Node3D.new()
	handle.name = "ChargingHandle"
	handle.position = Vector3(0.0, 0.040, -0.028)
	handle.add_child(_box("HandleBar", Vector3(0.046, 0.010, 0.036), Vector3.ZERO, steel))
	handle.add_child(_box("HandleLatch", Vector3(0.022, 0.013, 0.014), Vector3(-0.030, 0.0, 0.006), steel))
	root.add_child(handle)

	# --- Abzug ---
	var trigger := Node3D.new()
	trigger.name = "Trigger"
	trigger.position = Vector3(0.0, -0.048, -0.072)
	trigger.add_child(_box("TriggerBlade", Vector3(0.006, 0.024, 0.008), Vector3(0.0, -0.012, 0.0),
		steel, Vector3(10.0, 0.0, 0.0)))
	root.add_child(trigger)

	# --- Feuerwahlhebel links ---
	var selector := Node3D.new()
	selector.name = "Selector"
	selector.position = Vector3(-0.017, -0.026, -0.052)
	selector.add_child(_cylinder("SelectorPin", 0.0065, 0.014, Vector3(-0.006, 0.0, 0.0), black,
		Vector3(0.0, 0.0, 90.0)))
	selector.add_child(_box("SelectorLever", Vector3(0.018, 0.008, 0.024), Vector3(-0.012, 0.0, 0.009), black))
	root.add_child(selector)


## Querstege einer Picatinny-Schiene zwischen zwei Z-Positionen.
static func _add_rail_teeth(root: Node3D, prefix: String, from_z: float, to_z: float,
		y: float, mat: Material) -> void:
	var spacing := 0.0115
	var span := absf(to_z - from_z)
	var count := int(span / spacing)
	for i in range(count):
		root.add_child(_box(
			"%sTooth%d" % [prefix, i],
			Vector3(0.021, 0.007, 0.0062),
			Vector3(0.0, y, from_z - float(i) * spacing - 0.004),
			mat
		))


static func _box(name: String, size: Vector3, pos: Vector3, mat: Material,
		rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(name, mesh, pos, mat, rotation_deg)


## Zylinder. Godot legt sie entlang Y an — fuer Laeufe drehen wir sie um
## 90 Grad, damit sie entlang Z zeigen.
static func _cylinder(name: String, radius: float, length: float, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
	return _cylinder_taper(name, radius, radius, length, pos, mat, rotation_deg)


## Konischer Zylinder — fuer Muendungsbremsen und alles, was sich verjuengt.
static func _cylinder_taper(name: String, top_radius: float, bottom_radius: float, length: float,
		pos: Vector3, mat: Material, rotation_deg: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = length
	mesh.radial_segments = 14
	mesh.rings = 1
	return _instance(name, mesh, pos, mat, rotation_deg)


## Ring — fuer die Lochblende der Kimme.
static func _torus(name: String, inner: float, outer: float, pos: Vector3,
		mat: Material, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 8
	return _instance(name, mesh, pos, mat, rotation_deg)


static func _instance(name: String, mesh: Mesh, pos: Vector3, mat: Material,
		rotation_deg: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation_degrees = rotation_deg
	return node


static func _marker(name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = pos
	return node


static func _material(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
