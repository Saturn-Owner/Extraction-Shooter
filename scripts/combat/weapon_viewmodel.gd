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

## ---------------------------------------------------------------------------
## ABLAUF DER LEEREN NACHLADUNG NACH DEM MAGAZINWECHSEL
##
## `_animate_magazine_swap()` ist mit ihren eigenen Bruchteilen (0/0.30/0.45/
## 0.85, teils abweichend je Waffe) fertig, sobald das neue Magazin sitzt.
## Was danach passiert, ist in eigene Phasen aufgeteilt, statt alles auf
## einmal ab 0.85 loszutreten — sonst dreht sich die Waffe, waehrend das
## Magazin noch gar nicht sitzt, und der Ladehebelzug faellt zeitlich mit der
## Drehung zusammen. Beides wurde genau so gemeldet und sah dadurch wie eine
## einzige verwaschene Bewegung aus statt wie drei einzelne Handgriffe.
##
##   0.85 -- RACK_TURN_START_PROGRESS      Pause. Nichts bewegt sich.
##   RACK_TURN_START_PROGRESS -- HANDLE_PULL_START_PROGRESS
##                                          Die Kamera dreht sich zur Seite
##                                          (weapon_view.gd liest diese Grenze
##                                          mit, siehe dort).
##   HANDLE_PULL_START_PROGRESS -- 1.0      Der Ladehebel wird gezogen.
##
## Als Bruchteile von 0..1 und nicht als feste Sekunden, weil der gesamte
## Nachladevorgang selbst schon in Bruchteilen rechnet (siehe notify_reload).
## weapon_view.gd braucht dieselben Grenzen fuer die Kameradrehung — deshalb
## stehen sie hier und nicht als Zahlen, die in zwei Dateien auseinanderlaufen
## koennten.
##
## VARIABLEN, KEINE KONSTANTEN: Eine Waffe mit eigenem, laengerem
## `reload_time_empty` (siehe WeaponData) und einer eigenen, mehrstufigen
## `_animate_magazine_swap()` braucht auch eigene Grenzen dafuer, wo ihr
## Magazinwechsel endet und wo ihre Drehung beginnen darf — siehe
## `_configure()` der AKM fuer ein Beispiel.
var rack_turn_start_progress: float = 0.87
var handle_pull_start_progress: float = 0.93

## WOHIN die Waffe fuer den Ladehebelzug dreht — null heisst: die Vorgabe
## der Kamera gilt (rack_turn_rotation/-offset in weapon_view.gd, entworfen
## fuer seitliche Hebel wie am AK).
##
## Eine Waffe, deren Ladehebel woanders sitzt, setzt hier ihre eigene Pose:
## Die AR-15 hat ihn hinten OBEN — sie wird zum Durchladen angewinkelt statt
## zur Seite gedreht (siehe AR15Viewmodel._configure()). Bewusst am Modell
## statt in weapon_view: weapon_view kennt keine Waffenteile, aber das
## Modell weiss, wo sein Hebel sitzt.
var rack_turn_rotation_override: Variant = null
var rack_turn_offset_override: Variant = null

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

## Ob der Spieler seine eigenen Hände an dieser Waffe sieht.
##
## ---------------------------------------------------------------------------
## JEDE WAFFE ENTSCHEIDET DAS SELBST
##
## `ViewmodelArms` greift `grip_point` und `support_point` — die muss es
## geben, und sie müssen an dieser Waffe auch stimmen. Bei der AR-15 sind sie
## am Modell gemessen; bei den übrigen gibt es sie noch nicht.
##
## Hände an eine Waffe zu setzen, deren Griffpunkte nicht stimmen, sieht
## schlimmer aus als gar keine: Sie fassen dann sichtbar daneben. Deshalb
## steht der Schalter hier und nicht als Liste im Kameracode — dieselbe
## Überlegung wie bei Grundsatzentscheidung 5, wo jede Waffe ihr eigenes
## Modell und ihre eigene Mechanik mitbringt.
##
## Wer eine Waffe mit Händen ausstatten will, misst ihre Griffpunkte und
## setzt das hier auf `true`. `verify_weapon_handling` prüft danach, ob die
## Arme wirklich hinreichen.
var shows_hands: bool = false

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

## Wo die Hände anfassen. Nur fuer Figuren, die man von aussen sieht — im
## Kameraraum sieht man ohnehin keine Haende.
##
## JEDE WAFFE SAGT SELBST, WO SIE ANGEFASST WIRD. Ein Sturmgewehr hat einen
## Pistolengriff und einen Vorderschaft, eine Flinte eine Pumpe, eine Pistole
## nur eine Griffstelle. Zentrale Werte in der Figur wuerden bedeuten, dass
## jede Waffe gleich gehalten wird — genau das, was CLAUDE.md fuer die
## Modelle ausschliesst.
##
## Fehlt einer der Punkte, faellt die Figur auf eine feste Haltung zurueck.
var grip_point: Node3D
var support_point: Node3D

## Wo die Hand beim Nachladen hingreift: an den Magazinschacht.
##
## NICHT AN DAS MAGAZIN SELBST. Das faellt beim Wechsel 34 cm nach unten, und
## dorthin reicht kein Arm — die Hand haenge dem Magazin hinterher, statt es
## zu wechseln. So laedt auch niemand nach: Man greift an den Schacht, loest
## das Magazin, und es faellt von allein.
var magwell_point: Node3D

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
## Gerechnet wird ueber die volle Transformationskette bis zum Modell hinauf,
## nicht ueber das Addieren zweier Positionen. Der kurze Weg hat vorausgesetzt,
## dass Aufnahmen ungedrehte Direktkinder sind und Teile in ihrer Aufnahme bei
## null sitzen. Beides gilt nicht mehr, seit Modelle aus Blender kommen: Die
## sind um 90 Grad gedreht, und jedes Teil bringt seine eigene Einbaustelle mit.
func _adopt_attachment_geometry(mount: WeaponMount, part: AttachmentViewmodel) -> void:
	var anchor := get_node_or_null(String(mount.anchor)) as Node3D
	if anchor == null:
		return

	if mount.slot == AttachmentData.Slot.SIGHT and part.aim_point != null:
		# Ab jetzt zielt der Spieler durch die Optik, nicht mehr ueber Kimme
		# und Korn. Genau hier entscheidet sich, ob die Waffe dorthin schiesst,
		# wo der Punkt steht.
		sight_height = position_in_model(part.aim_point).y

	if mount.slot == AttachmentData.Slot.MUZZLE and part.muzzle_point != null:
		muzzle_z = position_in_model(part.muzzle_point).z
		# Den Muendungspunkt der Waffe mitziehen, damit das Muendungsfeuer
		# an der Spitze des Daempfers erscheint und nicht mittendrin.
		if muzzle_point != null:
			muzzle_point.position.z = muzzle_z


## Wo dieser Knoten im Koordinatensystem des Modells liegt.
##
## Bewusst nicht ueber global_position: Das Modell haengt beim Bauen und in
## den Tests oft noch gar nicht im Szenenbaum, und dann liefert global_position
## Unsinn.
func position_in_model(node: Node3D) -> Vector3:
	var accumulated := Transform3D.IDENTITY
	var current := node
	while current != null and current != self:
		accumulated = current.transform * accumulated
		current = current.get_parent() as Node3D
	return accumulated.origin


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
func notify_reload(progress: float, from_empty: bool,
		chamber_only: bool = false) -> void:
	# Beim blossen Durchladen bleibt das Magazin, wo es ist. Sonst faellt hier
	# ein Magazin heraus, das gleich darauf wieder erscheint, obwohl es die
	# Waffe nie verlassen hat — siehe Weapon._reload_chamber_only.
	if not chamber_only:
		_animate_magazine_swap(progress)
	# Bei leergeschossener Waffe muss der Verschluss zum Schluss vor — aber
	# erst NACH der Pause und der Kameradrehung (siehe handle_pull_start_
	# progress oben), nicht schon direkt nach dem Magazinwechsel.
	if from_empty and progress > handle_pull_start_progress:
		var t := _ramp(progress, handle_pull_start_progress, 1.0)
		# Quadratisch statt linear: Der Hebel bewegt sich am Anfang kaum und
		# schnellt zum Schluss. Linear anwuchs sieht aus wie eine gleichmaessig
		# laufende Maschine; das hier liest sich als Ruck einer echten Hand.
		_handle_pull = t * t
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
	grip_point = get_node_or_null("GripPoint") as Node3D
	support_point = get_node_or_null("SupportPoint") as Node3D
	magwell_point = get_node_or_null("MagwellPoint") as Node3D

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
