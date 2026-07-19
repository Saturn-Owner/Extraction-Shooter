## Eine Schusswaffe.
##
## Die Waffe legt fest, WIE geschossen wird (Feuerrate, Rückstoß, Präzision).
## Was der Treffer anrichtet, entscheidet die geladene AmmoData.
## Diese Trennung ist wichtig: Dieselbe Waffe fühlt sich mit anderer Munition
## völlig anders an — genau das wollen wir.
class_name WeaponData
extends ItemData

enum FireMode {
	SINGLE,  ## Einzelfeuer
	BURST,   ## Feuerstoß
	AUTO,    ## Dauerfeuer
}

@export_group("Kaliber & Magazin")

## Muss exakt mit AmmoData.caliber übereinstimmen, z.B. "5.56x45".
@export var caliber: StringName = &"5.56x45"

## Standard-Magazingröße ohne Modifikationen.
@export_range(1, 200) var magazine_size: int = 30

## Welche Feuermodi die Waffe beherrscht.
@export var fire_modes: Array[FireMode] = [FireMode.SINGLE, FireMode.AUTO]

@export_group("Feuerverhalten")

## Schuss pro Minute im Dauerfeuer.
@export_range(30, 1400) var fire_rate_rpm: int = 700

## Anzahl Schuss im Feuerstoß-Modus.
@export_range(2, 5) var burst_count: int = 3

## Wie stark der Lauf die Mündungsgeschwindigkeit der Munition verändert.
## 1.0 = Standardlauf. Kurze Läufe (<1.0) verlieren Geschwindigkeit und
## damit auch Durchschlagskraft auf Distanz.
@export_range(0.7, 1.2) var muzzle_velocity_modifier: float = 1.0

@export_group("Rückstoß & Handling")

## Rückstoß nach oben pro Schuss.
@export_range(0.0, 500.0) var recoil_vertical: float = 120.0

## Seitlicher Rückstoß — sorgt dafür, dass Dauerfeuer ausfranst.
@export_range(0.0, 500.0) var recoil_horizontal: float = 40.0

## Ergonomie 0-100. Beeinflusst, wie schnell gezielt wird und wie lange
## der Spieler die Waffe ruhig halten kann. Hoch = handlich.
@export_range(0, 100) var ergonomics: int = 50

## Streuung in Bogenminuten (MOA). Kleiner = präziser.
## Nur bei Präzisionsgewehren wirklich spürbar.
@export_range(0.5, 15.0) var accuracy_moa: float = 3.0

@export_group("Nachladen")

## Magazinwechsel mit Patrone im Lauf. Schneller, weil der Verschluss
## nicht vorgelassen werden muss.
@export_range(0.5, 8.0) var reload_time_tactical: float = 2.3

## Magazinwechsel bei leergeschossener Waffe. Langsamer — der Verschluss
## steht hinten und muss zusaetzlich geloest werden.
@export_range(0.5, 10.0) var reload_time_empty: float = 3.1

## Wie lange das Beheben einer Ladehemmung dauert.
@export_range(0.5, 8.0) var jam_clear_time: float = 1.7

@export_group("Zielen")

## Sichtfeld beim Zielen ueber Kimme und Korn. Kleiner = mehr Zoom.
@export_range(20.0, 75.0) var ads_fov: float = 52.0

## Wieviel Streuung beim Zielen uebrig bleibt.
@export_range(0.05, 1.0) var ads_spread_multiplier: float = 0.35

## Wie stark das Zielen bremst (0.6 = 60 % Tempo).
@export_range(0.2, 1.0) var ads_move_multiplier: float = 0.62

@export_group("Zustand")

## Wie schnell die Waffe verschleißt. Abgenutzte Waffen sollen
## öfter Ladehemmungen haben — Arbeit für die Werkstatt.
@export_range(0.0, 5.0) var wear_per_shot: float = 0.01

## Grundwahrscheinlichkeit einer Ladehemmung bei perfektem Zustand.
@export_range(0.0, 0.5) var base_jam_chance: float = 0.001


## Zeit zwischen zwei Schüssen in Sekunden.
func get_shot_interval() -> float:
	return 60.0 / float(fire_rate_rpm)


## Wie lange ein Magazinwechsel dauert.
##
## Die Ergonomie zieht die Zeit spürbar zusammen: Eine handliche Waffe
## (Ergonomie 100) lädt rund 20 % schneller nach als eine sperrige (0).
## Damit ist Ergonomie nicht nur eine Zahl im Datenblatt, sondern etwas,
## das man im Gefecht merkt.
func get_reload_duration(from_empty: bool) -> float:
	var base := reload_time_empty if from_empty else reload_time_tactical
	var ergonomics_factor := 1.1 - 0.2 * (float(ergonomics) / 100.0)
	return base * ergonomics_factor


## Effektive Mündungsgeschwindigkeit mit dieser Munition.
func get_muzzle_velocity(ammo: AmmoData) -> float:
	return ammo.muzzle_velocity_ms * muzzle_velocity_modifier


## Ob diese Munition in diese Waffe passt.
func accepts_ammo(ammo: AmmoData) -> bool:
	return ammo.caliber == caliber


func validate() -> Array[String]:
	var problems := super()
	if caliber == &"":
		problems.append("caliber ist leer")
	if fire_modes.is_empty():
		problems.append("fire_modes ist leer — Waffe kann nicht schießen")
	if category != Category.WEAPON:
		problems.append("category sollte WEAPON sein")
	return problems
