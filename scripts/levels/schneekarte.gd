## Der Karten-Generator: eine grosse, verschneite Karte mit Gelaende,
## begehbaren Haeusern und Baeumen — zufaellig verteilt, aber reproduzierbar.
##
## Genau wie schiessstand.tscn/frachthafen_layout.gd KEIN Spielinhalt im
## eigentlichen Sinn, sondern eine Werkbank: Hier geht es darum, ob das
## Gelaende (TerrainGenerator), die Haeuser (WorldHouse) und die Baeume
## zusammen eine begehbare, glaubwuerdige Flaeche ergeben.
##
## ---------------------------------------------------------------------------
## WARUM EIN SEED UND KEINE FESTEN KOORDINATEN
##
## frachthafen_layout.gd zaehlt jede Kiste einzeln auf — das passt zu einer
## handgebauten Szene, bei der jede Stelle eine Entscheidung ist. Hier ist das
## Gegenteil gewollt: eine GROSSE Karte, bei der niemand jedes Haus einzeln
## platzieren will. `MAP_SEED` macht das Ergebnis trotzdem reproduzierbar —
## zwei Entwickler mit demselben Seed sehen dieselbe Karte, ohne dass
## irgendwo eine Liste von Koordinaten im Repo stehen muesste.
extends Node3D

## Grundflaeche der Karte in Metern.
const MAP_SIZE := Vector2(300.0, 300.0)

## Punkte je Achse fuer das Hoehenfeld — 129 ergibt ein Dreieck alle 2,3 m,
## fein genug fuer sanfte Huegel, grob genug, um nicht zu ruckeln.
const TERRAIN_RESOLUTION := 129

## Hoehenunterschied der Karte in Metern. Siehe TerrainGenerator.generate()
## fuer die Begruendung, warum das zurueckhaltend bleibt.
const TERRAIN_AMPLITUDE := 4.0

const MAP_SEED := 20260722

## Wie viele Haeuser insgesamt stehen — mehr als CATALOGUE.size(), weil
## Haeuser mehrfach vorkommen duerfen (sonst waere eine 300x300-Karte mit nur
## sechs Gebaeuden sehr leer).
const HOUSE_COUNT := 14

## Mindestabstand zwischen zwei Haus-Mittelpunkten, damit sich ihre
## Grundflaechen nicht ueberlappen. Grosszuegig ueber der groessten
## Haus-Diagonale (house_home: 11 x 22 m, Diagonale ~24 m) gewaehlt, damit
## auch nach der zufaelligen Drehung noch Luft bleibt.
const HOUSE_MIN_DISTANCE := 26.0

## Wie viele EINZELNE Pflanzen verteilt werden (siehe WorldTree — jede fuer
## sich, nicht immer derselbe Dreier-Klumpen). Deutlich mehr als bei Klumpen
## sinnvoll waeren: eine einzelne Pflanze braucht viel weniger Platz als drei
## zusammen, und ein Wald aus vier verschiedenen Arten an unabhaengigen
## Stellen sieht erst ab einer gewissen Dichte nach Wald aus.
const TREE_COUNT := 260

## Mindestabstand zwischen zwei Pflanzen — eng genug fuer einen dichten
## Wald, weit genug, dass sich Kronen nicht sichtbar durchdringen.
const TREE_MIN_DISTANCE := 3.0

## Wie nah eine Pflanze an ein Haus heranruecken darf — nicht direkt an der
## Wand, sonst wirken Baum und Haus wie ineinander gesteckt.
const TREE_HOUSE_CLEARANCE := 4.0

@onready var _player: PlayerController = $Player
@onready var _label: Label = $HUD/DebugPanel/DebugLabel

var _rng := RandomNumberGenerator.new()
var _heights: PackedFloat32Array
var _house_positions: Array[Vector2] = []


func _ready() -> void:
	_rng.seed = MAP_SEED
	_heights = TerrainGenerator.heights_grid(TERRAIN_RESOLUTION, MAP_SEED, TERRAIN_AMPLITUDE)

	add_child(TerrainGenerator.generate(MAP_SIZE, TERRAIN_RESOLUTION, MAP_SEED,
		TERRAIN_AMPLITUDE, WorldParts.snow_material()))

	_place_houses()
	_place_trees()
	_place_player()


## Hoehe des Gelaendes an einer Kartenposition (x, z lokal, Kartenmitte = 0).
func _ground_height(local_xz: Vector2) -> float:
	return TerrainGenerator.sample(_heights, TERRAIN_RESOLUTION, MAP_SIZE, local_xz)


## Verteilt HOUSE_COUNT Haeuser per Zurueckweisungs-Stichprobe: eine zufaellige
## Stelle vorschlagen, verwerfen und neu versuchen, wenn sie einem schon
## gesetzten Haus zu nahe kommt. Einfacher als echtes Poisson-Disc-Sampling,
## reicht aber fuer ein paar Dutzend Haeuser vollkommen.
func _place_houses() -> void:
	var container := Node3D.new()
	container.name = "Haeuser"
	add_child(container)

	var placed := 0
	var attempts := 0
	# Obergrenze gegen Endlosschleifen: Wird die Karte zu voll (oder
	# HOUSE_COUNT zu hoch fuer HOUSE_MIN_DISTANCE), bricht die Platzierung
	# lieber mit weniger Haeusern ab, als ewig zu suchen.
	var max_attempts := HOUSE_COUNT * 50

	while placed < HOUSE_COUNT and attempts < max_attempts:
		attempts += 1
		var candidate := Vector2(
			_rng.randf_range(-MAP_SIZE.x * 0.5 + 20.0, MAP_SIZE.x * 0.5 - 20.0),
			_rng.randf_range(-MAP_SIZE.y * 0.5 + 20.0, MAP_SIZE.y * 0.5 - 20.0))

		if _too_close(candidate, HOUSE_MIN_DISTANCE):
			continue

		var entry: Dictionary = WorldHouse.CATALOGUE[_rng.randi() % WorldHouse.CATALOGUE.size()]
		var rotation_deg := _rng.randf_range(0.0, 360.0)
		var height := _ground_height(candidate)
		var pos := Vector3(candidate.x, height, candidate.y)

		container.add_child(WorldHouse.place("Haus%02d" % placed,
			WorldHouse.HOUSES_DIR + String(entry.file), pos, rotation_deg))
		_house_positions.append(candidate)
		placed += 1

	print("[Schneekarte] %d von %d Haeusern platziert (%d Versuche)"
		% [placed, HOUSE_COUNT, attempts])


func _too_close(candidate: Vector2, min_distance: float) -> bool:
	for existing in _house_positions:
		if existing.distance_to(candidate) < min_distance:
			return true
	return false


## Einzelne Pflanzen (siehe WorldTree) — dieselbe Zurueckweisungs-Stichprobe
## wie bei den Haeusern, nur mit kleinerem Mindestabstand zueinander UND
## einem Sicherheitsabstand zu jedem Haus.
##
## Rein dekorativ (keine Kollision) — duenne, sich kreuzende Blattebenen
## ohne Innenraum liessen den Spieler im Spiel darin haengen bleiben (siehe
## WorldHouse.place()), bis es eine eigene, einfache Stamm-Kollision gibt.
func _place_trees() -> void:
	var container := Node3D.new()
	container.name = "Baeume"
	add_child(container)

	var positions: Array[Vector2] = []
	var placed := 0
	var attempts := 0
	var max_attempts := TREE_COUNT * 50

	while placed < TREE_COUNT and attempts < max_attempts:
		attempts += 1
		var candidate := Vector2(
			_rng.randf_range(-MAP_SIZE.x * 0.5 + 5.0, MAP_SIZE.x * 0.5 - 5.0),
			_rng.randf_range(-MAP_SIZE.y * 0.5 + 5.0, MAP_SIZE.y * 0.5 - 5.0))

		var too_close_to_tree := false
		for existing in positions:
			if existing.distance_to(candidate) < TREE_MIN_DISTANCE:
				too_close_to_tree = true
				break
		if too_close_to_tree or _too_close(candidate, HOUSE_MIN_DISTANCE * 0.5 + TREE_HOUSE_CLEARANCE):
			continue

		var plant_name: String = WorldTree.PLANT_NAMES[_rng.randi() % WorldTree.PLANT_NAMES.size()]
		var rotation_deg := _rng.randf_range(0.0, 360.0)
		var scale := _rng.randf_range(0.85, 1.2)
		var height := _ground_height(candidate)
		var pos := Vector3(candidate.x, height, candidate.y)

		container.add_child(WorldTree.place("Pflanze%03d" % placed, plant_name, pos,
			rotation_deg, scale))
		positions.append(candidate)
		placed += 1

	print("[Schneekarte] %d von %d Pflanzen platziert (%d Versuche)"
		% [placed, TREE_COUNT, attempts])


## Der Spieler steht in der Kartenmitte auf dem tatsaechlichen Gelaende, nicht
## auf einer angenommenen Hoehe null — sonst startet er je nach Huegel in der
## Luft oder im Boden.
func _place_player() -> void:
	var height := _ground_height(Vector2.ZERO)
	_player.global_position = Vector3(0.0, height + 1.0, 0.0)


func _process(_delta: float) -> void:
	_label.text = "Schneekarte — Seed %d\n%d Haeuser, %d Pflanzen" % [
		MAP_SEED, _house_positions.size(), TREE_COUNT]
