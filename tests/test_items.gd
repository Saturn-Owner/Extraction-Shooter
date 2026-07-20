## Gegenstaende, die es im Spiel gerade NICHT gibt, die Tests aber brauchen.
##
## Verpflegung, Medizin, Werkzeug, Kleidung und Platten sind aus dem Spiel
## geflogen — die kommen spaeter zurueck. Ohne Ersatz waeren damit still und
## leise auch die Pruefungen verschwunden, die an ihnen haengen:
##
##   * Rucksack      — verschachtelte Container, Gewicht des Inhalts
##   * Kleidung      — Waerme und Ausruestungsplaetze
##
## Genau das waere der gefaehrliche Fall: Tests, die nichts mehr pruefen, aber
## weiter gruen leuchten. Deshalb werden die Vorlagen hier im Code gebaut und
## zur Laufzeit eingetragen. Die Werte sind die der geloeschten Dateien.
##
## Wenn die echten Gegenstaende zurueckkommen, kann diese Datei weg.
##
## Die Schutzplatte hat diesen Weg bereits hinter sich: Sie stand hier, ist
## seit 2026-07-20 wieder eine echte Datei und wurde deshalb entfernt. Das ist
## die Richtung, in die diese Datei schrumpfen soll.
class_name TestItems
extends RefCounted


## Traegt alle Ersatzvorlagen ein. Mehrfaches Aufrufen schadet nicht.
##
## Die Schutzplatte steht hier bewusst NICHT mehr: Sie ist als echte Datei
## zurueck (assets/data/armor/plate_class4.tres). Stuende sie noch hier,
## wuerde ItemRegistry.register() die echte Datei ueberschreiben — und die
## Durchschlagstests pruefen wieder nur sich selbst statt das Spiel.
static func install() -> void:
	ItemRegistry.register(make_backpack())
	ItemRegistry.register(make_coat())
	ItemRegistry.register(make_boots())
	ItemRegistry.register(make_thermal_shirt())


static func make_backpack() -> ItemData:
	var pack := ItemData.new()
	pack.id = &"backpack_small"
	pack.display_name = "Kleiner Rucksack"
	pack.category = ItemData.Category.BACKPACK
	pack.equip_slot = ItemData.EquipSlot.BACKPACK
	pack.grid_width = 4
	pack.grid_height = 4
	pack.can_rotate = false
	pack.container_width = 5
	pack.container_height = 4
	pack.weight_kg = 1.2
	pack.max_stack = 1
	pack.base_price = 8200
	return pack


static func make_coat() -> ItemData:
	var coat := ItemData.new()
	coat.id = &"shirt_winter_coat"
	coat.display_name = "Wintermantel"
	coat.category = ItemData.Category.CLOTHING
	coat.equip_slot = ItemData.EquipSlot.SHIRT
	coat.insulation = 4.5
	coat.grid_width = 3
	coat.grid_height = 3
	coat.can_rotate = false
	coat.weight_kg = 2.1
	coat.base_price = 2600
	return coat


## Ein zweites Oberteil — damit sich pruefen laesst, dass ein belegter Platz
## den alten Gegenstand herausgibt, statt ihn zu verschlucken.
static func make_thermal_shirt() -> ItemData:
	var shirt := ItemData.new()
	shirt.id = &"shirt_thermal"
	shirt.display_name = "Thermounterhemd"
	shirt.category = ItemData.Category.CLOTHING
	shirt.equip_slot = ItemData.EquipSlot.SHIRT
	shirt.insulation = 2.2
	shirt.grid_width = 2
	shirt.grid_height = 2
	shirt.can_rotate = false
	shirt.weight_kg = 0.3
	shirt.base_price = 380
	return shirt


static func make_boots() -> ItemData:
	var boots := ItemData.new()
	boots.id = &"boots_winter"
	boots.display_name = "Winterstiefel"
	boots.category = ItemData.Category.CLOTHING
	boots.equip_slot = ItemData.EquipSlot.BOOTS
	boots.insulation = 2.6
	boots.grid_width = 2
	boots.grid_height = 3
	boots.weight_kg = 1.8
	boots.base_price = 2200
	return boots
