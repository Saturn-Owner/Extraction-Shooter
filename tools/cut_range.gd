## Schneidet einen Ausschnitt aus einer Aufnahme heraus.
##
##   Ansehen:    godot --headless --path . --script res://tools/cut_range.gd -- <datei>
##   Schneiden:  godot --headless --path . --script res://tools/cut_range.gd -- <datei> <ziel.wav> <von> <bis>
##
## Warum nicht split_sounds.gd: Das trennt an Pausen. Bei durchgehenden
## Aufnahmen — Atmen, Wind, Motorbrummen — gibt es keine Pausen, an denen man
## trennen könnte. Hier sagt ein Mensch, welcher Abschnitt gebraucht wird.
##
## Ohne Bereich zeigt das Werkzeug, was in der Aufnahme passiert: Pegel und
## Ereignisdichte je Sekunde. Damit lässt sich die Stelle finden, an der eine
## Aufnahme umschlägt — etwa von ruhigem zu schnellem Atmen — ohne sie zu
## hören.
extends SceneTree

## Fensterbreite der Übersicht.
const WINDOW_SECONDS := 1.0

## Ab welchem Anteil des Spitzenwerts ein Ausschlag als Ereignis zählt.
const EVENT_THRESHOLD := 0.25

## So lange muss es leise sein, bis das nächste Ereignis zählt.
const EVENT_GAP := 0.12

## Auf diesen Spitzenpegel wird der Ausschnitt gebracht.
const TARGET_PEAK := 0.90


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Aufruf: --script ... -- <datei> [<ziel.wav> <von> <bis>]")
		quit(1)
		return

	var source := args[0].strip_edges()
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

	var samples := WavTools.to_mono(raw, info)
	var rate: int = info.rate
	var peak := WavTools.peak_of(samples)

	print("=== %s ===" % source.get_file())
	print("%.2f s, %d Hz, Spitze %.3f\n" % [float(samples.size()) / float(rate), rate, peak])

	if args.size() < 4:
		_overview(samples, rate, peak)
		quit(0)
		return

	var target := args[1].strip_edges()
	var from_s := float(args[2])
	var to_s := float(args[3])
	quit(0 if _cut(samples, rate, peak, target, from_s, to_s) else 1)


## Zeigt je Sekunde, wie laut es ist und wie viel dort passiert.
func _overview(samples: PackedFloat32Array, rate: int, peak: float) -> void:
	var window := int(WINDOW_SECONDS * rate)
	if window <= 0 or peak <= 0.0:
		return

	print("  Sekunde   Spitze  Ereignisse  Pegel")
	var events := _find_onsets(samples, rate, peak)

	var second := 0
	while second * window < samples.size():
		var start := second * window
		var stop := mini(start + window, samples.size())

		var local := 0.0
		for i in range(start, stop):
			local = maxf(local, absf(samples[i]))

		var count := 0
		for at in events:
			if at >= start and at < stop:
				count += 1

		var bar := "#".repeat(int(local * 40.0))
		print("  %5.1f s   %5.3f   %8d   %s" % [
			float(start) / float(rate), local, count, bar])
		second += 1


## Wo im Signal ein neuer Ausschlag beginnt, in Samples.
func _find_onsets(samples: PackedFloat32Array, rate: int, peak: float) -> PackedInt32Array:
	var threshold := peak * EVENT_THRESHOLD
	var gap := int(EVENT_GAP * rate)

	var onsets := PackedInt32Array()
	var quiet := gap

	for i in range(samples.size()):
		if absf(samples[i]) >= threshold:
			if quiet >= gap:
				onsets.append(i)
			quiet = 0
		else:
			quiet += 1

	return onsets


func _cut(samples: PackedFloat32Array, rate: int, peak: float,
		target: String, from_s: float, to_s: float) -> bool:
	var start := clampi(int(from_s * rate), 0, samples.size())
	var stop := clampi(int(to_s * rate), start, samples.size())
	if stop - start <= 0:
		printerr("Leerer Bereich: %.2f bis %.2f" % [from_s, to_s])
		return false

	var cut := PackedFloat32Array()
	cut.resize(stop - start)
	for i in range(cut.size()):
		cut[i] = samples[start + i]

	var local_peak := WavTools.peak_of(cut)
	if local_peak > 0.0:
		var gain := TARGET_PEAK / local_peak
		for i in range(cut.size()):
			cut[i] *= gain

	# Etwas laenger ein- und ausblenden als beim Zerlegen: Dieser Ausschnitt
	# wird als Schleife abgespielt, und ein harter Schnitt knackt bei jedem
	# Durchlauf erneut.
	WavTools.fade_in(cut, rate, 0.040)
	WavTools.fade_out(cut, rate, 0.060)

	if not WavTools.write(target, cut, rate):
		return false

	print("Geschrieben: %s" % target)
	print("  %.2f bis %.2f s  (%.2f s)   Spitze vorher %.3f, jetzt %.2f" % [
		from_s, to_s, float(cut.size()) / float(rate), local_peak, TARGET_PEAK])
	return true
