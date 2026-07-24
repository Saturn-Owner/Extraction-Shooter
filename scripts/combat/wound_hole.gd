## Ein Einschussloch in Fleisch, an der Trefferstelle.
##
## Das GEGENSTUECK zu BulletHole, nicht dasselbe wiederverwendet: Dort steht
## ausdruecklich, warum ein Loch nur auf FESTEM Untergrund bleibt ("in Fleisch
## waere es falsch", siehe Projectile._spawn_impact()) — die Krater-Textur
## dort zeigt aufgeworfenen Staub und einen ausgefransten Rand, passend für
## Wand oder Boden, nicht für eine Wunde. Diese Klasse ist die Entsprechung
## für Körpertreffer: eine kleine, dunkelrote Wunde statt eines grauen
## Kraters. WoundBleed (der Blutstreifen) setzt direkt darunter an, siehe
## BlockyCharacter._spawn_wound().
##
## Haengt wie WoundBleed am getroffenen Koerperteil-Mesh statt an der
## Weltszene, damit sie mitgeht, wenn sich die Figur bewegt — anders als
## BulletHole, das an unbeweglicher Weltgeometrie haengenbleiben darf.
class_name WoundHole
extends Decal

## Deutlich groesser als massstabsgetreu, sonst wäre er auf Entfernung kaum
## zu erkennen (derselbe Grund wie bei BulletHole).
const SIZE_METRES := 0.07

## Flacher als BulletHole (0.12): Die Koerperteile dieser Figur sind duenn
## (ein Unterarm etwa 11 cm breit) — zu tief, und das Loch stuende auf der
## Rueckseite wieder heraus.
const DEPTH := 0.05

static var _texture: Texture2D = null
static var _orm_texture: Texture2D = null


## Setzt eine Wunde an die Trefferstelle. `normal` zeigt aus der Flaeche
## heraus, wie bei BulletHole.spawn().
static func spawn(parent: Node, position: Vector3, normal: Vector3) -> WoundHole:
	if parent == null:
		return null

	var hole := WoundHole.new()
	hole.texture_albedo = _get_texture()
	# ORM-Textur (Occlusion/Roughness/Metallic) mit niedriger Rauheit nur dort,
	# wo die Wunde selbst sichtbar ist (siehe _get_orm_texture()) — sonst wirkt
	# der Fleck matt wie trockene Farbe statt wie frisches, feuchtes Blut.
	hole.texture_orm = _get_orm_texture()
	hole.size = Vector3(SIZE_METRES, DEPTH, SIZE_METRES)
	hole.albedo_mix = 1.0
	hole.cull_mask = 0xFFFFF
	hole.normal_fade = 0.5

	parent.add_child(hole)
	hole.global_position = position + normal.normalized() * 0.004
	hole._orient(normal)
	return hole


## Richtet das Decal so aus, dass es in die Flaeche projiziert — identische
## Rechnung wie BulletHole._orient(), hier aber nicht geteilt: Beide Klassen
## sollen unabhaengig voneinander aenderbar bleiben, ohne dass eine
## gemeinsame Basisklasse Annahmen ueber Wand-Loecher in Wund-Loecher
## hineintraegt (oder umgekehrt).
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


## Die geteilte Textur: durchgehend Blutrot mit weichem Rand, KEINE dunkle
## Mitte. War zuerst ein fast schwarzer Kern mit rotem Rand (wie eingetrocknetes
## Blut um ein Loch) — sah dadurch aus wie ein schwarzer Punkt mit rotem Hof.
## Jetzt ist die ganze Flaeche dieselbe satte Rotfarbe, nur der Alphawert faellt
## zum Rand hin weich ab.
static func _get_texture() -> Texture2D:
	if _texture != null:
		return _texture

	const SIZE := 48
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := float(SIZE - 1) * 0.5

	var blood := Color(0.55, 0.03, 0.03)

	for y in range(SIZE):
		for x in range(SIZE):
			var offset := Vector2(float(x) - centre, float(y) - centre)
			var distance := offset.length() / centre

			var alpha := 0.0
			if distance < 0.55:
				alpha = 1.0
			elif distance < 1.0:
				var t := (distance - 0.55) / 0.45
				alpha = (1.0 - t) * (1.0 - t)

			image.set_pixel(x, y, Color(blood.r, blood.g, blood.b, alpha))

	_texture = ImageTexture.create_from_image(image)
	return _texture


## ORM-Textur (Rot=Verdeckung, Gruen=Rauheit, Blau=Metallisch) zur Farbtextur
## oben — DIESELBE Alpha-Maske (nur innerhalb der Wunde soll die Oberflaeche
## glaenzen, nicht das umliegende Fleisch), aber mit durchgehend niedriger
## Rauheit statt Farbe. Frisches Blut ist fluessig und reflektiert Licht,
## eingetrocknetes Fleisch drumherum nicht — deshalb hier extra und nicht
## einfach am Material der ganzen Figur.
static func _get_orm_texture() -> Texture2D:
	if _orm_texture != null:
		return _orm_texture

	const SIZE := 48
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := float(SIZE - 1) * 0.5

	# Rot=1.0 (keine zusaetzliche Verdeckung), Gruen=Rauheit (niedrig = glaenzend),
	# Blau=0.0 (Blut ist nicht metallisch).
	const ROUGHNESS := 0.1
	var orm := Color(1.0, ROUGHNESS, 0.0)

	for y in range(SIZE):
		for x in range(SIZE):
			var offset := Vector2(float(x) - centre, float(y) - centre)
			var distance := offset.length() / centre

			var alpha := 0.0
			if distance < 0.55:
				alpha = 1.0
			elif distance < 1.0:
				var t := (distance - 0.55) / 0.45
				alpha = (1.0 - t) * (1.0 - t)

			image.set_pixel(x, y, Color(orm.r, orm.g, orm.b, alpha))

	_orm_texture = ImageTexture.create_from_image(image)
	return _orm_texture
