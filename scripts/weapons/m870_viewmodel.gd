## Remington 870 — Vorderschaftrepetierflinte, 12/70, Roehrenmagazin.
##
## Charakter: brutal auf kurze Distanz, danach hilflos. Jeder Schuss kostet
## eine bewusste Handlung, und Nachladen dauert ewig, weil jede Patrone
## einzeln in die Roehre wandert.
##
## EIGENE MECHANIK — hier weicht fast alles vom Gewehr ab:
##   - Der Vorderschaft wird von Hand repetiert. Die Bewegung ist lang und
##     traege, nicht das kurze Zucken eines Selbstladers
##   - Es gibt KEIN abnehmbares Magazin. Deshalb existiert der Magazine-Knoten
##     hier gar nicht, und die Nachladeanimation zeigt stattdessen, wie
##     Patronen einzeln von unten eingeschoben werden
class_name M870Viewmodel
extends WeaponViewmodel

const BORE_Y := 0.016

## Wie viele Patronen die Nachladeanimation sichtbar einschiebt.
## Rein optisch — wie viele wirklich ankommen, entscheidet weapon.gd.
const SHELLS_PER_RELOAD := 5

var _mats: Dictionary

## Vorderschaft beim Repetieren und beim Einschieben von Patronen.
var _pump_cycle: float = 0.0
var _shell_push: float = 0.0


func get_model_name() -> String:
	return "m870"


func _configure() -> void:
	sight_height = 0.042
	muzzle_z = -0.640
	# Schwerste Waffe im Arsenal, entsprechend wuchtig im Bild.
	recoil_scale = 1.9
	action_travel = 0.095
	# Ein Mensch repetiert langsamer, als ein Gasdrucklader zyklisiert.
	action_cycle_time = 0.34
	hip_position = Vector3(0.120, -0.140, -0.200)
	hip_rotation_degrees = Vector3(0.0, -3.0, 0.0)


func _build_parts() -> void:
	_mats = ViewmodelParts.materials()
	_build_receiver()
	_build_barrel()
	_build_stock()
	_build_sights()
	_build_moving_parts()

	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	add_child(ViewmodelParts.pivot("EjectPoint", Vector3(0.028, 0.020, -0.130)))

	# Aufnahmen. Kein Griff und kein Vordergriff: Beides ist bei einer
	# Vorderschaftrepetierflinte fest mit der Waffe verbunden - der
	# Vorderschaft IST das bewegliche Teil.
	# Schiene auf dem Gehaeuse, dort wo sonst die Kerbe sitzt.
	add_child(ViewmodelParts.pivot("MountSight", Vector3(0.0, 0.046, -0.060)))
	# Gewinde am Laufende.
	add_child(ViewmodelParts.pivot("MountMuzzle", Vector3(0.0, BORE_Y, -0.610)))


func _build_receiver() -> void:
	var blued: Material = _mats["blued"]
	var steel: Material = _mats["steel"]
	var black: Material = _mats["black"]

	add_child(ViewmodelParts.box("Receiver", Vector3(0.042, 0.058, 0.185), Vector3(0.0, 0.006, -0.118), blued))
	add_child(ViewmodelParts.box("ReceiverTop", Vector3(0.032, 0.010, 0.185), Vector3(0.0, 0.038, -0.118), blued))
	add_child(ViewmodelParts.box("EjectionPort", Vector3(0.006, 0.024, 0.060), Vector3(0.022, 0.012, -0.130), black))
	# Die Ladeoeffnung unten — dort verschwinden die Patronen beim Nachladen.
	add_child(ViewmodelParts.box("LoadingGate", Vector3(0.026, 0.006, 0.058), Vector3(0.0, -0.024, -0.128), black))

	add_child(ViewmodelParts.box("GuardBody", Vector3(0.030, 0.020, 0.062), Vector3(0.0, -0.034, -0.086), steel))
	add_child(ViewmodelParts.box("GuardBottom", Vector3(0.010, 0.006, 0.052), Vector3(0.0, -0.052, -0.082), steel))
	add_child(ViewmodelParts.box("SafetyButton", Vector3(0.020, 0.008, 0.008), Vector3(0.0, -0.030, -0.056), black,
		Vector3(0.0, 0.0, 90.0)))


func _build_barrel() -> void:
	var blued: Material = _mats["blued"]
	var steel: Material = _mats["steel"]

	add_child(ViewmodelParts.cylinder("Barrel", 0.0125, 0.480, Vector3(0.0, BORE_Y, -0.400), blued))
	# Die Laufschiene oben — darauf sitzt das Korn.
	add_child(ViewmodelParts.box("VentRib", Vector3(0.012, 0.005, 0.460), Vector3(0.0, BORE_Y + 0.017, -0.400), blued))
	for i in range(12):
		add_child(ViewmodelParts.box("RibPost%d" % i, Vector3(0.008, 0.008, 0.006),
			Vector3(0.0, BORE_Y + 0.010, -0.190 - float(i) * 0.036), blued))

	# Roehrenmagazin unter dem Lauf. Das ist die "Munitionsanzeige" dieser
	# Waffe — man sieht ihm nichts an, und genau das macht sie unheimlich.
	add_child(ViewmodelParts.cylinder("MagazineTube", 0.0110, 0.370, Vector3(0.0, BORE_Y - 0.026, -0.345), blued))
	add_child(ViewmodelParts.cylinder("TubeCap", 0.0125, 0.024, Vector3(0.0, BORE_Y - 0.026, -0.522), steel))
	add_child(ViewmodelParts.box("BarrelClamp", Vector3(0.030, 0.048, 0.018), Vector3(0.0, BORE_Y - 0.010, -0.512), steel))


func _build_stock() -> void:
	var wood: Material = _mats["wood"]
	var black: Material = _mats["black"]

	# ACHTUNG, WIEDERHOLTER FEHLER: Diese Teile stehen bewusst an absoluten
	# Positionen und tragen ihre Neigung jeweils selbst. Ein gemeinsamer,
	# gedrehter Elternknoten sieht aufgeraeumter aus, dreht aber auch die
	# POSITIONEN mit — beim ersten Versuch ist der Schaft dadurch nach hinten
	# unten weggewandert und hing sichtbar neben dem Gehaeuse.
	#
	# Der Hals ragt bewusst ein Stueck ins Gehaeuse hinein. Auf Stoss gesetzt
	# klafft bei der kleinsten Aenderung eine Fuge.
	# WICHTIG IST DIE OBERKANTE: Das Gehaeuse endet bei y = 0.035. Vorher lag
	# der Hals 2 cm tiefer, und dieser Absatz direkt hinter dem Gehaeuse las
	# sich aus jeder Entfernung als Luecke — obwohl sich die Teile beruehrten.
	# Der Ruecken laeuft jetzt fast auf einer Linie weiter und faellt erst
	# nach hinten ab, so wie bei einer echten Flinte.
	add_child(ViewmodelParts.box("StockWrist", Vector3(0.032, 0.058, 0.115), Vector3(0.0, 0.000, 0.028),
		wood, Vector3(7.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("StockComb", Vector3(0.030, 0.034, 0.130), Vector3(0.0, 0.010, 0.100),
		wood, Vector3(7.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("StockBody", Vector3(0.038, 0.064, 0.125), Vector3(0.0, -0.020, 0.108),
		wood, Vector3(7.0, 0.0, 0.0)))
	add_child(ViewmodelParts.box("ButtPad", Vector3(0.040, 0.088, 0.014), Vector3(0.0, -0.014, 0.176),
		black, Vector3(7.0, 0.0, 0.0)))


func _build_sights() -> void:
	var black: Material = _mats["black"]
	var steel: Material = _mats["steel"]

	# Kerbe hinten auf dem Gehaeuse.
	var rear := ViewmodelParts.pivot("RearSight", Vector3(0.0, sight_height, -0.040))
	rear.add_child(ViewmodelParts.box("RearBlockL", Vector3(0.008, 0.012, 0.010), Vector3(-0.009, 0.0, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearBlockR", Vector3(0.008, 0.012, 0.010), Vector3(0.009, 0.0, 0.0), black))
	rear.add_child(ViewmodelParts.box("RearBase", Vector3(0.026, 0.006, 0.012), Vector3(0.0, -0.007, 0.0), black))
	add_child(rear)

	# Vorne nur eine Perle auf der Schiene — mehr braucht eine Flinte nicht.
	var front := ViewmodelParts.pivot("FrontSight", Vector3(0.0, sight_height, -0.615))
	front.add_child(ViewmodelParts.box("BeadPost", Vector3(0.004, 0.010, 0.004), Vector3(0.0, -0.005, 0.0), black))
	front.add_child(ViewmodelParts.torus("Bead", 0.001, 0.005, Vector3.ZERO, steel, Vector3(90.0, 0.0, 0.0)))
	add_child(front)


func _build_moving_parts() -> void:
	var wood: Material = _mats["wood"]
	var steel: Material = _mats["steel"]

	# Der Vorderschaft ist die "Action" dieser Waffe. Er umschliesst das
	# Roehrenmagazin und wird von Hand hin und her geschoben.
	var pump := ViewmodelParts.pivot("Action", Vector3(0.0, BORE_Y - 0.026, -0.330))
	pump.add_child(ViewmodelParts.box("PumpBody", Vector3(0.046, 0.042, 0.140), Vector3.ZERO, wood))
	# Vorn und hinten leicht schmaler — der Vorderschaft einer 870 laeuft an
	# beiden Enden aus, statt ein Kasten zu sein.
	pump.add_child(ViewmodelParts.box("PumpFront", Vector3(0.038, 0.034, 0.024), Vector3(0.0, 0.0, -0.078), wood))
	pump.add_child(ViewmodelParts.box("PumpRear", Vector3(0.038, 0.034, 0.024), Vector3(0.0, 0.0, 0.078), wood))

	# Laengsrillen an beiden Seiten und unten.
	#
	# Vorher waren das quer liegende Bloecke, die BREITER als der Schaft
	# selbst waren — sie standen links und rechts als Flossen ab, und der
	# Vorderschaft sah aus wie ein Blech mit Rippen. Rillen an einer
	# Vorderschaftrepetierflinte laufen laengs, in Schubrichtung.
	for side in [-1.0, 1.0]:
		pump.add_child(ViewmodelParts.ribs("PumpRib%s" % ("L" if side < 0.0 else "R"), 5,
			Vector3(0.004, 0.005, 0.120),
			Vector3(side * 0.0225, -0.014, 0.0), Vector3(0.0, 0.007, 0.0), _mats["black"]))
	pump.add_child(ViewmodelParts.ribs("PumpRibBottom", 4, Vector3(0.005, 0.004, 0.120),
		Vector3(-0.0105, -0.0205, 0.0), Vector3(0.007, 0.0, 0.0), _mats["black"]))
	add_child(pump)

	var trigger_pivot := ViewmodelParts.pivot("Trigger", Vector3(0.0, -0.038, -0.084))
	trigger_pivot.add_child(ViewmodelParts.box("TriggerBlade", Vector3(0.007, 0.022, 0.008), Vector3(0.0, -0.011, 0.0),
		steel, Vector3(8.0, 0.0, 0.0)))
	add_child(trigger_pivot)


## Repetieren statt zyklisieren: Der Vorderschaft geht weit zurueck und
## kommt wieder vor. Das dauert lange genug, dass der Spieler es als eigene
## Handlung wahrnimmt — anders als der kaum sichtbare Verschluss der AR-15.
func notify_shot() -> void:
	_pump_cycle = action_cycle_time
	_trigger_pull = 1.0


## Es gibt kein Magazin zum Wechseln. Stattdessen werden Patronen einzeln
## von unten in die Roehre geschoben — sichtbar als Folge kurzer Stoesse,
## damit der Spieler mitzaehlen kann, wie lange es noch dauert.
func notify_reload(progress: float, _from_empty: bool,
		chamber_only: bool = false) -> void:
	_handle_pull = 0.0

	# Volle Roehre, leerer Lauf: Es wird nichts nachgeschoben, nur einmal
	# durchrepetiert. Ohne das schiebt die Flinte sichtbar Patronen nach, die
	# sie gar nicht hat.
	if chamber_only:
		_shell_push = 0.0
		_pump_cycle = maxf(_pump_cycle, action_cycle_time * sin(progress * PI))
		return

	var phase: float = fposmod(progress * float(SHELLS_PER_RELOAD), 1.0)
	# Jede Patrone: kurzer Druck nach oben, dann zurueck.
	_shell_push = sin(clampf(phase, 0.0, 0.55) / 0.55 * PI)

	# Zum Schluss einmal durchrepetieren, damit die erste Patrone im Lauf ist.
	if progress > 0.88:
		_pump_cycle = maxf(_pump_cycle, action_cycle_time * _ramp(progress, 0.88, 1.0))


func notify_unjam(progress: float) -> void:
	# Eine klemmende Flinte wird durchgerissen, nicht am Ladehebel gezupft.
	_pump_cycle = maxf(_pump_cycle, action_cycle_time * sin(progress * PI))


func update_mechanics(delta: float) -> void:
	if _pump_cycle > 0.0:
		_pump_cycle = maxf(0.0, _pump_cycle - delta)

	if action != null:
		var travel := 0.0
		if _action_locked:
			travel = 1.0
		elif _pump_cycle > 0.0:
			travel = sin((1.0 - _pump_cycle / action_cycle_time) * PI)
		# Beim Einschieben einer Patrone wippt der Vorderschaft leicht mit.
		action.position = _action_home + Vector3(0.0, _shell_push * 0.006, travel * action_travel)

	if trigger != null:
		_trigger_pull = maxf(0.0, _trigger_pull - delta * 9.0)
		trigger.rotation_degrees.x = -_trigger_pull * 14.0

	_shell_push = maxf(0.0, _shell_push - delta * 2.5)


func notify_sequence_ended() -> void:
	_shell_push = 0.0
