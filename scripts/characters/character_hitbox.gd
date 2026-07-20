## Eine Trefferzone am Körper: ein Kasten, der weiss, welches Körperteil er ist.
##
## ---------------------------------------------------------------------------
## WARUM EIN KÖRPER UND KEINE AREA3D
##
## `Projectile._check_segment()` fragt die Physik mit `collide_with_areas =
## false` ab. Eine Area3D wäre für Geschosse schlicht unsichtbar — die Kugel
## flöge hindurch, und niemand käme darauf, warum ausgerechnet der Kopf nie
## getroffen wird.
##
## AnimatableBody3D statt StaticBody3D, weil sich diese Kästen mit der Figur
## bewegen sollen. Ein StaticBody, den man jeden Frame verschiebt, ist genau
## das, wovor die Godot-Dokumentation warnt: Die Physik geht davon aus, dass er
## stehen bleibt, und aktualisiert ihre Suchstruktur entsprechend träge.
##
## ---------------------------------------------------------------------------
## DIESE KLASSE ENTSCHEIDET NICHTS
##
## Sie nimmt den Treffer entgegen und reicht ihn samt Körperteil an die Figur
## weiter. Was der Treffer anrichtet, rechnet `Ballistics`, und ob jemand
## stirbt, entscheidet `HealthSystem` — beides gehört nicht in einen Kasten.
##
## Das ist dieselbe Trennung wie bei der Waffe: Der Client meldet "hier wurde
## getroffen", die Auswertung passiert an einer Stelle. Im Mehrspielerbetrieb
## läuft die später auf dem Server.
class_name CharacterHitbox
extends AnimatableBody3D

## Welches Körperteil dieser Kasten abdeckt.
var part: HealthSystem.Part = HealthSystem.Part.CHEST

## Die Figur, an der dieser Kasten hängt. Sie wertet den Treffer aus.
var character: BlockyCharacter


## Wird vom Geschoss gerufen — dieselbe Signatur wie bei TargetDummy, damit
## `Projectile._apply_damage()` nichts über Figuren wissen muss.
func take_hit(ammo: AmmoData, distance: float, point: Vector3,
		direction: Vector3) -> Ballistics.HitResult:
	if character == null:
		return Ballistics.HitResult.new()
	return character.take_hit_on_part(part, ammo, distance, point, direction)
