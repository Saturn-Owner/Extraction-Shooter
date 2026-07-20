## Eine Loot-Tabelle: was in einem Container liegen kann und wie oft.
##
## Datengetrieben wie alles andere — eine neue Fundort-Sorte ist eine neue
## .tres-Datei, kein neuer Code.
##
## AUFBAU:
## Jeder Eintrag hat ein Gewicht (nicht in kg — ein Losanteil). Bei den
## Gewichten 60/30/10 wird der erste Eintrag sechsmal so oft gezogen wie
## der letzte. Das ist einfacher zu pflegen als Prozentangaben, weil man
## einen Eintrag ergänzen kann, ohne alle anderen anzupassen.
##
## BALANCING-GEDANKE:
## Seltenheit soll aus der Tabelle kommen, nicht aus dem Preis. Ein Container
## im Militärlager zieht aus einer anderen Tabelle als eine Küchenschublade —
## dadurch lohnt es sich, gefährliche Orte aufzusuchen, statt überall
## dasselbe zu finden.
class_name LootTableData
extends Resource

## Ein möglicher Fund.
@export var entries: Array[Dictionary] = []

## Wie viele Züge dieser Container macht (zufällig zwischen min und max).
## Jeder Zug kann leer ausgehen, siehe empty_weight.
@export_range(0, 12) var min_rolls: int = 1
@export_range(0, 12) var max_rolls: int = 3

## Losanteil dafür, dass ein Zug NICHTS ergibt.
## Ohne das wäre jeder Container garantiert voll, und Suchen hätte keine
## Spannung — man würde einfach alles abklappern.
@export_range(0, 1000) var empty_weight: int = 25


## Zieht den Inhalt für einen Container.
## Gibt eine Liste aus {id, quantity} zurück.
##
## rng erlaubt reproduzierbare Ergebnisse im Test. Im Mehrspielerbetrieb
## würfelt später ausschliesslich der Server — sonst könnte jeder Client
## sich seinen eigenen Loot ausdenken.
func roll(rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if entries.is_empty():
		return result

	var generator := rng
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	var total_weight := empty_weight
	for entry in entries:
		total_weight += int(entry.get("weight", 1))
	if total_weight <= 0:
		return result

	var rolls := generator.randi_range(min_rolls, maxi(min_rolls, max_rolls))
	for i in range(rolls):
		var pick := generator.randi_range(1, total_weight)

		# Leerer Zug zuerst abhandeln.
		if pick <= empty_weight:
			continue

		var running := empty_weight
		for entry in entries:
			running += int(entry.get("weight", 1))
			if pick <= running:
				var min_q := int(entry.get("min", 1))
				var max_q := int(entry.get("max", min_q))
				result.append({
					"id": StringName(entry.get("id", "")),
					"quantity": generator.randi_range(min_q, maxi(min_q, max_q)),
				})
				break

	return result


## Prüft die Tabelle auf Datenfehler. Wird vom Test aufgerufen, damit ein
## Tippfehler in einer Item-ID nicht erst im Spiel auffällt.
func validate() -> Array[String]:
	var problems: Array[String] = []

	if min_rolls > max_rolls:
		problems.append("min_rolls (%d) ist groesser als max_rolls (%d)" % [min_rolls, max_rolls])

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var id := StringName(entry.get("id", ""))
		if id == &"":
			problems.append("Eintrag %d hat keine id" % i)
			continue
		if not ItemRegistry.has_item(id):
			problems.append("Eintrag %d verweist auf unbekanntes Item '%s'" % [i, id])
		if int(entry.get("weight", 1)) <= 0:
			problems.append("Eintrag %d ('%s') hat Gewicht 0 und kann nie gezogen werden" % [i, id])
		if int(entry.get("min", 1)) > int(entry.get("max", 1)):
			problems.append("Eintrag %d ('%s') hat min groesser als max" % [i, id])

	return problems
