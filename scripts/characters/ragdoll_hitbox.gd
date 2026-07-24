## Ein Ragdoll-Kasten, der auch nach dem Tod noch Treffer registriert.
##
## OHNE DAS: RagdollRig._on_died() schaltet die CharacterHitbox-Trefferzonen
## der lebenden Figur ab (collision_layer = 0, siehe dort), und ein nackter
## RigidBody3D-Kasten hat keine take_hit()-Methode — Projectile._apply_
## damage() findet also niemanden, an den es den Treffer weiterreichen kann
## (siehe collider.has_method("take_hit")), und ein Schuss auf die Leiche
## verpufft wirkungslos wie gegen eine Wand.
##
## KEINE GESUNDHEITSAENDERUNG MEHR NOETIG: HealthSystem.apply_damage() gibt
## bei einer bereits toten Figur ohnehin sofort 0 zurueck (siehe dort,
## "if is_dead ... return 0.0") — hier geht es nur noch um die Optik: eine
## weitere Wunde, weiteres Blut, genau an der Stelle, die diesmal getroffen
## wurde (siehe RagdollRig.take_hit_on_corpse()).
class_name RagdollHitbox
extends RigidBody3D

var rig: RagdollRig
var part: HealthSystem.Part


func take_hit(ammo: AmmoData, distance: float, point: Vector3, direction: Vector3) -> Ballistics.HitResult:
	return rig.take_hit_on_corpse(self, ammo, distance, point, direction)
