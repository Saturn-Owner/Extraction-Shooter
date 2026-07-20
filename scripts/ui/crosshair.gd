## Das Fadenkreuz.
##
## ---------------------------------------------------------------------------
## ES SITZT IN DER BILDMITTE, UND DAS IST KEINE ANNAHME
##
## `Weapon.get_aim_point()` schiesst seinen Zielstrahl von der KAMERA entlang
## deren Blickachse — nicht aus der Mündung. Der Treffpunkt liegt damit immer
## genau dort, wohin die Kamera zeigt, also in der Bildmitte.
##
## Dadurch stimmt das Fadenkreuz auch bei Rückstoss: Der schiebt die Kamera,
## und die Bildmitte wandert mit. Ein Fadenkreuz, das stattdessen der Mündung
## folgte, müsste all das nachrechnen und läge trotzdem daneben, sobald die
## Waffe seitlich am Körper sitzt.
##
## `verify_player` prüft genau das nach: Der Zielpunkt der Waffe muss sich auf
## die Bildmitte zurückrechnen lassen.
##
## ---------------------------------------------------------------------------
## LEICHT, NICHT AUFDRINGLICH
##
## Vier kurze Striche mit einer Lücke in der Mitte. Die Lücke ist der Punkt:
## Ein durchgezogenes Kreuz verdeckt genau das, worauf man zielt — bei einem
## Kopf auf 100 m ist das der Kopf.
##
## Der dunkle Saum darunter ist kein Schmuck. Ohne ihn verschwinden weisse
## Striche vor Schnee und Himmel vollständig, und das ist in diesem Spiel die
## Hälfte aller Hintergründe.
class_name Crosshair
extends Control

## Länge eines Strichs.
const ARM_LENGTH := 7.0

## Abstand vom Mittelpunkt. Hier bleibt das Ziel frei.
const GAP := 4.0

const THICKNESS := 1.0
const OUTLINE := 2.0

const COLOR := Color(1.0, 1.0, 1.0, 0.72)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.42)


func _ready() -> void:
	# Über den ganzen Bildschirm, damit die Mitte wirklich die Bildmitte ist.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Sonst fängt es Mausklicks ab, und der Schuss löst nicht aus.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bei Grössenänderung neu zeichnen, sonst klebt es an der alten Mitte.
	resized.connect(queue_redraw)


func _draw() -> void:
	var centre := size * 0.5

	# Die vier Richtungen. Kein Punkt in der Mitte: Der verdeckt das Ziel.
	var directions := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

	# Erst alle Säume, dann alle Striche. Andersherum läge der Saum des
	# zweiten Strichs über dem ersten und liesse ihn angeknabbert aussehen.
	for direction: Vector2 in directions:
		draw_line(centre + direction * GAP,
			centre + direction * (GAP + ARM_LENGTH),
			OUTLINE_COLOR, OUTLINE)
	for direction: Vector2 in directions:
		draw_line(centre + direction * GAP,
			centre + direction * (GAP + ARM_LENGTH),
			COLOR, THICKNESS)
