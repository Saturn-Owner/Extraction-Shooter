## Prüft Spielerszene, Testgelände, Eingabebelegung und Bewegungsrechnung.
##
##   godot --headless --path . --import --quit-after 120
##   godot --headless --path . --script res://tests/verify_player.gd
##
## Was hier NICHT geprüft werden kann: ob sich die Bewegung gut anfühlt.
## Das muss ein Mensch im Spiel beurteilen.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	print("=== Spieler und Testgelände prüfen ===\n")
	_test_input_actions()
	_test_player_scene()
	_test_level_scene()
	_test_weight_curve()
	_test_sprint_rules()
	_test_ui_lock()
	_test_windows()
	await _test_visible_body()

	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Der sichtbare Koerper des Spielers.
##
## ---------------------------------------------------------------------------
## DIESELBE FIGUR WIE IM TESTGELAENDE
##
## Kein zweiter Koerper fuer den Spieler — genau dafuer kennt
## `CharacterAnimation` nur `stance`, `is_sprinting`, `is_aiming` und `speed`.
## Frueher fuellte ein Dummy-Skript diese Felder, jetzt tun es die Tasten.
##
## Der wichtigste Punkt steht weiter unten: Der Koerper teilt sich das
## `HealthSystem` des Spielers. Damit ist der Spieler zum ersten Mal NACH
## KOERPERTEILEN treffbar — vorher hatte er nur eine Kollisionskapsel ohne
## `take_hit`, Geschosse blieben also folgenlos.
func _test_visible_body() -> void:
	_section("Sichtbarer Koerper")

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	root.add_child(floor_body)

	var scene := load("res://scenes/player/player.tscn") as PackedScene
	var player := scene.instantiate() as PlayerController
	root.add_child(player)
	# Erst nach einem Bild ist der Knoten wirklich im Baum — vorher wirft
	# global_position einen Fehler und die Zuweisung verpufft.
	await process_frame
	player.global_position = Vector3(0.0, 0.05, 0.0)
	for i in range(30):
		await process_frame

	_check(player.body != null, "der Spieler hat einen Koerper")
	if player.body == null:
		return

	_check(player.body.health == player.health,
		"und teilt sich dessen Gesundheitssystem, statt ein eigenes zu haben")

	var boxes := 0
	for node in PlayerController._all_children(player.body):
		if node is CharacterHitbox:
			boxes += 1
	_check(boxes >= 7, "er bringt Trefferzonen mit (%d)" % boxes)

	# --- Man sieht seinen eigenen Koerper, aber nicht von innen ---
	#
	# HIER STAND EINMAL DAS GEGENTEIL.
	#
	# Zuerst war der ganze Koerper vor der eigenen Kamera ausgeblendet, und
	# dieser Test bestand darauf. Beim Spielen sah man daraufhin gar keinen
	# Koerper — nur die Waffe, also genau den Zustand von vorher. Der Test war
	# gruen und hat die falsche Sache abgesichert.
	#
	# Ausgeblendet gehoert nur, worin die Kamera steckt: der Kopf auf 1,56 bis
	# 1,80 m bei einer Augenhoehe von 1,65.
	var own_bit := 1 << (PlayerController.OWN_BODY_LAYER - 1)
	var camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	_check(camera != null and (camera.cull_mask & own_bit) == 0,
		"die eigene Kamera blendet die versteckte Ebene aus")

	# Kopf UND Brust muessen weg.
	#
	# Der Kopf, weil die Kamera darin steckt. Die Brust, weil ihre Oberkante
	# bei 1,52 m liegt und die Kamera bei 1,65 senkrecht darueber — beim
	# Blick nach unten fuellte sie im Rendering den kompletten Schirm. Das
	# habe ich erst gesehen, nachdem ich es gerendert hatte; gerechnet hatte
	# ich nur, dass sie die Kamera nicht umschliesst. Tut sie auch nicht, sie
	# steht nur 13 cm davor.
	for part: HealthSystem.Part in PlayerController.HIDDEN_FROM_SELF:
		var hidden := true
		for mesh: MeshInstance3D in player.body.meshes_of(part):
			if mesh.layers != own_bit:
				hidden = false
		_check(hidden, "%s ist vor der eigenen Kamera versteckt"
			% BlockyCharacter.part_name(part))

	_check(not PlayerController.HIDDEN_FROM_SELF.has(HealthSystem.Part.LEFT_ARM)
			and not PlayerController.HIDDEN_FROM_SELF.has(HealthSystem.Part.LEFT_LEG),
		"Arme und Beine stehen NICHT auf der Versteckliste")

	# ARME, BAUCH UND BEINE MUESSEN SICHTBAR SEIN.
	#
	# Das ist der Kern der ersten Person hier: Man soll die eigenen Arme
	# sehen, wie sie die Waffe halten und nachladen — nicht ein zweites
	# Modell vor der Kamera.
	var visible_parts := 0
	for part: HealthSystem.Part in [HealthSystem.Part.STOMACH,
			HealthSystem.Part.LEFT_ARM, HealthSystem.Part.RIGHT_ARM,
			HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG]:
		for mesh: MeshInstance3D in player.body.meshes_of(part):
			if (mesh.layers & camera.cull_mask) != 0:
				visible_parts += 1
	_check(visible_parts >= 8,
		"Arme, Bauch und Beine sind sichtbar (%d Kaesten)" % visible_parts)

	_check(player.body.visible,
		"der Koerper ist nicht auf unsichtbar gestellt - sonst waeren auch "
			+ "die Trefferzonen und der eigene Schatten weg")

	# --- Der Koerper HAELT die Waffe, wie die Dummys es tun ---
	#
	# Ohne sie hingen die Arme an den Seiten, waehrend das Kameramodell davor
	# schwebte — beim Blick nach unten sah man genau das. Die Waffe am Koerper
	# ist dieselbe CharacterWeapon wie bei den Figuren im Testgelaende, nur in
	# der Betriebsart DRIVEN: Sie entscheidet nichts, sie zeigt nur.
	_check(player.body_weapon != null, "der Koerper haelt eine Waffe")
	if player.body_weapon != null:
		var anim := player._body_animation
		_check(anim.holding_weapon,
			"die Arme gehoeren an die Waffe statt in den Gehzyklus")
		_check(anim.grip_target != null and anim.support_target != null,
			"die Griffpunkte kommen aus dem Waffenmodell")

		if anim.grip_target != null and anim.support_target != null:
			var right_hand := player.body.hand_of(HealthSystem.Part.RIGHT_ARM)
			var left_hand := player.body.hand_of(HealthSystem.Part.LEFT_ARM)
			var to_grip := right_hand.global_position.distance_to(
				anim.grip_target.global_position)
			var to_fore := left_hand.global_position.distance_to(
				anim.support_target.global_position)
			_check(to_grip < 0.05 and to_fore < 0.05,
				"beide Haende liegen daran (%.0f / %.0f mm)"
					% [to_grip * 1000.0, to_fore * 1000.0])

		# ZWEI WAFFEN, EINE SICHTBAR — und zwar die am Koerper.
		#
		# Frueher war es umgekehrt: Das Modell im Kameraraum war sichtbar, die
		# Koerperwaffe versteckt. Dann hielten die Arme ein unsichtbares
		# Gewehr, waehrend ein zweites daneben schwebte.
		var visible_weapon := 0
		for node in PlayerController._all_children(player.body_weapon):
			if node is VisualInstance3D:
				if ((node as VisualInstance3D).layers & camera.cull_mask) != 0:
					visible_weapon += 1
		_check(visible_weapon > 0,
			"die Waffe am Koerper ist sichtbar (%d Teile)" % visible_weapon)
		if player.weapon_view != null:
			_check(not player.weapon_view.visible,
				"und das Modell im Kameraraum ist dafuer aus")

		# Auf Schulterhoehe, nicht vor dem Bauch: Bei 1,30 m rutschte sie
		# unter den Bildrand, die Augen liegen auf 1,65.
		_check(player.body_weapon.global_position.y
				> camera.global_position.y - 0.30,
			"sie haengt hoch genug, um im Bild zu sein (%.2f gegen Auge %.2f)"
				% [player.body_weapon.global_position.y,
					camera.global_position.y])

		_check(player.body_weapon.behaviour == CharacterWeapon.Behaviour.DRIVEN,
			"sie laeuft nicht von allein, sondern zeigt nur die echte Waffe")

	# --- Ein fremder Schuss trifft ein KOERPERTEIL ---
	# Gezielt wird auf den KOPF, nicht auf die Brust.
	#
	# Vor der Brust liegen jetzt die Arme, weil sie die Waffe halten — ein
	# Schuss dorthin trifft zuerst den Unterarm. Das ist richtig so und war
	# der Grund, warum diese Pruefung nach dem Bewaffnen des Koerpers rot
	# wurde. Der Kopf ist die einzige Zone, vor der nichts steht.
	var ammo := ItemRegistry.get_item(&"ammo_556x45_m855a1") as AmmoData
	var head_box := player.body.hitbox_of(HealthSystem.Part.HEAD)
	var target := head_box.global_position
	var from := target + Vector3(0.0, 0.0, -6.0)
	var before := player.health.get_total_hp()

	var shot := Projectile.new()
	root.add_child(shot)
	shot.launch(ammo, from, (target - from).normalized(), 900.0, null, 1 | 4)
	for i in range(60):
		await process_frame

	_check(player.health.get_total_hp() < before,
		"ein fremder Schuss verletzt ihn (%.0f auf %.0f)"
			% [before, player.health.get_total_hp()])
	_check(player.health.get_hp(HealthSystem.Part.HEAD)
			< HealthSystem.get_max_hp(HealthSystem.Part.HEAD),
		"und zwar am getroffenen Koerperteil, nicht irgendwo")

	# --- Der Geschoss-Ausschluss kennt die Trefferzonen ---
	#
	# GEPRUEFT WIRD DIE LISTE, NICHT DER SELBSTSCHADEN.
	#
	# Die Muendung sitzt 84 cm VOR dem Koerper, weil die Waffe im Kameraraum
	# haengt. Ein Selbstschuss laesst sich damit gar nicht herbeifuehren, in
	# keinem Blickwinkel — ein Test darauf waere immer gruen und wuerde nichts
	# beweisen.
	#
	# Sobald ein Schuss naeher am Leib entsteht — Waffe in der Hand des
	# Koerpers, dritte Person, ein Gegner mit Modell —, entscheidet genau
	# diese Liste. Deshalb wird sie selbst geprueft.
	var probe := Projectile.new()
	probe.shooter = player
	root.add_child(probe)
	var excluded: Array[RID] = probe._shooter_bodies()
	_check(excluded.size() >= boxes + 1,
		"der Ausschluss deckt Kapsel UND alle Trefferzonen (%d Koerper)"
			% excluded.size())
	_check(excluded.has(head_box.get_rid()),
		"die Kopfzone des Schuetzen steht darin")
	probe.queue_free()

	# --- Schulterkamera zum Nachsehen ---
	#
	# In der ersten Person steckt die Kamera im Kopf; von dort sieht man vom
	# eigenen Koerper fast nichts — Kopf, Brust und Arme sind ausgeblendet,
	# und der Rest liegt unter dem Bildrand. Ohne diese Ansicht liesse sich
	# gar nicht pruefen, ob Halten, Rennen, Ducken und Springen richtig
	# aussehen. Sie ist ein Werkzeug, kein Spielmodus.
	player._toggle_third_person()
	await process_frame
	_check(player._third_person, "F5 schaltet in die dritte Person")
	_check((camera.cull_mask & own_bit) != 0,
		"dort sieht die Kamera auch Kopf, Brust und Arme")
	_check(camera.position.z > 1.0,
		"und steht hinter der Figur (%.1f m)" % camera.position.z)
	player._toggle_third_person()
	await process_frame
	_check(not player._third_person and (camera.cull_mask & own_bit) == 0,
		"und zurueck in die erste Person")

	# In BEIDEN Ansichten bleibt das Modell im Kameraraum aus — gesehen wird
	# die Waffe am Koerper. Der Umschalter hat es frueher beim Zurueckgehen
	# wieder eingeschaltet, aus der Zeit, als der Spieler keinen sichtbaren
	# Arm hatte.
	if player.weapon_view != null:
		_check(not player.weapon_view.visible,
			"das Kameramodell bleibt in beiden Ansichten aus")

	player.queue_free()
	floor_body.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


## Fehlende Eingabeaktionen führen sonst erst beim Spielen zu Fehlern.
func _test_input_actions() -> void:
	_section("Eingabebelegung")
	for action in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump", "toggle_mouse"]:
		var exists := InputMap.has_action(action)
		_check(exists, "Aktion '%s' ist belegt" % action)
		if exists:
			_check(not InputMap.action_get_events(action).is_empty(),
				"Aktion '%s' hat mindestens eine Taste" % action)


func _test_player_scene() -> void:
	_section("Spielerszene")
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	_check(packed != null, "player.tscn lädt")
	if packed == null:
		return

	var player: Node = packed.instantiate()
	_check(player is PlayerController, "Wurzel ist ein PlayerController")
	_check(player.get_node_or_null("CollisionShape3D") != null, "CollisionShape3D vorhanden")
	_check(player.get_node_or_null("CameraPivot") != null, "CameraPivot vorhanden")
	_check(player.get_node_or_null("CameraPivot/Camera3D") != null, "Kamera unter dem Pivot")

	var p := player as PlayerController
	_check(p.walk_speed < p.sprint_speed, "Sprint ist schneller als Gehen")
	_check(p.crouch_speed < p.walk_speed, "Ducken ist langsamer als Gehen")
	_check(p.crouch_eye_height < p.stand_eye_height, "Augenhöhe sinkt beim Ducken")

	player.free()


func _test_level_scene() -> void:
	_section("Testgelände")
	var packed: PackedScene = load("res://scenes/levels/testgelaende.tscn")
	_check(packed != null, "testgelaende.tscn lädt")
	if packed == null:
		return

	var level: Node = packed.instantiate()
	_check(level.get_node_or_null("Player") != null, "Spieler ist im Level")
	_check(level.get_node_or_null("Boden") != null, "Boden vorhanden")
	_check(level.get_node_or_null("Sonne") != null, "Licht vorhanden")
	_check(level.get_node_or_null("WorldEnvironment") != null, "Umgebung vorhanden")
	_check(level.get_node_or_null("HUD/DebugPanel/DebugLabel") != null, "Debug-Anzeige vorhanden")

	# Ohne Kollision am Boden fällt der Spieler durch die Welt.
	var boden := level.get_node_or_null("Boden/CollisionShape3D") as CollisionShape3D
	_check(boden != null and boden.shape != null, "Boden hat eine Kollisionsform")

	# Die im Projekt eingetragene Startszene muss auch existieren.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_scene != "", "Startszene ist im Projekt eingetragen")
	_check(ResourceLoader.exists(main_scene), "Startszene existiert: %s" % main_scene)

	level.free()


## Die Traglast muss stetig bremsen — keine Sprünge, nie schneller durch Gewicht.
func _test_weight_curve() -> void:
	_section("Traglast")
	var p := PlayerController.new()

	p.carried_weight_kg = 0.0
	var empty_factor := p.get_weight_factor()
	_check(empty_factor > 1.0, "leeres Inventar gibt einen Tempo-Bonus (%.2f)" % empty_factor)

	p.carried_weight_kg = p.comfortable_weight_kg
	_check(is_equal_approx(p.get_weight_factor(), 1.0),
		"an der Komfortgrenze (%.0f kg) genau Normaltempo" % p.comfortable_weight_kg)

	# Kein Sprung an der Komfortgrenze — sonst ruckelt das Tempo beim Aufheben
	# eines einzelnen Gegenstands sichtbar.
	p.carried_weight_kg = p.comfortable_weight_kg - 0.1
	var just_below := p.get_weight_factor()
	p.carried_weight_kg = p.comfortable_weight_kg + 0.1
	var just_above := p.get_weight_factor()
	_check(absf(just_below - just_above) < 0.03, "stetiger Übergang an der Komfortgrenze")

	# Das eigentliche Feedback: 6 kg drueber muss man deutlich merken.
	p.carried_weight_kg = p.comfortable_weight_kg + 6.0
	var noticeable := p.get_weight_factor()
	_check(noticeable < 0.9,
		"6 kg über der Grenze sind spürbar (Faktor %.2f)" % noticeable)

	var last := 99.0
	var monotonic := true
	for kg in [0.0, 3.0, 6.0, 12.0, 20.0, 30.0, 40.0, 60.0]:
		p.carried_weight_kg = kg
		var f := p.get_weight_factor()
		if f > last:
			monotonic = false
		last = f
	_check(monotonic, "mehr Gewicht macht nie schneller")

	p.carried_weight_kg = 999.0
	_check(p.get_weight_factor() > 0.0, "auch überladen bleibt Restbewegung möglich")

	p.free()


## Sprinten soll bewusst eingeschränkt sein, sonst rennt jeder dauernd.
func _test_sprint_rules() -> void:
	_section("Sprintregeln")
	var p := PlayerController.new()
	var forward := Vector2(0.0, -1.0)
	var backward := Vector2(0.0, 1.0)

	# is_on_floor() ist ausserhalb des Spiels immer false, deshalb prüfen wir
	# hier nur die Regeln, die unabhängig davon greifen.
	p.stamina = 0.0
	_check(not p.can_sprint(forward), "ohne Ausdauer kein Sprint")

	p.stamina = p.max_stamina
	_check(not p.can_sprint(backward), "rückwärts kein Sprint")

	p.carried_weight_kg = p.max_weight_kg + 5.0
	_check(not p.can_sprint(forward), "hoffnungslos überladen kein Sprint")

	p.free()


## Bei offenem Fenster darf die Figur nichts mehr tun.
##
## Ohne diese Sperre loest ein Klick auf einen Gegenstand gleichzeitig einen
## Schuss aus — und wer im Dauerfeuer das Inventar oeffnet, ballert weiter.
func _test_ui_lock() -> void:
	_section("Steuerung bei offenem Fenster")

	var packed: PackedScene = load("res://scenes/player/player.tscn")
	if packed == null:
		_check(false, "player.tscn lädt")
		return

	# Ohne Fenster laesst sich der Mausmodus headless nicht pruefen (es gibt
	# keins), und ein Physikschritt ausserhalb des Baums liefert nur Fehler.
	# Geprueft wird deshalb der Zustand, den beide Fenster setzen — dass er
	# dann wirklich greift, steht direkt in den drei Abfragen im Controller.
	var p := packed.instantiate() as PlayerController
	root.add_child(p)

	_check(not p.ui_open, "Steuerung ist zu Beginn frei")

	p.is_sprinting = true
	p.set_ui_open(true)
	_check(p.ui_open, "Fenster offen sperrt die Steuerung")
	_check(not p.is_sprinting, "Sprint endet beim Öffnen")

	# Zweimal öffnen darf nichts kaputtmachen — zwei Fenster können sich
	# überlappen, ohne dass der Spieler danach gelähmt bleibt.
	p.set_ui_open(true)
	p.set_ui_open(false)
	_check(not p.ui_open, "Schliessen gibt die Steuerung wieder frei")

	root.remove_child(p)
	p.free()


## Es gibt nur noch EIN Fenster fuer Ausruestung, Gesundheit und Inventar,
## und es haengt auf Tab. Das eigene Inventarfenster ist geloescht — dieser
## Test haelt fest, dass es auch geloescht bleibt.
func _test_windows() -> void:
	_section("Fenster im Raid")

	_check(not ResourceLoader.exists("res://scenes/ui/inventory_window.tscn"),
		"das alte Inventarfenster ist weg")

	var packed: PackedScene = load("res://scenes/ui/character_window.tscn")
	_check(packed != null, "character_window.tscn lädt")
	if packed == null:
		return

	var window: Node = packed.instantiate()
	_check(window is CharacterWindow, "Wurzel ist ein CharacterWindow")
	# Die Teile, die das Ziehen braucht — frueher lagen sie im Inventarfenster.
	_check(window.get_node_or_null("Layout/Inhalt/Mitte/Inventar/Raster") is InventoryGridView,
		"Rasteransicht vorhanden")
	_check(window.get_node_or_null("DragGhost") is DragGhost, "Zeiger-Abbild vorhanden")
	_check(window.get_node_or_null("SplitPrompt") is SplitPrompt, "Mengenabfrage vorhanden")
	_check(window.get_node_or_null("ItemTooltip") is ItemTooltip, "Infoanzeige vorhanden")
	window.free()

	var level: PackedScene = load("res://scenes/levels/raid_eisstadt.tscn")
	if level == null:
		_check(false, "raid_eisstadt.tscn lädt")
		return
	var raid: Node = level.instantiate()
	_check(raid.get_node_or_null("HUD/CharacterWindow") != null,
		"das Charakterfenster hängt im HUD des Raids")
	_check(raid.get_node_or_null("HUD/InventoryWindow") == null,
		"und kein zweites Inventarfenster daneben")
	raid.free()
