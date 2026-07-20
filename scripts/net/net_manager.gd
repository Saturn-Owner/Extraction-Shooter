## Netzwerk-Drehscheibe — läuft als Autoload unter /root/Net auf Server und Client.
##
## Das ist die eine Stelle, die den Transport (ENet) kennt. Alles andere redet
## über die RPCs und Signale hier. Der Pfad /root/Net ist auf jedem Rechner
## identisch — genau das braucht Godots High-Level-Multiplayer, damit ein RPC
## sein Gegenstück findet.
##
## Rollen:
##   Server (Peer 1, headless auf dem VPS): führt das Roster, weist Spawns zu,
##     entscheidet später Treffer und Tod. Der Server hat keinen eigenen Spieler.
##   Client: fragt an und wartet auf Antwort (Grundsatz 2) — er bekommt das
##     Roster nur als Abschrift zum Anzeigen.
##
## Solo-Spiel bleibt unberührt: Ohne start_server()/start_client() ist der
## Modus OFFLINE und kein bestehendes System merkt, dass es dieses Autoload gibt.
extends Node

## Ein Eintrag pro verbundenem Spieler. Nur der Server schreibt hier,
## Clients erhalten Abschriften über _sync_roster().
signal roster_changed
signal connection_succeeded
signal connection_failed
signal server_disconnected

## Der eigene Avatar ist da — das Level weiß jetzt, wo der Spieler hingehört.
signal own_avatar_spawned(spawn_position: Vector3)

const DEFAULT_PORT := 24567
const MAX_PEERS := 8
## Die Arena hat vier Spawn-Ecken; mehr Spieler teilen sich die Ecken.
const SPAWN_COUNT := 4

const AVATAR_SCENE := "res://scenes/net/remote_avatar.tscn"

enum Mode {OFFLINE, SERVER, CLIENT}

var mode: Mode = Mode.OFFLINE
## Anzeigename, den der Client nach dem Verbinden beim Server anmeldet.
var player_name: String = "Spieler"
## peer_id -> {name, spawn_index, alive, kills, weapon_id, ready}
var roster: Dictionary = {}

## Das gerade laufende Arena-Level meldet sich hier an. Solange keines
## angemeldet ist, werden Spawn-RPCs still verworfen — das passiert z. B.
## in Tests ohne Szene oder während eines Szenenwechsels.
var arena: Node = null
## peer_id -> RemoteAvatar, auf jedem Rechner gleich befüllt.
var avatars: Dictionary = {}

var _console: DevConsole


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Ohne Fenster braucht niemand eine Konsole (VPS, Headless-Tests).
	if DisplayServer.get_name() != "headless":
		_console = DevConsole.new()
		_console.name = "DevConsole"
		add_child(_console)
		_register_console_commands()


func is_server() -> bool:
	return mode == Mode.SERVER


func is_client() -> bool:
	return mode == Mode.CLIENT


func is_multiplayer() -> bool:
	return mode != Mode.OFFLINE


func local_peer_id() -> int:
	return multiplayer.get_unique_id() if is_multiplayer() else 0


## Startet den dedizierten Server. Leerer Rückgabewert heißt Erfolg,
## sonst steht drin, was schiefging.
func start_server(port: int = DEFAULT_PORT) -> String:
	if is_multiplayer():
		return "Schon verbunden — erst disconnect"
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PEERS) != OK:
		return "Server-Start auf Port %d fehlgeschlagen (Port belegt?)" % port
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	roster.clear()
	print("[Net] Server laeuft auf Port %d" % port)
	return ""


## Verbindet als Client. Ob es klappt, meldet erst connection_succeeded /
## connection_failed — diese Funktion sagt nur, ob der Versuch losging.
func start_client(ip: String, port: int = DEFAULT_PORT) -> String:
	if is_multiplayer():
		return "Schon verbunden — erst disconnect"
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		return "Verbindungsaufbau zu %s:%d fehlgeschlagen" % [ip, port]
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	print("[Net] Verbinde mit %s:%d ..." % [ip, port])
	return ""


func shutdown() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	roster.clear()
	# Die Figuren der anderen verschwinden mit der Verbindung — sonst stehen
	# Geister in der Arena, deren Synchronizer ins Leere funken.
	for peer_id in avatars:
		if is_instance_valid(avatars[peer_id]):
			avatars[peer_id].queue_free()
	avatars.clear()
	roster_changed.emit()


# --- Arena und Avatare ----------------------------------------------------

## Das Arena-Level meldet sich beim Laden an. Auf dem Client stößt das die
## Bereitmeldung an den Server an — erst DANN spawnt der Server Avatare für
## diesen Client. Wer sofort beim Verbinden spawnen würde, funkte gegen einen
## Client, dessen Szene noch gar nicht steht, und die Pakete verpufften.
func register_arena(level: Node) -> void:
	arena = level
	avatars.clear()
	# Der Server braucht keine Bereitmeldung an sich selbst — er spawnt,
	# sobald Clients sich melden.
	if is_client():
		_client_ready.rpc_id(1)


func unregister_arena(level: Node) -> void:
	if arena == level:
		arena = null
		avatars.clear()


## Client meldet: Meine Arena-Szene steht, ich kann Spawns empfangen.
@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not roster.has(peer_id) or roster[peer_id].ready:
		return
	roster[peer_id].ready = true

	# Erst bekommt der Neue alle, die schon da sind ...
	for existing_id in avatars:
		_spawn_avatar.rpc_id(peer_id, existing_id,
			avatars[existing_id].sync_position, roster[existing_id].name)
	# ... dann bekommen alle Bereiten (und der Server selbst) den Neuen.
	var spawn_position := _spawn_point_of(peer_id)
	_spawn_avatar_here(peer_id, spawn_position, roster[peer_id].name)
	for other_id in roster:
		if roster[other_id].ready:
			_spawn_avatar.rpc_id(other_id, peer_id, spawn_position, roster[peer_id].name)


## Wo der Spieler hingehört: seine Ecke, laut Arena-Level.
func _spawn_point_of(peer_id: int) -> Vector3:
	if arena != null and arena.has_method("spawn_position"):
		return arena.spawn_position(roster[peer_id].spawn_index)
	return Vector3.ZERO


@rpc("authority", "reliable")
func _spawn_avatar(peer_id: int, spawn_position: Vector3, display_name: String) -> void:
	_spawn_avatar_here(peer_id, spawn_position, display_name)


## Baut den Avatar in den lokalen Baum — auf Server wie Client identisch,
## damit die Synchronizer-Pfade übereinstimmen.
func _spawn_avatar_here(peer_id: int, spawn_position: Vector3, display_name: String) -> void:
	if arena == null or avatars.has(peer_id):
		return
	var container: Node = arena.get_node_or_null("Avatare")
	if container == null:
		return
	var avatar: RemoteAvatar = (load(AVATAR_SCENE) as PackedScene).instantiate()
	# Der Name MUSS die Peer-ID sein: Er ist der Knotenpfad, über den die
	# Synchronizer beider Seiten zueinanderfinden.
	avatar.name = str(peer_id)
	avatar.sync_position = spawn_position
	avatar.display_name = display_name
	# Autorität VOR dem Einhängen setzen, sonst startet der Synchronizer
	# mit der falschen und die erste Pose kommt vom falschen Absender.
	avatar.set_multiplayer_authority(peer_id)
	container.add_child(avatar)
	avatars[peer_id] = avatar

	if peer_id == multiplayer.get_unique_id():
		own_avatar_spawned.emit(spawn_position)


@rpc("authority", "reliable")
func _despawn_avatar(peer_id: int) -> void:
	_despawn_avatar_here(peer_id)


func _despawn_avatar_here(peer_id: int) -> void:
	if avatars.has(peer_id):
		if is_instance_valid(avatars[peer_id]):
			avatars[peer_id].queue_free()
		avatars.erase(peer_id)


# --- Server-Seite ---------------------------------------------------------

## Ein Peer ist da. Der Server legt seinen Roster-Eintrag an und weist ihm
## die am wenigsten belegte Spawn-Ecke zu.
func _on_peer_connected(peer_id: int) -> void:
	if not is_server():
		return
	roster[peer_id] = {
		name = "Spieler %d" % peer_id,
		spawn_index = _least_used_spawn(),
		alive = true,
		kills = 0,
		weapon_id = "",
		ready = false,
	}
	print("[Net] Peer %d verbunden (Spawn %d)" % [peer_id, roster[peer_id].spawn_index])
	_push_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_server():
		return
	roster.erase(peer_id)
	_despawn_avatar_here(peer_id)
	_despawn_avatar.rpc(peer_id)
	print("[Net] Peer %d getrennt" % peer_id)
	_push_roster()


## Die Ecke, an der gerade die wenigsten Spieler hängen — so verteilen sich
## auch Nachzügler gleichmäßig, wenn früh Verbundene wieder gegangen sind.
func _least_used_spawn() -> int:
	var usage := {}
	for index in SPAWN_COUNT:
		usage[index] = 0
	for entry in roster.values():
		usage[entry.spawn_index] += 1
	var best := 0
	for index in SPAWN_COUNT:
		if usage[index] < usage[best]:
			best = index
	return best


## Schickt allen Clients die aktuelle Abschrift des Rosters.
func _push_roster() -> void:
	roster_changed.emit()
	_sync_roster.rpc(roster)


## Client meldet nach dem Verbinden seinen Namen an.
@rpc("any_peer", "reliable")
func _register_client(display_name: String) -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not roster.has(peer_id):
		return
	var cleaned := display_name.strip_edges().substr(0, 24)
	if not cleaned.is_empty():
		roster[peer_id].name = cleaned
	_push_roster()


# --- Client-Seite ---------------------------------------------------------

func _on_connected_to_server() -> void:
	print("[Net] Verbunden, eigene Peer-ID: %d" % multiplayer.get_unique_id())
	_register_client.rpc_id(1, player_name)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	shutdown()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	shutdown()
	server_disconnected.emit()


## Abschrift des Server-Rosters — nur zum Anzeigen, nie zum Entscheiden.
@rpc("authority", "reliable")
func _sync_roster(server_roster: Dictionary) -> void:
	roster = server_roster
	roster_changed.emit()


# --- Konsolen-Befehle -----------------------------------------------------

func _register_console_commands() -> void:
	_console.register_command("connect",
		"Mit Server verbinden: connect <ip[:port]>", _cmd_connect)
	_console.register_command("disconnect",
		"Verbindung trennen", _cmd_disconnect)
	_console.register_command("status",
		"Verbindung und Spielerliste anzeigen", _cmd_status)
	_console.register_command("name",
		"Anzeigename setzen: name <spielername>", _cmd_name)
	_console.register_command("host",
		"Dieses Fenster wird Server: host [port]", _cmd_host)
	_console.register_command("quit",
		"Spiel beenden", _cmd_quit)


## Zerlegt "ip:port" bzw. "ip" in Adresse und Port.
func _parse_address(text: String) -> Array:
	var ip := text
	var port := DEFAULT_PORT
	if ":" in text:
		var parts := text.rsplit(":", false, 1)
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = parts[1].to_int()
	return [ip, port]


func _cmd_connect(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Benutzung: connect <ip[:port]>"
	var address := _parse_address(args[0])
	var error := start_client(address[0], address[1])
	return error if not error.is_empty() else "Verbinde mit %s:%d ..." % [address[0], address[1]]


func _cmd_disconnect(_args: PackedStringArray) -> String:
	if not is_multiplayer():
		return "Nicht verbunden"
	shutdown()
	return "Getrennt"


func _cmd_status(_args: PackedStringArray) -> String:
	var lines: PackedStringArray = []
	match mode:
		Mode.OFFLINE:
			lines.append("Offline (Solo)")
		Mode.SERVER:
			lines.append("Server, Port offen, %d Spieler" % roster.size())
		Mode.CLIENT:
			lines.append("Client, eigene Peer-ID %d" % multiplayer.get_unique_id())
	for peer_id in roster:
		var entry: Dictionary = roster[peer_id]
		lines.append("  %d  %s  Spawn %d  Kills %d" % [peer_id, entry.name, entry.spawn_index, entry.kills])
	return "\n".join(lines)


func _cmd_name(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Benutzung: name <spielername>"
	player_name = " ".join(args).substr(0, 24)
	if is_client():
		_register_client.rpc_id(1, player_name)
	return "Name: %s" % player_name


func _cmd_host(args: PackedStringArray) -> String:
	var port := DEFAULT_PORT
	if not args.is_empty() and args[0].is_valid_int():
		port = args[0].to_int()
	var error := start_server(port)
	return error if not error.is_empty() else "Server laeuft auf Port %d — dieses Fenster ist jetzt reiner Server" % port


func _cmd_quit(_args: PackedStringArray) -> String:
	get_tree().quit()
	return ""
