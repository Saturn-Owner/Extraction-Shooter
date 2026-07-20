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


func _ready() -> void:
	_rig = get_parent() as PlayerController


func _physics_process(_delta: float) -> void:
	if _rig == null:
		return
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
