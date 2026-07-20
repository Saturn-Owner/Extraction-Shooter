## Prüft die Karte "Frachthafen" — rechnerisch, ohne dass jemand hinsieht.
##
##   godot --headless --path . --script res://tests/verify_frachthafen.gd
##
## Was hier NICHT geprüft werden kann, und das ist bei einer Karte der grösste
## Teil: ob die Gassen sich eng anfühlen, ob die Kräne im Nebel taugen, ob der
## Weg zur Halle sich nach Spannung oder nach Fussmarsch anfühlt. Das muss ein
## Mensch laufen.
##
## Was geprüft WERDEN kann, ist mehr, als man denkt: Abstände, Erreichbarkeit,
## Rampenwinkel, ob eine Kiste in einer Wand steckt — und vor allem, ob die
## Design-Entscheidung noch stimmt. "Gutes Zeug liegt weit weg" ist eine
## Behauptung über Koordinaten, und Koordinaten kann man nachrechnen. Wer die
## Lagerhalle später verschiebt, bekommt es hier gesagt statt im Spiel.
extends SceneTree

const SCENE := "res://scenes/levels/raid_frachthafen.tscn"

## Godots Grenze für begehbaren Boden liegt bei 45 Grad. Wir bleiben deutlich
## darunter — eine Rampe, die man gerade so hochkommt, fühlt sich wie eine
## Rutsche an.
const MAX_RAMP_DEGREES := 30.0

## Die Architektur-Entscheidung aus CLAUDE.md: Karten bleiben unter ~4 km vom
## Ursprung, damit 32-bit-Floats reichen.
const MAX_WORLD_DISTANCE := 4000.0

var _failed := 0
var _passed := 0

var _level: Node = null
var _crates: Array[LootContainer] = []
var _exits: Array[ExtractionZone] = []
var _solids: Array[StaticBody3D] = []


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Frachthafen pruefen ===\n")
	_run_all()


## Getrennt, weil das Level einen Frame braucht, bis _ready() die Welt gebaut hat.
func _run_all() -> void:
	if not await _load_level():
		print("\n=== ABBRUCH: Karte laedt nicht ===")
		quit(1)
		return

	_test_inventory()
	_test_spawn_distance()
	_test_exit_requirements()
	_test_loot_tables()
	_test_risk_and_reward()
	_test_crates_free()
	_test_spawn_free()
	_test_ramps()
	_test_bridge_clear()
	_test_world_bounds()
	_test_collision_layers()

	_level.free()
	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


# ---------------------------------------------------------------------------

func _load_level() -> bool:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		return false

	_level = packed.instantiate()
	root.add_child(_level)
	# Zwei Frames: einer fuer _ready() der Ebenen, einer fuer die Kinder, die
	# das Layout darin erst anlegt.
	await process_frame
	await process_frame

	_collect(_level)
	return true


func _collect(node: Node) -> void:
	if node is LootContainer:
		_crates.append(node)
	elif node is ExtractionZone:
		_exits.append(node)
	elif node is StaticBody3D:
		_solids.append(node)
	for child in node.get_children():
		_collect(child)


func _test_inventory() -> void:
	_section("Bestand")

	_check(_crates.size() >= 10, "mindestens zehn Kisten (%d)" % _crates.size())
	_check(_exits.size() >= 2, "mindestens zwei Ausgaenge (%d)" % _exits.size())
	# Ein einziger Ausgang waere keine Entscheidung, sondern ein Rueckweg.
	_check(_exits.size() >= 3, "drei Ausgaenge, damit es etwas zu waehlen gibt")
	_check(_solids.size() > 50, "die Welt ist wirklich gebaut (%d Festkoerper)" % _solids.size())

	var player := _level.get_node_or_null("Player")
	_check(player != null, "der Spieler steht in der Szene")


## Der Fehler der alten Karte: Dort liegt ein Ausgang zehn Meter vom Spawn.
## Man kann einen Raid in zwoelf Sekunden beenden, ohne eine Kiste anzufassen —
## und damit gibt es nichts zu entscheiden.
func _test_spawn_distance() -> void:
	_section("Abstand zum naechsten Ausgang")

	var spawn := _spawn()
	var nearest := _nearest_exit_distance(spawn)
	_check(nearest >= 40.0,
		"der naechste Ausgang liegt %.0f m vom Spawn (mindestens 40)" % nearest)

	# Der kuerzeste Raid ist nicht "naechster Weg plus kuerzester Timer" —
	# beides muss am SELBEN Ausgang zusammenkommen. Also jeden durchrechnen
	# und den schnellsten nehmen.
	var quickest := INF
	var quickest_name := ""
	for zone in _exits:
		var seconds := zone.global_position.distance_to(spawn) / 2.4 + zone.required_time
		if seconds < quickest:
			quickest = seconds
			quickest_name = zone.display_name
	print("         schnellster Raid: %.0f s ueber %s (Gehtempo, Luftlinie)" % [
		quickest, quickest_name])
	_check(quickest >= 30.0, "auch der schnellste Weg raus dauert %.0f s" % quickest)


## Fängt genau den Fehler ab, der auf der alten Karte steht: AusgangKlippe
## verlangt dort `backpack_small` — ein Item, das es nicht gibt. Der Ausgang
## ist damit dauerhaft unbenutzbar, und niemand merkt es, weil die Anzeige
## einfach die rohe ID zeigt.
func _test_exit_requirements() -> void:
	_section("Bedingungen der Ausgaenge")

	for zone in _exits:
		if zone.required_item_id == &"":
			_check(true, "%s verlangt nichts" % zone.display_name)
			continue
		_check(ItemRegistry.has_item(zone.required_item_id),
			"%s verlangt '%s' — und das Item existiert" % [
				zone.display_name, zone.required_item_id])

	for zone in _exits:
		_check(zone.required_time > 0.0,
			"%s hat einen Timer (%.0f s)" % [zone.display_name, zone.required_time])


func _test_loot_tables() -> void:
	_section("Loot-Tabellen")

	for crate in _crates:
		if crate.loot_table == null:
			_check(false, "%s hat eine Tabelle" % crate.name)
			continue
		var problems := crate.loot_table.validate()
		_check(problems.is_empty(),
			"%s: Tabelle ohne Datenfehler%s" % [crate.name,
				"" if problems.is_empty() else " — " + ", ".join(problems)])

	# Das Raster muss zu den Kisten passen, die hineinsollen.
	for crate in _crates:
		_check(crate.grid_width > 0 and crate.grid_height > 0,
			"%s hat ein Raster (%dx%d)" % [crate.name, crate.grid_width, crate.grid_height])


## Die Design-Entscheidung als Rechnung.
##
## Gutes Zeug liegt weit weg vom Start, und in der Naehe des guten Zeugs gibt
## es keinen billigen Ausgang. Beides ist eine Behauptung ueber Koordinaten —
## und wer die Lagerhalle spaeter verschiebt, bekommt es hier gesagt.
func _test_risk_and_reward() -> void:
	_section("Risiko und Belohnung")

	var spawn := _spawn()
	var military := _crates_with("militaer")
	var housing := _crates_with("wohnung")

	_check(not military.is_empty(), "es gibt Militaerkisten (%d)" % military.size())
	_check(not housing.is_empty(), "es gibt Wohnungskisten (%d)" % housing.size())
	if military.is_empty() or housing.is_empty():
		return

	var nearest_military := INF
	for crate in military:
		nearest_military = minf(nearest_military, crate.global_position.distance_to(spawn))

	var farthest_housing := 0.0
	for crate in housing:
		farthest_housing = maxf(farthest_housing, crate.global_position.distance_to(spawn))

	_check(nearest_military > farthest_housing,
		"jede Militaerkiste liegt tiefer drin als jede Wohnungskiste (%.0f m gegen %.0f m)" % [
			nearest_military, farthest_housing])

	# Und der naechste Ausgang beim guten Zeug darf kein schneller sein.
	# Sonst waere der tiefe Weg belohnt UND billig — dann gibt es keinen Grund,
	# jemals den langen Rueckweg zu nehmen.
	for crate in military:
		var zone := _nearest_exit(crate.global_position)
		if zone == null:
			continue
		_check(zone.required_time >= 12.0,
			"%s: naechster Ausgang ist %s mit %.0f s (mindestens 12)" % [
				crate.name, zone.display_name, zone.required_time])


## Eine Kiste in einer Wand kann man sehen, aber nicht erreichen — und das
## faellt erst auf, wenn jemand davorsteht.
func _test_crates_free() -> void:
	_section("Kisten stehen frei")

	for crate in _crates:
		var blocker := _solid_containing(crate.global_position + Vector3(0.0, 0.4, 0.0))
		_check(blocker == "",
			"%s steckt in nichts%s" % [crate.name,
				"" if blocker == "" else " — steckt in %s" % blocker])


func _test_spawn_free() -> void:
	_section("Der Spawn")

	var spawn := _spawn()
	# Auf Brusthoehe pruefen: Der Fusspunkt liegt knapp ueber dem Boden, ein
	# Quader dort waere nur ein Bordstein.
	var blocker := _solid_containing(spawn + Vector3(0.0, 1.0, 0.0))
	_check(blocker == "", "der Spieler startet im Freien%s" % [
		"" if blocker == "" else " — steckt in %s" % blocker])

	var ground := _level.get_node_or_null("Boden")
	_check(ground != null, "es gibt einen Boden unter ihm")


## Der Spieler springt knapp 0,8 m hoch. Auf einen 2,6 m hohen Container kommt
## er nur ueber eine Rampe — und die muss flach genug sein, sonst ist sie eine
## Wand, die aussieht wie ein Weg.
func _test_ramps() -> void:
	_section("Rampen")

	var ramps := _level.find_child("Rampen", true, false)
	_check(ramps != null, "es gibt Rampen")
	if ramps == null:
		return

	for child in ramps.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		var angle := absf(body.rotation_degrees.x)
		_check(angle > 0.5 and angle <= MAX_RAMP_DEGREES,
			"%s steigt mit %.1f Grad (hoechstens %.0f)" % [body.name, angle, MAX_RAMP_DEGREES])

	# Die Rechnung im Layout muss zur Geometrie passen: Rampe hoch, Container
	# hoch — wer da danebenliegt, landet auf einer Kante statt oben.
	for entry: Dictionary in FrachthafenLayout.RAMPS:
		var rise: float = entry.rise
		var run: float = entry.run
		var degrees := rad_to_deg(atan2(rise, run))
		_check(degrees <= MAX_RAMP_DEGREES,
			"%s: %.2f m auf %.1f m sind %.1f Grad" % [entry.name, rise, run, degrees])


## Der Laufsteg streift die Containerreihe bei z = 6 nur knapp: Ein Zweierstapel
## endet bei 5,18 m, der Steg beginnt bei 5,60 m. Vier Zentimeter mehr als eine
## Handbreit.
##
## Wer in `CONTAINER_ROWS` bei z = 6 eine Hoehe von 2 auf 3 setzt — eine
## harmlos aussehende Zahl —, schiebt einen Container mitten durch die Bruecke.
## Im Spiel merkt man das erst, wenn man oben davorsteht und nicht weiterkommt.
func _test_bridge_clear() -> void:
	_section("Die Bruecke ist frei")

	var bridge := _level.find_child("Laufsteg", true, false) as StaticBody3D
	_check(bridge != null, "der Laufsteg steht")
	if bridge == null:
		return

	var walkway := _aabb_of(bridge)
	var blockers: Array[String] = []
	for body in _solids:
		if body == bridge or body.name.begins_with("Rampe") \
				or body.name == "Plattform" or body.name.begins_with("Kran") \
				or body.name.begins_with("Ausleger"):
			continue
		if _aabb_of(body).intersects(walkway):
			blockers.append(body.get_parent().name)

	_check(blockers.is_empty(),
		"nichts ragt in den Laufsteg%s" % [
			"" if blockers.is_empty() else " — " + ", ".join(blockers)])


func _test_world_bounds() -> void:
	_section("Weltgrenzen")

	var farthest := 0.0
	var farthest_name := ""
	for body in _solids:
		var distance := body.global_position.length()
		if distance > farthest:
			farthest = distance
			farthest_name = body.name

	_check(farthest < MAX_WORLD_DISTANCE,
		"alles bleibt unter %.0f m vom Ursprung (weitester: %s bei %.0f m)" % [
			MAX_WORLD_DISTANCE, farthest_name, farthest])


## Wer die Ebene vergisst, baut eine Kulisse, durch die man hindurchlaeuft.
func _test_collision_layers() -> void:
	_section("Kollisionsebenen")

	var wrong_layer := 0
	var wrong_mask := 0
	for body in _solids:
		if body.collision_layer != WorldParts.WORLD_LAYER:
			wrong_layer += 1
		if body.collision_mask != 0:
			wrong_mask += 1

	_check(wrong_layer == 0, "alle %d Festkoerper liegen auf Ebene 1 (%d falsch)" % [
		_solids.size(), wrong_layer])
	_check(wrong_mask == 0, "keiner tastet selbst ab (%d falsch)" % wrong_mask)


# ---------------------------------------------------------------------------
# Helfer
# ---------------------------------------------------------------------------

func _spawn() -> Vector3:
	var player := _level.get_node_or_null("Player") as Node3D
	return player.global_position if player != null else Vector3.ZERO


func _nearest_exit(from: Vector3) -> ExtractionZone:
	var best: ExtractionZone = null
	var best_distance := INF
	for zone in _exits:
		var distance := zone.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = zone
	return best


func _nearest_exit_distance(from: Vector3) -> float:
	var zone := _nearest_exit(from)
	return zone.global_position.distance_to(from) if zone != null else 0.0


## Alle Kisten, deren Loot-Tabelle so heisst.
func _crates_with(table_name: String) -> Array[LootContainer]:
	var result: Array[LootContainer] = []
	for crate in _crates:
		if crate.loot_table == null:
			continue
		if crate.loot_table.resource_path.get_file().begins_with(table_name):
			result.append(crate)
	return result


## Name des Festkoerpers, in dem dieser Punkt steckt — oder "".
##
## Gerechnet wird ueber die Weltraum-AABB der Mesh. Bei gedrehten Quadern ist
## die etwas zu gross; das macht die Pruefung strenger als noetig, nie
## grosszuegiger. Ein Fehlalarm ist hier billiger als ein uebersehener Fehler.
func _solid_containing(point: Vector3) -> String:
	for body in _solids:
		if _aabb_of(body).has_point(point):
			return body.name
	return ""


## Weltraum-AABB eines Festkoerpers. Leer, wenn er keine Mesh hat.
func _aabb_of(body: StaticBody3D) -> AABB:
	var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return AABB()
	return mesh.global_transform * mesh.get_aabb()
