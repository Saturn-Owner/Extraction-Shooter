## Der helle Schleier, den das eigene Mündungsfeuer ins Bild legt.
##
## Bei Dauerfeuer blitzt es sechzehnmal pro Sekunde eine Handbreit vor dem
## Auge. Das Auge kommt dagegen nicht an — das Bild wäscht aus.
##
## ---------------------------------------------------------------------------
## WARUM EIN OVERLAY UND KEIN GLOW IM ENVIRONMENT
##
## Glow lebt im `WorldEnvironment`, und das steht in der Levelszene. Es wäre
## also erstens eine `.tscn`-Änderung (nicht mergebar, und der Kollege arbeitet
## an der Datei), zweitens global — es verstärkt jede helle Stelle im ganzen
## Level dauerhaft, nicht nur beim Schiessen —, und drittens müsste man es in
## jedem künftigen Level erneut einstellen.
##
## Ein Overlay ist dagegen eine Zahl, die man prüfen kann, und lässt das Level
## unangetastet. Glow kann später als Verfeinerung dazukommen.
##
## Wird im Code gebaut, wie die Werkbank-Oberfläche auch.
class_name BlastOverlay
extends CanvasLayer

## Farbe des Mündungsfeuers. Bewusst dieselbe wie beim Blitz selbst, damit man
## Ursache und Wirkung als zusammengehörig erkennt.
const COLOR := Color(1.0, 0.82, 0.45)

## Schicht 0 — UNTER allem anderen.
##
## Das Debug-HUD des Testgeländes liegt auf 1, die Werkbank auf 10. Läge der
## Schleier darüber, wäre beim Dauerfeuer ausgerechnet die Munitionsanzeige
## überstrahlt, und die Werkbank blinkte beim Umbauen mit.
const LAYER := 0

var _rect: TextureRect


func _ready() -> void:
	layer = LAYER
	_build()
	set_alpha(0.0)


func _build() -> void:
	_rect = TextureRect.new()
	_rect.name = "Schleier"
	_rect.texture = _make_texture()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE

	# OHNE DAS FRISST DER SCHLEIER JEDEN MAUSKLICK. Ein Vollbild-Control liegt
	# über allem und fängt die Maus ab — die Werkbank wäre ab dem ersten
	# Dauerfeuer unbedienbar, und niemand käme auf den Zusammenhang.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Additiv: Der Blitz FÜGT Licht HINZU, er legt keine Farbe darüber.
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_rect.material = material

	add_child(_rect)


## Radialer Verlauf: in der Bildmitte hell, zu den Rändern auslaufend.
##
## Das Mündungsfeuer sitzt vor der Waffe, also ungefähr dort, wo man hinschaut.
## Ein gleichmässig heller Schleier über das ganze Bild sähe aus wie ein
## Weissabgleichfehler, nicht wie Blendung.
func _make_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		COLOR,
		Color(COLOR.r, COLOR.g, COLOR.b, 0.55),
		Color(COLOR.r, COLOR.g, COLOR.b, 0.0),
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture


## Deckkraft setzen, 0 bis 1.
func set_alpha(alpha: float) -> void:
	if _rect == null:
		return
	_rect.modulate.a = clampf(alpha, 0.0, 1.0)
	# Bei null gar nicht erst zeichnen — ein unsichtbares Vollbild-Control
	# kostet sonst bei jedem Bild Füllrate für nichts.
	_rect.visible = _rect.modulate.a > 0.001


func get_alpha() -> float:
	return _rect.modulate.a if _rect != null else 0.0
