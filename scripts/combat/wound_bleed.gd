## Ein Blutstreifen an einer Wunde — erscheint am Einschlagpunkt und waechst
## nach unten, als liefe Blut die Wunde herunter. Erreicht er den unteren
## Rand des Koerperteils, an dem er haengt, loesen sich von dort einzelne
## Tropfen und fallen frei zu Boden (siehe BloodDrop) — der Streifen selbst
## haengt nie in der Luft, wo keine Koerperflaeche mehr ist.
##
## Haengt als Kind direkt am getroffenen Mesh (siehe BlockyCharacter._spawn_
## wound()) und folgt darum automatisch jeder Bewegung dieses Koerperteils —
## Gehen, Zielen, Ducken, spaeter auch das Ragdoll, alles ohne eigenen Code
## hier. "Unten" ist die lokale Y-Achse des Elternteils, nicht Weltgravitation:
## Bei einem schraeg gehaltenen Arm laeuft der Streifen also mit dem Arm mit,
## nicht senkrecht zum Boden. Fuer diese Figur (kein Skelett, meist aufrechte
## Koerperteile) ist das die Naeherung, die ohne inverse Kinematik geht.
class_name WoundBleed
extends Node3D

## Schwer blutend (siehe Ballistics.HitResult.caused_heavy_bleeding) laeuft
## dicker, schneller und tropft haeufiger als eine leichte Blutung.
@export var heavy: bool = false

## Wie weit der Streifen als starre Linie waechst, bevor er den unteren Rand
## des Koerperteils erreicht — von aussen gesetzt (siehe BlockyCharacter.
## _edge_length()), NICHT bis zum Boden, siehe dortiger Kommentar.
@export var target_length: float = 0.16

## Welche Trefferzonen-Ebene ein abgeloester Tropfen zusaetzlich zur Welt
## als Landeflaeche behandeln soll — siehe BlockyCharacter.hit_layer. Ohne
## das faellt ein Tropfen durch den eigenen Koerper hindurch bis zum Boden,
## weil Trefferzonen nicht auf der Welt-Ebene liegen.
@export var body_hit_layer: int = 4

## War 0.022/0.038 — insgesamt doller bluten, siehe Klassenkopf-Aenderungen.
const WIDTH_LIGHT := 0.032
const WIDTH_HEAVY := 0.052

## Wachstum als GESCHWINDIGKEIT (m/s), nicht als feste Dauer — sonst waechst
## ein kurzer Streifen (Bein) genauso lang wie ein langer (Brust) am selben
## Koerperteil, nur eben schneller statt laenger zu brauchen. War 0.09/0.16.
const GROWTH_SPEED_LIGHT := 0.15
const GROWTH_SPEED_HEAVY := 0.26

## Wie oft (Sekunden, mit Zufallsstreuung) sich am unteren Ende ein Tropfen
## ablöst, sobald der Streifen sein Ziel erreicht hat. War 1.1/0.5 — kuerzer,
## damit insgesamt mehr und haeufiger tropft.
const DRIP_INTERVAL_LIGHT := 0.6
const DRIP_INTERVAL_HEAVY := 0.25

## Nach wie vielen Tropfen die Wunde aufhoert zu tropfen — sonst tropft eine
## laengst nicht mehr frische Wunde beliebig lange weiter. Eine Spanne statt
## einer festen Zahl: manche Treffer bluten kaum aus, andere laenger, auch
## bei gleicher Schwere. War 2-5/5-11 — insgesamt angehoben.
const MIN_DRIPS_LIGHT := 4
const MAX_DRIPS_LIGHT := 9
const MIN_DRIPS_HEAVY := 9
const MAX_DRIPS_HEAVY := 18

## Dunkles, fast schwarzes Rot statt reinem Rot — frisches Blut auf einer
## dunklen Wunde wirkt eher dunkel als knallig, siehe auch die Wundgriff-Farbe
## in RagdollRig.WOUND_CLUTCH_COLOR.
const COLOR := Color(0.42, 0.03, 0.03)

## Niedrige Rauheit statt der frueheren 0.35 — Blut ist fluessig und
## reflektiert Licht, keine matte Oberflaeche wie Stoff oder trockene Farbe.
## Clearcoat obendrauf simuliert die duenne, glatte Oberflaechenspannung
## einer Fluessigkeit (derselbe Trick wie nasse Haut/Lack in vielen Spielen) —
## ohne eigene Normal-Map, die Claude laut CLAUDE.md nicht anfertigen kann.
const ROUGHNESS := 0.08
const CLEARCOAT_ROUGHNESS := 0.03

## Gemeinsames Material fuer alle Blut-Meshes (Streifen UND Tropfen, siehe
## BloodDrop._ready()) — eine Stelle fuer "wie glaenzt Blut", statt dieselben
## Werte doppelt zu pflegen.
static func liquid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.roughness = ROUGHNESS
	material.clearcoat_enabled = true
	material.clearcoat = 1.0
	material.clearcoat_roughness = CLEARCOAT_ROUGHNESS
	return material


var _mesh: MeshInstance3D
var _box: BoxMesh
var _length: float = 0.0
var _speed: float
var _drip_interval: float
var _drip_timer: float = 0.0
var _drips_left: int = 0


func _ready() -> void:
	var width := WIDTH_HEAVY if heavy else WIDTH_LIGHT
	_speed = GROWTH_SPEED_HEAVY if heavy else GROWTH_SPEED_LIGHT
	_drip_interval = DRIP_INTERVAL_HEAVY if heavy else DRIP_INTERVAL_LIGHT
	_drip_timer = _drip_interval
	_drips_left = randi_range(MIN_DRIPS_HEAVY, MAX_DRIPS_HEAVY) if heavy \
		else randi_range(MIN_DRIPS_LIGHT, MAX_DRIPS_LIGHT)

	_box = BoxMesh.new()
	_box.size = Vector3(width, 0.001, width * 0.6)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = _box
	_mesh.material_override = liquid_material()
	add_child(_mesh)


func _process(delta: float) -> void:
	if _length < target_length:
		_length = minf(target_length, _length + _speed * delta)
		_box.size.y = maxf(0.001, _length)
		# Der obere Rand bleibt an der Wunde, das Wachstum geht nach unten —
		# derselbe Trick wie bei den Koerperteilen selbst, siehe
		# BlockyCharacter._add_segment().
		_mesh.position.y = -_length * 0.5
		return

	if _drips_left <= 0:
		set_process(false)
		return

	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = _drip_interval * randf_range(0.7, 1.3)
		_drips_left -= 1
		_release_drop()


## Loest einen Tropfen an der aktuellen Streifenspitze.
##
## HAENGT AM SELBEN MESH WIE DIESER STREIFEN, nicht an der Szene — sonst
## bleibt ein geloester Tropfen exakt an der Weltstelle haengen, an der die
## Figur beim Ablösen gerade stand, und "schwebt" sichtbar in der Luft, sobald
## sich der Koerper (laufend, oder als fallendes Ragdoll) von dort wegbewegt.
## Als Kind bewegt und dreht er sich automatisch MIT dem Koerperteil mit;
## BloodDrop faellt trotzdem weiter nach unten, weil es in _process() seine
## global_position (WELTRAUM) jedes Bild um ein Stueck Richtung Boden
## verschiebt — der Effekt ist ein Tropfen, der mit dem Koerper mitwandert
## und dabei gleichzeitig langsam an ihm herunterrutscht.
func _release_drop() -> void:
	var parent := get_parent()
	if parent == null:
		return

	var drop := BloodDrop.new()
	drop.collision_mask = 1 | body_hit_layer
	parent.add_child(drop)
	drop.global_position = to_global(Vector3(0.0, -_length, 0.0))
