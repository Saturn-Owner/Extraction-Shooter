## Fadenkreuz mit Treffer-Rückmeldung.
##
## Zwei Dinge, die beim Schiessgefühl den grössten Unterschied machen:
##
## 1. Das Fadenkreuz geht bei Rückstoss auf und schliesst sich wieder.
##    Der Spieler SIEHT dadurch, dass Dauerfeuer ungenau wird, statt es
##    nur zu erraten.
## 2. Die Trefferanzeige (kurzes X) bestätigt einen Treffer sofort —
##    auf 300 m sieht man sonst nicht, ob man getroffen hat.
##
## Die Farbe unterscheidet, ob die Rüstung gehalten hat. Das ist die
## wichtigste taktische Information im Feuergefecht: Muss ich die Munition
## wechseln oder weiter draufhalten?
class_name Crosshair
extends Control

const COLOR_NORMAL := Color(1, 1, 1, 0.7)
const COLOR_HIT := Color(1, 1, 1, 0.95)
const COLOR_ARMOR_STOPPED := Color(1.0, 0.85, 0.3, 0.95)
const COLOR_PENETRATED := Color(1.0, 0.45, 0.2, 0.95)
const COLOR_FLESH := Color(1.0, 0.25, 0.2, 0.95)

## Grundabstand der vier Striche vom Mittelpunkt.
@export var base_gap: float = 7.0
@export var line_length: float = 9.0
@export var line_width: float = 2.0

## Wie weit das Fadenkreuz bei Rückstoss maximal aufgeht.
@export var max_bloom: float = 42.0

## Wie schnell es sich wieder schliesst.
@export var recovery_speed: float = 55.0

var _bloom: float = 0.0
var _hit_timer: float = 0.0
var _hit_color: Color = COLOR_HIT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Wird bei jedem Schuss aufgerufen — das Fadenkreuz geht auf.
func add_bloom(amount: float) -> void:
	_bloom = minf(_bloom + amount, max_bloom)


## Wird bei jedem Treffer aufgerufen.
func show_hit(result: Ballistics.HitResult) -> void:
	_hit_timer = 0.22
	if not result.was_armored:
		_hit_color = COLOR_FLESH
	elif result.penetrated:
		_hit_color = COLOR_PENETRATED
	else:
		_hit_color = COLOR_ARMOR_STOPPED


func _process(delta: float) -> void:
	if _bloom > 0.0:
		_bloom = maxf(0.0, _bloom - recovery_speed * delta)
		queue_redraw()
	if _hit_timer > 0.0:
		_hit_timer = maxf(0.0, _hit_timer - delta)
		queue_redraw()
	elif is_zero_approx(_bloom):
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var gap := base_gap + _bloom

	# Vier Striche: oben, unten, links, rechts.
	var color := COLOR_NORMAL
	draw_line(center + Vector2(0, -gap), center + Vector2(0, -gap - line_length), color, line_width)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + line_length), color, line_width)
	draw_line(center + Vector2(-gap, 0), center + Vector2(-gap - line_length, 0), color, line_width)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + line_length, 0), color, line_width)

	# Mittelpunkt.
	draw_circle(center, 1.2, color)

	if _hit_timer <= 0.0:
		return

	# Trefferanzeige: diagonales X, das ausblendet.
	var fade := _hit_timer / 0.22
	var marker := _hit_color
	marker.a *= fade
	var d := 6.0 + (1.0 - fade) * 4.0
	draw_line(center + Vector2(-d, -d), center + Vector2(-d * 0.4, -d * 0.4), marker, 2.0)
	draw_line(center + Vector2(d, -d), center + Vector2(d * 0.4, -d * 0.4), marker, 2.0)
	draw_line(center + Vector2(-d, d), center + Vector2(-d * 0.4, d * 0.4), marker, 2.0)
	draw_line(center + Vector2(d, d), center + Vector2(d * 0.4, d * 0.4), marker, 2.0)
