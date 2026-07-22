## Baut jede Waffe mit eigenem Modell einmal unsichtbar auf, bevor der
## Spieler sie je in die Hand nimmt — damit die Grafikkarte ihre Shader
## compiliert, WÄHREND das Level lädt, statt beim ersten Waffenwechsel.
##
## ---------------------------------------------------------------------------
## WARUM ES DEN RUCKLER GAB
##
## Godots Forward+-Renderer übersetzt für jede Mesh+Material-Kombination
## einen GPU-Shader beim ERSTEN Zeichnen, nicht beim Laden der Datei. Die
## Box-Waffen (Pistolen, SMGs, Flinte) teilen sich eine Handvoll Materialien
## aus `ViewmodelParts.materials()` — die sind längst kompiliert, sobald die
## erste Waffe im Spiel sichtbar war. AK und AR-15 sind dagegen echte
## Blender/Sketchfab-Modelle mit vielen eigenen, einmaligen Materialien
## (Verschluss, Griff, Handschutz, Magazin, ...) — die Grafikkarte sah sie
## bisher zum ersten Mal genau in dem Frame, in dem der Spieler die Waffe
## auswählte. Das war der Ruckler.
##
## ---------------------------------------------------------------------------
## VERTEILT AUF MEHRERE FRAMES
##
## Alle Waffen im selben Frame aufzubauen, verschöbe den Ruckler nur vom
## Waffenwechsel zum Levelstart, ohne ihn kleiner zu machen. Stattdessen
## kommt jede Waffe in ihren EIGENEN Frame — aus einem grossen Ruckler
## werden viele kleine, die beim Losrennen kaum auffallen.
##
## Läuft in einem eigenen, unsichtbaren SubViewport, damit nichts davon im
## echten Spiel aufblitzt.
class_name WeaponWarmup
extends Node

const VIEWPORT_SIZE := Vector2i(64, 64)

var _viewport: SubViewport
var _weapons: Array[WeaponData] = []
var _index := 0


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var data := item as WeaponData
		# GenericViewmodel (kein eigenes Modell) braucht kein Aufwärmen — es
		# besteht nur aus den längst bekannten Box-Materialien.
		if data != null and data.has_own_viewmodel():
			_weapons.append(data)

	if _weapons.is_empty():
		queue_free()
		return

	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 1.0)
	_viewport.add_child(camera)
	camera.make_current()

	var light := DirectionalLight3D.new()
	_viewport.add_child(light)

	_warm_next()


func _warm_next() -> void:
	if _index >= _weapons.size():
		queue_free()
		return

	var model := _weapons[_index].create_viewmodel()
	_viewport.add_child(model)
	# Zwei Frames abwarten: eins, damit _ready() des Modells durchläuft und
	# es sich baut, eins, damit der Viewport es tatsächlich zeichnet — genau
	# das Zeichnen löst die Shader-Kompilierung aus.
	await get_tree().process_frame
	await get_tree().process_frame
	model.queue_free()

	_index += 1
	# Ein zusätzlicher freier Frame zwischen den Waffen, damit der jetzt
	# fällige Kompilier-Ruckler nicht mit dem der nächsten Waffe verklumpt.
	await get_tree().process_frame
	_warm_next()
