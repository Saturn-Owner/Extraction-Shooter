## Eine Munitionssorte, z.B. 5.56x45 M995 oder M855A1.
##
## Das ist das Herzstück des Waffen-/Rüstungs-Balancings. Der Grundgedanke
## (bewusst nah an Escape from Tarkov, weil sich das Modell bewährt hat):
##
##   Schaden       = was die Kugel im Fleisch anrichtet
##   Penetration   = ob sie überhaupt durch die Platte kommt
##
## Beide Werte sind ABSICHTLICH getrennt. Dadurch entsteht die gewünschte
## Realistik: M995 hat wenig Fleischschaden, durchschlägt aber fast alles.
## M855A1 macht mehr Schaden, scheitert dafür an hochwertigen Platten.
## So gibt es keine "beste" Munition, sondern eine Entscheidung.
##
## Die eigentliche Trefferberechnung kommt in Meilenstein 2 (ballistics.gd).
## Hier stehen nur die Werte.
class_name AmmoData
extends ItemData

@export_group("Kaliber")

## Muss exakt zum Kaliber der Waffe passen, z.B. "5.56x45".
## Schreibweise konsequent halten, sonst passt keine Munition in keine Waffe.
@export var caliber: StringName = &"5.56x45"

@export_group("Wirkung im Ziel")

## Schaden an ungeschütztem Fleisch, pro Projektil.
@export_range(0, 300) var damage: int = 40

## Durchschlagskraft, Skala 0-70.
## Grobe Orientierung:
##   0-15  = Pistolenmunition, scheitert an fast jeder Platte
##   20-30 = Standard-Vollmantel, kommt durch leichte Platten
##   35-45 = gute Panzerbrechende, kommt durch mittlere Platten
##   50-70 = Hochleistung wie M995, durchschlägt auch hochwertige Platten
@export_range(0, 70) var penetration_power: int = 30

## Wie stark ein Treffer die Platte zerstört, in Prozent.
## Auch ein NICHT durchgegangener Treffer beschädigt die Platte —
## deshalb hält keine Rüstung ewig. Das ersetzt bei uns das Stufensystem.
@export_range(0.0, 100.0) var armor_damage_percent: float = 30.0

## Chance, dass das Geschoss im Körper fragmentiert und Zusatzschaden macht.
## Nur relevant, wenn es NICHT durch eine Platte musste.
@export_range(0.0, 1.0) var fragmentation_chance: float = 0.15

@export_group("Ballistik (Flugverhalten)")

## Mündungsgeschwindigkeit in m/s. Bestimmt Flugzeit und Fallkurve.
## Wir simulieren echte Projektile, deshalb ist dieser Wert spürbar:
## Auf 300 m muss der Spieler vorhalten.
@export_range(100.0, 1200.0) var muzzle_velocity_ms: float = 920.0

## Ballistischer Koeffizient — wie gut das Geschoss die Geschwindigkeit hält.
## Höher = weniger Luftwiderstand = flachere Flugbahn auf Distanz.
@export_range(0.05, 1.0) var ballistic_coefficient: float = 0.30

## Geschwindigkeitsverlust pro durchschlagenem Objekt (Wand, Holz, Körper).
@export_range(0.0, 1.0) var speed_loss_per_hit: float = 0.35

@export_group("Verletzungen")

## Chance auf eine Blutung bei einem Treffer ins Fleisch.
## Greift auf das Verletzungssystem aus Meilenstein 5 vor.
@export_range(0.0, 1.0) var bleeding_chance: float = 0.20

## Chance auf eine schwere (arterielle) statt leichte Blutung.
@export_range(0.0, 1.0) var heavy_bleeding_chance: float = 0.05


## Kurze Zusammenfassung für die Item-Beschreibung im Terminal.
func get_stat_summary() -> String:
	return "%s | Schaden %d | Pen %d" % [caliber, damage, penetration_power]


func validate() -> Array[String]:
	var problems := super()
	if caliber == &"":
		problems.append("caliber ist leer")
	if category != Category.AMMO:
		problems.append("category sollte AMMO sein")
	return problems
