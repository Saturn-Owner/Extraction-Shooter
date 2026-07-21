## Hilfsclient für verify_net: verbindet sich, betritt die Arena und LÄUFT.
##
## Kein eigener Test — dieses Skript ist der "andere Spieler", dem die
## Suite von außen zusieht. Es geht denselben Weg wie ein echter Client
## (Arena laden, Spieler gespawnt bekommen, PlayerNetSync funkt die Pose)
## und bewegt seinen Spieler dann sichtbar hin und her.
##
## Aufruf (macht verify_net selbst):
##   godot --headless --path . --script res://tests/net_mover.gd -- --port 24599
extends SceneTree

const LIFETIME_MS := 30000

var _net: Node
var _arena: Node3D
var _t0 := 0
var _started := false
var _connected := false
var _origin := Vector3.INF


func _initialize() -> void:
	_net = root.get_node_or_null("Net")
	_net.player_name = "Laeufer"
	_net.connection_succeeded.connect(func() -> void: _connected = true)
	_net.connection_failed.connect(func() -> void: quit(1))
	_t0 = Time.get_ticks_msec()


func _port() -> int:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--port" and index + 1 < args.size():
			return args[index + 1].to_int()
	return 24567


## Standard ist der örtliche Testserver; mit --host kann man den Läufer
## auch gegen den VPS schicken.
func _host() -> String:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--host" and index + 1 < args.size():
			return args[index + 1]
	return "127.0.0.1"


func _process(_delta: float) -> bool:
	var elapsed := Time.get_ticks_msec() - _t0
	if elapsed > LIFETIME_MS:
		_net.shutdown()
		quit(0)
		return true

	if not _started:
		# Nicht in _initialize(): Dort ist die Multiplayer-API noch null.
		_started = true
		_net.start_client(_host(), _port())
		return false

	if _connected and _arena == null:
		_arena = (load("res://scenes/levels/arena_beta.tscn") as PackedScene).instantiate()
		root.add_child(_arena)
		return false

	if _arena == null:
		return false

	var player := _arena.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return false

	# Auf und ab laufen: 3 m Ausschlag, gut messbar, deutlich über jedem
	# Netz-Zittern. Direkt gesetzt statt über Eingaben — hier geht es um die
	# Leitung, nicht um die Beine.
	if _origin == Vector3.INF:
		_origin = player.global_position
	var t := float(elapsed) / 1000.0
	player.global_position = _origin + Vector3(sin(t * 2.0) * 3.0, 0.0, 0.0)
	return false
