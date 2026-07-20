## Eine Schusswaffe.
##
## Die Waffe legt fest, WIE geschossen wird (Feuerrate, Rückstoß, Präzision).
## Was der Treffer anrichtet, entscheidet die geladene AmmoData.
## Diese Trennung ist wichtig: Dieselbe Waffe fühlt sich mit anderer Munition
## völlig anders an — genau das wollen wir.
class_name WeaponData
extends ItemData

enum FireMode {
	SINGLE,  ## Einzelfeuer
	BURST,   ## Feuerstoß
	AUTO,    ## Dauerfeuer
}

@export_group("Kaliber & Magazin")

## Muss exakt mit AmmoData.caliber übereinstimmen, z.B. "5.56x45".
@export var caliber: StringName = &"5.56x45"

## Standard-Magazingröße ohne Modifikationen.
@export_range(1, 200) var magazine_size: int = 30

## Welche Feuermodi die Waffe beherrscht.
@export var fire_modes: Array[FireMode] = [FireMode.SINGLE, FireMode.AUTO]

@export_group("Feuerverhalten")

## Schuss pro Minute im Dauerfeuer.
@export_range(30, 1400) var fire_rate_rpm: int = 700

## Anzahl Schuss im Feuerstoß-Modus.
@export_range(2, 5) var burst_count: int = 3

## Wie stark der Lauf die Mündungsgeschwindigkeit der Munition verändert.
## 1.0 = Standardlauf. Kurze Läufe (<1.0) verlieren Geschwindigkeit und
## damit auch Durchschlagskraft auf Distanz.
@export_range(0.7, 1.2) var muzzle_velocity_modifier: float = 1.0

@export_group("Rückstoß & Handling")

## Rückstoß nach oben pro Schuss.
@export_range(0.0, 500.0) var recoil_vertical: float = 120.0

## Seitlicher Rückstoß — sorgt dafür, dass Dauerfeuer ausfranst.
@export_range(0.0, 500.0) var recoil_horizontal: float = 40.0

## Ergonomie 0-100. Beeinflusst, wie schnell gezielt wird und wie lange
## der Spieler die Waffe ruhig halten kann. Hoch = handlich.
@export_range(0, 100) var ergonomics: int = 50

## Streuung in Bogenminuten (MOA). Kleiner = präziser.
## Nur bei Präzisionsgewehren wirklich spürbar.
@export_range(0.5, 15.0) var accuracy_moa: float = 3.0

@export_group("Darstellung")

## Das sichtbare Modell dieser Waffe.
##
## GRUNDSATZ: Jede Waffe hat ihr eigenes Modell und ihre eigene Mechanik in
## einer eigenen Datei unter scripts/weapons/, abgeleitet von WeaponViewmodel.
## Es gibt bewusst keine Einheitswaffe mit ausgetauschten Werten — eine
## Pistole hat einen Schlitten, eine Flinte eine Pumpe, ein Sturmgewehr einen
## Verschluss. Das sind unterschiedliche Bewegungen.
##
## Bleibt das Feld leer, greift GenericViewmodel als sichtbarer Platzhalter,
## damit die Waffe spielbar bleibt statt unsichtbar zu sein.
@export var viewmodel: Script

@export_group("Anbauteile")

## Welche Steckplätze diese Waffe anbietet.
##
## Die Daten entscheiden, was montierbar ist: Eine Pistole bekommt schlicht
## keinen Vordergriff-Eintrag. Kompatibilität läuft über den interface_tag
## der Aufnahme, nicht über Listen erlaubter Teile — damit erbt eine neue
## Waffe mit Picatinny-Schiene sofort das ganze vorhandene Sortiment.
@export var mounts: Array[WeaponMount] = []

@export_group("Nachladen")

## Magazinwechsel mit Patrone im Lauf. Schneller, weil der Verschluss
## nicht vorgelassen werden muss.
@export_range(0.5, 8.0) var reload_time_tactical: float = 2.3

## Magazinwechsel bei leergeschossener Waffe. Langsamer — der Verschluss
## steht hinten und muss zusaetzlich geloest werden.
@export_range(0.5, 10.0) var reload_time_empty: float = 3.1

## Wie lange das Beheben einer Ladehemmung dauert.
@export_range(0.5, 8.0) var jam_clear_time: float = 1.7

@export_group("Zielen")

## Sichtfeld beim Zielen ueber Kimme und Korn. Kleiner = mehr Zoom.
@export_range(20.0, 75.0) var ads_fov: float = 52.0

## Wieviel Streuung beim Zielen uebrig bleibt.
@export_range(0.05, 1.0) var ads_spread_multiplier: float = 0.35

## Wie stark das Zielen bremst (0.6 = 60 % Tempo).
@export_range(0.2, 1.0) var ads_move_multiplier: float = 0.62

## Faktor auf die Zeit, bis die Visierlinie steht. Über 1.0 ist träger.
##
## Existiert, damit Anbauteile daran drehen können: Ein schweres Zielfernrohr
## kommt spürbar später ans Auge als ein Rotpunkt. Ohne Anbauteile bleibt der
## Wert bei 1.0 und ändert nichts.
@export_range(0.5, 2.5) var ads_time_multiplier: float = 1.0

@export_group("Signatur")

## Faktor auf die wahrgenommene Lautstärke. Der Schalldämpfer lebt hier.
##
## Ohne diesen Wert würde die Lautstärke allein aus dem Rückstoß abgeleitet —
## ein Schalldämpfer wäre dann nur leiser, weil er die Waffe ruhiger macht,
## und das ist der falsche Zusammenhang.
@export_range(0.1, 1.5) var loudness_multiplier: float = 1.0

@export_group("Zustand")

## Wie schnell die Waffe verschleißt. Abgenutzte Waffen sollen
## öfter Ladehemmungen haben — Arbeit für die Werkstatt.
@export_range(0.0, 5.0) var wear_per_shot: float = 0.01

## Grundwahrscheinlichkeit einer Ladehemmung bei perfektem Zustand.
@export_range(0.0, 0.5) var base_jam_chance: float = 0.001


## Zeit zwischen zwei Schüssen in Sekunden.
func get_shot_interval() -> float:
	return 60.0 / float(fire_rate_rpm)


## Wie lange ein Magazinwechsel dauert.
##
## Die Ergonomie zieht die Zeit spürbar zusammen: Eine handliche Waffe
## (Ergonomie 100) lädt rund 20 % schneller nach als eine sperrige (0).
## Damit ist Ergonomie nicht nur eine Zahl im Datenblatt, sondern etwas,
## das man im Gefecht merkt.
func get_reload_duration(from_empty: bool) -> float:
	var base := reload_time_empty if from_empty else reload_time_tactical
	var ergonomics_factor := 1.1 - 0.2 * (float(ergonomics) / 100.0)
	return base * ergonomics_factor


## Effektive Mündungsgeschwindigkeit mit dieser Munition.
func get_muzzle_velocity(ammo: AmmoData) -> float:
	return ammo.muzzle_velocity_ms * muzzle_velocity_modifier


## Ob diese Munition in diese Waffe passt.
func accepts_ammo(ammo: AmmoData) -> bool:
	return ammo.caliber == caliber


## Die Aufnahme für einen Steckplatz, oder null wenn die Waffe ihn nicht hat.
func find_mount(slot: AttachmentData.Slot) -> WeaponMount:
	for mount in mounts:
		if mount != null and mount.slot == slot:
			return mount
	return null


## Ob dieses Anbauteil an diese Waffe passt.
##
## Zwei Bedingungen: Die Waffe muss den Steckplatz überhaupt haben, und die
## Aufnahme muss dieselbe Schnittstelle sprechen. Ein Schalldämpfer mit
## 9-mm-Gewinde passt deshalb nicht auf ein 5,56er Gewehr, obwohl beide
## einen Mündungs-Steckplatz haben.
func accepts_attachment(attachment: AttachmentData) -> bool:
	if attachment == null:
		return false
	var mount := find_mount(attachment.slot)
	return mount != null and mount.interface_tag == attachment.interface_tag


## Alle Steckplätze in fester Reihenfolge — für die Oberfläche der Werkbank.
func get_slots() -> Array[AttachmentData.Slot]:
	var result: Array[AttachmentData.Slot] = []
	for slot in [AttachmentData.Slot.SIGHT, AttachmentData.Slot.MUZZLE,
			AttachmentData.Slot.GRIP, AttachmentData.Slot.FOREGRIP]:
		if find_mount(slot) != null:
			result.append(slot)
	return result


## Modell dieser Waffe erzeugen. Faellt auf den Platzhalter zurueck, wenn
## noch kein eigenes gebaut wurde.
func create_viewmodel() -> WeaponViewmodel:
	if viewmodel != null:
		var instance: Object = viewmodel.new()
		if instance is WeaponViewmodel:
			return instance as WeaponViewmodel
		push_error("[WeaponData] %s: viewmodel erbt nicht von WeaponViewmodel" % id)
	return GenericViewmodel.new()


## Ob diese Waffe schon ein eigenes Modell hat.
func has_own_viewmodel() -> bool:
	return viewmodel != null


func get_type_label() -> String:
	return "Waffe  —  %s" % caliber


func get_info_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Magazin:      %d Schuss" % magazine_size)
	lines.append("Feuerrate:    %d /min" % fire_rate_rpm)
	lines.append("Praezision:   %.1f MOA" % accuracy_moa)
	lines.append("Rueckstoss:   %.0f hoch / %.0f seitlich" % [recoil_vertical, recoil_horizontal])
	lines.append("Ergonomie:    %d von 100" % ergonomics)
	lines.append_array(super())
	return lines


func validate() -> Array[String]:
	var problems := super()
	if caliber == &"":
		problems.append("caliber ist leer")
	if fire_modes.is_empty():
		problems.append("fire_modes ist leer — Waffe kann nicht schießen")
	if category != Category.WEAPON:
		problems.append("category sollte WEAPON sein")

	# Doppelte Steckplätze wären zweideutig: find_mount() nähme den ersten,
	# die Oberfläche zeigte zwei — beides falsch, und schwer zu finden.
	var seen := {}
	for mount in mounts:
		if mount == null:
			problems.append("leerer Eintrag in mounts")
			continue
		for problem in mount.validate():
			problems.append("Aufnahme %s: %s" % [AttachmentData.slot_name(mount.slot), problem])
		if seen.has(mount.slot):
			problems.append("Steckplatz %s doppelt vergeben" % AttachmentData.slot_name(mount.slot))
		seen[mount.slot] = true

	return problems
