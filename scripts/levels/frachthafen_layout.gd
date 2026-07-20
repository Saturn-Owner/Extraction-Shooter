## Baut die Karte "Frachthafen" auf.
##
## ---------------------------------------------------------------------------
## WARUM IM CODE UND NICHT IN DER SZENE
##
## Eine Karte mit hundert Quadern waere eine riesige .tscn — und .tscn-Dateien
## lassen sich bei Konflikten nicht mergen. Bei zwei Entwicklern an einer Karte
## waere das eine dauerhafte Konfliktquelle. Dieselbe Begruendung steht schon
## in `workbench_station.gd` fuer die Werkbank.
##
## Damit die Karte trotzdem anfassbar bleibt, steht das LAYOUT hier oben als
## reine Daten. Eine Gasse verschieben heisst: eine Zahl aendern.
##
## ---------------------------------------------------------------------------
## DIE KARTE
##
##                          -Z (Norden)
##    [Eisbrecher]              ┌───────────────┐
##     (-48, -48)               │  LAGERHALLE   │  Militaerloot
##      15 Sekunden             └───────┬───────┘  (0, -48)
##
##         ═════════ KRANBRUECKE, y = 6 ═════════  [Kranhaus] (34, 6, 5)
##         Kran (-30)                Kran (30)      8 Sekunden, exponiert
##
##              ▨▨ ▨▨ ▨▨ CONTAINERFELD ▨▨ ▨▨
##                     Werkstattloot
##
##    [Fischerkai]              KAI
##     (-52, 58)          Wohnungsloot, Rucksack
##      12 Sekunden          ▲ SPAWN (0, 55)
##                          +Z (Sueden)
##
## Die Entscheidung, um die es geht: Das beste Zeug liegt 103 m vom Spawn in
## der Lagerhalle. Zurueck kommt man entweder ueber den Eisbrecher — 38 m
## entfernt, aber fuenfzehn Sekunden stillstehen, tief in der Karte — oder man
## traegt alles 110 m zurueck zum sicheren Fischerkai.
##
## Der class_name ist fuer den Test da: Der rechnet die Rampenwinkel aus
## denselben Zahlen nach, aus denen sie gebaut werden.
class_name FrachthafenLayout
extends Node3D

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

## Wo der Spieler anfaengt. Die Szene setzt den Player selbst dorthin; hier
## steht es, damit der Test nachrechnen kann, wie weit der naechste Ausgang ist.
const SPAWN := Vector3(0.0, 0.2, 55.0)

## Das Containerfeld, Reihe fuer Reihe von Sued nach Nord.
##
## Jede Reihe ist eine Ost-West-Wand aus Containern. Die LUECKEN sind das
## eigentliche Leveldesign: Wo in einer Reihe kein Container steht, kommt man
## nach Norden durch. Wer eine Gasse aufmachen will, nimmt hier eine Zahl aus
## `x` heraus.
##
## `hoch` ist die Stapelhoehe pro Container — gleich lang wie `x`.
const CONTAINER_ROWS := [
	{z = 34.0, x = [-32.0, -25.0, -18.0, -4.0, 3.0, 10.0, 24.0, 31.0],
		hoch = [1, 2, 1, 1, 2, 1, 1, 2]},
	{z = 27.0, x = [-32.0, -18.0, -11.0, -4.0, 10.0, 17.0, 24.0, 31.0],
		hoch = [2, 1, 2, 1, 1, 2, 1, 1]},
	{z = 20.0, x = [-25.0, -18.0, -11.0, 3.0, 10.0, 17.0, 31.0],
		hoch = [1, 3, 1, 2, 1, 1, 2]},
	{z = 13.0, x = [-32.0, -25.0, -11.0, -4.0, 3.0, 17.0, 24.0],
		hoch = [1, 1, 2, 1, 3, 1, 2]},
	{z = 6.0, x = [-32.0, -25.0, -18.0, -4.0, 10.0, 17.0, 24.0, 31.0],
		hoch = [2, 1, 1, 2, 1, 1, 2, 1]},
	{z = -1.0, x = [-25.0, -18.0, -11.0, 3.0, 10.0, 24.0, 31.0],
		hoch = [1, 2, 1, 1, 2, 1, 1]},
	{z = -8.0, x = [-32.0, -18.0, -11.0, -4.0, 3.0, 17.0, 24.0, 31.0],
		hoch = [1, 1, 2, 1, 1, 2, 1, 1]},
]

## Rampen. `rise` und `run` statt Grad: Man denkt beim Bauen in "von hier bis
## dort hoch", nicht in Winkeln.
##
## `richtung` ist die Blickrichtung in Grad um die Hochachse; 180 heisst nach
## Norden. `fuss` ist der Punkt, an dem man sie betritt.
const RAMPS := [
	{name = "RampeWest", fuss = Vector3(-4.0, 0.0, 41.0),
		rise = 2.59, run = 7.5, breite = 3.0, richtung = 180.0},
	{name = "RampeOst", fuss = Vector3(24.0, 0.0, 41.0),
		rise = 2.59, run = 7.5, breite = 3.0, richtung = 180.0},
	# Bewusst auf x = 37, nicht 36: Bei 36 streift die Rampenkante die
	# Containerreihe bei x = 31, die bis x = 34.03 reicht. Drei Zentimeter
	# Ueberschneidung sieht man nicht, aber man bleibt daran haengen.
	{name = "RampeKran", fuss = Vector3(37.0, 0.0, 22.0),
		rise = 6.0, run = 17.0, breite = 4.0, richtung = 180.0},
]

## Die Kranbruecke: der einzige Weg nach oben und die einzige Landmarke, die
## ueber dem Nebel steht. Ohne sie sieht ein Containerfeld ueberall gleich aus.
const BRIDGE_Y := 6.0
const BRIDGE := {von = -34.0, bis = 36.0, z = 5.0, breite = 3.0}
const CRANE_HEIGHT := 18.0
const CRANES := [-30.0, 30.0]

## Die Lagerhalle. Drei Zugaenge, damit sie kein Sackgassen-Tresor ist:
## ein Tor nach Sueden, eine Tuer im Osten, eine Bresche im Westen.
const HALL_POS := Vector3(0.0, 0.0, -48.0)
const HALL_SIZE := Vector3(34.0, 6.0, 22.0)
const HALL_OPENINGS := [
	{side = "sued", offset = 0.0, width = 6.0},
	{side = "ost", offset = -4.0, width = 2.5},
	{side = "west", offset = 5.0, width = 4.0},
]

## Huetten am Kai. Klein, mit einer Tuer, damit der Anfang nicht nur Schnee ist.
const HUTS := [
	{name = "HuetteWest", pos = Vector3(-30.0, 0.0, 52.0), size = Vector3(7.0, 3.0, 6.0),
		openings = [{side = "ost", offset = 0.0, width = 2.0}]},
	{name = "HuetteOst", pos = Vector3(12.0, 0.0, 52.0), size = Vector3(6.0, 3.0, 5.0),
		openings = [{side = "west", offset = 0.0, width = 2.0}]},
]

## Deckung auf dem offenen Stueck zwischen Containerfeld und Lagerhalle.
##
## Ohne das waeren es dreissig Meter blanker Schnee — der Weg zum besten Loot
## waere dann kein Risiko, sondern eine Hinrichtung, sobald es Gegner gibt.
const COVER := [
	{pos = Vector3(-20.0, 0.0, -18.0), size = Vector3(5.0, 2.2, 1.0), dreh = 20.0},
	{pos = Vector3(-6.0, 0.0, -24.0), size = Vector3(6.0, 1.6, 1.0), dreh = -10.0},
	{pos = Vector3(9.0, 0.0, -17.0), size = Vector3(4.0, 2.4, 1.0), dreh = 70.0},
	{pos = Vector3(22.0, 0.0, -26.0), size = Vector3(5.0, 1.8, 1.0), dreh = 15.0},
	{pos = Vector3(-14.0, 0.0, -31.0), size = Vector3(4.5, 2.0, 1.0), dreh = -35.0},
	{pos = Vector3(4.0, 0.0, -33.0), size = Vector3(6.0, 2.2, 1.0), dreh = 5.0},
]

## Die Kisten. `tabelle` ist der Dateiname unter assets/data/loot/.
##
## GRUNDSATZ: Gutes Zeug liegt weit weg. Militaerkisten stehen ausschliesslich
## in der Lagerhalle, 100 m vom Spawn; Wohnungskisten am Kai, wo man anfaengt.
## Der Test rechnet das nach — wer die Halle spaeter verschiebt, merkt es.
const CRATES := [
	{name = "Ausruestung", pos = Vector3(3.0, 0.0, 50.0), tabelle = "ausruestung",
		anzeige = "Ausruestungskiste", raster = Vector2i(4, 2), zeit = 0.6},

	{name = "KaiWest", pos = Vector3(-30.0, 0.0, 52.0), tabelle = "wohnung",
		anzeige = "Spind", raster = Vector2i(6, 4), zeit = 1.0},
	{name = "KaiOst", pos = Vector3(12.0, 0.0, 52.0), tabelle = "wohnung",
		anzeige = "Werkzeugschrank", raster = Vector2i(6, 4), zeit = 1.0},
	{name = "KaiMitte", pos = Vector3(-2.0, 0.0, 44.0), tabelle = "wohnung",
		anzeige = "Kiste am Kai", raster = Vector2i(6, 4), zeit = 1.0},

	{name = "Gasse1", pos = Vector3(-11.0, 0.0, 30.5), tabelle = "werkstatt",
		anzeige = "Ersatzteilkiste", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "Gasse2", pos = Vector3(17.0, 0.0, 23.5), tabelle = "werkstatt",
		anzeige = "Werkzeugkiste", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "Gasse3", pos = Vector3(28.0, 0.0, 16.5), tabelle = "werkstatt",
		anzeige = "Container offen", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "Gasse4", pos = Vector3(-28.0, 0.0, 9.5), tabelle = "werkstatt",
		anzeige = "Ladeguthaufen", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "Gasse5", pos = Vector3(6.0, 0.0, 2.5), tabelle = "werkstatt",
		anzeige = "Ersatzteilkiste", raster = Vector2i(6, 4), zeit = 1.4},

	{name = "HalleWest", pos = Vector3(-10.0, 0.0, -48.0), tabelle = "militaer",
		anzeige = "Militaerkiste", raster = Vector2i(6, 4), zeit = 1.8},
	{name = "HalleNord", pos = Vector3(-4.0, 0.0, -52.0), tabelle = "militaer",
		anzeige = "Munitionskiste", raster = Vector2i(6, 4), zeit = 1.8},
	{name = "HalleMitte", pos = Vector3(6.0, 0.0, -46.0), tabelle = "militaer",
		anzeige = "Waffenkiste", raster = Vector2i(6, 4), zeit = 1.8},
	{name = "HalleOst", pos = Vector3(11.0, 0.0, -51.0), tabelle = "militaer",
		anzeige = "Feldkiste", raster = Vector2i(6, 4), zeit = 1.8},
]

## Die Ausgaenge. Der Reiz liegt im Verhaeltnis von Naehe zu Timer.
const EXITS = [
	{name = "Fischerkai", pos = Vector3(-52.0, 0.0, 58.0), zeit = 12.0,
		anzeige = "Fischerkai"},
	{name = "Kranhaus", pos = Vector3(34.0, BRIDGE_Y, 5.0), zeit = 8.0,
		anzeige = "Kranhaus"},
	{name = "Eisbrecher", pos = Vector3(-48.0, 0.0, -48.0), zeit = 15.0,
		anzeige = "Eisbrecher"},
]

const LOOT_CONTAINER := preload("res://scenes/loot/loot_container.tscn")
const EXTRACTION_ZONE := preload("res://scenes/raid/extraction_zone.tscn")

var _mats: Dictionary = {}


func _ready() -> void:
	_mats = WorldParts.materials()
	_build_kai()
	_build_container_field()
	_build_ramps()
	_build_crane_bridge()
	_build_hall()
	_build_cover()
	_build_crates()
	_build_exits()


# ---------------------------------------------------------------------------
# Bauen
# ---------------------------------------------------------------------------

func _build_kai() -> void:
	var group := Node3D.new()
	group.name = "Kai"
	add_child(group)

	# Kaimauer am Suedrand: gibt dem Anfang eine Kante, damit man weiss, wo
	# hinten ist. Ohne sie steht man in einer Ebene ohne jeden Anhaltspunkt.
	group.add_child(WorldParts.solid("Kaimauer", Vector3(120.0, 1.2, 1.0),
		Vector3(-10.0, 0.6, 62.0), _mats.concrete))

	for hut: Dictionary in HUTS:
		group.add_child(WorldParts.building(hut.name, hut.size, hut.pos,
			_mats.concrete, _mats.dark, hut.openings))


func _build_container_field() -> void:
	var group := Node3D.new()
	group.name = "Containerfeld"
	add_child(group)

	var seed_counter := 0
	for row: Dictionary in CONTAINER_ROWS:
		var xs: Array = row.x
		var heights: Array = row.hoch
		for i in range(xs.size()):
			var height: int = int(heights[i]) if i < heights.size() else 1
			group.add_child(WorldParts.container_stack(
				"Stapel_%d_%d" % [int(row.z), i],
				Vector3(float(xs[i]), 0.0, float(row.z)),
				height, _mats, 0.0, seed_counter))
			seed_counter += 1


func _build_ramps() -> void:
	var group := Node3D.new()
	group.name = "Rampen"
	add_child(group)

	for r: Dictionary in RAMPS:
		group.add_child(WorldParts.ramp(r.name, r.rise, r.run, r.breite,
			r.fuss, _mats.steel, r.richtung))


func _build_crane_bridge() -> void:
	var group := Node3D.new()
	group.name = "Kranbruecke"
	add_child(group)

	var length: float = BRIDGE.bis - BRIDGE.von
	var middle: float = (BRIDGE.von + BRIDGE.bis) * 0.5

	# Die Oberkante liegt auf BRIDGE_Y — darauf laeuft man.
	group.add_child(WorldParts.solid("Laufsteg",
		Vector3(length, 0.4, BRIDGE.breite),
		Vector3(middle, BRIDGE_Y - 0.2, BRIDGE.z), _mats.steel))

	# Plattform am Ostende, breit genug fuer die Ausgangszone.
	group.add_child(WorldParts.solid("Plattform", Vector3(8.0, 0.4, 6.0),
		Vector3(34.0, BRIDGE_Y - 0.2, BRIDGE.z), _mats.steel))

	# Die Krantuerme. 18 Meter, damit sie ueber dem Nebel stehen und man sich
	# an ihnen ausrichten kann.
	for x: float in CRANES:
		group.add_child(WorldParts.solid("Kran%d" % int(x),
			Vector3(2.0, CRANE_HEIGHT, 2.0),
			Vector3(x, CRANE_HEIGHT * 0.5, BRIDGE.z), _mats.rust))
		group.add_child(WorldParts.solid("Ausleger%d" % int(x),
			Vector3(2.0, 1.0, 14.0),
			Vector3(x, CRANE_HEIGHT - 1.0, BRIDGE.z - 6.0), _mats.rust))


func _build_hall() -> void:
	var group := Node3D.new()
	group.name = "Lagerhalle"
	add_child(group)

	group.add_child(WorldParts.building("Halle", HALL_SIZE, HALL_POS,
		_mats.concrete, _mats.dark, HALL_OPENINGS))

	# Deckung im Inneren. Eine leere Halle mit vier Kisten waere ein Raum, in
	# dem man nirgends hinkann, sobald jemand im Tor steht.
	group.add_child(WorldParts.container("RegalWest", Vector3(-8.0, 0.0, -42.0),
		_mats.container_grey, 90.0))
	group.add_child(WorldParts.container("RegalOst", Vector3(9.0, 0.0, -54.0),
		_mats.container_grey, 90.0))
	group.add_child(WorldParts.solid("Stuetze", Vector3(1.0, 6.0, 1.0),
		Vector3(0.0, 3.0, -48.0), _mats.concrete))


func _build_cover() -> void:
	var group := Node3D.new()
	group.name = "Deckung"
	add_child(group)

	for i in range(COVER.size()):
		var piece: Dictionary = COVER[i]
		var size: Vector3 = piece.size
		group.add_child(WorldParts.solid("Mauerrest%d" % i, size,
			piece.pos + Vector3(0.0, size.y * 0.5, 0.0), _mats.concrete,
			Vector3(0.0, float(piece.dreh), 0.0)))


func _build_crates() -> void:
	var group := Node3D.new()
	group.name = "Kisten"
	add_child(group)

	for entry: Dictionary in CRATES:
		var box: LootContainer = LOOT_CONTAINER.instantiate()
		box.name = entry.name
		box.position = entry.pos

		# VOR add_child setzen: `_ready()` baut das Raster aus grid_width und
		# grid_height, und danach ist es zu spaet — die Kiste haette dann
		# stillschweigend die Standardgroesse.
		var raster: Vector2i = entry.raster
		box.grid_width = raster.x
		box.grid_height = raster.y
		box.display_name = entry.anzeige
		box.search_time_multiplier = entry.zeit
		box.loot_table = load("res://assets/data/loot/%s.tres" % entry.tabelle)

		group.add_child(box)


func _build_exits() -> void:
	var group := Node3D.new()
	group.name = "Ausgaenge"
	add_child(group)

	for entry: Dictionary in EXITS:
		var zone: ExtractionZone = EXTRACTION_ZONE.instantiate()
		zone.name = entry.name
		zone.position = entry.pos
		zone.required_time = entry.zeit
		zone.display_name = entry.anzeige
		group.add_child(zone)
