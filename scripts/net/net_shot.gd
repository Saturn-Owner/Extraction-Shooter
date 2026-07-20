## Der autoritative Schuss auf dem Server.
##
## Der Client feuert für das GEFÜHL: Mündungsfeuer, Rückstoß, Leuchtspur —
## aber seine Geschosse treffen nur die Welt. Ob ein SPIELER getroffen wurde,
## entscheidet allein diese Datei: Sie verschießt auf dem Server dieselben
## echten Projektile (Flugzeit, Fallkurve, Luftwiderstand — kein Hitscan)
## gegen die Trefferzonen der Avatare. Der Treffer läuft dann durch genau
## dieselbe Kette wie im Einzelspieler: CharacterHitbox.take_hit →
## BlockyCharacter.take_hit_on_part → Ballistics.resolve_hit →
## HealthSystem.apply_damage.
##
## Die Streuung wird hier NEU gewürfelt, nicht vom Client übernommen: Wer die
## Trefferentscheidung hat, würfelt auch — sonst schickt ein präparierter
## Client einfach immer Streuung null.
class_name NetShot

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")
## Welt und Trefferzonen — dieselbe Maske wie Weapon.projectile_mask im Solo.
const HIT_MASK := 1 | 4


## Feuert einen kompletten Schuss (bei Schrot: alle Kugeln).
## `on_hit` bekommt (collider, point, result, direction) für jede Kugel,
## die etwas trifft.
static func fire(parent: Node, shooter: Node3D, weapon_data: WeaponData,
		ammo: AmmoData, origin: Vector3, direction: Vector3, aiming: bool,
		on_hit: Callable) -> void:
	var speed := weapon_data.get_muzzle_velocity(ammo)
	for i in range(maxi(1, ammo.pellet_count)):
		var dir := apply_spread(direction, weapon_data, ammo, aiming, i)
		var projectile: Projectile = PROJECTILE_SCENE.instantiate()
		# Auf dem Server sieht niemand zu — Leuchtspur und Funken entfallen.
		projectile.visuals_enabled = false
		parent.add_child(projectile)
		projectile.launch(ammo, origin, dir, speed, shooter, HIT_MASK)
		projectile.hit_something.connect(
			func(collider: Node, point: Vector3, result: Ballistics.HitResult) -> void:
				on_hit.call(collider, point, result, dir))


## Streuung aus Waffenpräzision und Munition — dieselbe Rechnung wie
## Weapon._apply_spread(), nur ohne Waffenknoten: Der Server hat keinen.
## Wer hier etwas ändert, ändert es auch dort, sonst streuen Client-Spur
## und Server-Wahrheit verschieden weit.
static func apply_spread(direction: Vector3, weapon_data: WeaponData,
		ammo: AmmoData, aiming: bool, pellet_index: int) -> Vector3:
	var spread_deg := weapon_data.accuracy_moa / 60.0
	if aiming:
		spread_deg *= weapon_data.ads_spread_multiplier
	if ammo.pellet_count > 1 and pellet_index > 0:
		spread_deg += ammo.pellet_spread_degrees

	if spread_deg <= 0.0:
		return direction

	var angle := deg_to_rad(spread_deg)
	var perpendicular := direction.cross(Vector3.UP)
	if perpendicular.length_squared() < 0.001:
		perpendicular = direction.cross(Vector3.RIGHT)
	perpendicular = perpendicular.normalized()

	var roll := randf() * TAU
	var axis := perpendicular.rotated(direction.normalized(), roll)
	return direction.rotated(axis, randf() * angle).normalized()
