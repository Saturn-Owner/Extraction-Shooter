## Steuert einen Raid im Level: Anzeige, Loot-Bedienung, Ende.
##
## Das ist die erste Szene, die kein Testgelände mehr ist, sondern die
## Kernschleife des Genres zeigt: rein, looten, raus — oder sterben.
##
## HINWEIS ZUR OBERFLÄCHE:
## Die Loot-Anzeige ist bewusst eine schlichte Textliste mit Zifferntasten.
## Ein richtiges Raster mit Ziehen und Ablegen braucht jemanden, der sieht,
## wie es aussieht und sich bedient — das kann Claude nicht beurteilen.
## Die Logik dahinter ist aber vollständig und bleibt unverändert, wenn
## später eine richtige Oberfläche darüberkommt.
##
## Steuerung zusätzlich zu Bewegung und Waffe:
##   F         Kiste durchsuchen / öffnen
##   1-9       Gegenstand aus der offenen Kiste nehmen
##   Tab       alles nehmen, was passt
##   K         Selbsttötung (zum Testen des Verlusts)
##   Enter     neuen Raid starten
extends Node3D

@onready var _player: PlayerController = $Player
@onready var _raid: RaidManager = $RaidManager
@onready var _label: Label = $HUD/InfoPanel/InfoLabel
@onready var _prompt: Label = $HUD/PromptLabel

## Was der Spieler in den ersten Raid mitnimmt.
const STARTING_KIT := [
	{id = &"weapon_pistol_g17", count = 1},
	{id = &"ammo_9x19_fmj", count = 34},
]

var _spawn: Vector3
var _open_container: LootContainer = null
var _message := ""
var _message_timer := 0.0


func _ready() -> void:
	_spawn = _player.global_position
	_raid.setup(_player)
	_raid.raid_ended.connect(_on_raid_ended)

	for container in get_tree().get_nodes_in_group("loot_container"):
		var loot := container as LootContainer
		if loot != null:
			loot.search_finished.connect(_on_search_finished.bind(loot))

	_give_starting_kit()
	_raid.start_raid()


func _give_starting_kit() -> void:
	for entry in STARTING_KIT:
		_player.inventory.add(entry.id, entry.count)
	var weapons := _player.inventory.get_carried_weapons()
	if not weapons.is_empty():
		_player.equip_from_inventory(weapons[0])


func _on_search_finished(container: LootContainer) -> void:
	_open_container = container
	_show_message("%s durchsucht: %d Gegenstaende" % [container.display_name, container.contents.get_item_count()])


func _on_raid_ended(survived: bool, secured: int) -> void:
	if survived:
		_show_message("EXTRAHIERT — %d Gegenstaende ins Lager gebracht. [Enter] fuer neuen Raid" % secured, 30.0)
	else:
		_show_message("GESTORBEN — alles Mitgefuehrte verloren. [Enter] fuer neuen Raid", 30.0)
	_open_container = null


func _show_message(text: String, duration: float = 4.0) -> void:
	_message = text
	_message_timer = duration


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	var key := (event as InputEventKey).physical_keycode

	# Gegenstand aus der offenen Kiste nehmen.
	if key >= KEY_1 and key <= KEY_9 and _open_container != null:
		_take_from_container(key - KEY_1)
		return

	match key:
		KEY_TAB:
			if _open_container != null:
				var left := _open_container.take_all(_player.inventory.grid)
				if left > 0:
					_show_message("Inventar voll — %d Gegenstaende bleiben liegen" % left)
				else:
					_show_message("alles eingesammelt")
		KEY_K:
			if _raid.state == RaidManager.State.LAEUFT:
				_raid.die()
		KEY_ENTER, KEY_KP_ENTER:
			if _raid.state == RaidManager.State.BEENDET:
				_restart_raid()
		KEY_ESCAPE:
			_open_container = null


func _take_from_container(index: int) -> void:
	if _open_container == null:
		return
	var stacks := _open_container.contents.get_all_stacks()
	if index < 0 or index >= stacks.size():
		return

	var stack := stacks[index]
	var item_name := stack.get_data().display_name if stack.get_data() != null else "?"
	if _open_container.take_item(stack.instance_id, _player.inventory.grid):
		_show_message("%s genommen" % item_name)
	else:
		_show_message("kein Platz fuer %s" % item_name)


func _restart_raid() -> void:
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO

	# Ohne Ausruestung startet man mit dem Grundset — sonst ist man nach
	# einem Tod handlungsunfaehig. Spaeter kommt hier die Ausruestung aus
	# dem Lager ueber das Terminal.
	if _player.inventory.grid.get_item_count() == 0 and _player.inventory.equipped_weapon == null:
		_give_starting_kit()

	for container in get_tree().get_nodes_in_group("loot_container"):
		var loot := container as LootContainer
		if loot != null:
			loot.is_searched = false
			loot.contents.resize(loot.grid_width, loot.grid_height)

	_open_container = null
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

	if _player.interaction != null:
		var searching := _player.interaction.searching_container
		if searching != null:
			lines.append("Durchsuche... %d%%" % int(searching.get_search_progress() * 100.0))
		else:
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

	if _open_container != null:
		lines.append("")
		lines.append("--- %s ---" % _open_container.display_name)
		var stacks := _open_container.contents.get_all_stacks()
		if stacks.is_empty():
			lines.append("  leer")
		else:
			for i in range(mini(stacks.size(), 9)):
				var stack := stacks[i]
				var data := stack.get_data()
				var name := data.display_name if data != null else "?"
				var amount := " x%d" % stack.quantity if stack.quantity > 1 else ""
				lines.append("  [%d] %s%s" % [i + 1, name, amount])
			lines.append("  [Tab] alles nehmen")

	lines.append("")
	lines.append("F durchsuchen  Tab alles  K sterben  Enter neu")

	_label.text = "\n".join(lines)
