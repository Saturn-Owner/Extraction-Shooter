## Backt die im Code gebaute Karte in eine echte, editierbare Szene.
##
##   godot --headless --path . --script res://tools/bake_frachthafen.gd
##
## WARUM ES DAS GIBT
##
## Die Karte entstand im Code, damit die .tscn duenn und mergebar bleibt. Der
## Preis dafuer: Im Editor laesst sich nichts anfassen. Wer eine Halle zwei
## Meter nach links schieben will, muss eine Zahl raten, starten, hinsehen,
## wieder raten.
##
## Fuer Leveldesign ist das der falsche Handel. Dieses Werkzeug laeuft einmal
## und macht aus den erzeugten Knoten richtige Szenenknoten: anklickbar,
## verschiebbar, loeschbar.
##
## DER TRICK dabei ist `owner`. Godot speichert nur Knoten, die einen Besitzer
## haben — deshalb blieben die erzeugten bisher aus der Datei heraus. Hier wird
## der Besitzer gesetzt, und damit landen sie drin.
##
## Bei eingebundenen Szenen (Kisten, Ausgaenge) wird NICHT weiter hinabgestiegen:
## Deren Kinder gehoeren der Unterszene. Wer ihnen einen Besitzer gibt, schreibt
## die ganze Kiste ausgepackt in die Datei und die Verbindung zur Vorlage ist
## hin — aendert jemand spaeter loot_container.tscn, aendert sich hier nichts
## mehr.
extends SceneTree

## Gelesen wird die duenne Quelle, geschrieben die spielbare Karte.
##
## GETRENNTE DATEIEN, und zwar aus Erfahrung: Solange beides dieselbe Datei
## war, ueberschrieb das Backen seine eigene Vorlage. Danach liess sich die
## Karte nie wieder aus dem Layout erzeugen — jede Materialaenderung in
## WorldParts kam nicht mehr an, weil die Materialien in der gebackenen Szene
## festgeschrieben waren.
const SOURCE := "res://scenes/levels/frachthafen_quelle.tscn"
const TARGET := "res://scenes/levels/raid_frachthafen.tscn"
const WORLD_NODE := "Welt"


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load(SOURCE) as PackedScene
	if packed == null:
		printerr("Quelle nicht ladbar: ", SOURCE)
		quit(1)
		return

	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var world := level.get_node_or_null(WORLD_NODE)
	if world == null:
		printerr("Knoten '%s' fehlt in der Szene" % WORLD_NODE)
		quit(1)
		return

	var built := world.get_child_count()
	if built == 0:
		printerr("Die Welt ist leer — hat das Layout gebaut?")
		quit(1)
		return

	# Das Skript muss weg, sonst raeumt sein _ready() beim naechsten Start
	# genau die Knoten wieder ab, die wir gerade festschreiben.
	world.set_script(null)

	var count := _adopt(world, level)
	print("Besitzer gesetzt fuer %d Knoten in %d Gruppen" % [count, built])

	var out := PackedScene.new()
	if out.pack(level) != OK:
		printerr("Packen fehlgeschlagen")
		quit(1)
		return

	if ResourceSaver.save(out, TARGET) != OK:
		printerr("Speichern fehlgeschlagen: ", TARGET)
		quit(1)
		return

	print("Geschrieben: %s" % TARGET)
	print("Die Karte laesst sich jetzt im Editor anfassen.")
	quit(0)


## Setzt den Besitzer rekursiv — aber nicht innerhalb eingebundener Szenen.
func _adopt(node: Node, scene_root: Node) -> int:
	var count := 0
	for child in node.get_children():
		child.owner = scene_root
		count += 1
		# Eine eingebundene Szene bleibt eine eingebundene Szene.
		if child.scene_file_path != "":
			continue
		count += _adopt(child, scene_root)
	return count
