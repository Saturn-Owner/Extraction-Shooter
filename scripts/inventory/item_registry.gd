## Zentrale Nachschlagetabelle aller Item-Vorlagen.
##
## Bewusst STATISCH und kein Autoload: So ist die Registry überall gleich
## erreichbar — im Spiel, im Editor und in Headless-Tests. Autoloads stehen
## im `--script`-Modus nicht zur Verfügung, und Tests, die man nicht laufen
## lassen kann, sind wertlos.
##
## Warum es die Registry überhaupt gibt: Über das Netzwerk und in die Datenbank
## schicken wir nur die ID (&"ammo_556x45_m995"), nie das Objekt oder einen
## Dateipfad. Der Empfänger schlägt die Vorlage hier nach. Das hält die
## Datenmenge klein und verhindert, dass ein Client sich eigene Items ausdenkt —
## er kann nur IDs nennen, die der Server bereits kennt.
class_name ItemRegistry
extends RefCounted

const DATA_ROOT := "res://assets/data"

static var _items: Dictionary = {}
static var _loaded := false


## Lädt einmalig alle Vorlagen. Weitere Aufrufe kosten nichts.
static func ensure_loaded() -> void:
	if not _loaded:
		reload()


## Liest alle .tres unterhalb von assets/data neu ein.
static func reload() -> void:
	_items.clear()
	_scan_directory(DATA_ROOT)
	_loaded = true


static func _scan_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[ItemRegistry] Ordner nicht lesbar: %s" % path)
		return

	for sub in dir.get_directories():
		_scan_directory("%s/%s" % [path, sub])

	for file in dir.get_files():
		# Godot benennt Ressourcen im Export zu .remap um.
		var clean := file.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		_register_file("%s/%s" % [path, clean])


static func _register_file(full_path: String) -> void:
	var res := load(full_path)
	if res == null:
		push_error("[ItemRegistry] Konnte nicht laden: %s" % full_path)
		return
	if not (res is ItemData):
		return

	var item := res as ItemData
	var problems := item.validate()
	if not problems.is_empty():
		push_error("[ItemRegistry] %s ist fehlerhaft: %s" % [full_path, ", ".join(problems)])
		return
	if _items.has(item.id):
		push_error("[ItemRegistry] Doppelte Item-ID '%s' in %s" % [item.id, full_path])
		return

	_items[item.id] = item


## Vorlage zu einer ID, oder null wenn unbekannt.
static func get_item(id: StringName) -> ItemData:
	ensure_loaded()
	return _items.get(id)


static func has_item(id: StringName) -> bool:
	ensure_loaded()
	return _items.has(id)


static func get_count() -> int:
	ensure_loaded()
	return _items.size()


static func get_all_ids() -> Array[StringName]:
	ensure_loaded()
	var ids: Array[StringName] = []
	for key in _items.keys():
		ids.append(key)
	return ids


## Alle Items einer Kategorie — praktisch für Händlersortimente.
static func get_by_category(category: ItemData.Category) -> Array[ItemData]:
	ensure_loaded()
	var result: Array[ItemData] = []
	for item in _items.values():
		if item.category == category:
			result.append(item)
	return result
