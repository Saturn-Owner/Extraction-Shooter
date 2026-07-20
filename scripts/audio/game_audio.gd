## Die Audio-Busse des Spiels, zur Laufzeit angelegt.
##
## ---------------------------------------------------------------------------
## WARUM IM CODE UND NICHT IN project.godot
##
## Busse lassen sich im Editor anlegen und landen dann in `project.godot`.
## Genau das wollen wir nicht: An dieser Datei arbeiten beide Entwickler
## gleichzeitig, sie ist zwischen den Branches ohnehin schon auseinander
## gelaufen, und ein Merge-Konflikt in den Projekteinstellungen ist deutlich
## unangenehmer als einer in einer .gd — Godot schreibt die Datei bei jedem
## Editorstart neu und sortiert dabei um.
##
## Hier angelegt heisst ausserdem: Die Busse sind dokumentiert. Wer in der
## Editor-Oberflaeche einen Bus "Welt" sieht, weiss nicht, wofuer er da ist.
##
## ---------------------------------------------------------------------------
## ZWEI BUSSE, UND DIE TRENNUNG IST DER GANZE PUNKT
##
##   Master
##    ├── Welt      alles, was in der Spielwelt passiert: Schuesse, Schritte,
##    │             Nachladen, spaeter Gegner. Haengt am Tiefpass — wird
##    │             dumpf und leise, wenn die Ohren zu sind.
##    └── Tinnitus  das Pfeifen. Geht NICHT durch den Tiefpass.
##
## Das Pfeifen entsteht im Ohr, nicht in der Welt. Haengte es am selben Bus,
## wuerde es mit steigender Belastung selbst gedaempft — es wuerde also genau
## dann leiser, wenn es lauter werden soll. Ein Fehler, den man beim Spielen
## nur als "irgendwie schwach" bemerkt und nie findet.
class_name GameAudio
extends RefCounted

## Alles Diegetische. Was hier haengt, hoert der Spieler mit seinen Ohren —
## und die kann man kaputtschiessen.
const WORLD_BUS := &"Welt"

## Das Pfeifen im Kopf. Bewusst ausserhalb der Welt.
const TINNITUS_BUS := &"Tinnitus"

## Grenzfrequenz bei gesunden Ohren. Ueber dem menschlichen Hoerbereich, der
## Filter tut bei diesem Wert also nichts.
const OPEN_CUTOFF_HZ := 20500.0

static var _low_pass: AudioEffectLowPassFilter = null


## Legt die Busse an, falls sie fehlen. Mehrfach aufrufbar.
##
## Wird von MuzzleBlast beim Start gerufen. Bewusst kein Autoload: Autoloads
## gibt es im `--script`-Modus nicht, und dann liefen die Tests gegen eine
## Struktur, die es im Testlauf gar nicht gibt.
static func ensure_buses() -> void:
	var world := _ensure_bus(WORLD_BUS)
	_ensure_bus(TINNITUS_BUS)

	# Den Filter nur einmal anhaengen. Bei jedem Aufruf einen neuen zu
	# erzeugen wuerde die Filter stapeln — nach dem dritten Levelwechsel
	# klaenge dann alles dumpf, ohne dass ein Schuss gefallen waere.
	if AudioServer.get_bus_effect_count(world) == 0:
		_low_pass = AudioEffectLowPassFilter.new()
		_low_pass.cutoff_hz = OPEN_CUTOFF_HZ
		AudioServer.add_bus_effect(world, _low_pass)
	elif _low_pass == null:
		# Busse ueberleben einen Szenenwechsel, statische Variablen nicht
		# zwingend. Dann den vorhandenen Filter wieder einsammeln.
		var existing := AudioServer.get_bus_effect(world, 0)
		if existing is AudioEffectLowPassFilter:
			_low_pass = existing as AudioEffectLowPassFilter


## Setzt die Hoerdaempfung. `amount` 0 = gesund, 1 = voll zu.
##
## ---------------------------------------------------------------------------
## DIE GRENZFREQUENZ WIRD LOGARITHMISCH GEFAHREN, NICHT LINEAR
##
## Das Ohr hoert Tonhoehe logarithmisch: Der Schritt von 600 auf 1200 Hz ist
## derselbe wie der von 5000 auf 10000. Linear von 20500 auf 600 zu fahren
## hiesse, dass bei halber Belastung 10550 Hz stehen — und zwischen 20500 und
## 10550 hoert praktisch niemand einen Unterschied. Die erste Haelfte der
## Skala waere verschenkt, die zweite ein Absturz.
##
## Logarithmisch liegt die Mitte bei rund 3500 Hz, und das ist hoerbar dumpf.
## Der Regler tut damit ueber seinen ganzen Weg etwas.
static func set_muffle(amount: float, cutoff_hz: float, volume_db: float) -> void:
	var world := AudioServer.get_bus_index(WORLD_BUS)
	if world < 0:
		return

	amount = clampf(amount, 0.0, 1.0)

	if _low_pass != null:
		# Geometrisch statt ueber exp(lerp(log, log)) gerechnet. Dieselbe
		# Kurve, aber an den Enden exakt: pow(x, 0) ist glatt 1 und pow(x, 1)
		# glatt x, waehrend der Umweg ueber Logarithmus und Exponent bei
		# voller Belastung 603 Hz statt der eingestellten 600 lieferte. Hoerbar
		# ist der Unterschied nicht, aber ein Wert aus der .tres soll am
		# Anschlag auch genau der Wert aus der .tres sein.
		var ratio := maxf(20.0, cutoff_hz) / OPEN_CUTOFF_HZ
		_low_pass.cutoff_hz = OPEN_CUTOFF_HZ * pow(ratio, amount)

	AudioServer.set_bus_volume_db(world, lerpf(0.0, volume_db, amount))


## Setzt den Bus auf gesunde Ohren zurueck.
static func reset_muffle() -> void:
	set_muffle(0.0, OPEN_CUTOFF_HZ, 0.0)


## Index eines Busses, oder -1. Fuer Tests und Diagnose.
static func bus_index(bus_name: StringName) -> int:
	return AudioServer.get_bus_index(bus_name)


const SAMPLE_RATE := 44100

## Laenge der Tinnitus-Schleife. Eine Sekunde reicht, siehe unten — laenger
## kostet nur Speicher, weil sich der Klang exakt wiederholt.
const TINNITUS_SECONDS := 1.0


## Das Pfeifen im Ohr, als nahtlose Schleife.
##
## ---------------------------------------------------------------------------
## ZWEI TOENE, NICHT EINER
##
## Ein reiner Sinus klingt nach Messgeraet — sauber, gleichmaessig, tot. Zwei
## dicht beieinanderliegende Toene ueberlagern sich zu einer Schwebung: Die
## Lautstaerke pulsiert mit der Differenzfrequenz, hier also achtmal je
## Sekunde. Das klingt lebendig und unangenehm statt technisch, und genau das
## soll es.
##
## ---------------------------------------------------------------------------
## WARUM DIE FREQUENZEN GERUNDET WERDEN
##
## Eine Schleife klickt an der Nahtstelle, sobald der Sinus dort nicht gerade
## durch null geht — der Sprung ist ein Knacken, und bei einer Sekunde
## Schleifenlaenge knackt es einmal pro Sekunde, dauerhaft, solange es pfeift.
##
## Vermeiden laesst sich das nur, wenn in die Pufferlaenge eine GANZE Zahl von
## Schwingungen passt. Die Frequenzen kommen aber aus einer .tres und koennen
## dort auf beliebige Kommastellen stehen. Also werden sie hier auf die
## naechste passende Frequenz gerundet — bei 4500 und 4508 Hz aendert das
## nichts, bei 4507,3 verschiebt es um 0,3 Hz, und das hoert niemand. Ein
## Knacken hoert dagegen jeder.
static func make_tinnitus(hz: float = 4500.0, beat_hz: float = 4508.0) -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * TINNITUS_SECONDS)

	# Auf ganze Schwingungen je Puffer runden — sonst knackt die Naht.
	var cycles_a := maxf(1.0, round(hz * TINNITUS_SECONDS))
	var cycles_b := maxf(1.0, round(beat_hz * TINNITUS_SECONDS))

	var data := PackedByteArray()
	data.resize(frames * 2)

	for i in range(frames):
		var phase := float(i) / float(frames)
		# Je Ton die halbe Aussteuerung, sonst uebersteuert die Summe.
		var sample := sin(TAU * cycles_a * phase) * 0.5
		sample += sin(TAU * cycles_b * phase) * 0.5

		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


## Legt einen Bus an, falls er fehlt, und gibt seinen Index zurueck.
static func _ensure_bus(bus_name: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index

	index = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	return index
