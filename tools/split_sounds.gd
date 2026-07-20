## Zerlegt eine lange Aufnahme in ihre einzelnen Geräusche.
##
##   godot --headless --path . --script res://tools/split_sounds.gd -- <datei> <zielordner>
##
## Gedacht für Aufnahmen wie "AR-15 nachlade sounds.wav": 20 Sekunden, in
## denen nacheinander Magazin gelöst, Magazin eingesetzt und durchgeladen
## wird, mit Pausen dazwischen. Das Spiel braucht daraus einzelne Dateien.
##
## Was dieses Werkzeug NICHT kann: erkennen, WELCHE Aktion man hört. Ob
## Geräusch 4 das Einsetzen des Magazins ist oder das Verschlussfangen,
## muss ein Mensch entscheiden. Die Dateien werden deshalb durchnummeriert
## und mit ihrer Position in der Aufnahme benannt — dann kann man sie
## anhören und umbenennen.
extends SceneTree

## Ab welchem Anteil des lautesten Werts ein Geräusch als begonnen gilt.
##
## Sehr viel niedriger als beim Zuschneiden von Schüssen: Ein Magazinklick
## ist ein Bruchteil so laut wie das Durchladen in derselben Aufnahme.
##
## Gemessen an "AR-15 nachlade sounds.wav":
##   0.06 -> 10 Geräusche  (fünf leise fehlen stillschweigend)
##   0.02 -> 15 Geräusche  (alle, sauber getrennt)
##   0.01 -> 17 Geräusche, aber die ersten beiden verschmelzen
##
## Zu viele Dateien sind harmlos — man löscht die überzähligen. Fehlende
## fallen niemandem auf, weil man nicht weiß, dass sie fehlen.
const ONSET_THRESHOLD := 0.02

## So lange muss es leise sein, damit das Geräusch als beendet gilt.
const GAP_DURATION := 0.18

## Etwas Vorlauf und Nachlauf, damit nichts abgeschnitten wirkt.
const PRE_ROLL := 0.010
const POST_ROLL := 0.060

## Kürzere Ausschläge sind Rauschen, keine Aktion.
const MIN_EVENT := 0.030

## Alle auf denselben Spitzenpegel bringen.
const TARGET_PEAK := 0.90


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Aufruf: --script ... -- <datei> <zielordner>")
		quit(1)
		return

	var source := args[0].strip_edges()
	var target := args[1].strip_edges()

	# Optional die Schwelle uebersteuern. Leise Aktionen wie ein
	# Magazinklick liegen manchmal unter dem Standardwert und fehlen dann
	# stillschweigend — was schlimmer ist als zu viele Dateien.
	var threshold := ONSET_THRESHOLD
	if args.size() >= 3:
		threshold = maxf(0.001, float(args[2]))

	var raw := FileAccess.get_file_as_bytes(source)
	if raw.is_empty():
		printerr("Datei nicht lesbar: ", source)
		quit(1)
		return

	var info := WavTools.parse(raw)
	if info.is_empty():
		printerr("Kein lesbares WAV: ", source)
		quit(1)
		return

	if not DirAccess.dir_exists_absolute(target):
		DirAccess.make_dir_recursive_absolute(target)

	var samples := WavTools.to_mono(raw, info)
	var rate: int = info.rate
	var peak := WavTools.peak_of(samples)
	if peak <= 0.0:
		printerr("Nur Stille.")
		quit(1)
		return

	print("=== Aufnahme zerlegen ===")
	print("Quelle:  %s  (%.2f s)" % [source.get_file(), float(samples.size()) / float(rate)])
	print("Ziel:    %s\n" % target)

	var events := _find_events(samples, peak, rate, threshold)
	print("Schwelle: %.3f    %d Geraeusche gefunden.\n" % [threshold, events.size()])

	var written := 0
	for i in range(events.size()):
		var event: Dictionary = events[i]
		if _write_event(samples, event, rate, target, i + 1):
			written += 1

	print("\n%d Dateien geschrieben." % written)
	print("Anhoeren und sagen, welche Nummer welche Aktion ist:")
	print("  Magazin raus / Magazin rein / Durchladen")
	quit(0)


## Sucht zusammenhängende laute Abschnitte, getrennt durch Pausen.
func _find_events(samples: PackedFloat32Array, peak: float, rate: int,
		relative_threshold: float) -> Array:
	var threshold := peak * relative_threshold
	var gap_frames := int(GAP_DURATION * rate)
	var min_frames := int(MIN_EVENT * rate)

	var events: Array = []
	var in_event := false
	var start := 0
	var quiet_run := 0

	for i in range(samples.size()):
		var loud := absf(samples[i]) >= threshold

		if loud:
			if not in_event:
				in_event = true
				start = i
			quiet_run = 0
			continue

		if not in_event:
			continue

		quiet_run += 1
		if quiet_run < gap_frames:
			continue

		# Pause lang genug — das Geräusch ist vorbei.
		var stop := i - quiet_run
		if stop - start >= min_frames:
			events.append({start = start, stop = stop})
		in_event = false
		quiet_run = 0

	if in_event and samples.size() - start >= min_frames:
		events.append({start = start, stop = samples.size()})

	return events


func _write_event(samples: PackedFloat32Array, event: Dictionary, rate: int,
		target: String, index: int) -> bool:
	var start: int = maxi(0, int(event.start) - int(PRE_ROLL * rate))
	var stop: int = mini(samples.size(), int(event.stop) + int(POST_ROLL * rate))
	var length := stop - start

	var cut := PackedFloat32Array()
	cut.resize(length)
	for i in range(length):
		cut[i] = samples[start + i]

	# Jedes Geraeusch fuer sich normalisieren: Ein leiser Magazinklick soll
	# im Spiel genauso hoerbar sein wie das laute Durchladen. Die Abmischung
	# passiert spaeter im Spiel, nicht in den Dateien.
	var peak := WavTools.peak_of(cut)
	if peak > 0.0:
		var gain := TARGET_PEAK / peak
		for i in range(length):
			cut[i] *= gain

	WavTools.fade_in(cut, rate)
	WavTools.fade_out(cut, rate)

	# Der Zeitpunkt im Namen hilft beim Wiederfinden in der Originaldatei.
	var at := float(start) / float(rate)
	var name := "%02d_bei_%05.2fs.wav" % [index, at]
	var path := target.path_join(name)

	if not WavTools.write(path, cut, rate):
		return false

	print("  %-22s %.3f s   %s" % [
		name, float(length) / float(rate), _describe(cut, rate)])
	return true


## Beschreibt ein Geräusch mit messbaren Eigenschaften.
##
## Claude kann nicht hören. Diese Werte sind der Ersatz: Sie erlauben eine
## begründete Zuordnung statt zu raten, welcher Schnipsel wozu passt.
##
##   Nulldurchgaenge  wie oft das Signal die Nulllinie kreuzt.
##                    hoch = hell und rauschig (Papier, Folie, Kies)
##                    niedrig = tief und tonal (Schlag, Dumpfes)
##   Ausklingen       bis der Pegel auf ein Zehntel gefallen ist.
##                    lang = Metall, das nachschwingt
##                    kurz = Stoff, Holz, alles Gedaempfte
func _describe(samples: PackedFloat32Array, rate: int) -> String:
	if samples.is_empty():
		return ""

	# Nulldurchgaenge pro Sekunde.
	var crossings := 0
	for i in range(1, samples.size()):
		if (samples[i] < 0.0) != (samples[i - 1] < 0.0):
			crossings += 1
	var zcr := float(crossings) * float(rate) / float(samples.size())

	# Wann faellt der Pegel unter ein Zehntel der Spitze?
	#
	# Gemessen wird AB DEM LAUTESTEN PUNKT, nicht ab Dateianfang: Dort ist
	# durch die Einblendung noch Stille, und die liegt bereits unter der
	# Schwelle — das ergab vorher bei jedem Geraeusch 0,00 s.
	var peak := WavTools.peak_of(samples)
	var loudest := 0
	for i in range(samples.size()):
		if absf(samples[i]) >= peak:
			loudest = i
			break

	var decay_frames := samples.size() - loudest
	var block := maxi(1, int(0.005 * rate))
	var pos := loudest
	while pos < samples.size():
		var stop := mini(pos + block, samples.size())
		var block_peak := 0.0
		for i in range(pos, stop):
			block_peak = maxf(block_peak, absf(samples[i]))
		if block_peak < peak * 0.1:
			decay_frames = pos - loudest
			break
		pos = stop

	var decay := float(decay_frames) / float(rate)

	var art := "dumpf"
	if zcr > 6000.0:
		art = "hell/rauschig"
	elif zcr > 2500.0:
		art = "metallisch"
	elif zcr > 1000.0:
		art = "mittel"

	var nachklang := "kurz"
	if decay > 0.25:
		nachklang = "lang"
	elif decay > 0.10:
		nachklang = "mittel"

	return "%-14s Nachklang %-6s (%5.0f Hz, %.2f s)" % [art, nachklang, zcr, decay]
