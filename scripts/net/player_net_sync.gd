## Brücke vom lokalen Spieler in seinen Netzwerk-Avatar.
##
## Hängt als Kind unter dem PlayerController — aber nur im Multiplayer,
## eingehängt vom Arena-Level. Der Controller selbst weiß von alledem nichts:
## Diese Brücke LIEST jeden Physik-Frame seinen öffentlichen Zustand
## (Position, Haltung, Blick) und schreibt ihn in den eigenen Avatar, dessen
## Synchronizer ihn dann hinausfunkt.
##
## Dadurch bleibt player_controller.gd frei von Netzwerkcode — dieselbe
## Arbeitsteilung wie bei CharacterAnimation: Der Körper weiß nicht, wer ihn
## bewegt.
class_name PlayerNetSync
extends Node

var _rig: PlayerController
var _avatar: RemoteAvatar
## Die Waffe, an deren fired-Signal wir gerade hängen. Der Controller baut
## die Waffe bei jedem Wechsel neu — deshalb wird jede Runde verglichen.
var _hooked_weapon: Weapon


func _ready() -> void:
	_rig = get_parent() as PlayerController


func _physics_process(_delta: float) -> void:
	if _rig == null:
		return
	_hook_weapon()
	# Der Avatar kann später kommen als der Spieler — jede Runde nachsehen,
	# bis er da ist. Und nach einem Verbindungsabriss kann er wieder weg sein.
	if _avatar == null or not is_instance_valid(_avatar):
		_avatar = Net.avatars.get(Net.local_peer_id())
		if _avatar == null:
			return

	_avatar.sync_position = _rig.global_position
	_avatar.body_yaw = _rig.rotation.y
	_avatar.look_pitch = _rig._pitch
	_avatar.stance = (CharacterAnimation.Stance.CROUCH if _rig.is_crouching
		else CharacterAnimation.Stance.STAND)
	_avatar.sprinting = _rig.is_sprinting
	_avatar.aiming = _rig.is_aiming
	_avatar.airborne = not _rig.is_on_floor()
	_avatar.vertical_speed = _rig.velocity.y
	_avatar.move_speed = Vector2(_rig.velocity.x, _rig.velocity.z).length()
	_avatar.display_name = Net.player_name
	if _rig.weapon != null:
		_avatar.weapon_id = String(_rig.weapon.weapon_id)
	# Die Nachladebewegung der eigenen Körper-Animation mitfunken — so sehen
	# Mitspieler dieselbe Choreografie, die der Spieler selbst in der ersten
	# Person sieht.
	if _rig._body_animation != null:
		_avatar.reload_progress = _rig._body_animation.reload_progress


## Hängt sich an die aktuelle Waffe: Ihr fired-Signal wird zur Schussmeldung
## an den Server, und ihre Geschosse treffen nur noch die Welt.
func _hook_weapon() -> void:
	var current := _rig.weapon
	if current == _hooked_weapon:
		return
	if _hooked_weapon != null and is_instance_valid(_hooked_weapon):
		_hooked_weapon.fired.disconnect(_on_weapon_fired)
	_hooked_weapon = current
	if current == null:
		return
	current.fired.connect(_on_weapon_fired)
	# Die örtlichen Geschosse werden zur reinen Leuchtspur: Sie schlagen in
	# Wände ein, aber nie in Spieler — über Spieler entscheidet der Server.
	# Ebene 4 (Trefferzonen) fliegt deshalb aus der Maske.
	current.projectile_mask = 1


## Die Waffe hat örtlich gefeuert (Knall, Blitz, Rückstoß sind durch).
## Jetzt die Wahrheit anfragen: Der Server verschießt die echten Kugeln.
func _on_weapon_fired(ammo: AmmoData, _rounds_left: int) -> void:
	if _hooked_weapon == null or ammo == null:
		return
	var origin: Vector3 = _hooked_weapon.get_shot_origin()
	var direction := (_hooked_weapon.get_aim_point() - origin).normalized()
	Net.request_fire.rpc_id(1, origin, direction, String(ammo.id))
