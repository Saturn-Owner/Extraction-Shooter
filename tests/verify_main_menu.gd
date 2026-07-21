## Prüft das Hauptmenü: Szenen laden sauber, alle vier Menüpunkte öffnen ihr
## Panel und schliessen es wieder, die Lautstärkeregler wirken auf die echten
## Audio-Busse.
##
##   godot --headless --path . --script res://tests/verify_main_menu.gd
##
## Was hier NICHT geprüft werden kann: ob das Menü gut aussieht, ob die
## Platzhalterfigur sich rund dreht, ob sich die Buttons gut anfuehlen. Das
## muss ein Mensch im Editor ansehen.
##
## Was geprueft WERDEN kann: dass alle Szenen ohne Parserfehler laden, dass
## die Knotenpfade stimmen, die die Skripte per @onready erwarten, dass
## Store/Statistiken ehrlich ein Infofenster zeigen statt erfundene Werte,
## und dass Einstellungen -> Lautstaerke tatsaechlich am AudioServer ankommt.
extends SceneTree

var _failed := 0
var _passed := 0


func _initialize() -> void:
	print("=== Hauptmenue pruefen ===\n")
	_run_all()


func _run_all() -> void:
	await _test_menu_scene()
	await _test_settings_panel()
	_test_player_profile_data()
	await _test_profile_panel()

	print("\n=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  OK     ", label)
	else:
		_failed += 1
		print("  FEHLER ", label)


func _section(title: String) -> void:
	print("\n--- ", title)


# ---------------------------------------------------------------------------

func _test_menu_scene() -> void:
	_section("Hauptmenue-Szene")

	var scene := load("res://scenes/ui/main_menu.tscn") as PackedScene
	_check(scene != null, "Szene laedt")
	if scene == null:
		return

	var menu := scene.instantiate() as MainMenu
	_check(menu != null, "ist ein MainMenu")
	if menu == null:
		return

	root.add_child(menu)
	await process_frame

	var settings := menu.get_node_or_null("SettingsPanel") as SettingsPanel
	var info := menu.get_node_or_null("InfoPanel") as InfoPanel
	_check(settings != null and info != null, "SettingsPanel und InfoPanel haengen im Baum")
	_check(settings != null and not settings.visible, "SettingsPanel faengt versteckt an")
	_check(info != null and not info.visible, "InfoPanel faengt versteckt an")

	var preview_box := menu.get_node_or_null("Vorschau")
	_check(preview_box != null and preview_box.get_child_count() == 1,
		"die 3D-Vorschau wurde eingehaengt")
	_check(preview_box != null and preview_box.get_child(0) is CharacterPreview,
		"und ist eine CharacterPreview")

	var menu_list := menu.get_node_or_null("MenuList") as VBoxContainer
	var spielen := menu.get_node_or_null("MenuList/Spielen/Btn") as Button
	var store := menu.get_node_or_null("MenuList/Store/Btn") as Button
	var statistiken := menu.get_node_or_null("MenuList/Statistiken/Btn") as Button
	var einstellungen := menu.get_node_or_null("MenuList/Einstellungen/Btn") as Button
	_check(spielen != null and store != null and statistiken != null and einstellungen != null,
		"alle vier Buttons stehen im Baum")
	_check(store != null and not store.disabled, "Store ist klickbar (kein toter Knopf)")
	_check(statistiken != null and not statistiken.disabled, "Statistiken ist klickbar")

	# Ueber den echten Schliessen-Knopf, nicht per closed.emit() direkt — sonst
	# wuerde das nur den Zuhoerer in MainMenu ausloesen, ohne dass das Panel
	# sich selbst tatsaechlich versteckt (das passiert erst in
	# InfoPanel._on_close_pressed() / SettingsPanel._on_close_pressed()).
	# Genau dieser Unterschied blieb beim ersten Durchlauf unbemerkt: zwei
	# Panels standen gleichzeitig offen uebereinander.
	var info_close: Button = null
	if info != null:
		info_close = info.get_node_or_null("Panel/Inhalt/Kopf/Schliessen") as Button
	var settings_close: Button = null
	if settings != null:
		settings_close = settings.get_node_or_null("Panel/Inhalt/Kopf/Schliessen") as Button

	if menu_list != null and store != null and info != null and info_close != null:
		store.pressed.emit()
		await process_frame
		_check(not menu_list.visible, "Store blendet die Buttons aus")
		_check(info.visible, "und zeigt das Infofenster")
		_check(not info.get_node("Panel/Inhalt/Text").text.is_empty(),
			"mit erklaerendem Text statt erfundener Werte")

		info_close.pressed.emit()
		await process_frame
		_check(not info.visible, "Schliessen versteckt das Infofenster selbst")
		_check(menu_list.visible, "und zeigt die Buttons wieder")

	if menu_list != null and statistiken != null and info != null and info_close != null:
		statistiken.pressed.emit()
		await process_frame
		_check(info.visible, "Statistiken zeigt ebenfalls das Infofenster")
		info_close.pressed.emit()
		await process_frame
		_check(not info.visible, "und schliesst wieder sauber")

	if menu_list != null and einstellungen != null and settings != null and settings_close != null:
		einstellungen.pressed.emit()
		await process_frame
		_check(not menu_list.visible, "Einstellungen blendet die Buttons aus")
		_check(settings.visible, "und zeigt das echte Panel")

		settings_close.pressed.emit()
		await process_frame
		_check(not settings.visible, "Schliessen versteckt das Settings-Panel selbst")
		_check(menu_list.visible, "und zeigt die Buttons wieder")

	menu.free()


func _test_settings_panel() -> void:
	_section("Lautstaerke wirkt auf den echten Bus")

	var scene := load("res://scenes/ui/settings_panel.tscn") as PackedScene
	_check(scene != null, "Szene laedt")
	if scene == null:
		return

	var panel := scene.instantiate() as SettingsPanel
	root.add_child(panel)
	await process_frame

	var world_bus := AudioServer.get_bus_index(GameAudio.WORLD_BUS)
	_check(world_bus >= 0, "GameAudio hat den Welt-Bus angelegt")

	var slider := panel.get_node_or_null("Panel/Inhalt/Lautstaerke/Welt/Slider") as HSlider
	_check(slider != null, "Welt-Regler steht im Baum")
	if slider != null:
		slider.value = 0.25
		# HSlider.value setzen loest value_changed nicht von selbst aus.
		slider.value_changed.emit(0.25)
		var expected_db := linear_to_db(0.25)
		var actual_db := AudioServer.get_bus_volume_db(world_bus)
		_check(is_equal_approx(actual_db, expected_db),
			"0.25 am Regler ergibt %.1f dB am Bus (ist %.1f)" % [expected_db, actual_db])

	# Zurueck auf volle Lautstaerke, damit der naechste Testlauf nicht auf dem
	# Rest dieses Laufs aufsetzt — Busse ueberleben, static var in GameAudio
	# auch, aber der Bus-Pegel selbst bleibt sonst leise stehen.
	AudioServer.set_bus_volume_db(world_bus, 0.0)

	var keys_list := panel.get_node_or_null("Panel/Inhalt/Tasten/Liste") as VBoxContainer
	_check(keys_list != null and keys_list.get_child_count() == SettingsPanel.ACTIONS.size(),
		"jede Aktion aus project.godot bekommt eine Zeile (%d von %d)" % [
			keys_list.get_child_count() if keys_list != null else -1,
			SettingsPanel.ACTIONS.size(),
		])

	var close_button := panel.get_node_or_null("Panel/Inhalt/Kopf/Schliessen") as Button
	_check(close_button != null, "Schliessen-Knopf steht im Baum")

	panel.free()


## Reine Datenschicht, mit eigenen Testpfaden — ruehrt das echte Profil auf
## der Testmaschine nicht an.
func _test_player_profile_data() -> void:
	_section("PlayerProfile (eigene Testdateien)")

	const TEST_CONFIG := "user://verify_main_menu_profile.cfg"
	const TEST_AVATAR := "user://verify_main_menu_avatar.png"
	const TEST_SOURCE := "user://verify_main_menu_source.png"

	_check(PlayerProfile.get_display_name(TEST_CONFIG) == PlayerProfile.DEFAULT_NAME,
		"ohne Datei gilt der Standardname")

	PlayerProfile.set_display_name("Testname", TEST_CONFIG)
	_check(PlayerProfile.get_display_name(TEST_CONFIG) == "Testname",
		"gesetzter Name kommt zurueck")

	PlayerProfile.set_display_name("   ", TEST_CONFIG)
	_check(PlayerProfile.get_display_name(TEST_CONFIG) == "Testname",
		"ein leerer Name wird ignoriert, statt das Profil zu leeren")

	_check(not PlayerProfile.has_custom_avatar(TEST_AVATAR), "noch kein Profilbild")

	# Absichtlich kein Quadrat (10x20) — prueft das mittige Zuschneiden.
	var source := Image.create(10, 20, false, Image.FORMAT_RGB8)
	source.fill(Color(0.8, 0.2, 0.2))
	source.save_png(TEST_SOURCE)

	var texture := PlayerProfile.set_avatar_from_file(TEST_SOURCE, TEST_AVATAR)
	_check(texture != null, "Bild wird geladen und gespeichert")
	_check(PlayerProfile.has_custom_avatar(TEST_AVATAR), "Profilbild steht jetzt bereit")
	if texture != null:
		var image := texture.get_image()
		_check(image.get_width() == image.get_height(),
			"auf ein Quadrat zugeschnitten (%dx%d)" % [image.get_width(), image.get_height()])

	for path in [TEST_CONFIG, TEST_AVATAR, TEST_SOURCE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Backup/Restore der echten Profildatei, damit dieser Test das gespeicherte
## Profil auf der Testmaschine nicht veraendert.
func _backup_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _restore_file(path: String, backup: Variant) -> void:
	if backup == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(backup)
	file.close()


func _test_profile_panel() -> void:
	_section("Profil bearbeiten (echtes ProfilePanel, Dateien werden zurueckgesichert)")

	var name_backup: Variant = _backup_file(PlayerProfile.CONFIG_PATH)
	var avatar_backup: Variant = _backup_file(PlayerProfile.AVATAR_PATH)

	var scene := load("res://scenes/ui/main_menu.tscn") as PackedScene
	var menu := scene.instantiate() as MainMenu
	root.add_child(menu)
	await process_frame

	var profil_badge := menu.get_node("TopBar/Profil") as PanelContainer
	var profile_panel := menu.get_node("ProfilePanel") as ProfilePanel
	var menu_list := menu.get_node("MenuList") as VBoxContainer
	_check(profile_panel != null and not profile_panel.visible,
		"ProfilePanel haengt im Baum und faengt versteckt an")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	profil_badge.gui_input.emit(click)
	await process_frame
	_check(profile_panel.visible, "Klick auf das Abzeichen oeffnet ProfilePanel")
	_check(not menu_list.visible, "und blendet die Buttons aus")

	# Name: Klick macht das Feld editierbar, Enter uebernimmt.
	var name_edit := profile_panel.get_node("Panel/Inhalt/MainView/NameEdit") as LineEdit
	_check(not name_edit.editable, "Namensfeld faengt nicht editierbar an")
	name_edit.gui_input.emit(click)
	_check(name_edit.editable, "Klick macht es editierbar")
	name_edit.text = "Kommandant"
	name_edit.text_submitted.emit("Kommandant")
	_check(not name_edit.editable, "Enter beendet das Bearbeiten")
	_check(PlayerProfile.get_display_name() == "Kommandant", "und speichert den neuen Namen")

	# Bild: derselbe Weg wie ein echter Dateidialog — ueber file_selected.
	# Absichtlich kein Quadrat (60x40), das prueft den Zuschnitt-Editor
	# tatsaechlich, statt nur den einfachen Mittig-Zuschnitt-Pfad.
	const TEST_SOURCE := "user://verify_main_menu_profile_source.png"
	var source := Image.create(60, 40, false, Image.FORMAT_RGB8)
	source.fill(Color(0.2, 0.5, 0.9))
	source.save_png(TEST_SOURCE)

	var main_view := profile_panel.get_node("Panel/Inhalt/MainView") as VBoxContainer
	var editor_view := profile_panel.get_node("Panel/Inhalt/EditorView") as VBoxContainer
	var avatar_label := profile_panel.get_node("Panel/Inhalt/MainView/AvatarRow/AvatarButton/AvatarLabel") as Label
	var avatar_texture := profile_panel.get_node("Panel/Inhalt/MainView/AvatarRow/AvatarButton/AvatarTexture") as TextureRect
	_check(avatar_label.visible and not avatar_texture.visible, "zeigt anfangs den G4-Platzhalter")
	_check(not editor_view.visible, "Zuschnitt-Editor faengt versteckt an")

	# Erst eine nicht-Bilddatei: muss ehrlich scheitern statt Fehlerdaten
	# ins Profil zu uebernehmen.
	const TEST_NOT_AN_IMAGE := "user://verify_main_menu_not_an_image.png"
	var bogus := FileAccess.open(TEST_NOT_AN_IMAGE, FileAccess.WRITE)
	bogus.store_string("das ist kein Bild")
	bogus.close()
	profile_panel._on_avatar_file_selected(TEST_NOT_AN_IMAGE)
	await process_frame
	_check(not editor_view.visible, "eine kaputte Bilddatei oeffnet keinen Editor")
	var status_label := profile_panel.get_node("Panel/Inhalt/MainView/Status") as Label
	_check(not status_label.text.is_empty(), "und meldet den Fehler statt ihn zu verschlucken")
	DirAccess.remove_absolute(TEST_NOT_AN_IMAGE)

	# Jetzt ein echtes Bild: oeffnet den Zuschnitt-Editor statt sofort zu speichern.
	profile_panel._on_avatar_file_selected(TEST_SOURCE)
	await process_frame
	_check(editor_view.visible and not main_view.visible,
		"ein echtes Bild oeffnet den Zuschnitt-Editor")
	_check(not PlayerProfile.has_custom_avatar(),
		"noch nichts gespeichert, solange der Editor offen ist")

	var slider := profile_panel.get_node("Panel/Inhalt/EditorView/ZoomRow/Slider") as HSlider
	var preview := profile_panel.get_node("Panel/Inhalt/EditorView/RahmenBox/Rahmen/Vorschau") as TextureRect
	var initial_zoom: float = slider.value
	var zoomed_in: float = initial_zoom * 1.5
	slider.value = zoomed_in
	slider.value_changed.emit(zoomed_in)
	_check(is_equal_approx(preview.scale.x, zoomed_in), "Regler zoomt die Vorschau tatsaechlich")

	var accept_button := profile_panel.get_node("Panel/Inhalt/EditorView/Knoepfe/Uebernehmen") as Button
	accept_button.pressed.emit()
	await process_frame
	_check(not editor_view.visible and main_view.visible,
		"Uebernehmen schliesst den Editor wieder")
	_check(avatar_texture.visible and not avatar_label.visible,
		"und das zugeschnittene Bild ersetzt den Platzhalter")
	_check(PlayerProfile.has_custom_avatar(), "jetzt liegt es im echten Profil")

	var close_button := profile_panel.get_node("Panel/Inhalt/Kopf/Schliessen") as Button
	close_button.pressed.emit()
	await process_frame
	_check(not profile_panel.visible, "Schliessen versteckt ProfilePanel")
	_check(menu_list.visible, "und zeigt die Buttons wieder")

	var callsign := menu.get_node("TopBar/Profil/ProfilInner/ProfilText/Callsign") as Label
	_check(callsign.text == "Kommandant", "die Kopfzeile zeigt jetzt den neuen Namen")

	var topbar_avatar := menu.get_node("TopBar/Profil/ProfilInner/Avatar/AvatarTexture") as TextureRect
	_check(topbar_avatar.visible, "und das neue Bild")

	menu.queue_free()
	await process_frame

	if FileAccess.file_exists(TEST_SOURCE):
		DirAccess.remove_absolute(TEST_SOURCE)
	_restore_file(PlayerProfile.CONFIG_PATH, name_backup)
	_restore_file(PlayerProfile.AVATAR_PATH, avatar_backup)
