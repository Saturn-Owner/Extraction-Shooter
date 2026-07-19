## Ein Anbauteil für eine Waffe: Visier, Mündungsaufsatz, Griff, Vordergriff.
##
## Wie alles andere im Spiel eine eigene .tres-Datei unter assets/data/.
## Ein neues Visier ist eine neue Datei, kein neuer Code (Grundsatz 1).
##
## KOMPATIBILITÄT LÄUFT ÜBER SCHNITTSTELLEN, NICHT ÜBER WAFFENLISTEN.
## Das Teil verlangt eine Aufnahme (`interface_tag`), die Waffe bietet welche an.
## Dadurch erbt jede neue Waffe mit Picatinny-Schiene sofort das komplette
## vorhandene Visiersortiment — ohne dass eine einzige Datei angefasst wird.
## Eine Liste erlaubter Waffen-IDs müsste man dagegen bei jeder neuen Waffe
## in jedem Anbauteil nachpflegen.
class_name AttachmentData
extends ItemData

## An welcher Stelle der Waffe das Teil sitzt.
## Pro Steckplatz kann immer nur EIN Teil montiert sein.
## Neue Werte hinten anhängen — die .tres speichern die Zahl, nicht den Namen.
enum Slot {
	SIGHT,     ## Kimme/Korn, Rotpunkt, Zielfernrohr
	MUZZLE,    ## Mündungsbremse, Kompensator, Schalldämpfer
	GRIP,      ## Pistolengriff
	FOREGRIP,  ## Vordergriff am Handschutz
}

@export var slot: Slot = Slot.SIGHT

## Welche Aufnahme das Teil braucht, z.B. &"picatinny" oder &"thread_1_2x28".
## Muss exakt mit WeaponMount.interface_tag übereinstimmen.
@export var interface_tag: StringName = &""

## Das sichtbare Modell dieses Teils, abgeleitet von AttachmentViewmodel.
##
## Wie bei den Waffen bekommt jedes Teil seine eigene Datei unter
## scripts/attachments/ (Grundsatz 5). Bleibt das Feld leer, wird nichts
## angebaut — die Werte wirken trotzdem. Das ist bewusst erlaubt, damit man
## ein Teil erst durchbalancieren und danach modellieren kann.
@export var viewmodel_part: Script

@export_group("Rückstoß & Handling")

## Faktor auf den Rückstoß. Unter 1.0 macht die Waffe ruhiger.
@export_range(0.4, 1.6) var recoil_vertical_mult: float = 1.0
@export_range(0.4, 1.6) var recoil_horizontal_mult: float = 1.0

## Aufschlag auf die Ergonomie. Negativ = sperriger.
## Ergonomie steuert Zielgeschwindigkeit und Nachladezeit.
@export_range(-40, 40) var ergonomics_delta: int = 0

## Faktor auf die Streuung. Unter 1.0 ist präziser.
@export_range(0.3, 2.0) var accuracy_moa_mult: float = 1.0

@export_group("Zielen")

## Faktor auf die Zeit bis die Visierlinie steht. Über 1.0 ist langsamer —
## ein schweres Zielfernrohr kommt später ans Auge.
@export_range(0.5, 2.5) var ads_time_mult: float = 1.0

## Faktor auf die Streuung im Anschlag.
@export_range(0.2, 1.5) var ads_spread_mult: float = 1.0

## Faktor auf das Tempo im Anschlag.
@export_range(0.5, 1.5) var ads_move_mult: float = 1.0

## Sichtfeld im Anschlag. 0.0 = unverändert lassen.
##
## Nur Visiere setzen das. Ein Rotpunkt lässt den Wert der Waffe stehen
## (kein Zoom), ein Zielfernrohr zieht ihn deutlich zu.
@export_range(0.0, 75.0) var ads_fov_override: float = 0.0

@export_group("Lauf")

## Aufschlag auf den Mündungsgeschwindigkeits-Faktor der Waffe.
## Ein Schalldämpfer gibt minimal mehr, weil die Gase länger wirken.
@export_range(-0.15, 0.15) var muzzle_velocity_delta: float = 0.0

## Faktor auf die wahrgenommene Lautstärke. Der Schalldämpfer lebt hier.
@export_range(0.1, 1.5) var loudness_mult: float = 1.0


func _init() -> void:
	category = Category.ATTACHMENT


## Kurzer Name des Steckplatzes für Oberfläche und Fehlermeldungen.
static func slot_name(value: Slot) -> String:
	match value:
		Slot.SIGHT:
			return "Visier"
		Slot.MUZZLE:
			return "Mündung"
		Slot.GRIP:
			return "Griff"
		Slot.FOREGRIP:
			return "Vordergriff"
	return "?"


## Ob dieses Teil überhaupt etwas an den Werten ändert.
## Rein optische Teile sind erlaubt, aber meistens ein Versehen.
func changes_stats() -> bool:
	return not (
		is_equal_approx(recoil_vertical_mult, 1.0)
		and is_equal_approx(recoil_horizontal_mult, 1.0)
		and ergonomics_delta == 0
		and is_equal_approx(accuracy_moa_mult, 1.0)
		and is_equal_approx(ads_time_mult, 1.0)
		and is_equal_approx(ads_spread_mult, 1.0)
		and is_equal_approx(ads_move_mult, 1.0)
		and is_zero_approx(ads_fov_override)
		and is_zero_approx(muzzle_velocity_delta)
		and is_equal_approx(loudness_mult, 1.0)
	)


func validate() -> Array[String]:
	var problems := super()
	if interface_tag == &"":
		problems.append("interface_tag ist leer — das Teil passt an keine Waffe")
	if category != Category.ATTACHMENT:
		problems.append("category sollte ATTACHMENT sein")
	# Zoom gehört ans Visier. An einer Mündung wäre er ein Tippfehler.
	if not is_zero_approx(ads_fov_override) and slot != Slot.SIGHT:
		problems.append("ads_fov_override nur bei Visieren sinnvoll")
	return problems
