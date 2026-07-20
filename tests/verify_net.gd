## Prüft den Netzwerk-Unterbau — mit einem ECHTEN Server.
##
##   godot --headless --path . --script res://tests/verify_net.gd
##
## Der Kern dieser Suite ist kein Attrappen-Test: Sie startet das Spiel
## selbst als zweiten Headless-Prozess im Servermodus, verbindet sich über
## echtes ENet auf 127.0.0.1 und prüft, dass Roster und Spawn-Zuweisung
## wirklich über die Leitung ankommen. Ein Test, der sich sein Roster selbst
## ins Dictionary schreibt, würde genau die Fehler übersehen, um die es beim
## Netzwerk geht: RPC-Konfiguration, Pfad-Auflösung, Reihenfolge.
##
## STOLPERSTEIN: Dieses Skript wird kompiliert, BEVOR die Autoloads ihre
## globalen Namen registrieren — `Net.` gibt hier einen Compilerfehler.
## Deshalb wird das Autoload zur Laufzeit über seinen Pfad geholt.
##
## Gewartet wird auf Ereignisse mit Zeit-Obergrenze, nie auf Framezahlen —
## im Headless-Modus tickt _process nicht mit 60 Hz.
extends SceneTree

## Eigener Port, damit ein parallel laufendes Spiel nicht dazwischenfunkt.
const TEST_PORT := 24599
## Der Server-Prozess braucht ein paar Sekunden zum Laden.
const CONNECT_RETRY_MS := 2000
const MAX_CONNECT_ATTEMPTS := 5
const OVERALL_TIMEOUT_MS := 40000

enum Stage {LOCAL_COMBAT, BOOT, CONNECT, WAIT_ROSTER, WAIT_AVATAR, DONE}

var _net: Node
var _arena: Node3D
## Wo der Server den eigenen Avatar hingestellt hat — festgehalten im Moment
## des Spawns. Später überschreibt die NetSync-Brücke sync_position laufend
## mit der echten Spielerposition, dann ist der Spawn-Wert nicht mehr ablesbar.
var _spawned_at := Vector3.INF
## Die Zielfigur der örtlichen Schadenskette und was ihre Treffer melden.
var _victim: Node3D
var _combat_hits: Array = []
var _failed := 0
var _passed := 0
var _stage: Stage = Stage.BOOT
var _started_at := 0
var _stage_started_at := 0
var _connect_attempts := 0
var _server_pid := -1
var _got_success := false
var _got_failure := false


func _initialize() -> void:
	print("=== Netzwerk prüfen ===\n")
	_net = root.get_node_or_null("Net")
	if _net == null:
		print("  FEHLER  Net-Autoload fehlt — project.godot kaputt?")
		quit(1)
		return
	_run_unit_checks()
	_started_at = Time.get_ticks_msec()
	_stage_started_at = _started_at
	# Der Server bootet nebenher, während örtlich die Schadenskette läuft —
	# so kostet der Kettentest keine zusätzliche Wartezeit. Aufgebaut wird
	# die Kette erst im ersten Frame: In _initialize() ist der Baum noch
	# nicht aktiv, und global_position auf den Projektilen schlüge fehl.
	_launch_server()
	_stage = Stage.LOCAL_COMBAT
	_net.connection_succeeded.connect(func() -> void: _got_success = true)
	_net.connection_failed.connect(func() -> void: _got_failure = true)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


# --- Rechenlogik ohne Leitung ---------------------------------------------

func _run_unit_checks() -> void:
	# Adress-Zerlegung
	_check(_net._parse_address("10.0.0.1") == ["10.0.0.1", _net.DEFAULT_PORT],
		"Adresse ohne Port bekommt den Standardport")
	_check(_net._parse_address("10.0.0.1:777") == ["10.0.0.1", 777],
		"Adresse mit Port wird zerlegt")
	_check(_net._parse_address("srv.example.de:abc")[1] == _net.DEFAULT_PORT,
		"Kaputter Port fällt auf den Standard zurück")

	# Port aus Startargumenten (Bootstrap)
	var bootstrap: Node = (load("res://scripts/net/net_bootstrap.gd") as GDScript).new()
	_check(bootstrap._port_from_args(PackedStringArray(["--server", "--port", "777"])) == 777,
		"--port 777 wird gelesen")
	_check(bootstrap._port_from_args(PackedStringArray(["--port=888"])) == 888,
		"--port=888 wird gelesen")
	_check(bootstrap._port_from_args(PackedStringArray(["--server"])) == _net.DEFAULT_PORT,
		"Ohne Angabe gilt der Standardport")
	bootstrap.free()

	# Spawn-Verteilung: immer die am wenigsten belegte Ecke.
	# Konstruierte Eingabe ist hier in Ordnung — die Funktion ist pur, und ob
	# das Roster echt ankommt, prüft der Leitungs-Test unten.
	_net.roster = {}
	_check(_net._least_used_spawn() == 0, "Leeres Roster: erste Ecke")
	_net.roster = {2: {spawn_index = 0}, 3: {spawn_index = 1}}
	_check(_net._least_used_spawn() == 2, "Ecken 0+1 belegt: Ecke 2 ist dran")
	_net.roster = {2: {spawn_index = 0}, 3: {spawn_index = 1}, 4: {spawn_index = 2},
		5: {spawn_index = 3}, 6: {spawn_index = 0}}
	_check(_net._least_used_spawn() == 1, "Bei Überzahl: die am wenigsten belegte Ecke")
	_net.roster = {}


# --- Örtliche Schadenskette -----------------------------------------------
#
# Baut einen fremden Avatar (mit Körper und Trefferzonen, wie er auf dem
# Server steht) und verschießt echte NetShot-Projektile auf seine Brust.
# Das prüft die ganze Kette Projektil → Trefferzone → Körperteil →
# Gesundheit, so wie sie der Server im Ernstfall rechnet — ohne Attrappe.

func _setup_local_combat() -> void:
	var packed: PackedScene = load("res://scenes/net/remote_avatar.tscn")
	_victim = packed.instantiate()
	_victim.display_name = "Opfer"
	# Fremde Autorität: So baut der Avatar seinen Körper, wie auf dem Server.
	_victim.set_multiplayer_authority(77)
	root.add_child(_victim)

	var weapon_data := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var ammo := ItemRegistry.get_item(&"ammo_556x45_m855a1") as AmmoData
	_check(weapon_data != null and ammo != null, "Waffen- und Munitionsdaten geladen")
	if weapon_data == null or ammo == null:
		return

	# Zehn Schuss aus vier Metern auf Brusthöhe. Genug, um zu töten — genau
	# das soll die Kette ja beweisen.
	for i in range(10):
		NetShot.fire(root, null, weapon_data, ammo,
			Vector3(0.0, 1.3, 4.0), Vector3(0.0, 0.0, -1.0), true,
			func(collider: Node, _point: Vector3, result: Ballistics.HitResult,
					_direction: Vector3) -> void:
				_combat_hits.append({collider = collider, result = result}))


func _run_local_combat_checks() -> void:
	_check(_victim.get_node_or_null("Koerper") != null,
		"Fremder Avatar baut seinen Körper")
	_check(_combat_hits.size() >= 10,
		"Alle Kugeln haben eingeschlagen (%d von 10)" % _combat_hits.size())
	if _combat_hits.is_empty():
		return

	var first: Dictionary = _combat_hits[0]
	_check(first.collider is CharacterHitbox, "Getroffen wurde eine Trefferzone")
	_check((first.result as Ballistics.HitResult).damage_to_target > 0.0,
		"Der Treffer richtet Schaden an")

	var body := _victim.get_node_or_null("Koerper") as BlockyCharacter
	if body != null and body.health != null:
		# In den Gliedern bleiben Trefferpunkte übrig — tot ist, wessen
		# lebenswichtiges Teil zerstört ist, nicht wer bei null steht.
		_check(body.health.is_dead, "Zehn Brusttreffer 5,56 töten die Figur")
	_victim.queue_free()


# --- Echte Leitung --------------------------------------------------------

func _launch_server() -> void:
	var project_dir := ProjectSettings.globalize_path("res://")
	_server_pid = OS.create_process(OS.get_executable_path(),
		["--headless", "--path", project_dir, "--", "--server", "--port", str(TEST_PORT)])
	_check(_server_pid > 0, "Server-Prozess gestartet (PID %d)" % _server_pid)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started_at > OVERALL_TIMEOUT_MS:
		_check(false, "Zeitüberschreitung in Stufe %s" % Stage.keys()[_stage])
		return _finish()

	match _stage:
		Stage.LOCAL_COMBAT:
			if _victim == null:
				_setup_local_combat()
				return false
			# Fertig, sobald genug Kugeln eingeschlagen sind — oder nach
			# 5 Sekunden, dann schlagen die Prüfungen eben fehl und sagen warum.
			if _combat_hits.size() >= 10 \
					or Time.get_ticks_msec() - _stage_started_at > 5000:
				_run_local_combat_checks()
				_next_stage(Stage.BOOT)
		Stage.BOOT:
			# Dem Server-Prozess Zeit zum Laden geben, sonst läuft der erste
			# Verbindungsversuch garantiert ins Leere.
			if Time.get_ticks_msec() - _stage_started_at > 3000:
				_next_stage(Stage.CONNECT)
		Stage.CONNECT:
			_drive_connect()
		Stage.WAIT_ROSTER:
			# Erst wenn auch der Anzeigename da ist: Die erste Abschrift kommt
			# schon beim Verbinden, die Namensanmeldung ist ein zweiter RPC —
			# wer auf die erste prüft, testet gegen einen Wettlauf.
			var my_id: int = _net.local_peer_id()
			if _net.roster.has(my_id) and _net.roster[my_id].name == _net.player_name:
				_run_roster_checks()
				_enter_arena()
				_next_stage(Stage.WAIT_AVATAR)
		Stage.WAIT_AVATAR:
			if _net.avatars.has(_net.local_peer_id()) \
					and _arena.get_node_or_null("Player") != null:
				_run_avatar_checks()
				return _finish()
		Stage.DONE:
			return true
	return false


func _next_stage(stage: Stage) -> void:
	_stage = stage
	_stage_started_at = Time.get_ticks_msec()


func _drive_connect() -> void:
	if _got_success:
		_check(true, "Verbindung steht (Versuch %d)" % _connect_attempts)
		_next_stage(Stage.WAIT_ROSTER)
		return
	if _got_failure or _connect_attempts == 0:
		if _connect_attempts >= MAX_CONNECT_ATTEMPTS:
			_check(false, "Keine Verbindung nach %d Versuchen" % _connect_attempts)
			_finish()
			return
		if _connect_attempts == 0 \
				or Time.get_ticks_msec() - _stage_started_at > CONNECT_RETRY_MS:
			_got_failure = false
			_connect_attempts += 1
			_stage_started_at = Time.get_ticks_msec()
			var error: String = _net.start_client("127.0.0.1", TEST_PORT)
			if not error.is_empty():
				_net.shutdown()


func _run_roster_checks() -> void:
	var my_id: int = _net.local_peer_id()
	_check(my_id > 1, "Eigene Peer-ID ist vergeben (%d)" % my_id)
	_check(_net.is_client(), "Modus ist Client")
	var entry: Dictionary = _net.roster[my_id]
	_check(entry.spawn_index >= 0 and entry.spawn_index < _net.SPAWN_COUNT,
		"Server hat Spawn-Ecke zugewiesen (%d)" % entry.spawn_index)
	_check(entry.name == "Spieler", "Anzeigename kam über die Leitung an (%s)" % entry.name)
	_check(entry.alive == true, "Frisch verbunden heißt lebendig")
	_check(entry.kills == 0, "Killzähler beginnt bei null")


## Baut die Arena in den Testbaum — wie es der Bootstrap nach dem Verbinden
## täte. Erst DANACH meldet sich der Client bereit, und erst dann darf der
## Server Avatare für ihn spawnen.
func _enter_arena() -> void:
	var packed: PackedScene = load("res://scenes/levels/arena_beta.tscn")
	_check(packed != null, "Arena-Szene lädt")
	_net.own_avatar_spawned.connect(func(at: Vector3) -> void: _spawned_at = at)
	_arena = packed.instantiate()
	root.add_child(_arena)
	# Das Level meldet sich in _ready() selbst bei Net an — genau dieser Weg
	# (register_arena -> _client_ready -> Server spawnt) wird hier getestet.


func _run_avatar_checks() -> void:
	var my_id: int = _net.local_peer_id()
	var avatar: Node3D = _net.avatars[my_id]
	_check(avatar.get_multiplayer_authority() == my_id,
		"Eigener Avatar gehört dem eigenen Peer")
	_check(avatar.get_node_or_null("Koerper") == null,
		"Eigener Avatar bleibt körperlos (nur Transport)")

	# Der Server hat die Ecke aus dem Roster benutzt — der Avatar muss an
	# genau dem Marker gespawnt sein, den das Level für diesen Index kennt.
	var expected: Vector3 = _arena.spawn_position(_net.roster[my_id].spawn_index)
	_check(_spawned_at.distance_to(expected) < 0.01,
		"Avatar wurde an der zugewiesenen Ecke gespawnt")

	var player := _arena.get_node_or_null("Player") as Node3D
	_check(player != null, "Lokaler Spieler wurde in die Arena gestellt")
	if player != null:
		_check(player.global_position.distance_to(expected) < 0.5,
			"Spieler steht an seiner Ecke")
		_check(player.get_node_or_null("NetSync") != null,
			"NetSync-Brücke hängt am Spieler")

	var benches := _arena.get_node("Werkbaenke").get_child_count()
	_check(benches == 4, "Vier Werkbänke stehen an den Spawns (%d)" % benches)
	_check(_arena.get_node("Spawns").get_child_count() == 4, "Vier Spawn-Ecken")

	_net.shutdown()
	_check(not _net.is_multiplayer(), "Trennen setzt den Modus zurück")
	_check(_net.roster.is_empty(), "Trennen leert die Roster-Abschrift")


func _finish() -> bool:
	if _server_pid > 0:
		OS.kill(_server_pid)
	_stage = Stage.DONE
	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true
