## Erzeugt die Anbauteile als .tres und traegt die Aufnahmen in die Waffen ein.
##
##   godot --headless --path . --script res://tools/generate_attachments.gd
##
## ACHTUNG — EINMAL-WERKZEUG, wie generate_arsenal.gd:
## Nach dem Erzeugen sind die .tres die Wahrheit, nicht diese Tabelle. Wer hier
## nochmal draufdrueckt, ueberschreibt alles, was inzwischen nachbalanciert
## wurde. Zum Aendern also die .tres bearbeiten.
##
## ---------------------------------------------------------------------------
## BALANCING-GRUNDGEDANKE
##
## Jedes Teil kostet etwas. Es gibt bewusst kein Teil, das nur Vorteile hat —
## sonst waere die Werkbank keine Entscheidung, sondern eine Einkaufsliste.
##
##   Schalldaempfer  leise und ruhig, dafuer sperrig und langsam am Auge
##   Kompensator     weniger Hochschlag, dafuer lauter
##   Zielfernrohr    praezise auf Distanz, dafuer traege und langsam
##   Rotpunkt        schneller am Auge, sonst neutral
##   Vordergriffe    senkrecht daempft Hochschlag, schraeg das Ausfransen
##
## Die Schnittstellen-Tags entscheiden, was wohin passt. Ein 9-mm-Daempfer
## geht deshalb nicht auf ein 5,56er Gewehr, obwohl beide ein Gewinde haben.
extends SceneTree

const DIR := "res://assets/data/attachments"

const SIGHT := AttachmentData.Slot.SIGHT
const MUZZLE := AttachmentData.Slot.MUZZLE
const GRIP := AttachmentData.Slot.GRIP
const FOREGRIP := AttachmentData.Slot.FOREGRIP

## id, Name, Steckplatz, Schnittstelle, Gewicht, Preis, Rasterbreite/-hoehe,
## danach die Abweichungen vom Neutralwert.
const ATTACHMENTS := [
	# --- Visiere -------------------------------------------------------------
	{id = "sight_reddot", name = "Rotpunktvisier", slot = SIGHT, tag = "picatinny",
		w = 0.18, price = 11500, gw = 2, gh = 1, ergo = 3, ads_time = 0.88,
		desc = "Beide Augen auf, Punkt drauf, fertig. Kein Zoom - dafuer bist du schneller im Ziel als mit jedem Fernrohr."},
	{id = "sight_scope4x", name = "Zielfernrohr 4x", slot = SIGHT, tag = "picatinny",
		w = 0.42, price = 28000, gw = 2, gh = 1, ergo = -7, ads_time = 1.35,
		fov = 22.0, moa = 0.88, ads_move = 0.85,
		desc = "Holt weit entfernte Ziele heran. Auf kurze Distanz ist es eine Klobrille - du siehst nur noch einen Ausschnitt."},
	{id = "sight_micro_dot", name = "Mini-Rotpunkt", slot = SIGHT, tag = "pistol_dot",
		w = 0.06, price = 9400, gw = 1, gh = 1, ergo = 4, ads_time = 0.85,
		desc = "Winziger Punkt auf dem Schlitten. Nimmt der Pistole ihre groesste Schwaeche: die kurze Visierlinie."},

	# --- Muendung ------------------------------------------------------------
	{id = "muzzle_comp_556", name = "Kompensator 5,56", slot = MUZZLE, tag = "thread_556",
		w = 0.11, price = 7800, gw = 1, gh = 1, ergo = -2,
		rec_v = 0.80, rec_h = 0.90, loud = 1.20,
		desc = "Leitet Gase nach oben ab und drueckt die Muendung runter. Der Nachbar hoert dich dafuer doppelt so gut."},
	{id = "muzzle_suppressor_556", name = "Schalldaempfer 5,56", slot = MUZZLE, tag = "thread_556",
		w = 0.46, price = 34000, gw = 2, gh = 1, ergo = -9,
		rec_v = 0.88, rec_h = 0.94, loud = 0.32, v0 = 0.03, ads_time = 1.12,
		desc = "Macht dich schwer zu orten. Lang, schwer und kopflastig - die Waffe kommt spuerbar traeger ans Auge."},
	{id = "muzzle_suppressor_9mm", name = "Schalldaempfer 9 mm", slot = MUZZLE, tag = "thread_9mm",
		w = 0.28, price = 21000, gw = 2, gh = 1, ergo = -7,
		rec_v = 0.90, loud = 0.28, v0 = 0.02, ads_time = 1.10,
		desc = "Unterschallmunition vorausgesetzt, hoert man davon fast nichts. An der Pistole faellt das Gewicht sofort auf."},
	{id = "muzzle_choke_12", name = "Wuergebohrung", slot = MUZZLE, tag = "choke_12",
		w = 0.09, price = 5200, gw = 1, gh = 1, ergo = -1, moa = 0.72,
		desc = "Verengt den Lauf am Ende und haelt die Schrotgarbe laenger zusammen. Auf Distanz der Unterschied zwischen Treffer und Streuung."},

	# --- Griffe --------------------------------------------------------------
	{id = "grip_rubber", name = "Gummigriff", slot = GRIP, tag = "ar15_grip",
		w = 0.08, price = 3400, gw = 1, gh = 1, ergo = 5, rec_v = 0.95,
		desc = "Weiche Gummiauflage. Schluckt einen Teil des Stosses und rutscht auch mit nassen Haenden nicht."},
	{id = "grip_target", name = "Zielgriff", slot = GRIP, tag = "ar15_grip",
		w = 0.10, price = 6100, gw = 1, gh = 1, ergo = 8, ads_time = 0.92,
		desc = "Steiler Winkel, ausgeformte Handauflage. Die Waffe liegt ruhiger und kommt schneller hoch."},

	# --- Vordergriffe --------------------------------------------------------
	{id = "foregrip_vertical", name = "Vordergriff senkrecht", slot = FOREGRIP, tag = "mlok",
		w = 0.13, price = 4800, gw = 1, gh = 2, ergo = -3,
		rec_v = 0.86, ads_move = 0.95,
		desc = "Fest zupacken und die Muendung runterziehen. Gegen Hochschlag das Beste, was es gibt - dafuer sperrig."},
	{id = "foregrip_angled", name = "Winkelgriff", slot = FOREGRIP, tag = "mlok",
		w = 0.09, price = 4200, gw = 1, gh = 1, ergo = 2,
		rec_h = 0.84, ads_time = 0.94,
		desc = "Flach angeschraegt statt senkrecht. Haelt die Waffe seitlich ruhig, ohne im Weg zu sein."},
]

## Aufnahmen je Waffe: Steckplatz, Schnittstelle, Ankerknoten, ersetzte Teile.
const MOUNTS := {
	"rifle_ar15": [
		{slot = SIGHT, tag = "picatinny", anchor = "MountSight",
			hides = ["RearSight", "FrontSight"]},
		{slot = MUZZLE, tag = "thread_556", anchor = "MountMuzzle",
			hides = ["FlashHider", "HiderRingFront", "HiderRingRear"]},
		{slot = GRIP, tag = "ar15_grip", anchor = "MountGrip",
			hides = ["GripAssembly", "GripTang"]},
		{slot = FOREGRIP, tag = "mlok", anchor = "MountForegrip", hides = []},
	],
	"pistol_g17": [
		{slot = SIGHT, tag = "pistol_dot", anchor = "MountSight",
			hides = ["RearSight", "FrontSight"]},
		{slot = MUZZLE, tag = "thread_9mm", anchor = "MountMuzzle", hides = []},
	],
	"shotgun_m870": [
		{slot = SIGHT, tag = "picatinny", anchor = "MountSight",
			hides = ["RearSight", "FrontSight"]},
		{slot = MUZZLE, tag = "choke_12", anchor = "MountMuzzle", hides = []},
	],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var made := 0
	for entry in ATTACHMENTS:
		if _write_attachment(entry):
			made += 1
	print("%d Anbauteile geschrieben." % made)

	var patched := 0
	for weapon_file in MOUNTS:
		if _patch_weapon(weapon_file, MOUNTS[weapon_file]):
			patched += 1
	print("%d Waffen mit Aufnahmen versehen." % patched)

	quit(0)


func _write_attachment(e: Dictionary) -> bool:
	var a := AttachmentData.new()
	a.id = StringName(e.id)
	a.display_name = e.name
	a.description = e.get("desc", "")
	a.category = ItemData.Category.ATTACHMENT
	a.slot = e.slot
	a.interface_tag = StringName(e.tag)
	a.grid_width = e.get("gw", 1)
	a.grid_height = e.get("gh", 1)
	a.weight_kg = e.w
	a.base_price = e.price
	a.max_stack = 1

	a.ergonomics_delta = e.get("ergo", 0)
	a.recoil_vertical_mult = e.get("rec_v", 1.0)
	a.recoil_horizontal_mult = e.get("rec_h", 1.0)
	a.accuracy_moa_mult = e.get("moa", 1.0)
	a.ads_time_mult = e.get("ads_time", 1.0)
	a.ads_spread_mult = e.get("ads_spread", 1.0)
	a.ads_move_mult = e.get("ads_move", 1.0)
	a.ads_fov_override = e.get("fov", 0.0)
	a.muzzle_velocity_delta = e.get("v0", 0.0)
	a.loudness_mult = e.get("loud", 1.0)

	var problems := a.validate()
	if not problems.is_empty():
		push_error("[%s] %s" % [e.id, ", ".join(problems)])
		return false

	var path := "%s/%s.tres" % [DIR, e.id]
	var err := ResourceSaver.save(a, path)
	if err != OK:
		push_error("Konnte %s nicht speichern (%d)" % [path, err])
		return false
	return true


## Traegt die Aufnahmen in eine vorhandene Waffen-.tres ein.
##
## Bewusst laden und zurueckspeichern statt neu erzeugen: Alle bereits von
## Hand nachbalancierten Werte bleiben so erhalten.
func _patch_weapon(file_name: String, mount_specs: Array) -> bool:
	var path := "res://assets/data/weapons/%s.tres" % file_name
	var weapon := ResourceLoader.load(path) as WeaponData
	if weapon == null:
		push_error("Waffe nicht gefunden: %s" % path)
		return false

	var mounts: Array[WeaponMount] = []
	for spec in mount_specs:
		var mount := WeaponMount.new()
		mount.slot = spec.slot
		mount.interface_tag = StringName(spec.tag)
		mount.anchor = StringName(spec.anchor)
		var hides: Array[StringName] = []
		for name in spec.hides:
			hides.append(StringName(name))
		mount.hides = hides
		mounts.append(mount)

	weapon.mounts = mounts

	var problems := weapon.validate()
	if not problems.is_empty():
		push_error("[%s] %s" % [file_name, ", ".join(problems)])
		return false

	var err := ResourceSaver.save(weapon, path)
	if err != OK:
		push_error("Konnte %s nicht speichern (%d)" % [path, err])
		return false
	return true
