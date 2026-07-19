## Misst die tatsaechliche Lage aller Teile einer Waffe und gibt sie aus.
##
##   godot --headless --path . --script res://tools/inspect_viewmodel.gd -- m870
##
## Ohne Argument werden alle Waffen mit eigenem Modell ausgegeben.
##
## WOFUER: Ein gerendertes Bild sagt "da stimmt was nicht", aber nicht was.
## Schatten, Materialwechsel und ungluecklicher Blickwinkel taeuschen Luecken
## und Loecher vor, die es nicht gibt — und umgekehrt. Beim M870-Schaft hat
## genau das zu zwei Umbauten an einem Fehler gefuehrt, den es nie gab: Die
## Messung zeigte, dass alle Teile sauber ineinandergreifen.
##
## Faustregel: Wenn zwei Teile aneinanderstossen sollen, muessen sich ihre
## Bereiche ueberlappen. Auf Stoss gesetzt klafft bei der kleinsten Aenderung
## eine Fuge.
extends SceneTree


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	var args := OS.get_cmdline_user_args()
	var wanted: String = args[0] if args.size() > 0 else ""

	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var data := item as WeaponData
		if data == null or not data.has_own_viewmodel():
			continue

		var model := data.create_viewmodel()
		model.build()

		if wanted != "" and not model.get_model_name().contains(wanted):
			model.free()
			continue

		print("\n=== %s (%s) ===" % [data.display_name, model.get_model_name()])
		print("Visierhoehe %.4f   Muendung z %.4f" % [model.sight_height, model.muzzle_z])
		print("%-24s %9s %9s %9s %9s %8s" % ["Teil", "z vorn", "z hinten", "y unten", "y oben", "breite"])
		_dump(model, Transform3D.IDENTITY)
		model.free()

	quit(0)


func _dump(node: Node, transform: Transform3D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var box := transform * mesh_instance.mesh.get_aabb()
			print("%-24s %9.4f %9.4f %9.4f %9.4f %8.4f" % [
				node.name, box.position.z, box.end.z,
				box.position.y, box.end.y, box.size.x])

	for child in node.get_children():
		if child is Node3D:
			_dump(child, transform * (child as Node3D).transform)
