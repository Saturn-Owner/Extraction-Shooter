## Pulverdampf vor der Mündung.
##
## Bei Dauerfeuer steht nach ein paar Sekunden eine Wolke genau dort, wo man
## hinschaut — und man sieht das Ziel nicht mehr.
##
## ---------------------------------------------------------------------------
## DER DAMPF BLEIBT IN DER WELT STEHEN
##
## `local_coords = false`: Ausgestossene Schwaden hängen dort, wo sie entstanden
## sind, und ziehen langsam ab. Nur der Emitter selbst folgt der Mündung.
##
## Das IST der Nachteil, und es ist der lernbare Teil daran: Der Dampf steht in
## deiner Ziellinie, solange du draufhältst — trittst du zur Seite, siehst du
## wieder. Klebte er stattdessen an der Kamera, bekäme man ihn durch nichts
## los, und das läse sich als Fehler statt als Mechanik.
##
## ---------------------------------------------------------------------------
## EIN EMITTER, NICHT EINE WOLKE PRO SCHUSS
##
## MuzzleFlash legt pro Schuss einen Knoten an, der sich nach 0,36 s selbst
## entfernt — bei 750 Schuss/min sind das vier bis fünf gleichzeitig. Dampf
## muss aber Sekunden stehen; das wären dreissig Knoten mit je eigenem
## Partikelmaterial. Ein Emitter mit steuerbarer Rate ist billiger und ergibt
## eine zusammenhängende Wolke statt dreissig Einzelpuffs.
class_name PowderSmoke
extends GPUParticles3D

## Wie lange eine Schwade steht.
const LIFETIME := 2.6

## Obergrenze. Dauerfeuer darf die Bildrate nicht auffressen.
const MAX_PARTICLES := 48

const COLOR := Color(0.72, 0.71, 0.68)


func _ready() -> void:
	# Der eigentliche Kern: Partikel bleiben in Weltkoordinaten.
	local_coords = false

	amount = MAX_PARTICLES
	lifetime = LIFETIME
	explosiveness = 0.0
	randomness = 0.6
	emitting = false

	# OHNE GROSSZUEGIGE HUELLE VERSCHWINDET DER DAMPF. Mit local_coords = false
	# driften die Schwaden aus dem Bereich des Emitters heraus, und Godot
	# schneidet sie dann weg, sobald der Emitter selbst aus dem Bild ist.
	visibility_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))

	process_material = _make_process_material()
	draw_pass_1 = _make_mesh()


func _make_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()

	# Nach vorn aus dem Lauf, wie das Mündungsfeuer.
	material.direction = Vector3(0.0, 0.0, -1.0)
	material.spread = 22.0
	material.initial_velocity_min = 0.9
	material.initial_velocity_max = 2.0

	# Pulverdampf ist warm und steigt. Sehr langsam, sonst sieht es aus wie
	# Rauchzeichen statt wie eine stehende Wolke.
	# Sehr langsam nach oben. Zieht der Dampf schnell ab, haengt er nie dort,
	# wo man hinschaut — und genau das soll er.
	material.gravity = Vector3(0.0, 0.16, 0.0)
	material.damping_min = 1.4
	material.damping_max = 2.2

	# KLEIN ANFANGEN, GROSS WERDEN. Die Mündung sitzt 55 cm vor der Kamera —
	# eine Schwade, die dort schon 20 cm gross ist, füllt ein Viertel des
	# Bildes und steht einem sofort im Auge statt vor dem Lauf.
	material.scale_min = 0.35
	material.scale_max = 0.7
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.25))
	growth.add_point(Vector2(0.35, 1.0))
	growth.add_point(Vector2(1.0, 1.6))
	var growth_texture := CurveTexture.new()
	growth_texture.curve = growth
	material.scale_curve = growth_texture

	# Aufblenden und wieder verschwinden, sonst ploppen die Schwaden.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	fade.colors = PackedColorArray([
		Color(COLOR.r, COLOR.g, COLOR.b, 0.0),
		Color(COLOR.r, COLOR.g, COLOR.b, 0.55),
		Color(COLOR.r, COLOR.g, COLOR.b, 0.0),
	])
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture

	material.angle_min = -180.0
	material.angle_max = 180.0
	material.angular_velocity_min = -18.0
	material.angular_velocity_max = 18.0

	return material


func _make_mesh() -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.46, 0.46)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = COLOR
	material.albedo_texture = make_soft_dot()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.disable_receive_shadows = false
	# Weicher Uebergang, wo die Schwade eine Wand schneidet — sonst gibt es
	# eine harte Kante quer durch die Wolke.
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.6
	mesh.material = material
	return mesh


## Setzt den Emitter an die Mündung und regelt die Dichte.
##
## `amount_ratio` skaliert die aktive Partikelzahl, ohne das System neu
## aufzubauen — anders als `amount` zu ändern, was alle laufenden Schwaden
## wegwerfen würde.
func follow(muzzle: Vector3, forward: Basis, density: float) -> void:
	global_position = muzzle
	global_basis = forward
	amount_ratio = clampf(density, 0.0, 1.0)
	emitting = density > 0.01


## Weicher runder Fleck als Partikeltextur.
##
## OHNE DAS SIEHT MAN DIE VIERECKE. Ein untexturiertes Quad hat harte Kanten,
## und bei halbdurchsichtigen Partikeln liest das Auge sie sofort als
## uebereinanderliegende Pappstuecke statt als Wolke. Der Verlauf blendet zum
## Rand hin aus, dann bleibt nur die Form uebrig.
static func make_soft_dot() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.55),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture
