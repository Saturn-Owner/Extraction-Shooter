## Steuert einen Raid im Level: Anzeige, Loot-Bedienung, Ende.
##
## Das ist die erste Szene, die kein Testgelände mehr ist, sondern die
## Kernschleife des Genres zeigt: rein, looten, raus — oder sterben.
##
## Steuerung zusätzlich zu Bewegung und Waffe:
##   F         Kiste öffnen / Fenster schliessen
##   Tab       Inventar öffnen — oder, vor einer offenen Kiste, alles nehmen
##   Esc       Fenster schliessen
##   K         Selbsttötung (zum Testen des Verlusts)
##   Enter     neuen Raid starten
##
## Im Loot-Fenster: Ziehen verschiebt, Doppelklick schickt hinüber.
extends Node3D

@onready var _player: PlayerController = $Player
@onready var _raid: RaidManager = $RaidManager
@onready var _label: Label = $HUD/InfoPanel/InfoLabel
@onready var _prompt: Label = $HUD/PromptLabel
@onready var _loot_window: LootWindow = $HUD/LootWindow
@onready var _inventory_window: InventoryWindow = $HUD/InventoryWindow
@onready var _character_window: CharacterWindow = $HUD/CharacterWindow

## Was der Spieler in den ersten Raid mitnimmt.
##
## Grosse Gegenstaende zuerst: Das Inventar sucht den ersten freien Platz,
## und ein 5x2-Gewehr passt nicht mehr, wenn kleine Dinge die Reihen
## zerstueckelt haben.
##
## HINWEIS: Das ist eine Testausruestung, kein Balancing. Sobald es das
## Lager und das Terminal gibt, waehlt der Spieler selbst aus, was er
## mitnimmt — und ein Gewehr gratis zu bekommen widerspricht dem Genre.
const STARTING_KIT := [
	{id = &"weapon_rifle_ar15", count = 1},
	{id = &"weapon_pistol_g17", count = 1},
	{id = &"ammo_556x45_m855a1", count = 60},
	{id = &"ammo_9x19_fmj", count = 34},
]

var _spawn: Vector3
var _message := ""
var _message_timer := 0.0


func _ready() -> void:
	_spawn = _player.global_position
	_raid.setup(_player)
	_raid.raid_ended.connect(_on_raid_ended)
	# Jedes Fenster legt beim Öffnen die Steuerung still und gibt sie beim
	# Schliessen wieder frei. Ein Ort dafür, damit kein Fenster den Spieler
	# gelähmt zurücklassen kann.
	for window in [_loot_window, _inventory_window, _character_window]:
		window.opened.connect(_on_window_opened)
		window.closed.connect(_on_window_closed)

	# Wer im Raid stirbt, verliert alles — auch durch Hunger oder Kaelte.
	_player.health.died.connect(_on_player_died)

	_give_starting_kit()
	_raid.start_raid()


func _give_starting_kit() -> void:
	for entry in STARTING_KIT:
		if not _player.inventory.add(entry.id, entry.count):
			# Nicht stillschweigend schlucken: Ein fehlendes Gewehr faellt
			# sonst erst auf, wenn jemand im Raid danach sucht.
			push_error("[Raid] Startausruestung passt nicht ins Inventar: %s" % entry.id)

	# Gezielt das Gewehr in die Hand nehmen, nicht "irgendeine" Waffe.
	# get_carried_weapons() garantiert keine Reihenfolge — sobald sich die
	# Ausruestung aendert, haette man sonst zufaellig die Pistole.
	var weapons := _player.inventory.get_carried_weapons()
	var chosen: ItemStack = null
	for stack in weapons:
		if stack.item_id == &"weapon_rifle_ar15":
			chosen = stack
			break
	if chosen == null and not weapons.is_empty():
		chosen = weapons[0]

	if chosen != null:
		_player.equip_from_inventory(chosen)


func _on_window_opened() -> void:
	_player.set_ui_open(true)


func _on_window_closed() -> void:
	# Erst freigeben, wenn wirklich kein Fenster mehr offen ist.
	if not _any_window_open():
		_player.set_ui_open(false)
	_show_message("")


func _any_window_open() -> bool:
	return _loot_window.is_open() or _inventory_window.is_open() \
		or _character_window.is_open()


## Tod durch Verletzung, Hunger, Durst oder Kaelte — das Ergebnis ist gleich.
func _on_player_died(part: HealthSystem.Part) -> void:
	if _raid.state != RaidManager.State.LAEUFT:
		return
	_show_message("Toedlich getroffen: %s" % HealthSystem.get_part_name(part), 30.0)
	_raid.die()


func _on_raid_ended(survived: bool, secured: int) -> void:
	if _loot_window.is_open():
		_loot_window.close()
	if _inventory_window.is_open():
		_inventory_window.close()
	if _character_window.is_open():
		_character_window.close()
	if survived:
		_show_message("EXTRAHIERT — %d Gegenstaende ins Lager gebracht. [Enter] fuer neuen Raid" % secured, 30.0)
	else:
		_show_message("GESTORBEN — alles Mitgefuehrte verloren. [Enter] fuer neuen Raid", 30.0)


func _show_message(text: String, duration: float = 4.0) -> void:
	_message = text
	_message_timer = duration


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	match (event as InputEventKey).physical_keycode:
		KEY_F:
			_toggle_loot_window()
		KEY_TAB:
			# Vor einer offenen Kiste ist "alles nehmen" der haeufigere Wunsch
			# als das Inventar — sonst muesste man dafuer erst schliessen.
			if _loot_window.is_open():
				var left := _loot_window.take_all()
				_show_message("alles eingesammelt" if left == 0
					else "Inventar voll — %d Gegenstaende bleiben liegen" % left)
			else:
				_toggle_inventory_window()
		KEY_C:
			_toggle_character_window()
		KEY_K:
			if _raid.state == RaidManager.State.LAEUFT:
				_raid.die()
		KEY_ENTER, KEY_KP_ENTER:
			if _raid.state == RaidManager.State.BEENDET:
				_restart_raid()
		KEY_ESCAPE:
			if _loot_window.is_open():
				_loot_window.close()
			elif _inventory_window.is_open():
				_inventory_window.close()
			elif _character_window.is_open():
				_character_window.close()


func _toggle_inventory_window() -> void:
	if _inventory_window.is_open():
		_inventory_window.close()
		return
	if _character_window.is_open():
		_character_window.close()
	_inventory_window.open_for(_player)


func _toggle_character_window() -> void:
	if _character_window.is_open():
		_character_window.close()
		return
	# Nicht zwei Fenster uebereinander.
	if _inventory_window.is_open():
		_inventory_window.close()
	if _loot_window.is_open():
		_loot_window.close()
	_character_window.open_for(_player)


## F öffnet die Kiste, vor der man steht — oder schliesst das Fenster.
func _toggle_loot_window() -> void:
	if _loot_window.is_open():
		_loot_window.close()
		return

	# Nicht beide Fenster gleichzeitig.
	if _inventory_window.is_open():
		_inventory_window.close()

	var target := _player.interaction.current_target if _player.interaction != null else null
	if target is LootContainer:
		_loot_window.open_for(target as LootContainer, _player.inventory)


func _restart_raid() -> void:
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO

	# Ohne das startet man mit dem Zustand, in dem man gestorben ist —
	# also tot, verhungert oder erfroren.
	_player.health.reset()
	_player.survival.reset()

	# Ohne Ausruestung startet man mit dem Grundset — sonst ist man nach
	# einem Tod handlungsunfaehig. Spaeter kommt hier die Ausruestung aus
	# dem Lager ueber das Terminal.
	if _player.inventory.grid.get_item_count() == 0 and _player.inventory.equipped_weapon == null:
		_give_starting_kit()

	for container in get_tree().get_nodes_in_group("loot_container"):
		var loot := container as LootContainer
		if loot != null:
			loot.reset()

	_raid.start_raid()
	_show_message("Neuer Raid gestartet")


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message = ""

	_update_prompt()
	_update_info()


func _update_prompt() -> void:
	var lines: Array[String] = []

	if _player.interaction != null and not _loot_window.is_open():
		var text := _player.interaction.get_prompt()
		if text != "":
			lines.append(text)

	# Fortschritt am Ausgang.
	for zone in get_tree().get_nodes_in_group("extraction_zone"):
		var extraction := zone as ExtractionZone
		if extraction == null or extraction.get_ratio() <= 0.0:
			continue
		var reason := extraction.get_block_reason(_player)
		if reason != "":
			lines.append("%s: %s" % [extraction.display_name, reason])
		else:
			lines.append("%s: %d%%" % [extraction.display_name, int(extraction.get_ratio() * 100.0)])

	if _message != "":
		lines.append(_message)

	_prompt.text = "\n".join(lines)


func _update_info() -> void:
	var lines := [
		"Traglast:  %.1f kg  (Faktor %.2f)" % [_player.carried_weight_kg, _player.get_weight_factor()],
		"Ausdauer:  %.0f" % _player.stamina,
	]

	if _player.weapon != null and _player.weapon.data != null:
		lines.append("Waffe:     %s" % _player.weapon.get_status_text())

	lines.append("Dabei:     %d Gegenstaende" % _player.inventory.grid.get_item_count())
	lines.append("Lager:     %d Gegenstaende" % _raid.stash.get_item_count())
	lines.append("")
	lines.append("F Kiste  Tab Inventar  C Koerper  K sterben  Enter neu")

	_label.text = "\n".join(lines)
