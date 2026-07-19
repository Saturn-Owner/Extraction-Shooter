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

## Blutvolumen in Prozent. Blutungen ziehen es herunter, der Blutbeutel
## fuellt es auf. Bei null ist man tot — unabhaengig davon, wie voll die
## Trefferpunkte noch sind.
##
## Das ist der Grund, warum ein Verband wichtiger ist als ein Erste-Hilfe-
## Kasten: Trefferpunkte stehen still, Blut laeuft weiter.
const MAX_BLOOD := 100.0

## Ab hier wird einem schwarz vor Augen — langsamer, zittriger.
const BLOOD_WEAK := 60.0
const BLOOD_CRITICAL := 30.0

## Was eine Operation kostet: Das Koerperteil kommt zurueck, haelt aber
## dauerhaft weniger aus. Wer sich dasselbe Bein dreimal flicken laesst,
## hat am Ende ein Bein, das kaum noch etwas abkann.
const SURGERY_MAX_HP_LOSS := 0.25
const SURGERY_MAX_HP_FLOOR := 0.40

var is_dead: bool = false

## Woran gestorben wurde — fuer die Meldung am Raid-Ende.
var death_cause: String = ""

var blood: float = MAX_BLOOD

## Part -> aktuelle Trefferpunkte.
var _hp: Dictionary = {}

## Part -> Anteil des urspruenglichen Maximums, der noch uebrig ist.
## 1.0 = unversehrt, 0.4 = dreimal operiert.
var _max_scale: Dictionary = {}


## Beim Erzeugen, nicht erst beim Betreten des Baums.
##
## _ready() greift erst, wenn der Knoten wirklich in der Szene haengt. Bis
## dahin haette dieses System keine Trefferpunkte — und ein Gesundheitssystem,
## das kurzzeitig "null HP ueberall" meldet, ist eine Falle: Wer in diesem
## Moment nachfragt, haelt den Spieler fuer tot.
func _init() -> void:
	reset()


## Alles auf Anfang — für einen neuen Raid.
##
## Die Narben verschwinden dabei ebenfalls. Ob eine Operation ueber den Raid
## hinaus nachwirkt, entscheidet spaeter das Lager — hier waere es nur eine
## stille Strafe fuer einen Tod, den man ohnehin schon bezahlt hat.
func reset() -> void:
	is_dead = false
	death_cause = ""
	blood = MAX_BLOOD
	_hp.clear()
	_max_scale.clear()
	for part in MAX_HP:
		_max_scale[part] = 1.0
		_hp[part] = float(MAX_HP[part])


static func is_vital(part: Part) -> bool:
	return part in VITAL


static func get_part_name(part: Part) -> String:
	return PART_NAMES.get(part, "Unbekannt")


## Das Maximum eines unversehrten Koerpers. Fuer Vergleiche und Anzeige.
static func get_max_hp(part: Part) -> float:
	return float(MAX_HP.get(part, 1.0))


## Das Maximum DIESES Koerpers — nach allem, was schon geflickt wurde.
func get_effective_max_hp(part: Part) -> float:
	return get_max_hp(part) * float(_max_scale.get(part, 1.0))


## Wie viel vom urspruenglichen Maximum uebrig ist (1.0 = unversehrt).
func get_max_hp_scale(part: Part) -> float:
	return float(_max_scale.get(part, 1.0))


func get_hp(part: Part) -> float:
	return float(_hp.get(part, 0.0))


func get_ratio(part: Part) -> float:
	var maximum := get_effective_max_hp(part)
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
			death_cause = get_part_name(part)
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
	var after := minf(get_effective_max_hp(part), before + amount)
	_hp[part] = after
	var healed := after - before
	if healed > 0.0:
		part_healed.emit(part, healed)
	return healed


## Blutverlust. Bei null ist Schluss — auch mit vollen Trefferpunkten.
func lose_blood(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	blood = maxf(0.0, blood - amount)
	if blood <= 0.0:
		is_dead = true
		death_cause = "verblutet"
		died.emit(Part.CHEST)


func restore_blood(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := blood
	blood = minf(MAX_BLOOD, blood + amount)
	return blood - before


func get_blood_ratio() -> float:
	return clampf(blood / MAX_BLOOD, 0.0, 1.0)


## Wie stark Blutverlust schwaecht. Erst ab BLOOD_WEAK spuerbar — man soll
## eine Blutung ueberleben koennen, wenn man sie schnell versorgt.
func get_blood_penalty() -> float:
	if blood >= BLOOD_WEAK:
		return 0.0
	var span := maxf(1.0, BLOOD_WEAK)
	return clampf((BLOOD_WEAK - blood) / span, 0.0, 1.0) * 0.45


## Operation am ausgefallenen Koerperteil: Es kommt zurueck, haelt aber
## dauerhaft weniger aus.
##
## Gibt zurueck, ob operiert wurde. An einem Koerperteil, das noch
## Trefferpunkte hat, gibt es nichts zu operieren — dafuer sind Verband und
## Erste Hilfe da, und das Kit ist zu wertvoll, um es dafuer zu verbrauchen.
func apply_surgery(part: Part) -> bool:
	if is_dead or not is_destroyed(part):
		return false

	var scale: float = float(_max_scale.get(part, 1.0))
	_max_scale[part] = maxf(SURGERY_MAX_HP_FLOOR, scale - SURGERY_MAX_HP_LOSS)

	# Das Koerperteil kommt mit dem NEUEN Maximum zurueck, nicht halb tot:
	# Wer 20 Sekunden im Feuer operiert, soll danach laufen koennen.
	_hp[part] = get_effective_max_hp(part)
	part_healed.emit(part, _hp[part])
	return true


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
	var scales := {}
	for part in _hp:
		parts[str(part)] = _hp[part]
		scales[str(part)] = _max_scale.get(part, 1.0)
	return {"dead": is_dead, "blood": blood, "parts": parts, "scales": scales}


func from_dict(data: Dictionary) -> void:
	reset()
	is_dead = bool(data.get("dead", false))
	blood = clampf(float(data.get("blood", MAX_BLOOD)), 0.0, MAX_BLOOD)

	var scales: Dictionary = data.get("scales", {})
	for key in scales:
		var scaled := int(key)
		if MAX_HP.has(scaled):
			_max_scale[scaled] = clampf(float(scales[key]), SURGERY_MAX_HP_FLOOR, 1.0)

	var parts: Dictionary = data.get("parts", {})
	for key in parts:
		var part := int(key)
		if MAX_HP.has(part):
			_hp[part] = clampf(float(parts[key]), 0.0, get_effective_max_hp(part))
