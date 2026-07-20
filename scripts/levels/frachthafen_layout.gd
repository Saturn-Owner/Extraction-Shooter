## Baut die Karte "Frachthafen" auf — nach dem Vorbild eines echten
## Containerterminals (Port of Nordhaven, Winter Operations Plan).
##
## ---------------------------------------------------------------------------
## DER PLAN, VON NORD NACH SUED
##
##            WASSER / AUSSENREEDE            (z < -58)
##     ▄▄▄▄▄▄ Schiff West ▄▄▄▄▄▄    ▄▄▄▄▄▄ Schiff Ost ▄▄▄▄▄▄
##     ╥   ╥   ╥   ╥   KAIANLAGE mit Containerbruecken   ╥   ╥
##  ═══╧═══╧═══╧═══╧═══════════════════════════════════╧═══╧═══  Kaimauer
##
##   ┌────┐ ┌────┐ ┌────┐   ║SLIP║   ┌────┐ ┌────┐ ┌────┐
##   │BLOCK│ │BLOCK│ │BLOCK│  ║ 1  ║   │BLOCK│ │BLOCK│ │BLOCK│
##   └────┘ └────┘ └────┘   ║    ║   └────┘ └────┘ └────┘
##   ══════ TERMINALSTRASSE ══════════════════════════════
##   ┌────┐ ┌────┐ ┌────┐             ┌────┐ ┌────┐ ┌────┐
##   │BLOCK│ │BLOCK│ │BLOCK│             │BLOCK│ │BLOCK│ │BLOCK│
##   └────┘ └────┘ └────┘             └────┘ └────┘ └────┘
##       WEST-TERMINAL                    OST-TERMINAL
##
##   ══════════ BAHNHOF ══════════   ┌───┐ ┌───┐ ┌───┐
##   [TOR]        ▲ SPAWN            │LAGERHALLEN      │
##                                    └───┘ └───┘ └───┘
##
## Rund 330 x 185 m Landflaeche. Zum Vergleich: die Vorgaengerfassung hatte
## 110 x 125 m, die alte Eisstadt 50 x 48 m.
##
## ---------------------------------------------------------------------------
## DIE ENTSCHEIDUNG, UM DIE ES GEHT
##
## Das beste Zeug liegt auf den beiden Schiffen — ueber 175 m vom Spawn, ganz
## im Norden, und man kommt nur ueber eine Gangway hinauf. Dafuer liegt dort
## oben auch der schnellste Ausgang (8 s): Wer es bis aufs Schiff schafft, ist
## schnell draussen. Der sichere Weg ueber das Tor kostet dagegen 12 Sekunden
## und den ganzen Rueckweg.
##
## ---------------------------------------------------------------------------
## WARUM IM CODE
##
## Zwoelf Containerblocks mit je zwanzig Stapeln von Hand zu setzen waere eine
## Woche Klickarbeit. Der Code erzeugt sie aus wenigen Zahlen. Danach wird die
## Karte mit `tools/bake_frachthafen.gd` in eine echte Szene gebacken — ab dann
## laesst sie sich im Editor anfassen wie jede andere.
@tool
class_name FrachthafenLayout
extends Node3D

# ---------------------------------------------------------------------------
# Layout — hier stehen die Zahlen, die man dreht
# ---------------------------------------------------------------------------

## Wo der Spieler anfaengt: am Suedrand zwischen Tor und Bahnhof.
const SPAWN := Vector3(-60.0, 0.2, 100.0)

## Wo das Land aufhoert und das Hafenbecken anfaengt.
const QUAY_EDGE := -58.0

## Land- und Wassergrenzen.
const EAST_EDGE := 165.0
const SOUTH_EDGE := 126.0
const WATER_NORTH := -178.0

## Slip 1 — der Wasserarm, der die beiden Terminals trennt. Er ist der Grund,
## warum man nicht einfach quer laeuft: Wer von West nach Ost will, muss ganz
## nach Sueden um ihn herum oder ganz nach Norden ueber die Kaianlage.
const SLIP_HALF_WIDTH := 14.0
const SLIP_SOUTH := 8.0

## Ein Containerblock: 36 m breit, 40 m tief, darin 4 x 5 Stapelplaetze.
const BLOCK_SIZE := Vector2(36.0, 40.0)
const BLOCK_COLUMNS := 4
const BLOCK_ROWS := 5
const STACK_SPACING := Vector2(9.0, 7.5)

## Wo die Blocks anfangen (linke/noerdliche Ecke).
const BLOCK_X := [-145.0, -101.0, -57.0, 21.0, 65.0, 109.0]
const BLOCK_Z := [-38.0, 16.0]

## Die Containerbruecken am Kai — die hoechsten Dinger auf der Karte und
## damit die einzige Orientierung, die ueber alles hinwegragt.
const STS_CRANES := [-135.0, -105.0, -75.0, -45.0, 45.0, 75.0, 105.0, 135.0]
const STS_HEIGHT := 28.0

## Portalkrane ueber den Blocks. Gelb, damit man sie von unten aus den Gassen
## sieht und weiss, in welchem Block man steckt.
const RTG_HEIGHT := 12.0

## Die beiden Schiffe laengsseits. Deck auf 3 m — man kommt nur ueber die
## Gangway hinauf.
const DECK_Y := 3.0
const SHIPS := [
	{name = "SchiffWest", pos = Vector3(-90.0, 0.0, -72.0), size = Vector3(120.0, 8.0, 22.0)},
	{name = "SchiffOst", pos = Vector3(90.0, 0.0, -72.0), size = Vector3(120.0, 8.0, 22.0)},
]

## Die Gangways. `rise`/`run` statt Grad — man denkt in "von hier bis dort
## hoch". Sie sind der EINZIGE Weg auf die Schiffe.
const RAMPS := [
	{name = "GangwayWest", fuss = Vector3(-90.0, 0.0, -56.0),
		rise = DECK_Y, run = 9.0, breite = 3.0, richtung = 180.0},
	{name = "GangwayOst", fuss = Vector3(90.0, 0.0, -56.0),
		rise = DECK_Y, run = 9.0, breite = 3.0, richtung = 180.0},
]

## Der Bahnhof im Sueden: Gleise und ein paar abgestellte Wagen.
const RAIL_Z := [78.0, 86.0, 94.0]
const RAIL_FROM := -150.0
const RAIL_TO := 55.0
const RAILCARS := [
	{pos = Vector3(-118.0, 0.0, 78.0), size = Vector3(16.0, 3.6, 3.2)},
	{pos = Vector3(-96.0, 0.0, 78.0), size = Vector3(16.0, 3.6, 3.2)},
	{pos = Vector3(-40.0, 0.0, 86.0), size = Vector3(16.0, 3.6, 3.2)},
	{pos = Vector3(-18.0, 0.0, 86.0), size = Vector3(16.0, 3.6, 3.2)},
	{pos = Vector3(20.0, 0.0, 94.0), size = Vector3(16.0, 3.6, 3.2)},
]

## Die Lagerhallen im Suedosten. Grosse Innenraeume — das Gegenstueck zu den
## engen Gassen zwischen den Containern.
const WAREHOUSES := [
	{name = "LagerhalleA", pos = Vector3(78.0, 0.0, 92.0), size = Vector3(26.0, 8.0, 34.0),
		openings = [{side = "nord", offset = 0.0, width = 6.0},
			{side = "west", offset = 6.0, width = 3.0}]},
	{name = "LagerhalleB", pos = Vector3(108.0, 0.0, 92.0), size = Vector3(26.0, 8.0, 34.0),
		openings = [{side = "nord", offset = 0.0, width = 6.0},
			{side = "ost", offset = -8.0, width = 3.0}]},
	{name = "LagerhalleC", pos = Vector3(138.0, 0.0, 92.0), size = Vector3(26.0, 8.0, 34.0),
		openings = [{side = "nord", offset = 0.0, width = 6.0},
			{side = "sued", offset = 4.0, width = 3.0}]},
]

## Das Tor im Suedwesten. Wachhaus plus Schranken.
const GATE_POS := Vector3(-142.0, 0.0, 106.0)

## Die Kisten. `tabelle` ist der Dateiname unter assets/data/loot/.
##
## GRUNDSATZ: Gutes Zeug liegt weit weg. Militaerloot NUR auf den Schiffen,
## ueber 175 m vom Spawn und nur ueber eine Gangway erreichbar. Wohnungsloot am
## Bahnhof, wo man anfaengt. Der Test rechnet das Verhaeltnis nach.
const CRATES := [
	{name = "Ausruestung", pos = Vector3(-66.0, 0.0, 96.0), tabelle = "ausruestung",
		anzeige = "Ausruestungskiste", raster = Vector2i(4, 2), zeit = 0.6},

	{name = "BahnhofWest", pos = Vector3(-100.0, 0.0, 86.0), tabelle = "wohnung",
		anzeige = "Gueterwagen", raster = Vector2i(6, 4), zeit = 1.0},
	{name = "BahnhofMitte", pos = Vector3(-20.0, 0.0, 86.0), tabelle = "wohnung",
		anzeige = "Spind", raster = Vector2i(6, 4), zeit = 1.0},
	{name = "TorWache", pos = Vector3(-138.0, 0.0, 98.0), tabelle = "wohnung",
		anzeige = "Wachhaus", raster = Vector2i(6, 4), zeit = 1.0},

	{name = "BlockWest1", pos = Vector3(-108.0, 0.0, -20.0), tabelle = "werkstatt",
		anzeige = "Offener Container", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "BlockWest2", pos = Vector3(-64.0, 0.0, 36.0), tabelle = "werkstatt",
		anzeige = "Werkzeugkiste", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "BlockOst1", pos = Vector3(60.0, 0.0, -20.0), tabelle = "werkstatt",
		anzeige = "Ersatzteilkiste", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "BlockOst2", pos = Vector3(104.0, 0.0, 36.0), tabelle = "werkstatt",
		anzeige = "Offener Container", raster = Vector2i(6, 4), zeit = 1.4},
	{name = "LagerA", pos = Vector3(78.0, 0.0, 92.0), tabelle = "werkstatt",
		anzeige = "Palettenregal", raster = Vector2i(6, 4), zeit = 1.6},
	{name = "LagerB", pos = Vector3(108.0, 0.0, 92.0), tabelle = "werkstatt",
		anzeige = "Palettenregal", raster = Vector2i(6, 4), zeit = 1.6},
	{name = "LagerC", pos = Vector3(138.0, 0.0, 92.0), tabelle = "werkstatt",
		anzeige = "Palettenregal", raster = Vector2i(6, 4), zeit = 1.6},

	{name = "SchiffWestBug", pos = Vector3(-128.0, DECK_Y, -68.0), tabelle = "militaer",
		anzeige = "Ladeluke", raster = Vector2i(6, 4), zeit = 1.8},
	{name = "SchiffWestHeck", pos = Vector3(-56.0, DECK_Y, -76.0), tabelle = "militaer",
		anzeige = "Frachtraum", raster = Vector2i(6, 4), zeit = 1.8},
	{name = "SchiffOstBug", pos = Vector3(56.0, DECK_Y, -68.0), tabelle = "militaer",
		anzeige = "Ladeluke", raster = Vector2i(6, 4), zeit = 1.8},
	{name = "SchiffOstHeck", pos = Vector3(128.0, DECK_Y, -76.0), tabelle = "militaer",
		anzeige = "Frachtraum", raster = Vector2i(6, 4), zeit = 1.8},
]

## Die Ausgaenge. Der Reiz liegt im Verhaeltnis von Weg zu Timer.
const EXITS = [
	{name = "Tor", pos = Vector3(-142.0, 0.0, 112.0), zeit = 12.0, anzeige = "Werkstor"},
	{name = "BahnhofOst", pos = Vector3(50.0, 0.0, 88.0), zeit = 10.0, anzeige = "Bahnhof Ost"},
	{name = "SchiffWest", pos = Vector3(-90.0, DECK_Y, -72.0), zeit = 8.0, anzeige = "Schiff West"},
]

const LOOT_CONTAINER := preload("res://scenes/loot/loot_container.tscn")
const EXTRACTION_ZONE := preload("res://scenes/raid/extraction_zone.tscn")

var _mats: Dictionary = {}


func _ready() -> void:
	rebuild()


## Baut die ganze Karte neu auf.
##
## Erst aufraeumen, dann bauen: Im Editor laeuft `_ready()` bei jedem Neuladen
## des Skripts noch einmal. Ohne das Aufraeumen staende die Karte nach dem
## dritten Zahlendrehen dreifach uebereinander.
func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_mats = WorldParts.materials()
	_build_ground()
	_build_quay()
	_build_ships()
	_build_terminals()
	_build_rail_yard()
	_build_warehouses()
	_build_gate()
	_build_crates()
	_build_exits()


# ---------------------------------------------------------------------------
# Grund und Wasser
# ---------------------------------------------------------------------------

## Land, Hafenbecken und Kaimauer.
##
## Das Land ist BEWUSST in drei Stuecke geteilt: Ohne die Luecke gaebe es
## keinen Slip, und ohne Slip laeuft man einfach quer durch — dann waeren die
## beiden Terminals nur eine breite Flaeche statt zweier Orte.
func _build_ground() -> void:
	var group := Node3D.new()
	group.name = "Grund"
	add_child(group)

	var land_depth := SOUTH_EDGE - QUAY_EDGE
	var land_centre_z := (QUAY_EDGE + SOUTH_EDGE) * 0.5
	var west_width := EAST_EDGE - SLIP_HALF_WIDTH

	group.add_child(WorldParts.solid("LandWest",
		Vector3(west_width, 2.0, land_depth),
		Vector3(-(SLIP_HALF_WIDTH + west_width * 0.5), -1.0, land_centre_z), _mats.snow))
	group.add_child(WorldParts.solid("LandOst",
		Vector3(west_width, 2.0, land_depth),
		Vector3(SLIP_HALF_WIDTH + west_width * 0.5, -1.0, land_centre_z), _mats.snow))

	# Das Stueck suedlich vom Slip verbindet beide Terminals — der lange Weg.
	var bridge_depth := SOUTH_EDGE - SLIP_SOUTH
	group.add_child(WorldParts.solid("LandSued",
		Vector3(SLIP_HALF_WIDTH * 2.0, 2.0, bridge_depth),
		Vector3(0.0, -1.0, SLIP_SOUTH + bridge_depth * 0.5), _mats.snow))

	# Hafenbecken: ein Boden drei Meter tiefer. Wer ueber die Kaimauer kommt,
	# steht im Wasser statt ins Nichts zu fallen.
	var basin_depth := QUAY_EDGE - WATER_NORTH
	group.add_child(WorldParts.solid("Hafenbecken",
		Vector3(EAST_EDGE * 2.0, 2.0, basin_depth),
		Vector3(0.0, -4.0, WATER_NORTH + basin_depth * 0.5), _mats.dark))
	group.add_child(WorldParts.solid("SlipBoden",
		Vector3(SLIP_HALF_WIDTH * 2.0, 2.0, SLIP_SOUTH - QUAY_EDGE),
		Vector3(0.0, -4.0, (QUAY_EDGE + SLIP_SOUTH) * 0.5), _mats.dark))

	# Wasseroberflaeche: nur Optik, keine Kollision.
	group.add_child(WorldParts.flat("Wasser",
		Vector2(EAST_EDGE * 2.0, basin_depth),
		Vector3(0.0, -0.6, WATER_NORTH + basin_depth * 0.5), _mats.water))
	group.add_child(WorldParts.flat("SlipWasser",
		Vector2(SLIP_HALF_WIDTH * 2.0, SLIP_SOUTH - QUAY_EDGE),
		Vector3(0.0, -0.6, (QUAY_EDGE + SLIP_SOUTH) * 0.5), _mats.water))

	# Kaimauer. 1,6 m hoch — der Spieler springt 0,8 m, kommt also nicht
	# versehentlich hinein.
	group.add_child(WorldParts.solid("KaimauerWest",
		Vector3(west_width, 1.6, 1.2),
		Vector3(-(SLIP_HALF_WIDTH + west_width * 0.5), 0.8, QUAY_EDGE), _mats.concrete))
	group.add_child(WorldParts.solid("KaimauerOst",
		Vector3(west_width, 1.6, 1.2),
		Vector3(SLIP_HALF_WIDTH + west_width * 0.5, 0.8, QUAY_EDGE), _mats.concrete))

	var slip_length := SLIP_SOUTH - QUAY_EDGE
	for side: float in [-1.0, 1.0]:
		group.add_child(WorldParts.solid("SlipMauer%d" % int(side),
			Vector3(1.2, 1.6, slip_length),
			Vector3(side * (SLIP_HALF_WIDTH + 0.6), 0.8, (QUAY_EDGE + SLIP_SOUTH) * 0.5),
			_mats.concrete))
	group.add_child(WorldParts.solid("SlipKopf",
		Vector3(SLIP_HALF_WIDTH * 2.0, 1.6, 1.2),
		Vector3(0.0, 0.8, SLIP_SOUTH + 0.6), _mats.concrete))


# ---------------------------------------------------------------------------
# Kai und Containerbruecken
# ---------------------------------------------------------------------------

func _build_quay() -> void:
	var group := Node3D.new()
	group.name = "Kaianlage"
	add_child(group)

	# Die Kaistrasse: nur Farbe, keine Kollision.
	group.add_child(WorldParts.flat("Kaistrasse",
		Vector2(EAST_EDGE * 2.0, 16.0),
		Vector3(0.0, 0.02, QUAY_EDGE + 8.0), _mats.asphalt))

	for x: float in STS_CRANES:
		group.add_child(_build_sts_crane(x))


## Eine Containerbruecke: zwei Beinpaare auf dem Kai, darueber ein Ausleger,
## der weit ueber das Wasser reicht. Achtundzwanzig Meter hoch.
func _build_sts_crane(x: float) -> Node3D:
	var group := Node3D.new()
	group.name = "Bruecke%d" % int(x)

	for leg_z: float in [QUAY_EDGE + 2.0, QUAY_EDGE + 14.0]:
		for leg_x: float in [x - 7.0, x + 7.0]:
			group.add_child(WorldParts.solid("Bein",
				Vector3(1.6, STS_HEIGHT, 1.6),
				Vector3(leg_x, STS_HEIGHT * 0.5, leg_z), _mats.steel))

	group.add_child(WorldParts.solid("Portal",
		Vector3(17.0, 2.0, 14.0),
		Vector3(x, STS_HEIGHT + 1.0, QUAY_EDGE + 8.0), _mats.steel))

	# Der Ausleger reicht ueber das Schiff — das ist die Silhouette, an der man
	# den Hafen von ueberall wiedererkennt.
	group.add_child(WorldParts.solid("Ausleger",
		Vector3(3.0, 1.6, 48.0),
		Vector3(x, STS_HEIGHT + 2.8, QUAY_EDGE - 20.0), _mats.yellow))

	return group


# ---------------------------------------------------------------------------
# Schiffe
# ---------------------------------------------------------------------------

func _build_ships() -> void:
	var group := Node3D.new()
	group.name = "Schiffe"
	add_child(group)

	for ship: Dictionary in SHIPS:
		group.add_child(_build_ship(ship))

	for r: Dictionary in RAMPS:
		group.add_child(WorldParts.ramp(r.name, r.rise, r.run, r.breite,
			r.fuss, _mats.steel, r.richtung))

	# Ein drittes Schiff liegt im Slip — nicht begehbar, nur Kulisse. Es macht
	# aus dem Wasserarm einen Ort statt einer Luecke.
	group.add_child(WorldParts.solid("SchiffImSlip",
		Vector3(18.0, 8.0, 54.0), Vector3(0.0, -1.0, -26.0), _mats.rust))


func _build_ship(ship: Dictionary) -> Node3D:
	var group := Node3D.new()
	group.name = ship.name

	var size: Vector3 = ship.size
	var pos: Vector3 = ship.pos

	# Rumpf: Oberkante liegt auf DECK_Y, der Rest steckt im Wasser.
	group.add_child(WorldParts.solid("Rumpf", size,
		pos + Vector3(0.0, DECK_Y - size.y * 0.5, 0.0), _mats.dark))

	# Aufbau am Heck.
	group.add_child(WorldParts.solid("Aufbau", Vector3(16.0, 11.0, 18.0),
		pos + Vector3(size.x * 0.5 - 10.0, DECK_Y + 5.5, 0.0), _mats.concrete))

	# Deckslast: zwei Reihen Container laengs. Sie sind gleichzeitig die
	# Deckung an Deck — ohne sie waere das Schiff eine Schiessbude.
	var colours := WorldParts.container_colors()
	var count := 0
	for row: float in [-6.0, 0.0, 6.0]:
		var offset := -size.x * 0.5 + 12.0
		while offset < size.x * 0.5 - 22.0:
			var height := 1 + (count % 2)
			group.add_child(WorldParts.container_stack("Decklast%d" % count,
				pos + Vector3(offset, DECK_Y, row), height, _mats, 0.0, count))
			offset += 7.5
			count += 1

	return group


# ---------------------------------------------------------------------------
# Die beiden Terminals
# ---------------------------------------------------------------------------

func _build_terminals() -> void:
	var group := Node3D.new()
	group.name = "Terminals"
	add_child(group)

	var index := 0
	for block_x: float in BLOCK_X:
		for block_z: float in BLOCK_Z:
			group.add_child(_build_block(index, block_x, block_z))
			index += 1

	# Die Terminalstrasse zwischen den beiden Blockreihen.
	var road_z := (BLOCK_Z[0] + BLOCK_SIZE.y + BLOCK_Z[1]) * 0.5
	group.add_child(WorldParts.flat("Terminalstrasse",
		Vector2(EAST_EDGE * 2.0, BLOCK_Z[1] - (BLOCK_Z[0] + BLOCK_SIZE.y)),
		Vector3(0.0, 0.02, road_z), _mats.asphalt))


## Ein Containerblock samt Portalkran.
##
## Die Luecken im Raster sind das eigentliche Leveldesign: Sie entstehen aus
## einer festen Rechnung, nicht aus Zufall — damit die Karte nach dem Neubauen
## dieselbe bleibt und man sich Wege merken kann.
func _build_block(index: int, block_x: float, block_z: float) -> Node3D:
	var group := Node3D.new()
	group.name = "Block%d" % index

	for col in range(BLOCK_COLUMNS):
		for row in range(BLOCK_ROWS):
			# Jede siebte Stelle bleibt frei — das sind die Durchschluepfe.
			if (col + row * 2 + index) % 7 == 0:
				continue

			var height := 1 + ((col * 3 + row * 5 + index * 7) % 3)
			var pos := Vector3(
				block_x + 4.5 + float(col) * STACK_SPACING.x,
				0.0,
				block_z + 4.0 + float(row) * STACK_SPACING.y)
			group.add_child(WorldParts.container_stack(
				"Stapel_%d_%d" % [col, row], pos, height, _mats, 0.0, index + col))

	# Portalkran laengs ueber dem Block. Gelb und zwoelf Meter hoch: von unten
	# aus jeder Gasse sichtbar.
	var centre_x := block_x + BLOCK_SIZE.x * 0.5
	for leg_z: float in [block_z + 2.0, block_z + BLOCK_SIZE.y - 2.0]:
		for leg_x: float in [block_x + 1.0, block_x + BLOCK_SIZE.x - 1.0]:
			group.add_child(WorldParts.solid("Kranbein",
				Vector3(1.2, RTG_HEIGHT, 1.2),
				Vector3(leg_x, RTG_HEIGHT * 0.5, leg_z), _mats.steel))

	group.add_child(WorldParts.solid("Kranbruecke",
		Vector3(BLOCK_SIZE.x, 1.4, 3.0),
		Vector3(centre_x, RTG_HEIGHT + 0.7, block_z + BLOCK_SIZE.y * 0.5), _mats.yellow))

	return group


# ---------------------------------------------------------------------------
# Bahnhof, Lagerhallen, Tor
# ---------------------------------------------------------------------------

func _build_rail_yard() -> void:
	var group := Node3D.new()
	group.name = "Bahnhof"
	add_child(group)

	var length := RAIL_TO - RAIL_FROM
	var centre := (RAIL_FROM + RAIL_TO) * 0.5

	for z: float in RAIL_Z:
		# Zwei Schienen je Gleis, nur Optik.
		for offset: float in [-0.72, 0.72]:
			group.add_child(WorldParts.flat("Schiene",
				Vector2(length, 0.16), Vector3(centre, 0.03, z + offset), _mats.steel))

	for i in range(RAILCARS.size()):
		var car: Dictionary = RAILCARS[i]
		var size: Vector3 = car.size
		group.add_child(WorldParts.solid("Wagen%d" % i, size,
			car.pos + Vector3(0.0, size.y * 0.5 + 0.4, 0.0), _mats.rust))


func _build_warehouses() -> void:
	var group := Node3D.new()
	group.name = "Lagerhallen"
	add_child(group)

	for hall: Dictionary in WAREHOUSES:
		group.add_child(WorldParts.building(hall.name, hall.size, hall.pos,
			_mats.concrete, _mats.dark, hall.openings))

		# Regale im Inneren. Eine leere Halle waere ein Raum, in dem man
		# nirgends hinkann, sobald jemand in der Tuer steht.
		var pos: Vector3 = hall.pos
		for offset: float in [-9.0, 9.0]:
			group.add_child(WorldParts.solid("Regal",
				Vector3(3.0, 3.2, 20.0),
				pos + Vector3(offset, 1.6, 0.0), _mats.wood))


func _build_gate() -> void:
	var group := Node3D.new()
	group.name = "Tor"
	add_child(group)

	group.add_child(WorldParts.building("Wachhaus", Vector3(8.0, 3.5, 7.0),
		GATE_POS + Vector3(4.0, 0.0, -8.0), _mats.concrete, _mats.dark,
		[{side = "ost", offset = 0.0, width = 2.0}]))

	# Schranken links und rechts der Durchfahrt.
	for side: float in [-1.0, 1.0]:
		group.add_child(WorldParts.solid("Schranke%d" % int(side),
			Vector3(7.0, 0.4, 0.4),
			GATE_POS + Vector3(side * 6.0, 1.2, 0.0), _mats.yellow))

	group.add_child(WorldParts.flat("Zufahrt", Vector2(14.0, 26.0),
		GATE_POS + Vector3(0.0, 0.02, -8.0), _mats.asphalt))


# ---------------------------------------------------------------------------
# Kisten und Ausgaenge
# ---------------------------------------------------------------------------

func _build_crates() -> void:
	var group := Node3D.new()
	group.name = "Kisten"
	add_child(group)

	for entry: Dictionary in CRATES:
		var box: LootContainer = LOOT_CONTAINER.instantiate()
		box.name = entry.name
		box.position = entry.pos

		# VOR add_child setzen: `_ready()` baut das Raster aus grid_width und
		# grid_height, danach ist es zu spaet.
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
