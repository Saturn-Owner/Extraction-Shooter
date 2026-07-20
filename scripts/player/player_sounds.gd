## Schritte und Ausser-Atem-Geräusch des Spielers.
##
## ---------------------------------------------------------------------------
## SCHRITTE ÜBER DIE WEGSTRECKE, NICHT ÜBER EINEN TIMER
##
## Ein Timer müsste die Trittfrequenz selbst kennen und bei jeder Änderung
## nachgezogen werden — beim Ducken, beim Sprinten, bei Überladung, bei einem
## zerschossenen Bein. Stattdessen wird die zurückgelegte Strecke aufaddiert
## und bei jeder vollen Schrittlänge ein Geräusch gespielt.
##
## Damit stimmt die Frequenz automatisch: Wer langsamer läuft, tritt seltener
## auf, ohne dass irgendwo eine Zahl angepasst werden müsste. Und wer steht,
## macht keine Schritte — ohne Sonderfall.
##
## ---------------------------------------------------------------------------
## HINWEIS ZUM NETZWERK
##
## Das hier ist reine Darstellung und läuft beim Client. Sobald es Gegner und
## Mitspieler gibt, müssen DEREN Schritte aus ihrer Position kommen, nicht aus
## der eigenen — dann bekommt jede Figur diesen Knoten, und die Lautstärke
## entscheidet mit, wer wen hört.
class_name PlayerSounds
extends Node3D

## Wie weit man läuft, bis der nächste Fuss aufsetzt.
##
## Geduckt sind die Schritte kürzer (man schleicht), beim Sprinten länger
## (man greift aus). Die Werte sind gemessen an normalem Gehtempo 2.4 m/s:
## 0.90 m ergibt rund 2.7 Schritte pro Sekunde, was einem zügigen Gehen
## entspricht.
const STRIDE_CROUCH := 0.75
const STRIDE_WALK := 0.90
const STRIDE_SPRINT := 1.25

## Lautstärke je Haltung. Geduckt zu schleichen soll sich lohnen — spätestens,
## wenn es Gegner gibt, die einen hören können.
##
## Nach dem Hören zweimal um je 3 dB gesenkt, zusammen also 6 dB unter dem
## ersten Stand. Die Abstände untereinander bleiben jedes Mal gleich — nur
## das Ganze wandert nach unten. 3 dB sind die halbe Leistung: hörbar, aber
## kein Sprung.
const VOLUME_CROUCH_DB := -18.0
const VOLUME_WALK_DB := -10.0
const VOLUME_SPRINT_DB := -6.0

## Beim Aufkommen nach einem Sprung: ein einzelner, härterer Tritt.
const VOLUME_LANDING_DB := -4.0

## Etwas Tonhöhenstreuung, damit acht Dateien nach mehr klingen.
const PITCH_SPREAD := 0.12

## Langsamer als Gehtempo zählt nicht als Laufen. Ohne diese Grenze macht
## schon ein Abrutschen an einer Kante Geräusche.
const MIN_SPEED := 0.35

# --- Atmen ------------------------------------------------------------------

## So lange muss am Stück gesprintet werden.
const BREATHING_AFTER_SPRINT := 5.0

## ... und so weit muss die Ausdauer gefallen sein. Beides zusammen, nicht
## entweder oder — so hat Lucas es bestellt.
const BREATHING_BELOW_STAMINA := 15.0

## Ab hier hört das Keuchen wieder auf. Bewusst deutlich über der
## Einschaltschwelle: Mit nur einem Wert ginge das Atmen an der Grenze im
## Sekundentakt an und aus.
const BREATHING_STOPS_ABOVE := 35.0

const BREATHING_FADE_SECONDS := 0.8
const BREATHING_VOLUME_DB := -12.0

var player: PlayerController = null

## Aufgelaufene Wegstrecke seit dem letzten Schritt.
var _distance: float = 0.0

## Wie lange am Stück gesprintet wird.
var _sprint_seconds: float = 0.0

var _was_on_floor: bool = true
var _breathing_active: bool = false

var _steps: AudioStreamPlayer3D = null
var _breath: AudioStreamPlayer3D = null


func setup(p_player: PlayerController) -> void:
	player = p_player


func _ready() -> void:
	GameAudio.ensure_buses()

	_steps = AudioStreamPlayer3D.new()
	_steps.name = "Schritte"
	_steps.bus = GameAudio.WORLD_BUS
	# Schritte sind leise und nah. Kleine Einheitsgroesse heisst: Sie fallen
	# ueber Entfernung schnell ab, statt ueber die halbe Karte zu tragen.
	_steps.unit_size = 4.0
	_steps.max_distance = 40.0
	add_child(_steps)

	_breath = AudioStreamPlayer3D.new()
	_breath.name = "Atem"
	_breath.bus = GameAudio.WORLD_BUS
	_breath.unit_size = 3.0
	_breath.max_distance = 25.0
	_breath.volume_db = BREATHING_VOLUME_DB
	add_child(_breath)


func _physics_process(delta: float) -> void:
	if player == null:
		return

	_update_steps(delta)
	_update_breathing(delta)


# ---------------------------------------------------------------------------
# Schritte
# ---------------------------------------------------------------------------

func _update_steps(delta: float) -> void:
	var on_floor := player.is_on_floor()

	# Aufkommen nach einem Sprung: ein Tritt, und der Zaehler faengt neu an.
	if on_floor and not _was_on_floor:
		_play_step(VOLUME_LANDING_DB)
		_distance = 0.0
	_was_on_floor = on_floor

	if not on_floor:
		return

	var speed := Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	if speed < MIN_SPEED:
		# Im Stehen den Zaehler leerlaufen lassen, aber nicht ganz auf null:
		# Wer kurz stehenbleibt und weitergeht, soll nicht sofort auftreten.
		_distance = minf(_distance, _stride() * 0.5)
		return

	_distance += speed * delta
	if _distance < _stride():
		return

	_distance -= _stride()
	_play_step(_volume_db())


func _stride() -> float:
	if player.is_crouching:
		return STRIDE_CROUCH
	return STRIDE_SPRINT if player.is_sprinting else STRIDE_WALK


func _volume_db() -> float:
	if player.is_crouching:
		return VOLUME_CROUCH_DB
	return VOLUME_SPRINT_DB if player.is_sprinting else VOLUME_WALK_DB


func _play_step(volume_db: float) -> void:
	var stream := PlayerAudio.get_footstep()
	if stream == null or _steps == null:
		return
	_steps.stream = stream
	_steps.volume_db = volume_db
	_steps.pitch_scale = randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	_steps.play()


# ---------------------------------------------------------------------------
# Atmen
# ---------------------------------------------------------------------------

func _update_breathing(delta: float) -> void:
	if player.is_sprinting:
		_sprint_seconds += delta
	else:
		_sprint_seconds = 0.0

	if _breathing_active:
		if player.stamina > BREATHING_STOPS_ABOVE:
			_stop_breathing()
		return

	if _sprint_seconds >= BREATHING_AFTER_SPRINT \
			and player.stamina < BREATHING_BELOW_STAMINA:
		_start_breathing()


## Ob gerade gekeucht wird — für Anzeige und Tests.
func is_breathing() -> bool:
	return _breathing_active


func _start_breathing() -> void:
	var stream := PlayerAudio.get_breathing()
	if stream == null or _breath == null:
		return

	# Als Schleife, damit es nicht nach fuenf Sekunden aufhoert, waehrend der
	# Spieler noch keucht. Die Datei ist am Anfang und Ende ausgeblendet, die
	# Naht faellt dadurch nicht auf.
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

	_breathing_active = true
	_breath.stream = stream
	_breath.volume_db = BREATHING_VOLUME_DB
	_breath.play()


func _stop_breathing() -> void:
	_breathing_active = false
	if _breath == null or not _breath.playing:
		return

	# Ausblenden statt abschneiden: Ein Atemzug, der mitten drin abbricht,
	# klingt nach einem Fehler.
	var tween := create_tween()
	tween.tween_property(_breath, "volume_db", -40.0, BREATHING_FADE_SECONDS)
	tween.tween_callback(_breath.stop)
	tween.tween_property(_breath, "volume_db", BREATHING_VOLUME_DB, 0.0)


# ---------------------------------------------------------------------------
# Reine Rechnung — ohne Physik und ohne Ton prüfbar
# ---------------------------------------------------------------------------

## Wie viele Schritte auf einer Strecke anfallen.
##
## Ausgelagert, damit die Trittfrequenz geprüft werden kann, ohne den Spieler
## laufen zu lassen: Ein Test, der eine echte Figur über den Boden schiebt,
## prüft am Ende die Physik-Engine und nicht diese Rechnung.
static func steps_for_distance(distance: float, stride: float) -> int:
	if stride <= 0.0 or distance <= 0.0:
		return 0
	return int(distance / stride)


## Ob das Keuchen bei diesem Zustand einsetzen würde.
static func should_start_breathing(sprint_seconds: float, stamina: float) -> bool:
	return sprint_seconds >= BREATHING_AFTER_SPRINT \
		and stamina < BREATHING_BELOW_STAMINA
