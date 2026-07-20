## Mündungsfeuer: kurzer Lichtblitz plus Funkenwolke nach vorn.
##
## Sehr kurz gehalten (unter 60 ms). Ein zu langes Mündungsfeuer wirkt
## sofort billig und blendet bei Dauerfeuer.
##
## Wie ImpactEffect komplett im Code aufgebaut, damit es sich je nach Waffe
## skalieren lässt — eine Pistole blitzt anders als ein Scharfschützengewehr.
class_name MuzzleFlash
extends Node3D

const DURATION := 0.06
const COLOR := Color(1.0, 0.82, 0.45)


## scale_factor skaliert mit dem Kaliber: grosse Waffen blitzen stärker.
##
## Die Transformation wird gemerkt und erst in _ready() gesetzt — global_transform
## funktioniert nur, wenn der Knoten wirklich im Szenenbaum haengt.
static func spawn(parent: Node, at: Transform3D, scale_factor: float = 1.0) -> MuzzleFlash:
	var flash := MuzzleFlash.new()
	flash.intensity = clampf(scale_factor, 0.4, 2.5)
	flash._spawn_transform = at
	parent.add_child(flash)
	return flash


var intensity: float = 1.0

var _spawn_transform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	global_transform = _spawn_transform
	_build_light()
	_build_particles()
	get_tree().create_timer(DURATION * 6.0).timeout.connect(queue_free)


func _build_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 4.5 * intensity
	light.omni_range = 6.0 * intensity
	add_child(light)

	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, DURATION)


func _build_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = int(10 * intensity)
	particles.lifetime = 0.09
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true

	var process := ParticleProcessMaterial.new()
	# Nach vorn aus dem Lauf heraus.
	process.direction = Vector3(0, 0, -1)
	process.spread = 18.0
	process.initial_velocity_min = 6.0 * intensity
	process.initial_velocity_max = 14.0 * intensity
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5 * intensity
	process.scale_max = 1.4 * intensity
	process.color = COLOR
	particles.process_material = process

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.09, 0.09) * intensity
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = COLOR
	# Weicher Fleck statt hartem Viereck. Bei Dauerfeuer lagen sonst lauter
	# gelbe Kloetze uebereinander im Bild.
	material.albedo_texture = PowderSmoke.make_soft_dot()
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 4.0
	mesh.material = material
	particles.draw_pass_1 = mesh

	add_child(particles)
