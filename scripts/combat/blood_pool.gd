## Blutlache, die sich unter einer gestorbenen Figur ausbreitet.
##
## Ein `Decal`, aus denselben Gruenden wie bei `BulletHole`: Es legt sich ueber
## den Boden, egal ob eben, uneben oder leicht geneigt — ein aufgeklebtes Quad
## muesste exakt auf der Flaeche liegen.
##
## ---------------------------------------------------------------------------
## WARUM ES EINE OBERGRENZE GIBT
##
## Dieselbe Ueberlegung wie bei `BulletHole`: Jedes Decal kostet Zeichenzeit.
## Lachen sind seltener als Einschusslöcher (eine pro Tod, nicht eine pro
## Schuss), deshalb reicht hier eine kleinere Liste.
class_name BloodPool
extends Decal

const MAX_POOLS := 24

## Wie lange eine Lache bleibt, bevor sie verblasst.
const LIFETIME := 45.0
const FADE_TIME := 6.0

## Wie lange das Wachsen von klein auf volle Groesse dauert — sofort in voller
## Groesse da zu sein, sieht aus wie ein aufgeklebter Aufkleber statt wie
## Fluessigkeit, die sich gerade ausbreitet.
const GROW_TIME := 1.4

## Durchmesser in Metern, mit Streuung, damit nicht jede Lache gleich aussieht.
const SIZE_MIN := 0.9
const SIZE_MAX := 1.5

const DEPTH := 0.12

static var _texture: Texture2D = null
static var _pools: Array[BloodPool] = []

var _age: float = 0.0
var _target_size: float = 1.0


## Setzt eine Lache an die angegebene Bodenstelle.
static func spawn(parent: Node, position: Vector3) -> BloodPool:
	if parent == null:
		return null

	var pool := BloodPool.new()
	pool.texture_albedo = _get_texture()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	pool._target_size = rng.randf_range(SIZE_MIN, SIZE_MAX)
	# Klein anfangen — _process() zieht das hoch auf _target_size.
	pool.size = Vector3(0.05, DEPTH, 0.05)
	pool.albedo_mix = 1.0
	pool.cull_mask = 0xFFFFF
	pool.normal_fade = 0.6
	pool.distance_fade_enabled = true
	pool.distance_fade_begin = 35.0
	pool.distance_fade_length = 12.0

	parent.add_child(pool)
	pool.global_position = position + Vector3(0.0, 0.02, 0.0)
	# Zufaellig gedreht, damit uebereinanderliegende Lachen (mehrere Tote am
	# selben Fleck) nicht wie dieselbe Kopie wirken.
	pool.rotate_object_local(Vector3.UP, rng.randf() * TAU)
	_remember(pool)
	return pool


static func _remember(pool: BloodPool) -> void:
	var alive: Array[BloodPool] = []
	for entry in _pools:
		if is_instance_valid(entry):
			alive.append(entry)
	_pools = alive

	_pools.append(pool)
	while _pools.size() > MAX_POOLS:
		var oldest: BloodPool = _pools.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Beim Szenenwechsel aufraeumen, damit die Liste nicht auf tote Knoten zeigt.
static func clear_all() -> void:
	for entry in _pools:
		if is_instance_valid(entry):
			entry.queue_free()
	_pools.clear()


func _process(delta: float) -> void:
	_age += delta

	if _age < GROW_TIME:
		var t := _age / GROW_TIME
		# Quadratisch statt linear: Fluessigkeit breitet sich anfangs schnell
		# aus und wird zum Rand hin langsamer, nicht gleichmaessig.
		var current := lerpf(0.05, _target_size, 1.0 - (1.0 - t) * (1.0 - t))
		size = Vector3(current, DEPTH, current)

	if _age < LIFETIME - FADE_TIME:
		return
	if _age >= LIFETIME:
		queue_free()
		return
	modulate.a = 1.0 - (_age - (LIFETIME - FADE_TIME)) / FADE_TIME


## Die geteilte Textur: unregelmaessiger dunkelroter Fleck mit weichem Rand.
##
## Dieselbe Technik wie bei `BulletHole._get_texture()` (mehrere Sinuswellen
## mit zufaelliger Phase fuer eine Kontur, die nicht wie eine Formel aussieht)
## — hier aber EIN Fleck statt Krater-plus-Staub, dafuer mit einer zweiten,
## feineren Wellenschicht, damit der Rand nicht nur oval, sondern richtig
## ausgefranst wirkt (eine Lache breitet sich entlang kleiner Bodenrisse aus,
## nicht als glatte Ellipse).
static func _get_texture() -> Texture2D:
	if _texture != null:
		return _texture

	const SIZE := 64
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := float(SIZE - 1) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260722

	var coarse := []
	for i in range(4):
		coarse.append({
			frequency = rng.randf_range(2.0, 5.0),
			phase = rng.randf() * TAU,
			amplitude = rng.randf_range(0.05, 0.11),
		})
	var fine := []
	for i in range(6):
		fine.append({
			frequency = rng.randf_range(9.0, 17.0),
			phase = rng.randf() * TAU,
			amplitude = rng.randf_range(0.02, 0.05),
		})

	var core := Color(0.30, 0.015, 0.015)
	var rim := Color(0.16, 0.01, 0.01)

	for y in range(SIZE):
		for x in range(SIZE):
			var offset := Vector2(float(x) - centre, float(y) - centre)
			var distance := offset.length() / centre
			var angle := offset.angle()

			var ragged := 1.0
			for wave in coarse:
				ragged += sin(angle * float(wave.frequency) + float(wave.phase)) * float(wave.amplitude)
			for wave in fine:
				ragged += sin(angle * float(wave.frequency) + float(wave.phase)) * float(wave.amplitude)
			distance /= ragged

			var alpha := 0.0
			var colour := core
			if distance < 0.75:
				alpha = 0.92
				colour = core
			elif distance < 1.0:
				var t := (distance - 0.75) / 0.25
				alpha = (1.0 - t) * (1.0 - t) * 0.92
				colour = core.lerp(rim, t)

			image.set_pixel(x, y, Color(colour.r, colour.g, colour.b, clampf(alpha, 0.0, 1.0)))

	_texture = ImageTexture.create_from_image(image)
	return _texture
