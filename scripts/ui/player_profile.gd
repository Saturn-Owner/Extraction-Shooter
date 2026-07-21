## Name und Profilbild des Spielers — reine Anzeigesache, kein Spielzustand.
##
## Liegt bewusst getrennt vom Lager/Spielstand (siehe RaidManager.to_dict()):
## Das hier ist eine Puffer-Datei für Vorlieben (wie eine Einstellung), keine
## Fortschrittsdaten, die verloren gehen dürfen. Darum genügt eine einfache
## ConfigFile unter user://, ohne auf ein richtiges Speichersystem zu warten.
##
## Das Profilbild wird beim Auswählen nach user://profile_avatar.png kopiert,
## nicht am Originalpfad referenziert — sonst würde das Bild verschwinden,
## sobald der Spieler die Originaldatei verschiebt oder löscht.
class_name PlayerProfile
extends RefCounted

const CONFIG_PATH := "user://profile.cfg"
const AVATAR_PATH := "user://profile_avatar.png"
const DEFAULT_NAME := "GHOST-04"

const SECTION := "profile"
const KEY_NAME := "name"

## Erlaubte Bildformate — was Godots Image.load() lesen kann.
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "bmp", "webp", "tga"]


## config_path ist ueberschreibbar, damit Tests eine eigene Datei benutzen
## koennen, statt das echte Profil auf der Testmaschine zu ueberschreiben.
static func get_display_name(config_path: String = CONFIG_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return DEFAULT_NAME
	return config.get_value(SECTION, KEY_NAME, DEFAULT_NAME)


## Leerer Name wird ignoriert — sonst stuende irgendwann niemand mehr im
## Profil, ohne dass ersichtlich waere, warum.
static func set_display_name(new_name: String, config_path: String = CONFIG_PATH) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty():
		return

	var config := ConfigFile.new()
	config.load(config_path)
	config.set_value(SECTION, KEY_NAME, new_name)
	config.save(config_path)


static func has_custom_avatar(avatar_path: String = AVATAR_PATH) -> bool:
	return FileAccess.file_exists(avatar_path)


## Lädt das gespeicherte Profilbild, oder null ohne eines.
static func load_avatar_texture(avatar_path: String = AVATAR_PATH) -> ImageTexture:
	if not has_custom_avatar(avatar_path):
		return null
	var image := Image.new()
	if image.load(avatar_path) != OK:
		return null
	return ImageTexture.create_from_image(image)


## Höchste Kantenlänge, die gespeichert wird — größer ist nur verschwendeter
## Speicher, das Abzeichen zeigt es ohnehin nur bei 52x52 Pixeln.
const MAX_AVATAR_SIZE := 256


## Kopiert das gewählte Bild ins Profil, mittig quadratisch zugeschnitten.
## Für den Fall, dass kein Zuschnitt-Editor dazwischenhängt (z. B. Tests).
## Gibt die geladene Textur zurück, oder null, wenn die Datei sich nicht als
## Bild lesen liess.
static func set_avatar_from_file(source_path: String, avatar_path: String = AVATAR_PATH) -> ImageTexture:
	var image := Image.new()
	if image.load(source_path) != OK:
		return null

	var side: int = mini(image.get_width(), image.get_height())
	var x := (image.get_width() - side) / 2
	var y := (image.get_height() - side) / 2
	return save_avatar_image(image.get_region(Rect2i(x, y, side, side)), avatar_path)


## Speichert ein bereits zugeschnittenes Bild als Profilbild — der Weg vom
## interaktiven Zuschnitt-Editor in ProfilePanel (ausschneiden + skalieren
## übernimmt der Editor, hier wird nur noch verkleinert und gespeichert).
static func save_avatar_image(image: Image, avatar_path: String = AVATAR_PATH) -> ImageTexture:
	if image.get_width() > MAX_AVATAR_SIZE or image.get_height() > MAX_AVATAR_SIZE:
		image.resize(MAX_AVATAR_SIZE, MAX_AVATAR_SIZE, Image.INTERPOLATE_LANCZOS)

	if image.save_png(avatar_path) != OK:
		return null
	return ImageTexture.create_from_image(image)
