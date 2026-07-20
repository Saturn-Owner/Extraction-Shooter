## Die Waffe in der Hand des Spielers.
##
## Verbindet WeaponData (wie geschossen wird) mit AmmoData (was der Treffer
## anrichtet). Dieselbe Waffe fuehlt sich mit anderer Munition deutlich
## anders an — das ist beabsichtigt.
##
## NETZWERK: Der Client darf hier abdruecken, aber die Trefferentscheidung
## faellt spaeter auf dem Server. Diese Klasse erzeugt nur die Anfrage
## "ich schiesse in diese Richtung" plus die sichtbare Rueckmeldung.
class_name Weapon
extends Node3D

signal fired(ammo: AmmoData, rounds_left: int)
signal reloaded(rounds: int)
signal dry_fire()
signal recoil_kick(vertical: float, horizontal: float)

signal reload_started(duration: float, from_empty: bool)
signal reload_finished(rounds: int)
signal reload_cancelled()
signal jammed()
signal unjam_started(duration: float)
signal unjammed()
signal fire_mode_changed(mode: WeaponData.FireMode)

## Eine andere Waffe liegt in der Hand. Die Darstellung muss ihr Modell
## austauschen — jede Waffe hat ihr eigenes.
signal weapon_changed(new_data: WeaponData)

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

## Wie stark Verschleiss die Ladehemmungen hochtreibt.
##
## Bewusst hier und nicht in den Waffendaten: Das ist eine Spielregel, die
## fuer alle Waffen gleich gilt. Was sich pro Waffe unterscheidet, sind
## base_jam_chance und wear_per_shot — die stehen in der .tres.
## Bei Zustand 0 ist die Hemmungswahrscheinlichkeit 20-mal so hoch wie neu.
const WEAR_JAM_MULTIPLIER := 20.0

@export var weapon_id: StringName = &"weapon_rifle_ar15"
@export var ammo_id: StringName = &"ammo_556x45_m855a1"

## Auf welchen Ebenen Geschosse einschlagen (1 = Welt, 2 = Spieler, 4 = Gegner).
@export_flags_3d_physics var projectile_mask: int = 1 | 2 | 4

## Die unveränderte Vorlage aus der Registry. NIEMALS hineinschreiben —
## sie wird von allen Exemplaren dieser Waffe geteilt.
var base_data: WeaponData

## Die effektiven Werte DIESES Exemplars, also Vorlage plus Anbauteile.
##
## ACHTUNG: `data` ist eine eigenständige Kopie und NICHT dasselbe Objekt wie
## `ItemRegistry.get_item(weapon_id)`. Wer die beiden vergleicht, bekommt
## immer "ungleich". Diese Trennung ist der ganze Grund, warum eine bestückte
## Waffe nicht alle anderen Waffen desselben Typs mitverändert.
var data: WeaponData

## Was an dieser Waffe montiert ist. Nach Änderungen `rebuild()` aufrufen.
var build: WeaponBuild = WeaponBuild.new()

var loaded_ammo: AmmoData
var rounds_in_magazine: int = 0
var current_fire_mode: WeaponData.FireMode = WeaponData.FireMode.SINGLE

## Patrone im Lauf. Getrennt vom Magazin, weil genau daraus der Unterschied
## zwischen taktischem Nachladen (30+1) und leergeschossen (30) entsteht.
var round_chambered: bool = false

## Zustand der Waffe von 100 (neu) bis 0 (Schrott). Sinkt mit jedem Schuss
## und treibt die Ladehemmungen hoch. Spaeter Arbeit fuer die Werkstatt.
var condition: float = 100.0

var is_jammed: bool = false

## Ob der Spieler gerade zielt. Reduziert die Streuung.
var aiming: bool = false

## Woher Munition beim Nachladen kommt. Wird vom PlayerController gesetzt:
##   weapon.ammo_supplier = func(id, count): return inventory.take_ammo(id, count)
##
## Ueber eine Callable statt einer direkten Inventar-Referenz, damit die Waffe
## nichts vom Inventar weiss und einzeln testbar bleibt — und damit spaeter
## der Server dieselbe Stelle bedienen kann.
var ammo_supplier: Callable = Callable()

var _cooldown: float = 0.0
var _burst_remaining: int = 0
var _shots_since_release: int = 0

## Ob seit dem letzten Loslassen schon ins Leere geklickt wurde.
var _dry_fired_since_release: bool = false
var _reload_time_left: float = 0.0
var _reload_from_empty: bool = false

## Nachladegeraeusche und ihre Stelle im Ablauf (0 = Anfang, 1 = fertig).
##
## Der Verschluss kommt nur bei leergeschossener Waffe vor: Steckt noch eine
## Patrone im Lauf, bleibt er vorn und es gibt nichts vorzulassen.
const RELOAD_CUES := [
	{at = 0.08, sound = "nachladen_magazin_raus", only_empty = false},
	{at = 0.52, sound = "nachladen_magazin_rein", only_empty = false},
	{at = 0.88, sound = "nachladen_verschluss", only_empty = true},
]

var _reload_total: float = 0.0
var _next_cue: int = 0
var _unjam_time_left: float = 0.0

## Optionaler Punkt fuer das Muendungsfeuer aus dem sichtbaren Modell.
## Ohne Modell faellt alles auf den Muzzle-Knoten zurueck.
var _visual_muzzle: Node3D

## Die Kamera. Sie entscheidet, worauf gezielt wird — siehe get_aim_point().
var _aim_source: Node3D

## Wie weit der Zielstrahl reicht, wenn er auf nichts trifft.
## Grosszuegig: Auf dem Testgelaende stehen Ziele auf 300 m.
const AIM_DISTANCE := 2000.0

## Schuss-Sound der aktuellen Waffe. Kommt aus einer echten Audiodatei,
## falls unter assets/audio/weapons/ eine passende liegt — sonst synthetisch.
var _shot_sound: AudioStream
var _dry_sound: AudioStream

@onready var _muzzle: Node3D = $Muzzle
@onready var _audio: AudioStreamPlayer3D = $Muzzle/AudioStreamPlayer3D

## Wie viele Geraeusche gleichzeitig klingen duerfen.
##
## MIT EINER EINZIGEN STIMME KLANG DAUERFEUER WIE KLICKEN. Jeder Schuss setzte
## den Stream neu und startete ihn von vorn — bei 750 Schuss pro Minute liegen
## 80 ms zwischen den Schuessen, die Aufnahme ist 2,6 Sekunden lang. Zu hoeren
## waren also immer nur die ersten 80 ms: der Anschlag, nie der Knall.
##
## Sechs reichen: Bei 900 Schuss pro Minute und einem Ausklang von 2,6 s
## ueberlappen sich zwar mehr, aber die aeltesten sind dann so leise, dass ihr
## Abbruch nicht auffaellt.
const AUDIO_VOICES := 6

var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	setup(weapon_id, ammo_id)
	_dry_sound = WeaponAudio.make_dry_fire()
	_build_voices()


## Legt die zusaetzlichen Stimmen als Geschwister der Szenen-Stimme an.
##
## Bewusst im Code und nicht in player.tscn: Szenen lassen sich bei Konflikten
## nicht mergen, und die Zahl der Stimmen ist eine Frage des Verhaltens, keine
## der Szene.
func _build_voices() -> void:
	if _audio == null:
		return

	# Alles Diegetische haengt am Welt-Bus, damit der Muendungsknall es
	# daempfen kann. Vor dem Duplizieren setzen, sonst muesste es sechsmal
	# passieren.
	GameAudio.ensure_buses()
	_audio.bus = GameAudio.WORLD_BUS

	_voices.append(_audio)
	for i in range(AUDIO_VOICES - 1):
		var voice := _audio.duplicate() as AudioStreamPlayer3D
		voice.name = "Stimme%d" % (i + 2)
		_audio.get_parent().add_child(voice)
		_voices.append(voice)


## Waffe und Munition setzen. Laedt gleich ein volles Magazin.
func setup(p_weapon_id: StringName, p_ammo_id: StringName) -> bool:
	var w := ItemRegistry.get_item(p_weapon_id)
	var a := ItemRegistry.get_item(p_ammo_id)

	if not (w is WeaponData):
		push_error("[Weapon] Unbekannte Waffe: %s" % p_weapon_id)
		return false
	if not (a is AmmoData):
		push_error("[Weapon] Unbekannte Munition: %s" % p_ammo_id)
		return false

	base_data = w as WeaponData
	data = WeaponBuild.apply(base_data, build)
	if not data.accepts_ammo(a as AmmoData):
		push_error("[Weapon] %s passt nicht in %s" % [a.display_name, data.display_name])
		return false

	loaded_ammo = a as AmmoData
	weapon_id = p_weapon_id
	ammo_id = p_ammo_id
	# Waffe kommt leer — Munition muss aus dem Inventar geladen werden.
	rounds_in_magazine = 0
	round_chambered = false
	is_jammed = false
	_reload_time_left = 0.0
	_unjam_time_left = 0.0
	current_fire_mode = data.fire_modes[0] if not data.fire_modes.is_empty() else WeaponData.FireMode.SINGLE

	# Die Darstellung muss ihr Modell austauschen — jede Waffe hat ihr eigenes.
	weapon_changed.emit(data)
	fire_mode_changed.emit(current_fire_mode)

	# Sucht zuerst eine echte Audiodatei für diese Waffe, sonst Synthese.
	_shot_sound = WeaponAudio.get_gunshot(data)
	return true


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

	_advance_reload(delta)
	_advance_unjam(delta)

	# Feuerstoss weiterschiessen, ohne dass der Spieler nachdrueckt.
	if _burst_remaining > 0 and _cooldown <= 0.0:
		_burst_remaining -= 1
		_shoot()


## Naechsten Feuermodus waehlen.
func cycle_fire_mode() -> WeaponData.FireMode:
	if data == null or data.fire_modes.size() <= 1:
		return current_fire_mode
	var index := data.fire_modes.find(current_fire_mode)
	current_fire_mode = data.fire_modes[(index + 1) % data.fire_modes.size()]
	fire_mode_changed.emit(current_fire_mode)
	return current_fire_mode


## Abzug gedrueckt halten. Ruft je nach Modus einen oder mehrere Schuesse aus.
func try_fire(trigger_held: bool, trigger_just_pressed: bool) -> bool:
	if data == null or _cooldown > 0.0 or _burst_remaining > 0:
		return false

	# Waehrend Nachladen oder Ladehemmung geht gar nichts.
	# Der Klick soll trotzdem hoerbar ins Leere gehen, damit der Spieler
	# merkt, dass die Waffe nicht bereit ist.
	if is_busy():
		if trigger_just_pressed:
			_play(_dry_sound, 1.0)
			dry_fire.emit()
		return false

	match current_fire_mode:
		WeaponData.FireMode.AUTO:
			if not trigger_held:
				return false
		WeaponData.FireMode.BURST:
			if not trigger_just_pressed:
				return false
			_burst_remaining = data.burst_count - 1
		_:
			if not trigger_just_pressed:
				return false

	return _shoot()


func _shoot() -> bool:
	# Geschossen wird aus dem Lauf, nicht aus dem Magazin. Ein volles Magazin
	# ohne Patrone im Lauf feuert nicht — der Verschluss muss erst vor.
	if not round_chambered:
		_burst_remaining = 0
		# EINMAL pro Abzug, nicht jeden Frame. Vorher wurde _cooldown in
		# diesem Zweig nicht gesetzt, also lief try_fire() im Dauerfeuer bei
		# jedem Bild erneut durch — das ergab ein Klicken im Bildtakt statt
		# des einen Klacks, den eine leergeschossene Waffe macht.
		if not _dry_fired_since_release:
			_dry_fired_since_release = true
			_play(_dry_sound, 1.0)
			dry_fire.emit()
		_cooldown = data.get_shot_interval()
		return false

	round_chambered = false
	_cooldown = data.get_shot_interval()
	_shots_since_release += 1
	condition = maxf(0.0, condition - data.wear_per_shot)

	var speed := data.get_muzzle_velocity(loaded_ammo)
	var origin := get_shot_origin()
	var base_dir := (get_aim_point() - origin).normalized()

	# Schrot verschiesst mehrere Projektile mit Streuung.
	for i in range(maxi(1, loaded_ammo.pellet_count)):
		var dir := _apply_spread(base_dir, i)
		_spawn_projectile(origin, dir, speed)

	_play_shot_feedback()
	_emit_recoil()
	_cycle_action()
	fired.emit(loaded_ammo, rounds_in_magazine)
	return true


## Der Verschluss laedt nach: naechste Patrone aus dem Magazin in den Lauf.
## Hier entscheidet sich auch, ob die Waffe klemmt.
func _cycle_action() -> void:
	if _roll_jam():
		is_jammed = true
		_burst_remaining = 0
		jammed.emit()
		return

	if rounds_in_magazine > 0:
		rounds_in_magazine -= 1
		round_chambered = true


## Wahrscheinlichkeit einer Ladehemmung, abhaengig vom Zustand der Waffe.
## Eine neue Waffe klemmt praktisch nie, eine heruntergerittene staendig.
func _roll_jam() -> bool:
	if data == null or data.base_jam_chance <= 0.0:
		return false
	var wear := 1.0 - condition / 100.0
	var chance := data.base_jam_chance * (1.0 + wear * WEAR_JAM_MULTIPLIER)
	return randf() < chance


## Mündungsfeuer und Knall. Beides muss exakt im selben Frame kommen wie
## das Geschoss, sonst fühlt sich der Schuss "abgekoppelt" an.
func _play_shot_feedback() -> void:
	# Der Blitz gehoert an die Muendung des sichtbaren Modells, damit er beim
	# Zielen mitwandert. Geschosse starten weiter am festen Muzzle-Knoten —
	# die Flugbahn darf nicht davon abhaengen, wo das Modell gerade wackelt.
	var flash_from := _visual_muzzle if _visual_muzzle != null else _muzzle
	if flash_from != null:
		var power := WeaponAudio.get_power_for_weapon(data)
		MuzzleFlash.spawn(get_spawn_parent(), flash_from.global_transform, 0.6 + power)

	# Tonhöhe leicht variieren, damit Dauerfeuer nicht wie eine Maschine klingt.
	#
	# Die Lautstaerke bekommt NUR der Schuss. Ein Schalldaempfer macht das
	# Magazin nicht leiser — er sitzt vorn am Lauf und hat mit dem Schacht
	# nichts zu tun. Die Nachladegeraeusche laufen deshalb weiter auf 0 dB.
	_play(_shot_sound, randf_range(0.94, 1.06), WeaponAudio.volume_db_for(data))


## Spielt ein Geraeusch, ohne das vorherige abzuschneiden.
##
## Gesucht wird zuerst eine freie Stimme. Ist keine frei, wird reihum die
## naechste genommen — dann klingt der aelteste Schuss ab, und das ist der,
## den man am wenigsten vermisst.
func _play(stream: AudioStream, pitch: float, volume_db: float = 0.0) -> void:
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
	# Die Stimmen werden reihum wiederverwendet — ohne ausdrueckliches Setzen
	# behielte eine Stimme die Lautstaerke des vorigen Geraeuschs. Nach einem
	# gedaempften Schuss klaenge dann das naechste Nachladen zu leise.
	voice.volume_db = volume_db
	voice.play()


## Streuung aus Waffenpraezision (MOA) und Munitionsstreuung (Schrot).
func _apply_spread(direction: Vector3, pellet_index: int) -> Vector3:
	# 1 MOA entspricht rund 1/60 Grad.
	var spread_deg := data.accuracy_moa / 60.0
	# Ueber Kimme und Korn gezielt wird die Waffe deutlich praeziser.
	# Schrotstreuung bleibt davon unberuehrt — die kommt aus dem Lauf,
	# nicht aus der Haltung.
	if aiming:
		spread_deg *= data.ads_spread_multiplier
	if loaded_ammo.pellet_count > 1 and pellet_index > 0:
		spread_deg += loaded_ammo.pellet_spread_degrees

	if spread_deg <= 0.0:
		return direction

	var angle := deg_to_rad(spread_deg)
	# Zufaellige Abweichung in einem Kegel um die Zielrichtung.
	var perpendicular := direction.cross(Vector3.UP)
	if perpendicular.length_squared() < 0.001:
		perpendicular = direction.cross(Vector3.RIGHT)
	perpendicular = perpendicular.normalized()

	var roll := randf() * TAU
	var axis := perpendicular.rotated(direction.normalized(), roll)
	return direction.rotated(axis, randf() * angle).normalized()


func _spawn_projectile(origin: Vector3, direction: Vector3, speed: float) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	# An den Baum haengen, nicht an die Waffe — sonst fliegt das Geschoss
	# mit, wenn sich der Spieler dreht.
	get_spawn_parent().add_child(projectile)
	projectile.launch(loaded_ammo, origin, direction, speed, owner, projectile_mask)


## Wohin Geschosse und Effekte gehaengt werden.
##
## current_scene ist null, sobald die Szene nicht als Hauptszene laeuft —
## etwa waehrend eines Szenenwechsels, im Test oder wenn spaeter mehrere
## Level gleichzeitig geladen sind. Deshalb mit Rueckfallebene statt blind
## darauf zu vertrauen.
func get_spawn_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return self
	if tree.current_scene != null:
		return tree.current_scene
	# Oberster Vorfahr unterhalb der Baumwurzel.
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != tree.root:
		node = node.get_parent()
	return node


## Rueckstoss. Waechst innerhalb einer Salve an, damit Dauerfeuer auf
## Distanz sinnlos wird und kurze Feuerstoesse belohnt werden.
func _emit_recoil() -> void:
	var ergonomics_factor := 1.0 - (float(data.ergonomics) / 200.0)
	var ramp := 1.0 + minf(float(_shots_since_release) * 0.06, 0.8)

	var vertical := data.recoil_vertical * ergonomics_factor * ramp * 0.01
	var horizontal := data.recoil_horizontal * ergonomics_factor * ramp * 0.01
	horizontal *= (1.0 if randf() < 0.5 else -1.0)

	recoil_kick.emit(vertical, horizontal)


## Abzug losgelassen — Rueckstossaufbau zuruecksetzen.
func release_trigger() -> void:
	_shots_since_release = 0
	_dry_fired_since_release = false


## Effektive Werte neu ausrechnen, nachdem sich die Bestückung geändert hat.
##
## Meldet über weapon_changed, damit die Darstellung ihr Modell neu aufbaut —
## dasselbe Signal wie beim Waffenwechsel, weil aus Sicht der Darstellung
## genau das passiert: Es liegt eine andere Waffe in der Hand.
func rebuild() -> void:
	if base_data == null:
		return
	data = WeaponBuild.apply(base_data, build)
	# DEN KLANG MITZIEHEN. Ohne diese Zeile schraubt man an der Werkbank
	# einen Schalldaempfer an, sieht ihn am Lauf — und hoert weiter den
	# ungedaempften Knall, weil _shot_sound aus setup() stehenbleibt.
	_shot_sound = WeaponAudio.get_gunshot(data)
	weapon_changed.emit(data)


## Waffe ohne passende Munition in die Hand nehmen.
##
## Eine gueltige Notlage: Man findet ein Gewehr, hat aber kein Kaliber dafuer.
## Braucht einen eigenen Weg, weil setup() eine gueltige Munitionssorte
## verlangt — und weil sonst das Modell nicht gewechselt wuerde und man mit
## der alten Waffe in der Hand dastuende.
func equip_without_ammo(new_data: WeaponData) -> void:
	if new_data == null:
		return
	base_data = new_data
	data = WeaponBuild.apply(base_data, build)
	_shot_sound = WeaponAudio.get_gunshot(data)
	weapon_id = new_data.id
	loaded_ammo = null
	rounds_in_magazine = 0
	round_chambered = false
	is_jammed = false
	_reload_time_left = 0.0
	_unjam_time_left = 0.0
	current_fire_mode = data.fire_modes[0] if not data.fire_modes.is_empty() else WeaponData.FireMode.SINGLE

	weapon_changed.emit(data)
	fire_mode_changed.emit(current_fire_mode)


## Muendungspunkt des sichtbaren Modells anmelden.
func set_visual_muzzle(node: Node3D) -> void:
	_visual_muzzle = node


## Die Kamera anmelden. Sie bestimmt, WOHIN geschossen wird.
func set_aim_source(node: Node3D) -> void:
	_aim_source = node


## Woher die Kugel losfliegt: aus der Muendung des sichtbaren Modells.
##
## Nur fuer die Optik — die Flugrichtung kommt von woanders, siehe unten.
func get_shot_origin() -> Vector3:
	if _visual_muzzle != null:
		return _visual_muzzle.global_position
	if _muzzle != null:
		return _muzzle.global_position
	return global_position


## Der Punkt, auf den die Kugel zulaeuft: das, worauf der Spieler zielt.
##
## ---------------------------------------------------------------------------
## WARUM NICHT EINFACH GERADEAUS AUS DEM LAUF
##
## Vorher startete die Kugel an einem festen Punkt neben der Kamera und flog
## PARALLEL zur Blickrichtung. Damit ging jeder Schuss um den Versatz der
## Muendung daneben — rund 18 cm nach rechts und 12 cm nach unten, und zwar
## auf jede Entfernung gleich. Auf 30 m ist das ein Meter Vorbeischuss.
##
## Richtig ist: Gezielt wird mit der KAMERA, geschossen aus der MUENDUNG. Die
## Kamera schickt einen Strahl auf das, was in der Bildmitte steht, und die
## Kugel laeuft von der Muendung auf genau diesen Punkt zu. Dadurch kommt sie
## sichtbar aus dem Lauf UND trifft dort, wo der Spieler hinsieht.
func get_aim_point() -> Vector3:
	if _aim_source == null:
		# Ohne Kamera bleibt nur die Laufrichtung. Gilt fuer Gegner und Tests.
		var fallback := _visual_muzzle if _visual_muzzle != null else _muzzle
		if fallback == null:
			return global_position - global_basis.z * AIM_DISTANCE
		return fallback.global_position - fallback.global_basis.z * AIM_DISTANCE

	var from := _aim_source.global_position
	var direction := -_aim_source.global_basis.z
	var to := from + direction * AIM_DISTANCE

	var world := get_world_3d()
	if world == null:
		return to

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = projectile_mask
	query.collide_with_areas = false
	if owner is CollisionObject3D:
		query.exclude = [(owner as CollisionObject3D).get_rid()]

	var hit := world.direct_space_state.intersect_ray(query)
	# Trifft der Strahl nichts, wird auf einen fernen Punkt gezielt. Das ist
	# richtig so: Die Kugel soll dann geradeaus in die Ferne fliegen.
	return hit.get("position", to)


## Ob die Waffe gerade beschaeftigt ist und nicht schiessen kann.
func is_busy() -> bool:
	return is_jammed or _reload_time_left > 0.0 or _unjam_time_left > 0.0


func is_reloading() -> bool:
	return _reload_time_left > 0.0


## Patronen insgesamt: Magazin plus die im Lauf.
func get_total_rounds() -> int:
	return rounds_in_magazine + (1 if round_chambered else 0)


## Nachladen anstossen. Die Munition wird erst am ENDE entnommen —
## wer mittendrin abbricht, verliert nichts.
func request_reload() -> bool:
	if data == null or is_busy():
		return false
	# Volles Magazin mit Patrone im Lauf: nichts zu tun.
	if get_missing_rounds() <= 0 and round_chambered:
		return false

	_reload_from_empty = not round_chambered
	_reload_time_left = data.get_reload_duration(_reload_from_empty)
	_reload_total = _reload_time_left
	_next_cue = 0
	reload_started.emit(_reload_time_left, _reload_from_empty)
	return true


## Nachladen abbrechen — etwa weil der Spieler losrennt.
## Bewusst folgenlos: Es gibt keine halb eingeschobenen Magazine.
func cancel_reload() -> void:
	if _reload_time_left <= 0.0:
		return
	_reload_time_left = 0.0
	_next_cue = RELOAD_CUES.size()
	reload_cancelled.emit()


## Spielt die Nachladegeraeusche an ihrer Stelle im Ablauf.
##
## Die Geraeusche haengen am FORTSCHRITT, nicht an festen Sekunden: Eine Waffe
## mit langsamerem Nachladen soll ihre Klicks entsprechend gedehnt hoeren
## lassen, statt am Anfang alles abzufeuern und dann still zu sein.
##
## Fehlt eine Datei, bleibt es an dieser Stelle einfach still — ein fehlendes
## Geraeusch darf das Nachladen nicht aufhalten.
func _play_reload_cues() -> void:
	if _reload_total <= 0.0:
		return

	var progress := 1.0 - _reload_time_left / _reload_total
	while _next_cue < RELOAD_CUES.size():
		var cue: Dictionary = RELOAD_CUES[_next_cue]
		if progress < float(cue.at):
			break
		_next_cue += 1
		if bool(cue.only_empty) and not _reload_from_empty:
			continue
		_play(WeaponAudio.get_sound(base_data, String(cue.sound)), randf_range(0.97, 1.03))


## Ladehemmung beheben.
func request_unjam() -> bool:
	if not is_jammed or _unjam_time_left > 0.0:
		return false
	_unjam_time_left = data.jam_clear_time
	unjam_started.emit(_unjam_time_left)
	return true


func _advance_reload(delta: float) -> void:
	if _reload_time_left <= 0.0:
		return
	_reload_time_left = maxf(0.0, _reload_time_left - delta)
	_play_reload_cues()
	if _reload_time_left > 0.0:
		return

	var needed := get_missing_rounds()
	var supplied := 0
	if ammo_supplier.is_valid():
		supplied = int(ammo_supplier.call(ammo_id, needed))
	rounds_in_magazine += clampi(supplied, 0, needed)

	# Verschluss vorlassen: eine Patrone wandert aus dem Magazin in den Lauf.
	# Genau hier entsteht der Unterschied 30+1 gegen 30.
	_chamber_if_possible()
	_shots_since_release = 0

	reload_finished.emit(rounds_in_magazine)
	reloaded.emit(rounds_in_magazine)


func _advance_unjam(delta: float) -> void:
	if _unjam_time_left <= 0.0:
		return
	_unjam_time_left = maxf(0.0, _unjam_time_left - delta)
	if _unjam_time_left > 0.0:
		return

	is_jammed = false
	# Die klemmende Patrone ist weg — es wird eine frische zugefuehrt.
	_chamber_if_possible()
	unjammed.emit()


func _chamber_if_possible() -> void:
	if round_chambered or rounds_in_magazine <= 0:
		return
	rounds_in_magazine -= 1
	round_chambered = true


## Wie viele Patronen noch ins Magazin passen.
func get_missing_rounds() -> int:
	if data == null:
		return 0
	return maxi(0, data.magazine_size - rounds_in_magazine)


## Laedt eine bestimmte Anzahl Patronen nach.
##
## Die Waffe erfindet keine Munition — wer sie aufruft, muss sie vorher
## irgendwo entnommen haben. Dadurch bleibt diese Klasse unabhaengig vom
## Inventar und damit einzeln testbar, und der Server kann spaeter dieselbe
## Pruefung vornehmen.
func load_rounds(count: int) -> int:
	if data == null or count <= 0:
		return 0
	var loaded := mini(count, get_missing_rounds())
	rounds_in_magazine += loaded
	_chamber_if_possible()
	_shots_since_release = 0
	if loaded > 0:
		_play_reload()
		reloaded.emit(rounds_in_magazine)
	return loaded


## Stellt einen gemerkten Magazinzustand wieder her — Magazin UND Lauf.
##
## ---------------------------------------------------------------------------
## WARUM NICHT load_rounds()
##
## load_rounds() ist zum NACHLADEN da und tut deshalb zweierlei zuviel: Es
## kammert nach (`_chamber_if_possible`) und es spielt das Nachladegeraeusch.
##
## Beides ist beim Waffenwechsel falsch. Das Nachkammern nimmt eine Patrone
## aus dem Magazin und legt sie in den Lauf — bei einer Waffe, die schon eine
## im Lauf hatte, kommt dadurch jedes Mal eine Patrone zu wenig im Magazin an.
## Nach zehn Wechseln fehlen zehn Schuss, ohne dass jemand geschossen haette.
## Und das Geraeusch gehoert zum Nachladen, nicht zum Griff an die Schulter.
##
## Diese Funktion setzt den Zustand deshalb schlicht, ohne Nebenwirkung.
func restore_magazine(rounds: int, chambered: bool) -> void:
	if data == null:
		return
	rounds_in_magazine = clampi(rounds, 0, data.magazine_size)
	round_chambered = chambered
	_shots_since_release = 0


## Spielt die Nachladegeraeusche als Folge ab: Magazin raus, Magazin rein,
## durchladen — mit den Pausen dazwischen, die eine echte Bewegung braucht.
##
## Bewusst NICHT eine einzige lange Datei: Die Abstaende sollen spaeter zur
## Nachladedauer der jeweiligen Waffe passen, und eine leere MP5 laedt
## anders nach als ein Scharfschuetzengewehr.
##
## Fehlt eine Datei, passiert nichts. Stille ist besser als ein falscher
## Klang — der synthetische Versuch klang schlecht und war deshalb lange
## ganz abgeschaltet.
func _play_reload() -> void:
	var steps := WeaponAudio.get_reload_sequence()
	if steps.is_empty():
		return

	for step in steps:
		var stream: AudioStream = step.stream
		var delay: float = step.delay
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		# Waehrend der Pause kann die Waffe weggelegt worden sein.
		if not is_inside_tree():
			return
		_play(stream, randf_range(0.97, 1.03))


## Fuellt das Magazin ohne Munitionsverbrauch.
## Nur fuer Tests und den Schiessstand im Bunker gedacht.
func fill_magazine() -> void:
	if data == null:
		return
	rounds_in_magazine = data.magazine_size
	round_chambered = true
	is_jammed = false
	_shots_since_release = 0
	reloaded.emit(rounds_in_magazine)


func get_status_text() -> String:
	if data == null or loaded_ammo == null:
		return "keine Waffe"
	var mode_names := {
		WeaponData.FireMode.SINGLE: "Einzel",
		WeaponData.FireMode.BURST: "Stoss",
		WeaponData.FireMode.AUTO: "Auto",
	}
	# Die Patrone im Lauf wird als "+1" ausgewiesen, damit man den Unterschied
	# zwischen taktischem Nachladen und leergeschossen wirklich sieht.
	var chamber := "+1" if round_chambered else "  "
	var state := ""
	if is_jammed:
		state = "  LADEHEMMUNG (R)"
	elif _unjam_time_left > 0.0:
		state = "  behebt Hemmung %.1fs" % _unjam_time_left
	elif _reload_time_left > 0.0:
		state = "  laedt %.1fs" % _reload_time_left

	return "%s  [%s]  %d%s/%d  %s  Zustand %.0f%%%s" % [
		data.display_name,
		mode_names.get(current_fire_mode, "?"),
		rounds_in_magazine,
		chamber,
		data.magazine_size,
		loaded_ammo.display_name,
		condition,
		state,
	]
