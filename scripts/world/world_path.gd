## Waldwege quer durchs Gelaende.
##
## Ein Trampelpfad ist keine Gerade — er schlingert leicht, folgt aber im
## Grossen einer Richtung von einem Kartenrand zum anderen. Baeume und Haeuser
## halten Abstand von ihm (siehe schneekarte.gd), sonst waechst ein Baum
## mitten auf dem Weg oder ein Haus verbaut ihn.
##
## ---------------------------------------------------------------------------
## WARUM EINE EIGENE, HOEHENFOLGENDE MESH STATT WorldParts.flat()
##
## WorldParts.flat() ist ein flacher Quader fuer ebene Flaechen (Kaimauer,
## Strasse im Hafen) — hier ist das Gelaende aber nicht eben, sondern hat
## echte Huegel (TerrainGenerator). Ein starrer Quader wuerde an Haengen
## entweder ueber dem Boden schweben oder im Boden versinken. Der Weg wird
## deshalb aus denselben Hoehenwerten gebaut wie das Gelaende selbst
## (TerrainGenerator.sample()) — genau wie Haeuser und Baeume ihre Standhoehe
## daraus beziehen.
class_name WorldPath
extends RefCounted

## Breite eines Weges in Metern. Schmal genug fuer einen Trampelpfad, breit
## genug, dass zwei Spieler nebeneinander hindurchpassen.
const WIDTH := 3.0

## Wie weit die sichtbare Wegflaeche ueber der Gelaendehoehe schwebt — gegen
## Z-Fighting mit dem Gelaende darunter, aber knapp genug, dass es wie
## aufgetragener Belag aussieht statt wie eine zweite Ebene.
const LIFT := 0.03


## Erzeugt `count` Wege als Liste von Wegpunkt-Listen (Array[Array[Vector2]],
## lokale Kartenkoordinaten, Kartenmitte = 0). Start und Ziel jedes Weges
## liegen an zufaelligen Stellen am Kartenrand, dazwischen schlingert der Pfad
## statt geradewegs durchzulaufen — eine Luftlinie durch einen Wald sieht nach
## Lineal aus, kein Trampelpfad.
static func generate(rng: RandomNumberGenerator, map_size: Vector2, count: int,
		step: float = 6.0, wander_deg: float = 35.0) -> Array:
	var paths: Array = []
	for i in range(count):
		var start := _edge_point(rng, map_size)
		var target := _edge_point(rng, map_size)
		paths.append(_walk(rng, start, target, step, wander_deg))
	return paths


static func _edge_point(rng: RandomNumberGenerator, map_size: Vector2) -> Vector2:
	var half := map_size * 0.5
	match rng.randi() % 4:
		0: return Vector2(-half.x, rng.randf_range(-half.y, half.y))
		1: return Vector2(half.x, rng.randf_range(-half.y, half.y))
		2: return Vector2(rng.randf_range(-half.x, half.x), -half.y)
		_: return Vector2(rng.randf_range(-half.x, half.x), half.y)


## Ein schlingernder Weg von `start` nach `target`.
##
## ---------------------------------------------------------------------------
## JEDEN SCHRITT FRISCH ZUM ZIEL AUSRICHTEN, NICHT DIE RICHTUNG FORTSCHREIBEN
##
## Ein frueherer Versuch schrieb die Richtung fort (vorherige Richtung
## behalten, nur leicht zum Ziel nachgezogen, dann zufaellig gedreht) — das
## sah nach echtem Trampelpfad aus, konnte sich aber in einem echten
## Renderbild nachweislich zu einer in sich verschlungenen Schleife
## aufschaukeln, die nie beim Ziel ankam, statt einfach zu wandern (die
## Zielkorrektur war zu schwach, um die aufgebaute Drehung wieder
## auszugleichen). Hier zeigt JEDER Schritt frisch zum Ziel und wird danach
## nur um `wander_deg` gedreht — die Vorwaertskomponente bleibt damit fuer
## wander_deg < 90 Grad immer positiv, der Weg kann sich rechnerisch also
## nicht mehr um sich selbst wickeln, schlingert aber trotzdem sichtbar, weil
## der Schlingerwinkel sich von Schritt zu Schritt neu auswuerfelt.
static func _walk(rng: RandomNumberGenerator, start: Vector2, target: Vector2,
		step: float, wander_deg: float) -> Array:
	var waypoints: Array = [start]
	var current := start

	# Obergrenze gegen Endlosschleifen, falls Rundungsfehler den Weg nie
	# nah genug ans Ziel bringen wuerden.
	var max_steps := int(start.distance_to(target) / step) * 3 + 10
	for i in range(max_steps):
		if current.distance_to(target) <= step:
			break
		var to_target := (target - current).normalized()
		var jitter := deg_to_rad(rng.randf_range(-wander_deg, wander_deg))
		current += to_target.rotated(jitter) * step
		waypoints.append(current)

	waypoints.append(target)
	return waypoints


## Kuerzester Abstand von `point` zu irgendeinem Teilstueck von `path` — damit
## weichen Baeume und Haeuser dem Weg aus (siehe schneekarte.gd), ohne dass
## diese Klasse wissen muss, wer sie aufruft.
static func distance_to_path(point: Vector2, path: Array) -> float:
	var closest := INF
	for i in range(path.size() - 1):
		closest = minf(closest, _distance_to_segment(point, path[i], path[i + 1]))
	return closest


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_sq := segment.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(a + segment * t)


## Baut die sichtbare Wegflaeche als Dreiecksleiste — pro Teilstueck ein
## Viereck aus vier Punkten, deren Hoehe einzeln aus `heights` abgetastet wird
## (nicht nur an der Mittellinie: sonst schneidet ein 3 m breiter Weg quer
## ueber einen Hang durch den sichtbaren Boden).
##
## Wickelreihenfolge (a, b, c) / (b, d, c) — dieselbe, an einem echten
## Renderbild nachgemessene Reihenfolge wie in TerrainGenerator._build_mesh(),
## aus demselben Grund: Godots Rueckseitenausblendung fuer dieses Kamera-/
## Weltachsen-Setup verwirft die geometrisch "logisch" wirkende Alternative.
static func build_mesh(path: Array, heights: PackedFloat32Array, samples: int,
		map_size: Vector2, mat: Material) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var forward := b - a
		if forward.length() < 0.001:
			continue
		# ACHTUNG WICKELREIHENFOLGE: (forward.y, -forward.x) und nicht die
		# "naheliegende" (-forward.y, forward.x) — mit der falschen Senkrechten
		# zeigt das Kreuzprodukt aus (a+side)-(a-side) und (b-side)-(a-side)
		# nach +Y statt nach -Y, und genau das war der Grund, warum das
		# Gelaende einmal komplett unsichtbar war (siehe TerrainGenerator.
		# _build_mesh()). Nachgerechnet, nicht geraten: fuer JEDE Richtung
		# `forward` ergibt cross((-forward.y, 0, forward.x), (forward.x, 0,
		# forward.z)) immer +Y — die andere Senkrechte ist die einzig richtige.
		var side := Vector2(forward.y, -forward.x).normalized() * (WIDTH * 0.5)

		var v0 := _lifted(a - side, heights, samples, map_size)
		var v1 := _lifted(a + side, heights, samples, map_size)
		var v2 := _lifted(b - side, heights, samples, map_size)
		var v3 := _lifted(b + side, heights, samples, map_size)

		# Flaechennormale aus den tatsaechlichen (unterschiedlich hohen) Ecken,
		# statt pauschal nach oben zu zeigen — sonst schattiert ein Weg am
		# Hang wie eine ebene Flaeche.
		var normal := (v2 - v0).cross(v1 - v0).normalized()
		if normal.y < 0.0:
			normal = -normal

		var base := vertices.size()
		vertices.append(v0); vertices.append(v1); vertices.append(v2); vertices.append(v3)
		normals.append(normal); normals.append(normal); normals.append(normal); normals.append(normal)

		indices.append(base); indices.append(base + 1); indices.append(base + 2)
		indices.append(base + 1); indices.append(base + 3); indices.append(base + 2)

	var view := MeshInstance3D.new()
	view.name = "Weg"
	if vertices.is_empty():
		return view

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	view.mesh = mesh
	view.material_override = mat
	return view


static func _lifted(local_xz: Vector2, heights: PackedFloat32Array, samples: int,
		map_size: Vector2) -> Vector3:
	var h := TerrainGenerator.sample(heights, samples, map_size, local_xz)
	return Vector3(local_xz.x, h + LIFT, local_xz.y)


## Getrampelter Schnee/Erde-Ton fuer die Wegflaeche — dunkler und rauer als
## der umgebende Schnee. Bewusst ohne eigene Fototextur (dieselbe Begruendung
## wie bei WorldParts._surface): ein frischer Clone soll den Weg sehen, ohne
## dass irgendwo eine Texturdatei fehlen koennte.
static func trail_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.52, 0.47)
	mat.roughness = 0.95
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 2.0
	return mat
