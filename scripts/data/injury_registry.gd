## Nachschlagetabelle der Verletzungsarten.
##
## Dasselbe Muster wie ItemRegistry, aus demselben Grund: Über das Netz geht
## später nur die ID (&"bleed_heavy"), nie das Objekt. Und weil sie statisch
## ist, funktioniert sie auch in Headless-Tests, wo es keine Autoloads gibt.
class_name InjuryRegistry
extends RefCounted

const INJURY_DIR := "res://assets/data/injuries"

static var _injuries: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		reload()


static func reload() -> void:
	_injuries.clear()
	_loaded = true

	var dir := DirAccess.open(INJURY_DIR)
	if dir == null:
		push_warning("[InjuryRegistry] Ordner nicht lesbar: %s" % INJURY_DIR)
		return

	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var res := load("%s/%s" % [INJURY_DIR, file])
		if res is InjuryData:
			var injury := res as InjuryData
			if injury.id == &"":
				push_error("[InjuryRegistry] Verletzung ohne ID: %s" % file)
				continue
			_injuries[injury.id] = injury


static func get_injury(id: StringName) -> InjuryData:
	ensure_loaded()
	return _injuries.get(id)


static func has_injury(id: StringName) -> bool:
	ensure_loaded()
	return _injuries.has(id)


static func get_all() -> Array[InjuryData]:
	ensure_loaded()
	var result: Array[InjuryData] = []
	for injury in _injuries.values():
		result.append(injury)
	return result


## Alle Verletzungen einer Art — etwa fuer die Zufallsauswahl beim Testknopf.
static func get_by_kind(kind: InjuryData.Kind) -> Array[InjuryData]:
	var result: Array[InjuryData] = []
	for injury in get_all():
		if injury.kind == kind:
			result.append(injury)
	return result
