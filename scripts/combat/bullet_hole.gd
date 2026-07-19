## Einschussloch an einer getroffenen Fläche.
##
## Ein `Decal` und kein aufgeklebtes Mesh: Ein Decal legt sich über alles, was
## unter ihm liegt — auch über Kanten und Rundungen. Ein Quad müsste exakt auf
## der Fläche liegen und würde an jeder Rundung durch die Wand stechen oder
## darüber schweben.
##
## ---------------------------------------------------------------------------
## WARUM ES EINE OBERGRENZE GIBT
##
## Jedes Decal kostet Rechenzeit beim Zeichnen, und ein Spieler feuert im
## Verlauf eines Gefechts hunderte Schüsse ab. Ohne Grenze wird das Bild
## langsam immer zäher, und niemand kommt auf die Idee, dass es an den
## Einschusslöchern liegt. Deshalb hält diese Klasse eine feste Liste: Ist sie
## voll, verschwindet das älteste Loch.
##
## Die Textur wird einmal erzeugt und von allen Löchern geteilt. Sie im Code
## zu bauen statt als Bilddatei abzulegen hat denselben Grund wie bei den
## Waffenmodellen — sie lässt sich anpassen, ohne dass jemand ein Bild­
## programm öffnen muss.
class_name BulletHole
extends Decal

## Wie viele Löcher gleichzeitig sichtbar bleiben.
const MAX_HOLES := 96

## Wie lange ein Loch bleibt, bevor es verblasst.
const LIFETIME := 90.0

## Über wie viele Sekunden es am Ende ausblendet.
const FADE_TIME := 4.0

## Durchmesser in Metern. Ein Einschuss ist klein — hier wird bewusst etwas
## übertrieben, weil ein maßstabsgetreues Loch auf Entfernung unsichtbar wäre.
const SIZE_METRES := 0.055

## Wie tief das Decal in die Fläche greift. Zu flach und es verschwindet auf
## schrägen Wänden, zu tief und es taucht auf der Rückseite wieder auf.
const DEPTH := 0.12

static var _texture: Texture2D = null
static var _holes: Array[BulletHole] = []

var _age: float = 0.0


## Setzt ein Loch an die Trefferstelle.
##
## `normal` zeigt aus der Fläche heraus. Das Decal projiziert entlang seiner
## eigenen -Y-Achse, deshalb wird die Normale zur Hochachse gemacht.
static func spawn(parent: Node, position: Vector3, normal: Vector3) -> BulletHole:
	if parent == null:
		return null

	var hole := BulletHole.new()
	hole.texture_albedo = _get_texture()
	hole.size = Vector3(SIZE_METRES, DEPTH, SIZE_METRES)
	# Nur die Grundfarbe abdunkeln, nichts glänzen lassen.
	hole.modulate = Color(1.0, 1.0, 1.0, 1.0)
	hole.albedo_mix = 1.0
	hole.cull_mask = 0xFFFFF
	# Auf sehr schrägen Flächen sieht ein Loch verzerrt aus — ab 60 Grad
	# ausblenden statt einen langgezogenen Fleck zu zeigen.
	hole.normal_fade = 0.5
	hole.distance_fade_enabled = true
	hole.distance_fade_begin = 40.0
	hole.distance_fade_length = 15.0

	parent.add_child(hole)
	hole.global_position = position + normal.normalized() * 0.01
	hole._orient(normal)
	_remember(hole)
	return hole


## Richtet das Decal so aus, dass es in die Fläche projiziert.
func _orient(normal: Vector3) -> void:
	var direction := normal.normalized()
	if direction.length_squared() < 0.001:
		return

	# look_at bricht ab, wenn die Blickrichtung parallel zur Hochachse liegt.
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT

	# Das Decal projiziert nach unten (-Y). Erst in die Normale schauen,
	# dann um 90 Grad kippen, damit -Y in die Fläche zeigt.
	look_at(global_position + direction, up)
	rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	# Zufällige Drehung, damit nicht alle Löcher gleich aussehen.
	rotate_object_local(Vector3.UP, randf() * TAU)


## Nimmt das Loch in die Liste auf und entfernt das älteste, wenn nötig.
static func _remember(hole: BulletHole) -> void:
	# Aufgeräumte Einträge zuerst aussortieren — Löcher können auch von aussen
	# verschwinden, etwa beim Szenenwechsel.
	var alive: Array[BulletHole] = []
	for entry in _holes:
		if is_instance_valid(entry):
			alive.append(entry)
	_holes = alive

	_holes.append(hole)
	while _holes.size() > MAX_HOLES:
		var oldest: BulletHole = _holes.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Beim Szenenwechsel aufräumen, damit die Liste nicht auf tote Knoten zeigt.
static func clear_all() -> void:
	for entry in _holes:
		if is_instance_valid(entry):
			entry.queue_free()
	_holes.clear()


func _process(delta: float) -> void:
	_age += delta
	if _age < LIFETIME - FADE_TIME:
		return
	if _age >= LIFETIME:
		queue_free()
		return
	# Ausblenden statt schlagartig verschwinden — ein Loch, das im Blickfeld
	# plötzlich weg ist, fällt mehr auf als eines, das langsam verblasst.
	modulate.a = 1.0 - (_age - (LIFETIME - FADE_TIME)) / FADE_TIME


## Die geteilte Textur: dunkler Krater mit ausgefranstem Rand.
static func _get_texture() -> Texture2D:
	if _texture != null:
		return _texture

	const SIZE := 64
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := float(SIZE - 1) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260720

	# Unregelmässiger Rand aus mehreren Wellen mit ZUFÄLLIGER PHASE.
	#
	# Vorher standen hier zwei Sinuswellen mit fester Phase und 7- bzw.
	# 13-facher Symmetrie. Das war im Bild deutlich zu sehen: Die Löcher sahen
	# aus wie kleine Sternchen, alle gleich gedreht. Mit verschobenen Phasen
	# und schwächerer Auslenkung wird daraus eine Kontur, die man nicht mehr
	# als Formel erkennt.
	var waves := []
	for i in range(5):
		waves.append({
			frequency = rng.randf_range(3.0, 11.0),
			phase = rng.randf() * TAU,
			amplitude = rng.randf_range(0.012, 0.030),
		})

	for y in range(SIZE):
		for x in range(SIZE):
			var offset := Vector2(float(x) - centre, float(y) - centre)
			var distance := offset.length() / centre

			var angle := offset.angle()
			var ragged := 1.0
			for wave in waves:
				ragged += sin(angle * float(wave.frequency) + float(wave.phase)) * float(wave.amplitude)
			distance /= ragged

			var alpha := 0.0
			var brightness := 0.0
			if distance < 0.30:
				# Der eigentliche Krater: fast schwarz, mit weicher Kante.
				alpha = 1.0
				brightness = 0.03
			elif distance < 0.42:
				# Schmaler Übergang, damit der Krater keine harte Scheibe ist.
				var t := (distance - 0.30) / 0.12
				alpha = 1.0
				brightness = lerpf(0.03, 0.14, t * t)
			elif distance < 1.0:
				# Aufgeworfener Staub, nach aussen ausblendend. Quadratisch,
				# damit er nah am Loch dicht ist und aussen schnell verschwindet.
				var t := (distance - 0.42) / 0.58
				alpha = (1.0 - t) * (1.0 - t) * 0.7
				brightness = lerpf(0.16, 0.42, t)

			brightness += rng.randf_range(-0.025, 0.025)
			image.set_pixel(x, y, Color(brightness, brightness, brightness, clampf(alpha, 0.0, 1.0)))

	_texture = ImageTexture.create_from_image(image)
	return _texture
