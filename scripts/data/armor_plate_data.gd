## Eine einzelne Schutzplatte, die in einen Plattenträger eingesetzt wird.
##
## Bewusste Designentscheidung (aus der Anforderungsanalyse):
## Es gibt KEIN klassisches Rüstungs-Stufensystem, bei dem "Level 5" immer
## besser ist als "Level 4". Stattdessen:
##
##   - Rüstung deckt nur eine FLÄCHE ab. Ein Treffer daneben trifft ungeschützt.
##   - Platten NUTZEN SICH AB. Jeder Treffer zählt, auch ein gestoppter.
##   - Starke Munition (M995) geht auch durch gute Platten.
##
## Dadurch fühlt sich Rüstung wie eine Chance an, nicht wie Unverwundbarkeit —
## und der Spieler bleibt jederzeit sterblich.
class_name ArmorPlateData
extends ItemData

## Welche Körperzone die Platte abdeckt.
enum Coverage {
	CHEST_FRONT, ## Brust vorne — der häufigste Treffer
	CHEST_BACK,  ## Rücken
	SIDE_LEFT,   ## Flanke links
	SIDE_RIGHT,  ## Flanke rechts
	HEAD,        ## Helm-Einsatz
}

@export_group("Schutzwirkung")

## Schutzklasse 1-6, angelehnt an reale Normen.
## Wird gegen AmmoData.penetration_power gerechnet:
##   Grobe Faustregel — penetration_power muss ungefähr
##   (armor_class * 10) erreichen, um zuverlässig durchzukommen.
## Eine Klasse-4-Platte stoppt also typischerweise alles unter Pen 40,
## aber M995 mit Pen 53 geht durch. Genau so ist es gewollt.
@export_range(1, 6) var armor_class: int = 4

## Wie viel Beschuss die Platte aushält, bevor sie wirkungslos ist.
## Sinkt mit jedem Treffer um AmmoData.armor_damage_percent.
@export_range(1.0, 200.0) var max_durability: float = 40.0

## Welche Zone geschützt wird.
@export var coverage: Coverage = Coverage.CHEST_FRONT

## Ab welcher Restlebensdauer (in Prozent) die Schutzwirkung merklich
## nachlässt. Darunter sinkt die effektive Schutzklasse.
@export_range(0.0, 1.0) var degradation_threshold: float = 0.5

@export_group("Nachteile")

## Bewegungseinschränkung in Prozent. Schwere Platten sollen wehtun —
## sonst trägt jeder immer die stärkste.
@export_range(0.0, 50.0) var movement_penalty_percent: float = 5.0

## Wie sehr die Platte beim Zielen und Drehen behindert.
@export_range(0.0, 50.0) var ergonomics_penalty: float = 3.0

## Wärmedämmung. Im Schnee-Setting ist das ein echter Vorteil —
## eine schwere Platte hält auch warm. Kleiner Ausgleich zum Gewicht.
@export_range(0.0, 10.0) var insulation_bonus: float = 0.5


## Effektive Schutzklasse bei aktuellem Zustand.
## Eine halb zerschossene Platte schützt schlechter — das macht
## Reparatur in der Werkstatt (Meilenstein 8) relevant.
func get_effective_class(current_durability: float) -> float:
	if current_durability <= 0.0:
		return 0.0
	var ratio := current_durability / max_durability
	if ratio >= degradation_threshold:
		return float(armor_class)
	# Unterhalb der Schwelle linear bis auf 0 abfallen lassen.
	var falloff := ratio / degradation_threshold
	return float(armor_class) * falloff


func get_type_label() -> String:
	return "Schutzplatte  —  Klasse %d" % armor_class


func get_info_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Schutzklasse: %d" % armor_class)
	lines.append("Haltbarkeit:  %.0f" % max_durability)
	lines.append("Abdeckung:    %s" % Coverage.keys()[coverage])
	lines.append("Bremst um:    %.0f %%" % movement_penalty_percent)
	lines.append_array(super())
	return lines


func validate() -> Array[String]:
	var problems := super()
	if category != Category.ARMOR_PLATE:
		problems.append("category sollte ARMOR_PLATE sein")
	return problems
