## Gesundheit pro Körperteil.
##
## ---------------------------------------------------------------------------
## DIE REGEL
##
## Jedes Körperteil hat eigene Trefferpunkte. Kopf oder Brust auf null
## bedeutet **sofort tot**. Arme, Beine und Bauch können ausfallen, ohne zu
## töten — aber sie werden dann zur Last:
##
##   Bein zerschossen    langsamer
##   Arm zerschossen     mehr Rückstoß, zittrigeres Zielen
##   Bauch zerschossen   Hunger und Durst steigen schneller
##
## Damit ein ausgefallenes Glied kein Freibrief wird, geht weiterer Schaden
## darauf zu 70 % auf die BRUST über. Wer mit zerschossenem Bein weiterläuft,
## stirbt am Ende an einem Beintreffer — das ist die Entscheidung, die das
## System erzeugen soll: weiterlaufen oder behandeln.
##
## ---------------------------------------------------------------------------
## HINWEIS ZUM NETZWERK
## Diese Klasse ist die Wahrheit über Leben und Tod. Im Mehrspielerbetrieb
## läuft sie ausschließlich auf dem Server. Der Client bekommt Werte zur
## Anzeige und darf sie nie selbst verändern — sonst ist Unsterblichkeit
## eine Zeile Code beim Spieler.
class_name HealthSystem
extends Node

signal part_damaged(part: Part, amount: float, remaining: float)
signal part_destroyed(part: Part)
signal part_healed(part: Part, amount: float)
signal died(killing_part: Part)

enum Part {
	HEAD,
	CHEST,
	STOMACH,
	LEFT_ARM,
	RIGHT_ARM,
	LEFT_LEG,
	RIGHT_LEG,
}

## Wie viel jedes Körperteil aushält.
##
## Kopf und Brust sind bewusst niedrig: Ein Kopftreffer soll töten, nicht
## verhandeln. Die Summe ist mit 440 zweitrangig — entscheidend ist, dass
## keine einzelne Stelle beliebig viel wegsteckt.
const MAX_HP := {
	Part.HEAD: 35.0,
	Part.CHEST: 85.0,
	Part.STOMACH: 70.0,
	Part.LEFT_ARM: 60.0,
	Part.RIGHT_ARM: 60.0,
	Part.LEFT_LEG: 65.0,
	Part.RIGHT_LEG: 65.0,
}

## Körperteile, deren Ausfall sofort tötet.
const VITAL := [Part.HEAD, Part.CHEST]

## Wie viel Schaden auf ein bereits zerstörtes Glied in die Brust übergeht.
const OVERFLOW_TO_CHEST := 0.7

const PART_NAMES := {
	Part.HEAD: "Kopf",
	Part.CHEST: "Brust",
	Part.STOMACH: "Bauch",
	Part.LEFT_ARM: "Linker Arm",
	Part.RIGHT_ARM: "Rechter Arm",
	Part.LEFT_LEG: "Linkes Bein",
	Part.RIGHT_LEG: "Rechtes Bein",
}

var is_dead: bool = false

## Part -> aktuelle Trefferpunkte.
var _hp: Dictionary = {}


## Beim Erzeugen, nicht erst beim Betreten des Baums.
##
## _ready() greift erst, wenn der Knoten wirklich in der Szene haengt. Bis
## dahin haette dieses System keine Trefferpunkte — und ein Gesundheitssystem,
## das kurzzeitig "null HP ueberall" meldet, ist eine Falle: Wer in diesem
## Moment nachfragt, haelt den Spieler fuer tot.
func _init() -> void:
	reset()


## Alles auf Anfang — für einen neuen Raid.
func reset() -> void:
	is_dead = false
	_hp.clear()
	for part in MAX_HP:
		_hp[part] = float(MAX_HP[part])


static func is_vital(part: Part) -> bool:
	return part in VITAL


static func get_part_name(part: Part) -> String:
	return PART_NAMES.get(part, "Unbekannt")


static func get_max_hp(part: Part) -> float:
	return float(MAX_HP.get(part, 1.0))


func get_hp(part: Part) -> float:
	return float(_hp.get(part, 0.0))


func get_ratio(part: Part) -> float:
	var maximum := get_max_hp(part)
	return 0.0 if maximum <= 0.0 else clampf(get_hp(part) / maximum, 0.0, 1.0)


func is_destroyed(part: Part) -> bool:
	return get_hp(part) <= 0.0


## Summe über alle Körperteile — nur für die Anzeige.
## Das Spiel entscheidet NIE anhand dieser Zahl, ob jemand lebt.
func get_total_hp() -> float:
	var total := 0.0
	for part in _hp:
		total += float(_hp[part])
	return total


static func get_total_max_hp() -> float:
	var total := 0.0
	for part in MAX_HP:
		total += float(MAX_HP[part])
	return total


## Fügt einem Körperteil Schaden zu.
##
## Gibt zurück, wie viel tatsächlich angekommen ist — inklusive dem Anteil,
## der von einem zerstörten Glied in die Brust übergegangen ist.
func apply_damage(part: Part, amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0

	# Auf ein bereits ausgefallenes Glied kann nichts mehr einwirken —
	# der Schaden geht gedaempft auf die Brust.
	if is_destroyed(part) and not is_vital(part):
		return apply_damage(Part.CHEST, amount * OVERFLOW_TO_CHEST)

	var before := get_hp(part)
	var after := maxf(0.0, before - amount)
	_hp[part] = after

	var dealt := before - after
	part_damaged.emit(part, dealt, after)

	if after <= 0.0 and before > 0.0:
		part_destroyed.emit(part)
		if is_vital(part):
			is_dead = true
			died.emit(part)

	# Was ueber die Trefferpunkte hinausging, geht VERLOREN.
	#
	# Der Schuss, der ein Bein zerstoert, toetet also nicht zusaetzlich. Nur
	# JEDER WEITERE Treffer auf das bereits ausgefallene Bein wirkt auf die
	# Brust (siehe oben). Sonst waere ein einzelner starker Treffer aufs Bein
	# toedlich, und Gliedmassen waeren keine Puffer mehr, sondern Zuender.
	return dealt


## Heilt ein Körperteil. Ein zerstörtes Glied laesst sich wieder herstellen —
## das ist die Aufgabe des Erste-Hilfe-Kastens.
func heal(part: Part, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := get_hp(part)
	var after := minf(get_max_hp(part), before + amount)
	_hp[part] = after
	var healed := after - before
	if healed > 0.0:
		part_healed.emit(part, healed)
	return healed


## Wie stark ein zerschossenes Bein das Tempo druekt.
## Zwei kaputte Beine sind schlimmer als eins, aber nicht doppelt so schlimm —
## irgendwann kriecht man ohnehin nur noch.
func get_movement_penalty() -> float:
	var broken := 0
	if is_destroyed(Part.LEFT_LEG):
		broken += 1
	if is_destroyed(Part.RIGHT_LEG):
		broken += 1
	match broken:
		1: return 0.35
		2: return 0.60
	return 0.0


## Wie stark ein zerschossener Arm das Zielen stoert.
func get_aim_penalty() -> float:
	var broken := 0
	if is_destroyed(Part.LEFT_ARM):
		broken += 1
	if is_destroyed(Part.RIGHT_ARM):
		broken += 1
	match broken:
		1: return 0.30
		2: return 0.55
	return 0.0


## Ein zerschossener Bauch laesst Hunger und Durst schneller steigen.
func get_metabolism_multiplier() -> float:
	return 1.8 if is_destroyed(Part.STOMACH) else 1.0


func to_dict() -> Dictionary:
	var parts := {}
	for part in _hp:
		parts[str(part)] = _hp[part]
	return {"dead": is_dead, "parts": parts}


func from_dict(data: Dictionary) -> void:
	reset()
	is_dead = bool(data.get("dead", false))
	var parts: Dictionary = data.get("parts", {})
	for key in parts:
		var part := int(key)
		if MAX_HP.has(part):
			_hp[part] = clampf(float(parts[key]), 0.0, get_max_hp(part))
