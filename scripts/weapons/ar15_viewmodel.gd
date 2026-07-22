## AR-15 — Sturmgewehr, Direktgassystem, abnehmbares Stangenmagazin.
##
## ---------------------------------------------------------------------------
## DIESES MODELL IST EIN EINZELNES .glb, WIE BEI DER AKM
##
## Quelle: "AR-15" von wafla (Sketchfab, CC BY 4.0 — siehe QUELLEN.md),
## aufbereitet durch tools/convert_ar15_sketchfab.gd (Texturen verkleinert,
## Sketchfab-Hüllknoten entfernt, alles vermessen).
##
## Das Modell bringt ALLES in einer Datei mit: Gehäuse, bewegliche Teile UND
## Anbauteile (EOtech, GEMTECH-Dämpfer, Frontgriff, Lampe). Beim Laden passiert
## deshalb dreierlei:
##
##   1. ANBAUTEILE RAUS aus dem Grundkörper (_STRIP_NODES): Sie gehören dem
##      Anbausystem. Blieben sie fest dran, wäre die Waffe immer voll bestückt
##      und die Steckplätze hätten nichts mehr zu tun. Die Anbauteil-Skripte
##      (ar15_holo.gd, ar15_suppressor.gd, ...) holen sich dieselben Knoten
##      aus derselben Datei zurück, wenn ihr Item angebaut ist — eine Quelle,
##      kein doppeltes Modell.
##   2. BEWEGLICHE TEILE HERAUSLÖSEN (_MOVING_PARTS): Verschlussträger,
##      Ladehebel, Abzug, Feuerwahlhebel und Magazin stecken als benannte
##      Knoten im Baum, nur ohne beweglichen Elternknoten — sie werden wie bei
##      der AKM in Pivots umgehängt, die _collect_parts() beim Namen findet.
##   3. EINPASSEN: Das Modell kommt in Sketchfab-Einheiten (die Waffe ist
##      "8,18 lang"). fit_transform() skaliert und dreht es in den Kameraraum.
##
## ALLE ZAHLEN SIND GEMESSEN, nicht geraten — sie stammen aus dem Messprotokoll
## des Konverters. Wer das Modell austauscht, lässt den Konverter laufen und
## trägt die neuen Zahlen hier ein.
class_name AR15Viewmodel
extends WeaponViewmodel

const MODEL := "res://assets/models/weapons/ar15/ar15.glb"

# --- Messwerte im MODELLRAUM (Ausdruck von tools/convert_ar15_sketchfab.gd) ---

## Laufachse: Mitte von Verschluss (y 0.2423), Verschlussträger (0.2489) und
## Dämpfer-Aufnahme (0.2418) — der Lauf liegt bei y ≈ 0.242, seitlich mittig.
const BORE_Y_MODEL := 0.242

## Vorderkante der Mündungsbremse — das Ende der Waffe ohne Dämpfer.
const MUZZLE_TIP_MODEL := 4.1298

## Die Mündungsbremse liegt in der Quelldatei GEPARKT unter dem Lauf
## (AABB-Mitte y -0.1823 statt Laufachse 0.242) — vermutlich, weil der Autor
## sie als Alternative zum Dämpfer daneben abgelegt hat. In X sitzt sie
## bereits exakt am Laufende; nur die Höhe fehlt. Gemessene Differenz:
const BRAKE_LIFT := 0.242 - (-0.1823)

## Oberkante der durchgehenden Schiene (Upper receiver 0.5424, Handschutz
## 0.5417). Ohne Optik zielt man wie bei der AKM über die nackte Schiene.
const RAIL_TOP_MODEL := 0.5424

## Hülle des Grundkörpers NACH dem Entfernen der Anbauteile: von der
## Schaftkappe (x -3.2368) bis zur Mündungsbremse (x 4.1298), von der
## Magazinunterkante (y -1.7669) bis zur Schiene, Ladehebel-Flügel seitlich.
const BASE_LENGTH_MODEL := 7.3666

## Gewünschte Gesamtlänge im Kameraraum — M4-Klasse mit CQB-Schaft.
const FIT_LENGTH := 0.74

## Höhe der Laufachse im Kameraraum — derselbe Wert wie bei allen Waffen.
const BORE_Y := 0.012

## Wo die Mündungsspitze im Kameraraum sitzt. Als Konstante, weil auch die
## Anbauteil-Skripte dieselbe Einpassung rechnen müssen (fit_transform_for).
const MUZZLE_Z := -0.60

## Anbauteile, die im Grundkörper stecken, aber dem Anbausystem gehören.
## Die Namen stammen aus der Modelldatei; gesucht wird tolerant (siehe
## find_model_node), weil Importe Leerzeichen mal erhalten und mal ersetzen.
const _STRIP_NODES := [
	"GEMTECH ABYSS 5_56", "EOtech EXPS-2", "BCM VFG",
	"Surefire EDC1", "mount flashlight",
]

## Bewegliche Teile: Pivot-Name (den _collect_parts() sucht) -> Modellknoten.
## Der Verschlussträger nimmt Bolzen, Trägerschlüssel und Schlagbolzen mit —
## in echt fahren die als eine Gruppe zurück.
##
## `pivot_at` (Modellraum) setzt den Drehpunkt, wo der Knotenursprung der
## Datei nichts taugt: Das PMAG hat seinen Ursprung im Modell-Nullpunkt —
## eine Kippanimation würde sonst um die Waffenmitte statt ums Magazin drehen.
const _MOVING_PARTS := [
	{pivot = "Action", nodes = ["Bolt carrier", "Bolt", "Bolt carrier key", "Firing pin"]},
	# Der Griff des Ladehebels sitzt hinten (Modell x -0.9, y 0.45) — dort
	# fasst die Figur beim Durchladen an, nicht am Datei-Ursprung.
	{pivot = "ChargingHandle", nodes = ["Charging handle"],
		pivot_at = Vector3(-0.9, 0.45, 0.0)},
	{pivot = "Trigger", nodes = ["Trigger"]},
	{pivot = "Selector", nodes = ["SSL"]},
	{pivot = "Magazine", nodes = ["Magpul PMAG 30", "Bullets"],
		pivot_at = Vector3(0.74, -0.3, 0.0)},
]


func get_model_name() -> String:
	return "ar15"


func _configure() -> void:
	# Schienenoberkante im Kameraraum: fit_point() rechnet den Modellwert um.
	# Dieselbe Zahl senkt weapon_view die Waffe beim Zielen ab.
	sight_height = fit_point(Vector3(0.0, RAIL_TOP_MODEL, 0.0)).y
	muzzle_z = MUZZLE_Z
	# Leichte, gut ausbalancierte Waffe: liegt ruhig und kickt wenig.
	# Nach dem Spielen gezaehmt (wie die AKM davor): Der sichtbare Kick hier
	# und der echte Rueckstoss in rifle_ar15.tres wurden ZUSAMMEN gesenkt —
	# beide getrennt zu aendern laesst Bild und Wirkung auseinanderlaufen.
	recoil_scale = 0.6
	action_travel = 0.075
	action_cycle_time = 0.055
	# Wie bei der AKM: Beim Zielen rutscht der Schaft hinter die Nahgrenze der
	# Kamera, sonst füllt er das halbe Bild.
	ads_distance = -0.06
	# Bildausschnitt im Hüftanschlag. Nach dem Spielen nachgestellt: Die Waffe
	# sass zu dicht am Körper, deshalb ein Stück nach vorn (z 0.02 -> -0.06).
	hip_position = Vector3(0.105, -0.115, -0.06)

	# --- Durchladen bei leerer Nachladung -----------------------------------
	#
	# Die Kamera-Vorgabe (Drehung nach links, rack_turn_rotation in
	# weapon_view.gd) ist für seitliche Hebel wie am AK gebaut. Der Ladehebel
	# der AR-15 sitzt hinten OBEN — die Waffe wird deshalb ANGEWINKELT
	# (Mündung hoch, leicht gerollt und näher ans Auge), damit man den Zug
	# von oben sieht, statt sie wegzudrehen. Nach dem Spielen eingestellt.
	rack_turn_rotation_override = Vector3(-14.0, -3.0, 12.0)
	rack_turn_offset_override = Vector3(0.0, -0.012, 0.03)
	# Die Anwinkelung rahmt die GANZE Nachladung, nicht nur den Hebelzug:
	# erst hochwinkeln, DANN Magazin raus, neues rein, zum Schluss der Zug.
	# Deshalb 0.0 — die Feder in weapon_view zieht die Pose gleich zu Beginn
	# weich an, und die Waffe bleibt oben, bis alles durch ist.
	rack_turn_start_progress = 0.0
	# Der Zug selbst bekommt mehr Zeit: Das Fenster beginnt früher (0.82
	# statt 0.93 der Grundklasse), damit die Hand den Hebel sichtbar ZIEHT
	# statt ihn nur zucken zu lassen.
	handle_pull_start_progress = 0.82


func _build_parts() -> void:
	_build_body()
	_build_moving_parts()
	_build_points()
	_build_mounts()


## Der Grundkörper: das GLB ohne Anbauteile.
##
## Fällt die Datei aus (frischer Clone ohne LFS o. ä.), bleibt die Waffe
## unsichtbar statt abzustürzen — spielbar ist sie über _configure() weiter.
func _build_body() -> void:
	var scene := load(MODEL) as PackedScene
	if scene == null:
		push_warning("[AR15] Modell fehlt: %s" % MODEL)
		return

	var instance := scene.instantiate()

	for doomed_name in _STRIP_NODES:
		var doomed := find_model_node(instance, doomed_name)
		if doomed == null:
			push_warning("[AR15] Anbauteil '%s' nicht im Modell — schon entfernt?" % doomed_name)
			continue
		doomed.get_parent().remove_child(doomed)
		doomed.queue_free()

	# Die geparkte Mündungsbremse auf die Laufachse heben — siehe BRAKE_LIFT.
	var brake := find_model_node(instance, "Muzzle brake") as Node3D
	if brake != null:
		brake.position += Vector3(0.0, BRAKE_LIFT, 0.0)

	var body := Node3D.new()
	body.name = "Body"
	body.add_child(instance)
	body.transform = fit_transform()
	add_child(body)

	_model_instance = instance


func _build_moving_parts() -> void:
	if _model_instance == null:
		return
	for entry in _MOVING_PARTS:
		_extract_group(_model_instance, entry.nodes, entry.pivot, entry.get("pivot_at"))


func _build_points() -> void:
	var muzzle := fit_point(Vector3(MUZZLE_TIP_MODEL, BORE_Y_MODEL, 0.0))
	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, muzzle.y, muzzle.z)))

	# Auswurffenster: rechts am Gehäuse, gemessen an der Klappe
	# (Modell x 0.076..1.084 auf der +Z-Seite).
	add_child(ViewmodelParts.pivot("EjectPoint", fit_point(Vector3(0.58, 0.24, 0.28))))

	# Wo die Hände anfassen — Pistolengriff (Modell-Mitte -0.85, -0.84) und
	# Handschutz-Unterseite vor dem Magazin. Gemessen, deshalb dürfen die
	# Hände sichtbar sein.
	shows_hands = true
	add_child(ViewmodelParts.pivot("GripPoint", fit_point(Vector3(-0.85, -0.84, 0.0))))
	# Bewusst am HINTEREN Ende des Handschutzes (Modell x 1.15, Beginn 1.05):
	# Das neue Modell ist länger als das alte, und weiter vorn kommt der Arm
	# der Blockfigur nicht mehr hin (verify_character misst das nach).
	add_child(ViewmodelParts.pivot("SupportPoint", fit_point(Vector3(1.15, -0.08, 0.0))))

	# Magazinschacht: unteres Drittel des sitzenden Magazins
	# (PMAG reicht im Modell von y 0.17 bis -1.77).
	add_child(ViewmodelParts.pivot("MagwellPoint", fit_point(Vector3(0.74, -1.0, 0.0))))

	# Visierlinie ohne Optik: über die nackte Schiene, wie bei der AKM.
	# verify_weapon_handling prüft an diesen Punkten die freie Sicht.
	add_child(ViewmodelParts.pivot("FrontSight",
		fit_point(Vector3(3.7, RAIL_TOP_MODEL, 0.0))))
	add_child(ViewmodelParts.pivot("RearSight",
		fit_point(Vector3(-0.8, RAIL_TOP_MODEL, 0.0))))


## Die vier Steckplätze. Sie liegen im Ursprung — jedes Anbauteil bringt
## seine Stelle selbst mit (die Anbauteil-Skripte messen sie aus derselben
## Modelldatei bzw. setzen sie auf die Schiene).
func _build_mounts() -> void:
	for mount_name in ["MountSight", "MountMuzzle", "MountGrip", "MountForegrip"]:
		add_child(ViewmodelParts.pivot(mount_name, Vector3.ZERO))


# --- Einpassen und Herauslösen — geteilt mit den Anbauteil-Skripten ----------

var _model_instance: Node = null


## Skaliert und dreht den Modellraum in den Kameraraum.
##
## +X (Mündung im Modell) wird -Z (Mündung im Spiel), die Laufachse landet
## auf BORE-Höhe, die Mündungsspitze auf muzzle_z. Statisch nutzbar, weil
## auch die Anbauteil-Skripte denselben Weg rechnen müssen.
static func fit_transform_for(muzzle_z_view: float) -> Transform3D:
	var scale := FIT_LENGTH / BASE_LENGTH_MODEL
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(90.0), 0.0)) \
		* Basis().scaled(Vector3.ONE * scale)
	# Wohin die Mündungsspitze nach Drehung+Skalierung fällt — der Rest ist
	# die Verschiebung, die sie auf (0, BORE, muzzle_z) bringt.
	var tip := basis * Vector3(MUZZLE_TIP_MODEL, BORE_Y_MODEL, 0.0)
	var target := Vector3(0.0, BORE_Y, muzzle_z_view)
	return Transform3D(basis, target - tip)


func fit_transform() -> Transform3D:
	return fit_transform_for(muzzle_z)


## Rechnet einen im Konverter gemessenen Modellpunkt in den Kameraraum um.
func fit_point(model_point: Vector3) -> Vector3:
	return fit_transform() * model_point


## Sucht einen Modellknoten tolerant: Importe erhalten Leerzeichen mal und
## ersetzen sie mal — verglichen wird deshalb ohne Leerzeichen/Unterstriche
## und ohne Gross-Klein.
static func find_model_node(node: Node, target: String) -> Node:
	var wanted := _plain(target)
	if _plain(String(node.name)) == wanted:
		return node
	for child in node.get_children():
		var found := find_model_node(child, target)
		if found != null:
			return found
	return null


static func _plain(text: String) -> String:
	return text.to_lower().replace(" ", "").replace("_", "").replace("-", "")


## Löst eine Gruppe von Modellknoten heraus und hängt sie unter einen neuen
## Pivot mit dem gegebenen Namen — wie AKMViewmodel._extract_part(), nur für
## mehrere Knoten, die sich gemeinsam bewegen (Verschlussträger + Bolzen).
##
## POSITION AUF DEN PIVOT, DREHUNG AUF DIE MESHES: Die Animationen SETZEN die
## Pivot-Rotation und stellen sie danach hart auf null zurück — eine krumme
## Grunddrehung aus der FBX-Konvertierung muss deshalb auf den Kindern liegen,
## sonst steht das Teil nach der ersten Animation verdreht da (siehe die
## ausführliche Begründung in akm_viewmodel.gd).
func _extract_group(instance: Node, node_names: Array, pivot_name: String,
		pivot_at: Variant = null) -> void:
	var fit := fit_transform()
	var pivot: Node3D = null

	for node_name in node_names:
		var part := find_model_node(instance, node_name)
		if part == null:
			push_warning("[AR15] Teil '%s' nicht gefunden — '%s' bleibt unvollständig"
				% [node_name, pivot_name])
			continue

		var full := fit * _accumulate(instance, part)
		if pivot == null:
			# Der erste Knoten der Gruppe bestimmt den Drehpunkt — außer die
			# Teileliste gibt einen besseren vor (pivot_at, Modellraum).
			pivot = Node3D.new()
			pivot.name = pivot_name
			pivot.position = (fit * (pivot_at as Vector3)) if pivot_at != null else full.origin
			add_child(pivot)

		part.get_parent().remove_child(part)
		part.owner = null
		pivot.add_child(part)
		(part as Node3D).transform = Transform3D(full.basis, full.origin - pivot.position)

	if pivot == null:
		push_warning("[AR15] Kein Teil der Gruppe '%s' gefunden" % pivot_name)


## Magazin-Mitte im Modellraum (Messprotokoll: PMAG-AABB).
const MAG_CENTRE_MODEL := Vector3(0.7383, -0.7977, 0.0)


## Ein einzelnes PMAG als eigenständiges Modell: Modellachsen (+X vorn),
## Geometrie um den Ursprung, auf Meter skaliert.
##
## Für das sichtbare Ersatzmagazin in der Westentasche (player_controller,
## humanoid_target) — DASSELBE Modell wie in der Waffe, kein zweites. Fehlt
## die Datei, kommt ein leerer Knoten zurück und die Figur greift eben ins
## Leere, statt abzustürzen.
static func spare_magazine_model() -> Node3D:
	var holder := Node3D.new()
	holder.name = "PMAG"
	var scene := load(MODEL) as PackedScene
	if scene == null:
		push_warning("[AR15] Modell fehlt — kein Ersatzmagazin")
		return holder

	var instance := scene.instantiate()
	var part := find_model_node(instance, "Magpul PMAG 30")
	if part == null:
		push_warning("[AR15] PMAG nicht im Modell — kein Ersatzmagazin")
		instance.free()
		return holder

	var full := _accumulate(instance, part)
	part.get_parent().remove_child(part)
	part.owner = null
	holder.add_child(part)
	var scale := FIT_LENGTH / BASE_LENGTH_MODEL
	(part as Node3D).transform = Transform3D(Basis().scaled(Vector3.ONE * scale), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -MAG_CENTRE_MODEL) * full
	instance.free()
	return holder


static func _accumulate(root_node: Node, target: Node) -> Transform3D:
	var chain: Array[Node3D] = []
	var walker := target
	while walker != root_node and walker != null:
		if walker is Node3D:
			chain.append(walker)
		walker = walker.get_parent()
	var result := Transform3D.IDENTITY
	for i in range(chain.size() - 1, -1, -1):
		result = result * (chain[i] as Node3D).transform
	return result
