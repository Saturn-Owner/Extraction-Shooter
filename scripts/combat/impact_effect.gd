## Einschlageffekt: Funken, Staub und ein kurzer Lichtblitz.
##
## Wird komplett im Code aufgebaut statt als .tscn. Grund: Partikel-Material
## von Hand in eine Szenendatei zu schreiben ist extrem fehleranfaellig, und
## so laesst sich der Effekt je nach Treffer unterschiedlich einfaerben.
##
## Der Effekt raeumt sich selbst auf — es gibt kein Aufsammeln von Resten.
class_name ImpactEffect
extends Node3D

## Wie lange der Effekt lebt, bevor er sich entfernt.
const LIFETIME := 1.2

## Farben je nach Trefferart. Die Rueckmeldung soll auf einen Blick
## erkennbar sein, ohne den Text im HUD lesen zu muessen.
const COLOR_WORLD := Color(0.85, 0.82, 0.72)     ## Erde, Schnee, Beton
const COLOR_FLESH := Color(0.72, 0.12, 0.10)     ## ungeschuetzter Treffer
const COLOR_ARMOR_STOP := Color(0.95, 0.85, 0.45) ## Platte haelt: Funken
const COLOR_ARMOR_PEN := Color(0.95, 0.45, 0.20)  ## Platte durchschlagen


enum Kind { WORLD, FLESH, ARMOR_STOPPED, ARMOR_PENETRATED }


## Erzeugt einen Einschlag an der Trefferstelle und haengt ihn in die Szene.
##
## Position und Ausrichtung werden gemerkt und erst in _ready() angewendet.
## Grund: global_position funktioniert nur, wenn der Knoten wirklich im
## Szenenbaum haengt — direkt nach add_child() ist das nicht garantiert.
static func spawn(parent: Node, position: Vector3, normal: Vector3, kind: Kind) -> ImpactEffect:
	var effect := ImpactEffect.new()
	effect.kind = kind
	effect._spawn_position = position
	effect._spawn_normal = normal
	parent.add_child(effect)
	return effect


var kind: Kind = Kind.WORLD

var _spawn_position: Vector3 = Vector3.ZERO
var _spawn_normal: Vector3 = Vector3.UP


func _ready() -> void:
	global_position = _spawn_position
	if _spawn_normal.length_squared() > 0.001:
		# Nicht ausrichten, wenn die Normale parallel zur Hochachse liegt —
		# look_at wirft dann einen Fehler.
		var up := Vector3.UP
		if absf(_spawn_normal.normalized().dot(up)) > 0.99:
			up = Vector3.RIGHT
		look_at(_spawn_position + _spawn_normal, up)

	var color := _get_color()
	_build_particles(color)
	_build_light(color)

	# Selbstaufraeumen, damit sich keine Effekte ansammeln.
	var timer := get_tree().create_timer(LIFETIME)
	timer.timeout.connect(queue_free)


func _get_color() -> Color:
	match kind:
		Kind.FLESH: return COLOR_FLESH
		Kind.ARMOR_STOPPED: return COLOR_ARMOR_STOP
		Kind.ARMOR_PENETRATED: return COLOR_ARMOR_PEN
		_: return COLOR_WORLD


func _build_particles(color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 14 if kind == Kind.WORLD else 22
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 0, 1)
	process.spread = 55.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0, -9.0, 0)
	process.scale_min = 0.3
	process.scale_max = 1.0
	# Partikel schrumpfen im Verlauf, damit der Effekt ausklingt statt
	# abrupt zu verschwinden.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_texture := CurveTexture.new()
	curve_texture.curve = curve
	process.scale_curve = curve_texture
	process.color = color
	particles.process_material = process

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.045, 0.045)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	particles.draw_pass_1 = mesh

	add_child(particles)


func _build_light(color: Color) -> void:
	# Nur bei Treffern mit Funken — ein Einschlag im Schnee leuchtet nicht.
	if kind == Kind.WORLD:
		return

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.4
	light.omni_range = 3.0
	add_child(light)

	# Schnell ausblenden, sonst wirkt es wie eine Lampe statt wie ein Funke.
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.12)
