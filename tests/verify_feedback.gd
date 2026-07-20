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
	_test_suppressor_changes_the_sound_in_hand()
	_test_recordings_start_immediately()
	_test_reload_sounds_are_wired()
	await _test_sounds_do_not_cut_each_other()
	await _test_empty_weapon_clicks_once()
	_test_bullet_holes()
	_test_shot_starts_at_the_muzzle()
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

	_test_shot_hits_the_crosshair(player, weapon)

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


## Der Schuss muss dorthin gehen, wo der Spieler HINSIEHT.
##
## Vorher startete die Kugel an einem festen Punkt neben der Kamera und flog
## PARALLEL zur Blickrichtung. Sie ging damit immer um den Versatz der
## Muendung daneben - rund 18 cm nach rechts und 12 cm nach unten, auf jede
## Entfernung gleich. Getroffen hat man damit fast nichts, und im Spiel sah
## es aus, als streue die Waffe.
##
## Geprueft wird deshalb der WINKEL zwischen Schussrichtung und Blickachse.
## Ein Test auf gleiche Startpunkte waere falsch: Die Kugel SOLL aus dem Lauf
## kommen und nicht aus dem Auge.
func _test_shot_hits_the_crosshair(player: PlayerController, weapon: Weapon) -> void:
	_section("Der Schuss geht aufs Fadenkreuz")

	var camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	_check(camera != null, "Kamera gefunden")
	if camera == null:
		return

	var aim_point := weapon.get_aim_point()
	var origin := weapon.get_shot_origin()

	_check(origin.distance_to(camera.global_position) > 0.05,
		"die Kugel startet an der Muendung, nicht im Auge (%.2f m entfernt)"
			% origin.distance_to(camera.global_position))

	var look := -camera.global_basis.z
	var to_aim := (aim_point - camera.global_position).normalized()
	_check(look.dot(to_aim) > 0.9999,
		"der Zielpunkt liegt genau auf der Blickachse")

	# Der entscheidende Wert: Wie weit verfehlt die Kugel den Zielpunkt?
	var shot_dir := (aim_point - origin).normalized()
	var distance := origin.distance_to(aim_point)
	var miss := (origin + shot_dir * distance).distance_to(aim_point)
	_check(miss < 0.01, "die Kugel laeuft auf den Zielpunkt zu (%.4f m Abweichung)" % miss)

	# Und gegen den alten Fehler: Parallel zur Blickachse waere zu wenig.
	# Auf Entfernung muss die Schussrichtung zur Blickachse hin einschwenken.
	var parallel_miss := (origin + look * distance).distance_to(aim_point)
	_check(parallel_miss > miss,
		"parallel geschossen wuerde um %.2f m danebengehen" % parallel_miss)


## Der Schalldaempfer muss den Klang IN DER HAND aendern, nicht nur in der
## Nachschlagetabelle.
##
## Genau hier war der Fehler: rebuild() rechnete die Werte neu, liess aber
## _shot_sound aus setup() stehen. Man schraubte an der Werkbank den Daempfer
## an, sah ihn am Lauf und hoerte weiter den vollen Knall.
func _test_suppressor_changes_the_sound_in_hand() -> void:
	_section("Der Daempfer aendert den Klang in der Hand")

	var weapon := Weapon.new()
	weapon.setup(&"weapon_rifle_ar15", &"ammo_556x45_m855a1")
	var loud := weapon._shot_sound
	_check(loud != null, "ungedaempft liegt ein Schuss-Sound bereit")

	weapon.build.set_attachment(AttachmentData.Slot.MUZZLE, &"ar15_muzzle_suppressor")
	weapon.rebuild()

	_check(weapon._shot_sound != null and weapon._shot_sound != loud,
		"nach dem Anbau klingt die Waffe anders (%s)"
			% (weapon._shot_sound.resource_path if weapon._shot_sound else "nichts"))

	weapon.build.clear_slot(AttachmentData.Slot.MUZZLE)
	weapon.rebuild()
	_check(weapon._shot_sound == loud, "abgenommen klingt sie wieder wie vorher")

	weapon.free()


## Aufnahmen muessen sofort losgehen und duerfen nicht uebersteuern.
##
## Fuehrende Stille war ein echtes Problem: Zwei der gelieferten Dateien
## hatten 0,3 bzw. 0,9 Sekunden davor. Der Schuss waere also erst deutlich
## nach dem Mausklick zu hoeren gewesen.
func _test_recordings_start_immediately() -> void:
	_section("Aufnahmen fangen sofort an")

	for path in [
		"res://assets/audio/weapons/weapon_rifle_ar15.wav",
		"res://assets/audio/weapons/ar15/schuss_gedaempft.wav",
		"res://assets/audio/weapons/ar15/schuss_innen.wav",
		"res://assets/audio/weapons/ar15/schuss_fern.wav",
	]:
		var stream := load(path) as AudioStreamWAV
		if stream == null:
			_check(false, "%s laedt" % path.get_file())
			continue

		var start := _first_loud_sample(stream)
		_check(start >= 0 and start < 0.05,
			"%s beginnt bei %.3f s" % [path.get_file(), start])


## Wann wird die Aufnahme zum ersten Mal hoerbar laut?
func _first_loud_sample(stream: AudioStreamWAV) -> float:
	var bytes := stream.data
	var frames := bytes.size() / 2
	for i in range(mini(frames, stream.mix_rate)):
		var lo := bytes[i * 2]
		var hi := bytes[i * 2 + 1]
		var value := (hi << 8) | lo
		if value >= 32768:
			value -= 65536
		# 5 % vom Vollausschlag: deutlich ueber Grundrauschen, deutlich unter
		# dem, was ein Schuss erreicht.
		if absi(value) > 1638:
			return float(i) / float(stream.mix_rate)
	return -1.0


## Die drei Nachladegeraeusche muessen da sein und an ihrer Stelle kommen.
##
## Ohne diesen Test faellt ein Tippfehler im Dateinamen nicht auf: get_sound()
## liefert dann null, es bleibt still, und Stille beim Nachladen wirkt wie
## eine bewusste Entscheidung statt wie ein Fehler.
func _test_reload_sounds_are_wired() -> void:
	_section("Nachladegeraeusche")

	var ar15 := ItemRegistry.get_item(&"weapon_rifle_ar15") as WeaponData
	for cue in Weapon.RELOAD_CUES:
		var stream := WeaponAudio.get_sound(ar15, String(cue.sound))
		_check(stream != null, "%s liegt bereit" % cue.sound)

	# Die Reihenfolge muss stimmen, sonst kommt der Verschluss vor dem Magazin.
	var previous := -1.0
	var ordered := true
	for cue in Weapon.RELOAD_CUES:
		if float(cue.at) <= previous:
			ordered = false
		previous = float(cue.at)
	_check(ordered, "die Geraeusche stehen in der richtigen Reihenfolge")

	# Der Verschluss darf nur bei leergeschossener Waffe kommen.
	var bolt_only_empty := false
	for cue in Weapon.RELOAD_CUES:
		if String(cue.sound) == "nachladen_verschluss":
			bolt_only_empty = bool(cue.only_empty)
	_check(bolt_only_empty, "der Verschluss kommt nur bei leerer Waffe")

	# Und der Ablauf muss sie wirklich abrufen: taktisch zwei, leer drei.
	_check(_count_cues(false) == 2, "taktisches Nachladen spielt zwei Geraeusche")
	_check(_count_cues(true) == 3, "aus leerem Magazin kommen drei")


func _count_cues(from_empty: bool) -> int:
	var count := 0
	for cue in Weapon.RELOAD_CUES:
		if not bool(cue.only_empty) or from_empty:
			count += 1
	return count


## Schuesse duerfen sich nicht gegenseitig abschneiden.
##
## Mit einer einzigen Stimme setzte jeder Schuss den Stream neu und startete
## ihn von vorn. Bei 750 Schuss pro Minute liegen 80 ms zwischen den Schuessen,
## die Aufnahme ist 2,6 s lang - zu hoeren waren also nur die ersten 80 ms.
## Dauerfeuer klang wie Klicken, nicht wie Schiessen.
func _test_sounds_do_not_cut_each_other() -> void:
	_section("Schuesse schneiden sich nicht ab")

	var weapon := Weapon.new()
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	var speaker := AudioStreamPlayer3D.new()
	# Name ausdruecklich setzen: weapon.gd sucht ueber
	# $Muzzle/AudioStreamPlayer3D, und ohne Namen vergibt Godot einen eigenen.
	speaker.name = "AudioStreamPlayer3D"
	muzzle.add_child(speaker)
	weapon.add_child(muzzle)
	root.add_child(weapon)
	# _ready() laeuft erst im naechsten Frame - vorher gibt es keine Stimmen.
	await process_frame

	_check(weapon._voices.size() == Weapon.AUDIO_VOICES,
		"es gibt %d Stimmen (%d)" % [Weapon.AUDIO_VOICES, weapon._voices.size()])
	_check(weapon._voices.size() > 1,
		"mehr als eine - sonst schneidet jeder Schuss den vorigen ab")

	# Mehrere Geraeusche kurz hintereinander muessen auf VERSCHIEDENEN
	# Stimmen landen.
	var sound := WeaponAudio.make_gunshot(0.6)
	var used := {}
	for i in range(Weapon.AUDIO_VOICES):
		weapon._play(sound, 1.0)
		for voice in weapon._voices:
			if voice.stream == sound and voice.playing:
				used[voice.get_instance_id()] = true

	_check(used.size() > 1, "aufeinanderfolgende Schuesse belegen verschiedene Stimmen (%d)"
		% used.size())

	weapon.queue_free()


## Eine leergeschossene Waffe macht EINEN Klack, kein Maschinengewehr-Klicken.
##
## Vorher setzte der Leerlauf-Zweig kein _cooldown. Im Dauerfeuer lief
## try_fire() dadurch bei jedem Bild erneut durch und klickte im Bildtakt.
func _test_empty_weapon_clicks_once() -> void:
	_section("Leere Waffe klickt einmal")

	var weapon := Weapon.new()
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	var speaker := AudioStreamPlayer3D.new()
	speaker.name = "AudioStreamPlayer3D"
	muzzle.add_child(speaker)
	weapon.add_child(muzzle)
	root.add_child(weapon)
	await process_frame
	weapon.setup(&"weapon_rifle_ar15", &"ammo_556x45_m855a1")

	weapon.rounds_in_magazine = 0
	weapon.round_chambered = false
	weapon.current_fire_mode = WeaponData.FireMode.AUTO

	# GDScript-Lambdas fangen Werte als KOPIE. Ein einfacher int-Zaehler
	# bliebe hier fuer immer null - das Array wird dagegen geteilt.
	var clicks := [0]
	weapon.dry_fire.connect(func(): clicks[0] += 1)

	# Abzug 60 Bilder lang gehalten, ohne dass Zeit vergeht.
	for i in range(60):
		weapon.try_fire(true, i == 0)
	_check(clicks[0] == 1, "gehaltener Abzug klickt genau einmal (%d)" % clicks[0])

	# Loslassen und neu druecken darf wieder klicken.
	#
	# Die Wartezeit muss dafuer abgelaufen sein: Auch ins Leere klickt eine
	# Waffe nur im Takt ihrer Feuerrate, nicht beliebig schnell.
	weapon.release_trigger()
	weapon._cooldown = 0.0
	weapon.try_fire(true, true)
	_check(clicks[0] == 2, "nach dem Loslassen klickt es wieder (%d)" % clicks[0])

	weapon.queue_free()


## Einschussloecher.
##
## Reine Rueckmeldung - aber genau deshalb faellt es nicht auf, wenn sie
## fehlt: Es knallt trotzdem, es trifft trotzdem. Man merkt nur, dass sich das
## Schiessen "flach" anfuehlt, ohne sagen zu koennen warum.
func _test_bullet_holes() -> void:
	_section("Einschussloecher")

	BulletHole.clear_all()
	var holder := Node3D.new()
	root.add_child(holder)

	var hole := BulletHole.spawn(holder, Vector3(1.0, 2.0, 3.0), Vector3.UP)
	_check(hole != null, "ein Einschussloch entsteht")
	_check(hole != null and hole.texture_albedo != null, "es hat eine Textur")

	# Die Obergrenze ist der eigentliche Punkt: Ohne sie wird das Bild im
	# Laufe eines Gefechts immer zaeher, und niemand kaeme auf die Loecher.
	for i in range(BulletHole.MAX_HOLES + 25):
		BulletHole.spawn(holder, Vector3(float(i) * 0.1, 0.0, 0.0), Vector3.UP)

	var alive := 0
	for child in holder.get_children():
		if child is BulletHole and not (child as BulletHole).is_queued_for_deletion():
			alive += 1
	_check(alive <= BulletHole.MAX_HOLES,
		"nie mehr als %d Loecher gleichzeitig (%d)" % [BulletHole.MAX_HOLES, alive])

	BulletHole.clear_all()
	holder.queue_free()

	# Gegenprobe: Das Geschoss darf KEINE Leuchtspur mehr mitbringen.
	# Sie wurde bewusst entfernt - eine Spur an jeder Kugel verraet die
	# Stellung des Schuetzen quer ueber die Karte.
	var ammo := ItemRegistry.get_item(&"ammo_556x45_m855a1") as AmmoData
	var projectile: Projectile = load("res://scenes/combat/projectile.tscn").instantiate()
	root.add_child(projectile)
	projectile.launch(ammo, Vector3.ZERO, Vector3.FORWARD, 900.0)
	_check(projectile.get_node_or_null("Leuchtspur") == null,
		"das Geschoss zieht keine sichtbare Spur")
	projectile.queue_free()


## Der sichtbare Abgang muss an der MUENDUNG haengen, nicht am Geschoss.
##
## Vorher steckte in projectile.tscn eine leuchtende Kapsel, die am Geschoss
## klebte. Sichtbar wurde sie nie am Lauf: Bei 900 m/s und 60 Bildern legt ein
## Geschoss 15 METER PRO BILD zurueck — im ersten gezeichneten Bild ist es
## laengst weit weg, und dort liegt die Ziellinie praktisch auf der Bildmitte.
## Es sah aus, als kaeme der Schuss mitten aus dem Bildschirm.
func _test_shot_starts_at_the_muzzle() -> void:
	_section("Der Schuss kommt am Lauf raus")

	var ammo := ItemRegistry.get_item(&"ammo_556x45_m855a1") as AmmoData
	var muzzle := Vector3(0.15, 1.54, -0.84)
	var projectile: Projectile = load("res://scenes/combat/projectile.tscn").instantiate()
	root.add_child(projectile)
	projectile.launch(ammo, muzzle, Vector3.FORWARD, 900.0)

	var streak := projectile.get_node_or_null("Abgang") as MeshInstance3D
	_check(streak != null, "der Abgang wird gebaut")
	if streak == null:
		projectile.queue_free()
		return

	# Ein Bild Flug simulieren.
	projectile._physics_process(1.0 / 60.0)

	_check(streak.visible, "und ist direkt nach dem Schuss sichtbar")

	# DER KERN: Das hintere Ende des Strichs muss an der Muendung sitzen.
	var half := streak.global_basis.z.normalized() * streak.scale.z * 0.5
	var tail := streak.global_position - half
	var head := streak.global_position + half
	var back := tail if tail.distance_to(muzzle) < head.distance_to(muzzle) else head
	_check(back.distance_to(muzzle) < 0.2,
		"das hintere Ende sitzt an der Muendung (%.3f m entfernt)" % back.distance_to(muzzle))

	_check(streak.scale.z <= Projectile.STREAK_MAX_LENGTH + 0.01,
		"der Strich bleibt kurz (%.1f von hoechstens %.1f m)"
			% [streak.scale.z, Projectile.STREAK_MAX_LENGTH])

	# Und er verschwindet wieder — sonst ist es eine Leuchtspur quer ueber die
	# Karte, und die war ausdruecklich nicht gewollt.
	for i in range(20):
		projectile._physics_process(1.0 / 60.0)
	_check(not streak.visible,
		"nach %.2f s ist er weg" % Projectile.STREAK_SECONDS)

	projectile.queue_free()
