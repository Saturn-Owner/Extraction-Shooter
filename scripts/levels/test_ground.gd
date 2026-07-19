## Testgelände für Bewegung, Ballistik und Inventar.
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
##   R             Nachladen (verbraucht echte Munition aus dem Inventar)
##   B             Feuermodus wechseln
##   Q / E         Waffe wechseln (nur was im Inventar liegt)
##   F / G         Munition wechseln (nur was im Inventar liegt)
##   T             Munitionsnachschub (Testhilfe)
##   Z             Rucksack mit Ballast füllen (Gewicht spüren)
##   0             Zurück zum Start, Ziele und Ausrüstung zurücksetzen
##   Esc           Maus freigeben
extends Node3D

## Startausrüstung. Bewusst knapp gehalten, damit man merkt, dass Munition
## eine begrenzte Ressource ist und nicht selbstverständlich.
## Reihenfolge ist wichtig: Grosse Gegenstaende zuerst, sonst zerstueckeln
## die kleinen das Raster und der Rucksack findet keinen Platz mehr.
const LOADOUT := [
	{id = &"backpack_small", count = 1},
	{id = &"weapon_rifle_ar15", count = 1},
	{id = &"weapon_shotgun_m870", count = 1},
	{id = &"weapon_pistol_g17", count = 1},
	{id = &"ammo_556x45_m855a1", count = 60},
	{id = &"ammo_556x45_m995", count = 30},
	{id = &"ammo_9x19_fmj", count = 51},
	{id = &"ammo_12x70_buckshot", count = 20},
	{id = &"ammo_12x70_slug", count = 10},
]

@onready var _player: PlayerController = $Player
@onready var _label: Label = $HUD/DebugPanel/DebugLabel

var _spawn: Vector3
var _weapon_index := 0
var _ammo_index := 0
var _last_hit := "noch kein Treffer"
var _last_action := ""


func _ready() -> void:
	_spawn = _player.global_position

	for target in _find_targets():
		target.was_hit.connect(_on_target_hit.bind(target))

	_give_loadout()


## Füllt das Inventar und nimmt die erste Waffe in die Hand.
func _give_loadout() -> void:
	var inventory := _player.inventory
	if inventory == null:
		return

	for entry in LOADOUT:
		if not inventory.add(entry.id, entry.count):
			# Lauter Fehler statt stiller Warnung: Wenn die Startausruestung
			# nicht passt, ist das Raster zu klein und muss angepasst werden.
			push_error("[Testgelände] Kein Platz für %s — Raster zu klein" % entry.id)

	var weapons := inventory.get_carried_weapons()
	if not weapons.is_empty():
		_weapon_index = 0
		_player.equip_from_inventory(weapons[0])


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


func _switch_weapon(step: int) -> void:
	var inventory := _player.inventory
	if inventory == null:
		return
	var weapons := inventory.get_carried_weapons()
	if weapons.is_empty():
		_last_action = "keine weitere Waffe im Inventar"
		return

	_weapon_index = wrapi(_weapon_index + step, 0, weapons.size())
	_player.equip_from_inventory(weapons[_weapon_index])
	_ammo_index = 0
	_last_action = ""


func _switch_ammo(step: int) -> void:
	var inventory := _player.inventory
	var weapon := _player.weapon
	if inventory == null or weapon == null or weapon.data == null:
		return

	var options := inventory.get_compatible_ammo(weapon.data)
	if options.is_empty():
		_last_action = "keine passende Munition im Inventar"
		return

	options.sort()
	_ammo_index = wrapi(_ammo_index + step, 0, options.size())
	_player.switch_ammo(options[_ammo_index])
	_last_action = ""


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	var inventory := _player.inventory

	match (event as InputEventKey).physical_keycode:
		KEY_Q:
			_switch_weapon(-1)
		KEY_E:
			_switch_weapon(1)
		KEY_F:
			_switch_ammo(-1)
		KEY_G:
			_switch_ammo(1)
		KEY_T:
			# Testhilfe: Nachschub für alle Kaliber.
			for entry in LOADOUT:
				var data := ItemRegistry.get_item(entry.id)
				if data is AmmoData:
					inventory.add(entry.id, entry.count)
			_last_action = "Munition aufgefüllt"
		KEY_Z:
			# Ballast, um die Gewichtsbremse zu spüren.
			if inventory.add(&"plate_class4_front", 1):
				_last_action = "Platte eingepackt (+3.4 kg)"
			else:
				_last_action = "kein Platz mehr"
		KEY_0:
			_player.global_position = _spawn
			_player.velocity = Vector3.ZERO
			for target in _find_targets():
				target.reset()
			_last_hit = "zurückgesetzt"
			_last_action = ""


func _process(_delta: float) -> void:
	var horizontal := Vector3(_player.velocity.x, 0.0, _player.velocity.z)

	var haltung := "stehend"
	if _player.is_crouching:
		haltung = "geduckt"
	elif _player.is_sprinting:
		haltung = "sprintend"

	var factor := _player.get_weight_factor()
	var hint := "leicht, +Tempo"
	if factor < 0.999:
		hint = "beladen, -Tempo"
	elif factor <= 1.001:
		hint = "Komfortgrenze"

	var lines := [
		"Tempo:      %.2f / %.2f m/s" % [horizontal.length(), _player.get_current_max_speed()],
		"Haltung:    %s" % haltung,
		"Ausdauer:   %.0f / %.0f" % [_player.stamina, _player.max_stamina],
		"Traglast:   %.1f kg  (Faktor %.2f, %s)" % [_player.carried_weight_kg, factor, hint],
	]

	var weapon := _player.weapon
	var inventory := _player.inventory
	if weapon != null and weapon.data != null:
		lines.append("")
		lines.append("Waffe:      %s" % weapon.get_status_text())
		if weapon.loaded_ammo != null and inventory != null:
			lines.append("Vorrat:     %d Patronen im Inventar" % inventory.count_ammo(weapon.ammo_id))
			lines.append("Munition:   %s" % weapon.loaded_ammo.get_stat_summary())
		lines.append("Treffer:    %s" % _last_hit)

	if inventory != null:
		lines.append("Inventar:   %d Gegenstaende, %d Felder frei" % [
			inventory.grid.get_item_count(), inventory.grid.get_free_cell_count()])

	if _last_action != "":
		lines.append("> %s" % _last_action)

	lines.append("")
	lines.append("Q/E Waffe  F/G Munition  R Laden  B Modus")
	lines.append("T Nachschub  Z Ballast  0 Reset  Esc Maus")

	_label.text = "\n".join(lines)
