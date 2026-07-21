## Profil bearbeiten: Bild und Name.
##
## Aufgerufen per Klick auf das Profil-Abzeichen im Hauptmenü (siehe
## scripts/ui/main_menu.gd). Speichert über PlayerProfile — reine Vorliebe,
## kein Spielstand, siehe dort.
##
## BILD: Klick auf das Abzeichen öffnet einen echten, systemeigenen
## Datei-Dialog (FileDialog, ACCESS_FILESYSTEM, use_native_dialog) — der
## Spieler sieht alle Ordner auf seinem PC, ausgewählt wird trotzdem nur, was
## sich als Bild lesen lässt. Danach folgt ein Zuschnitt-Editor: verschieben
## per Ziehen, Größe per Regler, erst "Übernehmen" speichert wirklich.
##
## NAME: Das Namensfeld sieht wie Text aus (durchsichtiger Rahmen), bis man
## draufklickt — dann wird es ein echtes Eingabefeld. Enter oder Wegklicken
## übernimmt die Änderung.
class_name ProfilePanel
extends Control

signal closed()

const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.bmp, *.webp, *.tga ; Bilddateien"

## Kantenlänge des quadratischen Ausschnitt-Rahmens im Editor, in UI-Pixeln.
const FRAME_SIZE := 260.0

## Wie weit sich über "füllt den Rahmen genau" hinaus hineinzoomen lässt.
const MAX_ZOOM_FACTOR := 4.0

@onready var _close_button: Button = $Panel/Inhalt/Kopf/Schliessen

@onready var _main_view: VBoxContainer = $Panel/Inhalt/MainView
@onready var _avatar_button: Button = $Panel/Inhalt/MainView/AvatarRow/AvatarButton
@onready var _avatar_label: Label = $Panel/Inhalt/MainView/AvatarRow/AvatarButton/AvatarLabel
@onready var _avatar_texture: TextureRect = $Panel/Inhalt/MainView/AvatarRow/AvatarButton/AvatarTexture
@onready var _status_label: Label = $Panel/Inhalt/MainView/Status
@onready var _name_edit: LineEdit = $Panel/Inhalt/MainView/NameEdit

@onready var _editor_view: VBoxContainer = $Panel/Inhalt/EditorView
@onready var _frame: Control = $Panel/Inhalt/EditorView/RahmenBox/Rahmen
@onready var _preview: TextureRect = $Panel/Inhalt/EditorView/RahmenBox/Rahmen/Vorschau
@onready var _zoom_slider: HSlider = $Panel/Inhalt/EditorView/ZoomRow/Slider
@onready var _accept_button: Button = $Panel/Inhalt/EditorView/Knoepfe/Uebernehmen
@onready var _cancel_button: Button = $Panel/Inhalt/EditorView/Knoepfe/Abbrechen

var _file_dialog: FileDialog

## Das volle, ungeschnittene Bild, waehrend der Editor offen ist.
var _editor_image: Image = null


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_avatar_button.pressed.connect(_on_avatar_pressed)

	_name_edit.editable = false
	_name_edit.gui_input.connect(_on_name_gui_input)
	_name_edit.focus_exited.connect(_commit_name)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _commit_name())

	_frame.clip_contents = true
	_preview.gui_input.connect(_on_preview_gui_input)
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_accept_button.pressed.connect(_on_accept_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_editor_view.hide()

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	# Der native Dialog des Betriebssystems statt Godots eigener Oberflaeche:
	# zeigt wirklich alle Ordner so, wie der Spieler es von Windows kennt, und
	# das Betriebssystem selbst hilft, den Filter durchzusetzen.
	_file_dialog.use_native_dialog = true
	_file_dialog.title = "Profilbild waehlen"
	_file_dialog.size = Vector2i(760, 500)
	_file_dialog.filters = PackedStringArray([IMAGE_FILTER])
	_file_dialog.file_selected.connect(_on_avatar_file_selected)
	add_child(_file_dialog)


func open() -> void:
	_refresh()
	_close_editor()
	show()


func _refresh() -> void:
	_name_edit.text = PlayerProfile.get_display_name()
	_status_label.text = ""
	_update_avatar_display(PlayerProfile.load_avatar_texture())


func _update_avatar_display(texture: ImageTexture) -> void:
	if texture != null:
		_avatar_texture.texture = texture
		_avatar_texture.show()
		_avatar_label.hide()
	else:
		_avatar_texture.hide()
		_avatar_label.show()


func _on_close_pressed() -> void:
	# Eine offene Bearbeitung wird verworfen, kein Name-Feld bleibt haengen.
	_close_editor()
	if _name_edit.editable:
		_commit_name()
	hide()
	closed.emit()


func _on_avatar_pressed() -> void:
	_status_label.text = ""
	_file_dialog.popup_centered()


# ---------------------------------------------------------------------------
# Bildauswahl und Zuschnitt-Editor
#
# Nur die Datei-Endung zu pruefen reicht nicht — eine .png, die in
# Wirklichkeit keine ist, wuerde sonst als "Fehlerdaten" im Profil landen.
# Image.load() selbst entscheidet, ob sich etwas als Bild lesen laesst.
# ---------------------------------------------------------------------------

func _on_avatar_file_selected(path: String) -> void:
	var extension := path.get_extension().to_lower()
	if not PlayerProfile.IMAGE_EXTENSIONS.has(extension):
		_status_label.text = "Das ist keine Bilddatei."
		return

	var image := Image.new()
	if image.load(path) != OK:
		_status_label.text = "Konnte die Datei nicht als Bild lesen."
		return

	_open_editor(image)


func _open_editor(image: Image) -> void:
	_editor_image = image
	_preview.texture = ImageTexture.create_from_image(image)
	# "Rahmen" ist ein einfaches Control, kein Container — die Vorschau
	# bekommt ihre Grundgroesse deshalb nicht automatisch von ihrer Textur,
	# sie muss von Hand auf die Bildgroesse gesetzt werden. scale zoomt von
	# hier aus weiter.
	_preview.size = Vector2(image.get_width(), image.get_height())

	# Nie kleiner zoomen, als noetig ist, um den Rahmen ganz zu fuellen —
	# sonst blieben Luecken am Rand statt eines Fotos.
	var fill_zoom := maxf(
		FRAME_SIZE / float(image.get_width()),
		FRAME_SIZE / float(image.get_height())
	)
	_zoom_slider.min_value = fill_zoom
	_zoom_slider.max_value = fill_zoom * MAX_ZOOM_FACTOR
	_zoom_slider.value = fill_zoom

	_preview.scale = Vector2.ONE * fill_zoom
	_center_preview()

	_main_view.hide()
	_editor_view.show()


func _center_preview() -> void:
	var scaled := Vector2(_editor_image.get_width(), _editor_image.get_height()) * _preview.scale.x
	_preview.position = (Vector2(FRAME_SIZE, FRAME_SIZE) - scaled) * 0.5


## Zoomt um den Punkt, der gerade in der Rahmenmitte liegt, statt die Anzeige
## bei jedem Reglerschritt neu zu zentrieren — fuehlt sich sonst an, als
## spraenge das Bild beim Ziehen des Reglers hin und her.
func _on_zoom_changed(new_zoom: float) -> void:
	if _editor_image == null:
		return
	var old_zoom := _preview.scale.x
	var frame_centre := Vector2(FRAME_SIZE, FRAME_SIZE) * 0.5
	var image_point := (frame_centre - _preview.position) / old_zoom

	_preview.scale = Vector2.ONE * new_zoom
	_preview.position = frame_centre - image_point * new_zoom
	_clamp_preview_position()


func _on_preview_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
		return
	_preview.position += motion.relative
	_clamp_preview_position()


## Haelt das Bild so, dass es den Rahmen immer ganz ausfuellt — sonst liesse
## sich der Ausschnitt an den Rand ziehen, bis dort nur noch Leerflaeche steht.
func _clamp_preview_position() -> void:
	var scaled := Vector2(_editor_image.get_width(), _editor_image.get_height()) * _preview.scale.x
	var min_position := Vector2(FRAME_SIZE, FRAME_SIZE) - scaled
	_preview.position = Vector2(
		clampf(_preview.position.x, min_position.x, 0.0),
		clampf(_preview.position.y, min_position.y, 0.0),
	)


func _on_accept_pressed() -> void:
	if _editor_image == null:
		return

	var zoom := _preview.scale.x
	var top_left := (Vector2.ZERO - _preview.position) / zoom
	var size := Vector2(FRAME_SIZE, FRAME_SIZE) / zoom
	var crop := Rect2i(
		Vector2i(roundi(top_left.x), roundi(top_left.y)),
		Vector2i(roundi(size.x), roundi(size.y)),
	)
	# Rundung kann den Ausschnitt um ein, zwei Pixel ueber den Bildrand
	# schieben — auf das tatsaechliche Bild begrenzen, statt dass get_region()
	# daran scheitert.
	crop = crop.intersection(Rect2i(Vector2i.ZERO, _editor_image.get_size()))

	var texture := PlayerProfile.save_avatar_image(_editor_image.get_region(crop))
	_update_avatar_display(texture)
	_close_editor()


func _on_cancel_pressed() -> void:
	_close_editor()


func _close_editor() -> void:
	_editor_image = null
	_preview.texture = null
	_editor_view.hide()
	_main_view.show()


# ---------------------------------------------------------------------------
# Name
# ---------------------------------------------------------------------------

func _on_name_gui_input(event: InputEvent) -> void:
	if _name_edit.editable:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	_name_edit.editable = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func _commit_name() -> void:
	if not _name_edit.editable:
		return
	_name_edit.editable = false
	PlayerProfile.set_display_name(_name_edit.text)
	# Falls der Name leer war (PlayerProfile.set_display_name ignoriert das),
	# zeigt das Feld wieder den zuletzt gespeicherten Namen statt leer zu bleiben.
	_name_edit.text = PlayerProfile.get_display_name()
