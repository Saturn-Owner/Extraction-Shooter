## Die Beta-Arena — ein Paintballfeld mit Gebäude in der Mitte.
##
## Läuft in drei Rollen, und der Unterschied steckt fast nur im Spawnen:
##
##   Server:   lädt die Szene ohne Spieler. Avatare kommen über Net, sobald
##             Clients sich bereitmelden.
##   Client:   meldet sich bei Net bereit und wartet auf den EIGENEN Avatar —
##             erst mit ihm weiß er, welche Ecke der Server ihm gegeben hat,
##             und stellt dort seinen PlayerController hin.
##   Solo:     wird die Szene ohne Verbindung geöffnet (F6 im Editor), steht
##             der Spieler sofort an Ecke 0 — zum Ansehen und Bauen der Map.
class_name ArenaLevel
extends Node3D

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const MENU_SCENE := "res://scenes/main.tscn"

var _player: PlayerController

@onready var _spawns: Node3D = $Spawns


func _ready() -> void:
	Net.own_avatar_spawned.connect(_on_own_avatar_spawned)
	Net.server_disconnected.connect(_on_server_lost)
	Net.roster_changed.connect(_update_status)
	Net.register_arena(self)
	_update_status()

	if not Net.is_multiplayer():
		# Solo geöffnet: kein Server, der eine Ecke zuweist — Ecke 0 reicht,
		# um die Map zu begehen.
		_place_local_player(spawn_position(0))


func _exit_tree() -> void:
	Net.unregister_arena(self)


## Die Ecke mit diesem Index, als Weltposition. Die Marker stehen in der
## Szene — wer die Map umbaut, verschiebt die Marker, nicht den Code.
func spawn_position(index: int) -> Vector3:
	var count := _spawns.get_child_count()
	if count == 0:
		return Vector3.ZERO
	var marker := _spawns.get_child(clampi(index, 0, count - 1)) as Node3D
	return marker.global_position


func _on_own_avatar_spawned(spawn_pos: Vector3) -> void:
	_place_local_player(spawn_pos)


func _place_local_player(spawn_pos: Vector3) -> void:
	if _player != null or Net.is_server():
		return
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	# "Player" ist der verabredete Name — Konsole und Werkbank suchen danach.
	_player.name = "Player"
	add_child(_player)
	_player.global_position = spawn_pos
	# Blick zur Feldmitte, damit niemand in die eigene Eckwand schaut.
	_player.look_at(Vector3(0.0, spawn_pos.y, 0.0), Vector3.UP)

	if Net.is_multiplayer():
		var sync := PlayerNetSync.new()
		sync.name = "NetSync"
		_player.add_child(sync)


## Fällt der Server weg, hilft kein Weiterspielen — zurück ins Menü.
func _on_server_lost() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _update_status() -> void:
	var label := get_node_or_null("HUD/StatusPanel/StatusLabel") as Label
	if label == null:
		return
	if not Net.is_multiplayer():
		label.text = "Arena (solo)"
		return
	var lines: PackedStringArray = ["Spieler: %d" % Net.roster.size()]
	for peer_id in Net.roster:
		var entry: Dictionary = Net.roster[peer_id]
		var marker := "  < du" if peer_id == Net.local_peer_id() else ""
		lines.append("  %s  %d Kills%s" % [entry.name, entry.kills, marker])
	label.text = "\n".join(lines)
