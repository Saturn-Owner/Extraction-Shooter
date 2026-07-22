## Baut jede Waffe mit eigenem Modell einmal unsichtbar auf, bevor der
## Spieler sie je in die Hand nimmt — damit die Grafikkarte ihre Shader
## compiliert, WÄHREND das Level lädt, statt beim ersten Waffenwechsel.
##
## ---------------------------------------------------------------------------
## WARUM ES DEN RUCKLER GAB
##
## Godots Forward+-Renderer übersetzt für jede Kombination aus Mesh,
## Material UND aktiven Umgebungs-Merkmalen (Nebel, Umgebungslicht, ...)
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
## DIESELBE WELT, NICHT EINE EIGENE — SONST STIMMT DIE SHADER-VARIANTE NICHT
##
## Ein erster Versuch hat hier einen Viewport mit `own_world_3d = true`
## benutzt: eigene, leere Welt ohne Nebel, ohne die Umgebungsbeleuchtung des
## echten Levels. Das Ergebnis war wirkungslos — kompiliert wurde die
## Shader-Variante FÜR DIESE leere Welt, und beim echten Schuss im Level
## (mit Nebel, mit der echten Sonne) brauchte es trotzdem eine ANDERE
## Variante. Der Ruckler blieb.
##
## Deshalb bekommt der Viewport hier KEINE eigene Welt: Ohne `own_world_3d`
## teilt er sich automatisch die World3D des Levels, in dem er hängt — same
## Nebel, dieselbe Sonne, dieselbe Umgebung wie beim echten Spielen. Damit
## kompiliert er GENAU die Variante, die gleich wirklich gebraucht wird.
## Positioniert wird deshalb weit ausserhalb jeder Karte (WARMUP_POSITION),
## damit die echte Spielkamera die aufgewärmten Waffen nie zu Gesicht
## bekommt.
##
## ---------------------------------------------------------------------------
## AK UND AR-15 ZUERST
##
## Der Spieler startet im Testgelände (und je nach Ausrüstung auch im Raid)
## bereits MIT diesen beiden Waffen in der Hand — er kann sie sofort
## wechseln, noch bevor eine über eine feste Reihenfolge spät drankommende
## Waffe aufgewärmt wäre. Die beiden teuren, echten Modelle stehen deshalb
## vorn in der Warteschlange, die günstigen Box-Waffen (ohnehin fast
## kostenlos aufzuwärmen) hinten.
##
## ---------------------------------------------------------------------------
## VERTEILT AUF MEHRERE FRAMES
##
## Alle Waffen im selben Frame aufzubauen, verschöbe den Ruckler nur vom
## Waffenwechsel zum Levelstart, ohne ihn kleiner zu machen. Stattdessen
## kommt jede Waffe in ihren EIGENEN Frame — aus einem grossen Ruckler
## werden viele kleine, die beim Losrennen kaum auffallen.
class_name WeaponWarmup
extends Node

const VIEWPORT_SIZE := Vector2i(64, 64)

## Weit ausserhalb jeder Karte und jeder Nebel-/Sichtweite. Die Kamera hier
## sieht nur die aufgewärmte Waffe, und die echte Spielkamera sieht diese
## Stelle nie.
const WARMUP_POSITION := Vector3(0.0, 6000.0, 0.0)

## Diese Waffen zuerst, weil der Spieler sie sofort in der Hand hat (siehe
## Klassenkopf). Alles andere folgt in der Reihenfolge von ItemRegistry.
const PRIORITY := [&"weapon_rifle_akm", &"weapon_rifle_ar15"]

var _viewport: SubViewport
var _weapons: Array[WeaponData] = []
var _index := 0


func _ready() -> void:
	ItemRegistry.ensure_loaded()

	var rest: Array[WeaponData] = []
	for item in ItemRegistry.get_by_category(ItemData.Category.WEAPON):
		var data := item as WeaponData
		# GenericViewmodel (kein eigenes Modell) braucht kein Aufwärmen — es
		# besteht nur aus den längst bekannten Box-Materialien.
		if data != null and data.has_own_viewmodel() and not PRIORITY.has(data.id):
			rest.append(data)

	for priority_id in PRIORITY:
		var data := ItemRegistry.get_item(priority_id) as WeaponData
		if data != null:
			_weapons.append(data)
	_weapons.append_array(rest)

	if _weapons.is_empty():
		queue_free()
		return

	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.global_position = WARMUP_POSITION
	_viewport.add_child(camera)
	camera.make_current()

	_warm_next()


func _warm_next() -> void:
	if _index >= _weapons.size():
		queue_free()
		return

	var data := _weapons[_index]
	var model := data.create_viewmodel()
	# Auch die Anbauteile aufwärmen, nicht nur den Waffenkörper — sonst
	# ruckelt es stattdessen beim ersten Anbau an der Werkbank. Weapon_data
	# MUSS vor add_child() stehen, sonst baut das Modell ohne Bestückung
	# (siehe dieselbe Reihenfolge-Regel in weapon_view.gd).
	model.weapon_data = data
	model.attachments = _full_kit(data)
	_viewport.add_child(model)
	model.global_position = WARMUP_POSITION + Vector3(0.0, 0.0, -0.5)
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


## Je ein Anbauteil pro Steckplatz, den diese Waffe hat — wortgleiches
## Vorbild: tools/render_viewmodel.gd::_full_kit().
func _full_kit(weapon: WeaponData) -> Dictionary:
	var kit := {}
	for item in ItemRegistry.get_by_category(ItemData.Category.ATTACHMENT):
		var attachment := item as AttachmentData
		if attachment == null or not weapon.accepts_attachment(attachment):
			continue
		if not kit.has(int(attachment.slot)):
			kit[int(attachment.slot)] = attachment.id
	return kit
