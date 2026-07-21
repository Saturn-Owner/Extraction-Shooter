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
## Die eigene Gesundheit wurde vom Server aktualisiert (nur Anzeige).
signal local_player_hit
## Der eigene Spieler ist gefallen bzw. wieder da.
signal local_player_eliminated(killer_name: String)
signal local_player_respawned

const DEFAULT_PORT := 24567
const MAX_PEERS := 8
## Die Arena hat vier Spawn-Ecken; mehr Spieler teilen sich die Ecken.
const SPAWN_COUNT := 4

const AVATAR_SCENE := "res://scenes/net/remote_avatar.tscn"

## Wartezeit zwischen Tod und Respawn an der eigenen Ecke.
const RESPAWN_SECONDS := 5.0
## Kadenz-Prüfung mit Luft: Netz-Zittern staucht Pakete zusammen, und wer
## ehrlich Dauerfeuer schießt, soll nicht alle paar Schuss verschluckt sehen.
const FIRE_INTERVAL_TOLERANCE := 0.75
## Wie weit der gemeldete Abschusspunkt vom Avatar entfernt sein darf.
## Großzügig, weil die gefunkte Position dem echten Spieler hinterherläuft.
const MAX_ORIGIN_DRIFT := 3.5

## Muss auf Client und Server gleich sein — wird bei JEDER Änderung an
## RPCs, Synchronizer-Feldern oder Spielregeln von Hand hochgezählt.
## Ein Client mit alter Version bekommt eine klare Absage statt eines
## Spiels voller Geistereffekte.
const PROTOCOL_VERSION := 2

enum Mode {OFFLINE, SERVER, CLIENT}

var mode: Mode = Mode.OFFLINE
## Anzeigename, den der Client nach dem Verbinden beim Server anmeldet.
var player_name: String = "Spieler"
## Sitzungs-Token aus dem Launcher (Steam-Anmeldung). Leer = Gast.
var session_token: String = ""
## Die Steam-Anmeldeprüfung — nur auf dem Server gesetzt (net_bootstrap).
var auth: AuthService = null
## peer_id -> {name, spawn_index, alive, kills, weapon_id, ready, steam_id}
var roster: Dictionary = {}
## Warum der Server uns zuletzt abgewiesen hat (fürs Menü).
var rejection_reason: String = ""

## Das gerade laufende Arena-Level meldet sich hier an. Solange keines
## angemeldet ist, werden Spawn-RPCs still verworfen — das passiert z. B.
## in Tests ohne Szene oder während eines Szenenwechsels.
var arena: Node = null
## peer_id -> RemoteAvatar, auf jedem Rechner gleich befüllt.
var avatars: Dictionary = {}

var _console: DevConsole
## peer_id -> Zeitstempel des letzten angenommenen Schusses (nur Server).
var _last_shot_ms: Dictionary = {}


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
	elif is_client():
		# Handschlag gegen den Einfrier-Fehler: Erst wenn WIR den Avatar
		# gebaut haben, darf sein Besitzer anfangen, uns seine Pose zu
		# funken. Der Server reicht die Meldung an ihn weiter.
		_avatar_ready_for.rpc_id(1, peer_id)


## Ein Client meldet: Ich habe den Avatar von owner_peer gebaut.
## Der Server sagt dem Besitzer, dass er diesen Zuschauer freigeben darf.
@rpc("any_peer", "reliable")
func _avatar_ready_for(owner_peer: int) -> void:
	if not is_server():
		return
	var viewer := multiplayer.get_remote_sender_id()
	if roster.has(owner_peer):
		_allow_viewer.rpc_id(owner_peer, viewer)


## Der eigene Avatar darf ab jetzt an diesen Peer funken.
@rpc("authority", "reliable")
func _allow_viewer(viewer_peer: int) -> void:
	var avatar: RemoteAvatar = avatars.get(local_peer_id())
	if avatar != null:
		avatar.allow_peer(viewer_peer)


@rpc("authority", "reliable")
func _despawn_avatar(peer_id: int) -> void:
	_despawn_avatar_here(peer_id)


func _despawn_avatar_here(peer_id: int) -> void:
	if avatars.has(peer_id):
		if is_instance_valid(avatars[peer_id]):
			avatars[peer_id].queue_free()
		avatars.erase(peer_id)


# --- Kampf: Der Server entscheidet Treffer --------------------------------

## Ein Client meldet einen Schuss. Der Server prüft, würfelt die Streuung
## selbst und verschießt echte Projektile gegen die Avatar-Trefferzonen.
## Der Client hat da längst geknallt und geblitzt — seine Leuchtspur trifft
## aber nur die Welt. Ob ein SPIELER etwas abbekommt, steht erst hier fest.
@rpc("any_peer", "reliable")
func request_fire(origin: Vector3, direction: Vector3, ammo_id: String) -> void:
	if not is_server() or arena == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not roster.has(peer_id) or not roster[peer_id].alive:
		return
	var avatar: RemoteAvatar = avatars.get(peer_id)
	if avatar == null:
		return

	var weapon_data := ItemRegistry.get_item(StringName(avatar.weapon_id)) as WeaponData
	var ammo := ItemRegistry.get_item(StringName(ammo_id)) as AmmoData
	if weapon_data == null or ammo == null:
		return
	# Munition muss zur Waffe passen — sonst schickt ein präparierter Client
	# .338-Schaden aus der Pistole.
	if ammo.caliber != weapon_data.caliber:
		return
	# Schneller als die Waffe kann, geht nicht.
	var now := Time.get_ticks_msec()
	var min_interval := int(weapon_data.get_shot_interval() * 1000.0 * FIRE_INTERVAL_TOLERANCE)
	if _last_shot_ms.has(peer_id) and now - int(_last_shot_ms[peer_id]) < min_interval:
		return
	_last_shot_ms[peer_id] = now
	# Der Abschusspunkt muss ungefähr am Avatar liegen.
	if origin.distance_to(avatar.sync_position + Vector3(0.0, 1.5, 0.0)) > MAX_ORIGIN_DRIFT:
		return
	if not direction.is_normalized():
		return

	NetShot.fire(arena, avatar, weapon_data, ammo, origin, direction,
		avatar.aiming, _on_server_pellet_hit.bind(peer_id))
	# Bei allen anderen blitzt und knallt die Waffe des Schützen.
	_avatar_fired.rpc(peer_id)


## Eine Server-Kugel hat etwas getroffen. Der Schaden ist in diesem Moment
## SCHON PASSIERT — take_hit lief in der Projektilkette gegen die
## Server-Kopie der Gesundheit. Hier wird nur noch zugeordnet und verkündet.
func _on_server_pellet_hit(collider: Node, point: Vector3,
		result: Ballistics.HitResult, direction: Vector3, shooter_peer: int) -> void:
	var target_peer := _peer_of(collider)
	if target_peer == 0:
		return
	var avatar: RemoteAvatar = avatars.get(target_peer)
	if avatar == null or avatar.body == null or avatar.body.health == null:
		return

	var kind := ImpactEffect.Kind.WORLD
	if result.was_armored:
		kind = ImpactEffect.Kind.ARMOR_PENETRATED if result.penetrated \
			else ImpactEffect.Kind.ARMOR_STOPPED
	elif result.damage_to_target > 0.0:
		kind = ImpactEffect.Kind.FLESH

	_on_hit.rpc(target_peer, point, -direction, int(kind), avatar.body.health.to_dict())

	if avatar.body.health.is_dead and roster.has(target_peer) and roster[target_peer].alive:
		_eliminate(target_peer, shooter_peer)


## Testtod auf Wunsch: Der Spieler lässt sich selbst eliminieren. Damit kann
## man Todesbildschirm und Respawn prüfen, ohne getroffen werden zu müssen.
@rpc("any_peer", "reliable")
func request_suicide() -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not roster.has(peer_id) or not roster[peer_id].alive:
		return
	var avatar: RemoteAvatar = avatars.get(peer_id)
	if avatar != null and avatar.body != null and avatar.body.health != null:
		# Auch der Testtod geht über das Gesundheitssystem, nicht daran vorbei.
		avatar.body.health.apply_damage(HealthSystem.Part.HEAD, 10000.0)
	_eliminate(peer_id, peer_id)


## Zu welchem Spieler diese Trefferzone gehört — 0 heißt: zu keinem (Welt).
func _peer_of(node: Node) -> int:
	var current := node
	while current != null:
		if current is RemoteAvatar:
			return int(String(current.name))
		current = current.get_parent()
	return 0


func _eliminate(target_peer: int, shooter_peer: int) -> void:
	roster[target_peer].alive = false
	if shooter_peer != target_peer and roster.has(shooter_peer):
		roster[shooter_peer].kills += 1
	_push_roster()
	var killer_name := "?"
	if roster.has(shooter_peer):
		killer_name = roster[shooter_peer].name
	_on_eliminated.rpc(target_peer, killer_name)
	print("[Net] Peer %d eliminiert (von %d)" % [target_peer, shooter_peer])
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(_respawn_peer.bind(target_peer))


## Nach der Wartezeit: Gesundheit zurücksetzen und an die eigene Ecke.
func _respawn_peer(peer_id: int) -> void:
	# Der Peer kann in den fünf Sekunden gegangen sein.
	if not is_server() or not roster.has(peer_id) or roster[peer_id].alive:
		return
	roster[peer_id].alive = true
	var spawn_pos := _spawn_point_of(peer_id)
	var avatar: RemoteAvatar = avatars.get(peer_id)
	if avatar != null:
		if avatar.body != null and avatar.body.health != null:
			avatar.body.health.reset()
			avatar.body.refresh_colors()
		# Die Server-Kopie sofort umsetzen — die nächste Pose vom Client
		# kommt ohnehin von der neuen Ecke.
		avatar.position = spawn_pos
		avatar.sync_position = spawn_pos
	_push_roster()
	_on_respawn.rpc(peer_id, spawn_pos)


# --- Kampf: Was die Clients zu sehen bekommen -----------------------------

## Mündungsfeuer der anderen. Unzuverlässig gefunkt: Geht eins verloren,
## fehlt ein Blitz — das merkt niemand, und Dauerfeuer flutet so keine
## zuverlässige Warteschlange.
@rpc("authority", "unreliable")
func _avatar_fired(peer_id: int) -> void:
	if peer_id == local_peer_id():
		return
	var avatar: RemoteAvatar = avatars.get(peer_id)
	if avatar != null and avatar.weapon != null:
		avatar.weapon.drive_shot()


## Ein Treffer, entschieden vom Server. Für alle: Einschlag zeigen und die
## örtliche Kopie des Getroffenen auf den Serverstand bringen. Für den
## Getroffenen selbst: Das ist der Moment, in dem seine Anzeige die Wahrheit
## erfährt — gerechnet hat sie nichts.
@rpc("authority", "reliable")
func _on_hit(target_peer: int, point: Vector3, normal: Vector3,
		kind: int, health_snapshot: Dictionary) -> void:
	if arena != null:
		ImpactEffect.spawn(arena, point, normal, kind as ImpactEffect.Kind)

	if target_peer == local_peer_id():
		var player := _local_player()
		if player != null and player.health != null:
			player.health.from_dict(health_snapshot)
			local_player_hit.emit()
		return

	var avatar: RemoteAvatar = avatars.get(target_peer)
	if avatar != null and avatar.body != null and avatar.body.health != null:
		avatar.body.health.from_dict(health_snapshot)
		avatar.body.refresh_colors()


@rpc("authority", "reliable")
func _on_eliminated(target_peer: int, killer_name: String) -> void:
	if target_peer != local_peer_id():
		return
	var player := _local_player()
	if player != null:
		# Dieselbe Sperre wie bei offenen Fenstern: kein Laufen, kein
		# Schießen, Maus frei. Der Respawn hebt sie wieder auf.
		player.set_ui_open(true)
	local_player_eliminated.emit(killer_name)


@rpc("authority", "reliable")
func _on_respawn(peer_id: int, spawn_pos: Vector3) -> void:
	if peer_id == local_peer_id():
		var player := _local_player()
		if player != null:
			player.global_position = spawn_pos
			player.velocity = Vector3.ZERO
			if player.health != null:
				player.health.reset()
			player.set_ui_open(false)
		local_player_respawned.emit()
		return
	var avatar: RemoteAvatar = avatars.get(peer_id)
	if avatar != null and avatar.body != null and avatar.body.health != null:
		avatar.body.health.reset()
		avatar.body.refresh_colors()


func _local_player() -> PlayerController:
	if arena == null:
		return null
	return arena.get_node_or_null("Player") as PlayerController


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
		steam_id = "",
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


## Client meldet nach dem Verbinden Namen, Version und Steam-Sitzung an.
@rpc("any_peer", "reliable")
func _register_client(display_name: String, protocol: int, token: String) -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not roster.has(peer_id):
		return

	# Alte Version? Klare Absage statt stiller Geisterfehler — genau so einer
	# hat den ersten Beta-Test gekostet.
	if protocol != PROTOCOL_VERSION:
		print("[Net] Peer %d abgewiesen: Version %d, Server hat %d"
			% [peer_id, protocol, PROTOCOL_VERSION])
		_rejected.rpc_id(peer_id,
			"Deine Spielversion ist veraltet — Launcher neu starten für das Update.")
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	var cleaned := display_name.strip_edges().substr(0, 24)
	if not cleaned.is_empty():
		roster[peer_id].name = cleaned

	# Steam-Anmeldung: Das Token wurde vom Anmelde-Dienst ausgegeben, die
	# Zuordnung ist also schon von Steam bestätigt. Ohne Token (Editor,
	# Gast) läuft es vorerst auch — die Beta soll niemanden aussperren.
	if not token.is_empty() and auth != null:
		var steam_id := auth.steam_id_for(token)
		if steam_id.is_empty():
			print("[Net] Peer %d: unbekanntes Token — läuft als Gast" % peer_id)
		else:
			roster[peer_id].steam_id = steam_id
			print("[Net] Peer %d angemeldet als Steam %s" % [peer_id, steam_id])
	_push_roster()


## Der Server hat die Verbindung abgelehnt — der Grund gehört dem Spieler
## gezeigt, bevor gleich darauf die Leitung fällt.
@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	rejection_reason = reason
	print("[Net] Abgewiesen: %s" % reason)


# --- Client-Seite ---------------------------------------------------------

func _on_connected_to_server() -> void:
	print("[Net] Verbunden, eigene Peer-ID: %d" % multiplayer.get_unique_id())
	rejection_reason = ""
	_register_client.rpc_id(1, player_name, PROTOCOL_VERSION, session_token)
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
	_console.register_command("die",
		"Testtod: sofort eliminieren lassen (nur im Multiplayer)", _cmd_die)


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
		_register_client.rpc_id(1, player_name, PROTOCOL_VERSION, session_token)
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


func _cmd_die(_args: PackedStringArray) -> String:
	if not is_client():
		return "Geht nur als verbundener Client"
	request_suicide.rpc_id(1)
	return "Anfrage gestellt ..."
