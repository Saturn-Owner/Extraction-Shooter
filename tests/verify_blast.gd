## Prüft die Mündungsknall-Belastung.
##
##   godot --headless --path . --script res://tests/verify_blast.gd
##
## Der wichtigste Test hier ist _test_suppressor_protects(). Alles andere fällt
## beim Spielen auf — ein wirkungsloser Schalldämpfer nicht: Das Spiel wirkt
## dann einfach "hart" statt kaputt, und die Entscheidung "lohnt sich ein
## Dämpfer?" ist ohne erkennbaren Grund tot.
extends SceneTree

## Schussabstand der AR-15 bei 750 Schuss pro Minute.
const SHOT_INTERVAL := 60.0 / 750.0

var _failed := 0
var _passed := 0


func _initialize() -> void:
	ItemRegistry.ensure_loaded()
	print("=== Mündungsknall prüfen ===\n")

	_test_config_is_sane()
	_test_single_shot_does_nothing()
	_test_burst_crosses_threshold()
	_test_suppressor_protects()
	_test_only_the_suppressor_smokes()
	_test_semi_auto_stays_clean()
	_test_everything_returns_to_rest()
	_test_envelopes_have_different_memory()
	_test_never_leaves_range()
	_test_tinnitus_loops_without_clicking()
	_test_volume_follows_loudness()
	await _test_in_level()

	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


## Baut einen Belastungsknoten ohne Szenenbaum. Die Rechnung braucht keinen.
func _make() -> MuzzleBlast:
	var blast := MuzzleBlast.new()
	blast.config = load(MuzzleBlast.DEFAULT_CONFIG) as MuzzleBlastData
	return blast


func _weapon(id: StringName, attachment: StringName = &"") -> WeaponData:
	var base := ItemRegistry.get_item(id) as WeaponData
	if attachment == &"":
		return base
	var build := WeaponBuild.new()
	var part := ItemRegistry.get_item(attachment) as AttachmentData
	build.set_attachment(part.slot, attachment)
	return WeaponBuild.apply(base, build)


## Feuert eine Salve im Takt der Feuerrate und lässt die Zeit dabei laufen.
func _fire_burst(blast: MuzzleBlast, weapon: WeaponData, shots: int,
		interval: float = SHOT_INTERVAL) -> void:
	for i in range(shots):
		blast.add(weapon)
		blast._process(interval)


func _advance(blast: MuzzleBlast, seconds: float) -> void:
	# In kleinen Schritten, damit die Hüllkurven realistisch laufen.
	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < seconds:
		blast._process(step)
		elapsed += step


func _test_config_is_sane() -> void:
	_section("Abstimmungswerte")

	var config := load(MuzzleBlast.DEFAULT_CONFIG) as MuzzleBlastData
	_check(config != null, "muzzle_blast_default.tres lädt")
	if config == null:
		return

	var problems := config.validate()
	_check(problems.is_empty(), "Werte sind widerspruchsfrei%s"
		% ("" if problems.is_empty() else ": " + ", ".join(problems)))

	# Die Haltezeit muss über dem Schussabstand liegen, sonst erholt sich die
	# Waffe mitten in der eigenen Salve.
	_check(config.hold_seconds > SHOT_INTERVAL,
		"Haltezeit (%.2f s) liegt über dem Schussabstand (%.3f s)"
			% [config.hold_seconds, SHOT_INTERVAL])


## DIE KERNZUSAGE: Ein Einzelschuss bleibt folgenlos.
func _test_single_shot_does_nothing() -> void:
	_section("Ein Einzelschuss tut nichts")

	var blast := _make()
	blast.add(_weapon(&"weapon_rifle_ar15"))

	_check(blast.strain > 0.0, "die Belastung steigt überhaupt (%.3f)" % blast.strain)
	_check(is_zero_approx(blast.intensity()),
		"aber die Wirkung ist EXAKT null (%.6f)" % blast.intensity())

	# Auch drei Einzelschüsse mit einer Sekunde Pause bleiben folgenlos.
	for i in range(3):
		blast.add(_weapon(&"weapon_rifle_ar15"))
		_advance(blast, 1.0)
	_check(is_zero_approx(blast.intensity()),
		"drei bedächtige Einzelschüsse ebenfalls null (%.6f)" % blast.intensity())


func _test_burst_crosses_threshold() -> void:
	_section("Eine Salve schlägt durch")

	var ar15 := _weapon(&"weapon_rifle_ar15")

	# Zwei Schüsse noch nicht, mehrere schon. BEIDE Richtungen prüfen — sonst
	# hält der Test auch eine kaputt hohe Steigerung für richtig.
	var early := _make()
	_fire_burst(early, ar15, 2)
	_check(is_zero_approx(early.intensity()),
		"zwei Schuss reissen die Schwelle noch nicht (%.3f Belastung)" % early.strain)

	var burst := _make()
	_fire_burst(burst, ar15, 6)
	_check(burst.intensity() > 0.0,
		"sechs Schuss reissen sie (%.3f Belastung, Wirkung %.2f)"
			% [burst.strain, burst.intensity()])

	# Ein volles Magazin muss deutlich im Anschlag liegen.
	var full := _make()
	_fire_burst(full, ar15, 30)
	_check(full.intensity() > 0.9,
		"ein Magazin am Stück wirkt fast voll (%.2f)" % full.intensity())
	_check(full.strain <= 1.0, "die Belastung geht nie über eins (%.3f)" % full.strain)


## DER WICHTIGSTE TEST. Siehe Klassenkopf.
func _test_suppressor_protects() -> void:
	_section("Der Schalldämpfer schützt")

	var suppressed := _weapon(&"weapon_rifle_ar15", &"ar15_muzzle_suppressor")
	_check(suppressed.loudness_multiplier < 0.6,
		"die bestückte Waffe ist wirklich leise (%.2f)" % suppressed.loudness_multiplier)

	var blast := _make()
	_fire_burst(blast, suppressed, 30)
	_check(is_zero_approx(blast.intensity()),
		"ein volles Magazin gedämpft bleibt folgenlos (%.3f Belastung, Wirkung %.4f)"
			% [blast.strain, blast.intensity()])

	# Verglichen wird der ZUWACHS JE SCHUSS, nicht die aufgelaufene Belastung.
	# Die läuft ungedämpft in den Deckel bei eins, und dann misst der Vergleich
	# nur noch den Deckel statt den Unterschied.
	var loud_rise := blast.rise_for(_weapon(&"weapon_rifle_ar15"))
	var quiet_rise := blast.rise_for(suppressed)
	_check(loud_rise > quiet_rise * 8.0,
		"ein lauter Schuss belastet mehr als achtmal so stark (%.4f gegen %.4f)"
			% [loud_rise, quiet_rise])


## Halbautomatisches Feuern soll straffrei bleiben — kurze Feuerstösse werden
## belohnt, genau wie es die Rückstossrampe schon tut.
func _test_semi_auto_stays_clean() -> void:
	_section("Einzelfeuer bleibt straffrei")

	var ar15 := _weapon(&"weapon_rifle_ar15")

	# Gezieltes Einzelfeuer: gut ein Schuss pro Sekunde, zwanzig Stück lang.
	var aimed := _make()
	var worst := 0.0
	for i in range(20):
		aimed.add(ar15)
		_advance(aimed, 0.9)
		worst = maxf(worst, aimed.intensity())
	_check(is_zero_approx(worst),
		"zwanzig gezielte Einzelschüsse lösen nichts aus (Spitze %.4f)" % worst)

	# GEGENPROBE, und die ist genauso wichtig: Hektisches Klicken IST laut und
	# soll sehr wohl bestrafen. Ohne diese Zusicherung könnte man die Erholung
	# beliebig hochdrehen und "Einzelfeuer bleibt sauber" bliebe grün, während
	# der Effekt insgesamt tot wäre.
	var spam := _make()
	for i in range(20):
		spam.add(ar15)
		_advance(spam, 1.0 / 4.0)
	_check(spam.intensity() > 0.5,
		"hektisches Klicken bestraft dagegen sehr wohl (%.2f)" % spam.intensity())


func _test_everything_returns_to_rest() -> void:
	_section("Alles kommt zur Ruhe")

	var blast := _make()
	_fire_burst(blast, _weapon(&"weapon_rifle_ar15"), 30)
	_check(blast.intensity() > 0.5, "erst mal ordentlich belastet (%.2f)" % blast.intensity())

	# Grosszügig warten: Der Tinnitus hat mit 12 s das längste Gedächtnis.
	_advance(blast, 25.0)

	# Ein Effekt, der bei 0,02 hängenbleibt, ist unsichtbar und trotzdem falsch.
	_check(is_zero_approx(blast.strain), "Belastung ist exakt null (%.6f)" % blast.strain)
	_check(is_zero_approx(blast.flash), "Blendung ist exakt null (%.6f)" % blast.flash)
	_check(is_zero_approx(blast.smoke), "Rauch ist exakt null (%.6f)" % blast.smoke)
	_check(is_zero_approx(blast.shake), "Wackeln ist exakt null (%.6f)" % blast.shake)
	_check(is_zero_approx(blast.smoke_strain),
		"auch die Rauchquelle ist exakt null (%.6f)" % blast.smoke_strain)
	_check(is_zero_approx(blast.tinnitus), "Pfeifen ist exakt null (%.6f)" % blast.tinnitus)


## Die vier teilen sich eine Quelle, aber nicht ihr Gedächtnis. Ohne diesen
## Test können sie unbemerkt wieder verschmelzen — und dann sieht die Erholung
## aus, als hätte jemand einen Regler zurückgedreht.
func _test_envelopes_have_different_memory() -> void:
	_section("Vier verschiedene Gedächtnisse")

	var blast := _make()
	_fire_burst(blast, _weapon(&"weapon_rifle_ar15"), 30)

	# Nach 0,8 s: Das Wackeln (0,5 s Gedächtnis) ist durch, die Blendung
	# (1,2 s) noch nicht. Später gemessen wären beide bei null, und der
	# Vergleich würde nichts mehr belegen.
	_advance(blast, 0.8)
	_check(is_zero_approx(blast.shake),
		"nach 0,8 s ist das Wackeln vorbei (%.4f)" % blast.shake)
	_check(blast.flash > 0.0,
		"die Blendung ist da noch da (%.3f)" % blast.flash)

	_advance(blast, 1.2)
	_check(blast.tinnitus > blast.flash,
		"das Pfeifen hält länger als die Blendung (%.3f > %.3f)" % [blast.tinnitus, blast.flash])

	# Der Rauch hängt an einer eigenen Quelle und braucht deshalb eine eigene
	# Waffe zum Vergleich — eine gedämpfte.
	var smoky := _make()
	_fire_burst(smoky, _weapon(&"weapon_rifle_ar15", &"ar15_muzzle_suppressor"), 30)
	_advance(smoky, 2.0)
	_check(smoky.smoke > blast.flash,
		"der Rauch hält länger als die Blendung (%.3f > %.3f)" % [smoky.smoke, blast.flash])

	# Und nach fünf Sekunden pfeift es als einziges noch.
	_advance(blast, 3.0)
	_check(is_zero_approx(blast.flash) and is_zero_approx(blast.smoke),
		"nach fünf Sekunden sind Blendung und Rauch weg")
	_check(blast.tinnitus > 0.0, "das Pfeifen ist noch da (%.3f)" % blast.tinnitus)


func _test_never_leaves_range() -> void:
	_section("Werte bleiben im Rahmen")

	var blast := _make()
	var ok := true

	# Wild durcheinander feuern und warten, dabei jeden Wert im Auge behalten.
	for round_index in range(40):
		blast.add(_weapon(&"weapon_rifle_ar15"))
		blast.add(_weapon(&"weapon_shotgun_m870"))
		_advance(blast, 0.05 + float(round_index % 5) * 0.1)
		for value in [blast.strain, blast.flash, blast.smoke, blast.shake, blast.tinnitus]:
			if value < 0.0 or value > 1.0:
				ok = false

	_check(ok, "keine Grösse verlässt jemals den Bereich 0 bis 1")

	blast.reset()
	_check(is_zero_approx(blast.strain) and is_zero_approx(blast.tinnitus),
		"reset() räumt alles ab")


## Im echten Spielerbaum: Verdrahtung und Kanaltrennung.
##
## DIE WICHTIGSTE ZUSICHERUNG HIER ist, dass das Wackeln den Rückstoss nicht
## anfasst. Beide bewegen die Sicht, aber der Rückstoss schreibt die ECHTE
## Blickrichtung (_camera_pivot plus _pitch), das Wackeln nur die Kamera
## darunter. Schriebe das Wackeln versehentlich auf denselben Knoten, wanderte
## die Blickrichtung mit jedem Magazin ein Stück weg — und das merkt man im
## Spiel erst nach Minuten, wenn man plötzlich in den Himmel schaut.
## Liest einen 16-Bit-Wert aus den Rohdaten, -1 bis 1.
func _sample_at(data: PackedByteArray, index: int) -> float:
	var low := data[index * 2]
	var high := data[index * 2 + 1]
	var value := low | (high << 8)
	if value >= 32768:
		value -= 65536
	return float(value) / 32767.0


## DIE SCHLEIFE DARF NICHT KNACKEN.
##
## Ein Sinus, der an der Nahtstelle nicht gerade durch null geht, springt beim
## Zurueckspringen — und das hoert man als Knacken. Bei einer Sekunde
## Schleifenlaenge knackt es einmal pro Sekunde, dauerhaft, solange es pfeift.
##
## Das faellt beim Spielen als "das Pfeifen klingt komisch" auf, und die
## Ursache sucht man dann in der Lautstaerke oder im Filter statt in der
## Pufferlaenge. Deshalb steht es hier fest.
func _test_tinnitus_loops_without_clicking() -> void:
	_section("Tinnitus")

	var stream := GameAudio.make_tinnitus(4500.0, 4508.0)
	_check(stream != null, "der Klang wird erzeugt")
	if stream == null:
		return

	_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "er ist als Schleife markiert")
	_check(stream.loop_end == int(GameAudio.SAMPLE_RATE * GameAudio.TINNITUS_SECONDS),
		"und die Schleife umfasst den ganzen Puffer (%d)" % stream.loop_end)

	var data := stream.data
	var count := data.size() / 2
	_check(count > 0, "es sind Daten drin (%d Werte)" % count)
	if count < 2:
		return

	# Der groesste Schritt INNERHALB des Puffers ist der Massstab. Der Sprung
	# an der Naht darf nicht groesser sein — sonst ist er hoerbar.
	var biggest_step := 0.0
	for i in range(count - 1):
		biggest_step = maxf(biggest_step, absf(_sample_at(data, i + 1) - _sample_at(data, i)))

	var seam := absf(_sample_at(data, 0) - _sample_at(data, count - 1))
	_check(seam <= biggest_step * 1.5,
		"der Sprung an der Naht ist nicht groesser als im Puffer (%.5f gegen %.5f)"
			% [seam, biggest_step])

	# Und mit krummen Frequenzen ebenso — die stehen in einer .tres und
	# koennen dort auf beliebige Kommastellen gesetzt werden.
	var odd := GameAudio.make_tinnitus(4507.3, 4513.9)
	var odd_data := odd.data
	var odd_count := odd_data.size() / 2
	var odd_step := 0.0
	for i in range(odd_count - 1):
		odd_step = maxf(odd_step, absf(_sample_at(odd_data, i + 1) - _sample_at(odd_data, i)))
	var odd_seam := absf(_sample_at(odd_data, 0) - _sample_at(odd_data, odd_count - 1))
	_check(odd_seam <= odd_step * 1.5,
		"auch bei krummen Frequenzen (%.5f gegen %.5f)" % [odd_seam, odd_step])

	# ZWEI TOENE, NICHT EINER. Ein reiner Sinus klingt nach Messgeraet. Die
	# Schwebung erkennt man daran, dass die Huellkurve pulsiert: Es gibt
	# Stellen mit fast voller Auslenkung und Stellen nahe null.
	var loudest := 0.0
	var quietest := 1.0
	var window := int(GameAudio.SAMPLE_RATE * 0.01)
	var at := 0
	while at + window < count:
		var peak := 0.0
		for i in range(at, at + window):
			peak = maxf(peak, absf(_sample_at(data, i)))
		loudest = maxf(loudest, peak)
		quietest = minf(quietest, peak)
		at += window

	_check(loudest > 0.8, "die Schwebung erreicht volle Staerke (%.2f)" % loudest)
	_check(quietest < 0.3,
		"und faellt zwischendurch fast auf null — das ist die Schwebung (%.2f)" % quietest)


## Ein Schalldämpfer muss die Waffe HÖRBAR leiser machen.
##
## ---------------------------------------------------------------------------
## DAS HAT VORHER GEFEHLT, UND ZWAR VOLLSTÄNDIG
##
## `loudness_multiplier` steuerte die Sample-Auswahl, die Synthese und die
## Knall-Belastung — aber nie die Abspiellautstärke. Ein Dämpfer machte damit
## bei Glock, AKM und M870 gar nichts leiser. Aufgefallen ist das nie, weil
## die AR-15 eine eigene gedämpfte Aufnahme hat und deshalb anders klang —
## der einzige Fall, in dem es zufällig funktionierte.
func _test_volume_follows_loudness() -> void:
	_section("Lautstärke")

	var loud := _weapon(&"weapon_rifle_ar15")
	var quiet := _weapon(&"weapon_rifle_ar15", &"ar15_muzzle_suppressor")

	_check(quiet.loudness_multiplier < loud.loudness_multiplier,
		"der Dämpfer senkt loudness_multiplier (%.2f gegen %.2f)"
			% [quiet.loudness_multiplier, loud.loudness_multiplier])

	var loud_db := WeaponAudio.volume_db_for(loud)
	var quiet_db := WeaponAudio.volume_db_for(quiet)

	_check(is_zero_approx(loud_db), "ungedämpft läuft auf voller Lautstärke (%.1f dB)" % loud_db)
	_check(quiet_db < loud_db, "gedämpft ist leiser (%.1f dB)" % quiet_db)

	# DIE GRÖSSE DES UNTERSCHIEDS IST DER PUNKT, nicht sein Vorhandensein.
	# Ein halbes Dezibel wäre technisch "leiser" und im Spiel nicht zu
	# bemerken — die Prüfung darüber bliebe trotzdem grün.
	_check(quiet_db < -6.0,
		"und zwar deutlich: mindestens 6 dB (%.1f dB)" % quiet_db)

	# Nach unten begrenzt, sonst könnte eine .tres die Waffe stummschalten.
	var silent := WeaponData.new()
	silent.loudness_multiplier = 0.0
	_check(WeaponAudio.volume_db_for(silent) > -30.0,
		"selbst bei loudness_multiplier = 0 bleibt sie hörbar (%.1f dB)"
			% WeaponAudio.volume_db_for(silent))

	_check(is_zero_approx(WeaponAudio.volume_db_for(null)),
		"ohne Waffe kommt 0 dB heraus statt eines Fehlers")


func _test_in_level() -> void:
	_section("Im Spielerbaum")

	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var player := scene.instantiate() as PlayerController
	root.add_child(player)
	await process_frame

	var blast := player.get_node_or_null("CameraPivot/MuzzleBlast") as MuzzleBlast
	_check(blast != null, "der Belastungsknoten hängt am Kamerapivot")
	if blast == null:
		player.queue_free()
		return

	var camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	_check(camera != null and pivot != null, "Kamera und Pivot gefunden")
	if camera == null or pivot == null:
		player.queue_free()
		return

	# --- Kanaltrennung ---
	var pivot_before := pivot.rotation_degrees
	var pitch_before: float = player._pitch

	blast.strain = 1.0
	var moved := 0.0
	for i in range(60):
		# Belastung halten, sonst klingt das Wackeln waehrend der Messung ab
		# und die Kamera steht am Ende wieder gerade.
		blast.shake = 1.0
		blast._process(1.0 / 60.0)
		moved = maxf(moved, camera.rotation_degrees.length())

	_check(pivot.rotation_degrees.is_equal_approx(pivot_before),
		"eine Sekunde Wackeln lässt den Kamerapivot unberührt (%v)" % pivot.rotation_degrees)
	_check(is_equal_approx(player._pitch, pitch_before),
		"und die Blickrichtung ebenfalls (%.6f)" % player._pitch)
	_check(moved > 0.0, "die Kamera selbst hat sich aber bewegt (%.4f Grad)" % moved)

	# --- Rollen kostet keine Präzision ---
	# Der Zielstrahl läuft entlang -Z. Rollen dreht um genau diese Achse, die
	# Richtung darf sich dadurch nicht ändern.
	var forward_before := -camera.global_basis.z
	camera.rotation_degrees = Vector3(0.0, 0.0, 30.0)
	var forward_rolled := -camera.global_basis.z
	_check(forward_before.dot(forward_rolled) > 0.9999,
		"Rollen ändert die Zielrichtung nicht (%.6f)" % forward_before.dot(forward_rolled))

	# --- Ruhelage ---
	blast.reset()
	blast._process(1.0 / 60.0)
	_check(camera.rotation_degrees.is_zero_approx() and camera.position.is_zero_approx(),
		"ohne Belastung steht die Kamera exakt gerade (%v / %v)"
			% [camera.rotation_degrees, camera.position])

	# --- Die Grenzen halten, UND der Effekt kommt oben auch an ---
	#
	# Die untere Schranke ist die wichtigere von beiden. Vorher stand hier nur
	# "bleibt unter dem Höchstwert" — diese Prüfung besteht ein Effekt, der gar
	# nichts tut, mühelos. Genau das ist passiert: FastNoiseLite steht ab Werk
	# auf Frequenz 0,01, das Wackeln erreichte 0,035 statt 1,5 Grad, und der
	# Test war grün.
	blast.strain = 1.0
	blast.shake = 1.0
	var worst_pitch := 0.0
	var worst_roll := 0.0
	for i in range(240):
		blast._process(1.0 / 60.0)
		blast.shake = 1.0
		worst_pitch = maxf(worst_pitch, absf(camera.rotation_degrees.x))
		worst_roll = maxf(worst_roll, absf(camera.rotation_degrees.z))

	_check(worst_pitch <= blast.config.shake_pitch_deg + 0.001,
		"das Nicken bleibt unter dem Höchstwert (%.3f von %.3f Grad)"
			% [worst_pitch, blast.config.shake_pitch_deg])
	_check(worst_roll <= blast.config.shake_roll_deg + 0.001,
		"das Rollen bleibt unter dem Höchstwert (%.3f von %.3f Grad)"
			% [worst_roll, blast.config.shake_roll_deg])

	_check(worst_roll > blast.config.shake_roll_deg * 0.6,
		"und erreicht auch mindestens 60 %% davon (%.3f von %.3f Grad)"
			% [worst_roll, blast.config.shake_roll_deg])
	_check(worst_pitch > blast.config.shake_pitch_deg * 0.6,
		"dasselbe fürs Nicken (%.3f von %.3f Grad)"
			% [worst_pitch, blast.config.shake_pitch_deg])

	# --- Die Waffe muss MITwackeln, nicht dagegen ---
	#
	# Sie hängt neben der Kamera, nicht unter ihr. Bewegt sich nur die Kamera,
	# bleibt die Waffe stehen und schwimmt gegenläufig durchs Bild — das sieht
	# kaputt aus statt erschüttert, und zwar bei JEDER Stärke.
	var weapon_node := player.get_node_or_null("CameraPivot/Weapon") as Node3D
	_check(weapon_node != null, "Waffenknoten gefunden")
	if weapon_node != null:
		blast.shake = 1.0
		blast._process(1.0 / 60.0)
		_check(weapon_node.rotation_degrees.is_equal_approx(camera.rotation_degrees),
			"Waffe und Sicht kippen gemeinsam (%v / %v)"
				% [weapon_node.rotation_degrees, camera.rotation_degrees])

		blast.reset()
		blast._process(1.0 / 60.0)
		_check(weapon_node.rotation_degrees.is_zero_approx(),
			"und stehen ohne Belastung beide gerade (%v)" % weapon_node.rotation_degrees)

	# --- Der Schleier ---
	_check(blast.overlay != null, "der Schleier ist da")
	if blast.overlay != null:
		_check(blast.overlay.layer < 10,
			"er liegt unter der Werkbank-Oberfläche (Schicht %d)" % blast.overlay.layer)

		var rect := blast.overlay.get_node_or_null("Schleier") as TextureRect
		_check(rect != null and rect.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"und fängt keine Mausklicks ab — sonst wäre die Werkbank blockiert")

		blast.reset()
		blast._process(1.0 / 60.0)
		_check(is_zero_approx(blast.overlay.get_alpha()),
			"ohne Belastung ist er unsichtbar (%.4f)" % blast.overlay.get_alpha())
		_check(rect != null and not rect.visible,
			"und wird dann gar nicht erst gezeichnet")

		blast.flash = 1.0
		blast._process(1.0 / 60.0)
		_check(blast.overlay.get_alpha() > 0.0,
			"bei voller Blendung deckt er (%.2f)" % blast.overlay.get_alpha())
		_check(blast.overlay.get_alpha() <= blast.config.flash_alpha + 0.001,
			"aber nie mehr als eingestellt (%.2f von %.2f)"
				% [blast.overlay.get_alpha(), blast.config.flash_alpha])

	# --- Der Pulverdampf ---
	_check(blast.smoke_cloud != null, "der Pulverdampf ist da")
	if blast.smoke_cloud != null:
		# DIE WICHTIGSTE EIGENSCHAFT. Mit local_coords = true klebten die
		# Schwaden an der Kamera und zögen mit jedem Blick mit — man bekäme sie
		# durch nichts los, und aus der Mechanik "tritt zur Seite, dann siehst
		# du wieder" würde ein Filter, den man für einen Fehler hält.
		_check(not blast.smoke_cloud.local_coords,
			"die Schwaden bleiben in der Welt stehen, statt an der Kamera zu kleben")

		_check(blast.smoke_cloud.amount <= PowderSmoke.MAX_PARTICLES,
			"die Partikelzahl ist gedeckelt (%d)" % blast.smoke_cloud.amount)

		# Ohne grosszügige Hülle schneidet Godot die abgedrifteten Schwaden weg.
		_check(blast.smoke_cloud.visibility_aabb.size.length() > 5.0,
			"die Sichtbarkeitshülle ist gross genug (%.1f m)"
				% blast.smoke_cloud.visibility_aabb.size.length())

		blast.reset()
		blast._process(1.0 / 60.0)
		_check(not blast.smoke_cloud.emitting, "ohne Belastung raucht nichts")

		blast.smoke = 1.0
		blast._process(1.0 / 60.0)
		_check(blast.smoke_cloud.emitting, "bei voller Belastung raucht es")
		_check(blast.smoke_cloud.amount_ratio > 0.9,
			"und zwar dicht (%.2f)" % blast.smoke_cloud.amount_ratio)

	# --- Das Gehör ---
	var world := GameAudio.bus_index(GameAudio.WORLD_BUS)
	var ringing := GameAudio.bus_index(GameAudio.TINNITUS_BUS)
	_check(world > 0, "der Welt-Bus ist angelegt (Index %d)" % world)
	_check(ringing > 0, "der Tinnitus-Bus ist angelegt (Index %d)" % ringing)

	if world > 0 and ringing > 0:
		_check(world != ringing, "und es sind wirklich zwei verschiedene")

		# DIE TRENNUNG IST DER GANZE PUNKT. Haengt das Pfeifen am selben Bus
		# wie die Welt, wird es mit steigender Belastung selbst gedaempft — es
		# wuerde also genau dann leiser, wenn es lauter werden soll.
		_check(AudioServer.get_bus_effect_count(world) == 1,
			"am Welt-Bus haengt genau ein Filter (%d)"
				% AudioServer.get_bus_effect_count(world))
		_check(AudioServer.get_bus_effect(world, 0) is AudioEffectLowPassFilter,
			"und zwar ein Tiefpass")
		_check(AudioServer.get_bus_effect_count(ringing) == 0,
			"das Pfeifen laeuft an ihm vorbei — es entsteht im Ohr, nicht in der Welt")

		# Mehrfaches ensure_buses() darf nichts stapeln. Sonst klaenge nach
		# dem dritten Levelwechsel alles dumpf, ohne dass ein Schuss fiel.
		GameAudio.ensure_buses()
		GameAudio.ensure_buses()
		_check(AudioServer.get_bus_effect_count(world) == 1,
			"auch nach dreimaligem Anlegen (%d Filter)"
				% AudioServer.get_bus_effect_count(world))

		var filter := AudioServer.get_bus_effect(world, 0) as AudioEffectLowPassFilter

		# Ruhe: offen und laut.
		blast.reset()
		blast._process(1.0 / 60.0)
		_check(filter.cutoff_hz > 20000.0,
			"ohne Belastung ist das Gehoer offen (%.0f Hz)" % filter.cutoff_hz)
		_check(is_zero_approx(AudioServer.get_bus_volume_db(world)),
			"und die Welt auf voller Lautstaerke (%.1f dB)"
				% AudioServer.get_bus_volume_db(world))
		_check(not blast._tinnitus_player.playing, "es pfeift nicht")

		# Der Anschlag, ueber die oeffentliche Schnittstelle gemessen.
		#
		# NICHT ueber _process(): Das klingt die Huellkurve erst ab und
		# aktualisiert dann das Gehoer, es stehen also 0,9986 statt 1,0 an —
		# und damit 603 Hz statt 600. Das ist richtig so, taugt aber nicht,
		# um den Endwert zu pruefen.
		GameAudio.set_muffle(1.0, blast.config.muffle_cutoff_hz, blast.config.muffle_volume_db)
		_check(is_equal_approx(filter.cutoff_hz, blast.config.muffle_cutoff_hz),
			"am Anschlag steht genau der Wert aus der .tres (%.1f von %.1f Hz)"
				% [filter.cutoff_hz, blast.config.muffle_cutoff_hz])
		_check(is_equal_approx(AudioServer.get_bus_volume_db(world), blast.config.muffle_volume_db),
			"und genau die eingestellte Lautstaerke (%.1f dB)"
				% AudioServer.get_bus_volume_db(world))

		# Und jetzt der Weg, den das Spiel wirklich geht.
		blast.tinnitus = 1.0
		blast._process(1.0 / 60.0)
		_check(filter.cutoff_hz < blast.config.muffle_cutoff_hz * 1.05,
			"bei voller Belastung ist es dumpf (%.0f Hz)" % filter.cutoff_hz)
		_check(AudioServer.get_bus_volume_db(world) < blast.config.muffle_volume_db * 0.95,
			"und leise (%.1f dB)" % AudioServer.get_bus_volume_db(world))
		_check(blast._tinnitus_player.playing, "und es pfeift")

		# DIE GRENZFREQUENZ MUSS LOGARITHMISCH LAUFEN.
		#
		# Linear laege die Mitte zwischen 20500 und 600 bei 10550 Hz — und
		# zwischen 20500 und 10550 hoert praktisch niemand einen Unterschied.
		# Die halbe Skala waere dann wirkungslos, und niemand merkte es, weil
		# der Effekt bei voller Belastung ja trotzdem stimmt.
		blast.tinnitus = 0.5
		blast._process(1.0 / 60.0)
		_check(filter.cutoff_hz < 6000.0,
			"bei halber Belastung schon deutlich dumpf (%.0f Hz statt linearer 10550)"
				% filter.cutoff_hz)
		_check(filter.cutoff_hz > blast.config.muffle_cutoff_hz,
			"aber noch nicht ganz zu (%.0f Hz)" % filter.cutoff_hz)

		# UND ES MUSS SICH WIEDER OEFFNEN. Der Bus ueberlebt einen
		# Levelwechsel — ohne Zuruecksetzen betraete man das naechste Level
		# mit den Ohren vom letzten, und niemand kaeme auf die Ursache.
		blast.reset()
		_check(filter.cutoff_hz > 20000.0,
			"reset() macht die Ohren wieder auf (%.0f Hz)" % filter.cutoff_hz)
		_check(is_zero_approx(AudioServer.get_bus_volume_db(world)),
			"und die Welt wieder laut (%.1f dB)" % AudioServer.get_bus_volume_db(world))
		_check(not blast._tinnitus_player.playing, "und das Pfeifen hoert auf")

		# --- Die Waffe haengt am Welt-Bus, sonst daempft der Filter sie nicht ---
		var weapon := player.get_node_or_null("CameraPivot/Weapon") as Weapon
		_check(weapon != null, "Waffe gefunden")
		if weapon != null:
			var off_bus := 0
			for voice in weapon._voices:
				if voice.bus != GameAudio.WORLD_BUS:
					off_bus += 1
			_check(weapon._voices.size() == Weapon.AUDIO_VOICES,
				"alle %d Stimmen sind da" % Weapon.AUDIO_VOICES)
			_check(off_bus == 0,
				"und alle haengen am Welt-Bus — sonst daempft der Tiefpass sie nicht (%d daneben)"
					% off_bus)

	player.queue_free()


## RAUCH KOMMT VOR ALLEM VOM SCHALLDÄMPFER — und das ist die Umkehrung von
## allem anderen hier.
##
## Blendung, Wackeln und Pfeifen kommen vom KNALL, der Dämpfer schützt davor.
## Rauch entsteht dagegen, WEIL ein Dämpfer dran ist: Er fängt die Pulvergase
## ab und lässt sie langsam und gekühlt austreten, statt sie in einem Schlag
## frei auszublasen.
##
## Damit hat der Dämpfer zwei Seiten, und genau das soll dieser Test
## festhalten. Fällt er weg, verschwindet der Nachteil des Dämpfers still, und
## er wäre wieder eine Entscheidung ohne Preis.
func _test_only_the_suppressor_smokes() -> void:
	_section("Der Dämpfer qualmt deutlich mehr")

	var loud := _weapon(&"weapon_rifle_ar15")
	var quiet := _weapon(&"weapon_rifle_ar15", &"ar15_muzzle_suppressor")

	_check(not MuzzleBlast.is_suppressed(loud), "die nackte AR-15 gilt als ungedämpft")
	_check(MuzzleBlast.is_suppressed(quiet), "mit Dämpfer gilt sie als gedämpft")

	# Ungedämpft: viel Belastung, wenig Rauch.
	var bare := _make()
	_fire_burst(bare, loud, 30)
	_check(bare.intensity() > 0.9, "ungedämpft blendet und wackelt es (%.2f)" % bare.intensity())
	_check(bare.smoke_intensity() > 0.0,
		"es qualmt auch ungedämpft — ein offener Lauf raucht ja (%.2f)"
			% bare.smoke_intensity())

	# Gedämpft: kein Knall, dafür Rauch.
	var suppressed := _make()
	_fire_burst(suppressed, quiet, 30)
	_check(is_zero_approx(suppressed.intensity()),
		"gedämpft blendet und wackelt nichts (%.6f)" % suppressed.intensity())
	_check(suppressed.smoke_intensity() > 0.9,
		"dafür qualmt es kräftig (%.2f)" % suppressed.smoke_intensity())

	# DER UNTERSCHIED IST DER PUNKT, nicht das blosse Vorhandensein. Ohne diese
	# Zusicherung könnte jemand die Abstufung auf 0,95 hochdrehen, beide Tests
	# oben blieben grün, und der Nachteil des Dämpfers wäre still verschwunden.
	_check(suppressed.smoke_intensity() > bare.smoke_intensity() * 1.5,
		"gedämpft qualmt deutlich mehr (%.2f gegen %.2f)"
			% [suppressed.smoke_intensity(), bare.smoke_intensity()])

	# Und ungedämpft erreicht es nie die volle Dichte, egal wie lange man hält.
	var endless := _make()
	_fire_burst(endless, loud, 200)
	_check(endless.smoke_intensity() < 0.9,
		"ungedämpft wird es auch nach 200 Schuss nicht so dicht (%.2f)"
			% endless.smoke_intensity())

	# Ein einzelner Schuss darf noch nicht vernebeln — gedämpft so wenig wie
	# ungedämpft.
	for entry in [{label = "gedämpft", weapon = quiet}, {label = "ungedämpft", weapon = loud}]:
		var single := _make()
		single.add(entry.weapon)
		_check(is_zero_approx(single.smoke_intensity()),
			"ein einzelner Schuss qualmt nicht (%s, %.6f)"
				% [entry.label, single.smoke_intensity()])

	# Und der Rauch verzieht sich wieder.
	_advance(suppressed, 12.0)
	_check(is_zero_approx(suppressed.smoke_strain) and is_zero_approx(suppressed.smoke),
		"nach zwölf Sekunden ist die Luft wieder klar")
