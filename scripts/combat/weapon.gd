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
var _reload_time_left: float = 0.0
var _reload_from_empty: bool = false
var _unjam_time_left: float = 0.0

## Optionaler Punkt fuer das Muendungsfeuer aus dem sichtbaren Modell.
## Ohne Modell faellt alles auf den Muzzle-Knoten zurueck.
var _visual_muzzle: Node3D

## Schuss-Sound der aktuellen Waffe. Kommt aus einer echten Audiodatei,
## falls unter assets/audio/weapons/ eine passende liegt — sonst synthetisch.
var _shot_sound: AudioStream
var _dry_sound: AudioStream

@onready var _muzzle: Node3D = $Muzzle
@onready var _audio: AudioStreamPlayer3D = $Muzzle/AudioStreamPlayer3D


func _ready() -> void:
	ItemRegistry.ensure_loaded()
	setup(weapon_id, ammo_id)
	_dry_sound = WeaponAudio.make_dry_fire()


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
		_play(_dry_sound, 1.0)
		dry_fire.emit()
		return false

	round_chambered = false
	_cooldown = data.get_shot_interval()
	_shots_since_release += 1
	condition = maxf(0.0, condition - data.wear_per_shot)

	var speed := data.get_muzzle_velocity(loaded_ammo)
	var origin := _muzzle.global_position if _muzzle != null else global_position
	var base_dir := -(_muzzle.global_basis.z if _muzzle != null else global_basis.z)

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
	_play(_shot_sound, randf_range(0.94, 1.06))


func _play(stream: AudioStream, pitch: float) -> void:
	if _audio == null or stream == null:
		return
	_audio.stream = stream
	_audio.pitch_scale = pitch
	_audio.play()


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


## Effektive Werte neu ausrechnen, nachdem sich die Bestückung geändert hat.
##
## Meldet über weapon_changed, damit die Darstellung ihr Modell neu aufbaut —
## dasselbe Signal wie beim Waffenwechsel, weil aus Sicht der Darstellung
## genau das passiert: Es liegt eine andere Waffe in der Hand.
func rebuild() -> void:
	if base_data == null:
		return
	data = WeaponBuild.apply(base_data, build)
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
	reload_started.emit(_reload_time_left, _reload_from_empty)
	return true


## Nachladen abbrechen — etwa weil der Spieler losrennt.
## Bewusst folgenlos: Es gibt keine halb eingeschobenen Magazine.
func cancel_reload() -> void:
	if _reload_time_left <= 0.0:
		return
	_reload_time_left = 0.0
	reload_cancelled.emit()


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
	# Bewusst ohne Sound: Der synthetische Nachladeklang klang schlecht.
	# Sobald echte Aufnahmen vorliegen, hier wieder einhaengen.
	if loaded > 0:
		reloaded.emit(rounds_in_magazine)
	return loaded


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
