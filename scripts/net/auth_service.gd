## Steam-Anmeldeprüfung auf dem dedizierten Server.
##
## Der Launcher schickt hierher, was Steam seinem Browser mitgegeben hat.
## DIESER Dienst fragt dann selbst bei Steam nach: "Habt ihr das wirklich
## unterschrieben?" (openid check_authentication). Erst wenn Steam ja sagt,
## gibt es ein Sitzungs-Token. Ohne diese Gegenprüfung könnte jeder Client
## einfach eine fremde Steam-ID behaupten.
##
## Wir speichern KEINE Passwörter und legen keine Konten an — nur eine
## Tabelle "Token gehört zu Steam-ID", die mit dem Serverprozess stirbt.
##
## Ein winziger, handgebauter HTTP-Listener genügt: eine Route, kleine
## Anfragen, keine Dateien. Für alles Größere (Downloads) ist er bewusst
## NICHT zuständig — das macht ein normaler Datei-Server (siehe docs).
class_name AuthService
extends Node

const DEFAULT_PORT := 24568
const STEAM_OPENID := "https://steamcommunity.com/openid/login"
## Wer nach 10 Sekunden seine Anfrage nicht losgeworden ist, fliegt raus.
const REQUEST_TIMEOUT_MS := 10000

var _server: TCPServer
## Offene Verbindungen: [{peer, buffer, started_at}]
var _pending: Array = []
## token -> steam_id — die ganze "Datenbank".
var _sessions: Dictionary = {}
var _crypto := Crypto.new()


func listen(port: int = DEFAULT_PORT) -> String:
	_server = TCPServer.new()
	if _server.listen(port) != OK:
		return "Anmelde-Dienst kann Port %d nicht öffnen" % port
	print("[Auth] Anmelde-Dienst lauscht auf Port %d" % port)
	return ""


## Gehört dieses Token zu einer bestätigten Anmeldung? Leer heißt nein.
func steam_id_for(token: String) -> String:
	return _sessions.get(token, "")


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_pending.append({
			peer = _server.take_connection(),
			buffer = "",
			started_at = Time.get_ticks_msec(),
		})

	for entry in _pending.duplicate():
		var peer: StreamPeerTCP = entry.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED \
				or Time.get_ticks_msec() - entry.started_at > REQUEST_TIMEOUT_MS:
			_drop(entry)
			continue
		if peer.get_available_bytes() > 0:
			entry.buffer += peer.get_utf8_string(peer.get_available_bytes())
		if _request_complete(entry.buffer):
			_handle_request(entry)


func _drop(entry: Dictionary) -> void:
	(entry.peer as StreamPeerTCP).disconnect_from_host()
	_pending.erase(entry)


## Kopfzeilen komplett und der Rumpf so lang wie angekündigt?
func _request_complete(buffer: String) -> bool:
	var split := buffer.find("\r\n\r\n")
	if split < 0:
		return false
	var announced := 0
	for line in buffer.substr(0, split).split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			announced = line.get_slice(":", 1).strip_edges().to_int()
	return buffer.length() >= split + 4 + announced


func _handle_request(entry: Dictionary) -> void:
	var buffer: String = entry.buffer
	var first_line := buffer.get_slice("\r\n", 0)
	var body := buffer.substr(buffer.find("\r\n\r\n") + 4)
	_pending.erase(entry)

	if first_line.begins_with("POST /steam-auth"):
		_verify_with_steam(entry.peer, body)
	else:
		_respond(entry.peer, 404, '{"error":"unbekannter Pfad"}')


## Fragt bei Steam nach, ob die Antwort echt ist.
##
## Die Parameter werden UNANGETASTET weitergereicht (nur der Modus wird
## getauscht): Steam hat exakt diese Werte signiert — wer sie umkodiert,
## macht die Unterschrift kaputt.
func _verify_with_steam(peer: StreamPeerTCP, openid_query: String) -> void:
	var pairs: PackedStringArray = []
	for pair in openid_query.split("&", false):
		if not pair.begins_with("openid.mode="):
			pairs.append(pair)
	pairs.append("openid.mode=check_authentication")

	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			request.queue_free()
			_on_steam_answer(peer, openid_query, result, code, body))
	var error := request.request(STEAM_OPENID,
		["Content-Type: application/x-www-form-urlencoded"],
		HTTPClient.METHOD_POST, "&".join(pairs))
	if error != OK:
		request.queue_free()
		_respond(peer, 502, '{"error":"Steam nicht erreichbar"}')


func _on_steam_answer(peer: StreamPeerTCP, openid_query: String,
		result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_respond(peer, 502, '{"error":"Steam antwortet nicht"}')
		return
	if not "is_valid:true" in body.get_string_from_utf8():
		print("[Auth] Anmeldung abgelehnt — Steam bestätigt die Unterschrift nicht")
		_respond(peer, 403, '{"error":"Steam bestätigt die Anmeldung nicht"}')
		return

	var steam_id := _steam_id_from(openid_query)
	if steam_id.is_empty():
		_respond(peer, 400, '{"error":"keine Steam-ID in der Antwort"}')
		return

	var token := _crypto.generate_random_bytes(24).hex_encode()
	_sessions[token] = steam_id
	print("[Auth] Steam-Anmeldung bestätigt: %s" % steam_id)
	_respond(peer, 200, JSON.stringify({token = token, steam_id = steam_id}))


## Die Steam-ID steckt in openid.claimed_id:
##   https://steamcommunity.com/openid/id/76561198...
func _steam_id_from(openid_query: String) -> String:
	for pair in openid_query.split("&", false):
		if pair.begins_with("openid.claimed_id="):
			var value := pair.get_slice("=", 1).uri_decode()
			return value.get_slice("/id/", 1)
	return ""


func _respond(peer: StreamPeerTCP, code: int, body: String) -> void:
	var reason := "OK" if code == 200 else "Error"
	var payload := body.to_utf8_buffer()
	peer.put_data(("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\n" % [code, reason] +
		"Content-Length: %d\r\nConnection: close\r\n\r\n" % payload.size()).to_utf8_buffer())
	peer.put_data(payload)
	peer.disconnect_from_host()
