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

## Womit jeder in die Arena startet. Mehr gibt es an der Werkbank.
const STARTING_KIT := [
	{id = &"ammo_556x45_m855a1", count = 90},
	{id = &"ammo_9x19_fmj", count = 51},
]

var _player: PlayerController
var _death_label: Label

@onready var _spawns: Node3D = $Spawns


func _ready() -> void:
	Net.own_avatar_spawned.connect(_on_own_avatar_spawned)
	Net.server_disconnected.connect(_on_server_lost)
	Net.roster_changed.connect(_update_status)
	Net.local_player_hit.connect(_update_status)
	Net.local_player_eliminated.connect(_on_local_eliminated)
	Net.local_player_respawned.connect(_on_local_respawned)
	Net.register_arena(self)
	_build_death_label()
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
	_give_starting_kit()

	if Net.is_multiplayer():
		var sync := PlayerNetSync.new()
		sync.name = "NetSync"
		_player.add_child(sync)


## Gewehr, Pistole und Munition — als echte Ausrüstungs-Stacks, damit die
## Werkbank sie kennt und der Waffenwechsel funktioniert. Die voreingestellte
## Waffe aus player.tscn fliegt vorher raus, sonst zählt sie doppelt.
func _give_starting_kit() -> void:
	_player.empty_hands()
	if not _player.assign_weapon(ItemStack.create(&"weapon_rifle_ar15", 1)):
		push_error("[Arena] Kein Waffenplatz fuer das Gewehr frei")
	if not _player.assign_weapon(ItemStack.create(&"weapon_pistol_g17", 1)):
		push_error("[Arena] Kein Waffenplatz fuer die Pistole frei")
	for entry in STARTING_KIT:
		if not _player.inventory.add(entry.id, entry.count):
			push_error("[Arena] Startmunition passt nicht ins Inventar: %s" % entry.id)
	_player.select_weapon_slot(ItemData.EquipSlot.PRIMARY)


## Fällt der Server weg, hilft kein Weiterspielen — zurück ins Menü.
func _on_server_lost() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Die große Mitteilung in der Bildmitte für Tod und Respawn.
func _build_death_label() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	_death_label = Label.new()
	_death_label.name = "Todesmeldung"
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 30)
	_death_label.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
	_death_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_death_label.add_theme_constant_override("outline_size", 8)
	_death_label.visible = false
	hud.add_child(_death_label)


func _on_local_eliminated(killer_name: String) -> void:
	if _death_label != null:
		_death_label.text = "GEFALLEN — %s hat dich erwischt\nRespawn in %d Sekunden ..." \
			% [killer_name, int(Net.RESPAWN_SECONDS)]
		_death_label.visible = true
	_update_status()


func _on_local_respawned() -> void:
	if _death_label != null:
		_death_label.visible = false
	_update_status()


func _update_status() -> void:
	var label := get_node_or_null("HUD/StatusPanel/StatusLabel") as Label
	if label == null:
		return
	var lines: PackedStringArray = []
	if _player != null and _player.health != null:
		lines.append("Zustand: %.0f TP" % _player.health.get_total_hp())
	if not Net.is_multiplayer():
		lines.append("Arena (solo)")
		label.text = "\n".join(lines)
		return
	lines.append("Spieler: %d" % Net.roster.size())
	for peer_id in Net.roster:
		var entry: Dictionary = Net.roster[peer_id]
		var marker := "  < du" if peer_id == Net.local_peer_id() else ""
		var state := "" if entry.alive else "  (tot)"
		lines.append("  %s  %d Kills%s%s" % [entry.name, entry.kills, state, marker])
	label.text = "\n".join(lines)
