## Erzeugt die Verletzungsarten und die medizinischen Gegenstaende.
##
##   godot --headless --path . --script res://tools/generate_injuries.gd
##
## ACHTUNG — EINMAL-WERKZEUG: Danach sind die .tres die Wahrheit. Wer hier
## nochmal draufdrueckt, ueberschreibt alle Balancing-Aenderungen.
##
## ---------------------------------------------------------------------------
## BALANCING-GEDANKE
##
## Blut ist die eigentliche Uhr. Das Volumen sind 100 Prozent:
##
##   leichte Blutung   0.35 %/s  ->  rund 4,5 Minuten bis zum Tod
##   starke Blutung    1.20 %/s  ->  rund 80 Sekunden
##   Schnitt           0.50 %/s  ->  rund 3 Minuten
##
## Eine starke Blutung ist damit ein Notfall, eine leichte ein Aergernis mit
## Frist. Genau dieser Unterschied soll die Entscheidung tragen, ob man jetzt
## stehen bleibt oder es bis zum Ausgang schafft.
##
## Der Bruch blutet nicht. Er tut nur weh — und ist damit die Verletzung, die
## man mit Schmerzmitteln "wegdruecken" kann, ohne dass sie geheilt waere.
extends SceneTree

const INJURY_DIR := "res://assets/data/injuries"
const MEDICAL_DIR := "res://assets/data/medical"

const INJURIES := [
	{
		id = "bleed_light", name = "Leichte Blutung",
		kind = InjuryData.Kind.BLEED_LIGHT,
		blood = 0.35, hp = 0.0, move = 0.0, aim = 0.0,
		relieved = false, heals_after = 0.0,
		text = "Sickert. Nicht dramatisch, aber es hoert nicht von selbst auf.",
	},
	{
		id = "bleed_heavy", name = "Starke Blutung",
		kind = InjuryData.Kind.BLEED_HEAVY,
		blood = 1.20, hp = 0.0, move = 0.0, aim = 0.0,
		relieved = false, heals_after = 0.0,
		text = "Eine Arterie. Ohne Aderpresse sind das ein bis zwei Minuten.",
	},
	{
		id = "cut", name = "Schnitt",
		kind = InjuryData.Kind.CUT,
		blood = 0.50, hp = 0.0, move = 0.10, aim = 0.10,
		relieved = true, heals_after = 0.0,
		text = "Tiefer Schnitt. Blutet und behindert jede Bewegung.",
	},
	{
		id = "fracture", name = "Knochenbruch",
		kind = InjuryData.Kind.FRACTURE,
		blood = 0.0, hp = 0.0, move = 0.30, aim = 0.30,
		relieved = true, heals_after = 0.0,
		text = "Gebrochen. Jeder Schritt ist eine eigene Entscheidung.",
	},
]

const MEDICAL := [
	{
		id = "med_bandage", name = "Verband", kind = MedicalData.Kind.BANDAGE,
		seconds = 6.0, treats = [InjuryData.Kind.BLEED_LIGHT, InjuryData.Kind.CUT],
		heal = 8.0, stack = 5, weight = 0.1, price = 210,
		w = 1, h = 1,
		text = "Mullbinde. Stoppt eine leichte Blutung, wenn man sich die Zeit nimmt.",
	},
	{
		id = "med_tourniquet", name = "Aderpresse", kind = MedicalData.Kind.TOURNIQUET,
		seconds = 5.0, treats = [InjuryData.Kind.BLEED_HEAVY],
		heal = 0.0, stack = 3, weight = 0.08, price = 950,
		w = 1, h = 1,
		text = "Abbinden ueber der Wunde. Das Einzige, was eine Arterie aufhaelt.",
	},
	{
		id = "med_splint", name = "Schiene", kind = MedicalData.Kind.SPLINT,
		seconds = 10.0, treats = [InjuryData.Kind.FRACTURE],
		heal = 0.0, stack = 2, weight = 0.35, price = 1400,
		w = 2, h = 1,
		text = "Zwei Streben und Gurte. Der Bruch bleibt, aber man kann wieder laufen.",
	},
	{
		id = "med_painkillers", name = "Schmerzmittel", kind = MedicalData.Kind.PAINKILLER,
		seconds = 3.0, treats = [],
		heal = 0.0, stack = 4, weight = 0.05, price = 620,
		w = 1, h = 1, relief = 180.0,
		text = "Nimmt den Schmerz fuer drei Minuten. Heilt nichts — man merkt es nur nicht mehr.",
	},
	{
		id = "med_surgical_kit", name = "Chirurgenkit", kind = MedicalData.Kind.SURGERY,
		seconds = 20.0, treats = [],
		heal = 0.0, stack = 1, weight = 1.6, price = 9800,
		w = 3, h = 2,
		text = "Bringt ein ausgefallenes Koerperteil zurueck. Danach haelt es dauerhaft weniger aus.",
	},
	{
		id = "med_blood_bag", name = "Blutbeutel", kind = MedicalData.Kind.BLOOD,
		seconds = 0.0, treats = [],
		heal = 0.0, stack = 2, weight = 0.6, price = 3200,
		w = 1, h = 2, blood_rate = 6.0, blood_total = 60.0,
		text = "Laeuft, bis der Koerper voll ist oder der Beutel leer. Ersetzt Blut, keine Wunden.",
	},
]


func _initialize() -> void:
	print("=== Verletzungen und Medizin erzeugen ===\n")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INJURY_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MEDICAL_DIR))

	var errors := 0
	for entry in INJURIES:
		if not _write_injury(entry):
			errors += 1
	for entry in MEDICAL:
		if not _write_medical(entry):
			errors += 1

	print("\n%d Dateien erzeugt, %d Fehler."
		% [INJURIES.size() + MEDICAL.size() - errors, errors])
	quit(1 if errors > 0 else 0)


func _write_injury(entry: Dictionary) -> bool:
	var injury := InjuryData.new()
	injury.id = StringName(entry.id)
	injury.display_name = entry.name
	injury.description = entry.text
	injury.kind = entry.kind
	injury.blood_per_second = entry.blood
	injury.hp_per_second = entry.hp
	injury.movement_penalty = entry.move
	injury.aim_penalty = entry.aim
	injury.relieved_by_painkillers = entry.relieved
	injury.heals_after_seconds = entry.heals_after

	var path := "%s/%s.tres" % [INJURY_DIR, entry.id]
	if ResourceSaver.save(injury, path) != OK:
		push_error("Konnte %s nicht speichern" % path)
		return false

	var death := "-" if injury.blood_per_second <= 0.0 \
		else "%.0f s bis leer" % (100.0 / injury.blood_per_second)
	print("  %-14s %-16s %s" % [entry.id, injury.get_kind_name(), death])
	return true


func _write_medical(entry: Dictionary) -> bool:
	var med := MedicalData.new()
	med.id = StringName(entry.id)
	med.display_name = entry.name
	med.description = entry.text
	med.category = ItemData.Category.MEDICAL
	med.kind = entry.kind
	med.grid_width = entry.w
	med.grid_height = entry.h
	med.can_rotate = entry.w != entry.h
	med.weight_kg = entry.weight
	med.max_stack = entry.stack
	med.base_price = entry.price

	med.use_seconds = entry.seconds
	var treats: Array[int] = []
	for kind in entry.treats:
		treats.append(int(kind))
	med.treats = treats
	med.heal_hp = entry.heal
	med.pain_relief_seconds = entry.get("relief", 0.0)
	med.blood_per_second = entry.get("blood_rate", 0.0)
	med.blood_total = entry.get("blood_total", 0.0)

	var path := "%s/%s.tres" % [MEDICAL_DIR, entry.id]
	if ResourceSaver.save(med, path) != OK:
		push_error("Konnte %s nicht speichern" % path)
		return false

	print("  %-18s %-14s %4.1f s" % [entry.id, med.get_kind_name(), med.use_seconds])
	return true
