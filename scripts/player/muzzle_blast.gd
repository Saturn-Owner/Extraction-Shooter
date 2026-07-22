## Was der eigene Mündungsknall mit dem Spieler macht.
##
## Dauerfeuer ohne Schalldämpfer blendet, vernebelt die Sicht, lässt die Ohren
## pfeifen und rüttelt an der Kamera. Ein Einzelschuss tut nichts davon.
##
## ---------------------------------------------------------------------------
## EINE QUELLE, VIER GEDÄCHTNISSE
##
## `strain` ist die einzige Wahrheit: Jeder Schuss hebt sie, mit der Zeit fällt
## sie. Alle vier Effekte lesen dieselbe Zahl — sie können gar nicht
## auseinanderlaufen, und wer die Balance ändert, verschiebt alle gemeinsam.
##
## Sie haben aber verschiedenes GEDÄCHTNIS: Blendung vergeht in gut einer
## Sekunde, Rauch verzieht sich in zweieinhalb, ein Pfeifen im Ohr bleibt zehn
## Sekunden und länger. Deshalb hängt an der einen Quelle je Effekt eine eigene
## Hüllkurve, die sofort mit nach oben geht und unterschiedlich schnell fällt.
## Ohne das erholen sich alle vier im Gleichschritt, und das liest sich, als
## hätte jemand einen Regler zurückgedreht.
##
## ---------------------------------------------------------------------------
## WARUM ES KEINEN SCHUSSZÄHLER GIBT
##
## „Mehrere Schüsse in Serie" entsteht von selbst: Anstieg gegen Abklingen,
## plus eine Schwelle, unter der exakt null herauskommt. Ein Zähler über
## `_shots_since_release` wäre schlechter — der wird beim Nachladen genullt,
## und Ohren vergessen einen Magazinwechsel nicht.
class_name MuzzleBlast
extends Node

const DEFAULT_CONFIG := "res://assets/data/effects/muzzle_blast_default.tres"

## Die aktuelle Belastung, 0 bis 1. Quelle für Blendung, Wackeln und Pfeifen.
var strain: float = 0.0

## Der Rauch hat eine EIGENE Quelle, und zwar mit umgekehrtem Vorzeichen.
##
## Blendung, Wackeln und Tinnitus kommen vom KNALL — je lauter, desto
## schlimmer, und der Schalldämpfer schützt davor. Rauch entsteht dagegen vor
## allem, WEIL ein Dämpfer dran ist: Er fängt die Pulvergase ab und lässt sie
## langsam und gekühlt austreten, statt sie in einem Schlag frei auszublasen.
##
## Ungedämpft qualmt es trotzdem, nur deutlich dünner und mit einer
## Obergrenze — ein offener Lauf raucht ja auch. Es ist eine Abstufung, kein
## Schalter.
##
## Das ist bewusst keine gemeinsame Quelle mehr. Beides an `strain` zu hängen
## hiesse, zwei gegenläufige Vorgänge in eine Zahl zu pressen — dann müsste
## irgendwo ein Sonderfall stehen, und Sonderfälle in einer Kurve findet
## später niemand wieder.
var smoke_strain: float = 0.0

## Hüllkurven je Effekt. Steigen sofort mit, fallen verschieden schnell.
var flash: float = 0.0
var smoke: float = 0.0
var shake: float = 0.0
var tinnitus: float = 0.0

var config: MuzzleBlastData

var _weapon: Weapon
var _camera: Camera3D

## Der Waffenknoten. Wackelt mit, damit die Waffe nicht im Bild schwimmt.
var _weapon_node: Node3D

## Der helle Schleier. Wird selbst angelegt.
var overlay: BlastOverlay

## Der Pulverdampf. Ebenfalls selbst angelegt.
var smoke_cloud: PowderSmoke

## Das Pfeifen im Ohr.
##
## AudioStreamPlayer, nicht AudioStreamPlayer3D: Ein Tinnitus hat keinen Ort
## im Raum. Er wird im Ohr erzeugt, nicht gehoert — er darf also weder leiser
## werden, wenn man sich wegdreht, noch von links kommen.
var _tinnitus_player: AudioStreamPlayer

## Unter diesem Wert schweigt das Pfeifen ganz und der Spieler wird gestoppt.
##
## Nicht nur der Sauberkeit wegen: linear_to_db(0) ist minus unendlich, und
## das faengt Godot zwar ab, aber ein dauerhaft laufender Spieler bei -80 dB
## mischt trotzdem jeden Frame mit.
const TINNITUS_SILENCE := 0.01
var _time_since_shot: float = 999.0
var _shake_time: float = 0.0

## Ruhelage des Waffenknotens. Gemerkt, weil das Wackeln absolut setzt und
## die Waffe sonst in den Ursprung springen wuerde.
var _weapon_home: Vector3 = Vector3.ZERO

## Ruhelage der Kamera, auf die das Ruetteln aufgesetzt wird.
##
## ---------------------------------------------------------------------------
## WARUM DAS NICHT EINFACH NULL IST
##
## Hier stand `_camera.position = offset`, also die Annahme, die Kamera sitze
## im Ursprung ihres Elternknotens. Fuer die erste Person stimmt das.
##
## Die Schulterkamera (F5) setzt sie aber 2,8 m nach hinten — und dieses
## Ruetteln zog sie in jedem Bild wieder auf null zurueck. Die dritte Person
## sprang dadurch sofort in die erste, ohne dass etwas im Umschalter falsch
## gewesen waere.
##
## Bei der Waffe wurde es von Anfang an richtig gemacht (`_weapon_home +
## offset`); die Kamera war die Ausnahme.
var camera_home: Vector3 = Vector3.ZERO

## Frequenz der Rauschquellen.
##
## ACHTUNG, HIER LAG EIN FEHLER: FastNoiseLite steht ab Werk auf 0.01. Bei den
## Werten, mit denen hier abgetastet wird, liegt das Rauschen dann praktisch
## bei null und aendert sich kaum — herausgekommen sind 0,035 Grad Rollen statt
## der eingestellten 1,5. Der Effekt war da, aber vierzigmal zu schwach, und im
## Spiel schlicht nicht wahrnehmbar.
const NOISE_FREQUENCY := 0.5

## FastNoiseLite liefert nicht den vollen Bereich -1 bis 1, gemessen sind es
## rund -0,65 bis 0,57. Ohne Ausgleich erreicht das Wackeln nie die Staerke,
## die in der .tres steht — wer dort 1,5 Grad eintraegt, bekaeme 1,0.
const NOISE_GAIN := 1.6

## Drei Rauschquellen mit verschiedenen Startwerten, damit die Achsen nicht im
## Gleichtakt laufen.
##
## Rauschen statt randf() pro Bild: Weisses Rauschen bei 144 Bildern je Sekunde
## sieht aus wie ein Wackelkontakt, nicht wie ein zitternder Mensch.
var _noise_pitch := FastNoiseLite.new()
var _noise_yaw := FastNoiseLite.new()
var _noise_roll := FastNoiseLite.new()


func _ready() -> void:
	if config == null:
		config = _load_config()
	overlay = BlastOverlay.new()
	overlay.name = "BlastOverlay"
	add_child(overlay)

	smoke_cloud = PowderSmoke.new()
	smoke_cloud.name = "PowderSmoke"
	add_child(smoke_cloud)

	GameAudio.ensure_buses()
	_tinnitus_player = AudioStreamPlayer.new()
	_tinnitus_player.name = "Tinnitus"
	_tinnitus_player.stream = GameAudio.make_tinnitus(config.tinnitus_hz, config.tinnitus_beat_hz)
	_tinnitus_player.bus = GameAudio.TINNITUS_BUS
	_tinnitus_player.volume_db = -80.0
	add_child(_tinnitus_player)

	for noise in [_noise_pitch, _noise_yaw, _noise_roll]:
		noise.frequency = NOISE_FREQUENCY
	_noise_pitch.seed = 1
	_noise_yaw.seed = 2
	_noise_roll.seed = 3


## Verbindet sich selbst mit der Waffe — nach dem Vorbild von
## WeaponView.attach_weapon(). Der PlayerController muss dadurch nichts über
## die Innereien dieses Effekts wissen.
func attach(weapon: Weapon, camera: Camera3D = null) -> void:
	_camera = camera
	# Die Waffe haengt neben der Kamera, nicht unter ihr. Ohne sie
	# mitzudrehen bleibt sie stehen, waehrend die Sicht kippt — sie schwimmt
	# dann gegenlaeufig durchs Bild, und das sieht kaputt aus statt
	# erschuettert. Kopf und Haende gehoeren zusammen.
	_weapon_node = weapon
	if _weapon == weapon:
		return
	if _weapon != null and _weapon.fired.is_connected(_on_fired):
		_weapon.fired.disconnect(_on_fired)

	_weapon = weapon
	if _weapon != null:
		_weapon_home = _weapon.position
		_weapon.fired.connect(_on_fired)


## Ein Schuss ist gefallen.
##
## Die Stärke kommt aus der Waffe selbst, das Signal muss sie nicht tragen.
func _on_fired(_ammo: AmmoData, _rounds_left: int) -> void:
	if _weapon == null or _weapon.data == null:
		return
	add(_weapon.data)


## Hebt die Belastung um das, was diese Waffe anrichtet.
##
## DIE LAUTSTÄRKE GEHT QUADRATISCH EIN, und das ist der Kern der ganzen
## Mechanik: `get_power_for_weapon()` enthält sie bereits einmal linear, hier
## kommt sie ein zweites Mal dazu. Linear wäre ein Schalldämpfer dreimal
## besser, quadratisch ist er zehnmal besser — erst damit ist er eine
## Anschaffung wert statt einer Nuance.
func add(weapon_data: WeaponData) -> void:
	if weapon_data == null or config == null:
		return

	strain = minf(1.0, strain + rise_for(weapon_data))

	# Gedämpft qualmt es kräftig, ungedämpft deutlich weniger — aber nicht gar
	# nicht. Ein offener Lauf raucht auch, die Gase reissen nur ab, statt
	# langsam und gekühlt auszutreten.
	var suppressed := is_suppressed(weapon_data)
	var factor := 1.0 if suppressed else config.smoke_unsuppressed_factor
	var ceiling := 1.0 if suppressed else config.smoke_unsuppressed_max
	smoke_strain = minf(ceiling, smoke_strain + config.smoke_rise_per_shot * factor)

	_time_since_shot = 0.0

	# Die Hüllkurven werden HIER angestossen, nicht jeden Frame nachgezogen.
	#
	# Zöge man sie laufend auf die aktuelle Wirkung hoch, könnte die Blendung
	# nie schneller vergehen als die Belastung selbst — die vier verschiedenen
	# Abklingzeiten wären dann fast wirkungslos und würden sich erst im
	# allerletzten Rest unterscheiden. So bekommt jede ihren Stoss und vergisst
	# ihn danach in ihrem eigenen Tempo.
	var hit := intensity()
	flash = maxf(flash, hit)
	shake = maxf(shake, hit)
	tinnitus = maxf(tinnitus, hit)
	smoke = maxf(smoke, smoke_intensity())


## Ob an dieser Waffe ein Schalldämpfer hängt. Weiterhin hier aufrufbar,
## damit bestehende Stellen nicht umgeschrieben werden müssen — die
## eigentliche Antwort kommt aus WeaponAudio, der einzigen Quelle dafür.
static func is_suppressed(weapon_data: WeaponData) -> bool:
	return WeaponAudio.is_suppressed(weapon_data)


## Wieviel Belastung ein Schuss dieser Waffe hinzufügt.
##
## Eigene Funktion, damit sich die Wirkung einer Waffe prüfen lässt, ohne den
## Sättigungsdeckel bei eins mitzumessen.
func rise_for(weapon_data: WeaponData) -> float:
	if weapon_data == null or config == null:
		return 0.0
	var power := WeaponAudio.get_power_for_weapon(weapon_data)
	return config.rise_per_shot * power * weapon_data.loudness_multiplier


## Wieviel der Effekt gerade wirkt, 0 bis 1.
##
## Unterhalb der Schwelle kommt EXAKT null heraus, nicht „ein bisschen".
## Ein Rauchschleier mit zwei Prozent Deckkraft ist kein Effekt, sondern ein
## Fehler, den niemand findet.
func intensity() -> float:
	if config == null:
		return 0.0
	return smoothstep(config.threshold, 1.0, strain)


## Wieviel Rauch gerade entsteht, 0 bis 1. Eigene Quelle, siehe oben.
func smoke_intensity() -> float:
	if config == null:
		return 0.0
	return smoothstep(config.threshold, 1.0, smoke_strain)


func _process(delta: float) -> void:
	if config == null:
		return

	_time_since_shot += delta

	# Erst nach der Haltezeit erholen, sonst klingt die Waffe mitten in der
	# eigenen Salve ab.
	if _time_since_shot > config.hold_seconds:
		strain = maxf(0.0, strain - delta / config.recovery_seconds)
		smoke_strain = maxf(0.0, smoke_strain - delta / config.smoke_recovery_seconds)

	# Jede Hüllkurve vergisst in ihrem eigenen Tempo. Angestossen werden sie
	# ausschliesslich in add().
	flash = _decay(flash, config.flash_fall, delta)
	smoke = _decay(smoke, config.smoke_fall, delta)
	shake = _decay(shake, config.shake_fall, delta)
	tinnitus = _decay(tinnitus, config.tinnitus_fall, delta)

	_shake_time += delta
	apply_shake()

	if overlay != null:
		overlay.set_alpha(flash * config.flash_alpha)

	_update_smoke()
	_update_hearing()


## Dumpfes Gehoer und Pfeifen.
##
## ---------------------------------------------------------------------------
## BEIDES HAENGT AN DERSELBEN HUELLKURVE, UND DAS IST WICHTIG
##
## `tinnitus` faellt mit Abstand am langsamsten (12 s gegen 1,2 s bei der
## Blendung). Das Ohr ist also noch lange zu, wenn man optisch laengst wieder
## klarkommt — man sieht das Ziel, hoert aber nichts. Genau dieses
## Auseinanderfallen ist der Effekt: Wer eine lange Salve schiesst, ist danach
## sehend taub, und in einem Extraction-Shooter ist Hoeren das, womit man
## ueberlebt.
##
## ---------------------------------------------------------------------------
## EHRLICHE EINSCHRAENKUNG
##
## Solange die Waffe die einzige Tonquelle im Spiel ist, ist das Stimmung und
## kein Nachteil — es gibt keine Schritte und keine Gegner, die man ueberhoeren
## koennte. Sobald es die gibt, wird daraus von selbst eine Mechanik, ohne dass
## hier etwas geaendert werden muesste.
func _update_hearing() -> void:
	GameAudio.set_muffle(tinnitus, config.muffle_cutoff_hz, config.muffle_volume_db)

	if _tinnitus_player == null:
		return

	if tinnitus < TINNITUS_SILENCE:
		if _tinnitus_player.playing:
			_tinnitus_player.stop()
		return

	# linear_to_db statt einer linearen Rampe: Lautstaerke wird logarithmisch
	# gehoert. Linear ueber die Huellkurve zu fahren hiesse, dass das Pfeifen
	# gefuehlt sofort auf voller Staerke steht und dann ewig auf demselben
	# Pegel haengt — der Abfall passierte fast vollstaendig in den letzten
	# Zehnteln der Kurve.
	_tinnitus_player.volume_db = linear_to_db(tinnitus) + config.tinnitus_volume_db
	if not _tinnitus_player.playing:
		_tinnitus_player.play()


## Haelt den Dampf an der Muendung. Die Schwaden selbst bleiben stehen.
func _update_smoke() -> void:
	if smoke_cloud == null:
		return
	if _weapon == null:
		smoke_cloud.emitting = false
		return

	# Der sichtbare Muendungspunkt wandert mit dem Modell und mit einem
	# angebauten Schalldaempfer — deshalb von der Waffe erfragen statt zu raten.
	var muzzle := _weapon.get_shot_origin()
	var forward := _camera.global_basis if _camera != null else Basis.IDENTITY
	smoke_cloud.follow(muzzle, forward, smoke)


## Setzt das Wackeln auf die Kamera.
##
## ---------------------------------------------------------------------------
## WARUM AUF DIE KAMERA UND NICHT AUF DEN PIVOT
##
## Der Rückstoss schreibt `_camera_pivot.rotation_degrees.x` und summiert dabei
## in `_pitch` auf. Wackelte man auf demselben Knoten, wanderte die
## Blickrichtung dauerhaft weg — der Spieler schaute nach ein paar Magazinen
## schräg nach oben, ohne dass jemand den Zusammenhang sähe. Die Camera3D
## darunter wird von niemandem sonst beschrieben.
##
## ---------------------------------------------------------------------------
## ABER: DIE KAMERA IST DIE ZIELQUELLE
##
## player_controller.gd übergibt sie mit `weapon.set_aim_source()` an die
## Waffe, und `Weapon.get_aim_point()` schiesst den Zielstrahl entlang ihrer
## Blickachse. Wer die Kamera dreht, dreht also den Treffpunkt mit. Deshalb
## die Aufteilung:
##
##   Rollen        gross  — dreht um die Blickachse, ändert die Richtung NICHT
##   Nicken/Gieren klein  — verschiebt wirklich den Treffpunkt
##   Verschieben   frei   — verschiebt nur den Ursprung, nicht die Richtung
##
## Das meiste sichtbare Wackeln kommt damit aus dem Rollen und kostet keine
## Präzision. Was wehtut, ist klein und mit Absicht so.
##
## JEDEN FRAME ABSOLUT SETZEN, NIE ADDIEREN: Sonst summieren sich
## Rundungsfehler, und die Kamera steht irgendwann dauerhaft schief. Bei
## shake = 0 ergibt die Rechnung exakt null, der Kanal räumt sich selbst auf.
func apply_shake() -> void:
	if _camera == null or config == null:
		return

	var t := _shake_time * config.shake_speed
	var angles := Vector3(
		_wobble(_noise_pitch, t) * config.shake_pitch_deg * shake,
		_wobble(_noise_yaw, t) * config.shake_yaw_deg * shake,
		_wobble(_noise_roll, t) * config.shake_roll_deg * shake
	)
	var offset := Vector3(
		_wobble(_noise_yaw, t + 100.0) * config.shake_offset_m * shake,
		_wobble(_noise_pitch, t + 100.0) * config.shake_offset_m * shake,
		0.0
	)

	_camera.rotation_degrees = angles
	_camera.position = camera_home + offset

	# Dieselbe Bewegung auf die Waffe, sonst schwimmt sie gegenlaeufig im Bild.
	if _weapon_node != null:
		_weapon_node.rotation_degrees = angles
		_weapon_node.position = _weapon_home + offset


## Ein Rauschwert von -1 bis 1, ausgeglichen und begrenzt.
static func _wobble(noise: FastNoiseLite, at: float) -> float:
	return clampf(noise.get_noise_1d(at) * NOISE_GAIN, -1.0, 1.0)


## Fällt von voll auf null in `fall_time` Sekunden.
static func _decay(current: float, fall_time: float, delta: float) -> float:
	return maxf(0.0, current - delta / maxf(0.01, fall_time))


## Alles zurücksetzen — etwa beim Betreten eines neuen Levels.
func reset() -> void:
	strain = 0.0
	smoke_strain = 0.0
	flash = 0.0
	smoke = 0.0
	shake = 0.0
	tinnitus = 0.0
	_time_since_shot = 999.0
	apply_shake()
	if overlay != null:
		overlay.set_alpha(0.0)
	if smoke_cloud != null:
		smoke_cloud.emitting = false

	# Der Bus ueberlebt einen Levelwechsel. Ohne das Zuruecksetzen betraete man
	# das naechste Level mit den Ohren vom letzten.
	GameAudio.reset_muffle()
	if _tinnitus_player != null and _tinnitus_player.playing:
		_tinnitus_player.stop()


func _load_config() -> MuzzleBlastData:
	if ResourceLoader.exists(DEFAULT_CONFIG):
		var loaded := load(DEFAULT_CONFIG)
		if loaded is MuzzleBlastData:
			return loaded as MuzzleBlastData
	# Fehlt die Datei, laufen die Standardwerte aus dem Skript. Das Spiel soll
	# nicht wegen einer fehlenden Abstimmungsdatei stumm bleiben.
	push_warning("[MuzzleBlast] %s fehlt — Standardwerte werden benutzt" % DEFAULT_CONFIG)
	return MuzzleBlastData.new()
