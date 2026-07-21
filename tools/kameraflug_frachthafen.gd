## Kamerafahrt über den Frachthafen — für Video-Aufnahmen (TikTok/Devlog).
##
##   tools/kameraflug_frachthafen.tscn im Editor öffnen und mit F6 starten,
##   dann mit OBS o. ä. aufnehmen. ESC beendet.
##
## Die Route ist eine weiche Spline durch feste Wegpunkte: Süd-Totale über
## dem Spawn, tief durch eine Containergasse, hinauf über den Kai an den
## Containerbrücken vorbei, Finale hoch über dem Wasser mit Blick zurück
## auf den ganzen Hafen. Jeder Wegpunkt hat ein eigenes Blickziel, damit
## die Kamera nicht stur geradeaus starrt.
##
## Kein Spieler, kein HUD — die Szene enthält nur Welt, Himmel und Kamera.
extends Node3D

## Dauer der kompletten Fahrt in Sekunden. Fürs Video eher langsam lassen —
## beschleunigen kann man im Schnitt immer, verlangsamen sieht ruckelig aus.
@export var duration: float = 45.0

## Am Ende von vorn beginnen (praktisch beim Aufnehmen: einfach laufen
## lassen und den besten Durchlauf schneiden).
@export var loop: bool = true

## Wegpunkte der Fahrt: Position der Kamera und wohin sie dabei schaut.
## Koordinaten stammen aus dem Layout (frachthafen_layout.gd):
## Spawn (-60, 0.2, 100), Containergasse bei x=-61 (Lücke zwischen den
## Blocks -101 und -57), Kaikante z=-58, Schiffe bei z=-72.
const WAYPOINTS := [
	{pos = Vector3(-60.0, 32.0, 150.0), look = Vector3(0.0, 6.0, -40.0)},
	{pos = Vector3(-60.0, 12.0, 112.0), look = Vector3(-40.0, 2.0, 86.0)},
	{pos = Vector3(-61.0, 3.5, 52.0), look = Vector3(-61.0, 3.0, -20.0)},
	{pos = Vector3(-61.0, 3.5, 9.0), look = Vector3(-61.0, 4.0, -60.0)},
	{pos = Vector3(-61.0, 15.0, -46.0), look = Vector3(-45.0, 24.0, -58.0)},
	{pos = Vector3(-20.0, 20.0, -66.0), look = Vector3(90.0, 8.0, -72.0)},
	{pos = Vector3(55.0, 34.0, -105.0), look = Vector3(0.0, 4.0, 10.0)},
	{pos = Vector3(0.0, 46.0, -135.0), look = Vector3(-10.0, 2.0, 60.0)},
]

var _camera: Camera3D
var _elapsed := 0.0


func _ready() -> void:
	_camera = $Kamera
	_camera.current = true
	_apply(0.0)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / duration
	if t >= 1.0:
		if loop:
			_elapsed = 0.0
			t = 0.0
		else:
			t = 1.0
	_apply(t)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()


## Setzt Kameraposition und Blick für den Fahrt-Fortschritt t (0..1).
func _apply(t: float) -> void:
	# Sanft anfahren und auslaufen — ein harter Start sieht nach Fehler aus.
	var eased := smoothstep(0.0, 1.0, t)
	var count := WAYPOINTS.size()
	var span := eased * float(count - 1)
	var index := clampi(int(span), 0, count - 2)
	var local := span - float(index)

	_camera.position = _catmull(index, local, "pos")
	var look: Vector3 = _catmull(index, local, "look")
	# look_at stürzt ab, wenn Ziel und Position identisch sind — kommt bei
	# diesen Wegpunkten nicht vor, aber sicher ist sicher.
	if not _camera.position.is_equal_approx(look):
		_camera.look_at(look)


## Catmull-Rom-Spline zwischen den Wegpunkten `index` und `index+1`.
## Nimmt die Nachbarpunkte als Tangenten; an den Rändern wird der
## jeweilige Endpunkt wiederholt, damit die Kurve nicht überschwingt.
func _catmull(index: int, local: float, key: String) -> Vector3:
	var p0: Vector3 = WAYPOINTS[maxi(index - 1, 0)][key]
	var p1: Vector3 = WAYPOINTS[index][key]
	var p2: Vector3 = WAYPOINTS[index + 1][key]
	var p3: Vector3 = WAYPOINTS[mini(index + 2, WAYPOINTS.size() - 1)][key]
	var t2 := local * local
	var t3 := t2 * local
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * local \
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
