## Die Netzwerk-Figur eines Spielers — das, was ANDERE von ihm sehen.
##
## Ein Avatar existiert pro Spieler auf JEDEM Rechner, aber in zwei Gestalten:
##
##   Beim Besitzer selbst:  nur Transport. Kein Körper — der Spieler sieht
##       sich ja durch seine eigene Kamera. `PlayerNetSync` schreibt jeden
##       Frame die Pose hinein, der Synchronizer funkt sie hinaus.
##   Überall sonst (Mitspieler UND Server): ein voller Körper nach dem Muster
##       von HumanoidTarget — BlockyCharacter + CharacterAnimation +
##       CharacterWeapon(DRIVEN). Auf dem Server ist der Körper wichtiger als
##       auf jedem Client: Er trägt die Trefferzonen (Ebene 4), gegen die der
##       Server später autoritativ Treffer entscheidet.
##
## Die gefunkten Felder sind genau die Stanze-Schnittstelle, für die die
## Dummys gebaut wurden: stance, sprinting, aiming, look_pitch, airborne,
## vertical_speed, speed. Ein Dummy, der Spieler und ein Mitspieler treiben
## denselben Körper — nur die Quelle der Werte unterscheidet sich.
class_name RemoteAvatar
extends Node3D

## Wie zäh die Figur der gefunkten Position folgt. Höher = strafferes,
## aber nervöseres Nachziehen.
const FOLLOW_RATE := 14.0
## Ab dieser Distanz wird gesprungen statt geglättet (Respawn, Teleport).
const SNAP_DISTANCE := 4.0
const LABEL_HEIGHT := 0.32

# --- Gefunkte Felder (Autorität: der besitzende Spieler) -------------------
var sync_position: Vector3 = Vector3.ZERO
var body_yaw: float = 0.0
var look_pitch: float = 0.0
var stance: int = CharacterAnimation.Stance.STAND
var sprinting: bool = false
var aiming: bool = false
var airborne: bool = false
var vertical_speed: float = 0.0
var move_speed: float = 0.0
var reload_progress: float = -1.0
var weapon_id: String = "weapon_rifle_ar15"
var display_name: String = "Spieler"

var body: BlockyCharacter
var weapon: CharacterWeapon

var _animation: CharacterAnimation
var _label: Label3D
## Mit welcher Waffe der Körper gerade bestückt ist — weicht das vom
## gefunkten weapon_id ab, wird umgerüstet.
var _built_weapon_id: String = ""


func _ready() -> void:
	position = sync_position
	rotation.y = body_yaw
	if is_own():
		# WEM gefunkt wird, entscheidet die Freigabe-Liste (allow_peer), nicht
		# der Automatismus: Der Synchronizer würde sonst sofort an jeden neuen
		# Peer senden — auch an einen, dessen Arena diesen Avatar noch gar
		# nicht gebaut hat. Übers Internet kam genau so das erste Paket zu
		# früh an, der Pfad-Handschlag scheiterte einmal, und der Empfänger
		# warf danach ALLE Bewegungs-Updates stumm weg: Mitspieler standen
		# wie eingefroren. Nur der Server bekommt sofort Freigabe — seine
		# Kopie steht garantiert, er hat sie ja selbst gespawnt.
		$Synchronizer.set_visibility_for(1, true)
		return
	_build_body()


## Freigabe: Dieser Peer hat unseren Avatar gebaut und darf ab jetzt die
## laufende Pose empfangen. Wird nur auf dem Besitzer-Rechner aufgerufen —
## Sichtbarkeit entscheidet immer die Autorität.
func allow_peer(peer_id: int) -> void:
	$Synchronizer.set_visibility_for(peer_id, true)


## Gehört dieser Avatar dem Spieler an diesem Rechner?
func is_own() -> bool:
	# Nach einem Trennen lebt der Avatar noch einen Frame, aber der Peer ist
	# schon weg — get_unique_id() würde dann einen Fehler ins Log schreiben.
	if not multiplayer.has_multiplayer_peer():
		return false
	return get_multiplayer_authority() == multiplayer.get_unique_id()


## Baut den sichtbaren Körper — dasselbe Muster wie
## PlayerController._build_body() und HumanoidTarget._ready().
func _build_body() -> void:
	body = BlockyCharacter.new()
	body.name = "Koerper"
	# Ebene 4 wie alle Trefferzonen — siehe den Kommentar in
	# PlayerController._build_body().
	body.hit_layer = 4
	add_child(body)

	_animation = CharacterAnimation.new()
	_animation.name = "Bewegung"
	add_child(_animation)
	# Erst nach dem Einhängen: attach() liest die Ruhelage der Gelenke,
	# und die gibt es erst, nachdem build() gelaufen ist.
	_animation.attach(body)

	_label = Label3D.new()
	_label.name = "Namensschild"
	_label.position = Vector3(0.0, BlockyCharacter.HEIGHT + LABEL_HEIGHT, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 56
	_label.pixel_size = 0.0016
	_label.modulate = Color(0.86, 0.88, 0.92)
	_label.outline_size = 16
	_label.text = display_name
	add_child(_label)

	_rebuild_weapon()


## Rüstet den Körper mit der gefunkten Waffe aus (oder um).
func _rebuild_weapon() -> void:
	if weapon != null:
		weapon.queue_free()
		weapon = null
	_built_weapon_id = weapon_id
	if weapon_id.is_empty():
		_animation.holding_weapon = false
		return

	var mount := body.weapon_mount()
	if mount == null:
		return
	weapon = CharacterWeapon.new()
	weapon.name = "Waffe"
	weapon.weapon_id = StringName(weapon_id)
	# DRIVEN: Diese Waffe entscheidet nichts — sie zeigt nur, was der echte
	# Spieler am anderen Ende gerade tut.
	weapon.behaviour = CharacterWeapon.Behaviour.DRIVEN
	mount.add_child(weapon)

	_animation.holding_weapon = true
	if weapon.viewmodel != null:
		_animation.grip_target = weapon.viewmodel.grip_point
		_animation.support_target = weapon.viewmodel.support_point
		_animation.magwell_target = weapon.viewmodel.magwell_point
		_animation.charge_target = weapon.viewmodel.charging_handle


func _process(delta: float) -> void:
	if is_own():
		# Der Besitzer schreibt nur hinein — bewegt wird hier nichts.
		return

	# Position glätten statt hart setzen: Der Synchronizer funkt seltener als
	# der Bildschirm zeichnet, und ohne Glättung ruckelt die Figur im Takt
	# der Pakete. Bei großen Sprüngen (Respawn) wird nicht geglättet, sonst
	# rutscht die Figur sichtbar quer über die halbe Arena.
	if position.distance_to(sync_position) > SNAP_DISTANCE:
		position = sync_position
	else:
		position = position.lerp(sync_position, 1.0 - exp(-FOLLOW_RATE * delta))
	rotation.y = lerp_angle(rotation.y, body_yaw, 1.0 - exp(-FOLLOW_RATE * delta))

	if _animation == null:
		return
	_animation.stance = stance as CharacterAnimation.Stance
	_animation.is_sprinting = sprinting
	_animation.is_aiming = aiming
	_animation.is_airborne = airborne
	_animation.vertical_speed = vertical_speed
	_animation.look_pitch = look_pitch
	_animation.speed = move_speed
	_animation.reload_progress = reload_progress

	if weapon_id != _built_weapon_id:
		_rebuild_weapon()
	if _label != null and _label.text != display_name:
		_label.text = display_name
