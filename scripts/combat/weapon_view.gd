## Haelt und bewegt das sichtbare Waffenmodell in der Hand des Spielers.
##
## ARBEITSTEILUNG — das ist der Kern dieser Datei:
##
##   weapon_view.gd  (hier)   Alles, was im Kameraraum passiert und fuer JEDE
##                            Waffe gleich funktioniert: Haltung, Zielen,
##                            Nachschwingen, Laufwackeln, Rueckstossfeder.
##
##   scripts/weapons/*.gd     Alles, was diese eine Waffe ausmacht: ihre
##                            Geometrie und ihre Mechanik. Der Schlitten einer
##                            Pistole, die Pumpe einer Flinte, der Verschluss
##                            eines Sturmgewehrs — das sind verschiedene
##                            Bewegungen, keine Varianten derselben.
##
## Diese Klasse kennt deshalb kein einziges Waffenteil beim Namen. Sie sagt
## dem Modell nur, WAS passiert ist ("ein Schuss ist gefallen", "Nachladen
## laeuft zu 40 %"), und das Modell entscheidet, wie es das zeigt.
##
## Diese Klasse enthaelt KEINE Spiellogik. Ob geschossen werden darf,
## entscheidet weapon.gd — hier wird nur dargestellt, was passiert ist. Das
## ist wichtig fuer den spaeteren Multiplayer: Die Darstellung darf nie zur
## Quelle der Wahrheit werden.
##
## AUFBAU DER KNOTEN — jede Animationsart bekommt einen eigenen Knoten,
## damit sie sich nicht gegenseitig ueberschreiben:
##
##   WeaponView
##    └ Pose       Huefte <-> Zielen, Sprint, Nachladehaltung
##       └ Sway    Nachschwingen bei Mausbewegung, Laufwackeln
##          └ Recoil   Rueckstossfeder
##             └ Viewmodel   das Modell dieser Waffe
##
## WAS HIER FEHLT: Haende und Arme. Die Waffe schwebt frei. Das ist fuer ein
## Blockout normal — sichtbare Haende brauchen Rigging und handgemachte
## Animationen, das kann Claude nicht liefern (siehe CLAUDE.md).
class_name WeaponView
extends Node3D

@export_group("Haltung")

## Wie schnell zwischen den Haltungen gewechselt wird.
## Die Haltungen selbst kommen aus dem jeweiligen Modell — eine Pistole
## liegt anders in der Hand als ein Praezisionsgewehr.
@export var pose_speed: float = 11.0

@export_group("Zielen")

## Sekunden von der Huefte bis die Visierlinie steht.
## Wird mit der Ergonomie der Waffe verrechnet — eine handliche Waffe
## kommt schneller ans Auge.
@export var ads_base_time: float = 0.26

@export_group("Nachschwingen")

## Wie stark die Waffe der Mausbewegung hinterherhaengt (Grad).
@export var sway_amount: float = 4.5

## Federhaerte des Nachschwingens — hoch = kommt schneller zurueck.
##
## Zusammen mit sway_damping bestimmt dieser Wert das ganze Gefuehl. Die
## aperiodische Grenze liegt bei damping = 2 * sqrt(stiffness), also hier bei
## rund 19. Alles darunter schwingt ueber, alles darueber kriecht zurueck.
@export var sway_stiffness: float = 90.0

## Daempfung des Nachschwingens — NIEDRIG = schwingt ueber.
##
## Das ist die Zahl, an der das Gefuehl haengt. Bei 19 (aperiodisch) kommt die
## Waffe sauber zur Ruhe und wirkt gebremst; bei 7 schwingt sie deutlich ueber
## die Mitte hinaus und pendelt sich ein. Weniger als etwa 5 wird zappelig.
@export var sway_damping: float = 7.0

## Wieviel Nachschwingen beim Zielen uebrig bleibt.
@export_range(0.0, 1.0) var sway_ads_factor: float = 0.25

@export_group("Ladehebel")

## Drehung, in die die Waffe waehrend einer leeren Nachladung dreht (Grad,
## Kameraraum) — damit man die Seite mit dem Ladehebel sieht, statt nur von
## hinten drauf zu schauen.
##
## ---------------------------------------------------------------------------
## Z (ROLLEN) TRAEGT DIE DREHUNG, Y (GIEREN) BLEIBT KLEIN — NICHT UMGEKEHRT
##
## Der erste Versuch drehte ueberwiegend um Y (Gieren, die Muendung schwenkt
## zur Seite) und liess die Waffe dabei komplett aus dem Bild verschwinden.
## Der Grund ist die Geometrie: Die Drehung passiert um den Ursprung von
## `Pose`, ungefaehr am Griff — die Muendung sitzt gut 0.56 m weiter vorn.
## Bei einer Gierdrehung bewegt sich ein Punkt in dieser Entfernung auf einem
## KREISBOGEN: 0.56 m * sin(42°) ≈ 0.43 m seitlicher Versatz. Aus der Naehe
## einer Egoperspektive ist das mehr, als die Kamera ueberhaupt zeigt — die
## Muendung schwingt schlicht aus dem Bildwinkel heraus.
##
## Rollen (Z) hat dieses Problem nicht: Es dreht das Bild um die Blickachse,
## statt Punkte quer dazu zu verschieben — ein entfernter Punkt bleibt dabei
## ungefaehr an seinem Platz, er kippt nur. Deshalb traegt hier Z den
## Hauptanteil der Drehung, Y bleibt klein genug, dass selbst mit dem
## Ueberschwung der Feder (rack_damping) nichts aus dem Bild laeuft.
@export var rack_turn_rotation: Vector3 = Vector3(-4.0, -11.0, 38.0)

## Versatz, der die Drehung begleitet (Meter, Kameraraum) — verlagert das
## Gewicht sichtbar mit, statt nur auf der Stelle zu rotieren.
@export var rack_turn_offset: Vector3 = Vector3(-0.02, 0.0, 0.0)

## Federhaerte der Drehbewegung. Zusammen mit rack_damping bestimmt das, wie
## schnell und wie ruckartig die Waffe sich dreht.
@export var rack_stiffness: float = 40.0

## Daempfung der Drehbewegung — NIEDRIG laesst sie ueber die Zieldrehung
## hinausschiessen und zurueckfedern, das liest sich als Ruck einer echten
## Hand statt als servomotorisch glatte Bewegung. Zu niedrig wird zappelig
## UND vergroessert den Ueberschwung ueber rack_turn_rotation hinaus — bei
## der Gierkomponente (Y) ist das der Spielraum, der oben einkalkuliert ist.
@export var rack_damping: float = 8.0

@export_group("Laufwackeln")

@export var bob_speed: float = 8.5
@export var bob_amount: float = 0.016
@export_range(0.0, 1.0) var bob_ads_factor: float = 0.3

@export_group("Rueckstoss (sichtbar)")

## Wie weit die Waffe pro Schuss nach hinten geht (Meter).
@export var recoil_kick_back: float = 0.055

## Wie weit die Muendung hochspringt (Grad).
@export var recoil_kick_up: float = 3.4

## Federhaerte — hoch = schnappt schneller zurueck.
@export var recoil_stiffness: float = 190.0

## Daempfung — niedrig = schwingt nach.
@export var recoil_damping: float = 17.0

@export_group("Haende")

## Wie schnell der Uebergang zwischen Pfad und Magazin laeuft (siehe
## _magazine_hold_blend). Niedrig = traege, das Greifen zieht sich sichtbar
## hin; hoch = fast augenblicklich. Betrifft nur das Greifen und Loslassen
## des Magazins — der Ladehebelzug der Griffhand hat sein eigenes, progress-
## basiertes Ueberblenden (siehe _grip_hand_while_reloading()) und braucht
## das nicht.
@export var hand_reach_speed: float = 9.0

var _weapon: Weapon

# Knoten der Animationsebenen
var _pose: Node3D
var _sway: Node3D
var _recoil: Node3D

## Die eigenen Haende an der Waffe. Siehe ViewmodelArms.
var _arms: ViewmodelArms

## Wie weit die Stuetzhand gerade vom berechneten Pfad zur tatsaechlichen
## Magazinposition uebergeblendet ist: 0 = ganz am Pfad (Handschutz o.ae.),
## 1 = ganz am Magazin. Rampt weich zwischen beidem, statt beim Kippen von
## magazine_held_by_hand (siehe _update_arms()) hart umzuschalten — Greifen
## und Loslassen sollen wie eine Bewegung aussehen, kein Sprung.
##
## ---------------------------------------------------------------------------
## EIN ZAHLENWERT, KEINE WELTPOSITION
##
## Der erste Versuch liess eine gespeicherte WELTPOSITION ihrem Ziel
## hinterherhinken. Das ging beim Umsehen sichtbar kaputt: Griff und
## Handschutz drehen sich mit der Kamera sofort mit, die gespeicherte
## Position tat das nur verzoegert — die Hand blieb beim schnellen Umsehen
## buchstaeblich in der Luft haengen, statt an der Waffe zu bleiben.
##
## Ein reiner Uebergangs-WERT hat dieses Problem nicht: Beide Enden des
## lerp() in _update_arms() (der Pfad-Zielpunkt UND die Magazinposition)
## werden jeden Frame frisch aus der aktuellen Kamerahaltung berechnet und
## drehen sich damit automatisch mit. Nur der Uebergang ZWISCHEN ihnen
## braucht Zeit, nicht ihre Position selbst.
var _magazine_hold_blend: float = 0.0

## Wohin die Hand greift, um ein frisches Magazin zu holen — relativ zur
## Kamera. Unten links und dicht am Koerper, also dort, wo die Magazintaschen
## der Weste sitzen. Bewusst unterhalb des Bildrands: Man sieht die Hand
## hinuntergehen und mit dem Magazin zurueckkommen, nicht die Tasche selbst.
const POUCH_IN_VIEW := Vector3(-0.22, -0.46, -0.10)

## Das Modell der Waffe, die gerade in der Hand liegt.
var _viewmodel: WeaponViewmodel

# Zustand von aussen
var _aiming: bool = false
var _sprinting: bool = false
var _speed_ratio: float = 0.0

# Laufende Animationswerte
var _aim_progress: float = 0.0
var _look_delta: Vector2 = Vector2.ZERO
var _sway_offset: Vector2 = Vector2.ZERO

## Wie schnell sich das Nachschwingen gerade bewegt (Grad je Sekunde).
## Ohne diese Groesse gaebe es kein Ueberschwingen — eine Feder braucht Masse.
var _sway_velocity: Vector2 = Vector2.ZERO
var _bob_time: float = 0.0

var _recoil_offset: Vector3 = Vector3.ZERO
var _recoil_velocity: Vector3 = Vector3.ZERO
var _recoil_angle: float = 0.0
var _recoil_angular_velocity: float = 0.0

## 0 = normale Haltung, 1 = ganz in die Ladehebel-Drehung gedreht. Wie beim
## Nachschwingen eine Feder statt eines lerp — siehe _update_pose().
var _rack_progress: float = 0.0
var _rack_velocity: float = 0.0

# Nachladen und Ladehemmung laufen als Zeitleiste von 1.0 auf 0.0
var _sequence_time_left: float = 0.0
var _sequence_duration: float = 0.0
var _sequence_kind: StringName = &""
var _sequence_from_empty: bool = false

## 0..1, wie weit die laufende Sequenz (Nachladen/Ladehemmung) fortgeschritten
## ist. Von _update_sequence() gepflegt, von _update_pose() gelesen — die
## Ladehebel-Drehung darf erst ab RACK_TURN_START_PROGRESS beginnen, nicht
## schon beim Start der Sequenz.
var _sequence_progress: float = 0.0

## Magazin bleibt drin, es wird nur durchgeladen — siehe Weapon.
var _sequence_chamber_only: bool = false


func _ready() -> void:
	_build_hierarchy()


func _build_hierarchy() -> void:
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)

	_sway = Node3D.new()
	_sway.name = "Sway"
	_pose.add_child(_sway)

	_recoil = Node3D.new()
	_recoil.name = "Recoil"
	_sway.add_child(_recoil)

	# ---------------------------------------------------------------------
	# DIE ARME HAENGEN NEBEN DER WAFFE, NICHT AN IHR
	#
	# Sie kommen an WeaponView selbst und damit ins feste Kameraraster — die
	# Schultern bleiben stehen, wo Schultern hingehoeren, waehrend die Waffe
	# darueber schwankt, zurueckstoesst und sich beim Nachladen anhebt.
	#
	# Haengte man sie unter `_recoil`, wuerden sie jede Waffenbewegung
	# mitmachen und dabei genau das verlieren, was sie zeigen sollen: dass
	# HAENDE die Waffe fuehren. Die Verbindung entsteht stattdessen ueber die
	# Kinematik in `_update_arms()`.
	_arms = ViewmodelArms.new()
	_arms.name = "Arme"
	add_child(_arms)


## Waffe anmelden. Ab hier reagiert die Darstellung auf ihre Signale.
func attach_weapon(weapon: Weapon) -> void:
	if _weapon == weapon:
		return
	_weapon = weapon
	if _weapon == null:
		return

	_weapon.fired.connect(_on_fired)
	_weapon.dry_fire.connect(_on_dry_fire)
	_weapon.reload_started.connect(_on_reload_started)
	_weapon.reload_finished.connect(_on_reload_finished)
	_weapon.reload_cancelled.connect(_on_sequence_cancelled)
	_weapon.jammed.connect(_on_jammed)
	_weapon.unjam_started.connect(_on_unjam_started)
	_weapon.unjammed.connect(_on_unjammed)
	_weapon.fire_mode_changed.connect(_on_fire_mode_changed)
	_weapon.weapon_changed.connect(_on_weapon_changed)

	_on_weapon_changed(_weapon.data)


## Eine andere Waffe liegt in der Hand — Modell austauschen.
##
## Es wird bewusst komplett neu gebaut statt Teile umzuhaengen: Die Waffen
## haben unterschiedliche Teile, nicht dieselben in anderer Form.
func _on_weapon_changed(new_data: WeaponData) -> void:
	if _viewmodel != null:
		_viewmodel.queue_free()
		_viewmodel = null

	if new_data == null:
		return

	_viewmodel = new_data.create_viewmodel()
	_viewmodel.name = "Viewmodel"

	# REIHENFOLGE IST HIER WICHTIG: WeaponViewmodel._ready() baut das Modell,
	# und _ready() laeuft beim Einhaengen in den Baum. Bestueckung und Daten
	# muessen also VOR add_child() stehen — danach gesetzt kaeme beides zu
	# spaet und die Anbauteile fehlten kommentarlos.
	_viewmodel.weapon_data = new_data
	if _weapon != null and _weapon.build != null:
		_viewmodel.attachments = _weapon.build.attachments.duplicate()

	_recoil.add_child(_viewmodel)

	# Ruhelage sofort setzen, sonst schwingt die neue Waffe aus der alten
	# Haltung heran, als haette man sie geworfen.
	_pose.position = _viewmodel.hip_position
	_pose.rotation_degrees = _viewmodel.hip_rotation_degrees
	_reset_animation_state()

	# Das Muendungsfeuer gehoert an die Muendung DIESER Waffe.
	if _weapon != null:
		_weapon.set_visual_muzzle(_viewmodel.muzzle_point)
		_viewmodel.notify_fire_mode(_weapon.current_fire_mode)


func _reset_animation_state() -> void:
	_recoil_offset = Vector3.ZERO
	_recoil_velocity = Vector3.ZERO
	_recoil_angle = 0.0
	_recoil_angular_velocity = 0.0
	# Sonst nimmt die neue Waffe den Schwung der alten mit und schlaegt beim
	# Ziehen einmal aus, ohne dass jemand die Maus bewegt haette.
	_sway_offset = Vector2.ZERO
	_sway_velocity = Vector2.ZERO
	_look_delta = Vector2.ZERO
	_rack_progress = 0.0
	_rack_velocity = 0.0
	_sequence_time_left = 0.0
	_sequence_kind = &""
	_sequence_progress = 0.0
	_aim_progress = 0.0
	# Neue Waffe, neues Magazin (oder gar keins) — ein Uebergang von der
	# vorigen Waffe her ergibt keinen Sinn.
	_magazine_hold_blend = 0.0


## Das Modell, das gerade in der Hand liegt. Fuer Tests und Werkzeuge.
func get_viewmodel() -> WeaponViewmodel:
	return _viewmodel


## Wohin das Muendungsfeuer gehoert. Wandert mit dem Modell mit, damit der
## Blitz beim Zielen nicht neben der Waffe in der Luft haengt.
func get_muzzle_point() -> Node3D:
	return _viewmodel.muzzle_point if _viewmodel != null else null


## Bewegungszustand vom PlayerController. Treibt Laufwackeln und Sprinthaltung.
func set_movement(speed_ratio: float, sprinting: bool) -> void:
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	_sprinting = sprinting


## Beim Sprinten wird nicht gezielt — das entscheidet der Controller.
func set_aiming(aiming: bool) -> void:
	_aiming = aiming


## Mausbewegung fuer das Nachschwingen. Kommt aus _unhandled_input des Controllers.
func add_look_delta(delta: Vector2) -> void:
	_look_delta += delta


## 0.0 = Huefte, 1.0 = im Ziel. Der Controller zieht daran das Sichtfeld.
func get_aim_progress() -> float:
	return _aim_progress


func _process(delta: float) -> void:
	_update_sequence(delta)
	_update_aim(delta)
	_update_pose(delta)
	_update_sway(delta)
	_update_bob(delta)
	_update_recoil(delta)
	# Die beweglichen Teile bewegt die Waffe selbst.
	if _viewmodel != null:
		_viewmodel.update_mechanics(delta)

	# GANZ ZUM SCHLUSS: Die Arme greifen dorthin, wo die Waffe nach allen
	# Bewegungen dieses Bildes wirklich steht. Stuenden sie weiter oben,
	# griffen sie um einen Frame versetzt — bei Rueckstoss sichtbar als
	# Zittern zwischen Hand und Griff.
	_update_arms(delta)


## Zielen ist eine reine Zeitinterpolation. Die Ergonomie der Waffe bestimmt
## das Tempo: eine handliche Waffe kommt spuerbar schneller ans Auge.
func _update_aim(delta: float) -> void:
	var wants_aim := _aiming and not _sprinting and _sequence_kind == &""

	var ergonomics := 50.0
	var attachment_factor := 1.0
	if _weapon != null and _weapon.data != null:
		ergonomics = float(_weapon.data.ergonomics)
		# Ein schweres Zielfernrohr kommt spuerbar spaeter ans Auge als ein
		# Rotpunkt — unabhaengig davon, wie handlich die Waffe selbst ist.
		attachment_factor = _weapon.data.ads_time_multiplier
	# Ergonomie 0 -> 1.4x langsamer, 100 -> 0.7x schneller.
	var duration := ads_base_time * (1.4 - 0.7 * (ergonomics / 100.0)) * attachment_factor
	var step := delta / maxf(0.01, duration)

	_aim_progress = clampf(_aim_progress + (step if wants_aim else -step), 0.0, 1.0)


## ---------------------------------------------------------------------------
## NACHLADEN HEBT DIE WAFFE NICHT MEHR AN
##
## Frueher wanderte die Waffe waehrend des Nachladens in eine eigene Haltung
## (`reload_position`/`reload_rotation_degrees` am Modell) — angehoben und
## eingedreht, damit der Magazinwechsel besser im Bild stattfindet. Das sah in
## der Egoperspektive falsch aus: Die Waffe schwenkte sichtbar nach vorne, statt
## einfach in der gewohnten Haltung zu bleiben.
##
## `reload_position`/`reload_rotation_degrees` existieren am Modell weiterhin —
## `character_weapon.gd` liest sie fuer die DRITTE Person: Andere Spieler
## sollen sehen, dass jemand nachlaedt (die Waffe geht dort sichtbar hoch als
## Erkennungszeichen). Nur die EIGENE Egoperspektive schwenkt nicht mehr dahin.
func _update_pose(delta: float) -> void:
	if _viewmodel == null:
		return

	var target_pos := _viewmodel.hip_position
	var target_rot := _viewmodel.hip_rotation_degrees
	var weight := clampf(pose_speed * delta, 0.0, 1.0)

	if _sprinting:
		target_pos = _viewmodel.sprint_position
		target_rot = _viewmodel.sprint_rotation_degrees
	elif _aim_progress > 0.0:
		# Zielpose: Die Visierlinie muss exakt auf der Kameramitte landen.
		# Deshalb wird das Modell genau um SEINE Visierhoehe abgesenkt —
		# die ist je Waffe verschieden, eine Pistole zielt tiefer als ein
		# Gewehr mit hoher Schiene.
		var ads_pos := Vector3(0.0, -_viewmodel.sight_height, -_viewmodel.ads_distance)
		target_pos = target_pos.lerp(ads_pos, _aim_progress)
		target_rot = target_rot.lerp(Vector3.ZERO, _aim_progress)

	# Ladehebel-Drehung: Bei einer LEEREN Nachladung dreht die ganze Waffe zur
	# Seite, damit man den Ladehebel sieht, bleibt dort stehen, waehrend er
	# gezogen wird, und dreht danach wieder zurueck. Bei einer taktischen
	# Nachladung (noch Munition im Magazin) bleibt `wants_rack` falsch — die
	# Waffe bleibt in der normalen Haltung.
	#
	# ERST ab _viewmodel.rack_turn_start_progress, NICHT gleich beim Start der
	# Sequenz: Sonst dreht sich die Waffe schon, waehrend das alte Magazin noch
	# draussen haengt — Magazinwechsel und Drehung wuerden gleichzeitig
	# ablaufen statt nacheinander. Derselbe Wert steht am Modell in
	# weapon_viewmodel.gd, wo der Ladehebel selbst erst NOCH spaeter
	# (handle_pull_start_progress) einsetzt — jede Waffe kann beide Grenzen
	# fuer sich selbst verschieben (siehe AKMViewmodel._configure()), ohne dass
	# sie hier und dort auseinanderlaufen.
	#
	# Eine Feder statt eines lerp, aus demselben Grund wie beim Nachschwingen
	# weiter unten: Ein lerp naehert sich der Drehung sauber an und kommt nie
	# darueber hinaus — das wirkt glatt und maschinell. Eine schwach gedaempfte
	# Feder schiesst leicht ueber die Zieldrehung hinaus und federt zurueck,
	# das liest sich als Ruck einer echten Hand.
	var wants_rack := _sequence_kind == &"reload" and _sequence_from_empty \
			and _sequence_progress > _viewmodel.rack_turn_start_progress
	var rack_target := 1.0 if wants_rack else 0.0
	var rack_step := minf(delta, 1.0 / 30.0)
	var rack_accel := (rack_target - _rack_progress) * rack_stiffness - _rack_velocity * rack_damping
	_rack_velocity += rack_accel * rack_step
	_rack_progress += _rack_velocity * rack_step

	target_pos += rack_turn_offset * _rack_progress
	target_rot += rack_turn_rotation * _rack_progress

	_pose.position = _pose.position.lerp(target_pos, weight)
	_pose.rotation_degrees = _pose.rotation_degrees.lerp(target_rot, weight)


## Die Waffe haengt der Blickrichtung hinterher. Ohne das klebt sie starr
## im Bild und wirkt wie aufgemalt.
##
## ---------------------------------------------------------------------------
## FEDER STATT NACHZIEHEN — DARAN HAENGT DAS GEFUEHL
##
## Vorher wurde die Waffe mit `lerp` an ihre Zielhaltung herangezogen. Das ist
## eine Exponentialkurve: Sie naehert sich der Mitte und kommt nie darueber
## hinaus. Die Waffe hinkt beim Drehen hinterher und kriecht dann zurueck —
## sie wirkt, als haenge sie an einem Gummiband.
##
## Jetzt haengt sie an einer Feder mit Masse, wie der Rueckstoss weiter unten.
## Der Unterschied ist der eine Punkt, um den es geht: Eine Feder mit zu wenig
## Daempfung schiesst UEBER die Ruhelage hinaus. Beim Drehen bleibt die Waffe
## erst zurueck, und wenn die Maus stehenbleibt, holt sie nicht nur auf,
## sondern schwingt durch die Mitte hindurch und pendelt sich ein.
##
## Genau in diesem Moment dreht sich die Waffe schneller als der Spieler —
## das ist der Ausschlag, den Insurgency Sandstorm und Bodycam so deutlich
## zeigen. Mit einem lerp ist er nicht zu haben, egal an welcher Zahl man
## dreht: Eine Exponentialkurve kann ihr Ziel nicht ueberholen.
##
## ---------------------------------------------------------------------------
## DER VERSATZ BLEIBT STEHEN, BIS EINE NEUE DREHUNG IHN AUFHEBT
##
## `_look_delta` relaxierte frueher von selbst gegen null — die Waffe schwang
## also immer zurueck zur Mitte, auch wenn der Spieler laengst stillstand.
## Das ist jetzt weg: Wer nach links schaut, bekommt einen Versatz nach links,
## der STEHEN BLEIBT, bis eine Drehung nach rechts ihn wieder abbaut. Nur eine
## neue Mausbewegung veraendert `_look_delta` noch, keine verstreichende Zeit.
##
## Die Klammerung auf den Bereich, den `target` sowieso ausnutzen kann,
## verhindert dabei, dass `_look_delta` bei einer schnellen Drehung ins
## Unermessliche waechst: Ohne sie muesste eine Drehung um 360 Grad erst durch
## eine ebenso grosse Gegendrehung ausgeglichen werden, bevor sich ueberhaupt
## etwas ruehrt.
##
## Die Ausnahme ist das Zielen: Wer zielt, will die Visierlinie in der Mitte
## haben, nicht den zuletzt aufgesammelten Versatz. Deshalb relaxiert
## `_look_delta` NUR waehrend `_aim_progress > 0` — das ist die einzige
## Situation, in der die Waffe von selbst zur Mitte zurueckfindet.
func _update_sway(delta: float) -> void:
	var factor := lerpf(1.0, sway_ads_factor, _aim_progress)

	var max_component := sway_amount / 0.35
	_look_delta.x = clampf(_look_delta.x, -max_component, max_component)
	_look_delta.y = clampf(_look_delta.y, -max_component, max_component)

	var target := Vector2(
		clampf(-_look_delta.x * 0.35, -sway_amount, sway_amount),
		clampf(-_look_delta.y * 0.35, -sway_amount, sway_amount)
	) * factor

	# Bei einem Ruckler waere der Schritt so gross, dass die Feder sich
	# aufschaukelt statt einzupendeln — dann fliegt die Waffe aus dem Bild.
	# Lieber eine Zehntelsekunde zu langsam nachschwingen als einmal explodieren.
	var step := minf(delta, 1.0 / 30.0)

	var accel := (target - _sway_offset) * sway_stiffness - _sway_velocity * sway_damping
	_sway_velocity += accel * step
	_sway_offset += _sway_velocity * step

	if _aim_progress > 0.0:
		_look_delta = _look_delta.lerp(Vector2.ZERO, clampf(12.0 * delta, 0.0, 1.0))

	_sway.rotation_degrees.y = _sway_offset.x
	_sway.rotation_degrees.x = -_sway_offset.y
	# Leichtes Kippen um die Laengsachse macht die Bewegung organischer.
	_sway.rotation_degrees.z = _sway_offset.x * 0.4


func _update_bob(delta: float) -> void:
	var factor := lerpf(1.0, bob_ads_factor, _aim_progress)
	if _speed_ratio <= 0.01:
		# Im Stehen sauber auslaufen lassen statt mitten im Ausschlag einfrieren.
		_sway.position = _sway.position.lerp(Vector3.ZERO, clampf(6.0 * delta, 0.0, 1.0))
		return

	_bob_time += delta * bob_speed * _speed_ratio
	var amount := bob_amount * _speed_ratio * factor
	var target := Vector3(
		sin(_bob_time) * amount,
		-absf(cos(_bob_time)) * amount * 0.8,
		0.0
	)
	_sway.position = _sway.position.lerp(target, clampf(10.0 * delta, 0.0, 1.0))


## Rueckstoss als echte Feder statt als fester Rueckweg. Dadurch schwingt
## die Waffe bei Dauerfeuer auf, statt jedes Mal sauber zurueckzukommen —
## genau das soll Dauerfeuer auf Distanz unattraktiv machen.
func _update_recoil(delta: float) -> void:
	var accel := -_recoil_offset * recoil_stiffness - _recoil_velocity * recoil_damping
	_recoil_velocity += accel * delta
	_recoil_offset += _recoil_velocity * delta

	var angular_accel := -_recoil_angle * recoil_stiffness - _recoil_angular_velocity * recoil_damping
	_recoil_angular_velocity += angular_accel * delta
	_recoil_angle += _recoil_angular_velocity * delta

	_recoil.position = _recoil_offset
	_recoil.rotation_degrees.x = _recoil_angle


## Legt die Haende an die Waffe.
##
## ---------------------------------------------------------------------------
## DIE LINKE HAND VERLAESST DIE WAFFE BEIM NACHLADEN
##
## Die rechte bleibt am Griff — die Waffe haelt man dabei fest. Die linke
## macht den Wechsel: zum Schacht, das leere Magazin heraus, ein neues holen,
## einschieben, Ladehebel durchziehen.
##
## Die Wegmarken kommen aus `CharacterAnimation`, wo derselbe Ablauf fuer die
## Figuren steht. Sie hier abzuschreiben hiesse, dass beide beim naechsten
## Abstimmen auseinanderlaufen — dieselbe Ueberlegung wie bei der
## Nachladedrehung, die aus dem Waffenmodell kommt.
##
## ---------------------------------------------------------------------------
## AUSNAHME: DER LADEHEBEL RECHTS AM GEHAEUSE
##
## Das oben gilt fuer Waffen wie die AR-15, deren Ladehebel mittig hinten
## liegt und von der Stuetzhand ueber das Gehaeuse erreicht wird. Bei einer
## AK sitzt der Hebel rechts, genau dort, wo ohnehin die Schiesshand liegt —
## die zieht ihn, waehrend die linke zurueck an den Handschutz greift und die
## Waffe allein haelt. Welche Rolle gilt, sagt `WeaponViewmodel.right_hand_
## racks_charging_handle`; siehe _grip_hand_while_reloading().
func _update_arms(delta: float) -> void:
	if _arms == null:
		return

	# Nur Waffen mit gemessenen Griffpunkten bekommen Haende. Bei allen
	# anderen fassten sie sichtbar daneben, und das ist schlimmer als gar
	# keine Haende — siehe `shows_hands` in WeaponViewmodel.
	var wanted := (_viewmodel != null and _viewmodel.shows_hands
		and _viewmodel.grip_point != null and _viewmodel.support_point != null)
	if _arms.visible != wanted:
		_arms.visible = wanted
	if not wanted:
		_magazine_hold_blend = 0.0
		return

	var grip := _viewmodel.grip_point.global_position
	var handguard := _viewmodel.support_point.global_position
	var support := handguard

	if _sequence_kind == &"reload" and _sequence_duration > 0.0:
		var progress := 1.0 - _sequence_time_left / _sequence_duration
		var grip_hand_racks := _viewmodel.right_hand_racks_charging_handle \
				and _sequence_from_empty
		support = _support_hand_while_reloading(progress, handguard, grip_hand_racks)
		if grip_hand_racks:
			var handle := handguard
			if _viewmodel.charging_handle != null:
				handle = _viewmodel.charging_handle.global_position
			grip = _grip_hand_while_reloading(progress, grip, handle)

	# Die Hand geht ans Magazin, nicht umgekehrt: Solange es gehalten wird
	# (siehe magazine_held_by_hand in weapon_viewmodel.gd), ist SEINE
	# tatsaechliche Position die Wahrheit — die eigens dafuer gebaute,
	# AK-typische Kippbewegung bleibt unangetastet. Die Hand folgt ihr, statt
	# das Magazin auf einen generischen Handpfad zu zwingen. Gilt fuer jede
	# Waffe mit Haenden, nicht nur die mit vertauschten Rollen.
	#
	# Uebergeblendet wird ueber _magazine_hold_blend (ein reiner Zahlenwert),
	# NICHT ueber eine gespeicherte Weltposition: "support" und die
	# Magazinposition werden hier jeden Frame frisch aus der aktuellen
	# Kamerahaltung berechnet, drehen sich also automatisch mit ihr mit —
	# nur der Uebergang zwischen beiden braucht Zeit. Eine gespeicherte
	# Position wuerde beim schnellen Umsehen dagegen sichtbar zurueckbleiben,
	# weil Griff und Handschutz sich sofort mitdrehen, sie selbst aber nur
	# verzoegert hinterherkaeme.
	var wants_magazine := _viewmodel.magazine != null and _viewmodel.magazine_held_by_hand
	var blend_weight := clampf(hand_reach_speed * delta, 0.0, 1.0)
	_magazine_hold_blend = lerpf(_magazine_hold_blend, 1.0 if wants_magazine else 0.0, blend_weight)
	if _viewmodel.magazine != null and _magazine_hold_blend > 0.001:
		support = support.lerp(_viewmodel.magazine.global_position, _magazine_hold_blend)

	_arms.aim_at(grip, support)


## Wo die linke Hand im jeweiligen Abschnitt des Nachladens ist.
##
## Der Ablauf kommt aus `CharacterAnimation.reload_hand_path()` — dieselbe
## Choreografie, die auch die Figuren im Level laufen. Hier werden nur die
## Punkte eingesetzt, die es im Kameraraum gibt.
##
## `skip_handle`: Bei Waffen, deren rechte Hand den Ladehebel zieht (siehe
## _update_arms()), hat die linke damit nichts zu tun — sie kehrt nach dem
## Einsetzen an den Handschutz zurueck und bleibt dort, statt weiter zum
## Hebel zu greifen.
func _support_hand_while_reloading(progress: float, handguard: Vector3,
		skip_handle: bool = false) -> Vector3:
	if _viewmodel.magwell_point == null:
		return handguard

	var magwell := _viewmodel.magwell_point.global_position
	# Nach unten aus der WAFFE heraus, nicht nach Weltkoordinaten unten: Beim
	# Nachladen ist sie gekippt.
	var down := -_viewmodel.magwell_point.global_basis.y.normalized()
	var pulled := magwell + down * CharacterAnimation.PULL_DISTANCE

	# Beim blossen Durchladen wird kein Magazin gewechselt: Die Hand bleibt am
	# Schaft und zieht nur zum Schluss den Ladehebel — ausser die rechte Hand
	# uebernimmt das, dann bleibt die linke die ganze Zeit am Handschutz.
	if _sequence_chamber_only:
		if skip_handle:
			return handguard
		var handle := magwell
		if _viewmodel.charging_handle != null:
			handle = _viewmodel.charging_handle.global_position
		if progress < CharacterAnimation.RELOAD_SEAT:
			return handguard
		if progress < CharacterAnimation.RELOAD_CHARGE:
			return handguard.lerp(handle,
				smoothstep(CharacterAnimation.RELOAD_SEAT,
					CharacterAnimation.RELOAD_CHARGE, progress))
		return handle.lerp(handguard,
			smoothstep(CharacterAnimation.RELOAD_CHARGE, 1.0, progress))

	# Wo das frische Magazin herkommt. Im Kameraraum gibt es keine Weste, also
	# ein Punkt unten links ausserhalb des Bildes — dorthin greift man auch in
	# Wirklichkeit, zur Tasche an der Brust.
	var pouch: Vector3 = global_transform * POUCH_IN_VIEW

	if skip_handle:
		# WICHTIG: Die linke muss FERTIG sein (schon wieder am Handschutz),
		# BEVOR die rechte ueberhaupt zum Hebel greift — _grip_hand_while_
		# reloading() startet ihre Bewegung erst bei rack_turn_start_progress,
		# und genau dort darf sich die linke nicht mehr bewegen. Die Marken in
		# CharacterAnimation (REACH..CHARGE, siehe reload_hand_path) sind aber
		# auf ein Fenster von 0 bis 1 abgestimmt, das bei WAFFENENDE steht,
		# nicht bei rack_turn_start_progress. Deshalb wird der ganze Wechsel
		# hier zeitlich gestaucht: "handguard" statt "handle" als Fernziel
		# laesst die letzten beiden Abschnitte der Choreografie (statt zum
		# Hebel zu greifen) direkt zum Handschutz zurueckfinden.
		#
		# Das Fenster endet bei magazine_seated_progress, nicht bei
		# rack_turn_start_progress selbst: Genau dort haengt gleichzeitig
		# magazine_held_by_hand (siehe _animate_magazine_swap()) — sobald das
		# Magazin sitzt, laesst die Hand es los und ist damit schon am
		# Handschutz. Dazwischen liegt ohnehin die eingebaute Pause bis
		# rack_turn_start_progress (siehe Kommentar dort) — die liefert den
		# Puffer, kein zusaetzlicher Faktor noetig.
		var window := maxf(0.0001, _viewmodel.magazine_seated_progress)
		var local_progress := minf(1.0, progress / window)
		return CharacterAnimation.reload_hand_path(local_progress, handguard,
			magwell, pulled, pouch, handguard)

	var handle := magwell
	if _viewmodel.charging_handle != null:
		handle = _viewmodel.charging_handle.global_position

	return CharacterAnimation.reload_hand_path(progress, handguard, magwell,
		pulled, pouch, handle)


## Wo die rechte (Griff-)Hand waehrend einer leergeschossenen Nachladung
## zeigt — nur wenn `WeaponViewmodel.right_hand_racks_charging_handle` gilt.
##
## Drei Abschnitte, an denselben Zeitmarken wie die Kameradrehung
## (rack_turn_start_progress, handle_pull_start_progress — siehe dort):
## Griff halten, waehrend die Drehung die Seite zeigt zum Hebel greifen,
## kurz halten und ziehen, dann den GROESSEREN Teil des restlichen Fensters
## fuer den Rueckweg — genau wie verlangt: Zeit, die Hand zurueck an den
## Griff zu bringen, statt sie zurueckschnappen zu lassen.
func _grip_hand_while_reloading(progress: float, grip: Vector3, handle: Vector3) -> Vector3:
	var reach_start := _viewmodel.rack_turn_start_progress
	var pull_start := _viewmodel.handle_pull_start_progress
	if progress < reach_start:
		return grip

	if progress < pull_start:
		return grip.lerp(handle, smoothstep(reach_start, pull_start, progress))

	var release := lerpf(pull_start, 1.0, 0.4)
	if progress < release:
		return handle
	return handle.lerp(grip, smoothstep(release, 1.0, progress))


## Zeitleiste fuer Nachladen und Ladehemmung.
##
## Der Fortschritt wird nur ausgerechnet und weitergereicht — was dabei
## sichtbar passiert, entscheidet das Modell der jeweiligen Waffe. Deshalb
## kann die Flinte hier Patronen einzeln nachschieben, waehrend das Gewehr
## ein Magazin wechselt, ohne dass diese Datei davon etwas wissen muss.
func _update_sequence(delta: float) -> void:
	if _sequence_time_left <= 0.0:
		return

	_sequence_time_left = maxf(0.0, _sequence_time_left - delta)
	var progress := 1.0 - _sequence_time_left / maxf(0.01, _sequence_duration)
	_sequence_progress = progress

	if _viewmodel != null:
		match _sequence_kind:
			&"reload":
				_viewmodel.notify_reload(progress, _sequence_from_empty,
					_sequence_chamber_only)
			&"unjam":
				_viewmodel.notify_unjam(progress)

	if _sequence_time_left <= 0.0:
		_sequence_kind = &""
		if _viewmodel != null:
			_viewmodel.notify_sequence_ended()



# --- Reaktionen auf die Waffe ---

func _on_fired(_ammo: AmmoData, rounds_left: int) -> void:
	# Rueckstoss als Impuls auf die Federgeschwindigkeit, nicht als
	# Positionssprung — sonst ruckelt es statt zu kicken.
	var strength := 1.0
	var aim_recoil_factor := 0.72
	if _weapon != null and _weapon.data != null:
		# Schwere Waffen kicken staerker, gute Ergonomie daempft.
		strength = _weapon.data.recoil_vertical / 120.0
		strength *= 1.0 - float(_weapon.data.ergonomics) / 250.0
		# Derselbe Faktor wie beim tatsaechlichen (kamerawirksamen) Rueckstoss
		# in Weapon._emit_recoil() — siehe ads_recoil_multiplier in
		# weapon_data.gd. Ohne Waffendaten (z. B. im Renderwerkzeug ohne
		# Weapon-Knoten) bleibt der alte feste Wert als Rueckfall.
		aim_recoil_factor = _weapon.data.ads_recoil_multiplier
	# Beim Zielen liegt die Waffe ruhiger an der Schulter.
	strength *= lerpf(1.0, aim_recoil_factor, _aim_progress)
	# Und jede Waffe springt anders — eine Pistole kippt, ein schweres
	# Praezisionsgewehr schiebt.
	if _viewmodel != null:
		strength *= _viewmodel.recoil_scale

	# Wie stark der Rueckstoss nach hinten schiebt gegenueber wie stark er die
	# Muendung hochreisst — je Waffe eigens verschiebbar, siehe
	# recoil_rise_scale/recoil_push_scale in weapon_viewmodel.gd.
	var rise_scale := _viewmodel.recoil_rise_scale if _viewmodel != null else 1.0
	var push_scale := _viewmodel.recoil_push_scale if _viewmodel != null else 1.0

	_recoil_velocity.z += recoil_kick_back * strength * push_scale * 26.0
	_recoil_velocity.y += recoil_kick_back * strength * push_scale * 5.0
	_recoil_angular_velocity += recoil_kick_up * strength * rise_scale * 26.0

	if _viewmodel != null:
		_viewmodel.notify_shot()
		_viewmodel.notify_action_locked(rounds_left <= 0 and not _has_chambered_round())


func _on_dry_fire() -> void:
	if _viewmodel != null:
		_viewmodel.notify_shot_dry()


func _on_reload_started(duration: float, from_empty: bool, chamber_only: bool) -> void:
	_sequence_kind = &"reload"
	_sequence_from_empty = from_empty
	_sequence_chamber_only = chamber_only
	_sequence_duration = duration
	_sequence_time_left = duration


func _on_reload_finished(_rounds: int) -> void:
	if _viewmodel != null:
		_viewmodel.notify_action_locked(false)


func _on_sequence_cancelled() -> void:
	_sequence_time_left = 0.0
	_sequence_kind = &""
	if _viewmodel != null:
		_viewmodel.notify_sequence_ended()


func _on_jammed() -> void:
	if _viewmodel != null:
		_viewmodel.notify_action_locked(true)


func _on_unjam_started(duration: float) -> void:
	_sequence_kind = &"unjam"
	_sequence_duration = duration
	_sequence_time_left = duration


func _on_unjammed() -> void:
	if _viewmodel != null:
		_viewmodel.notify_action_locked(false)


func _on_fire_mode_changed(mode: WeaponData.FireMode) -> void:
	if _viewmodel != null:
		_viewmodel.notify_fire_mode(mode)


func _has_chambered_round() -> bool:
	return _weapon != null and _weapon.round_chambered
