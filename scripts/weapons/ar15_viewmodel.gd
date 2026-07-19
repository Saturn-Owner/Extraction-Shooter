## AR-15 — Sturmgewehr, Direktgassystem, abnehmbares Stangenmagazin.
##
## Das Modell kommt als .glb aus Blender, ein Teil pro Datei. Dieser Code baut
## keine Geometrie mehr, sondern haengt die Teile an ihre Stelle und kuemmert
## sich um das, was Blender nicht mitliefert: Bewegung.
##
## WARUM DIE BEWEGLICHEN TEILE EINZELNE DATEIEN SIND: Verschluss, Ladehebel,
## Abzug und Feuerwahlhebel muessen sich unabhaengig voneinander bewegen.
## Waeren sie mit dem Gehaeuse verschmolzen, koennte nur die ganze Waffe am
## Stueck ruckeln — das Modell saehe dann besser aus, als es sich anfuehlt.
##
## KOORDINATEN: -Z ist vorne, +Y oben, +X rechts. Die Umrechnung aus den
## Blender-Achsen macht GlbParts, siehe dort.
class_name AR15Viewmodel
extends WeaponViewmodel

## Hoehe der Laufachse, am Modell gemessen.
const BORE_Y := 0.012

## Alles, was weiter vorn liegt als hier, ist der Schalldaempfer.
##
## Die Basisdatei enthaelt ihn noch mit eingebaut. Er muss raus: Er ist ein
## Anbauteil, und fest eingebaut waere die Waffe immer gedaempft, waehrend der
## Muendungs-Steckplatz nichts mehr zu tun haette.
##
## Erkannt wird ueber die LAGE, nicht ueber den Namen. Godot vergibt fuer
## unbenannte Meshes "Mesh", "Mesh2", … — das haengt an der Reihenfolge im
## Export und aendert sich beim naechsten Mal. Die Lage aendert sich nicht.
const STRIP_FORWARD_OF_X := 0.30

## Wo der eingebaute Ladehebel in der Basisdatei sitzt (Modellachsen).
##
## Auch er muss raus: Er liegt jetzt als eigene Datei bei, damit er sich
## bewegen kann. Die eingebaute Kopie wuerde daneben stehenbleiben und beim
## Nachladen zwei Ladehebel zeigen.
const BUILT_IN_HANDLE := Vector3(-0.2265, 0.0824, -0.0036)

## Die beweglichen Teile und ihre Dateien.
##
## Die Knotennamen sind Pflicht: WeaponViewmodel._collect_parts() sucht genau
## danach. Ein Tippfehler hiesse, dass das Teil zwar richtig sitzt, sich aber
## nie bewegt — und das faellt beim Spielen kaum auf.
const MOVING_PARTS := [
	{node = "Action", file = "AR15_Verschluss-Action"},
	{node = "ChargingHandle", file = "AR15_Ladehebel"},
	{node = "Trigger", file = "AR15_Abzug"},
	{node = "Selector", file = "AR15_Feuerwahlhebel"},
	{node = "Magazine", file = "AR15_Magazin"},
]


func get_model_name() -> String:
	return "ar15"


func _configure() -> void:
	# Beide Werte am Modell gemessen, nicht geschaetzt.
	#
	# Die Waffe hat bewusst KEINE Notvisierung — ohne Optik zielt man ueber die
	# nackte Schiene. Deshalb ist die Zielhoehe hier die Schienenoberkante.
	sight_height = 0.045
	muzzle_z = -0.621
	# Leichte, gut ausbalancierte Waffe: liegt ruhig und kickt wenig.
	recoil_scale = 0.9
	action_travel = 0.075
	action_cycle_time = 0.055


func _build_parts() -> void:
	_build_body()
	_build_moving_parts()
	_build_points()
	_build_mounts()


## Die Waffe ohne alles, was sich bewegt oder angebaut wird.
func _build_body() -> void:
	var body := GlbParts.load_part("AR15_Waffe-ohne-Anbauteile", "Body")
	if body == null:
		return

	# DER KOERPER MUSS DIESELBE VERSCHIEBUNG BEKOMMEN WIE DIE TEILE.
	#
	# Teile werden ueber GlbParts.to_view() gesetzt, und das rechnet die
	# Ursprungsverschiebung mit ein. Der Koerper wird dagegen einfach
	# eingehaengt und traegt nur die Drehung. Ohne diese Zeile liegen Koerper
	# und Teile 27 cm auseinander — das Magazin schwebte vor dem Handschutz.
	body.position = GlbParts.to_view(Vector3.ZERO)

	add_child(body)
	_strip_misplaced_parts(body)


func _strip_misplaced_parts(node: Node) -> void:
	var doomed: Array[Node] = []
	_collect_misplaced(node, Transform3D.IDENTITY, doomed)
	for mesh in doomed:
		mesh.get_parent().remove_child(mesh)
		mesh.queue_free()


## Sucht in MODELLACHSEN und beginnt deshalb unterhalb des gedrehten Halters:
## Die Grenzen oben sind in denselben Achsen gemessen wie die Datei.
func _collect_misplaced(node: Node, transform: Transform3D, into: Array[Node]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var centre: Vector3 = (transform * mesh_instance.mesh.get_aabb()).get_center()
			if centre.x > STRIP_FORWARD_OF_X:
				into.append(node)
			elif centre.distance_to(BUILT_IN_HANDLE) < 0.02:
				into.append(node)

	for child in node.get_children():
		if child is Node3D:
			_collect_misplaced(child, transform * (child as Node3D).transform, into)


func _build_moving_parts() -> void:
	for entry in MOVING_PARTS:
		var pivot := GlbParts.pivot(entry.node, GlbParts.mount_point(entry.file))
		var model := GlbParts.load_part(entry.file, "Modell")
		if model != null:
			pivot.add_child(model)
		add_child(pivot)


func _build_points() -> void:
	add_child(GlbParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	# Auswurffenster: rechts neben dem Verschluss.
	add_child(GlbParts.pivot("EjectPoint", Vector3(0.030, 0.026, -0.098)))


## Die vier Steckplaetze.
##
## Die Aufnahmen liegen im Ursprung, nicht an der Einbaustelle: Jedes Teil
## bringt seine eigene Stelle aus seiner Datei mit. Zwei Visiere sitzen an
## verschiedenen Punkten derselben Schiene — mit einer festen Aufnahme saesse
## eines von beiden zwangslaeufig falsch.
func _build_mounts() -> void:
	for mount_name in ["MountSight", "MountMuzzle", "MountGrip", "MountForegrip"]:
		add_child(GlbParts.pivot(mount_name, Vector3.ZERO))
