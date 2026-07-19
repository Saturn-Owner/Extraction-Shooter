## Eine Verletzungsart.
##
## ---------------------------------------------------------------------------
## WARUM VERLETZUNGEN GETRENNT VON TREFFERPUNKTEN STEHEN
##
## Trefferpunkte sagen nur, wie nah man am Tod ist. Eine Verletzung sagt, WAS
## kaputt ist — und das ist die interessantere Information: Ein Bein mit 60 von
## 65 Trefferpunkten und einem Bruch ist schlimmer dran als eines mit 30 ohne.
##
## Jede Verletzung haengt an einem Koerperteil und wirkt LAUFEND, bis jemand
## sie behandelt. Sie geht nicht von selbst weg (ausser `heals_after_seconds`
## ist gesetzt). Genau das erzeugt die Entscheidung, um die es geht:
## weitermachen oder verbinden.
##
## Neue Verletzungsarten sind neue .tres-Dateien unter assets/data/injuries/,
## kein neuer Code.
class_name InjuryData
extends Resource

enum Kind {
	BLEED_LIGHT, ## Leichte Blutung — Verband
	BLEED_HEAVY, ## Starke Blutung — nur die Aderpresse haelt sie auf
	CUT,         ## Schnitt aus dem Nahkampf, blutet und schmerzt
	FRACTURE,    ## Knochenbruch — Schiene
}

@export var id: StringName = &""
@export var display_name: String = ""

@export_multiline var description: String = ""

@export var kind: Kind = Kind.BLEED_LIGHT

@export_group("Wirkung pro Sekunde")

## Blutverlust in Prozent des Volumens. Der eigentliche Killer: Eine starke
## Blutung bringt einen um, lange bevor die Trefferpunkte zur Neige gehen.
@export var blood_per_second: float = 0.0

## Zusaetzlicher Schaden am betroffenen Koerperteil.
@export var hp_per_second: float = 0.0

@export_group("Behinderung")

## Wie stark ein betroffenes BEIN das Tempo drueckt (0..1).
@export_range(0.0, 1.0) var movement_penalty: float = 0.0

## Wie stark ein betroffener ARM das Zielen stoert (0..1).
@export_range(0.0, 1.0) var aim_penalty: float = 0.0

## Ob Schmerzmittel die Behinderung voruebergehend wegnehmen.
##
## Bei einem Bruch ja — man laeuft dann auf einem gebrochenen Bein, weil man
## es nicht mehr spuert. Bei einer Blutung nein: Schmerzmittel stopfen kein
## Loch, und ein Spieler, der das glaubt, verblutet mit gutem Gefuehl.
@export var relieved_by_painkillers: bool = false

@export_group("Heilung")

## Nach wie vielen Sekunden sie von selbst verschwindet. 0 = nie.
@export var heals_after_seconds: float = 0.0


## Ob diese Verletzung blutet — fuer Anzeige und Warnungen.
func is_bleeding() -> bool:
	return blood_per_second > 0.0


func get_kind_name() -> String:
	match kind:
		Kind.BLEED_LIGHT: return "Blutung"
		Kind.BLEED_HEAVY: return "Starke Blutung"
		Kind.CUT: return "Schnitt"
		Kind.FRACTURE: return "Bruch"
	return "Verletzung"
