## First-Person-Steuerung der Spielerfigur.
##
## Bewegungsgefühl bewusst "schwer und bedacht" (Tarkov/Arma), nicht flott:
## Die Figur beschleunigt und bremst spürbar, statt sofort auf Tempo zu sein.
## Jede Bewegung soll sich nach einer Entscheidung anfühlen, nicht nach einem
## Reflex — das trägt später das Survival-Gefühl.
##
## Drei Dinge bremsen den Spieler, und alle sollen sich unterscheidbar anfühlen:
##   1. Getragenes Gewicht (Inventar)
##   2. Erschöpfung (Ausdauer leer)
##   3. Haltung (geduckt)
##
## HINWEIS ZUM NETZWERK: Diese Klasse bewegt den lokalen Spieler und ist damit
## bewusst client-seitig. Sobald Multiplayer dazukommt, muss der Server jede
## Position gegenprüfen (Plausibilitätscheck gegen die hier definierten
## Höchstgeschwindigkeiten), sonst kann ein Client beliebig schnell laufen.
class_name PlayerController
extends CharacterBody3D

signal stamina_changed(current: float, maximum: float)
signal exhausted()

@export_group("Tempo (Meter pro Sekunde)")

## Normales Gehen. Bewusst langsam — das ist die Standardgeschwindigkeit,
## in der der Spieler die meiste Zeit unterwegs ist.
@export var walk_speed: float = 2.4

## Sprint. Kostet Ausdauer und macht laut.
@export var sprint_speed: float = 5.2

## Geduckt. Langsam, aber leise und schwerer zu treffen.
@export var crouch_speed: float = 1.2

@export_group("Trägheit")

## Wie schnell die Figur auf Tempo kommt. Niedrig = schwerfällig.
@export var acceleration: float = 8.0

## Wie schnell sie zum Stehen kommt.
@export var deceleration: float = 10.0

## Bewegungskontrolle in der Luft (0 = gar keine).
@export_range(0.0, 1.0) var air_control: float = 0.15

@export var jump_velocity: float = 4.0

@export_group("Kamera")

@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.15

## Wie weit hoch und runter geschaut werden darf (Grad).
@export var pitch_limit_degrees: float = 89.0

## Augenhöhe im Stehen und im Ducken.
@export var stand_eye_height: float = 1.65
@export var crouch_eye_height: float = 0.95

@export_group("Ausdauer")

@export var max_stamina: float = 100.0

## Verbrauch pro Sekunde beim Sprinten.
@export var stamina_drain_per_second: float = 14.0

## Erholung pro Sekunde, wenn nicht gesprintet wird.
@export var stamina_regen_per_second: float = 9.0

## Pause vor Beginn der Erholung. Verhindert Dauersprint mit Mikropausen.
@export var stamina_regen_delay: float = 1.4

@export_group("Traglast")

## Gewicht, ab dem der Spieler langsamer wird.
## Bewusst niedrig: Man soll schon eine halbe Ausrüstung spüren, nicht erst
## einen vollen Rucksack. Ein Gewehr allein wiegt bereits 3.1 kg.
@export var comfortable_weight_kg: float = 6.0

## Gewicht, ab dem kaum noch Bewegung möglich ist.
@export var max_weight_kg: float = 40.0

## Wie stark Überladung bremst (1.0 = bis zum Stillstand bei max_weight_kg).
@export_range(0.0, 1.0) var weight_slowdown: float = 0.55

## Tempo-Bonus mit komplett leerem Inventar.
## Ohne diesen Bonus gäbe es nur Strafe und nie Belohnung — leicht zu reisen
## soll sich aktiv gut anfühlen, nicht bloss "nicht schlecht".
@export_range(0.0, 0.5) var unencumbered_bonus: float = 0.18

## Wie früh die Bremse zubeisst. Kleiner als 1.0 = die ersten Kilos über der
## Komfortgrenze wirken schon deutlich, statt dass erst die letzten wehtun.
@export_range(0.3, 2.0) var weight_curve: float = 0.7

## Aktuell getragenes Gewicht. Wird später vom Inventar gesetzt:
##   player.carried_weight_kg = inventory.get_total_weight()
var carried_weight_kg: float = 0.0

var stamina: float = 100.0
var is_crouching: bool = false
var is_sprinting: bool = false

## Ob gerade ein Fenster offen ist (Loot, Inventar).
## Solange das gilt, nimmt die Figur KEINE Eingaben entgegen: nicht schiessen,
## nicht laufen, nicht umschauen. Sonst wuerde ein Klick auf einen Gegenstand
## gleichzeitig einen Schuss ausloesen — und im Loot-Fenster steht man
## bewegungsunfaehig vor der Kiste, was genau das Risiko sein soll.
var ui_open: bool = false

var _pitch: float = 0.0
var _time_since_sprint: float = 0.0
var _was_exhausted: bool = false

## Rückstoß, der noch auf die Kamera wirkt, und was davon zurückfedert.
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0

## Wie schnell die Waffe nach dem Rückstoß wieder ins Ziel kommt.
@export_group("Rückstoß")
@export var recoil_recovery_speed: float = 6.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var weapon: Weapon = $CameraPivot/Weapon
@onready var inventory: PlayerInventory = $Inventory
@onready var interaction: PlayerInteraction = $CameraPivot/Interaction
@onready var health: HealthSystem = $Health
@onready var survival: SurvivalStats = $Survival
@onready var equipment: Equipment = $Equipment
@onready var injuries: InjurySystem = $Injuries

## Sammelt Sekundenbruchteile, damit Hunger- und Kaelteschaden einmal pro
## Sekunde wirkt statt in jedem Frame ein Krümelchen.
var _survival_damage_timer: float = 0.0

## Welcher Waffenplatz gerade in der Hand liegt.
var active_weapon_slot: ItemData.EquipSlot = ItemData.EquipSlot.PRIMARY

## Was in den Magazinen der NICHT getragenen Waffen steckt,
## nach `instance_id` der Waffe.
##
## Ohne das waere jeder Waffenwechsel ein Munitionsverlust: Die Patronen im
## Lauf gehoeren zu DIESER Waffe, nicht zur Hand. Genau dieser Fehler hat
## uns schon einmal bei der Extraction Munition gekostet.
##
## Der Schluessel ist bewusst die Waffe und nicht der Platz. Sonst waere das
## Magazin weg, sobald die Waffe einmal in den Rucksack wandert — und genau
## das kann man jetzt mit der Maus tun.
var _magazines: Dictionary = {}


func _ready() -> void:
	stamina = max_stamina
	_capture_mouse(true)
	if weapon != null:
		weapon.recoil_kick.connect(_on_recoil_kick)
	if inventory != null:
		inventory.changed.connect(_on_inventory_changed)
		_on_inventory_changed()
	if equipment != null:
		equipment.changed.connect(_on_equipment_changed)
		_on_equipment_changed()


## Das Gewicht kommt jetzt aus dem Inventar statt von Hand gesetzt zu werden.
## Ein voller Rucksack bremst dadurch wirklich.
func _on_inventory_changed() -> void:
	_update_carried_weight()


## Getragene Kleidung waermt und wiegt — beides muss sofort greifen.
func _on_equipment_changed() -> void:
	if survival != null and equipment != null:
		survival.insulation = equipment.get_total_insulation()
	_update_carried_weight()


## Angelegte Ausruestung zaehlt zum Gewicht: Man traegt sie ja. Sie belegt
## nur keine Rasterfelder — genau das ist der Anreiz, etwas anzuziehen.
## Das Raster plus alles am Koerper.
##
## Die Waffe in der Hand steckt immer in einem Waffenplatz und ist damit
## Teil der Ausruestung — sie darf hier nicht ein zweites Mal dazukommen.
## Deshalb `grid` statt `inventory.get_total_weight()`.
func _update_carried_weight() -> void:
	var total := 0.0
	if inventory != null and inventory.grid != null:
		total += inventory.grid.get_total_weight()
	if equipment != null:
		total += equipment.get_total_weight()
	carried_weight_kg = total


## Legt eine Waffe aus dem Inventar auf einen Waffenplatz.
##
## Ohne `slot` wird der erste freie genommen; sind beide belegt, ersetzt sie
## die Waffe im gerade aktiven Platz — was dort lag, wandert ins Raster.
func assign_weapon(stack: ItemStack, slot: ItemData.EquipSlot = ItemData.EquipSlot.NONE) -> bool:
	if equipment == null or inventory == null or stack == null:
		return false
	if not equipment.can_equip(stack, ItemData.EquipSlot.PRIMARY):
		return false

	var target := slot
	if target == ItemData.EquipSlot.NONE:
		target = equipment.get_free_weapon_slot()
		if target == ItemData.EquipSlot.NONE:
			target = active_weapon_slot

	# Erst pruefen, ob die verdraengte Waffe ins Raster passt. Sonst
	# verschwindet sie beim Tauschen stillschweigend.
	var displaced := equipment.get_item(target)
	if displaced != null and displaced != stack:
		if not inventory.grid.can_place_or_merge(displaced, 0, 0) \
				and inventory.grid.find_free_position(displaced).x < 0:
			return false

	if inventory.grid.get_stack(stack.instance_id) != null:
		inventory.grid.remove_item(stack.instance_id)

	equipment.equip(stack, target)
	if displaced != null and displaced != stack:
		inventory.grid.add_item(displaced)

	# Der Platz, auf den gerade gelegt wurde, kommt auch in die Hand.
	select_weapon_slot(target)
	return true


## Wechselt zwischen Primaer- und Sekundaerwaffe (Tasten 1 und 2).
##
## Die Munition im Magazin der bisherigen Waffe bleibt dort — sie steckt ja
## in DIESER Waffe. Beim Wechsel zurueck ist sie wieder da.
func select_weapon_slot(slot: ItemData.EquipSlot) -> bool:
	if equipment == null or weapon == null:
		return false
	if not Equipment.is_weapon_slot(slot):
		return false

	var stack := equipment.get_item(slot)
	if stack == null:
		return false

	# Was noch im Lauf steckt, gehoert zur alten Waffe. Merken, damit es
	# beim Zurueckwechseln nicht verschwunden ist.
	if active_weapon_slot != slot:
		_remember_magazine()

	active_weapon_slot = slot
	inventory.equipped_weapon = stack
	_put_in_hand(stack)
	return true


## Merkt sich, was im Magazin der Waffe steckt, die gerade in der Hand liegt.
func _remember_magazine() -> void:
	if weapon == null or equipment == null:
		return
	var held := equipment.get_item(active_weapon_slot)
	if held == null:
		return
	_magazines[held.instance_id] = {
		"rounds": weapon.rounds_in_magazine,
		"ammo": weapon.ammo_id,
	}


## Baut die Waffe in der Hand auf und laedt sie.
func _put_in_hand(stack: ItemStack) -> void:
	var weapon_data := stack.get_data() as WeaponData
	if weapon_data == null:
		return

	var saved: Dictionary = _magazines.get(stack.instance_id, {})
	var saved_rounds := int(saved.get("rounds", 0))
	var saved_ammo: StringName = saved.get("ammo", &"")

	if saved_rounds > 0 and saved_ammo != &"":
		weapon.setup(stack.item_id, saved_ammo)
		weapon.load_rounds(saved_rounds)
		return

	var compatible := inventory.get_compatible_ammo(weapon_data)
	var chosen: StringName = compatible[0] if not compatible.is_empty() else &""

	if chosen == &"":
		# Waffe ohne passende Munition: trotzdem in die Hand nehmen,
		# aber sie bleibt leer. Das ist eine gueltige Notlage.
		weapon.data = weapon_data
		weapon.rounds_in_magazine = 0
		return

	weapon.setup(stack.item_id, chosen)
	try_reload()


## Nimmt eine Waffe aus dem Inventar in die Hand.
## Kurzform fuer assign_weapon() auf den ersten freien Platz.
func equip_from_inventory(stack: ItemStack) -> bool:
	return assign_weapon(stack)


## Packt weg, was in einem Platz steckt: vom Koerper zurueck ins Raster.
##
## Mit `x`/`y` landet es auf einem bestimmten Feld — das ist der Fall beim
## Ziehen mit der Maus. Passt es dort nicht, sucht es sich selbst einen Platz.
##
## Passt es NIRGENDS hin, bleibt es angelegt und die Funktion gibt `false`
## zurueck. Etwas fallen zu lassen, weil kein Platz ist, waere im Raid ein
## stiller Verlust — und zwar meist der teuerste Gegenstand, den man hat.
func stow_equipment(slot: ItemData.EquipSlot, x: int = -1, y: int = -1) -> bool:
	if equipment == null or inventory == null:
		return false

	var stack := equipment.get_item(slot)
	if stack == null:
		return false

	# Das Magazin gehoert zur Waffe und muss mitwandern, bevor die Hand
	# leer wird.
	if Equipment.is_weapon_slot(slot) and slot == active_weapon_slot:
		_remember_magazine()

	var placed := false
	if x >= 0 and y >= 0 and inventory.grid.can_place(stack, x, y):
		placed = inventory.grid.place(stack, x, y)
	if not placed:
		placed = inventory.grid.add_item(stack)
	if not placed:
		return false

	equipment.unequip(slot)

	# Die Waffe, die gerade in der Hand lag, ist jetzt im Rucksack. Statt mit
	# leeren Haenden dazustehen, greift der Spieler zur zweiten Waffe — hat er
	# keine, sind die Haende eben leer.
	if Equipment.is_weapon_slot(slot) and slot == active_weapon_slot:
		var other := ItemData.EquipSlot.SECONDARY \
			if slot == ItemData.EquipSlot.PRIMARY else ItemData.EquipSlot.PRIMARY
		if equipment.get_item(other) != null:
			select_weapon_slot(other)
		else:
			_empty_hands()

	return true


# ---------------------------------------------------------------------------
# Behandlung
#
# Behandeln dauert. Ein Verband braucht sechs Sekunden, eine Operation
# zwanzig — und in dieser Zeit ist man beschaeftigt. Genau das soll die
# Entscheidung erzeugen: jetzt in Deckung versorgen, oder es bis zum Ausgang
# versuchen.
#
# HINWEIS ZUM NETZWERK: Der Client fragt an, der Server laesst die Uhr laufen
# und entscheidet am Ende. Sonst behandelt sich jeder in null Sekunden.
# ---------------------------------------------------------------------------

signal treatment_started(med: MedicalData, part: HealthSystem.Part)
signal treatment_finished(med: MedicalData, part: HealthSystem.Part, success: bool)

## Die laufende Behandlung, oder ein leeres Dictionary.
## {stack, med, part, elapsed, duration}
var _treatment: Dictionary = {}


## Beginnt eine Behandlung. Gibt zurueck, ob sie ueberhaupt sinnvoll ist —
## ein Verband an einem gesunden Bein wird gar nicht erst angefangen, statt
## sechs Sekunden lang nichts zu tun und sich dann zu verbrauchen.
func start_treatment(stack: ItemStack, part: HealthSystem.Part) -> bool:
	if stack == null or health == null or health.is_dead:
		return false
	var med := stack.get_data() as MedicalData
	if med == null or not can_treat_with(med, part):
		return false

	var duration := med.use_seconds
	if med.kind == MedicalData.Kind.BLOOD:
		# Der Beutel laeuft, bis der Koerper voll ist oder er leer ist.
		duration = _blood_duration(med)

	_treatment = {
		"stack": stack, "med": med, "part": int(part),
		"elapsed": 0.0, "duration": maxf(0.1, duration),
	}
	treatment_started.emit(med, part)
	return true


## Wie lange dieser Beutel laufen wird: so lange, bis der Koerper voll ist —
## laenger nur, wenn nicht genug drin ist.
func _blood_duration(med: MedicalData) -> float:
	if med.blood_per_second <= 0.0:
		return 1.0
	var missing := HealthSystem.MAX_BLOOD - health.blood
	var usable := minf(missing, med.blood_total)
	return maxf(0.5, usable / med.blood_per_second)


## Ob dieses Mittel an diesem Koerperteil etwas ausrichtet.
func can_treat_with(med: MedicalData, part: HealthSystem.Part) -> bool:
	if med == null or health == null:
		return false

	match med.kind:
		MedicalData.Kind.SURGERY:
			return health.is_destroyed(part)
		MedicalData.Kind.BLOOD:
			return health.blood < HealthSystem.MAX_BLOOD
		MedicalData.Kind.PAINKILLER:
			return true
		_:
			if injuries != null and injuries.can_treat(med, part):
				return true
			# Ein Verband heilt nebenbei ein paar Trefferpunkte — das darf
			# auch der Grund sein, ihn zu benutzen.
			return med.heal_hp > 0.0 and health.get_hp(part) < health.get_effective_max_hp(part)


func is_treating() -> bool:
	return not _treatment.is_empty()


func get_treatment_progress() -> float:
	if _treatment.is_empty():
		return 0.0
	return clampf(float(_treatment["elapsed"]) / float(_treatment["duration"]), 0.0, 1.0)


func get_treatment_label() -> String:
	if _treatment.is_empty():
		return ""
	var med: MedicalData = _treatment["med"]
	return "%s — %s" % [med.display_name,
		HealthSystem.get_part_name(_treatment["part"])]


## Abbrechen. Der Gegenstand bleibt heil: Wer eine Behandlung abbricht, soll
## nicht auch noch den Verband verlieren.
func cancel_treatment() -> void:
	if _treatment.is_empty():
		return
	var med: MedicalData = _treatment["med"]
	var part: int = _treatment["part"]
	_treatment = {}
	treatment_finished.emit(med, part, false)


## Laesst die Uhr der laufenden Behandlung weiterlaufen.
## Oeffentlich, damit Tests sie ohne echte Physikframes vorspulen koennen.
func tick_treatment(delta: float) -> void:
	if _treatment.is_empty():
		return

	if health != null and health.is_dead:
		cancel_treatment()
		return

	_treatment["elapsed"] = float(_treatment["elapsed"]) + delta
	if float(_treatment["elapsed"]) < float(_treatment["duration"]):
		return

	_finish_treatment()


func _finish_treatment() -> void:
	var stack: ItemStack = _treatment["stack"]
	var med: MedicalData = _treatment["med"]
	var part: int = _treatment["part"]
	_treatment = {}

	_apply_treatment(med, part)
	_consume(stack)
	treatment_finished.emit(med, part, true)


func _apply_treatment(med: MedicalData, part: int) -> void:
	match med.kind:
		MedicalData.Kind.SURGERY:
			health.apply_surgery(part)
		MedicalData.Kind.BLOOD:
			health.restore_blood(med.blood_total)
		MedicalData.Kind.PAINKILLER:
			if injuries != null:
				injuries.apply_painkillers(med.pain_relief_seconds)
		_:
			if injuries != null:
				injuries.treat(med, part)
			if med.heal_hp > 0.0:
				health.heal(part, med.heal_hp)


## Verbraucht eine Anwendung. Ein Stapel Verbaende wird dabei kleiner, statt
## dass der ganze Stapel verschwindet.
func _consume(stack: ItemStack) -> void:
	if stack == null or inventory == null:
		return
	stack.quantity -= 1
	if stack.quantity <= 0:
		inventory.grid.remove_item(stack.instance_id)
	inventory.changed.emit()


## Alle medizinischen Gegenstaende im Inventar — fuer die Auswahl im Fenster.
func get_medical_items() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	if inventory == null or inventory.grid == null:
		return result
	for stack in inventory.grid.get_all_stacks():
		if stack.get_data() is MedicalData:
			result.append(stack)
	return result


## Leere Haende. Schiessen ist damit unmoeglich (Weapon.try_fire prueft `data`).
func _empty_hands() -> void:
	if weapon != null:
		weapon.data = null
		weapon.loaded_ammo = null
		weapon.rounds_in_magazine = 0
	if inventory != null:
		inventory.equipped_weapon = null


## Entlaedt das Magazin zurueck ins Inventar.
##
## Muss vor jeder Extraction passieren, sonst verschwinden die geladenen
## Patronen — bei M995 waeren das ueber 20.000 Spielwaehrung pro Raid.
## Solange Magazine keine eigenen Gegenstaende sind, ist das Magazin ein
## blinder Fleck: Munition darin gehoert niemandem.
func unload_weapon() -> int:
	if weapon == null or inventory == null or weapon.rounds_in_magazine <= 0:
		return 0
	var rounds := weapon.rounds_in_magazine
	if not inventory.add(weapon.ammo_id, rounds):
		# Kein Platz: lieber im Magazin lassen als vernichten.
		return 0
	weapon.rounds_in_magazine = 0
	return rounds


## Nachladen: holt echte Patronen aus dem Inventar.
## Ein halb gefuelltes Magazin ist ein gueltiges Ergebnis.
func try_reload() -> int:
	if weapon == null or inventory == null or weapon.data == null:
		return 0
	var needed := weapon.get_missing_rounds()
	if needed <= 0:
		return 0
	var available := inventory.take_ammo(weapon.ammo_id, needed)
	return weapon.load_rounds(available)


## Wechselt die geladene Munitionssorte. Die noch im Magazin steckenden
## Patronen wandern zurueck ins Inventar, statt zu verschwinden.
func switch_ammo(new_ammo_id: StringName) -> bool:
	if weapon == null or inventory == null or weapon.data == null:
		return false
	var candidate := ItemRegistry.get_item(new_ammo_id) as AmmoData
	if candidate == null or not weapon.data.accepts_ammo(candidate):
		return false

	if weapon.rounds_in_magazine > 0 and weapon.ammo_id != new_ammo_id:
		inventory.add(weapon.ammo_id, weapon.rounds_in_magazine)
		weapon.rounds_in_magazine = 0

	weapon.setup(weapon.weapon_id, new_ammo_id)
	try_reload()
	return true


## Schaltet die Steuerung ab, solange ein Fenster offen ist.
##
## Der Abzug wird dabei bewusst losgelassen: Wer im Dauerfeuer das Inventar
## oeffnet, soll nicht weiterballern, und beim Schliessen nicht sofort wieder
## anfangen, nur weil die Maustaste noch gedrueckt war.
func set_ui_open(open: bool) -> void:
	if ui_open == open:
		return
	ui_open = open

	if open:
		is_sprinting = false
		if weapon != null:
			weapon.release_trigger()

	_capture_mouse(not open)


## Rückstoß hebt die Kamera an. Der Aufschlag ist sofort, die Erholung
## langsam — dadurch muss der Spieler bei Dauerfeuer gegenhalten.
func _on_recoil_kick(vertical: float, horizontal: float) -> void:
	_recoil_pitch += vertical
	_recoil_yaw += horizontal


func _update_recoil(delta: float) -> void:
	if is_zero_approx(_recoil_pitch) and is_zero_approx(_recoil_yaw):
		return

	var recovered_pitch := move_toward(_recoil_pitch, 0.0, recoil_recovery_speed * delta * maxf(1.0, absf(_recoil_pitch)))
	var recovered_yaw := move_toward(_recoil_yaw, 0.0, recoil_recovery_speed * delta * maxf(1.0, absf(_recoil_yaw)))

	# Nur die Differenz anwenden, sonst driftet die Blickrichtung weg.
	_pitch += _recoil_pitch - recovered_pitch
	rotate_y(deg_to_rad(-(_recoil_yaw - recovered_yaw)))

	_recoil_pitch = recovered_pitch
	_recoil_yaw = recovered_yaw
	_pitch = clampf(_pitch, -pitch_limit_degrees, pitch_limit_degrees)
	_camera_pivot.rotation_degrees.x = _pitch


func _handle_weapon_input() -> void:
	if weapon == null or ui_open:
		return

	if Input.is_action_just_pressed("fire_mode"):
		weapon.cycle_fire_mode()
	if Input.is_action_just_pressed("reload"):
		try_reload()
	if Input.is_action_just_released("fire"):
		weapon.release_trigger()

	# Sprinten und Schiessen schliessen sich aus — die Waffe ist weggeklappt.
	if is_sprinting:
		return


	weapon.try_fire(
		Input.is_action_pressed("fire"),
		Input.is_action_just_pressed("fire")
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# Waagerecht dreht die ganze Figur, senkrecht nur den Kopf.
		rotate_y(deg_to_rad(-motion.relative.x * mouse_sensitivity))
		_pitch = clampf(
			_pitch - motion.relative.y * mouse_sensitivity,
			-pitch_limit_degrees,
			pitch_limit_degrees
		)
		_camera_pivot.rotation_degrees.x = _pitch

	# Bei offenem Fenster darf die Maus nicht eingefangen werden — sonst
	# koennte man nichts mehr anklicken.
	if event.is_action_pressed("toggle_mouse") and not ui_open:
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)


func _capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	_update_survival(delta)
	_update_crouch(delta)
	_update_stamina(delta)
	_update_movement(delta)
	_update_recoil(delta)
	_handle_weapon_input()

	move_and_slide()


## Hunger, Durst und Kaelte fortschreiben — und ihren Schaden anwenden.
##
## Der Schaden wirkt einmal pro Sekunde statt in jedem Frame. Bei 60 Bildern
## waeren es sonst 60 winzige Ereignisse pro Sekunde, und jede Anzeige, die
## am Schadenssignal haengt, wuerde flackern.
func _update_survival(delta: float) -> void:
	if survival == null or health == null or health.is_dead:
		return

	survival.metabolism_multiplier = health.get_metabolism_multiplier()
	survival.tick(delta)

	# Blutungen laufen im selben Takt weiter. Sie sind der Grund, warum man
	# eine Behandlung nicht "spaeter" macht.
	if injuries != null:
		injuries.tick(delta, health)
	tick_treatment(delta)

	_survival_damage_timer += delta
	if _survival_damage_timer < 1.0:
		return
	_survival_damage_timer -= 1.0

	for entry in survival.get_damage_this_second():
		health.apply_damage(entry.part, entry.amount)


func _update_crouch(delta: float) -> void:
	is_crouching = not ui_open and Input.is_action_pressed("crouch") and is_on_floor()
	var target_height := crouch_eye_height if is_crouching else stand_eye_height
	# Weich statt sprunghaft — sonst wirkt das Ducken wie ein Teleport.
	_camera_pivot.position.y = move_toward(_camera_pivot.position.y, target_height, 6.0 * delta)

	var shape := _collision.shape as CapsuleShape3D
	if shape != null:
		var target_shape_height := 1.2 if is_crouching else 1.8
		shape.height = move_toward(shape.height, target_shape_height, 4.0 * delta)


func _update_stamina(delta: float) -> void:
	if is_sprinting:
		stamina = maxf(0.0, stamina - stamina_drain_per_second * delta)
		_time_since_sprint = 0.0
	else:
		_time_since_sprint += delta
		if _time_since_sprint >= stamina_regen_delay:
			stamina = minf(max_stamina, stamina + stamina_regen_per_second * delta)

	stamina_changed.emit(stamina, max_stamina)

	# Nur einmal melden, nicht in jedem Frame.
	if stamina <= 0.0 and not _was_exhausted:
		_was_exhausted = true
		exhausted.emit()
	elif stamina > max_stamina * 0.2:
		_was_exhausted = false


## Wie stark die Traglast das Tempo verändert.
##
##   ueber 1.0 = leicht unterwegs, schneller als normal
##   genau 1.0 = an der Komfortgrenze
##   unter 1.0 = überladen, langsamer
##
## Beispielwerte mit den Standardeinstellungen:
##   0 kg -> 1.18    6 kg -> 1.00    12 kg -> 0.84    24 kg -> 0.66    40 kg -> 0.45
func get_weight_factor() -> float:
	if carried_weight_kg <= comfortable_weight_kg:
		# Bonus läuft von voll (leeres Inventar) auf null (Komfortgrenze) aus.
		var light_ratio := carried_weight_kg / maxf(0.01, comfortable_weight_kg)
		return 1.0 + unencumbered_bonus * (1.0 - clampf(light_ratio, 0.0, 1.0))

	var over := carried_weight_kg - comfortable_weight_kg
	var span := maxf(1.0, max_weight_kg - comfortable_weight_kg)
	var ratio := clampf(over / span, 0.0, 1.0)
	# Kurve < 1.0 zieht kleine Werte nach oben: die ersten Kilos wirken stärker.
	var curved := pow(ratio, weight_curve)
	return 1.0 - curved * weight_slowdown


## Ob gerade gesprintet werden darf.
## Bewusst restriktiv: nicht rückwärts, nicht geduckt, nicht ohne Ausdauer,
## nicht hoffnungslos überladen.
func can_sprint(input_dir: Vector2) -> bool:
	if is_crouching or not is_on_floor():
		return false
	if stamina <= 0.0:
		return false
	if carried_weight_kg >= max_weight_kg:
		return false
	return input_dir.y < -0.1


## Wie stark Verletzungen und Kaelte das Tempo druecken.
##
## Multiplikativ verrechnet, nicht addiert: Zwei Strafen von je 35 % ergeben
## 42 % Resttempo, nicht 30 %. So kann der Spieler nie auf null fallen und
## voellig handlungsunfaehig werden — er wird langsam, aber bleibt spielbar.
func get_condition_factor() -> float:
	var factor := 1.0
	if health != null:
		factor *= 1.0 - health.get_movement_penalty()
		factor *= 1.0 - health.get_blood_penalty()
	if survival != null:
		factor *= 1.0 - survival.get_cold_movement_penalty()
	if injuries != null:
		factor *= 1.0 - injuries.get_movement_penalty()
	return maxf(0.15, factor)


func get_current_max_speed() -> float:
	var base := walk_speed
	if is_crouching:
		base = crouch_speed
	elif is_sprinting:
		base = sprint_speed
	return base * get_weight_factor() * get_condition_factor()


func _update_movement(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Bei offenem Fenster bleibt die Eingabe leer — die Figur bremst dadurch
	# von selbst aus, statt abrupt stehenzubleiben.
	var input_dir := Vector2.ZERO if ui_open \
		else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_sprinting = not ui_open and Input.is_action_pressed("sprint") and can_sprint(input_dir)

	if not ui_open and Input.is_action_just_pressed("jump") and is_on_floor() and stamina > 10.0:
		velocity.y = jump_velocity
		stamina = maxf(0.0, stamina - 8.0)

	# Eingaberichtung in Weltkoordinaten umrechnen.
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := get_current_max_speed()
	var control := 1.0 if is_on_floor() else air_control

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() > 0.01:
		var target := direction * speed
		horizontal = horizontal.move_toward(target, acceleration * control * delta * speed)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, deceleration * control * delta * speed)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
