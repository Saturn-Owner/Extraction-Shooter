## Testgelände für die Spielerbewegung.
##
## Zweck: Bewegung ausprobieren und Werte im Blick haben. Das ist KEIN
## Spielinhalt, sondern eine Werkbank — sie fliegt raus, sobald es echte
## Level gibt.
##
## Das HUD gibt es aus einem bestimmten Grund: Claude kann nicht fühlen, ob
## sich die Bewegung richtig anfühlt. Wenn ihr konkrete Zahlen seht ("Sprint
## liegt bei 5.2, fühlt sich zu schnell an"), lässt sich das gezielt ändern —
## bei "fühlt sich komisch an" kann niemand etwas tun.
##
## Steuerung:
##   WASD          Gehen
##   Shift         Sprinten (kostet Ausdauer, nur vorwärts)
##   Strg          Ducken
##   Leertaste     Springen
##   Esc           Maus freigeben
##   1 / 2         Traglast erhöhen / verringern (zum Ausprobieren)
##   R             Zurück zum Startpunkt
extends Node3D

@onready var _player: PlayerController = $Player
@onready var _label: Label = $HUD/DebugPanel/DebugLabel

var _spawn: Vector3


func _ready() -> void:
	_spawn = _player.global_position
	# Startgewicht: leeres Inventar plus etwas Ausrüstung am Körper.
	_player.carried_weight_kg = 6.0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	match (event as InputEventKey).physical_keycode:
		KEY_1:
			_player.carried_weight_kg = minf(_player.carried_weight_kg + 4.0, 80.0)
		KEY_2:
			_player.carried_weight_kg = maxf(_player.carried_weight_kg - 4.0, 0.0)
		KEY_R:
			_player.global_position = _spawn
			_player.velocity = Vector3.ZERO


func _process(_delta: float) -> void:
	var horizontal := Vector3(_player.velocity.x, 0.0, _player.velocity.z)

	var haltung := "stehend"
	if _player.is_crouching:
		haltung = "geduckt"
	elif _player.is_sprinting:
		haltung = "sprintend"

	_label.text = "\n".join([
		"Tempo:      %.2f / %.2f m/s" % [horizontal.length(), _player.get_current_max_speed()],
		"Haltung:    %s" % haltung,
		"Ausdauer:   %.0f / %.0f" % [_player.stamina, _player.max_stamina],
		"Traglast:   %.1f kg  (Faktor %.2f)" % [_player.carried_weight_kg, _player.get_weight_factor()],
		"Boden:      %s" % ("ja" if _player.is_on_floor() else "nein"),
		"",
		"1/2 = Gewicht  |  R = Reset  |  Esc = Maus",
	])
