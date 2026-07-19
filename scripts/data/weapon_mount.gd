## Eine Aufnahme an einer Waffe: wo ein Anbauteil sitzt und was es ersetzt.
##
## Steht als Liste in der .tres der Waffe. Damit entscheiden die Daten, welche
## Waffe welche Steckplätze hat — eine Pistole bekommt schlicht keinen
## Vordergriff-Eintrag, und niemand muss das im Code abfragen.
class_name WeaponMount
extends Resource

@export var slot: AttachmentData.Slot = AttachmentData.Slot.SIGHT

## Welche Teile hier passen. Muss exakt mit AttachmentData.interface_tag
## übereinstimmen, z.B. &"picatinny" oder &"thread_1_2x28".
@export var interface_tag: StringName = &""

## Name des Knotens im Waffenmodell, an den das Teil gehängt wird,
## z.B. &"MountSight".
##
## Wird der Knoten nicht gefunden, verschwindet das Anbauteil stillschweigend.
## Genau deshalb prüft verify_weapon_handling, dass jeder hier genannte Name
## im gebauten Modell wirklich existiert.
@export var anchor: StringName = &""

## Eingebaute Teile, die verschwinden, sobald hier etwas montiert ist.
##
## Beispiel Visier-Aufnahme: ["RearSight", "FrontSight"] — die Notvisierung
## klappt weg, sobald eine Optik draufsitzt. Die Knoten werden nur unsichtbar
## geschaltet, nicht gelöscht: Sie kommen beim Abnehmen zurück, und die
## Teilesuche des Viewmodels findet weiterhin alles.
@export var hides: Array[StringName] = []


func validate() -> Array[String]:
	var problems: Array[String] = []
	if interface_tag == &"":
		problems.append("interface_tag ist leer — hier passt nichts hinein")
	if anchor == &"":
		problems.append("anchor ist leer — das Teil hätte keinen Platz")
	return problems
