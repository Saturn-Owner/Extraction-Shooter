## Legt Verpflegung, Medizin, Krimskrams und Werkzeug an.
##
##   godot --headless --path . --script res://tools/generate_supplies.gd
##
## Einmaliger Generator, wie generate_arsenal.gd. Danach werden die
## .tres-Dateien von Hand gepflegt — der Generator dient nur dazu, nicht
## vierzig Dateien einzeln tippen zu müssen.
##
## WARUM DIESE KATEGORIEN:
## Bisher gab es ausschliesslich Munition, Waffen, eine Platte und einen
## Rucksack. Eine Kiste konnte also gar nichts anderes ausspucken. Damit
## fehlte dem Looten die Breite: Wer nur Munition findet, trifft keine
## Entscheidung, was er mitnimmt — und ohne Verpflegung gibt es später
## kein Survival-System, auf das man aufbauen kann.
##
## PREISE bestimmen die Seltenheitsstufe (siehe ItemData.get_rarity):
##   unter 150   grau      150+  gruen      500+  blau
##   5000+       gold      20000+ rot
## Die Werte hier sind bewusst so gewählt, dass Krimskrams grau bleibt und
## nur echte Fundstücke farbig werden.
extends SceneTree

const OUT_DIR := "res://assets/data/supplies"


## Kategorien werden ueber ItemData.Category benannt, NICHT als Zahl.
## Beim ersten Versuch hatte ich sie durchnummeriert und mich um zwei
## verzaehlt — Medizin wurde zu Verpflegung, Werkzeug zu einem Index, den
## es gar nicht gibt. Dieselbe Falle hat auch den Rucksack erwischt, der
## im Projekt jahrelang als "Medizin" gefuehrt wurde.
const ITEMS := [
	# --- Verpflegung -------------------------------------------------------
	{
		id = "food_cracker_pack", name = "Kekspackung", category = ItemData.Category.FOOD,
		desc = "Trockene Kekse in Folie. Kein Genuss, aber sie halten den Magen ruhig.",
		w = 1, h = 1, kg = 0.15, stack = 3, price = 45,
	},
	{
		id = "food_canned_meat", name = "Fleischkonserve", category = ItemData.Category.FOOD,
		desc = "Dose ohne Etikett. Der Inhalt ist noch gut, solange die Dose nicht gewoelbt ist.",
		w = 1, h = 1, kg = 0.4, stack = 2, price = 130,
	},
	{
		id = "food_water_bottle", name = "Wasserflasche", category = ItemData.Category.FOOD,
		desc = "Halb voll und angetaut. Schnee essen kuehlt aus, das hier nicht.",
		w = 1, h = 2, kg = 0.6, stack = 1, price = 90,
	},
	{
		id = "food_coffee_tin", name = "Kaffeedose", category = ItemData.Category.FOOD,
		desc = "Ungeoeffnet. Vor dem Krieg ein Fruehstueck, heute ein Tauschmittel.",
		w = 1, h = 1, kg = 0.35, stack = 1, price = 620,
	},

	# --- Medizin -----------------------------------------------------------
	{
		id = "med_bandage", name = "Verband", category = ItemData.Category.MEDICAL,
		desc = "Sterile Mullbinde. Stoppt leichte Blutungen, gegen eine Arterie zwecklos.",
		w = 1, h = 1, kg = 0.05, stack = 4, price = 160,
	},
	{
		id = "med_tourniquet", name = "Aderpresse", category = ItemData.Category.MEDICAL,
		desc = "Schnuert das Glied ab. Rettet gegen schwere Blutungen - kostet aber das Glied, wenn sie zu lange sitzt.",
		w = 1, h = 1, kg = 0.08, stack = 2, price = 780,
	},
	{
		id = "med_splint", name = "Schiene", category = ItemData.Category.MEDICAL,
		desc = "Aluminium und Klettband. Ein gebrochenes Bein traegt damit wieder, aber es bleibt gebrochen.",
		w = 1, h = 2, kg = 0.2, stack = 1, price = 540,
	},
	{
		id = "med_painkillers", name = "Schmerzmittel", category = ItemData.Category.MEDICAL,
		desc = "Blisterstreifen. Nimmt den Schmerz, nicht die Verletzung - man laeuft weiter und merkt zu spaet, wie schlecht es steht.",
		w = 1, h = 1, kg = 0.03, stack = 3, price = 410,
	},
	{
		id = "med_first_aid_kit", name = "Erste-Hilfe-Kasten", category = ItemData.Category.MEDICAL,
		desc = "Vollstaendig und versiegelt. Wer den findet, hat den Raid schon fast bezahlt.",
		w = 2, h = 2, kg = 1.1, stack = 1, price = 5400,
	},

	# --- Krimskrams (Tauschware) ------------------------------------------
	{
		id = "misc_screws", name = "Schraubensortiment", category = ItemData.Category.MISC,
		desc = "Eine Handvoll Schrauben in einer Blechdose. Klappert beim Laufen.",
		w = 1, h = 1, kg = 0.3, stack = 5, price = 35,
	},
	{
		id = "misc_wire_spool", name = "Kabelrolle", category = ItemData.Category.MISC,
		desc = "Kupferdraht, teilweise abisoliert. Der Werkstatt-Ausbau frisst so etwas in Mengen.",
		w = 1, h = 1, kg = 0.5, stack = 3, price = 85,
	},
	{
		id = "misc_gear_wheel", name = "Zahnrad", category = ItemData.Category.MISC,
		desc = "Schwer, geoelt, unbeschaedigt. Aus einem Getriebe, das jemand vor dem Winter ausgebaut hat.",
		w = 1, h = 1, kg = 0.8, stack = 2, price = 240,
	},
	{
		id = "misc_car_battery", name = "Autobatterie", category = ItemData.Category.MISC,
		desc = "Haelt noch Ladung. Sperrig und schwer - wer die mitnimmt, laesst etwas anderes liegen.",
		w = 2, h = 2, kg = 12.0, stack = 1, price = 1900,
	},
	{
		id = "misc_gold_chain", name = "Goldkette", category = ItemData.Category.MISC,
		desc = "Vor dem Winter ein Geschenk, heute Gewicht in Gold. Passt in die Hosentasche.",
		w = 1, h = 1, kg = 0.05, stack = 1, price = 7400,
	},

	# --- Werkzeug ----------------------------------------------------------
	{
		id = "tool_multitool", name = "Multitool", category = ItemData.Category.TOOL,
		desc = "Zange, Klinge, Schraubendreher. Nichts davon richtig gut, alles davon brauchbar.",
		w = 1, h = 1, kg = 0.25, stack = 1, price = 890,
	},
	{
		id = "tool_crowbar", name = "Brecheisen", category = ItemData.Category.TOOL,
		desc = "Oeffnet, was verschlossen ist, und taugt zur Not als Waffe. Kalt genug, dass die Hand daran klebt.",
		w = 1, h = 3, kg = 2.4, stack = 1, price = 1250,
	},
	{
		id = "tool_ice_axe", name = "Eispickel", category = ItemData.Category.TOOL,
		desc = "Ohne den kommt niemand die vereiste Klippe hoch. Der Weg dorthin ist kuerzer - wenn man ihn dabei hat.",
		w = 1, h = 3, kg = 1.1, stack = 1, price = 3200,
	},
]


func _initialize() -> void:
	print("=== Verpflegung, Medizin, Krimskrams, Werkzeug anlegen ===\n")

	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var written := 0
	for entry in ITEMS:
		if _write_item(entry):
			written += 1

	print("\n%d Dateien geschrieben nach %s" % [written, OUT_DIR])
	quit(0)


func _write_item(entry: Dictionary) -> bool:
	var item := ItemData.new()
	item.id = StringName(entry.id)
	item.display_name = entry.name
	item.description = entry.desc
	item.category = entry.category
	item.grid_width = entry.w
	item.grid_height = entry.h
	item.weight_kg = entry.kg
	item.max_stack = entry.stack
	item.base_price = entry.price
	# Ein 1x1-Gegenstand laesst sich nicht sinnvoll drehen.
	item.can_rotate = entry.w != entry.h

	var problems := item.validate()
	if not problems.is_empty():
		printerr("  FEHLER %s: %s" % [entry.id, ", ".join(problems)])
		return false

	var path := "%s/%s.tres" % [OUT_DIR, entry.id]
	var err := ResourceSaver.save(item, path)
	if err != OK:
		printerr("  FEHLER beim Speichern: %s (%d)" % [path, err])
		return false

	print("  %-22s %-14s %dx%d  %5.2f kg  %6d" % [
		entry.id, ItemData.Category.keys()[entry.category],
		entry.w, entry.h, entry.kg, entry.price,
	])
	return true
