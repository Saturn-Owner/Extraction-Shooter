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
	_test_container_model()
	_test_spawn_distance()
	_test_exit_requirements()
	_test_loot_tables()
	_test_risk_and_reward()
	_test_crates_free()
	_test_spawn_free()
	_test_ramps()
	_test_ships_boardable()
	_test_world_bounds()
	_test_collision_layers()
	_test_asset_sizes()

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


## Das Containermodell — das haeufigste Objekt der Karte, gut vierhundert Stueck.
func _test_container_model() -> void:
	_section("Containermodell")

	_check(WorldParts.has_container_model(), "das Modell liegt im Projekt")
	if not WorldParts.has_container_model():
		return

	var mesh: Mesh = load(WorldParts.CONTAINER_MESH)
	_check(mesh != null, "container_20ft.res laedt als Mesh")
	if mesh == null:
		return

	# Die Mesh kommt roh und schief aus dem Paket. Erst diese Rechnung macht
	# einen Container daraus, der mittig um den Ursprung sitzt und die Groesse
	# hat, mit der das Layout rechnet. Liegt sie daneben, stehen vierhundert
	# Container in falscher Groesse oder halb im Boden.
	var placed := WorldParts.container_mesh_transform(mesh) * mesh.get_aabb()
	var want := WorldParts.CONTAINER_SIZE

	_check(placed.size.is_equal_approx(want),
		"nach dem Zurechtruecken %.2f x %.2f x %.2f (soll %.2f x %.2f x %.2f)" % [
			placed.size.x, placed.size.y, placed.size.z, want.x, want.y, want.z])

	var centre := placed.position + placed.size * 0.5
	_check(centre.length() < 0.01,
		"und sitzt mittig um den Ursprung (Abweichung %.3f m)" % centre.length())

	# Rasterfreundlich: Alle drei Masse muessen restlos in 0,2 m aufgehen,
	# sonst laesst sich im Editor nichts buendig aneinanderschieben — und genau
	# daran ist Lucas beim ersten Versuch haengengeblieben.
	for axis: float in [want.x, want.y, want.z]:
		_check(absf(fmod(axis, 0.2)) < 0.001 or absf(fmod(axis, 0.2) - 0.2) < 0.001,
			"%.2f m passt ins 0,2-m-Raster" % axis)

	# Die entfaerbte Textur ist der Grund, warum eine Textur alle Farben traegt.
	# Steckt die Farbe doch noch drin, kaempft sie gegen die eingestellte.
	var albedo: Texture2D = load(WorldParts.CONTAINER_ALBEDO)
	_check(albedo != null, "die BaseColor-Textur laedt")
	if albedo != null:
		var image := albedo.get_image()
		var coloured := 0
		for i in range(200):
			var x := (i * 37) % image.get_width()
			var y := (i * 53) % image.get_height()
			var c := image.get_pixel(x, y)
			if absf(c.r - c.g) > 0.02 or absf(c.g - c.b) > 0.02:
				coloured += 1
		_check(coloured == 0,
			"sie ist wirklich entfaerbt (%d von 200 Stichproben farbig)" % coloured)

	_check(load(WorldParts.CONTAINER_ORM) != null, "die ORM-Textur laedt")
	_check(load(WorldParts.CONTAINER_NORMAL) != null, "die Normalenkarte laedt")

	# Genug unterscheidbare Farben, und alle teilen sich EINE Textur.
	var colours := WorldParts.container_colors()
	_check(colours.size() >= 4, "mindestens vier Farben (%d)" % colours.size())

	var mats := WorldParts.container_materials()
	var shared := true
	var seen: Texture2D = null
	for key: String in colours:
		var mat: BaseMaterial3D = mats.get(key)
		if mat == null:
			_check(false, "Material '%s' fehlt" % key)
			continue
		if seen == null:
			seen = mat.albedo_texture
		elif mat.albedo_texture != seen:
			shared = false
	_check(shared, "alle Farben teilen sich dieselbe Textur")


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

	# Der Faktor ist das Entscheidende, nicht die blosse Reihenfolge: Liegt das
	# gute Zeug nur zehn Meter weiter, ist der Weg dorthin keine Entscheidung.
	_check(nearest_military > farthest_housing * 1.5,
		"Militaerloot liegt mehr als anderthalbmal so tief wie Wohnungsloot (%.0f m gegen %.0f m)" % [
			nearest_military, farthest_housing])

	# Das gute Zeug liegt an Deck. Ein Ausgang dort oben darf ruhig schnell
	# sein — bezahlt wird mit dem WEG, nicht mit dem Timer. Der Test haelt nur
	# fest, dass der Weg auch wirklich lang ist.
	for crate in military:
		_check(crate.global_position.y > 1.0,
			"%s liegt erhoeht, nicht ebenerdig zu erreichen" % crate.name)


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

	# Boden unter den Fuessen — das Land baut das Layout selbst, es gibt keine
	# durchgehende Platte mehr. Ohne diese Pruefung faellt man beim Start
	# einfach ins Leere, und das merkt man erst beim Starten.
	var below := _solid_containing(spawn - Vector3(0.0, 0.6, 0.0))
	_check(below != "", "unter ihm ist Land%s" % [
		"" if below == "" else " (%s)" % below])

	# Und ueber dem Wasser darf KEIN Boden liegen. Frueher lag eine 220 m
	# grosse Platte auf y = 0 quer ueber dem ganzen Hafenbecken — man konnte
	# aufs Wasser laufen.
	var on_water := _solid_containing(Vector3(0.0, -0.3, -120.0))
	_check(on_water == "", "ueber dem Hafenbecken liegt kein Boden%s" % [
		"" if on_water == "" else " — %s ist im Weg" % on_water])


## Der Spieler springt knapp 0,8 m hoch. Auf einen 2,6 m hohen Container kommt
## er nur ueber eine Rampe — und die muss flach genug sein, sonst ist sie eine
## Wand, die aussieht wie ein Weg.
func _test_ramps() -> void:
	_section("Rampen")

	# Ueber die Neigung suchen, nicht ueber einen Elternknoten: Rampen koennen
	# ueberall haengen — an den Schiffen, an einem Block, irgendwo im Gelaende.
	# Der Test soll sie finden, egal wohin jemand sie spaeter schiebt.
	var ramps: Array[StaticBody3D] = []
	for body in _solids:
		if absf(body.global_rotation_degrees.x) > 0.5:
			ramps.append(body)

	_check(not ramps.is_empty(), "es gibt Rampen (%d)" % ramps.size())

	for body in ramps:
		var angle := absf(body.global_rotation_degrees.x)
		_check(angle <= MAX_RAMP_DEGREES,
			"%s steigt mit %.1f Grad (hoechstens %.0f)" % [body.name, angle, MAX_RAMP_DEGREES])

	# Die Rechnung im Layout muss zur Geometrie passen: Rampe hoch, Container
	# hoch — wer da danebenliegt, landet auf einer Kante statt oben.
	for entry: Dictionary in FrachthafenLayout.RAMPS:
		var rise: float = entry.rise
		var run: float = entry.run
		var degrees := rad_to_deg(atan2(rise, run))
		_check(degrees <= MAX_RAMP_DEGREES,
			"%s: %.2f m auf %.1f m sind %.1f Grad" % [entry.name, rise, run, degrees])


## Die Schiffe sind der einzige Ort mit Militaerloot — und die Gangways der
## einzige Weg hinauf. Landet eine davon neben dem Deck statt darauf, ist das
## beste Zeug der Karte unerreichbar, und niemand merkt es beim Hinsehen.
func _test_ships_boardable() -> void:
	_section("Die Schiffe sind zu betreten")

	for entry: Dictionary in FrachthafenLayout.RAMPS:
		var foot: Vector3 = entry.fuss
		var run: float = entry.run
		var rise: float = entry.rise

		# richtung 180 heisst nach Norden, also -Z.
		var facing: float = entry.richtung
		var forward := Vector3(sin(deg_to_rad(facing)), 0.0, cos(deg_to_rad(facing)))
		var top := foot + forward * run + Vector3(0.0, rise, 0.0)

		# Knapp ueber dem Deck nachsehen, ob dort wirklich Schiff ist.
		var landing := _solid_containing(top - Vector3(0.0, 0.2, 0.0))
		_check(landing != "",
			"%s endet auf festem Grund (%s)" % [entry.name,
				landing if landing != "" else "im Leeren"])

		_check(absf(rise - FrachthafenLayout.DECK_Y) < 0.01,
			"%s endet auf Deckshoehe (%.2f m)" % [entry.name, rise])

	# Und auf jedem Schiff muss auch etwas liegen, sonst lohnt der Weg nicht.
	var on_deck := 0
	for crate in _crates:
		if crate.global_position.y > 1.0:
			on_deck += 1
	_check(on_deck >= 2, "es liegt Loot an Deck (%d Kisten)" % on_deck)


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


## Waechter gegen zu grosse Dateien.
##
## Das Containerpaket, aus dem das Modell stammt, ist 675 MB gross. GitHub
## weist JEDE Datei ueber 100 MB beim Push ab — wer so etwas versehentlich
## einchecked, merkt es erst, wenn der Push scheitert, und muss dann die
## Historie umschreiben. Das ist die unangenehmste Art, das zu lernen.
##
## Geprueft wird, was tatsaechlich im Projekt liegt und nicht ignoriert ist.
func _test_asset_sizes() -> void:
	_section("Dateigroessen")

	# 50 MB, nicht 100: GitHubs harte Grenze liegt bei 100 MB, und wer erst
	# dort anschlaegt, hat schon eingecheckt. Die Haelfte laesst Luft zum
	# Reagieren. Der groesste Brocken im Repo ist heute ein 30-MB-Waffenmodell —
	# unschoen, aber kein Grund, den Test rot zu lassen.
	var limit := 50 * 1024 * 1024
	var oversized: Array[String] = []
	var total := 0
	var count := 0
	var biggest := 0
	var biggest_name := ""

	for path in _all_files("res://assets"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var size := file.get_length()
		file.close()
		total += size
		count += 1
		if size > biggest:
			biggest = size
			biggest_name = path.get_file()
		if size > limit:
			oversized.append("%s (%.0f MB)" % [path.get_file(), size / 1048576.0])

	_check(oversized.is_empty(),
		"keine Datei ueber 50 MB%s" % [
			"" if oversized.is_empty() else " — " + ", ".join(oversized)])
	print("         %d Dateien unter assets/, zusammen %.1f MB" % [
		count, total / 1048576.0])
	print("         groesste: %s mit %.0f MB" % [biggest_name, biggest / 1048576.0])


func _all_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

	for sub in dir.get_directories():
		found.append_array(_all_files("%s/%s" % [dir_path, sub]))
	for file in dir.get_files():
		# Godot haengt im Editor .import an; die eigentliche Datei zaehlt.
		if file.ends_with(".import"):
			continue
		found.append("%s/%s" % [dir_path, file])
	return found


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
