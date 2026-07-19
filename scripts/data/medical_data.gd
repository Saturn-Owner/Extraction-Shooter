## Ein medizinischer Gegenstand.
##
## Erbt von ItemData: Ein Verband liegt im Raster, wiegt etwas und hat einen
## Preis wie alles andere. Dazu kommt, WAS er behandelt und WIE LANGE das
## dauert.
##
## ---------------------------------------------------------------------------
## JEDES MITTEL KANN GENAU EINE SACHE
##
##   Verband        leichte Blutungen
##   Aderpresse     starke Blutungen
##   Schiene        Brueche
##   Schmerzmittel  nimmt die Behinderung weg, heilt aber NICHTS
##   Chirurgenkit   stellt ein ausgefallenes Koerperteil wieder her
##   Blutbeutel     fuellt das Blutvolumen auf
##
## Das ist Absicht. Ein Universalmittel wuerde die Frage "was habe ich dabei?"
## erledigen, und genau die soll im Raid wehtun.
class_name MedicalData
extends ItemData

enum Kind {
	BANDAGE,    ## Verband
	TOURNIQUET, ## Aderpresse
	SPLINT,     ## Schiene
	PAINKILLER, ## Schmerzmittel
	SURGERY,    ## Chirurgenkit
	BLOOD,      ## Blutbeutel
}

@export var kind: Kind = Kind.BANDAGE

@export_group("Anwendung")

## Wie lange die Behandlung dauert. Beim Blutbeutel steht hier 0: Der laeuft,
## bis der Koerper voll ist — wie lange das dauert, haengt davon ab, wie viel
## fehlt.
@export var use_seconds: float = 4.0

## Welche Verletzungsarten das Mittel beseitigt (InjuryData.Kind als Zahlen).
@export var treats: Array[int] = []

@export_group("Wirkung")

## Trefferpunkte, die das behandelte Koerperteil zurueckbekommt.
@export var heal_hp: float = 0.0

## Blut pro Sekunde beim Blutbeutel.
@export var blood_per_second: float = 0.0

## Wie viel Blut insgesamt im Beutel steckt.
@export var blood_total: float = 0.0

## Wie lange Schmerzmittel wirken.
@export var pain_relief_seconds: float = 0.0


func get_kind_name() -> String:
	match kind:
		Kind.BANDAGE: return "Verband"
		Kind.TOURNIQUET: return "Aderpresse"
		Kind.SPLINT: return "Schiene"
		Kind.PAINKILLER: return "Schmerzmittel"
		Kind.SURGERY: return "Chirurgenkit"
		Kind.BLOOD: return "Blutbeutel"
	return "Medizin"


func treats_kind(injury_kind: int) -> bool:
	return injury_kind in treats


## Ob das Mittel ueberhaupt eine Verletzung behandelt — Schmerzmittel,
## Blutbeutel und das Chirurgenkit tun das nicht.
func treats_injuries() -> bool:
	return not treats.is_empty()
