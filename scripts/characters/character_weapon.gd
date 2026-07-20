## Eine Waffe in der Hand einer Figur.
##
## ---------------------------------------------------------------------------
## DASSELBE MODELL WIE IM KAMERARAUM
##
## `WeaponViewmodel` ist nicht an die Kamera gebunden — es ist Geometrie mit
## beweglichen Teilen und einer Handvoll `notify_*`-Aufrufen. Was `WeaponView`
## vor der Kamera tut, tut diese Klasse an einer Figur. Damit gibt es die
## AR-15 genau EINMAL im Projekt, und wer sie in Blender ändert, ändert sie
## für Spieler und Gegner zugleich.
##
## ---------------------------------------------------------------------------
## SIE HÄNGT AN DER HAND, NICHT AN DER FIGUR
##
## Aufgehängt wird am unteren Ende des rechten Unterarms. Dadurch folgt die
## Waffe der Armhaltung von selbst — wer die Haltung in `CharacterAnimation`
## ändert, muss hier nichts nachziehen. Die Alternative wäre, Waffe und Arme
## getrennt auszurichten, und dann läuft beides über kurz oder lang
## auseinander.
##
## ---------------------------------------------------------------------------
## KEIN ECHTES SCHIESSEN
##
## Diese Klasse erzeugt Mündungsfeuer, Knall und Bewegung — aber KEINE
## Geschosse. Sie ist Vorführung, kein Gegner. Wer wirklich schiessen soll,
## bekommt eine `Weapon`, und die entscheidet dann server-autoritativ über
## Treffer. Hier wäre das nur eine zweite, halbgare Kopie derselben Logik.
class_name CharacterWeapon
extends Node3D

## Was die Figur mit der Waffe tut.
enum Behaviour {
	HOLD,     ## nur halten
	RELOAD,   ## immer wieder nachladen
	SHOOT,    ## feuern, bis leer, dann nachladen
	DRIVEN,   ## nichts von allein — von aussen gesteuert, siehe unten
}

@export var weapon_id: StringName = &"weapon_rifle_ar15"

## Anbauteile, als IDs. Der Schalldämpfer ist `ar15_muzzle_suppressor`.
@export var attachment_ids: Array[StringName] = []

@export var behaviour: Behaviour = Behaviour.HOLD

## Wie viele Schuss, bevor nachgeladen wird.
@export var magazine_size: int = 12

## Pause zwischen zwei Schüssen, in Sekunden.
@export var shot_interval: float = 0.16

## Wie lange ein Nachladen dauert.
@export var reload_seconds: float = 2.4

## Pause nach dem Nachladen, bevor es weitergeht.
@export var rest_seconds: float = 1.2

var data: WeaponData
var viewmodel: WeaponViewmodel

var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _shot_sound: AudioStream

## Wie viele Stimmen gleichzeitig klingen dürfen. Weniger als beim Spieler:
## Diese Figur feuert nicht in Dauerfeuer, und es können mehrere im Level
## stehen.
const VOICES := 3

## Wohin die Waffe beim Nachladen wandert, relativ zur Haltung.
##
## ---------------------------------------------------------------------------
## SO WENIG WIE MÖGLICH — ABER NICHT NULL
##
## Die Waffe soll beim Wechseln auf ihrer Seite bleiben und nicht vor die
## Körpermitte wandern. Ganz ohne Verschieben geht es aber nicht: Der
## Magazinschacht liegt im Anschlag zu weit von der linken Schulter entfernt,
## der Arm ist 0,637 m lang und käme 70 mm zu kurz. Ein gestreckter Arm, der
## kurz vor dem Magazin endet, sieht schlimmer aus als gar keine Animation.
##
## 7 cm sind das gemessene Minimum, mit dem die Hand überall hinkommt (7 mm
## Rest). Die Waffe rückt damit von x = 0,18 auf 0,11 — sichtbar noch rechts
## der Mitte. Bei 16 cm stand sie fast mittig vor dem Bauch, und genau das
## sollte weg.
##
## Wer PULL_DISTANCE in CharacterAnimation vergrössert, muss hier nachlegen.
const RELOAD_SHIFT := Vector3(-0.07, 0.0, 0.04)

## Wie die Waffe dabei gedreht wird — DIESELBE HALTUNG WIE BEIM SPIELER.
##
## ---------------------------------------------------------------------------
## DIE WERTE STEHEN NICHT HIER, SONDERN AM WAFFENMODELL
##
## `WeaponViewmodel` führt bereits `hip_rotation_degrees` und
## `reload_rotation_degrees` — die Haltung, die der Spieler im Kameraraum
## sieht, wenn er nachlädt. Der Unterschied der beiden ist die Drehung, die
## das Nachladen ausmacht: Nase hoch, zur Seite gekippt, etwas eingedreht.
##
## Sie hier abzuschreiben hiesse, dass Spieler und Figur beim nächsten
## Abstimmen auseinanderlaufen. Zwei Fassungen derselben Bewegung, von denen
## eine irgendwann vergessen wird — genau das, was das Projekt bei den
## Waffenmodellen ausschliesst.
##
## Eigene Werte gibt es deshalb nur für die VERSCHIEBUNG: Die ist beim
## Spieler winzig, weil die Waffe ohnehin dicht vor der Kamera hängt. Die
## Figur muss sie dagegen wirklich an sich heranziehen, sonst kommt der
## linke Arm nicht an den Schacht.
##
## ---------------------------------------------------------------------------
## NUR DIE NEIGUNG, NICHT DAS KIPPEN ZUR SEITE
##
## Der Spieler kippt die Waffe beim Nachladen zusätzlich um 34 Grad und dreht
## sie ein. Das hat im Kameraraum einen Zweck: Es dreht den Magazinschacht ins
## Bild, damit man den Wechsel überhaupt sieht.
##
## Von aussen betrachtet gibt es diesen Zweck nicht — dort liest sich dasselbe
## Kippen, als liesse die Figur die Waffe zur Seite wegsacken. Übernommen wird
## deshalb nur die Neigung nach oben; sie ist die Bewegung, die auch ein
## Zuschauer als "Waffe hochnehmen zum Wechseln" erkennt.
func _reload_rotation() -> Vector3:
	if viewmodel == null:
		return Vector3.ZERO
	var pitch := viewmodel.reload_rotation_degrees.x - viewmodel.hip_rotation_degrees.x
	return Vector3(pitch, 0.0, 0.0)

## In diesem Abschnitt wird herangezogen bzw. wieder ausgerichtet.
const BRING_IN_END := 0.12
const PUSH_OUT_START := 0.90

## ---------------------------------------------------------------------------
## DIE WAFFE WIRD IN JEDER HALTUNG GLEICH GEFASST
##
## Hier standen einmal eigene Werte fürs Zielen (Waffe 20 cm hoch, 13 cm zur
## Mitte) und fürs Rennen (28 Grad Mündung herunter). Beide waren von mir
## erfunden — es gibt im Projekt keine Vorlage dafür, so wie es sie fürs
## Nachladen gibt.
##
## Beim Ausprobieren fiel auf, dass die so ausgestatteten Figuren die Waffe
## anders hielten als die übrigen. Mechanisch war nichts kaputt: Die Hände
## sassen auf 0 mm an ihren Griffpunkten, die Mündung wich in beiden Fällen um
## dieselben 12 Grad ab. Es sah trotzdem falsch aus — und eine erfundene
## Haltung gegen eine gewachsene zu stellen, ist genau die Sorte zweiter
## Wahrheit, die das Projekt sonst vermeidet.
##
## Geblieben ist deshalb nur das Nachladen, weil dessen Werte aus dem
## `WeaponViewmodel` stammen. Ducken und Rennen zeigen sich am KÖRPER —
## abgesenkter Rumpf, vorgebeugte Haltung, Schrittzyklus —, nicht an der
## Waffe. Wenn Zielen später sichtbar werden soll, gehören seine Werte
## genauso ans Waffenmodell wie `reload_rotation_degrees`.

var _home_position: Vector3
var _timer: float = 0.0
var _rounds: int = 0
var _reloading: bool = false
var _reload_left: float = 0.0
var _resting: float = 0.0


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	_home_position = position
	_build()


func _build() -> void:
	var base := ItemRegistry.get_item(weapon_id)
	if not (base is WeaponData):
		push_error("[CharacterWeapon] Unbekannte Waffe: %s" % weapon_id)
		return

	# Anbauteile über denselben Weg wie beim Spieler, damit ein Schalldämpfer
	# hier genauso wirkt: leiser Klang, eigene Aufnahme, weniger Rückstoss.
	var build := WeaponBuild.new()
	for id in attachment_ids:
		var part := ItemRegistry.get_item(id)
		if part is AttachmentData:
			build.set_attachment((part as AttachmentData).slot, id)
		else:
			push_warning("[CharacterWeapon] Unbekanntes Anbauteil: %s" % id)

	data = WeaponBuild.apply(base as WeaponData, build)

	viewmodel = data.create_viewmodel()
	viewmodel.name = "Modell"
	viewmodel.weapon_data = data
	viewmodel.attachments = build.attachments.duplicate()
	add_child(viewmodel)

	_shot_sound = WeaponAudio.get_gunshot(data)
	_build_voices()
	_rounds = magazine_size


func _build_voices() -> void:
	GameAudio.ensure_buses()
	for i in range(VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Stimme%d" % (i + 1)
		voice.bus = GameAudio.WORLD_BUS
		voice.unit_size = 45.0
		voice.max_distance = 900.0
		add_child(voice)
		_voices.append(voice)


func _process(delta: float) -> void:
	if viewmodel == null:
		return

	# Ohne diesen Aufruf steht der Verschluss still und das Magazin klebt
	# fest — die Mechanik läuft nicht von allein.
	viewmodel.update_mechanics(delta)
	_update_hold_pose()

	match behaviour:
		Behaviour.HOLD, Behaviour.DRIVEN:
			pass
		Behaviour.RELOAD:
			_tick_reload_loop(delta)
		Behaviour.SHOOT:
			_tick_shooting(delta)


## Zieht die Waffe zum Nachladen heran und richtet sie danach wieder aus.
func _update_hold_pose() -> void:
	var amount := 0.0
	var progress := reload_progress()
	if progress >= 0.0:
		if progress < BRING_IN_END:
			amount = smoothstep(0.0, BRING_IN_END, progress)
		elif progress < PUSH_OUT_START:
			amount = 1.0
		else:
			amount = 1.0 - smoothstep(PUSH_OUT_START, 1.0, progress)

	position = _home_position + RELOAD_SHIFT * amount
	rotation_degrees = _reload_rotation() * amount


## Lädt endlos nach, mit Pause dazwischen.
func _tick_reload_loop(delta: float) -> void:
	if _reloading:
		_advance_reload(delta)
		return
	_resting -= delta
	if _resting <= 0.0:
		_start_reload()


## Feuert, bis das Magazin leer ist, lädt nach, wartet, von vorn.
func _tick_shooting(delta: float) -> void:
	if _reloading:
		_advance_reload(delta)
		return

	if _rounds <= 0:
		_resting -= delta
		if _resting <= 0.0:
			_start_reload()
		return

	_timer -= delta
	if _timer <= 0.0:
		_fire()
		_timer = shot_interval


func _fire() -> void:
	_rounds -= 1
	viewmodel.notify_shot()

	var muzzle := viewmodel.muzzle_point
	if muzzle != null:
		var power := WeaponAudio.get_power_for_weapon(data)
		MuzzleFlash.spawn(_spawn_parent(), muzzle.global_transform, 0.6 + power)

	_play(_shot_sound, randf_range(0.94, 1.06), WeaponAudio.volume_db_for(data))

	if _rounds <= 0:
		_resting = rest_seconds


## ---------------------------------------------------------------------------
## VON AUSSEN GESTEUERT — FUER DEN SPIELER
##
## Die drei Betriebsarten darueber sind Vorfuehrungen: Sie feuern und laden
## nach eigenem Takt, damit man im Testgelaende etwas sieht. Der Spieler
## braucht das Gegenteil — sein Koerper soll zeigen, was seine ECHTE Waffe
## gerade tut.
##
## Deshalb `DRIVEN`: Die Waffe tut von allein gar nichts, und `Weapon` schiebt
## ueber diese beiden Aufrufe herein, was passiert ist. Es gibt damit weiterhin
## nur EINE Stelle, die ueber Munition und Nachladen entscheidet — die echte
## Waffe. Der Koerper stellt nur dar.
##
## Genau umgekehrt waere der Fehler: Wenn diese Klasse beim Spieler mitzaehlte,
## haetten wir zwei Wahrheiten ueber dasselbe Magazin.
func drive_shot() -> void:
	if viewmodel == null:
		return
	viewmodel.notify_shot()
	var muzzle := viewmodel.muzzle_point
	if muzzle != null:
		var power := WeaponAudio.get_power_for_weapon(data)
		MuzzleFlash.spawn(_spawn_parent(), muzzle.global_transform, 0.6 + power)


func drive_dry_shot() -> void:
	if viewmodel != null:
		viewmodel.notify_shot_dry()


## Nachladen von aussen: Fortschritt 0 bis 1, negativ heisst fertig.
func drive_reload(progress: float, from_empty: bool, chamber_only: bool) -> void:
	if viewmodel == null:
		return
	if progress < 0.0:
		_reloading = false
		_reload_left = 0.0
		viewmodel.notify_sequence_ended()
		return
	_reloading = true
	# reload_progress() rechnet aus _reload_left zurueck — hier andersherum
	# gefuellt, damit Haltung und Hand denselben Wert sehen wie sonst auch.
	_reload_left = (1.0 - clampf(progress, 0.0, 1.0)) * maxf(0.01, reload_seconds)
	viewmodel.notify_reload(progress, from_empty, chamber_only)


func _start_reload() -> void:
	_reloading = true
	_reload_left = reload_seconds
	viewmodel.notify_reload(0.0, true)


func _advance_reload(delta: float) -> void:
	_reload_left -= delta
	var progress := 1.0 - clampf(_reload_left / maxf(0.01, reload_seconds), 0.0, 1.0)
	viewmodel.notify_reload(progress, true)

	if _reload_left > 0.0:
		return

	_reloading = false
	_rounds = magazine_size
	_resting = rest_seconds
	viewmodel.notify_sequence_ended()


## Wohin das Mündungsfeuer gehängt wird.
##
## NICHT EINFACH `get_tree().current_scene`: Im Testlauf über `--script` gibt
## es keine Hauptszene, der Wert ist dann null, und `add_child` darauf wirft
## einen Fehler. Aufgefallen ist das nicht in den Prüfungen — die blieben grün
## —, sondern weil `run_tests.ps1` auch Skriptfehler als Fehlschlag wertet.
## Genau dafür hat Lucas diese Prüfung eingebaut.
##
## Dieselbe Überlegung steht schon in `Weapon.get_spawn_parent()`.
func _spawn_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return self
	if tree.current_scene != null:
		return tree.current_scene
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != tree.root:
		node = node.get_parent()
	return node


func _play(stream: AudioStream, pitch: float, volume_db: float) -> void:
	if stream == null or _voices.is_empty():
		return
	var voice: AudioStreamPlayer3D = null
	for candidate in _voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		voice = _voices[_next_voice]
		_next_voice = (_next_voice + 1) % _voices.size()

	voice.stream = stream
	voice.pitch_scale = pitch
	voice.volume_db = volume_db
	voice.play()


## Wie weit das Nachladen ist, 0 bis 1. Negativ, wenn gerade nicht
## nachgeladen wird.
##
## Die Figur greift danach: Ihre Stützhand folgt dem Magazin, statt eine
## eigene Zeitleiste zu haben, die man synchron halten müsste.
func reload_progress() -> float:
	if not _reloading:
		return -1.0
	return 1.0 - clampf(_reload_left / maxf(0.01, reload_seconds), 0.0, 1.0)


## Setzt Magazin und Ablauf zurück.
func reset() -> void:
	_rounds = magazine_size
	_reloading = false
	_reload_left = 0.0
	_resting = 0.0
	_timer = 0.0
	if viewmodel != null:
		viewmodel.notify_sequence_ended()
