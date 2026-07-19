## Ein Ausgang aus dem Raid.
##
## Der Spieler muss eine Zeit lang IM Bereich bleiben. Verlässt er ihn,
## läuft der Zähler zurück — nicht auf null, aber spürbar.
##
## Warum ein Timer und kein sofortiges Verlassen:
## Der Moment am Ausgang ist der spannendste im Genre. Man steht mit voller
## Beute still, ist verwundbar, und weiss nicht, ob jemand zusieht. Ohne
## Wartezeit wäre Extraction eine Formsache statt einer Entscheidung.
##
## Manche Ausgänge verlangen Ausrüstung — das ist der Haken für die
## vereisten Wände und den Eispickel aus dem Konzept. Wer ihn nicht dabei
## hat, muss den langen, gefährlichen Weg nehmen.
class_name ExtractionZone
extends Area3D

signal extraction_started()
signal extraction_progress(ratio: float)
signal extraction_interrupted(reason: String)
signal extraction_complete(player: Node)

## Wie lange der Spieler im Bereich bleiben muss.
@export var required_time: float = 8.0

## Wie schnell der Fortschritt zurückläuft, wenn man den Bereich verlässt.
## Bewusst langsamer als der Aufbau: kurz in Deckung springen soll erlaubt
## sein, dauerhaft weglaufen nicht.
@export var decay_rate: float = 0.5

## Item, das der Spieler dabeihaben muss. Leer = für alle offen.
@export var required_item_id: StringName = &""

## Wird das Item beim Extrahieren verbraucht?
@export var consumes_item: bool = false

@export var display_name: String = "Ausgang"

## Ob dieser Ausgang gerade nutzbar ist. Später zeitabhängig oder an
## Bedingungen geknüpft (nur nachts, nur wenn der Generator läuft).
@export var is_open: bool = true

var progress: float = 0.0
var _player_inside: Node = null
var _completed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("extraction_zone")


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		_player_inside = body
		if is_open and can_use(body):
			extraction_started.emit()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_inside:
		_player_inside = null


## Ob dieser Spieler den Ausgang überhaupt benutzen darf.
func can_use(player: Node) -> bool:
	if required_item_id == &"":
		return true
	var controller := player as PlayerController
	if controller == null or controller.inventory == null:
		return false
	return controller.inventory.grid.count_items(required_item_id, true) > 0


## Warum der Ausgang nicht nutzbar ist — für die Anzeige.
func get_block_reason(player: Node) -> String:
	if not is_open:
		return "geschlossen"
	if can_use(player):
		return ""
	var item := ItemRegistry.get_item(required_item_id)
	var item_name := item.display_name if item != null else String(required_item_id)
	return "benoetigt: %s" % item_name


func _process(delta: float) -> void:
	if _completed:
		return

	var active := _player_inside != null and is_open and can_use(_player_inside)

	if active:
		progress = minf(required_time, progress + delta)
	elif progress > 0.0:
		progress = maxf(0.0, progress - delta * decay_rate)

	extraction_progress.emit(get_ratio())

	if active and progress >= required_time:
		_complete()


func get_ratio() -> float:
	return clampf(progress / maxf(0.01, required_time), 0.0, 1.0)


func _complete() -> void:
	_completed = true
	var player := _player_inside

	if consumes_item and required_item_id != &"":
		var controller := player as PlayerController
		if controller != null and controller.inventory != null:
			controller.inventory.take_ammo(required_item_id, 1)

	extraction_complete.emit(player)


## Für einen neuen Raid zurücksetzen.
func reset() -> void:
	progress = 0.0
	_completed = false
	_player_inside = null
