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

## Anzahl Projektile pro Schuss. 1 bei allem ausser Schrot.
## Schrot macht pro Kugel wenig Schaden, in Summe aber sehr viel — dafür
## streut es stark und hat kaum Durchschlagskraft. Auf Distanz nutzlos,
## auf zwei Metern tödlich.
@export_range(1, 16) var pellet_count: int = 1

## Streuung bei mehreren Projektilen, in Grad. 0 bei Einzelgeschossen.
@export_range(0.0, 15.0) var pellet_spread_degrees: float = 0.0

## Leuchtspur — verrät die eigene Position, hilft aber beim Korrigieren.
@export var is_tracer: bool = false

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


## Gesamtschaden eines Schusses, wenn alle Projektile treffen.
## Bei Schrot ist das deutlich mehr als der Einzelwert.
func get_total_damage() -> int:
	return damage * pellet_count


## Kurze Zusammenfassung für die Item-Beschreibung im Terminal.
func get_stat_summary() -> String:
	if pellet_count > 1:
		return "%s | %dx%d Schaden | Pen %d" % [caliber, pellet_count, damage, penetration_power]
	return "%s | Schaden %d | Pen %d" % [caliber, damage, penetration_power]


## Munitionsart im Klartext: Schrot, Panzerbrechend, Vollmantel, Teilmantel.
##
## ABGELEITET aus Durchschlag und Fragmentierung, nicht als eigenes Feld
## gepflegt. Vorteil: keine der 27 vorhandenen .tres-Dateien muss angefasst
## werden, und die Bezeichnung kann nie im Widerspruch zu den Werten stehen —
## eine Patrone mit Pen 60, die "Vollmantel" heisst, waere eine Luege.
##
## Nachteil: Sondermunition wie Subsonic oder Brandsatz laesst sich so nicht
## abbilden. Wenn wir die brauchen, wird daraus ein echtes Feld.
func get_ammo_type_name() -> String:
	if pellet_count > 1:
		return "Schrot"
	if penetration_power >= 45:
		return "Panzerbrechend"
	if penetration_power >= 28:
		return "Vollmantel"
	if fragmentation_chance >= 0.35:
		return "Teilmantel"
	return "Vollmantel"


func get_type_label() -> String:
	var art := get_ammo_type_name()
	if is_tracer:
		art += ", Leuchtspur"
	return "%s  —  %s" % [caliber, art]


func get_info_lines() -> Array[String]:
	var lines: Array[String] = []

	if pellet_count > 1:
		lines.append("Schaden:      %d x %d  (%d gesamt)" % [pellet_count, damage, get_total_damage()])
		lines.append("Streuung:     %.1f Grad" % pellet_spread_degrees)
	else:
		lines.append("Schaden:      %d" % damage)

	lines.append("Durchschlag:  %d von 70" % penetration_power)
	lines.append("Plattenschaden: %.0f %%" % armor_damage_percent)
	lines.append("Fragmentierung: %.0f %%" % (fragmentation_chance * 100.0))
	lines.append("Muendung:     %.0f m/s" % muzzle_velocity_ms)

	if bleeding_chance > 0.0:
		lines.append("Blutung:      %.0f %%  (schwer %.0f %%)" % [
			bleeding_chance * 100.0, heavy_bleeding_chance * 100.0])

	lines.append_array(super())
	return lines


func validate() -> Array[String]:
	var problems := super()
	if caliber == &"":
		problems.append("caliber ist leer")
	if category != Category.AMMO:
		problems.append("category sollte AMMO sein")
	return problems
