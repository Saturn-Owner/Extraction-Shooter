## Hunger, Durst und Körpertemperatur.
##
## ---------------------------------------------------------------------------
## WARUM DIESE DREI SICH UNTERSCHIEDLICH ANFÜHLEN SOLLEN
##
##   Hunger   langsam, planbar. Man sieht ihn kommen und kann entscheiden,
##            ob man den Riegel jetzt isst oder ihn verkauft.
##   Durst    schneller als Hunger. Wasser ist im Schnee überall und nirgends —
##            geschmolzener Schnee kühlt aus, das ist der Haken.
##   Kälte    hängt nicht an der Zeit, sondern an der Kleidung. Wer leicht
##            reist, friert. Das ist die Gegenrechnung zum Tempo-Bonus für
##            ein leeres Inventar.
##
## Alle drei ziehen bei null Trefferpunkte ab, aber an unterschiedlichen
## Stellen: Hunger und Durst am Bauch, Kälte an Armen und Beinen (Erfrierung
## beginnt außen). So erzählt schon der Schadensort, woran man gerade stirbt.
##
## HINWEIS ZUM NETZWERK: Läuft später ausschließlich auf dem Server.
class_name SurvivalStats
extends Node

signal hunger_changed(value: float)
signal thirst_changed(value: float)
signal temperature_changed(celsius: float)
signal starving()
signal dehydrated()
signal freezing()

@export_group("Hunger")

@export var max_hunger: float = 100.0

## Verbrauch pro Minute. Bei 2.5 hält eine volle Anzeige rund 40 Minuten —
## länger als ein Raid, aber kurz genug, dass Verpflegung im Lager zählt.
@export var hunger_per_minute: float = 2.5

@export_group("Durst")

@export var max_thirst: float = 100.0

## Bewusst schneller als Hunger: Durst soll der Wert sein, der einen zuerst
## zurück ins Lager treibt.
@export var thirst_per_minute: float = 4.0

@export_group("Temperatur")

## Körpertemperatur in Grad. 37 ist gesund, unter 35 wird es gefährlich.
@export var normal_temperature: float = 37.0
@export var danger_temperature: float = 35.0
@export var critical_temperature: float = 32.0

## Außentemperatur der Karte. Eine Schneelandschaft ist unbarmherzig.
@export var ambient_temperature: float = -18.0

## Wie schnell der Körper ohne Isolierung auskühlt (Grad pro Minute bei
## 0 Isolierung und -18 Grad außen).
@export var cooling_per_minute: float = 1.1

## Wie viel Isolierung die getragene Kleidung liefert. Setzt die Ausrüstung.
var insulation: float = 0.0

## Ob der Spieler gerade in Deckung oder am Feuer steht — dann wärmt er auf.
var is_sheltered: bool = false

var hunger: float = 100.0
var thirst: float = 100.0
var temperature: float = 37.0

## Wird vom Gesundheitssystem gesetzt: ein zerschossener Bauch zehrt schneller.
var metabolism_multiplier: float = 1.0

## Schaden pro Sekunde, wenn ein Wert am Anschlag ist.
const STARVING_DAMAGE := 0.9
const DEHYDRATION_DAMAGE := 1.4
const FREEZING_DAMAGE := 1.2

var _was_starving := false
var _was_dehydrated := false
var _was_freezing := false


func reset() -> void:
	hunger = max_hunger
	thirst = max_thirst
	temperature = normal_temperature
	_was_starving = false
	_was_dehydrated = false
	_was_freezing = false
	hunger_changed.emit(hunger)
	thirst_changed.emit(thirst)
	temperature_changed.emit(temperature)


## Sofort gueltig — siehe HealthSystem._init().
func _init() -> void:
	reset()


## Noch einmal, sobald die im Editor gesetzten Werte angekommen sind.
## Die greifen erst NACH _init(), sonst stuende hier immer der Vorgabewert.
func _ready() -> void:
	reset()


## Fortschreiben. `delta` in Sekunden.
func tick(delta: float) -> void:
	var minutes := delta / 60.0

	_tick_hunger(minutes)
	_tick_thirst(minutes)
	_tick_temperature(minutes)


func _tick_hunger(minutes: float) -> void:
	if hunger <= 0.0:
		if not _was_starving:
			_was_starving = true
			starving.emit()
		return

	hunger = maxf(0.0, hunger - hunger_per_minute * metabolism_multiplier * minutes)
	hunger_changed.emit(hunger)
	if hunger <= 0.0:
		_was_starving = true
		starving.emit()


func _tick_thirst(minutes: float) -> void:
	if thirst <= 0.0:
		if not _was_dehydrated:
			_was_dehydrated = true
			dehydrated.emit()
		return

	thirst = maxf(0.0, thirst - thirst_per_minute * metabolism_multiplier * minutes)
	thirst_changed.emit(thirst)
	if thirst <= 0.0:
		_was_dehydrated = true
		dehydrated.emit()


## Die Temperatur strebt einem Zielwert entgegen, statt stur zu fallen.
##
## Dadurch pendelt sie sich bei gegebener Kleidung auf einem Niveau ein,
## statt unweigerlich gegen null zu laufen. Gute Kleidung heißt: man bleibt
## gesund. Schlechte heißt: man hat eine Frist, keinen Todesurteil.
func _tick_temperature(minutes: float) -> void:
	var target := normal_temperature

	if not is_sheltered:
		# Jeder Punkt Isolierung holt einen Teil des Unterschieds zur
		# Aussentemperatur zurueck.
		var exposure := clampf(1.0 - insulation * 0.1, 0.0, 1.0)
		var drop := (normal_temperature - ambient_temperature) * 0.35 * exposure
		target = normal_temperature - drop

	var speed := cooling_per_minute * minutes
	if target > temperature:
		# Aufwaermen geht schneller als Auskuehlen — sonst ist ein Fehler
		# nicht mehr zu korrigieren.
		speed *= 2.0

	var before := temperature
	temperature = move_toward(temperature, target, speed)
	if not is_equal_approx(before, temperature):
		temperature_changed.emit(temperature)

	if temperature <= critical_temperature and not _was_freezing:
		_was_freezing = true
		freezing.emit()
	elif temperature > danger_temperature:
		_was_freezing = false


## Wie viel Schaden dieser Zustand gerade verursacht, und wo.
## Gibt eine Liste aus {part, amount} zurueck — leer, wenn alles in Ordnung ist.
func get_damage_this_second() -> Array:
	var result: Array = []

	if hunger <= 0.0:
		result.append({part = HealthSystem.Part.STOMACH, amount = STARVING_DAMAGE})
	if thirst <= 0.0:
		result.append({part = HealthSystem.Part.STOMACH, amount = DEHYDRATION_DAMAGE})

	# Erfrierung beginnt aussen: erst Haende und Fuesse, nicht der Rumpf.
	if temperature <= critical_temperature:
		var share := FREEZING_DAMAGE / 4.0
		for part in [HealthSystem.Part.LEFT_ARM, HealthSystem.Part.RIGHT_ARM,
				HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG]:
			result.append({part = part, amount = share})

	return result


## Wie stark Kaelte das Tempo druekt. Zittern kostet Kraft, lange bevor es
## gefaehrlich wird — der Spieler soll es merken, bevor die Anzeige rot ist.
func get_cold_movement_penalty() -> float:
	if temperature >= danger_temperature:
		return 0.0
	var span := maxf(0.1, danger_temperature - critical_temperature)
	var ratio := clampf((danger_temperature - temperature) / span, 0.0, 1.0)
	return ratio * 0.30


func eat(amount: float) -> void:
	hunger = minf(max_hunger, hunger + amount)
	if hunger > 0.0:
		_was_starving = false
	hunger_changed.emit(hunger)


func drink(amount: float) -> void:
	thirst = minf(max_thirst, thirst + amount)
	if thirst > 0.0:
		_was_dehydrated = false
	thirst_changed.emit(thirst)


func get_hunger_ratio() -> float:
	return clampf(hunger / maxf(1.0, max_hunger), 0.0, 1.0)


func get_thirst_ratio() -> float:
	return clampf(thirst / maxf(1.0, max_thirst), 0.0, 1.0)


## 1.0 = warm, 0.0 = kritisch unterkuehlt. Fuer die Anzeige.
func get_warmth_ratio() -> float:
	var span := maxf(0.1, normal_temperature - critical_temperature)
	return clampf((temperature - critical_temperature) / span, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"hunger": hunger, "thirst": thirst, "temperature": temperature}


func from_dict(data: Dictionary) -> void:
	hunger = clampf(float(data.get("hunger", max_hunger)), 0.0, max_hunger)
	thirst = clampf(float(data.get("thirst", max_thirst)), 0.0, max_thirst)
	temperature = float(data.get("temperature", normal_temperature))
	hunger_changed.emit(hunger)
	thirst_changed.emit(thirst)
	temperature_changed.emit(temperature)
