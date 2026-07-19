## Prüft die Treffer-Rückmeldung im echten Szenenbaum.
##
##   godot --headless --path . --script res://tests/verify_feedback.gd
##
## Anders als die anderen Tests laeuft dieser nicht auf reiner Mathematik,
## sondern baut das Testgelaende auf, drueckt wirklich ab und schaut nach,
## ob Geschosse, Effekte und Anzeigen tatsaechlich entstehen.
##
## Was er NICHT pruefen kann: ob es gut aussieht oder sich gut anfuehlt.
extends SceneTree

## Notbremse: Wenn ein Laufzeitfehler die Test-Koroutine abbricht, wird
## quit() nie erreicht und Godot laeuft endlos weiter. Ein haengender Test
## ist schlimmer als ein fehlschlagender — er faellt erst auf, wenn jemand
## nachschaut, warum nichts fertig wird.
const TIMEOUT_SECONDS := 60.0

var _failed := 0
var _passed := 0
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Treffer-Rueckmeldung pruefen ===\n")
	_run_all()


func _process(delta: float) -> bool:
	if _done:
		return false
	_elapsed += delta
	if _elapsed >= TIMEOUT_SECONDS:
		print("\n=== ABBRUCH: Test haengt seit %.0f s ===" % TIMEOUT_SECONDS)
		print("Wahrscheinlich hat ein Laufzeitfehler die Koroutine abgebrochen.")
		print("Bisher: %d bestanden, %d fehlgeschlagen" % [_passed, _failed])
		quit(1)
	return false


## Muss asynchron laufen: In _initialize() ist der Szenenbaum noch nicht
## bereit, Knoten landen dann nicht wirklich im Baum und _ready() feuert nie.
func _run_all() -> void:
	await process_frame

	_test_audio_generation()
	_test_real_recordings()
	await _test_effects_spawn()
	await _test_firing_in_level()


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


func _finish() -> void:
	_done = true
	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Die Sounds werden gerechnet, nicht geladen — also pruefen, dass wirklich
## Audiodaten herauskommen und nicht ein leerer Puffer.
func _test_audio_generation() -> void:
	_section("Synthetische Sounds")

	var shot := WeaponAudio.make_gunshot(0.6)
	_check(shot != null, "Schussgeraeusch wird erzeugt")
	_check(shot != null and shot.data.size() > 1000, "enthaelt Audiodaten (%d Bytes)" % (shot.data.size() if shot else 0))
	_check(shot != null and shot.mix_rate == WeaponAudio.SAMPLE_RATE, "korrekte Abtastrate")

	_check(_peak_of(shot) > 3000, "Signal ist hoerbar laut (Spitze %d)" % _peak_of(shot))
	_check(WeaponAudio.make_dry_fire() != null, "Leerschuss-Klick wird erzeugt")

	# Der Leerschuss darf nicht lauter sein als der Schuss selbst.
	_check(_peak_of(WeaponAudio.make_dry_fire()) < _peak_of(shot),
		"Leerschuss ist leiser als der Schuss")

	# Der Anfang muss hart einsetzen — ein Schuss ohne Transient klingt
	# nach Zischen statt nach Waffe.
	var attack := _peak_in_range(shot, 0, 400)
	var later := _peak_in_range(shot, 8000, 12000)
	_check(attack > later, "harter Anschlag am Anfang (%d vs %d spaeter)" % [attack, later])

	# Grosse Kaliber muessen laenger nachklingen.
	var quiet := WeaponAudio.make_gunshot(0.3)
	var loud := WeaponAudio.make_gunshot(1.0)
	_check(loud.data.size() > quiet.data.size(),
		"grosses Kaliber klingt laenger nach (%d vs %d Bytes)" % [loud.data.size(), quiet.data.size()])

	# Grosse Waffen muessen wuchtiger klingen als kleine.
	var pistol := ItemRegistry.get_item(&"weapon_pistol_g17") as WeaponData
	var sniper := ItemRegistry.get_item(&"weapon_sniper_axmc") as WeaponData
	if pistol != null and sniper != null:
		var p1 := WeaponAudio.get_power_for_weapon(pistol)
		var p2 := WeaponAudio.get_power_for_weapon(sniper)
		_check(p2 > p1, "AXMC klingt wuchtiger als G17 (%.2f vs %.2f)" % [p2, p1])

		# Der Zwischenspeicher muss pro Waffe unterscheiden, sonst klingen
		# alle Waffen gleich.
		WeaponAudio.clear_cache()
		var s1 := WeaponAudio.get_gunshot(pistol)
		var s2 := WeaponAudio.get_gunshot(sniper)
		_check(s1 != s2, "jede Waffe bekommt ihren eigenen Sound")
		_check(WeaponAudio.get_gunshot(pistol) == s1, "gleicher Waffe wird der Sound wiederverwendet")


func _peak_of(stream: AudioStreamWAV) -> int:
	if stream == null:
		return 0
	return _peak_in_range(stream, 0, stream.data.size() / 2)


func _peak_in_range(stream: AudioStreamWAV, first: int, last: int) -> int:
	if stream == null:
		return 0
	var peak := 0
	var frames := stream.data.size() / 2
	for f in range(maxi(0, first), mini(last, frames)):
		var value := stream.data[f * 2] | (stream.data[f * 2 + 1] << 8)
		if value > 32767:
			value -= 65536
		peak = maxi(peak, absi(value))
	return peak


func _test_effects_spawn() -> void:
	_section("Effekte")

	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame

	var impact := ImpactEffect.spawn(holder, Vector3(1, 2, 3), Vector3.UP, ImpactEffect.Kind.FLESH)
	_check(impact != null, "Einschlag wird erzeugt")
	_check(impact != null and impact.global_position.is_equal_approx(Vector3(1, 2, 3)),
		"Einschlag sitzt an der Trefferstelle")
	_check(impact != null and impact.get_child_count() > 0, "Einschlag hat Partikel")

	var flash := MuzzleFlash.spawn(holder, Transform3D(Basis(), Vector3(0, 1, 0)), 1.2)
	_check(flash != null, "Muendungsfeuer wird erzeugt")
	_check(flash != null and flash.get_child_count() > 0, "Muendungsfeuer hat Licht und Partikel")

	holder.free()


## Der eigentliche Integrationstest: Level aufbauen, abdruecken, nachsehen.
func _test_firing_in_level() -> void:
	_section("Schuss im echten Level")

	var packed: PackedScene = load("res://scenes/levels/testgelaende.tscn")
	if packed == null:
		_check(false, "Testgelaende laedt")
		_finish()
		return

	var level: Node = packed.instantiate()
	root.add_child(level)
	# Ein Frame, damit _ready() und @onready im ganzen Baum durchlaufen.
	await process_frame
	_check(true, "Testgelaende laedt und startet")

	var player := level.get_node_or_null("Player") as PlayerController
	_check(player != null, "Spieler gefunden")
	if player == null:
		_finish()
		return

	var weapon := player.weapon
	_check(weapon != null, "Waffe gefunden")
	if weapon == null:
		_finish()
		return

	_check(weapon.data != null, "Waffendaten geladen: %s" % (weapon.data.display_name if weapon.data else "-"))

	# Die Waffe kommt jetzt leer aus setup() und wird aus dem Inventar
	# geladen. Fuer diesen Test genuegt das Auffuellen ohne Verbrauch.
	weapon.fill_magazine()
	_check(weapon.rounds_in_magazine > 0, "Magazin ist gefuellt (%d)" % weapon.rounds_in_magazine)

	var before := weapon.rounds_in_magazine
	var projectiles_before := _count_projectiles(level)

	weapon._shoot()

	_check(weapon.rounds_in_magazine == before - 1,
		"Schuss verbraucht genau eine Patrone (%d -> %d)" % [before, weapon.rounds_in_magazine])

	var projectiles_after := _count_projectiles(level)
	_check(projectiles_after > projectiles_before,
		"Geschoss wurde erzeugt (%d -> %d)" % [projectiles_before, projectiles_after])

	# Die Patrone im Lauf zaehlt getrennt vom Magazin: Ein leeres Magazin
	# heisst nicht, dass die Waffe leer ist — ein Schuss steckt noch drin.
	weapon.rounds_in_magazine = 0
	_check(weapon.round_chambered, "nach dem Schuss steckt wieder eine Patrone im Lauf")
	var fired_last := weapon._shoot()
	_check(fired_last, "die Patrone im Lauf laesst sich noch verschiessen")

	# Erst jetzt ist die Waffe wirklich leer.
	var fired_empty := weapon._shoot()
	_check(not fired_empty, "leere Waffe schiesst nicht")
	_check(weapon.rounds_in_magazine == 0, "Munition geht nicht ins Minus")

	weapon.fill_magazine()
	_check(weapon.rounds_in_magazine == weapon.data.magazine_size, "Auffuellen fuellt das Magazin")

	# Schrot muss mehrere Geschosse gleichzeitig erzeugen.
	# NICHT auf Frames warten: add_child wirkt sofort, aber schon nach einem
	# einzigen Physikschritt koennen einzelne Schrotkoerner eingeschlagen und
	# sich selbst entfernt haben. Der Test wurde dadurch zufaellig rot.
	weapon.setup(&"weapon_shotgun_m870", &"ammo_12x70_buckshot")
	weapon.fill_magazine()
	var before_buck := _count_projectiles(level)
	weapon._shoot()
	var spawned := _count_projectiles(level) - before_buck
	_check(spawned == 8, "Buckshot erzeugt genau 8 Projektile (erzeugt: %d)" % spawned)

	level.free()
	_finish()


func _count_projectiles(from: Node) -> int:
	var count := 0
	for child in from.get_children():
		if child is Projectile:
			count += 1
	return count


## Echte Aufnahmen muessen auch wirklich genommen werden.
##
## Die Synthese ist der Notbehelf. Liegt eine Datei da und das Spiel spielt
## trotzdem das erzeugte Rauschen, faellt das niemandem auf - es klingt ja
## nach irgendetwas. Deshalb wird hier geprueft, dass die Datei gewinnt.
func _test_real_recordings() -> void:
	_section("Echte Aufnahmen")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	var loud := WeaponAudio.get_gunshot(ar15)
	_check(loud != null and loud.resource_path.ends_with("weapon_rifle_ar15.wav"),
		"AR-15 nimmt die echte Aufnahme (%s)" % (loud.resource_path if loud else "nichts"))

	# Mit Schalldaempfer muss eine ANDERE Datei kommen, nicht dieselbe leiser.
	# Ein gedaempfter Schuss ist ein anderer Klang, kein leiserer Knall.
	var build := WeaponBuild.new()
	build.set_attachment(AttachmentData.Slot.MUZZLE, &"ar15_muzzle_suppressor")
	var suppressed := WeaponBuild.apply(ar15, build)
	_check(suppressed.loudness_multiplier < WeaponAudio.SUPPRESSED_BELOW,
		"der Daempfer drueckt die Lautstaerke unter die Grenze (%.2f)"
			% suppressed.loudness_multiplier)

	var quiet := WeaponAudio.get_gunshot(suppressed)
	_check(quiet != null and quiet != loud,
		"gedaempft klingt aus einer eigenen Datei (%s)"
			% (quiet.resource_path if quiet else "nichts"))

	# Waffen ohne Aufnahme duerfen nicht stumm werden.
	var glock := ItemRegistry.get_item(&"weapon_pistol_g17") as WeaponData
	_check(WeaponAudio.get_gunshot(glock) != null,
		"Waffen ohne Aufnahme fallen auf die Synthese zurueck")

	# Ein fehlendes Nachladegeraeusch muss folgenlos bleiben.
	_check(WeaponAudio.get_sound(ar15, "gibt_es_nicht") == null,
		"ein unbekanntes Geraeusch liefert null statt zu knallen")
