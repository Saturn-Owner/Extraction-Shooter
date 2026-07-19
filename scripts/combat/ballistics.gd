## Trefferberechnung: Was passiert, wenn ein Geschoss auf ein Ziel trifft.
##
## Bewusst reine Mathematik ohne Szenen und Knoten — dadurch vollständig
## testbar, ohne das Spiel zu starten, und später unverändert auf dem
## Server einsetzbar.
##
## ---------------------------------------------------------------------------
## DAS MODELL
##
## Rüstung ist kein Schild, sondern eine Chance. Drei Ausgänge sind möglich:
##
##   1. DURCHSCHLAG    Das Geschoss kommt durch. Voller Schaden, Platte
##                     nimmt trotzdem Schaden.
##   2. GESTOPPT       Die Platte hält. Der Getroffene bekommt nur stumpfe
##                     Wucht ab (~12%) — er stirbt nicht, aber es tut weh.
##   3. UNGESCHUETZT   Kein Schutz an dieser Stelle. Voller Schaden.
##
## Entscheidend: Auch ein GESTOPPTER Treffer beschädigt die Platte. Deshalb
## hält keine Rüstung ewig, und deshalb ist Dauerbeschuss mit schwacher
## Munition eine gültige Taktik — man schiesst die Platte kaputt.
##
## Die Übergangszone ist absichtlich weich: Bei genau passendem Durchschlag
## kommt jeder zweite Schuss durch. Dadurch fühlt sich kein Kampf
## vorherbestimmt an, und Rüstung gibt Sicherheit statt Garantie.
class_name Ballistics
extends RefCounted

## Anteil des Schadens, der bei gestopptem Treffer durch die Platte wirkt.
const BLUNT_DAMAGE_FACTOR := 0.12

## Breite der Übergangszone in Durchschlagspunkten.
## Innerhalb von +/- diesem Wert um die Schwelle entscheidet der Zufall.
const PENETRATION_SOFT_ZONE := 15.0

## Wie viel Durchschlag eine Plattenklasse verlangt (Klasse * dieser Wert).
const CLASS_TO_PENETRATION := 10.0


## Ergebnis eines einzelnen Treffers.
class HitResult extends RefCounted:
	var penetrated: bool = false
	var was_armored: bool = false
	var damage_to_target: float = 0.0
	var damage_to_armor: float = 0.0
	var caused_bleeding: bool = false
	var caused_heavy_bleeding: bool = false

	func describe() -> String:
		if not was_armored:
			return "ungeschuetzt, %.0f Schaden" % damage_to_target
		if penetrated:
			return "DURCHSCHLAG, %.0f Schaden (Platte -%.0f)" % [damage_to_target, damage_to_armor]
		return "gestoppt, nur %.0f Wucht (Platte -%.0f)" % [damage_to_target, damage_to_armor]


## Wie viel Durchschlag nötig ist, um diese Schutzklasse zuverlässig zu knacken.
static func get_required_penetration(armor_class: float) -> float:
	return armor_class * CLASS_TO_PENETRATION


## Wahrscheinlichkeit, dass dieses Geschoss die Platte durchschlägt.
##
##   Durchschlag 15 unter der Schwelle -> 0.0 (kommt nie durch)
##   Durchschlag genau an der Schwelle -> 0.5
##   Durchschlag 15 über der Schwelle  -> 1.0 (kommt immer durch)
static func get_penetration_chance(penetration_power: float, effective_class: float) -> float:
	if effective_class <= 0.0:
		return 1.0
	var required := get_required_penetration(effective_class)
	var advantage := penetration_power - required
	return clampf((advantage + PENETRATION_SOFT_ZONE) / (PENETRATION_SOFT_ZONE * 2.0), 0.0, 1.0)


## Geschwindigkeitsverlust über die Flugstrecke.
## Ein hoher ballistischer Koeffizient hält das Geschoss schnell.
## Das wirkt sich direkt auf den Durchschlag aus: Auf 400 m kommt dieselbe
## Munition nicht mehr durch, was sie auf 50 m noch geknackt hätte.
static func get_velocity_at_distance(ammo: AmmoData, distance_m: float) -> float:
	if ammo == null:
		return 0.0
	# Vereinfachtes Widerstandsmodell: exponentieller Abfall, gedämpft durch
	# den ballistischen Koeffizienten. Kein Ersatz für echte Aerodynamik,
	# aber die Rangfolge der Kaliber stimmt und es ist nachvollziehbar.
	var drag := 0.0012 / maxf(0.05, ammo.ballistic_coefficient)
	return ammo.muzzle_velocity_ms * exp(-drag * maxf(0.0, distance_m))


## Effektiver Durchschlag auf Entfernung.
## Skaliert mit dem Quadrat der Geschwindigkeit (Bewegungsenergie).
static func get_penetration_at_distance(ammo: AmmoData, distance_m: float) -> float:
	if ammo == null:
		return 0.0
	if ammo.muzzle_velocity_ms <= 0.0:
		return float(ammo.penetration_power)
	var v := get_velocity_at_distance(ammo, distance_m)
	var ratio := v / ammo.muzzle_velocity_ms
	return float(ammo.penetration_power) * ratio * ratio


## Schaden auf Entfernung. Faellt schwächer ab als der Durchschlag —
## ein langsames Geschoss reisst immer noch, es kommt nur nicht mehr durch.
static func get_damage_at_distance(ammo: AmmoData, distance_m: float) -> float:
	if ammo == null:
		return 0.0
	if ammo.muzzle_velocity_ms <= 0.0:
		return float(ammo.damage)
	var v := get_velocity_at_distance(ammo, distance_m)
	var ratio := v / ammo.muzzle_velocity_ms
	return float(ammo.damage) * lerpf(1.0, ratio, 0.6)


## Berechnet einen Treffer.
##
## plate darf null sein (ungeschützte Stelle). rng erlaubt es, im Test mit
## festem Startwert reproduzierbare Ergebnisse zu bekommen.
static func resolve_hit(
		ammo: AmmoData,
		distance_m: float,
		plate: ArmorPlateData,
		plate_durability: float,
		rng: RandomNumberGenerator = null
) -> HitResult:
	var result := HitResult.new()
	if ammo == null:
		return result

	var damage := get_damage_at_distance(ammo, distance_m)
	var penetration := get_penetration_at_distance(ammo, distance_m)

	# Kein Schutz an dieser Stelle: voller Schaden, keine Frage.
	if plate == null or plate_durability <= 0.0:
		result.was_armored = false
		result.penetrated = true
		result.damage_to_target = damage
		_roll_bleeding(result, ammo, rng, 1.0)
		return result

	result.was_armored = true
	var effective_class := plate.get_effective_class(plate_durability)
	var chance := get_penetration_chance(penetration, effective_class)

	var roll := rng.randf() if rng != null else randf()
	result.penetrated = roll < chance

	# Die Platte nimmt IMMER Schaden — auch wenn sie hält.
	# Das ist der Grund, warum Rüstung nicht ewig schützt. Wie viel, hängt
	# davon ab, wie nah das Geschoss am Durchschlag war.
	result.damage_to_armor = minf(
		plate_durability,
		get_armor_damage(ammo, penetration, effective_class, plate, result.penetrated)
	)

	if result.penetrated:
		result.damage_to_target = damage
		_roll_bleeding(result, ammo, rng, 1.0)
	else:
		# Stumpfe Wucht durch die Platte. Keine Blutung — die Haut ist heil.
		result.damage_to_target = damage * BLUNT_DAMAGE_FACTOR

	return result


## Wie stark ein Treffer die Platte beschädigt.
##
## Ein Geschoss, das weit unter der Schwelle liegt, prallt praktisch ab und
## richtet kaum Schaden an der Platte an. Eines, das knapp scheitert, hat
## fast genug Energie und beschädigt sie erheblich.
##
## Ohne diese Kopplung würde eine Klasse-4-Platte nach fünf Pistolenschüssen
## zerfallen — was den ganzen Sinn von Rüstung aushebeln würde.
static func get_armor_damage(ammo: AmmoData, penetration: float, effective_class: float,
		plate: ArmorPlateData, penetrated: bool) -> float:
	if ammo == null or plate == null:
		return 0.0

	var full := ammo.armor_damage_percent * 0.01 * plate.max_durability
	if penetrated:
		return full

	var required := get_required_penetration(effective_class)
	if required <= 0.0:
		return full

	# Quadratisch, damit schwache Munition wirklich wenig ausrichtet.
	var ratio := clampf(penetration / required, 0.0, 1.0)
	return full * (0.1 + 0.9 * ratio * ratio)


static func _roll_bleeding(result: HitResult, ammo: AmmoData, rng: RandomNumberGenerator, scale: float) -> void:
	var r1 := rng.randf() if rng != null else randf()
	var r2 := rng.randf() if rng != null else randf()
	result.caused_heavy_bleeding = r2 < ammo.heavy_bleeding_chance * scale
	result.caused_bleeding = result.caused_heavy_bleeding or r1 < ammo.bleeding_chance * scale
