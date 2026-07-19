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
	_test_preview(station, player)
	_test_comparison(station)
	_test_hand_follows(player, stack)
	_test_repair(station, player, stack)
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


## Die Vorschau muss dasselbe Modell zeigen wie die Hand — und zwar für jede
## Waffe und jede Bestückung, ohne dass beim Wechsel etwas stehen bleibt.
func _test_preview(station: WorkbenchStation, player: PlayerController) -> void:
	var ui := station.get_node_or_null("WerkbankUI") as WorkbenchUI
	var preview := _find_preview(ui)
	_check(preview != null, "Vorschau ist Teil der Oberfläche")
	if preview == null:
		return

	for carried in player.inventory.get_carried_weapons():
		ui._on_weapon_chosen(carried)
		var weapon_data := carried.get_data() as WeaponData
		var shown := _preview_model_name(preview)
		_check(shown != "", "Vorschau zeigt ein Modell für %s (%s)"
			% [weapon_data.display_name, shown])

	# Bestückung anbauen und schauen, ob die Vorschau mehr Teile zeigt.
	var rifle := _find_carried(player, &"weapon_rifle_ar15")
	if rifle == null:
		return
	ui._on_weapon_chosen(rifle)
	var bare := _count_meshes(preview)
	station.request_attach(rifle.instance_id, AttachmentData.Slot.SIGHT, &"sight_reddot")
	ui.refresh()
	var kitted := _count_meshes(preview)
	_check(kitted > bare, "Vorschau zeigt das angebaute Teil (%d -> %d Meshes)" % [bare, kitted])

	station.request_detach(rifle.instance_id, AttachmentData.Slot.SIGHT)
	ui.refresh()
	_check(_count_meshes(preview) == bare, "nach dem Abnehmen ist die Vorschau wieder wie vorher")


## Der Vergleich vorher/nachher ist der Grund, warum es die Bank gibt. Zeigt
## er nichts an, kann man nur raten, ob ein Teil hilft.
func _test_comparison(station: WorkbenchStation) -> void:
	var ui := station.get_node_or_null("WerkbankUI") as WorkbenchUI
	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var stack := ItemStack.create(&"weapon_rifle_ar15")

	ui._stack = stack
	ui._slot = int(AttachmentData.Slot.MUZZLE)

	# Ohne Zeigen kein Vergleich.
	ui._on_candidate_cleared()
	_check(ui._candidate_data(ar15) == null, "ohne Zeigen wird nichts verglichen")

	ui._on_candidate(&"muzzle_comp_556")
	var with_comp := ui._candidate_data(ar15)
	_check(with_comp != null and with_comp.recoil_vertical < ar15.recoil_vertical,
		"Zeigen auf den Kompensator zeigt weniger Rückstoss")

	# Zeigen darf nichts anbauen — sonst würde der Vergleich zur Änderung.
	_check(stack.attachments.is_empty(), "Zeigen baut nichts an")

	ui._on_candidate_cleared()


## Instandsetzen muss beim Gegenstand ankommen, nicht nur in der Anzeige.
func _test_repair(station: WorkbenchStation, player: PlayerController, stack: ItemStack) -> void:
	stack.durability = 42.0
	if player.weapon != null:
		player.weapon.condition = 42.0

	_check(station.request_repair(stack.instance_id) == "", "Instandsetzen wird angenommen")
	_check(is_equal_approx(stack.durability, WorkbenchStation.FULL_CONDITION),
		"der Gegenstand ist danach wieder heil (%.0f)" % stack.durability)
	if player.inventory.equipped_weapon == stack and player.weapon != null:
		_check(is_equal_approx(player.weapon.condition, WorkbenchStation.FULL_CONDITION),
			"die Waffe in der Hand ist es auch")

	_check(station.request_repair(stack.instance_id) != "",
		"eine heile Waffe lässt sich nicht nochmal instandsetzen")


func _find_carried(player: PlayerController, item_id: StringName) -> ItemStack:
	for stack in player.inventory.get_carried_weapons():
		if stack.item_id == item_id:
			return stack
	return null


func _find_preview(node: Node) -> WeaponPreview:
	if node is WeaponPreview:
		return node as WeaponPreview
	for child in node.get_children():
		var found := _find_preview(child)
		if found != null:
			return found
	return null


func _preview_model_name(preview: WeaponPreview) -> String:
	var model := _find_viewmodel(preview)
	return model.get_model_name() if model != null else ""


func _find_viewmodel(node: Node) -> WeaponViewmodel:
	if node is WeaponViewmodel:
		return node as WeaponViewmodel
	for child in node.get_children():
		var found := _find_viewmodel(child)
		if found != null:
			return found
	return null


func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _count_buttons(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is Button:
			total += 1
		total += _count_buttons(child)
	return total
