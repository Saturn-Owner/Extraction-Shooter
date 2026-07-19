## Erzeugt den Grundbestand an Munition und Waffen als .tres-Dateien.
##
##   godot --headless --path . --script res://tools/generate_arsenal.gd
##
## ACHTUNG — EINMAL-WERKZEUG:
## Nach dem Erzeugen sind die .tres-Dateien die Wahrheit, nicht dieses Skript.
## Wer hier nochmal draufdrückt, überschreibt alle Änderungen, die inzwischen
## im Editor gemacht wurden. Zum Nachbalancieren also die .tres bearbeiten,
## nicht diese Tabelle.
##
## Der Generator existiert nur, weil ~40 Dateien von Hand zu schreiben
## garantiert Tippfehler produziert hätte.
##
## ---------------------------------------------------------------------------
## BALANCING-GRUNDGEDANKE
##
## Durchschlag (0-70) und Schaden sind ABSICHTLICH gegenläufig:
## Panzerbrechende Munition hat einen harten, kleinen Kern — der geht durch
## Platten, reisst im Gewebe aber wenig. Weiche Hohlspitzgeschosse verformen
## sich, richten enormen Schaden an und scheitern an jeder Platte.
##
## Deshalb gibt es keine "beste" Munition, sondern nur eine Entscheidung:
## Rechne ich mit gepanzerten Gegnern oder nicht?
##
## Faustregel Durchschlag gegen Plattenklasse: pen >= klasse * 10
##   Klasse 2 -> 20    Klasse 4 -> 40    Klasse 6 -> 60
extends SceneTree

const AMMO_DIR := "res://assets/data/ammo"
const WEAPON_DIR := "res://assets/data/weapons"

# ---------------------------------------------------------------------------
# MUNITION
# Reihenfolge: id, Name, Kaliber, Schaden, Pen, Plattenschaden%, Frag,
#              v0 m/s, BC, Blutung, schwere Blutung, Gewicht, Stapel, Preis
# ---------------------------------------------------------------------------
const AMMO := [
	# --- 9x19 Pistole / MP ---------------------------------------------------
	{id = "9x19_fmj", name = "9x19 FMJ", cal = "9x19", dmg = 54, pen = 10, ad = 22.0,
		frag = 0.05, v0 = 380.0, bc = 0.14, bleed = 0.18, hbleed = 0.03,
		kg = 0.011, stack = 70, price = 42,
		desc = "Standard-Vollmantel. Billig, ueberall zu finden, gegen jede Platte nutzlos."},
	{id = "9x19_hp", name = "9x19 Hohlspitz", cal = "9x19", dmg = 72, pen = 5, ad = 12.0,
		frag = 0.35, v0 = 355.0, bc = 0.12, bleed = 0.38, hbleed = 0.10,
		kg = 0.011, stack = 70, price = 78,
		desc = "Verformt sich im Ziel und richtet schwere Wunden an. Gegen Rüstung voellig wirkungslos."},
	{id = "9x19_ap", name = "9x19 AP 6.3", cal = "9x19", dmg = 44, pen = 32, ad = 44.0,
		frag = 0.02, v0 = 480.0, bc = 0.17, bleed = 0.12, hbleed = 0.02,
		kg = 0.010, stack = 70, price = 290,
		desc = "Panzerbrechende Pistolenmunition mit Stahlkern. Ueberraschend wirksam gegen leichte Platten."},

	# --- .45 ACP -------------------------------------------------------------
	{id = "45acp_fmj", name = ".45 ACP FMJ", cal = ".45 ACP", dmg = 68, pen = 8, ad = 20.0,
		frag = 0.04, v0 = 260.0, bc = 0.16, bleed = 0.22, hbleed = 0.04,
		kg = 0.021, stack = 60, price = 65,
		desc = "Schweres, langsames Geschoss. Enorme Wirkung auf kurze Distanz, faellt weit ab."},
	{id = "45acp_ap", name = ".45 ACP AP", cal = ".45 ACP", dmg = 52, pen = 30, ad = 40.0,
		frag = 0.02, v0 = 310.0, bc = 0.18, bleed = 0.14, hbleed = 0.02,
		kg = 0.020, stack = 60, price = 310,
		desc = "Selten und teuer. Verbindet die Wucht des Kalibers mit brauchbarem Durchschlag."},

	# --- 5.45x39 AK-74 -------------------------------------------------------
	{id = "545x39_hp", name = "5.45x39 HP", cal = "5.45x39", dmg = 62, pen = 12, ad = 16.0,
		frag = 0.42, v0 = 884.0, bc = 0.24, bleed = 0.40, hbleed = 0.11,
		kg = 0.010, stack = 60, price = 58,
		desc = "Hohlspitz. Reisst ungeschuetzte Ziele auf, scheitert an allem Gepanzerten."},
	{id = "545x39_ps", name = "5.45x39 PS", cal = "5.45x39", dmg = 46, pen = 30, ad = 34.0,
		frag = 0.14, v0 = 890.0, bc = 0.26, bleed = 0.20, hbleed = 0.05,
		kg = 0.010, stack = 60, price = 96,
		desc = "Der Standard. Solider Allrounder ohne Staerken und ohne Schwaechen."},
	{id = "545x39_bt", name = "5.45x39 BT", cal = "5.45x39", dmg = 44, pen = 37, ad = 42.0,
		frag = 0.10, v0 = 900.0, bc = 0.27, bleed = 0.18, hbleed = 0.04,
		kg = 0.010, stack = 60, price = 175, tracer = true,
		desc = "Leuchtspur mit gehaertetem Kern. Zeigt dir deine Treffer - und dem Gegner deine Position."},
	{id = "545x39_bs", name = "5.45x39 BS", cal = "5.45x39", dmg = 40, pen = 51, ad = 58.0,
		frag = 0.04, v0 = 830.0, bc = 0.29, bleed = 0.14, hbleed = 0.03,
		kg = 0.011, stack = 60, price = 720,
		desc = "Wolframkern. Durchschlaegt schwere Platten, laesst den Getroffenen aber oft noch stehen."},

	# --- 5.56x45 NATO (M995 und M855A1 existieren bereits) -------------------
	{id = "556x45_m855", name = "5.56x45 M855", cal = "5.56x45", dmg = 54, pen = 31, ad = 36.0,
		frag = 0.16, v0 = 922.0, bc = 0.27, bleed = 0.22, hbleed = 0.05,
		kg = 0.013, stack = 60, price = 118,
		desc = "Der alte NATO-Standard mit Stahlspitze. Guenstig und ueberall verfuegbar."},
	{id = "556x45_mk318", name = "5.56x45 Mk 318", cal = "5.56x45", dmg = 58, pen = 26, ad = 30.0,
		frag = 0.34, v0 = 900.0, bc = 0.26, bleed = 0.34, hbleed = 0.09,
		kg = 0.013, stack = 60, price = 152,
		desc = "Offene Spitze, gebaut fuer Wirkung im Ziel. Gegen Platten die schlechteste Wahl im Kaliber."},
	{id = "556x45_hp", name = "5.56x45 HP", cal = "5.56x45", dmg = 65, pen = 11, ad = 14.0,
		frag = 0.45, v0 = 880.0, bc = 0.23, bleed = 0.44, hbleed = 0.13,
		kg = 0.012, stack = 60, price = 74,
		desc = "Reine Jagdmunition. Verheerend gegen ungeschuetzte Ziele, nutzlos gegen alles andere."},

	# --- 7.62x39 AKM ---------------------------------------------------------
	{id = "762x39_hp", name = "7.62x39 HP", cal = "7.62x39", dmg = 73, pen = 15, ad = 18.0,
		frag = 0.40, v0 = 730.0, bc = 0.26, bleed = 0.42, hbleed = 0.12,
		kg = 0.016, stack = 60, price = 88,
		desc = "Schwere Hohlspitz. Ein Treffer in den Oberkoerper beendet die meisten Kaempfe sofort."},
	{id = "762x39_ps", name = "7.62x39 PS", cal = "7.62x39", dmg = 57, pen = 29, ad = 36.0,
		frag = 0.16, v0 = 720.0, bc = 0.28, bleed = 0.26, hbleed = 0.06,
		kg = 0.016, stack = 60, price = 105,
		desc = "Der Klassiker. Mehr Wucht als 5.45, dafuer traeger und mit staerkerem Rueckstoss."},
	{id = "762x39_bp", name = "7.62x39 BP", cal = "7.62x39", dmg = 53, pen = 47, ad = 54.0,
		frag = 0.06, v0 = 730.0, bc = 0.30, bleed = 0.20, hbleed = 0.04,
		kg = 0.017, stack = 60, price = 480,
		desc = "Gehaerteter Stahlkern. Der beste Kompromiss aus Durchschlag und Wirkung im ganzen Spiel."},

	# --- 7.62x51 NATO --------------------------------------------------------
	{id = "762x51_nosler", name = "7.62x51 Ultra Nosler", cal = "7.62x51", dmg = 107, pen = 20, ad = 24.0,
		frag = 0.48, v0 = 790.0, bc = 0.33, bleed = 0.50, hbleed = 0.16,
		kg = 0.023, stack = 40, price = 260,
		desc = "Jagdgeschoss im Militaerkaliber. Toetet ungepanzerte Ziele praktisch sofort."},
	{id = "762x51_m80", name = "7.62x51 M80", cal = "7.62x51", dmg = 80, pen = 41, ad = 48.0,
		frag = 0.14, v0 = 833.0, bc = 0.36, bleed = 0.30, hbleed = 0.08,
		kg = 0.024, stack = 40, price = 320,
		desc = "NATO-Standard. Schwer, laut, wirksam - und kommt durch mittlere Platten."},
	{id = "762x51_m62", name = "7.62x51 M62", cal = "7.62x51", dmg = 75, pen = 50, ad = 56.0,
		frag = 0.10, v0 = 838.0, bc = 0.37, bleed = 0.26, hbleed = 0.07,
		kg = 0.024, stack = 40, price = 540, tracer = true,
		desc = "Leuchtspur. Auf grosse Distanz eine echte Hilfe, verraet aber jede Stellung."},
	{id = "762x51_m61", name = "7.62x51 M61", cal = "7.62x51", dmg = 70, pen = 64, ad = 66.0,
		frag = 0.04, v0 = 850.0, bc = 0.39, bleed = 0.20, hbleed = 0.05,
		kg = 0.025, stack = 40, price = 1180,
		desc = "Panzerbrechend. Es gibt kaum eine Platte, die das zuverlaessig aufhaelt."},

	# --- 7.62x54R Dragunow ---------------------------------------------------
	{id = "762x54r_lps", name = "7.62x54R LPS", cal = "7.62x54R", dmg = 82, pen = 41, ad = 48.0,
		frag = 0.14, v0 = 800.0, bc = 0.36, bleed = 0.32, hbleed = 0.09,
		kg = 0.022, stack = 40, price = 340,
		desc = "Standard-Scharfschuetzenmunition. Reichweite und Wucht zu vertretbarem Preis."},
	{id = "762x54r_snb", name = "7.62x54R SNB", cal = "7.62x54R", dmg = 75, pen = 56, ad = 60.0,
		frag = 0.06, v0 = 820.0, bc = 0.38, bleed = 0.24, hbleed = 0.06,
		kg = 0.022, stack = 40, price = 690,
		desc = "Stahlkern mit hoher Praezision. Bevorzugte Wahl gegen gepanzerte Ziele auf Distanz."},
	{id = "762x54r_bt", name = "7.62x54R BT", cal = "7.62x54R", dmg = 78, pen = 62, ad = 68.0,
		frag = 0.04, v0 = 810.0, bc = 0.39, bleed = 0.22, hbleed = 0.05,
		kg = 0.023, stack = 40, price = 980, tracer = true,
		desc = "Panzerbrechende Leuchtspur. Durchschlaegt fast alles - und zeigt allen, wo du liegst."},

	# --- .338 Lapua Magnum ---------------------------------------------------
	{id = "338lm_fmj", name = ".338 LM FMJ", cal = ".338 LM", dmg = 152, pen = 47, ad = 56.0,
		frag = 0.20, v0 = 880.0, bc = 0.52, bleed = 0.44, hbleed = 0.16,
		kg = 0.043, stack = 30, price = 1450,
		desc = "Extrem schweres Geschoss. Was es trifft, steht danach nicht mehr auf."},
	{id = "338lm_ap", name = ".338 LM AP", cal = ".338 LM", dmg = 130, pen = 70, ad = 78.0,
		frag = 0.05, v0 = 915.0, bc = 0.58, bleed = 0.30, hbleed = 0.09,
		kg = 0.044, stack = 30, price = 3600,
		desc = "Die staerkste Munition im Spiel. Keine Platte haelt das auf. Der Preis entsprechend."},

	# --- 12/70 Schrot --------------------------------------------------------
	{id = "12x70_buckshot", name = "12/70 Buckshot", cal = "12/70", dmg = 48, pen = 3, ad = 8.0,
		frag = 0.0, v0 = 385.0, bc = 0.06, bleed = 0.30, hbleed = 0.07,
		kg = 0.052, stack = 20, price = 55, pellets = 8, spread = 4.5,
		desc = "Acht Kugeln pro Schuss. Auf zwei Metern vernichtend, auf dreissig voellig harmlos."},
	{id = "12x70_flechette", name = "12/70 Flechette", cal = "12/70", dmg = 26, pen = 31, ad = 26.0,
		frag = 0.0, v0 = 450.0, bc = 0.09, bleed = 0.34, hbleed = 0.08,
		kg = 0.050, stack = 20, price = 210, pellets = 8, spread = 3.0,
		desc = "Acht Stahlpfeile. Einzeln schwach, aber sie kommen durch leichte Platten."},
	{id = "12x70_slug", name = "12/70 Flintenlaufgeschoss", cal = "12/70", dmg = 190, pen = 20, ad = 32.0,
		frag = 0.10, v0 = 470.0, bc = 0.14, bleed = 0.40, hbleed = 0.14,
		kg = 0.055, stack = 20, price = 130,
		desc = "Ein einzelnes schweres Geschoss statt Schrot. Macht aus der Flinte eine Kurzdistanzwaffe mit Wucht."},
]

# ---------------------------------------------------------------------------
# WAFFEN
# ---------------------------------------------------------------------------
const WEAPONS := [
	{id = "pistol_g17", name = "G17", cal = "9x19", w = 2, h = 2, kg = 0.62, mag = 17,
		rpm = 450, rv = 62.0, rh = 24.0, ergo = 86, moa = 4.2, price = 6800,
		modes = ["SINGLE"], vmod = 0.92,
		desc = "Schlichte Dienstpistole. Leicht, zuverlaessig, immer besser als nichts."},
	{id = "pistol_m1911", name = "M1911", cal = ".45 ACP", w = 2, h = 2, kg = 1.1, mag = 7,
		rpm = 380, rv = 88.0, rh = 32.0, ergo = 74, moa = 4.8, price = 9400,
		modes = ["SINGLE"], vmod = 0.90,
		desc = "Alte Konstruktion, harter Rueckstoss, wenig Schuss. Wer trifft, braucht keinen zweiten."},
	{id = "smg_mp5", name = "MP5", cal = "9x19", w = 4, h = 2, kg = 2.5, mag = 30,
		rpm = 800, rv = 74.0, rh = 30.0, ergo = 78, moa = 3.4, price = 21000,
		modes = ["SINGLE", "BURST", "AUTO"], vmod = 1.02,
		desc = "Sehr kontrollierbare Maschinenpistole. In engen Raeumen kaum zu schlagen."},
	{id = "smg_pp19", name = "PP-19 Vityaz", cal = "9x19", w = 4, h = 2, kg = 2.9, mag = 30,
		rpm = 700, rv = 82.0, rh = 34.0, ergo = 70, moa = 3.8, price = 17500,
		modes = ["SINGLE", "AUTO"], vmod = 1.0,
		desc = "Robuste MP auf Kalaschnikow-Basis. Weniger fein als die MP5, dafuer unverwuestlich."},
	{id = "rifle_ak74m", name = "AK-74M", cal = "5.45x39", w = 5, h = 2, kg = 3.4, mag = 30,
		rpm = 650, rv = 126.0, rh = 46.0, ergo = 50, moa = 2.8, price = 22000,
		modes = ["SINGLE", "AUTO"], vmod = 1.0,
		desc = "Das Arbeitstier. Frisst Dreck, Schnee und Vernachlaessigung ohne Klage."},
	{id = "rifle_akm", name = "AKM", cal = "7.62x39", w = 5, h = 2, kg = 3.6, mag = 30,
		rpm = 600, rv = 158.0, rh = 62.0, ergo = 46, moa = 3.2, price = 24500,
		modes = ["SINGLE", "AUTO"], vmod = 1.0,
		desc = "Mehr Wucht als die AK-74, aber auch deutlich mehr Rueckstoss. Dauerfeuer ist Verschwendung."},
	{id = "rifle_ar15", name = "AR-15", cal = "5.56x45", w = 5, h = 2, kg = 3.1, mag = 30,
		rpm = 750, rv = 118.0, rh = 42.0, ergo = 54, moa = 2.4, price = 24000,
		modes = ["SINGLE", "AUTO"], vmod = 1.0,
		desc = "Praezise und angenehm zu schiessen. Empfindlicher gegen Dreck als eine Kalaschnikow."},
	{id = "rifle_scar_h", name = "SCAR-H", cal = "7.62x51", w = 5, h = 2, kg = 4.1, mag = 20,
		rpm = 600, rv = 172.0, rh = 68.0, ergo = 44, moa = 1.9, price = 68000,
		modes = ["SINGLE", "AUTO"], vmod = 1.0,
		desc = "Schweres Sturmgewehr. Enorme Wirkung, enormer Rueckstoss, enormer Preis."},
	{id = "dmr_m14", name = "M14", cal = "7.62x51", w = 6, h = 2, kg = 4.5, mag = 20,
		rpm = 700, rv = 180.0, rh = 70.0, ergo = 38, moa = 1.5, price = 52000,
		modes = ["SINGLE"], vmod = 1.06,
		desc = "Altes Selbstladegewehr mit langem Lauf. Auf Distanz gnadenlos, in Gebaeuden unhandlich."},
	{id = "dmr_svd", name = "SVD", cal = "7.62x54R", w = 6, h = 2, kg = 4.3, mag = 10,
		rpm = 650, rv = 186.0, rh = 66.0, ergo = 36, moa = 1.2, price = 61000,
		modes = ["SINGLE"], vmod = 1.08,
		desc = "Die klassische Dragunow. Gebaut, um auf mehreren hundert Metern zu treffen."},
	{id = "sniper_axmc", name = "AXMC", cal = ".338 LM", w = 6, h = 2, kg = 6.8, mag = 10,
		rpm = 40, rv = 320.0, rh = 90.0, ergo = 24, moa = 0.6, price = 240000,
		modes = ["SINGLE"], vmod = 1.12,
		desc = "Repetierbuechse fuer extreme Entfernungen. Schwer, langsam, unbezahlbar - und toedlich."},
	{id = "shotgun_m870", name = "M870", cal = "12/70", w = 5, h = 2, kg = 3.6, mag = 7,
		rpm = 60, rv = 240.0, rh = 74.0, ergo = 48, moa = 9.0, price = 14500,
		modes = ["SINGLE"], vmod = 0.95,
		desc = "Vorderschaftrepetierer. Ein Treffer auf kurze Distanz beendet fast jede Auseinandersetzung."},
]


func _initialize() -> void:
	print("=== Arsenal erzeugen ===\n")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AMMO_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WEAPON_DIR))

	var ammo_count := 0
	for entry in AMMO:
		if _write_ammo(entry):
			ammo_count += 1

	var weapon_count := 0
	for entry in WEAPONS:
		if _write_weapon(entry):
			weapon_count += 1

	print("\n%d Munitionssorten, %d Waffen erzeugt." % [ammo_count, weapon_count])
	quit(0)


func _write_ammo(e: Dictionary) -> bool:
	var a := AmmoData.new()
	a.id = StringName("ammo_" + e.id)
	a.display_name = e.name
	a.description = e.desc
	a.category = ItemData.Category.AMMO
	a.grid_width = 1
	a.grid_height = 1
	a.can_rotate = false
	a.weight_kg = e.kg
	a.max_stack = e.stack
	a.base_price = e.price
	a.caliber = StringName(e.cal)
	a.damage = e.dmg
	a.penetration_power = e.pen
	a.armor_damage_percent = e.ad
	a.fragmentation_chance = e.frag
	a.muzzle_velocity_ms = e.v0
	a.ballistic_coefficient = e.bc
	a.bleeding_chance = e.bleed
	a.heavy_bleeding_chance = e.hbleed
	a.pellet_count = e.get("pellets", 1)
	a.pellet_spread_degrees = e.get("spread", 0.0)
	a.is_tracer = e.get("tracer", false)

	var path := "%s/%s.tres" % [AMMO_DIR, e.id]
	var err := ResourceSaver.save(a, path)
	if err != OK:
		push_error("Konnte %s nicht speichern (Fehler %d)" % [path, err])
		return false
	print("  Munition  ", path)
	return true


func _write_weapon(e: Dictionary) -> bool:
	var w := WeaponData.new()
	w.id = StringName("weapon_" + e.id)
	w.display_name = e.name
	w.description = e.desc
	w.category = ItemData.Category.WEAPON
	w.grid_width = e.w
	w.grid_height = e.h
	w.can_rotate = true
	w.weight_kg = e.kg
	w.max_stack = 1
	w.base_price = e.price
	w.caliber = StringName(e.cal)
	w.magazine_size = e.mag
	w.fire_rate_rpm = e.rpm
	w.recoil_vertical = e.rv
	w.recoil_horizontal = e.rh
	w.ergonomics = e.ergo
	w.accuracy_moa = e.moa
	w.muzzle_velocity_modifier = e.vmod

	var modes: Array[WeaponData.FireMode] = []
	for name in e.modes:
		match name:
			"SINGLE": modes.append(WeaponData.FireMode.SINGLE)
			"BURST": modes.append(WeaponData.FireMode.BURST)
			"AUTO": modes.append(WeaponData.FireMode.AUTO)
	w.fire_modes = modes

	var path := "%s/%s.tres" % [WEAPON_DIR, e.id]
	var err := ResourceSaver.save(w, path)
	if err != OK:
		push_error("Konnte %s nicht speichern (Fehler %d)" % [path, err])
		return false
	print("  Waffe     ", path)
	return true
