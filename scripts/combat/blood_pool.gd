## Eine Blutlache auf dem Boden unter einer toten Figur — entsteht am Punkt,
## wo tatsaechlich eine Wunde ist (per Strahl nach unten gesucht, siehe
## RagdollRig._spawn_blood_pool()), nicht pauschal irgendwo unter dem Koerper.
## Waechst ueber ein paar Sekunden, dann bleibt sie stehen — eine Leiche
## blutet nicht ewig weiter aus derselben Lache.
##
## Haengt an der WELTSZENE, nicht an der Figur oder einem Ragdoll-Kasten: Der
## Boden bewegt sich nicht, eine Lache soll darum liegen bleiben, auch wenn
## der Koerper darueber noch nachrutscht.
class_name BloodPool
extends Decal

## Anfangsgroesse — klein, damit man das Wachsen sieht, statt dass die Lache
## schlagartig auftaucht.
const START_SIZE_METRES := 0.10

## Maximale Groesse. Deutlich groesser als ein einzelner Blutfleck (siehe
## WoundHole) — eine Lache ist die Summe von allem, was aus der Wunde kam.
const MAX_SIZE_METRES := 1.1

## Wie lange das Wachstum dauert.
const GROWTH_DURATION := 4.5

## Flacher als WoundHole: Eine Lache liegt AUF dem Boden, sie muss nicht in
## eine Flaeche eingreifen wie ein Einschuss in Fleisch.
const DEPTH := 0.08

static var _texture: Texture2D = null
static var _orm_texture: Texture2D = null

var _age: float = 0.0


## Setzt eine Lache an eine Bodenstelle. `normal` zeigt aus der Flaeche
## heraus, wie bei WoundHole.spawn().
static func spawn(parent: Node, position: Vector3, normal: Vector3) -> BloodPool:
	if parent == null:
		return null

	var pool := BloodPool.new()
	pool.texture_albedo = _get_texture()
	# Siehe WoundHole._get_orm_texture() fuer denselben Trick — eine stehende
	# Lache spiegelt sogar noch staerker als ein einzelner Wundfleck, darum
	# hier eine noch niedrigere Rauheit (siehe POOL_ROUGHNESS unten).
	pool.texture_orm = _get_orm_texture()
	pool.size = Vector3(START_SIZE_METRES, DEPTH, START_SIZE_METRES)
	pool.albedo_mix = 1.0
	pool.cull_mask = 0xFFFFF
	pool.normal_fade = 0.5

	parent.add_child(pool)
	pool.global_position = position + normal.normalized() * 0.006
	pool._orient(normal)
	return pool


## Identische Rechnung wie WoundHole._orient() — siehe dortigen Kommentar,
## warum das nicht geteilt wird.
func _orient(normal: Vector3) -> void:
	var direction := normal.normalized()
	if direction.length_squared() < 0.001:
		return

	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT

	look_at(global_position + direction, up)
	rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	rotate_object_local(Vector3.UP, randf() * TAU)


func _process(delta: float) -> void:
	_age += delta
	if _age >= GROWTH_DURATION:
		set_process(false)
		return

	# Ease-out: waechst zuerst schnell (frisches Blut, viel Nachschub), dann
	# langsamer aus, wie eine Lache, die sich allmaehlich verteilt statt
	# linear aufzublasen.
	var t := _age / GROWTH_DURATION
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var current := lerpf(START_SIZE_METRES, MAX_SIZE_METRES, eased)
	size = Vector3(current, DEPTH, current)


const SIZE := 64

## Die geteilte Textur: dieselbe satte Blutfarbe wie WoundHole (siehe dort,
## warum kein dunkler Kern), aber mit einem unregelmaessigen statt perfekt
## runden Rand — eine Lache verteilt sich ungleichmaessig, ein Einschuss ist
## dagegen ein sauberer Kreis. Der Wellen-Trick dafuer ist derselbe wie in
## BulletHole._get_texture() (siehe dort), hier eigens berechnet, damit beide
## Klassen unabhaengig voneinander bleiben.
static func _get_texture() -> Texture2D:
	if _texture != null:
		return _texture

	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var alpha_mask := _edge_alpha_mask()
	var blood := Color(0.5, 0.03, 0.03)

	for y in range(SIZE):
		for x in range(SIZE):
			var alpha := alpha_mask[y * SIZE + x]
			image.set_pixel(x, y, Color(blood.r, blood.g, blood.b, alpha))

	_texture = ImageTexture.create_from_image(image)
	return _texture


## ORM-Textur (Rot=Verdeckung, Gruen=Rauheit, Blau=Metallisch) — siehe
## WoundHole._get_orm_texture() fuer die Begruendung. Dieselbe unregelmaessige
## Randmaske wie die Farbtextur oben (_edge_alpha_mask()), damit Glanz und
## sichtbare Lachenform exakt zusammenfallen. Eine STEHENDE Lache glaenzt
## staerker als ein einzelner Wundfleck (mehr Fluessigkeit, ruhige
## Oberflaeche) — deshalb niedrigere Rauheit als WoundHole.
const POOL_ROUGHNESS := 0.06

static func _get_orm_texture() -> Texture2D:
	if _orm_texture != null:
		return _orm_texture

	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var alpha_mask := _edge_alpha_mask()
	var orm := Color(1.0, POOL_ROUGHNESS, 0.0)

	for y in range(SIZE):
		for x in range(SIZE):
			var alpha := alpha_mask[y * SIZE + x]
			image.set_pixel(x, y, Color(orm.r, orm.g, orm.b, alpha))

	_orm_texture = ImageTexture.create_from_image(image)
	return _orm_texture


## Die unregelmaessige, wellige Alpha-Maske, die Farb- UND ORM-Textur
## gemeinsam nutzen — fester Seed, damit beide Aufrufe (Farbe, ORM) exakt
## dieselbe Form ausrechnen, statt bei jedem Aufruf neu zu wuerfeln.
static func _edge_alpha_mask() -> PackedFloat32Array:
	var centre := float(SIZE - 1) * 0.5
	var mask := PackedFloat32Array()
	mask.resize(SIZE * SIZE)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260723
	var waves := []
	for i in range(4):
		waves.append({
			frequency = rng.randf_range(3.0, 8.0),
			phase = rng.randf() * TAU,
			amplitude = rng.randf_range(0.05, 0.14),
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
			if distance < 0.75:
				alpha = 1.0
			elif distance < 1.0:
				var t := (distance - 0.75) / 0.25
				alpha = (1.0 - t) * (1.0 - t)

			mask[y * SIZE + x] = alpha

	return mask
