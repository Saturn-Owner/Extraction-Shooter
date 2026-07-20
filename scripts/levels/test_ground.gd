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
##   Tab           Charakterfenster: Ausrüstung, Trefferpunkte, Inventar
##   R             Nachladen (verbraucht echte Munition aus dem Inventar)
##   B             Feuermodus wechseln
##   Q / E         Waffe wechseln (nur was im Inventar liegt)
##   5 / 6         Munition wechseln (nur was im Inventar liegt)
##   T             Munitionsnachschub (Testhilfe)
##   Z             Rucksack mit Ballast füllen (Gewicht spüren)
##   0             Zurück zum Start, Ziele und Ausrüstung zurücksetzen
##   Esc           Maus freigeben
extends Node3D

## Startausrüstung. Bewusst knapp gehalten, damit man merkt, dass Munition
## eine begrenzte Ressource ist und nicht selbstverständlich.
## Reihenfolge ist wichtig: Grosse Gegenstaende zuerst, sonst zerstueckeln
## die kleinen das Raster und die Gewehre finden keinen Platz mehr.
const LOADOUT := [
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

	_place_humanoids()
	_add_character_window()
	_give_loadout()


## Das Charakterfenster gab es hier bisher nicht.
##
## ---------------------------------------------------------------------------
## WARUM DAS FEHLTE UND WARUM ES STÖRT
##
## Es hängt in `raid_eisstadt.tscn`, nicht in der Spielerszene — im
## Testgelände tat `Tab` deshalb schlicht nichts. Solange man hier nur auf
## flache Scheiben geschossen hat, fiel das niemandem auf.
##
## Mit den Figuren fällt es sofort auf: Sie haben Trefferpunkte pro Körperteil,
## und die will man beim Schiessen sehen. Ohne das Fenster ist der einzige
## Hinweis die kurze Schrift über ihrem Kopf, und die eigenen Trefferpunkte
## sieht man gar nicht.
##
## AUS DEM CODE UND NICHT IN DIE SZENE, aus demselben Grund wie die Figuren
## selbst: An `testgelaende.tscn` haben zuletzt beide Entwickler gearbeitet,
## und `.tscn` lässt sich bei Konflikten praktisch nicht zusammenführen.
const CHARACTER_WINDOW := preload("res://scenes/ui/character_window.tscn")

var _character_window: CharacterWindow


func _add_character_window() -> void:
	var hud := get_node_or_null("HUD")
	if hud == null:
		return

	_character_window = CHARACTER_WINDOW.instantiate() as CharacterWindow
	hud.add_child(_character_window)

	# Bei offenem Fenster steht die Figur still und die Maus ist frei —
	# sonst dreht man sich beim Ziehen im Raster im Kreis.
	_character_window.opened.connect(func(): _player.set_ui_open(true))
	_character_window.closed.connect(func(): _player.set_ui_open(false))


func _toggle_character_window() -> void:
	if _character_window == null:
		return
	if _character_window.is_open():
		_character_window.close()
		return
	_character_window.open_for(_player)


## Wo die Figuren stehen. Dritte Reihe neben den flachen Scheiben, damit man
## auf dieselbe Entfernung vergleichen kann: Scheibe ohne Platte bei x = -3,
## mit Platte bei x = 0, Figur bei x = +3.
## Die mittlere geht, die beiden anderen stehen. Ein bewegliches Ziel prüft
## den Vorhalt, ein stehendes die Trefferzonen — man braucht beides.
##
## DER GEHER STEHT WEITER RECHTS, und das ist kein Geschmack: Er pendelt um
## seinen Standplatz, also über acht Meter von x = 4 bis x = 12. Bliebe er
## wie die anderen bei x = 3, liefe seine Bahn von -1 bis 7 — mitten durch
## die gepanzerte Scheibe bei x = 0.
const HUMANOID_PLACES := [
	{distance = 25.0, x = 3.0, patrol = 0.0, speed = 0.0, label = "steht"},
	{distance = 50.0, x = 9.0, patrol = 14.0, speed = 4.4, label = "rennt"},
	{distance = 100.0, x = 8.0, patrol = 8.0, speed = 1.6, label = "geht"},
	{distance = 300.0, x = 3.0, patrol = 0.0, speed = 0.0, label = "steht"},
]


## Stellt die Figuren AUS DEM CODE hin, nicht in testgelaende.tscn.
##
## Szenen lassen sich bei Konflikten praktisch nicht mergen, und an dieser
## Szene haben zuletzt beide Entwickler gearbeitet — die Werkbank und die
## Zielscheiben liegen nur Stunden auseinander. Drei Knoten dafür in eine
## .tscn zu schreiben, wäre genau die Konfliktquelle, die uns beim letzten
## Zusammenführen Arbeit gemacht hat.
##
## Dieselbe Überlegung steht schon hinter `Weapon._build_voices()` und der
## Werkbank: Was sich im Code beschreiben lässt, gehört nicht in eine Szene.
func _place_humanoids() -> void:
	var container := get_node_or_null("Ziele")
	if container == null:
		return

	for place in HUMANOID_PLACES:
		var distance: float = place.distance
		var figure := HumanoidTarget.new()
		figure.name = "Figur%dm" % int(distance)
		figure.label_text = "%d m  %s" % [int(distance), place.label]
		figure.patrol_width = place.patrol
		figure.patrol_speed = place.speed

		container.add_child(figure)
		# Nach dem Einhängen setzen: global_position braucht den Baum.
		figure.global_position = Vector3(place.x, 0.0, -distance)
		# Sie schaut den Schützen an — sonst zielt man auf ihre Seite und
		# die Arme decken den Rumpf ab.
		figure.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		figure.part_hit.connect(_on_humanoid_hit.bind(figure))


## Füllt das Inventar und nimmt die erste Waffe in die Hand.
func _give_loadout() -> void:
	var inventory := _player.inventory
	if inventory == null:
		return

	# Der Schiessstand ist kein Raid: Hier geht es darum, jede Waffe mit jedem
	# Kaliber auszuprobieren, nicht darum, Platz zu verwalten. Die nackten
	# Taschen (2x8) fassen davon nicht einmal die Haelfte, deshalb bekommt
	# der Spieler hier ein grosszuegiges Raster.
	inventory.grid.resize(10, 8)

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


## Bei der Figur steht das KÖRPERTEIL vorn, nicht der Schaden.
##
## Das ist die Frage, die man an einer Figur hat: Habe ich getroffen, was ich
## treffen wollte? Wie viel Schaden es war, sagt die Beschriftung über ihrem
## Kopf ohnehin dauerhaft.
func _on_humanoid_hit(part: HealthSystem.Part, result: Ballistics.HitResult,
		figure: HumanoidTarget) -> void:
	_last_hit = "%s — %s: %s" % [
		figure.label_text, BlockyCharacter.part_name(part), result.describe()]


func _find_humanoids() -> Array[HumanoidTarget]:
	var result: Array[HumanoidTarget] = []
	var container := get_node_or_null("Ziele")
	if container == null:
		return result
	for child in container.get_children():
		if child is HumanoidTarget:
			result.append(child as HumanoidTarget)
	return result


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
		KEY_TAB:
			_toggle_character_window()
		KEY_ESCAPE:
			# Das Fenster schreibt unten selbst "[Tab] / [Esc] schliessen" —
			# ohne diese Zeile wäre der Hinweis hier gelogen.
			#
			# Kein Streit mit der Maustaste: PlayerController prüft bei
			# `toggle_mouse` ausdrücklich `not ui_open`, und offen ist offen.
			if _character_window != null and _character_window.is_open():
				_character_window.close()
		KEY_Q:
			_switch_weapon(-1)
		KEY_E:
			_switch_weapon(1)
		# Nicht F/G: F ist inzwischen die Interaktionstaste.
		KEY_5:
			_switch_ammo(-1)
		KEY_6:
			_switch_ammo(1)
		KEY_T:
			# Testhilfe: Nachschub für alle Kaliber.
			for entry in LOADOUT:
				var data := ItemRegistry.get_item(entry.id)
				if data is AmmoData:
					inventory.add(entry.id, entry.count)
			_last_action = "Munition aufgefüllt"
		KEY_Z:
			# Ballast, um die Gewichtsbremse zu spüren. Frueher war das eine
			# Schutzplatte; solange es nur Waffen und Munition gibt, tut es
			# ein Schwung Gewehrmunition genauso.
			if inventory.add(&"ammo_762x51_m80", 40):
				_last_action = "40 Patronen eingepackt"
			else:
				_last_action = "kein Platz mehr"
		KEY_0:
			_player.global_position = _spawn
			_player.velocity = Vector3.ZERO
			for target in _find_targets():
				target.reset()
			for figure in _find_humanoids():
				figure.reset()
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
	lines.append("Tab Charakter  Q/E Waffe  5/6 Munition  R Laden  B Modus")
	lines.append("T Nachschub  Z Ballast  0 Reset  Esc Maus")

	_label.text = "\n".join(lines)

