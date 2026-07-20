## Waffenwerkbank: Hier wird eine Waffe aus dem Inventar umgebaut.
##
## SERVER-AUTORITATIV (Grundsatz 2). Die Oberfläche schreibt nie selbst in
## einen ItemStack. Sie fragt an, die Station prüft, die Station ändert:
##
##     UI klickt  →  request_attach(...)
##                →  Station prüft (Waffe da? Steckplatz da? Teil passt?)
##                →  Station ändert den Stack
##                →  Signal  →  UI und Waffe in der Hand zeichnen neu
##
## Genau dieselbe Reihenfolge wird später über das Netzwerk laufen, nur mit
## einem RPC zwischen Klick und Prüfung. Deshalb steht die Prüfung schon
## heute in eigenen, statischen Funktionen: Sie kennt keinen Szenenbaum und
## ist damit sowohl headless testbar als auch später serverseitig nutzbar.
##
## Die Bank baut ihr Modell im Code, wie die Waffen auch — eine eigene .tscn
## dafür wäre nur eine weitere Datei, die sich bei Konflikten nicht mergen
## lässt.
class_name WorkbenchStation
extends Area3D

## Der Spieler hat die Bank geöffnet bzw. verlassen.
signal opened()
signal closed()

## Die Bestückung einer Waffe hat sich geändert.
signal build_changed(stack: ItemStack)

## Ebene, auf der der Spieler liegt (siehe scenes/player/player.tscn).
##
## Ebenenbelegung im Projekt: 1 = Welt, 2 = Spieler, 4 = Ziele.
##
## Ohne diese Maske sieht die Bank den Spieler NICHT. Genau das ist beim
## ersten Spieltest passiert: Area3D horcht ab Werk nur auf Ebene 1, der
## Spieler liegt aber auf 2 — Tab tat schlicht nichts.
const PLAYER_LAYER := 2

## Zustand einer unbeschädigten Waffe. Steht hier und nicht als lose 100.0
## im Code, damit Reparatur und Prüfung nie auseinanderlaufen können.
const FULL_CONDITION := 100.0

## Der Waffenschrank der Bank: was man sich hier nehmen kann.
## Bewusst nur die drei Beta-Waffen — nicht das ganze Sortiment der Registry.
const ARSENAL: Array[StringName] = [
	&"weapon_rifle_ar15",
	&"weapon_shotgun_m870",
	&"weapon_pistol_g17",
]

## Was "Munition auffüllen" in die Taschen legt — genug für einen Anlauf,
## nicht genug, um nie wieder herzukommen.
const AMMO_PACKS := [
	{id = &"ammo_556x45_m855a1", count = 90},
	{id = &"ammo_9x19_fmj", count = 51},
	{id = &"ammo_12x70_buckshot", count = 25},
]

## Wie weit man von der Bank weg sein darf. Wird bei JEDER Anfrage geprüft,
## nicht nur beim Öffnen — sonst könnte man die Bank öffnen, weglaufen und
## aus der Ferne weiterbauen.
@export var use_range: float = 2.6

## Der Spieler in Reichweite, oder null.
var user: PlayerController = null

var _open: bool = false
var _ui: WorkbenchUI = null
var _hint: Label = null


func _ready() -> void:
	# Muss auch bei angehaltenem Spiel auf Tab reagieren — sonst käme man
	# nicht wieder heraus.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_bench()
	_build_trigger()
	_build_hint()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


# ---------------------------------------------------------------- Geometrie

func _build_bench() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.34, 0.26, 0.19)
	wood.roughness = 0.9

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.30, 0.31, 0.33)
	steel.roughness = 0.55
	steel.metallic = 0.6

	_add_box("Platte", Vector3(1.8, 0.08, 0.8), Vector3(0.0, 0.90, 0.0), wood)
	for i in range(4):
		var x := -0.78 if i % 2 == 0 else 0.78
		var z := -0.32 if i < 2 else 0.32
		_add_box("Bein%d" % i, Vector3(0.08, 0.86, 0.08), Vector3(x, 0.43, z), steel)
	_add_box("Ablage", Vector3(1.6, 0.05, 0.6), Vector3(0.0, 0.30, 0.0), wood)
	# Schraubstock — damit man von weitem sieht, wofür der Tisch da ist.
	_add_box("Schraubstock", Vector3(0.22, 0.18, 0.16), Vector3(0.62, 1.03, 0.0), steel)


func _add_box(node_name: String, size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)


## Der Bereich, in dem Tab greift. Bewusst grosszügiger als die Tischplatte,
## damit man nicht nach der richtigen Stelle suchen muss.
func _build_trigger() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 2.2, 2.0)
	var collision := CollisionShape3D.new()
	collision.name = "Reichweite"
	collision.shape = shape
	collision.position = Vector3(0.0, 1.1, 0.0)
	add_child(collision)

	# Nur Körper melden, keine anderen Bereiche — der Spieler ist einer.
	monitoring = true
	monitorable = false
	collision_mask = PLAYER_LAYER


## Hinweis am unteren Bildrand, sobald man nah genug steht.
##
## Ohne ihn ist die Bank unbedienbar für jeden, der nicht weiß, dass es sie
## gibt — und selbst wer es weiß, muss raten, ob er in Reichweite steht.
func _build_hint() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hinweis"
	layer.layer = 5
	add_child(layer)

	_hint = Label.new()
	_hint.text = "[Tab]  Werkbank"
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-60.0, -90.0)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.visible = false
	layer.add_child(_hint)


func _update_hint() -> void:
	if _hint != null:
		_hint.visible = user != null and not _open


# ------------------------------------------------------------------ Zugang

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		user = body as PlayerController
		_update_hint()


func _on_body_exited(body: Node3D) -> void:
	if body == user:
		# Wer weggeht, schliesst die Bank. Sonst bliebe die Oberfläche offen
		# und das Spiel angehalten, während die Bank ausser Reichweite ist.
		close()
		user = null
		_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	# Roher Tastencode statt neuer Eingabe-Aktion: project.godot ist zwischen
	# den Branches ohnehin schon auseinandergelaufen, und das Testgelände
	# behandelt seine Tasten genauso. Sobald der Bunker steht, zieht die
	# Werkbank auf die gemeinsame Benutzen-Taste um.
	if (event as InputEventKey).physical_keycode != KEY_TAB:
		return

	if _open:
		close()
		get_viewport().set_input_as_handled()
	elif user != null:
		open()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open or user == null:
		return
	_open = true

	if _ui == null:
		_ui = WorkbenchUI.new()
		_ui.name = "WerkbankUI"
		_ui.station = self
		add_child(_ui)
	_ui.show_for(user)

	# Der Spieler wird über die Pause angehalten, nicht über eine Sperre im
	# Controller. Damit muss weder player_controller.gd noch test_ground.gd
	# angefasst werden — beides liegt im Arbeitsbereich des Kollegen.
	#
	# IM MULTIPLAYER GEHT DAS NICHT: Die Welt läuft auf dem Server weiter,
	# und eine örtliche Pause friert nur die eigene Sicht ein — die Pakete
	# stauen sich, und beim Schließen springt alles. Deshalb dort die
	# UI-Sperre des Controllers, wie bei den Beute-Fenstern.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _is_multiplayer():
		user.set_ui_open(true)
	else:
		get_tree().paused = true
	_update_hint()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false

	if _ui != null:
		_ui.visible = false

	if _is_multiplayer():
		if user != null:
			user.set_ui_open(false)
	else:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hint()
	closed.emit()


## Läuft gerade ein Multiplayer-Spiel?
##
## BEWUSST ÜBER DEN KNOTENPFAD statt über den globalen Namen `Net`: Der
## globale Name steht erst fest, wenn die Autoloads registriert sind — und
## Testsuiten laden diese Datei teils davor. Ein Compile-Fehler hier risse
## das ganze Testgelände mit.
func _is_multiplayer() -> bool:
	var net := get_node_or_null("/root/Net")
	return net != null and bool(net.call("is_multiplayer"))


# ------------------------------------------------------- Anfragen der UI

## Gibt eine Waffe aus dem Schrank aus. Sind beide Plätze belegt, ersetzt
## assign_weapon() die aktive Waffe — die alte wandert ins Raster.
func request_take_weapon(weapon_id: StringName) -> String:
	if user == null:
		return "niemand an der Bank"
	if not _in_range():
		return "zu weit von der Werkbank entfernt"
	if not weapon_id in ARSENAL:
		return "diese Waffe gibt die Bank nicht aus"
	var data := ItemRegistry.get_item(weapon_id) as WeaponData
	if data == null:
		return "unbekannte Waffe"

	for stack in user.inventory.get_carried_weapons():
		var carried := stack.get_data()
		if carried != null and carried.id == weapon_id:
			return "%s trägst du schon" % data.display_name

	if not user.assign_weapon(ItemStack.create(weapon_id, 1)):
		return "kein Platz — Raster voll"
	build_changed.emit(user.inventory.equipped_weapon)
	return ""


## Füllt die Munitionsvorräte auf — kostenlos, das ist eine Arena, kein Raid.
func request_ammo() -> String:
	if user == null:
		return "niemand an der Bank"
	if not _in_range():
		return "zu weit von der Werkbank entfernt"
	var added := 0
	for pack in AMMO_PACKS:
		if user.inventory.add(pack.id, pack.count):
			added += pack.count
	if added == 0:
		return "kein Platz im Raster für Munition"
	user.inventory.notify_changed()
	return ""


## Baut ein Teil an. Gibt "" zurück, wenn es geklappt hat, sonst den Grund —
## der Grund ist für den Spieler bestimmt und steht deshalb auf Deutsch.
func request_attach(instance_id: int, slot: AttachmentData.Slot, attachment_id: StringName) -> String:
	var stack := _find_weapon(instance_id)
	if not _in_range():
		return "zu weit von der Werkbank entfernt"
	var problem := check_attach(stack, slot, attachment_id)
	if problem != "":
		return problem

	stack.attachments[int(slot)] = attachment_id
	_after_change(stack)
	return ""


## Nimmt das Teil aus einem Steckplatz.
func request_detach(instance_id: int, slot: AttachmentData.Slot) -> String:
	var stack := _find_weapon(instance_id)
	if stack == null:
		return "Waffe nicht gefunden"
	if not _in_range():
		return "zu weit von der Werkbank entfernt"
	if not stack.attachments.has(int(slot)):
		return "in diesem Steckplatz sitzt nichts"

	stack.attachments.erase(int(slot))
	_after_change(stack)
	return ""


## Setzt die Waffe wieder instand.
##
## VORERST KOSTENLOS. Sobald es Geld und Ersatzteile gibt, gehört genau
## hierher der Preis — die Stelle, an der geprüft und geändert wird, bleibt
## dieselbe. Ohne Kosten ist eine abgenutzte Waffe allerdings folgenlos, und
## damit auch die Ladehemmung: Das ist eine bewusste Zwischenstufe, kein
## fertiger Zustand.
func request_repair(instance_id: int) -> String:
	var stack := _find_weapon(instance_id)
	if stack == null:
		return "Waffe nicht gefunden"
	if not _in_range():
		return "zu weit von der Werkbank entfernt"
	if stack.durability >= FULL_CONDITION:
		return "die Waffe ist in Ordnung"

	stack.durability = FULL_CONDITION
	if user != null and user.inventory != null and user.inventory.equipped_weapon == stack:
		if user.weapon != null:
			user.weapon.condition = FULL_CONDITION
	build_changed.emit(stack)
	return ""


## Alles ausser der Reichweite — reine Prüfung ohne Szenenbaum, damit sie
## headless testbar ist und später unverändert auf dem Server laufen kann.
static func check_attach(stack: ItemStack, slot: AttachmentData.Slot, attachment_id: StringName) -> String:
	if stack == null:
		return "Waffe nicht gefunden"

	var weapon_data := stack.get_data() as WeaponData
	if weapon_data == null:
		return "das ist keine Waffe"

	var attachment := ItemRegistry.get_item(attachment_id) as AttachmentData
	if attachment == null:
		return "unbekanntes Anbauteil"

	if attachment.slot != slot:
		return "%s gehört nicht in diesen Steckplatz" % attachment.display_name

	var mount := weapon_data.find_mount(slot)
	if mount == null:
		return "%s hat keinen Platz für %s" % [
			weapon_data.display_name, AttachmentData.slot_name(slot)]

	if mount.interface_tag != attachment.interface_tag:
		return "%s passt nicht auf diese Aufnahme" % attachment.display_name

	return ""


## Welche Teile aus der Registry an diesen Steckplatz dieser Waffe passen.
##
## Vorerst sind alle Teile frei verfügbar — die Bank listet das ganze
## Sortiment, nicht nur was im Rucksack liegt. Sobald Teile gefunden oder
## gekauft werden müssen, wird hier gegen das Inventar gefiltert.
static func get_options(weapon_data: WeaponData, slot: AttachmentData.Slot) -> Array[AttachmentData]:
	var result: Array[AttachmentData] = []
	if weapon_data == null:
		return result

	for item in ItemRegistry.get_by_category(ItemData.Category.ATTACHMENT):
		var attachment := item as AttachmentData
		if attachment == null or attachment.slot != slot:
			continue
		if check_attach_data(weapon_data, attachment) == "":
			result.append(attachment)

	result.sort_custom(func(a: AttachmentData, b: AttachmentData) -> bool:
		return a.display_name < b.display_name)
	return result


## Passt dieses Teil grundsätzlich an diese Waffe?
static func check_attach_data(weapon_data: WeaponData, attachment: AttachmentData) -> String:
	if weapon_data == null or attachment == null:
		return "unvollständige Angaben"
	var mount := weapon_data.find_mount(attachment.slot)
	if mount == null:
		return "%s hat keinen Platz für %s" % [
			weapon_data.display_name, AttachmentData.slot_name(attachment.slot)]
	if mount.interface_tag != attachment.interface_tag:
		return "%s passt nicht auf diese Aufnahme" % attachment.display_name
	return ""


func _find_weapon(instance_id: int) -> ItemStack:
	if user == null or user.inventory == null:
		return null
	for stack in user.inventory.get_carried_weapons():
		if stack.instance_id == instance_id:
			return stack
	return null


func _in_range() -> bool:
	if user == null:
		return false
	return global_position.distance_to(user.global_position) <= use_range


## Nach jeder Änderung: Liegt die Waffe in der Hand, muss sie ihre Werte neu
## ausrechnen und ihr Modell neu bauen.
##
## Bewusst über rebuild() und NICHT über equip_from_inventory(): Letzteres
## würde die Waffe neu aufsetzen und dabei das Magazin leeren und aus dem
## Inventar nachfüllen. Ein Rotpunkt anschrauben darf keine Munition kosten.
func _after_change(stack: ItemStack) -> void:
	if user != null and user.inventory != null:
		if user.inventory.equipped_weapon == stack and user.weapon != null:
			user.weapon.build = WeaponBuild.from_stack(stack)
			user.weapon.rebuild()
		# Anbauteile wiegen mit — die Traglast muss neu gerechnet werden.
		user.inventory.notify_changed()
	build_changed.emit(stack)
