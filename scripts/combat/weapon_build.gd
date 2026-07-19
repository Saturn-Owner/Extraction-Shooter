## Die Bestückung einer Waffe und die Berechnung ihrer effektiven Werte.
##
## WARUM ES DIESE KLASSE GIBT
##
## `ItemRegistry.get_item()` liefert für jede Waffe DIESELBE Ressource an alle
## Aufrufer. Würde man die Werte einer bestückten AR-15 direkt darin ändern,
## bekäme jede AR-15 im Spiel gleichzeitig einen Schalldämpfer — genau der
## Fehler, den item_stack.gd für Platten beschreibt.
##
## Deshalb: Die Vorlage bleibt unangetastet, und `apply()` liefert eine
## eigenständige Kopie mit aufgerechneten Modifikatoren zurück.
##
## Nachgemessen, nicht angenommen: `duplicate(true)` kopiert in Godot 4.7
## verschachtelte Arrays wie `fire_modes` sauber, lässt das Feld `viewmodel`
## aber als dieselbe Script-Referenz stehen — `create_viewmodel()` funktioniert
## an der Kopie also weiterhin. Ausserdem ist `resource_path` der Kopie leer,
## sie landet also nie im Ressourcen-Cache. `duplicate(false)` wäre falsch:
## Dabei teilen sich Kopie und Vorlage das `fire_modes`-Array.
##
## Alle Modifikatoren sind kommutativ (Multiplikation und Addition) — die
## Reihenfolge der Anbauteile ist also egal. Einzige Ausnahme ist
## `ads_fov_override`, und das kann nur ein Visier setzen, von dem es pro
## Waffe genau eines gibt.
class_name WeaponBuild
extends RefCounted

## Was in welchem Steckplatz sitzt: {int(AttachmentData.Slot): StringName}.
var attachments: Dictionary = {}


## Bestückung aus einem Inventar-Exemplar lesen.
static func from_stack(stack: ItemStack) -> WeaponBuild:
	var build := WeaponBuild.new()
	if stack != null:
		build.attachments = stack.attachments.duplicate()
	return build


func is_empty() -> bool:
	return attachments.is_empty()


func get_attachment_id(slot: AttachmentData.Slot) -> StringName:
	return attachments.get(int(slot), &"")


func get_attachment(slot: AttachmentData.Slot) -> AttachmentData:
	var id: StringName = get_attachment_id(slot)
	if id == &"":
		return null
	return ItemRegistry.get_item(id) as AttachmentData


## Alle montierten Teile, in fester Reihenfolge der Steckplätze.
func get_all() -> Array[AttachmentData]:
	var result: Array[AttachmentData] = []
	for slot in [AttachmentData.Slot.SIGHT, AttachmentData.Slot.MUZZLE,
			AttachmentData.Slot.GRIP, AttachmentData.Slot.FOREGRIP]:
		var attachment := get_attachment(slot)
		if attachment != null:
			result.append(attachment)
	return result


func set_attachment(slot: AttachmentData.Slot, id: StringName) -> void:
	if id == &"":
		attachments.erase(int(slot))
	else:
		attachments[int(slot)] = id


func clear_slot(slot: AttachmentData.Slot) -> void:
	attachments.erase(int(slot))


func duplicate_build() -> WeaponBuild:
	var copy := WeaponBuild.new()
	copy.attachments = attachments.duplicate()
	return copy


## Die effektiven Werte einer bestückten Waffe.
##
## Gibt IMMER eine Kopie zurück, auch ohne Anbauteile — sonst wäre `data`
## mal die Vorlage und mal eine Kopie, und genau solche Unterschiede
## übersieht man später.
static func apply(base: WeaponData, build: WeaponBuild) -> WeaponData:
	if base == null:
		return null

	var result := base.duplicate(true) as WeaponData
	if build == null or build.is_empty():
		return result

	for attachment in build.get_all():
		# Nur montieren, was auch passt. Eine unpassende Bestückung ist ein
		# Fehler weiter oben, darf hier aber nicht still die Werte verbiegen.
		if not base.accepts_attachment(attachment):
			push_warning("[WeaponBuild] %s passt nicht an %s — Werte ignoriert"
				% [attachment.id, base.id])
			continue

		result.recoil_vertical *= attachment.recoil_vertical_mult
		result.recoil_horizontal *= attachment.recoil_horizontal_mult
		result.ergonomics += attachment.ergonomics_delta
		result.accuracy_moa *= attachment.accuracy_moa_mult
		result.ads_spread_multiplier *= attachment.ads_spread_mult
		result.ads_move_multiplier *= attachment.ads_move_mult
		result.ads_time_multiplier *= attachment.ads_time_mult
		result.muzzle_velocity_modifier += attachment.muzzle_velocity_delta
		result.loudness_multiplier *= attachment.loudness_mult

		# Zoom ersetzt statt zu multiplizieren: Ein Zielfernrohr gibt seine
		# Vergrösserung vor, sie hängt nicht am Wert der Waffe.
		if not is_zero_approx(attachment.ads_fov_override):
			result.ads_fov = attachment.ads_fov_override

	_clamp_to_valid_range(result)
	return result


## Hält die Werte in dem Bereich, den die Waffenlogik erwartet.
##
## Ohne das könnte eine Kette günstiger Teile die Ergonomie über 100 treiben
## oder die Streuung auf null — beides rechnet weiter unten falsch.
static func _clamp_to_valid_range(data: WeaponData) -> void:
	data.recoil_vertical = maxf(0.0, data.recoil_vertical)
	data.recoil_horizontal = maxf(0.0, data.recoil_horizontal)
	data.ergonomics = clampi(data.ergonomics, 0, 100)
	data.accuracy_moa = clampf(data.accuracy_moa, 0.1, 20.0)
	data.ads_spread_multiplier = clampf(data.ads_spread_multiplier, 0.05, 1.0)
	data.ads_move_multiplier = clampf(data.ads_move_multiplier, 0.2, 1.0)
	data.ads_time_multiplier = clampf(data.ads_time_multiplier, 0.4, 3.0)
	data.muzzle_velocity_modifier = clampf(data.muzzle_velocity_modifier, 0.5, 1.4)
	data.loudness_multiplier = clampf(data.loudness_multiplier, 0.05, 2.0)
	data.ads_fov = clampf(data.ads_fov, 8.0, 75.0)
