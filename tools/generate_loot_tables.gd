## Erzeugt die Loot-Tabellen als .tres-Dateien.
##
##   godot --headless --path . --script res://tools/generate_loot_tables.gd
##
## ACHTUNG — EINMAL-WERKZEUG (wie generate_arsenal.gd):
## Danach sind die .tres die Wahrheit. Wer hier nochmal draufdrueckt,
## ueberschreibt alle Balancing-Aenderungen aus dem Editor.
##
## ---------------------------------------------------------------------------
## BALANCING-GEDANKE
##
## Die Tabellen sind absichtlich sehr unterschiedlich, damit sich der Weg zu
## gefaehrlichen Orten lohnt:
##
##   Wohnung       viel Muell, gelegentlich Pistolenmunition. Sicher, arm.
##   Werkstatt     Mittelklasse, brauchbare Munition, selten eine Waffe.
##   Militaerkiste Panzerbrechende Munition, Platten, gute Waffen. Selten.
##
## Wer nur Wohnungen abklappert, kommt nie an M995. Wer ins Militaerlager
## geht, riskiert dafuer etwas. Genau das soll die Karte spannend machen.
extends SceneTree

const OUT_DIR := "res://assets/data/loot"

const TABLES := {
	"wohnung": {
		min_rolls = 1, max_rolls = 4, empty = 45,
		entries = [
			{id = "ammo_9x19_fmj", weight = 55, min = 4, max = 16},
			{id = "ammo_9x19_hp", weight = 22, min = 3, max = 10},
			{id = "ammo_12x70_buckshot", weight = 18, min = 2, max = 6},
			{id = "ammo_556x45_hp", weight = 12, min = 5, max = 14},
			{id = "backpack_small", weight = 8, min = 1, max = 1},
			{id = "weapon_pistol_g17", weight = 4, min = 1, max = 1},
		],
	},
	"werkstatt": {
		min_rolls = 2, max_rolls = 4, empty = 30,
		entries = [
			{id = "ammo_762x39_ps", weight = 40, min = 10, max = 30},
			{id = "ammo_556x45_m855", weight = 35, min = 10, max = 30},
			{id = "ammo_545x39_ps", weight = 35, min = 10, max = 30},
			{id = "ammo_12x70_slug", weight = 20, min = 3, max = 8},
			{id = "ammo_9x19_ap", weight = 14, min = 8, max = 20},
			{id = "plate_class4_front", weight = 10, min = 1, max = 1},
			{id = "weapon_shotgun_m870", weight = 7, min = 1, max = 1},
			{id = "weapon_rifle_akm", weight = 5, min = 1, max = 1},
			{id = "weapon_smg_mp5", weight = 4, min = 1, max = 1},
		],
	},
	"militaer": {
		min_rolls = 2, max_rolls = 5, empty = 18,
		entries = [
			{id = "ammo_556x45_m855a1", weight = 32, min = 20, max = 60},
			{id = "ammo_762x51_m80", weight = 24, min = 10, max = 30},
			{id = "ammo_545x39_bt", weight = 22, min = 20, max = 60},
			{id = "plate_class4_front", weight = 20, min = 1, max = 2},
			{id = "ammo_762x39_bp", weight = 16, min = 15, max = 40},
			{id = "ammo_556x45_m995", weight = 10, min = 10, max = 30},
			{id = "ammo_545x39_bs", weight = 9, min = 10, max = 30},
			{id = "weapon_rifle_ak74m", weight = 8, min = 1, max = 1},
			{id = "weapon_rifle_ar15", weight = 7, min = 1, max = 1},
			{id = "ammo_762x51_m61", weight = 5, min = 10, max = 20},
			{id = "weapon_rifle_scar_h", weight = 3, min = 1, max = 1},
			{id = "weapon_dmr_svd", weight = 2, min = 1, max = 1},
		],
	},
}


func _initialize() -> void:
	print("=== Loot-Tabellen erzeugen ===\n")
	ItemRegistry.ensure_loaded()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var errors := 0
	for name in TABLES.keys():
		if not _write_table(name, TABLES[name]):
			errors += 1

	print("\n%d Tabellen erzeugt, %d Fehler." % [TABLES.size() - errors, errors])
	quit(1 if errors > 0 else 0)


func _write_table(name: String, config: Dictionary) -> bool:
	var table := LootTableData.new()
	table.min_rolls = config.min_rolls
	table.max_rolls = config.max_rolls
	table.empty_weight = config.empty

	var entries: Array[Dictionary] = []
	for e in config.entries:
		# Frueh pruefen statt erst im Spiel — ein Tippfehler in einer Item-ID
		# faellt sonst erst auf, wenn jemand die Kiste oeffnet.
		if not ItemRegistry.has_item(StringName(e.id)):
			push_error("Unbekanntes Item in Tabelle '%s': %s" % [name, e.id])
			return false
		entries.append({
			"id": e.id,
			"weight": e.weight,
			"min": e.min,
			"max": e.max,
		})
	table.entries = entries

	var path := "%s/%s.tres" % [OUT_DIR, name]
	var err := ResourceSaver.save(table, path)
	if err != OK:
		push_error("Konnte %s nicht speichern (Fehler %d)" % [path, err])
		return false

	print("  %-12s %d Eintraege, %d-%d Zuege, %d%% Leerchance je Zug"
		% [name, entries.size(), table.min_rolls, table.max_rolls,
		   int(100.0 * table.empty_weight / float(table.empty_weight + _total_weight(entries)))])
	return true


func _total_weight(entries: Array[Dictionary]) -> int:
	var total := 0
	for e in entries:
		total += int(e.weight)
	return total
