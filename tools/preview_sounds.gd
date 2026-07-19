## Rendert Klangvarianten als WAV-Dateien zum Anhören — ohne sie ins Spiel
## zu übernehmen.
##
##   godot --headless --path . --script res://tools/preview_sounds.gd -- <Zielordner>
##
## Zweck: Claude kann nicht hören. Statt blind an Zahlen zu drehen und
## jedes Mal das Spiel zu starten, entstehen hier mehrere Varianten
## nebeneinander, die ein Mensch in Ruhe vergleichen kann. Was gefällt,
## wandert danach von Hand nach search_audio.gd.
##
## Die Varianten sind bewusst deutlich verschieden, nicht fein abgestuft —
## erst wenn die Richtung stimmt, lohnt Feinarbeit.
extends SceneTree

## Jede Variante: Name, Dauer, Anschläge (wie in SearchAudio).
const VARIANTS := {
	"waffe_a_aktuell": {
		dauer = 0.70, lautstaerke = 0.50,
		schlaege = [
			{at = 0.000, partials = [188.0, 268.0, 402.0, 611.0], decay = 13.0, amp = 1.00, noise = 0.42},
			{at = 0.105, partials = [232.0, 341.0, 523.0], decay = 19.0, amp = 0.48, noise = 0.26},
			{at = 0.178, partials = [880.0, 1240.0], decay = 32.0, amp = 0.22, noise = 0.14},
		],
	},
	"waffe_b_schwerer": {
		# Tiefer und traeger: mehr Masse, weniger Blech.
		dauer = 0.85, lautstaerke = 0.50,
		schlaege = [
			{at = 0.000, partials = [96.0, 141.0, 213.0, 318.0], decay = 9.0, amp = 1.00, noise = 0.55},
			{at = 0.130, partials = [124.0, 187.0, 279.0], decay = 14.0, amp = 0.52, noise = 0.30},
		],
	},
	"waffe_c_trocken": {
		# Kurz und hart: ein einzelnes Absetzen, kein Nachklappern.
		dauer = 0.34, lautstaerke = 0.50,
		schlaege = [
			{at = 0.000, partials = [210.0, 314.0, 470.0], decay = 26.0, amp = 1.00, noise = 0.62},
		],
	},
	"waffe_d_riegel": {
		# Metallisches Nachschlagen wie ein Verschluss, der einrastet.
		dauer = 0.62, lautstaerke = 0.50,
		schlaege = [
			{at = 0.000, partials = [174.0, 259.0, 388.0], decay = 15.0, amp = 0.95, noise = 0.48},
			{at = 0.075, partials = [1420.0, 2010.0, 2840.0], decay = 38.0, amp = 0.45, noise = 0.20},
			{at = 0.150, partials = [206.0, 305.0], decay = 22.0, amp = 0.35, noise = 0.18},
		],
	},

	"patrone_a_aktuell": {
		dauer = 0.38, lautstaerke = 0.42,
		schlaege = [
			{at = 0.000, partials = [1150.0, 1620.0, 2210.0], decay = 30.0, amp = 0.85, noise = 0.28},
			{at = 0.055, partials = [1290.0, 1810.0], decay = 34.0, amp = 0.52, noise = 0.20},
		],
	},
	"patrone_b_mehr_huelsen": {
		# Eine Handvoll Patronen, die gegeneinander fallen.
		dauer = 0.52, lautstaerke = 0.42,
		schlaege = [
			{at = 0.000, partials = [1240.0, 1730.0, 2380.0], decay = 34.0, amp = 0.80, noise = 0.30},
			{at = 0.042, partials = [1080.0, 1520.0, 2090.0], decay = 36.0, amp = 0.62, noise = 0.24},
			{at = 0.098, partials = [1380.0, 1930.0], decay = 40.0, amp = 0.45, noise = 0.18},
			{at = 0.155, partials = [1160.0, 1640.0], decay = 44.0, amp = 0.28, noise = 0.12},
		],
	},
	"patrone_c_pappschachtel": {
		# Nicht die Huelsen, sondern die Schachtel: dumpf, fast kein Metall.
		dauer = 0.30, lautstaerke = 0.42,
		schlaege = [
			{at = 0.000, partials = [320.0, 470.0], decay = 30.0, amp = 0.70, noise = 0.80},
		],
	},

	"platte_a_aktuell": {
		dauer = 0.52, lautstaerke = 0.55,
		schlaege = [
			{at = 0.000, partials = [94.0, 143.0, 207.0], decay = 21.0, amp = 1.00, noise = 0.55},
			{at = 0.070, partials = [118.0, 176.0], decay = 28.0, amp = 0.38, noise = 0.30},
		],
	},
	"platte_b_keramik": {
		# Haerter und hoeher: Keramik statt Stahl, kurzer heller Anteil.
		dauer = 0.44, lautstaerke = 0.55,
		schlaege = [
			{at = 0.000, partials = [140.0, 340.0, 790.0], decay = 24.0, amp = 1.00, noise = 0.70},
		],
	},
	"platte_c_sehr_dumpf": {
		# Fast nur Masse, kaum Klang — schwer und unangenehm.
		dauer = 0.60, lautstaerke = 0.55,
		schlaege = [
			{at = 0.000, partials = [62.0, 91.0], decay = 16.0, amp = 1.00, noise = 0.45},
		],
	},

	"schluessel_a_aktuell": {
		dauer = 0.62, lautstaerke = 0.50,
		schlaege = [
			{at = 0.000, partials = [2410.0, 3170.0, 4310.0, 5590.0], decay = 24.0, amp = 0.95, noise = 0.30},
			{at = 0.068, partials = [2180.0, 2960.0, 4020.0], decay = 27.0, amp = 0.72, noise = 0.22},
			{at = 0.132, partials = [2620.0, 3480.0, 4740.0], decay = 30.0, amp = 0.55, noise = 0.18},
			{at = 0.215, partials = [2290.0, 3060.0], decay = 34.0, amp = 0.34, noise = 0.12},
		],
	},
	"schluessel_b_einzeln": {
		# Ein einzelner Schluessel, kein Bund: zwei Anschlaege, tiefer.
		dauer = 0.40, lautstaerke = 0.50,
		schlaege = [
			{at = 0.000, partials = [1680.0, 2240.0, 3010.0], decay = 26.0, amp = 0.90, noise = 0.28},
			{at = 0.070, partials = [1520.0, 2080.0], decay = 32.0, amp = 0.45, noise = 0.16},
		],
	},
	"schluessel_c_lang": {
		# Ein Bund, der laenger nachschwingt.
		dauer = 0.95, lautstaerke = 0.50,
		schlaege = [
			{at = 0.000, partials = [2410.0, 3170.0, 4310.0, 5590.0], decay = 12.0, amp = 0.95, noise = 0.30},
			{at = 0.055, partials = [2180.0, 2960.0, 4020.0], decay = 14.0, amp = 0.75, noise = 0.22},
			{at = 0.115, partials = [2620.0, 3480.0, 4740.0], decay = 16.0, amp = 0.62, noise = 0.18},
			{at = 0.190, partials = [2290.0, 3060.0, 4180.0], decay = 18.0, amp = 0.48, noise = 0.14},
			{at = 0.290, partials = [2510.0, 3320.0], decay = 20.0, amp = 0.30, noise = 0.10},
		],
	},

	"verband_a_aktuell": {
		dauer = 0.46, lautstaerke = 0.48,
		schlaege = [
			{at = 0.000, partials = [], decay = 11.0, amp = 0.75, noise = 1.00},
			{at = 0.120, partials = [], decay = 15.0, amp = 0.45, noise = 1.00},
		],
	},
	"verband_b_knisternd": {
		# Mehrere kurze Stoesse statt zwei langer — knistert deutlicher.
		dauer = 0.50, lautstaerke = 0.48,
		schlaege = [
			{at = 0.000, partials = [], decay = 26.0, amp = 0.80, noise = 1.00},
			{at = 0.060, partials = [], decay = 30.0, amp = 0.62, noise = 1.00},
			{at = 0.115, partials = [], decay = 28.0, amp = 0.70, noise = 1.00},
			{at = 0.190, partials = [], decay = 34.0, amp = 0.45, noise = 1.00},
		],
	},
}

## Wie der tiefe Unterton fuer EPIC klingt — einmal separat zum Vergleich.
const UNTERTON := {
	"unterton_allein": {
		dauer = 0.68, lautstaerke = 0.62,
		schlaege = [{at = 0.0, partials = [52.0, 78.0], decay = 6.0, amp = 0.55, noise = 0.0}],
	},
	"waffe_mit_unterton": {
		dauer = 0.70, lautstaerke = 0.62,
		schlaege = [
			{at = 0.000, partials = [188.0, 268.0, 402.0, 611.0], decay = 13.0, amp = 1.00, noise = 0.42},
			{at = 0.105, partials = [232.0, 341.0, 523.0], decay = 19.0, amp = 0.48, noise = 0.26},
			{at = 0.178, partials = [880.0, 1240.0], decay = 32.0, amp = 0.22, noise = 0.14},
			{at = 0.000, partials = [52.0, 78.0], decay = 6.0, amp = 0.55, noise = 0.0},
		],
	},
}


func _initialize() -> void:
	var target := _target_directory()
	print("=== Klangvarianten rendern ===")
	print("Zielordner: ", target)

	if not DirAccess.dir_exists_absolute(target):
		var err := DirAccess.make_dir_recursive_absolute(target)
		if err != OK:
			printerr("Ordner laesst sich nicht anlegen: ", target, " (Fehler ", err, ")")
			quit(1)
			return

	var alle := {}
	alle.merge(VARIANTS)
	alle.merge(UNTERTON)

	var geschrieben := 0
	for name in alle.keys():
		var v: Dictionary = alle[name]
		var stream := SearchAudio._render(v.schlaege, v.dauer, v.lautstaerke)
		var path := target.path_join("%s.wav" % name)
		var err := stream.save_to_wav(path)
		if err != OK:
			printerr("  FEHLER beim Schreiben: ", path, " (", err, ")")
			continue
		geschrieben += 1
		print("  %-26s %.2f s" % [name + ".wav", v.dauer])

	print("\n%d Dateien geschrieben." % geschrieben)
	print("Anhoeren, dann sagen welche Variante passt — die wandert dann")
	print("von Hand nach scripts/loot/search_audio.gd.")
	quit(0)


## Zielordner aus den Argumenten nach "--", sonst user://klangproben.
func _target_directory() -> String:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].strip_edges() != "":
		return args[0].strip_edges()
	return ProjectSettings.globalize_path("user://klangproben")
