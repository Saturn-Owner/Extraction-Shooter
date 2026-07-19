## Basisklasse fuer alle sichtbaren Waffenmodelle.
##
## GRUNDSATZ: Jede Waffe hat ihr eigenes Modell und ihre eigene Mechanik in
## einer eigenen Datei unter scripts/weapons/. Es gibt bewusst KEINE
## Einheitswaffe mit ausgetauschten Werten — eine Pistole hat einen Schlitten,
## eine Vorderschaftrepetierflinte eine Pumpe, ein Sturmgewehr einen
## Verschluss. Das sind unterschiedliche Bewegungen, keine Varianten
## derselben.
##
## Diese Klasse liefert nur das Geruest:
##   - Kennwerte, die weapon_view.gd zum Zielen und Halten braucht
##   - das Standardverhalten eines Gewehrs mit Verschluss
##   - das Auffinden beweglicher Teile ueber ihre Namen
##
## Eine Unterklasse ueberschreibt:
##   _configure()    Kennwerte und Haltung dieser Waffe
##   _build_parts()  die Geometrie
##   und alles, wo ihre Mechanik vom Standard abweicht
##
## WARUM IM CODE UND NICHT ALS .tscn: Szenen lassen sich bei Konflikten
## praktisch nicht mergen (siehe CLAUDE.md). Bei zwoelf Waffen und zwei
## Entwicklern waere das eine dauerhafte Konfliktquelle.
class_name WeaponViewmodel
extends Node3D

## Hoehe der AKTIVEN Visierlinie ueber dem Modellursprung.
##
## weapon_view.gd senkt das Modell beim Zielen um genau diesen Wert ab, damit
## die Visierlinie auf der Kameramitte landet. Wer hier lügt, baut eine Waffe,
## die neben ihrem eigenen Korn vorbeischiesst.
##
## Unterklassen setzen hier in _configure() die Hoehe ihrer EIGENEN Visierung.
## Sitzt spaeter eine Optik auf der Waffe, wird der Wert auf deren Zielpunkt
## umgestellt — die Notvisierung klappt dann weg und zaehlt nicht mehr.
var sight_height: float = 0.068

## Die Hoehe der eingebauten Visierung, unabhaengig von Anbauteilen.
## Wird nach _configure() gesichert und danach nie wieder veraendert.
var iron_sight_height: float = 0.068

## Wie weit vorn die Muendung sitzt (negatives Z).
## Ein Schalldaempfer schiebt den Wert nach vorn.
var muzzle_z: float = -0.575

## Die Muendung ohne Anbauteile.
var bare_muzzle_z: float = -0.575

## Die Waffendaten, zu denen dieses Modell gehoert.
## Liefert die Aufnahmen — ohne sie kann nichts angebaut werden.
var weapon_data: WeaponData

## Was montiert werden soll: {int(AttachmentData.Slot): StringName}.
##
## MUSS VOR build() GESETZT SEIN. Da _ready() build() aufruft, heisst das in
## der Praxis: vor dem Einhaengen in den Szenenbaum.
var attachments: Dictionary = {}

## Die tatsaechlich montierten Modelle, nach Steckplatz.
var mounted: Dictionary = {}

@export_group("Haltung")

## Ruhelage in der Hand.
var hip_position := Vector3(0.115, -0.125, -0.22)
var hip_rotation_degrees := Vector3(0.0, -3.5, 0.0)

## Wie weit die Waffe beim Zielen vom Auge weg bleibt.
var ads_distance: float = 0.16

## Weggeklappt beim Sprinten.
var sprint_position := Vector3(0.16, -0.20, -0.16)
var sprint_rotation_degrees := Vector3(-26.0, 24.0, -14.0)

## Angehoben beim Nachladen, damit der Wechsel im Bild stattfindet.
var reload_position := Vector3(0.075, -0.150, -0.235)
var reload_rotation_degrees := Vector3(24.0, 17.0, -34.0)

@export_group("Mechanik")

## Multiplikator auf den sichtbaren Rueckstoss. Eine Pistole springt anders
## als ein Praezisionsgewehr, auch bei gleichem Kaliber.
var recoil_scale: float = 1.0

## Wie weit der Verschluss zurueckfaehrt und wie lange er dafuer braucht.
var action_travel: float = 0.075
var action_cycle_time: float = 0.055

## Wie weit das Magazin beim Wechsel nach unten faellt.
var magazine_drop: float = 0.34

# Bewegliche Teile. Fehlende Teile bleiben null — eine Pistole hat keinen
# Feuerwahlhebel, eine Flinte kein abnehmbares Magazin.
var action: Node3D          ## Verschluss, Schlitten oder Pumpe
var magazine: Node3D
var trigger: Node3D
var selector: Node3D
var charging_handle: Node3D
var muzzle_point: Node3D

var _action_home: Vector3
var _magazine_home: Vector3
var _charging_handle_home: Vector3

var _action_timer: float = 0.0
var _action_locked: bool = false
var _trigger_pull: float = 0.0
var _handle_pull: float = 0.0


## Ob das Modell schon gebaut wurde.
##
## Verhindert doppeltes Bauen, wenn jemand build() von Hand aufruft und den
## Knoten danach in den Baum haengt — dann liefe _ready() ein zweites Mal
## darueber und jedes Teil waere doppelt vorhanden.
var _built: bool = false


func _ready() -> void:
	build()


## Modell aufbauen. Wird auch vom Renderwerkzeug ausserhalb des Spiels genutzt.
func build() -> void:
	if _built:
		return
	_built = true

	_configure()
	# Die eingebauten Werte sichern, bevor Anbauteile sie verschieben.
	iron_sight_height = sight_height
	bare_muzzle_z = muzzle_z

	_build_parts()
	_collect_parts()
	_apply_attachments()


## Haengt die Anbauteile an ihre Aufnahmen und blendet aus, was sie ersetzen.
##
## Laeuft einmal beim Bauen. Aendert sich die Bestueckung, wird das ganze
## Modell neu erzeugt statt hier nachgebessert — die Teile unterscheiden sich
## zu stark, um sie ineinander umzubauen.
func _apply_attachments() -> void:
	if weapon_data == null or attachments.is_empty():
		return

	for mount in weapon_data.mounts:
		if mount == null:
			continue
		var id: StringName = attachments.get(int(mount.slot), &"")
		if id == &"":
			continue

		var data := ItemRegistry.get_item(id) as AttachmentData
		if data == null or data.interface_tag != mount.interface_tag:
			push_warning("[%s] %s passt nicht an die Aufnahme %s"
				% [get_model_name(), id, mount.interface_tag])
			continue

		var anchor := get_node_or_null(String(mount.anchor)) as Node3D
		if anchor == null:
			# Stiller Fehlschlag waere hier das Schlimmste: Das Teil
			# verschwaende einfach, ohne Hinweis. verify_weapon_handling
			# prueft deshalb jeden Ankernamen gegen das gebaute Modell.
			push_error("[%s] Aufnahme-Knoten '%s' fehlt im Modell"
				% [get_model_name(), mount.anchor])
			continue

		# Was das Teil ersetzt, wird unsichtbar — nicht geloescht. Beim Visier
		# ist das sogar ehrlich: Die Notvisierung klappt nur weg.
		for hidden_name in mount.hides:
			var hidden := get_node_or_null(String(hidden_name)) as Node3D
			if hidden != null:
				hidden.visible = false

		if data.viewmodel_part == null:
			continue

		var part: AttachmentViewmodel = data.viewmodel_part.new()
		part.name = "Attachment%s" % AttachmentData.slot_name(mount.slot)
		anchor.add_child(part)
		part.build()
		mounted[int(mount.slot)] = part

		_adopt_attachment_geometry(mount, part)


## Uebernimmt Visierlinie und Muendung vom Anbauteil.
##
## Die Aufnahmen sind direkte, ungedrehte Kinder des Modells — deshalb genuegt
## es, ihre Position mit der des Teils zu addieren. Waeren sie verschachtelt
## oder gedreht, muesste hier ueber Transformationen gerechnet werden.
func _adopt_attachment_geometry(mount: WeaponMount, part: AttachmentViewmodel) -> void:
	var anchor := get_node_or_null(String(mount.anchor)) as Node3D
	if anchor == null:
		return

	if mount.slot == AttachmentData.Slot.SIGHT and part.aim_point != null:
		# Ab jetzt zielt der Spieler durch die Optik, nicht mehr ueber Kimme
		# und Korn. Genau hier entscheidet sich, ob die Waffe dorthin schiesst,
		# wo der Punkt steht.
		sight_height = anchor.position.y + part.aim_point.position.y

	if mount.slot == AttachmentData.Slot.MUZZLE and part.muzzle_point != null:
		muzzle_z = anchor.position.z + part.muzzle_point.position.z
		# Den Muendungspunkt der Waffe mitziehen, damit das Muendungsfeuer
		# an der Spitze des Daempfers erscheint und nicht mittendrin.
		if muzzle_point != null:
			muzzle_point.position.z = muzzle_z


# --- Von Unterklassen zu ueberschreiben ---

## Kennwerte und Haltung dieser Waffe setzen.
func _configure() -> void:
	pass


## Die Geometrie bauen. Bewegliche Teile brauchen die Namen aus _collect_parts.
func _build_parts() -> void:
	pass


## Kurzname fuer Renderbilder und Fehlermeldungen.
func get_model_name() -> String:
	return "unbenannt"


# --- Standardverhalten. Ueberschreiben, wo die Waffe abweicht. ---

## Ein Schuss ist gefallen.
func notify_shot() -> void:
	_action_timer = action_cycle_time
	_trigger_pull = 1.0


## Der Hahn ist ins Leere gefallen. Standardmaessig nur der Abzug —
## eine Waffe mit spuerbarem Klicken kann das ueberschreiben.
func notify_shot_dry() -> void:
	_trigger_pull = 1.0


## Verschluss haengt hinten (leergeschossen oder Ladehemmung).
func notify_action_locked(locked: bool) -> void:
	_action_locked = locked


## Nachladen laeuft. progress geht von 0 auf 1.
func notify_reload(progress: float, from_empty: bool) -> void:
	_animate_magazine_swap(progress)
	# Bei leergeschossener Waffe muss der Verschluss zum Schluss vor.
	if from_empty and progress > 0.85:
		_handle_pull = _ramp(progress, 0.85, 1.0)
	else:
		_handle_pull = 0.0


## Ladehemmung wird behoben — kraeftig am Ladehebel reissen.
func notify_unjam(progress: float) -> void:
	_handle_pull = sin(progress * PI)


## Feuerwahlhebel umgelegt.
func notify_fire_mode(mode: WeaponData.FireMode) -> void:
	if selector == null:
		return
	match mode:
		WeaponData.FireMode.BURST:
			selector.rotation_degrees.x = -45.0
		WeaponData.FireMode.AUTO:
			selector.rotation_degrees.x = -90.0
		_:
			selector.rotation_degrees.x = 0.0


## Alle beweglichen Teile in die Ruhelage.
func notify_sequence_ended() -> void:
	_handle_pull = 0.0
	if magazine != null:
		magazine.position = _magazine_home
		magazine.rotation_degrees = Vector3.ZERO
		magazine.visible = true


## Laufende Bewegung. Wird jeden Frame von weapon_view.gd aufgerufen.
func update_mechanics(delta: float) -> void:
	if _action_timer > 0.0:
		_action_timer = maxf(0.0, _action_timer - delta)

	if action != null:
		var travel := 0.0
		if _action_locked:
			travel = 1.0
		elif _action_timer > 0.0:
			# Sinus: hinten in der Mitte des Zyklus, vorn an beiden Enden.
			travel = sin((1.0 - _action_timer / action_cycle_time) * PI)
		action.position = _action_home + Vector3(0.0, 0.0, travel * action_travel)

	if trigger != null:
		_trigger_pull = maxf(0.0, _trigger_pull - delta * 9.0)
		trigger.rotation_degrees.x = -_trigger_pull * 14.0

	if charging_handle != null:
		charging_handle.position = _charging_handle_home + Vector3(0.0, 0.0, _handle_pull * action_travel)


## Magazin faellt raus, kurze Luecke, neues kommt rein.
## Die Luecke ist wichtig — ohne sie liest sich der Wechsel nicht.
func _animate_magazine_swap(progress: float) -> void:
	if magazine == null:
		return

	if progress < 0.30:
		var t := _ramp(progress, 0.0, 0.30)
		magazine.visible = true
		magazine.position = _magazine_home + Vector3(0.0, -magazine_drop * t, 0.02 * t)
		magazine.rotation_degrees = Vector3(18.0 * t, 0.0, 6.0 * t)
	elif progress < 0.45:
		magazine.visible = false
	else:
		var t := _ramp(progress, 0.45, 0.85)
		magazine.visible = true
		magazine.position = _magazine_home + Vector3(0.0, -magazine_drop * 0.88 * (1.0 - t), 0.0)
		magazine.rotation_degrees = Vector3(12.0 * (1.0 - t), 0.0, 0.0)


## Bewegliche Teile ueber ihre Namen einsammeln und Ruhelagen merken.
func _collect_parts() -> void:
	action = get_node_or_null("Action") as Node3D
	magazine = get_node_or_null("Magazine") as Node3D
	trigger = get_node_or_null("Trigger") as Node3D
	selector = get_node_or_null("Selector") as Node3D
	charging_handle = get_node_or_null("ChargingHandle") as Node3D
	muzzle_point = get_node_or_null("MuzzlePoint") as Node3D

	if action != null:
		_action_home = action.position
	if magazine != null:
		_magazine_home = magazine.position
	if charging_handle != null:
		_charging_handle_home = charging_handle.position


## Rechnet einen Abschnitt einer Zeitleiste auf 0..1 um.
static func _ramp(value: float, from: float, to: float) -> float:
	if to <= from:
		return 1.0
	return clampf((value - from) / (to - from), 0.0, 1.0)
