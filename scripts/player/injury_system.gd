## Welche Verletzungen der Spieler gerade mit sich herumträgt.
##
## ---------------------------------------------------------------------------
## DIE IDEE
##
## Eine Verletzung geht NICHT von selbst weg. Sie hängt an einem Körperteil
## und wirkt jede Sekunde weiter, bis jemand sie behandelt. Damit ist sie
## etwas anderes als Schaden: Schaden ist passiert, eine Verletzung passiert
## gerade noch.
##
## Mehrere Verletzungen am selben Körperteil sind erlaubt und addieren sich —
## zwei Blutungen im selben Bein bluten doppelt. Wer das ignoriert, verblutet.
##
## Schmerzmittel sind bewusst ein Sonderfall: Sie nehmen die BEHINDERUNG weg,
## nicht die Verletzung. Man läuft dann auf einem gebrochenen Bein, weil man
## es nicht mehr spürt — und wenn die Wirkung nachlässt, ist es immer noch
## gebrochen.
##
## HINWEIS ZUM NETZWERK: Läuft später ausschließlich auf dem Server, wie das
## Gesundheitssystem. Ein Client, der seine Blutungen selbst beenden darf,
## blutet nie.
class_name InjurySystem
extends Node

signal injury_added(injury: InjuryData, part: HealthSystem.Part)
signal injury_healed(injury: InjuryData, part: HealthSystem.Part)

## Wie lange die Schmerzmittel noch wirken.
var pain_relief_remaining: float = 0.0

## Liste von {data: InjuryData, part: int, age: float}.
var _injuries: Array[Dictionary] = []


func reset() -> void:
	_injuries.clear()
	pain_relief_remaining = 0.0


## Fuegt eine Verletzung hinzu. `injury_id` ist die ID einer .tres unter
## assets/data/injuries/.
func add(injury_id: StringName, part: HealthSystem.Part) -> InjuryData:
	var data := InjuryRegistry.get_injury(injury_id)
	if data == null:
		push_error("[Injuries] Unbekannte Verletzung: %s" % injury_id)
		return null
	return add_data(data, part)


func add_data(data: InjuryData, part: HealthSystem.Part) -> InjuryData:
	if data == null:
		return null
	_injuries.append({"data": data, "part": int(part), "age": 0.0})
	injury_added.emit(data, part)
	return data


func has_any() -> bool:
	return not _injuries.is_empty()


func get_count() -> int:
	return _injuries.size()


## Alle Verletzungen, oder nur die eines Koerperteils.
func get_injuries(part: int = -1) -> Array[InjuryData]:
	var result: Array[InjuryData] = []
	for entry in _injuries:
		if part < 0 or int(entry["part"]) == part:
			result.append(entry["data"])
	return result


func has_kind(kind: InjuryData.Kind, part: int = -1) -> bool:
	for entry in _injuries:
		if part >= 0 and int(entry["part"]) != part:
			continue
		if (entry["data"] as InjuryData).kind == kind:
			return true
	return false


## Schreibt eine Sekunde fort: Blutverlust, laufender Schaden, Selbstheilung.
func tick(delta: float, health: HealthSystem) -> void:
	if pain_relief_remaining > 0.0:
		pain_relief_remaining = maxf(0.0, pain_relief_remaining - delta)

	if _injuries.is_empty() or health == null or health.is_dead:
		return

	var blood_loss := 0.0
	var expired: Array[Dictionary] = []

	for entry in _injuries:
		var data: InjuryData = entry["data"]
		var part: int = int(entry["part"])

		blood_loss += data.blood_per_second * delta
		if data.hp_per_second > 0.0:
			health.apply_damage(part, data.hp_per_second * delta)

		entry["age"] = float(entry["age"]) + delta
		if data.heals_after_seconds > 0.0 and float(entry["age"]) >= data.heals_after_seconds:
			expired.append(entry)

	if blood_loss > 0.0:
		health.lose_blood(blood_loss)

	for entry in expired:
		_injuries.erase(entry)
		injury_healed.emit(entry["data"], entry["part"])


## Behandelt die erste passende Verletzung an einem Koerperteil.
##
## Gibt zurueck, was behandelt wurde — oder null, wenn dort nichts war, was
## dieses Mittel beheben kann. Der Aufrufer darf den Gegenstand dann NICHT
## verbrauchen: Einen Verband an einem gesunden Bein zu verlieren, waere im
## Raid ein teurer Fehlklick.
func treat(med: MedicalData, part: HealthSystem.Part) -> InjuryData:
	if med == null:
		return null

	for entry in _injuries:
		if int(entry["part"]) != int(part):
			continue
		var data: InjuryData = entry["data"]
		if not med.treats_kind(data.kind):
			continue
		_injuries.erase(entry)
		injury_healed.emit(data, part)
		return data

	return null


## Ob dieses Mittel an diesem Koerperteil ueberhaupt etwas ausrichtet.
func can_treat(med: MedicalData, part: HealthSystem.Part) -> bool:
	if med == null or not med.treats_injuries():
		return false
	for entry in _injuries:
		if int(entry["part"]) == int(part) and med.treats_kind((entry["data"] as InjuryData).kind):
			return true
	return false


func apply_painkillers(seconds: float) -> void:
	# Nicht addieren, sondern die laengere Wirkung nehmen: Zwei Packungen
	# hintereinander sollen keine doppelte Betaeubung ergeben.
	pain_relief_remaining = maxf(pain_relief_remaining, seconds)


func is_pain_relieved() -> bool:
	return pain_relief_remaining > 0.0


## Wie stark Verletzungen an den BEINEN das Tempo druecken.
func get_movement_penalty() -> float:
	return _sum_penalty(true)


## Wie stark Verletzungen an den ARMEN das Zielen stoeren.
func get_aim_penalty() -> float:
	return _sum_penalty(false)


func _sum_penalty(legs: bool) -> float:
	var relevant := [HealthSystem.Part.LEFT_LEG, HealthSystem.Part.RIGHT_LEG] if legs \
		else [HealthSystem.Part.LEFT_ARM, HealthSystem.Part.RIGHT_ARM]

	var total := 0.0
	for entry in _injuries:
		if not (int(entry["part"]) in relevant):
			continue
		var data: InjuryData = entry["data"]
		if data.relieved_by_painkillers and is_pain_relieved():
			continue
		total += data.movement_penalty if legs else data.aim_penalty

	# Gedeckelt: Auch mit vier Bruechen soll man noch kriechen koennen.
	return minf(0.75, total)


func to_dict() -> Dictionary:
	var list: Array = []
	for entry in _injuries:
		list.append({
			"id": String((entry["data"] as InjuryData).id),
			"part": entry["part"],
			"age": entry["age"],
		})
	return {"injuries": list, "relief": pain_relief_remaining}


func from_dict(data: Dictionary) -> void:
	reset()
	pain_relief_remaining = float(data.get("relief", 0.0))
	for raw in data.get("injuries", []):
		var injury := InjuryRegistry.get_injury(StringName(raw.get("id", "")))
		if injury == null:
			continue
		_injuries.append({
			"data": injury,
			"part": int(raw.get("part", 0)),
			"age": float(raw.get("age", 0.0)),
		})
