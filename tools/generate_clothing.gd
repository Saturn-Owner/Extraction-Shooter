## Legt Kleidung und Helme an.
##
##   godot --headless --path . --script res://tools/generate_clothing.gd
##
## Einmaliger Generator wie generate_supplies.gd.
##
## ---------------------------------------------------------------------------
## BALANCING-GEDANKE: ISOLIERUNG GEGEN GEWICHT
##
## Kleidung ist die Gegenrechnung zum Tempo-Bonus für ein leeres Inventar.
## Wer leicht reist, ist schnell — und friert. Wer sich warm anzieht, ist
## sicher, aber langsamer und hat weniger Traglast für Beute übrig.
##
## Die Isolierungswerte sind so gesetzt, dass eine VOLLSTÄNDIGE Grundausrüstung
## (Mütze, Jacke, Hose, Stiefel) gerade so ausreicht, um bei -18 Grad nicht
## abzusinken. Wer ein Teil weglässt, hat eine Frist statt Sicherheit —
## genau die Spannung, die das Kältesystem tragen soll.
extends SceneTree

const OUT_DIR := "res://assets/data/clothing"

const ITEMS := [
	# --- Kopf ---------------------------------------------------------------
	{
		id = "head_wool_cap", name = "Wollmuetze", slot = ItemData.EquipSlot.HEAD,
		category = ItemData.Category.CLOTHING,
		desc = "Ausgeleiert und fusselig. Haelt trotzdem mehr Waerme als jeder Helm.",
		w = 1, h = 1, kg = 0.12, price = 120, insulation = 1.6,
	},
	{
		id = "head_steel_helmet", name = "Stahlhelm", slot = ItemData.EquipSlot.HEAD,
		category = ItemData.Category.CLOTHING,
		desc = "Alt, schwer, verbeult. Faengt Splitter ab - gegen ein Gewehr hilft er nicht, und kalt ist er obendrein.",
		w = 2, h = 2, kg = 1.4, price = 4200, insulation = 0.2,
	},

	# --- Oberkoerper --------------------------------------------------------
	{
		id = "shirt_thermal", name = "Thermounterhemd", slot = ItemData.EquipSlot.SHIRT,
		category = ItemData.Category.CLOTHING,
		desc = "Unscheinbar und unbezahlbar. Die Schicht, die man zuerst anzieht und zuletzt auszieht.",
		w = 2, h = 2, kg = 0.3, price = 380, insulation = 2.2,
	},
	{
		id = "shirt_winter_coat", name = "Wintermantel", slot = ItemData.EquipSlot.SHIRT,
		category = ItemData.Category.CLOTHING,
		desc = "Dick gefuettert, an drei Stellen geflickt. Sperrig, aber der Unterschied zwischen Bleiben und Umkehren.",
		w = 3, h = 3, kg = 2.1, price = 2600, insulation = 4.5,
	},

	# --- Guertel ------------------------------------------------------------
	{
		id = "belt_utility", name = "Koppelgurt", slot = ItemData.EquipSlot.BELT,
		category = ItemData.Category.CLOTHING,
		desc = "Breites Leder mit Metallschnalle. Traegt Gewicht an der Huefte statt an den Schultern.",
		w = 2, h = 1, kg = 0.4, price = 540, insulation = 0.1,
	},

	# --- Beine --------------------------------------------------------------
	{
		id = "pants_cargo", name = "Arbeitshose", slot = ItemData.EquipSlot.PANTS,
		category = ItemData.Category.CLOTHING,
		desc = "Robust, viele Taschen, null Waerme. Besser als nichts, schlechter als alles andere.",
		w = 2, h = 2, kg = 0.6, price = 210, insulation = 1.0,
	},
	{
		id = "pants_insulated", name = "Thermohose", slot = ItemData.EquipSlot.PANTS,
		category = ItemData.Category.CLOTHING,
		desc = "Gefuettert und windabweisend. Wer sie einmal getragen hat, geht ohne sie nicht mehr raus.",
		w = 2, h = 3, kg = 1.1, price = 1750, insulation = 3.0,
	},

	# --- Fuesse -------------------------------------------------------------
	{
		id = "boots_worn", name = "Abgelaufene Stiefel", slot = ItemData.EquipSlot.BOOTS,
		category = ItemData.Category.CLOTHING,
		desc = "Sohle duenn, Naht offen. Schnee kommt durch - und nasse Fuesse frieren am schnellsten.",
		w = 2, h = 2, kg = 0.9, price = 160, insulation = 0.8,
	},
	{
		id = "boots_winter", name = "Winterstiefel", slot = ItemData.EquipSlot.BOOTS,
		category = ItemData.Category.CLOTHING,
		desc = "Gefuettert, hoher Schaft, griffige Sohle. Schwer, aber man steht damit stundenlang im Schnee.",
		w = 2, h = 3, kg = 1.8, price = 2200, insulation = 2.6,
	},
]


func _initialize() -> void:
	print("=== Kleidung anlegen ===\n")

	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var written := 0
	var total_insulation := 0.0
	for entry in ITEMS:
		if _write_item(entry):
			written += 1

	# Zur Kontrolle: Reicht eine warme Grundausruestung wirklich?
	for id in ["head_wool_cap", "shirt_winter_coat", "pants_insulated", "boots_winter"]:
		for entry in ITEMS:
			if entry.id == id:
				total_insulation += entry.insulation

	print("\n%d Dateien geschrieben nach %s" % [written, OUT_DIR])
	print("Warme Grundausruestung ergibt Isolierung %.1f" % total_insulation)
	quit(0)


func _write_item(entry: Dictionary) -> bool:
	var item := ItemData.new()
	item.id = StringName(entry.id)
	item.display_name = entry.name
	item.description = entry.desc
	item.category = entry.category
	item.equip_slot = entry.slot
	item.insulation = entry.insulation
	item.grid_width = entry.w
	item.grid_height = entry.h
	item.weight_kg = entry.kg
	item.max_stack = 1
	item.base_price = entry.price
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

	print("  %-22s %-12s %dx%d  %4.2f kg  Isolierung %.1f  %6d" % [
		entry.id, Equipment.get_slot_name(entry.slot),
		entry.w, entry.h, entry.kg, entry.insulation, entry.price,
	])
	return true
