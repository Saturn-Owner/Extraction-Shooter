## Haelt und bewegt das sichtbare Waffenmodell in der Hand des Spielers.
##
## ARBEITSTEILUNG — das ist der Kern dieser Datei:
##
##   weapon_view.gd  (hier)   Alles, was im Kameraraum passiert und fuer JEDE
##                            Waffe gleich funktioniert: Haltung, Zielen,
##                            Nachschwingen, Laufwackeln, Rueckstossfeder.
##
##   scripts/weapons/*.gd     Alles, was diese eine Waffe ausmacht: ihre
##                            Geometrie und ihre Mechanik. Der Schlitten einer
##                            Pistole, die Pumpe einer Flinte, der Verschluss
##                            eines Sturmgewehrs — das sind verschiedene
##                            Bewegungen, keine Varianten derselben.
##
## Diese Klasse kennt deshalb kein einziges Waffenteil beim Namen. Sie sagt
## dem Modell nur, WAS passiert ist ("ein Schuss ist gefallen", "Nachladen
## laeuft zu 40 %"), und das Modell entscheidet, wie es das zeigt.
##
## Diese Klasse enthaelt KEINE Spiellogik. Ob geschossen werden darf,
## entscheidet weapon.gd — hier wird nur dargestellt, was passiert ist. Das
## ist wichtig fuer den spaeteren Multiplayer: Die Darstellung darf nie zur
## Quelle der Wahrheit werden.
##
## AUFBAU DER KNOTEN — jede Animationsart bekommt einen eigenen Knoten,
## damit sie sich nicht gegenseitig ueberschreiben:
##
##   WeaponView
##    └ Pose       Huefte <-> Zielen, Sprint, Nachladehaltung
##       └ Sway    Nachschwingen bei Mausbewegung, Laufwackeln
##          └ Recoil   Rueckstossfeder
##             └ Viewmodel   das Modell dieser Waffe
##
## WAS HIER FEHLT: Haende und Arme. Die Waffe schwebt frei. Das ist fuer ein
## Blockout normal — sichtbare Haende brauchen Rigging und handgemachte
## Animationen, das kann Claude nicht liefern (siehe CLAUDE.md).
class_name WeaponView
extends Node3D

@export_group("Haltung")

## Wie schnell zwischen den Haltungen gewechselt wird.
## Die Haltungen selbst kommen aus dem jeweiligen Modell — eine Pistole
## liegt anders in der Hand als ein Praezisionsgewehr.
@export var pose_speed: float = 11.0

## Anteil der Nachladezeit, in dem die Waffe hoch- bzw. wieder zurueckwandert.
@export_range(0.05, 0.45) var reload_pose_blend: float = 0.16

@export_group("Zielen")

## Sekunden von der Huefte bis die Visierlinie steht.
## Wird mit der Ergonomie der Waffe verrechnet — eine handliche Waffe
## kommt schneller ans Auge.
@export var ads_base_time: float = 0.26

@export_group("Nachschwingen")

## Wie stark die Waffe der Mausbewegung hinterherhaengt (Grad).
@export var sway_amount: float = 2.6

## Wie schnell sie wieder mittig steht.
@export var sway_return_speed: float = 7.0

## Wieviel Nachschwingen beim Zielen uebrig bleibt.
@export_range(0.0, 1.0) var sway_ads_factor: float = 0.25

@export_group("Laufwackeln")

@export var bob_speed: float = 8.5
@export var bob_amount: float = 0.016
@export_range(0.0, 1.0) var bob_ads_factor: float = 0.3

@export_group("Rueckstoss (sichtbar)")

## Wie weit die Waffe pro Schuss nach hinten geht (Meter).
@export var recoil_kick_back: float = 0.055

## Wie weit die Muendung hochspringt (Grad).
@export var recoil_kick_up: float = 3.4

## Federhaerte — hoch = schnappt schneller zurueck.
@export var recoil_stiffness: float = 190.0

## Daempfung — niedrig = schwingt nach.
@export var recoil_damping: float = 17.0

var _weapon: Weapon

# Knoten der Animationsebenen
var _pose: Node3D
var _sway: Node3D
var _recoil: Node3D

## Das Modell der Waffe, die gerade in der Hand liegt.
var _viewmodel: WeaponViewmodel

# Zustand von aussen
var _aiming: bool = false
var _sprinting: bool = false
var _speed_ratio: float = 0.0

# Laufende Animationswerte
var _aim_progress: float = 0.0
var _look_delta: Vector2 = Vector2.ZERO
var _sway_offset: Vector2 = Vector2.ZERO
var _bob_time: float = 0.0

var _recoil_offset: Vector3 = Vector3.ZERO
var _recoil_velocity: Vector3 = Vector3.ZERO
var _recoil_angle: float = 0.0
var _recoil_angular_velocity: float = 0.0

# Nachladen und Ladehemmung laufen als Zeitleiste von 1.0 auf 0.0
var _sequence_time_left: float = 0.0
var _sequence_duration: float = 0.0
var _sequence_kind: StringName = &""
var _sequence_from_empty: bool = false


func _ready() -> void:
	_build_hierarchy()


func _build_hierarchy() -> void:
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)

	_sway = Node3D.new()
	_sway.name = "Sway"
	_pose.add_child(_sway)

	_recoil = Node3D.new()
	_recoil.name = "Recoil"
	_sway.add_child(_recoil)


## Waffe anmelden. Ab hier reagiert die Darstellung auf ihre Signale.
func attach_weapon(weapon: Weapon) -> void:
	if _weapon == weapon:
		return
	_weapon = weapon
	if _weapon == null:
		return

	_weapon.fired.connect(_on_fired)
	_weapon.dry_fire.connect(_on_dry_fire)
	_weapon.reload_started.connect(_on_reload_started)
	_weapon.reload_finished.connect(_on_reload_finished)
	_weapon.reload_cancelled.connect(_on_sequence_cancelled)
	_weapon.jammed.connect(_on_jammed)
	_weapon.unjam_started.connect(_on_unjam_started)
	_weapon.unjammed.connect(_on_unjammed)
	_weapon.fire_mode_changed.connect(_on_fire_mode_changed)
	_weapon.weapon_changed.connect(_on_weapon_changed)

	_on_weapon_changed(_weapon.data)


## Eine andere Waffe liegt in der Hand — Modell austauschen.
##
## Es wird bewusst komplett neu gebaut statt Teile umzuhaengen: Die Waffen
## haben unterschiedliche Teile, nicht dieselben in anderer Form.
func _on_weapon_changed(new_data: WeaponData) -> void:
	if _viewmodel != null:
		_viewmodel.queue_free()
		_viewmodel = null

	if new_data == null:
		return

	_viewmodel = new_data.create_viewmodel()
	_viewmodel.name = "Viewmodel"

	# REIHENFOLGE IST HIER WICHTIG: WeaponViewmodel._ready() baut das Modell,
	# und _ready() laeuft beim Einhaengen in den Baum. Bestueckung und Daten
	# muessen also VOR add_child() stehen — danach gesetzt kaeme beides zu
	# spaet und die Anbauteile fehlten kommentarlos.
	_viewmodel.weapon_data = new_data
	if _weapon != null and _weapon.build != null:
		_viewmodel.attachments = _weapon.build.attachments.duplicate()

	_recoil.add_child(_viewmodel)

	# Ruhelage sofort setzen, sonst schwingt die neue Waffe aus der alten
	# Haltung heran, als haette man sie geworfen.
	_pose.position = _viewmodel.hip_position
	_pose.rotation_degrees = _viewmodel.hip_rotation_degrees
	_reset_animation_state()

	# Das Muendungsfeuer gehoert an die Muendung DIESER Waffe.
	if _weapon != null:
		_weapon.set_visual_muzzle(_viewmodel.muzzle_point)
		_viewmodel.notify_fire_mode(_weapon.current_fire_mode)


func _reset_animation_state() -> void:
	_recoil_offset = Vector3.ZERO
	_recoil_velocity = Vector3.ZERO
	_recoil_angle = 0.0
	_recoil_angular_velocity = 0.0
	_sequence_time_left = 0.0
	_sequence_kind = &""
	_aim_progress = 0.0


## Das Modell, das gerade in der Hand liegt. Fuer Tests und Werkzeuge.
func get_viewmodel() -> WeaponViewmodel:
	return _viewmodel


## Wohin das Muendungsfeuer gehoert. Wandert mit dem Modell mit, damit der
## Blitz beim Zielen nicht neben der Waffe in der Luft haengt.
func get_muzzle_point() -> Node3D:
	return _viewmodel.muzzle_point if _viewmodel != null else null


## Bewegungszustand vom PlayerController. Treibt Laufwackeln und Sprinthaltung.
func set_movement(speed_ratio: float, sprinting: bool) -> void:
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	_sprinting = sprinting


## Beim Sprinten wird nicht gezielt — das entscheidet der Controller.
func set_aiming(aiming: bool) -> void:
	_aiming = aiming


## Mausbewegung fuer das Nachschwingen. Kommt aus _unhandled_input des Controllers.
func add_look_delta(delta: Vector2) -> void:
	_look_delta += delta


## 0.0 = Huefte, 1.0 = im Ziel. Der Controller zieht daran das Sichtfeld.
func get_aim_progress() -> float:
	return _aim_progress


func _process(delta: float) -> void:
	_update_sequence(delta)
	_update_aim(delta)
	_update_pose(delta)
	_update_sway(delta)
	_update_bob(delta)
	_update_recoil(delta)
	# Die beweglichen Teile bewegt die Waffe selbst.
	if _viewmodel != null:
		_viewmodel.update_mechanics(delta)


## Zielen ist eine reine Zeitinterpolation. Die Ergonomie der Waffe bestimmt
## das Tempo: eine handliche Waffe kommt spuerbar schneller ans Auge.
func _update_aim(delta: float) -> void:
	var wants_aim := _aiming and not _sprinting and _sequence_kind == &""

	var ergonomics := 50.0
	var attachment_factor := 1.0
	if _weapon != null and _weapon.data != null:
		ergonomics = float(_weapon.data.ergonomics)
		# Ein schweres Zielfernrohr kommt spuerbar spaeter ans Auge als ein
		# Rotpunkt — unabhaengig davon, wie handlich die Waffe selbst ist.
		attachment_factor = _weapon.data.ads_time_multiplier
	# Ergonomie 0 -> 1.4x langsamer, 100 -> 0.7x schneller.
	var duration := ads_base_time * (1.4 - 0.7 * (ergonomics / 100.0)) * attachment_factor
	var step := delta / maxf(0.01, duration)

	_aim_progress = clampf(_aim_progress + (step if wants_aim else -step), 0.0, 1.0)


## Wie stark die Nachladehaltung gerade wirkt.
## Faehrt am Anfang hoch und am Ende wieder herunter, damit der Uebergang
## nicht springt.
func _get_reload_pose_weight() -> float:
	if _sequence_time_left <= 0.0 or _sequence_duration <= 0.0:
		return 0.0
	var progress := 1.0 - _sequence_time_left / _sequence_duration
	var blend := clampf(reload_pose_blend, 0.05, 0.45)
	var rise := _ramp(progress, 0.0, blend)
	var fall := 1.0 - _ramp(progress, 1.0 - blend, 1.0)
	# Weiche Kurve statt Gerade — sonst wirkt das Anheben mechanisch.
	return smoothstep(0.0, 1.0, minf(rise, fall))


func _update_pose(delta: float) -> void:
	if _viewmodel == null:
		return

	var target_pos := _viewmodel.hip_position
	var target_rot := _viewmodel.hip_rotation_degrees
	var weight := clampf(pose_speed * delta, 0.0, 1.0)

	var reload_weight := _get_reload_pose_weight()
	if reload_weight > 0.0:
		# Nachladen schlaegt alles andere: Wer nachlaedt, zielt nicht.
		target_pos = target_pos.lerp(_viewmodel.reload_position, reload_weight)
		target_rot = target_rot.lerp(_viewmodel.reload_rotation_degrees, reload_weight)
		_pose.position = _pose.position.lerp(target_pos, weight)
		_pose.rotation_degrees = _pose.rotation_degrees.lerp(target_rot, weight)
		return

	if _sprinting:
		target_pos = _viewmodel.sprint_position
		target_rot = _viewmodel.sprint_rotation_degrees
	elif _aim_progress > 0.0:
		# Zielpose: Die Visierlinie muss exakt auf der Kameramitte landen.
		# Deshalb wird das Modell genau um SEINE Visierhoehe abgesenkt —
		# die ist je Waffe verschieden, eine Pistole zielt tiefer als ein
		# Gewehr mit hoher Schiene.
		var ads_pos := Vector3(0.0, -_viewmodel.sight_height, -_viewmodel.ads_distance)
		target_pos = target_pos.lerp(ads_pos, _aim_progress)
		target_rot = target_rot.lerp(Vector3.ZERO, _aim_progress)

	_pose.position = _pose.position.lerp(target_pos, weight)
	_pose.rotation_degrees = _pose.rotation_degrees.lerp(target_rot, weight)


## Die Waffe haengt der Blickrichtung hinterher. Ohne das klebt sie starr
## im Bild und wirkt wie aufgemalt.
func _update_sway(delta: float) -> void:
	var factor := lerpf(1.0, sway_ads_factor, _aim_progress)
	var target := Vector2(
		clampf(-_look_delta.x * 0.35, -sway_amount, sway_amount),
		clampf(-_look_delta.y * 0.35, -sway_amount, sway_amount)
	) * factor

	_sway_offset = _sway_offset.lerp(target, clampf(sway_return_speed * delta, 0.0, 1.0))
	_look_delta = _look_delta.lerp(Vector2.ZERO, clampf(12.0 * delta, 0.0, 1.0))

	_sway.rotation_degrees.y = _sway_offset.x
	_sway.rotation_degrees.x = -_sway_offset.y
	# Leichtes Kippen um die Laengsachse macht die Bewegung organischer.
	_sway.rotation_degrees.z = _sway_offset.x * 0.4


func _update_bob(delta: float) -> void:
	var factor := lerpf(1.0, bob_ads_factor, _aim_progress)
	if _speed_ratio <= 0.01:
		# Im Stehen sauber auslaufen lassen statt mitten im Ausschlag einfrieren.
		_sway.position = _sway.position.lerp(Vector3.ZERO, clampf(6.0 * delta, 0.0, 1.0))
		return

	_bob_time += delta * bob_speed * _speed_ratio
	var amount := bob_amount * _speed_ratio * factor
	var target := Vector3(
		sin(_bob_time) * amount,
		-absf(cos(_bob_time)) * amount * 0.8,
		0.0
	)
	_sway.position = _sway.position.lerp(target, clampf(10.0 * delta, 0.0, 1.0))


## Rueckstoss als echte Feder statt als fester Rueckweg. Dadurch schwingt
## die Waffe bei Dauerfeuer auf, statt jedes Mal sauber zurueckzukommen —
## genau das soll Dauerfeuer auf Distanz unattraktiv machen.
func _update_recoil(delta: float) -> void:
	var accel := -_recoil_offset * recoil_stiffness - _recoil_velocity * recoil_damping
	_recoil_velocity += accel * delta
	_recoil_offset += _recoil_velocity * delta

	var angular_accel := -_recoil_angle * recoil_stiffness - _recoil_angular_velocity * recoil_damping
	_recoil_angular_velocity += angular_accel * delta
	_recoil_angle += _recoil_angular_velocity * delta

	_recoil.position = _recoil_offset
	_recoil.rotation_degrees.x = _recoil_angle


## Zeitleiste fuer Nachladen und Ladehemmung.
##
## Der Fortschritt wird nur ausgerechnet und weitergereicht — was dabei
## sichtbar passiert, entscheidet das Modell der jeweiligen Waffe. Deshalb
## kann die Flinte hier Patronen einzeln nachschieben, waehrend das Gewehr
## ein Magazin wechselt, ohne dass diese Datei davon etwas wissen muss.
func _update_sequence(delta: float) -> void:
	if _sequence_time_left <= 0.0:
		return

	_sequence_time_left = maxf(0.0, _sequence_time_left - delta)
	var progress := 1.0 - _sequence_time_left / maxf(0.01, _sequence_duration)

	if _viewmodel != null:
		match _sequence_kind:
			&"reload":
				_viewmodel.notify_reload(progress, _sequence_from_empty)
			&"unjam":
				_viewmodel.notify_unjam(progress)

	if _sequence_time_left <= 0.0:
		_sequence_kind = &""
		if _viewmodel != null:
			_viewmodel.notify_sequence_ended()


## Rechnet einen Abschnitt einer Zeitleiste auf 0..1 um.
static func _ramp(value: float, from: float, to: float) -> float:
	if to <= from:
		return 1.0
	return clampf((value - from) / (to - from), 0.0, 1.0)


# --- Reaktionen auf die Waffe ---

func _on_fired(_ammo: AmmoData, rounds_left: int) -> void:
	# Rueckstoss als Impuls auf die Federgeschwindigkeit, nicht als
	# Positionssprung — sonst ruckelt es statt zu kicken.
	var strength := 1.0
	if _weapon != null and _weapon.data != null:
		# Schwere Waffen kicken staerker, gute Ergonomie daempft.
		strength = _weapon.data.recoil_vertical / 120.0
		strength *= 1.0 - float(_weapon.data.ergonomics) / 250.0
	# Beim Zielen liegt die Waffe ruhiger an der Schulter.
	strength *= lerpf(1.0, 0.72, _aim_progress)
	# Und jede Waffe springt anders — eine Pistole kippt, ein schweres
	# Praezisionsgewehr schiebt.
	if _viewmodel != null:
		strength *= _viewmodel.recoil_scale

	_recoil_velocity.z += recoil_kick_back * strength * 26.0
	_recoil_velocity.y += recoil_kick_back * strength * 5.0
	_recoil_angular_velocity += recoil_kick_up * strength * 26.0

	if _viewmodel != null:
		_viewmodel.notify_shot()
		_viewmodel.notify_action_locked(rounds_left <= 0 and not _has_chambered_round())


func _on_dry_fire() -> void:
	if _viewmodel != null:
		_viewmodel.notify_shot_dry()


func _on_reload_started(duration: float, from_empty: bool) -> void:
	_sequence_kind = &"reload"
	_sequence_from_empty = from_empty
	_sequence_duration = duration
	_sequence_time_left = duration


func _on_reload_finished(_rounds: int) -> void:
	if _viewmodel != null:
		_viewmodel.notify_action_locked(false)


func _on_sequence_cancelled() -> void:
	_sequence_time_left = 0.0
	_sequence_kind = &""
	if _viewmodel != null:
		_viewmodel.notify_sequence_ended()


func _on_jammed() -> void:
	if _viewmodel != null:
		_viewmodel.notify_action_locked(true)


func _on_unjam_started(duration: float) -> void:
	_sequence_kind = &"unjam"
	_sequence_duration = duration
	_sequence_time_left = duration


func _on_unjammed() -> void:
	if _viewmodel != null:
		_viewmodel.notify_action_locked(false)


func _on_fire_mode_changed(mode: WeaponData.FireMode) -> void:
	if _viewmodel != null:
		_viewmodel.notify_fire_mode(mode)


func _has_chambered_round() -> bool:
	return _weapon != null and _weapon.round_chambered
