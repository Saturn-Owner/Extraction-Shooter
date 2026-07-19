## Testgelände für Bewegung und Ballistik.
##
## Zweck: Werte ausprobieren und im Blick haben. Das ist KEIN Spielinhalt,
## sondern eine Werkbank — sie fliegt raus, sobald es echte Level gibt.
##
## Das HUD gibt es aus einem bestimmten Grund: Claude kann nicht fühlen, ob
## sich Bewegung und Schiessen richtig anfühlen. Wenn ihr konkrete Zahlen
## seht, lässt sich das gezielt ändern — bei "fühlt sich komisch an" nicht.
##
## Steuerung:
##   WASD          Gehen
##   Shift         Sprinten (nur vorwärts, kostet Ausdauer)
##   Strg          Ducken
##   Leertaste     Springen
##   Linksklick    Schiessen
##   R             Nachladen
##   B             Feuermodus wechseln
##   Q / E         Waffe wechseln
##   F / G         Munition wechseln
##   1 / 2         Traglast +- 1 kg
##   3 / 4         Traglast +- 5 kg
##   0             Zurück zum Start, Ziele zurücksetzen
##   Esc           Maus freigeben
extends Node3D

## Durchschaltbare Waffen zum Ausprobieren des gesamten Arsenals.
const WEAPON_CYCLE: Array[StringName] = [
	&"weapon_rifle_ar15",
	&"weapon_rifle_ak74m",
	&"weapon_rifle_akm",
	&"weapon_smg_mp5",
	&"weapon_pistol_g17",
	&"weapon_shotgun_m870",
	&"weapon_dmr_svd",
	&"weapon_sniper_axmc",
	&"weapon_rifle_scar_h",
]

@onready var _player: PlayerController = $Player
@onready var _label: Label = $HUD/DebugPanel/DebugLabel

var _spawn: Vector3
var _weapon_index := 0
var _ammo_index := 0
var _available_ammo: Array[StringName] = []
var _last_hit := "noch kein Treffer"


func _ready() -> void:
	_spawn = _player.global_position
	# Bewusst leer starten, damit man den Tempo-Bonus sofort spürt.
	_player.carried_weight_kg = 0.0

	for target in get_tree().get_nodes_in_group("ziele"):
		if target is TargetDummy:
			(target as TargetDummy).was_hit.connect(_on_target_hit.bind(target))

	# Ziele automatisch registrieren, falls die Gruppe nicht gesetzt ist.
	for target in _find_targets():
		if not target.was_hit.is_connected(_on_target_hit):
			target.was_hit.connect(_on_target_hit.bind(target))

	_refresh_ammo_list()


func _find_targets() -> Array[TargetDummy]:
	var result: Array[TargetDummy] = []
	var container := get_node_or_null("Ziele")
	if container == null:
		return result
	for child in container.get_children():
		if child is TargetDummy:
			result.append(child as TargetDummy)
	return result


func _on_target_hit(result: Ballistics.HitResult, _hits: int, target: TargetDummy) -> void:
	_last_hit = "%s: %s" % [target.label_text, result.describe()]


## Alle Munitionssorten, die in die aktuelle Waffe passen.
func _refresh_ammo_list() -> void:
	_available_ammo.clear()
	var weapon := _player.weapon
	if weapon == null or weapon.data == null:
		return

	for item in ItemRegistry.get_by_category(ItemData.Category.AMMO):
		var ammo := item as AmmoData
		if weapon.data.accepts_ammo(ammo):
			_available_ammo.append(ammo.id)
	_available_ammo.sort()

	_ammo_index = clampi(_ammo_index, 0, maxi(0, _available_ammo.size() - 1))
	if not _available_ammo.is_empty():
		weapon.setup(weapon.weapon_id, _available_ammo[_ammo_index])


func _switch_weapon(step: int) -> void:
	_weapon_index = wrapi(_weapon_index + step, 0, WEAPON_CYCLE.size())
	var weapon := _player.weapon
	if weapon == null:
		return

	# Erste passende Munition suchen, sonst laesst sich die Waffe nicht laden.
	var new_id := WEAPON_CYCLE[_weapon_index]
	var candidate := ItemRegistry.get_item(new_id) as WeaponData
	if candidate == null:
		return

	for item in ItemRegistry.get_by_category(ItemData.Category.AMMO):
		var ammo := item as AmmoData
		if candidate.accepts_ammo(ammo):
			weapon.setup(new_id, ammo.id)
			break

	_ammo_index = 0
	_refresh_ammo_list()


func _switch_ammo(step: int) -> void:
	if _available_ammo.is_empty():
		return
	_ammo_index = wrapi(_ammo_index + step, 0, _available_ammo.size())
	var weapon := _player.weapon
	if weapon != null:
		weapon.setup(weapon.weapon_id, _available_ammo[_ammo_index])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	match (event as InputEventKey).physical_keycode:
		KEY_1:
			_player.carried_weight_kg = minf(_player.carried_weight_kg + 1.0, 80.0)
		KEY_2:
			_player.carried_weight_kg = maxf(_player.carried_weight_kg - 1.0, 0.0)
		KEY_3:
			_player.carried_weight_kg = minf(_player.carried_weight_kg + 5.0, 80.0)
		KEY_4:
			_player.carried_weight_kg = maxf(_player.carried_weight_kg - 5.0, 0.0)
		KEY_Q:
			_switch_weapon(-1)
		KEY_E:
			_switch_weapon(1)
		KEY_F:
			_switch_ammo(-1)
		KEY_G:
			_switch_ammo(1)
		KEY_0:
			_player.global_position = _spawn
			_player.velocity = Vector3.ZERO
			for target in _find_targets():
				target.reset()
			_last_hit = "zurückgesetzt"


func _process(_delta: float) -> void:
	var horizontal := Vector3(_player.velocity.x, 0.0, _player.velocity.z)

	var haltung := "stehend"
	if _player.is_crouching:
		haltung = "geduckt"
	elif _player.is_sprinting:
		haltung = "sprintend"

	var factor := _player.get_weight_factor()
	var last_hint := "leicht, +Tempo"
	if factor < 0.999:
		last_hint = "beladen, -Tempo"
	elif factor <= 1.001:
		last_hint = "Komfortgrenze"

	var lines := [
		"Tempo:      %.2f / %.2f m/s" % [horizontal.length(), _player.get_current_max_speed()],
		"Haltung:    %s" % haltung,
		"Ausdauer:   %.0f / %.0f" % [_player.stamina, _player.max_stamina],
		"Traglast:   %.1f kg  (Faktor %.2f, %s)" % [_player.carried_weight_kg, factor, last_hint],
	]

	var weapon := _player.weapon
	if weapon != null and weapon.data != null:
		lines.append("")
		lines.append("Waffe:      %s" % weapon.get_status_text())
		if weapon.loaded_ammo != null:
			var a := weapon.loaded_ammo
			lines.append("Munition:   %s" % a.get_stat_summary())
			lines.append("Reichweite: v0 %.0f m/s  Pen 100m %.1f" % [
				a.muzzle_velocity_ms,
				Ballistics.get_penetration_at_distance(a, 100.0),
			])
		lines.append("Treffer:    %s" % _last_hit)

	lines.append("")
	lines.append("Q/E Waffe  F/G Munition  R Laden  B Modus")
	lines.append("1-4 Gewicht   0 Reset   Esc Maus")

	_label.text = "\n".join(lines)
