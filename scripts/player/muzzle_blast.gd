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

## Die aktuelle Belastung, 0 bis 1. Einzige Quelle für alle Effekte.
var strain: float = 0.0

## Hüllkurven je Effekt. Steigen sofort mit, fallen verschieden schnell.
var flash: float = 0.0
var smoke: float = 0.0
var shake: float = 0.0
var tinnitus: float = 0.0

var config: MuzzleBlastData

var _weapon: Weapon
var _camera: Camera3D
var _time_since_shot: float = 999.0
var _shake_time: float = 0.0

## Zwei Rauschquellen mit verschiedenen Startwerten, damit Nicken und Gieren
## nicht im Gleichtakt laufen.
##
## Rauschen statt randf() pro Bild: Weisses Rauschen bei 144 Bildern je Sekunde
## sieht aus wie ein Wackelkontakt, nicht wie ein zitternder Mensch.
var _noise_pitch := FastNoiseLite.new()
var _noise_yaw := FastNoiseLite.new()
var _noise_roll := FastNoiseLite.new()


func _ready() -> void:
	if config == null:
		config = _load_config()
	_noise_pitch.seed = 1
	_noise_yaw.seed = 2
	_noise_roll.seed = 3


## Verbindet sich selbst mit der Waffe — nach dem Vorbild von
## WeaponView.attach_weapon(). Der PlayerController muss dadurch nichts über
## die Innereien dieses Effekts wissen.
func attach(weapon: Weapon, camera: Camera3D = null) -> void:
	_camera = camera
	if _weapon == weapon:
		return
	if _weapon != null and _weapon.fired.is_connected(_on_fired):
		_weapon.fired.disconnect(_on_fired)

	_weapon = weapon
	if _weapon != null:
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
	smoke = maxf(smoke, hit)
	shake = maxf(shake, hit)
	tinnitus = maxf(tinnitus, hit)


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


func _process(delta: float) -> void:
	if config == null:
		return

	_time_since_shot += delta

	# Erst nach der Haltezeit erholen, sonst klingt die Waffe mitten in der
	# eigenen Salve ab.
	if _time_since_shot > config.hold_seconds:
		strain = maxf(0.0, strain - delta / config.recovery_seconds)

	# Jede Hüllkurve vergisst in ihrem eigenen Tempo. Angestossen werden sie
	# ausschliesslich in add().
	flash = _decay(flash, config.flash_fall, delta)
	smoke = _decay(smoke, config.smoke_fall, delta)
	shake = _decay(shake, config.shake_fall, delta)
	tinnitus = _decay(tinnitus, config.tinnitus_fall, delta)

	_shake_time += delta
	apply_shake()


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
	_camera.rotation_degrees = Vector3(
		_noise_pitch.get_noise_1d(t) * config.shake_pitch_deg * shake,
		_noise_yaw.get_noise_1d(t) * config.shake_yaw_deg * shake,
		_noise_roll.get_noise_1d(t) * config.shake_roll_deg * shake
	)
	_camera.position = Vector3(
		_noise_yaw.get_noise_1d(t + 100.0) * config.shake_offset_m * shake,
		_noise_pitch.get_noise_1d(t + 100.0) * config.shake_offset_m * shake,
		0.0
	)


## Fällt von voll auf null in `fall_time` Sekunden.
static func _decay(current: float, fall_time: float, delta: float) -> float:
	return maxf(0.0, current - delta / maxf(0.01, fall_time))


## Alles zurücksetzen — etwa beim Betreten eines neuen Levels.
func reset() -> void:
	strain = 0.0
	flash = 0.0
	smoke = 0.0
	shake = 0.0
	tinnitus = 0.0
	_time_since_shot = 999.0
	apply_shake()


func _load_config() -> MuzzleBlastData:
	if ResourceLoader.exists(DEFAULT_CONFIG):
		var loaded := load(DEFAULT_CONFIG)
		if loaded is MuzzleBlastData:
			return loaded as MuzzleBlastData
	# Fehlt die Datei, laufen die Standardwerte aus dem Skript. Das Spiel soll
	# nicht wegen einer fehlenden Abstimmungsdatei stumm bleiben.
	push_warning("[MuzzleBlast] %s fehlt — Standardwerte werden benutzt" % DEFAULT_CONFIG)
	return MuzzleBlastData.new()
