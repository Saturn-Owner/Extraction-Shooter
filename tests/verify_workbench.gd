## Prüft die Werkbank im echten Szenenbaum.
##
##   godot --headless --path . --script res://tests/verify_workbench.gd
##
## WARUM EINE EIGENE SUITE: verify_attachments prüft die Rechenlogik ohne
## Szene — schnell und ohne Kulisse. Genau deshalb sieht sie nicht, ob die
## Oberfläche beim Neuzeichnen über einen leeren Behälter stolpert oder die
## Station beim Öffnen ins Leere greift. Beides ist beim ersten Durchlauf
## passiert, und beides wäre in der Rechenlogik unsichtbar geblieben.
##
## Deshalb lädt diese Suite das Testgelände wirklich und bedient die Bank.
extends SceneTree

var _failed := 0
var _passed := 0
var _level: Node
var _frames := 0


func _initialize() -> void:
	print("=== Werkbank prüfen ===\n")
	var packed: PackedScene = load("res://scenes/levels/testgelaende.tscn")
	if packed == null:
		print("  FEHLER  Testgelände lädt nicht")
		quit(1)
		return
	_level = packed.instantiate()
	root.add_child(_level)


## Erst nach ein paar Frames loslegen: In _initialize() hängen die Knoten
## zwar im Baum, aber _ready() ist noch nicht gelaufen — die Bank hätte dann
## weder Modell noch Reichweite.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	_run()
	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _run() -> void:
	var station := _level.get_node_or_null("Werkbank") as WorkbenchStation
	_check(station != null, "Werkbank steht im Testgelände")
	if station == null:
		return

	var player := _level.get_node_or_null("Player") as PlayerController
	_check(player != null and player.inventory != null, "Spieler mit Inventar gefunden")
	if player == null:
		return

	_check(station.get_child_count() > 0, "Bank hat ihr Modell gebaut (%d Knoten)"
		% station.get_child_count())

	# Reichweite: Ausser Reichweite darf gar nichts gehen — auch nicht mit
	# einer gültigen Anfrage. Sonst könnte man die Bank öffnen, weglaufen und
	# aus der Ferne weiterbauen.
	station.user = player
	var stack := player.inventory.equipped_weapon
	_check(stack != null, "Der Spieler hat eine Waffe in der Hand")
	if stack == null:
		return

	station.global_position = player.global_position + Vector3(0.0, 0.0, 50.0)
	_check(station.request_attach(stack.instance_id, AttachmentData.Slot.SIGHT, &"sight_micro_dot") != "",
		"aus 50 m Entfernung nimmt die Bank nichts an")

	station.global_position = player.global_position
	_check(station.request_attach(stack.instance_id, AttachmentData.Slot.SIGHT, &"sight_micro_dot") == "",
		"an der Bank geht derselbe Anbau durch")

	_test_ui(station, player, stack)
	_test_hand_follows(player, stack)
	_test_detach(station, stack)
	_test_open_and_close(station)


## Die Oberfläche muss sich beliebig oft neu zeichnen lassen, ohne dass etwas
## in ein leeres Feld greift.
func _test_ui(station: WorkbenchStation, player: PlayerController, stack: ItemStack) -> void:
	station.open()
	_check(station.is_open(), "Bank lässt sich öffnen")

	var ui := station.get_node_or_null("WerkbankUI") as WorkbenchUI
	_check(ui != null and ui.visible, "Oberfläche ist sichtbar")
	if ui == null:
		return

	ui.show_for(player)
	ui.refresh()
	ui.refresh()
	_check(_count_buttons(ui) > 0, "Oberfläche zeigt Schaltflächen (%d)" % _count_buttons(ui))

	# Jede Waffe im Inventar muss anwählbar sein, ohne dass es knallt.
	for carried in player.inventory.get_carried_weapons():
		ui._on_weapon_chosen(carried)
		var weapon_data := carried.get_data() as WeaponData
		for slot in weapon_data.get_slots():
			ui._on_slot_chosen(int(slot))
	_check(true, "jede Waffe und jeder Steckplatz lässt sich anwählen")

	# Zurück auf die Waffe in der Hand, damit die folgenden Tests wissen,
	# worauf sie schauen.
	ui._on_weapon_chosen(stack)


## Was an der Bank passiert, muss in der Hand ankommen — sonst baut man um
## und merkt es erst beim nächsten Waffenwechsel.
func _test_hand_follows(player: PlayerController, stack: ItemStack) -> void:
	_check(player.weapon != null and player.weapon.build != null, "Waffe in der Hand hat eine Bestückung")
	if player.weapon == null:
		return
	_check(player.weapon.build.attachments == stack.attachments,
		"Waffe in der Hand kennt die neue Bestückung")

	# Der Umbau darf keine Munition kosten. Genau das würde passieren, wenn
	# die Waffe über equip_from_inventory() neu aufgesetzt würde.
	var before := player.weapon.rounds_in_magazine
	player.weapon.build = WeaponBuild.from_stack(stack)
	player.weapon.rebuild()
	_check(player.weapon.rounds_in_magazine == before,
		"Umbau leert das Magazin nicht (%d Patronen)" % before)


func _test_detach(station: WorkbenchStation, stack: ItemStack) -> void:
	_check(station.request_detach(stack.instance_id, AttachmentData.Slot.SIGHT) == "",
		"Teil lässt sich wieder abnehmen")
	_check(stack.attachments.is_empty(), "Steckplatz ist danach leer")
	_check(station.request_detach(stack.instance_id, AttachmentData.Slot.SIGHT) != "",
		"aus einem leeren Steckplatz lässt sich nichts abnehmen")


## Die Bank hält das Spiel an. Bleibt die Pause hängen, steht das ganze Spiel.
func _test_open_and_close(station: WorkbenchStation) -> void:
	station.open()
	_check(paused, "offene Bank hält das Spiel an")
	station.close()
	_check(not paused, "geschlossene Bank gibt das Spiel wieder frei")
	_check(not station.is_open(), "Bank ist danach zu")

	# Zweimal schliessen darf nichts kaputt machen.
	station.close()
	_check(not paused, "zweimal schliessen bleibt folgenlos")


func _count_buttons(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is Button:
			total += 1
		total += _count_buttons(child)
	return total
