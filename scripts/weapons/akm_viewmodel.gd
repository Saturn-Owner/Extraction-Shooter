## AKM — Sturmgewehr, Langhubkolben, 7,62x39.
##
## Charakter: schwerer und stumpfer als die AR-15. Kraeftiger Rueckstoss,
## traegeres Handling — dafuer unempfindlich.
##
## ---------------------------------------------------------------------------
## DIESES MODELL KOMMT ALS .glb, NICHT AUS QUADERN
##
## Frueher war die AKM prozedural aus Quadern gebaut. Jetzt liegt ein echtes
## Modell unter assets/models/weapons/akm/ (Lucas' Vorlage, CC0 von Sketchfab).
## Abzug bewegt sich nicht einzeln — dafuer gibt es im Modell keine eigene
## Geometrie. Rueckstoss und Schwingen macht weapon_view.gd auf der ganzen
## Waffe, das bleibt.
##
## Magazin und Ladehebel sind die Ausnahme: Beide stecken im GLB bereits als
## eigene Mesh-Knoten ("pmag_001_pmag7_0", "barrel_002_barrel_0_001" — Namen
## aus der Sketchfab-Konvertierung, nicht selbst gewaehlt), nur ohne
## beweglichen Elternknoten. Statt in Blender neu zu exportieren, werden sie
## beim Laden aus dem Modellbaum herausgeloest — siehe _extract_part().
##
## Das Modell wird beim Laden VERMESSEN und selbst passend gesetzt: Sketchfab-
## Modelle kommen in beliebiger Groesse und Ausrichtung. Kommt es verdreht oder
## zu gross, dreht man an den drei Konstanten unten — kein Rechnen im Kopf.
class_name AKMViewmodel
extends WeaponViewmodel

const MODEL := "res://assets/models/weapons/akm/akm.glb"

## Hoehe der Laufachse ueber dem Modellursprung.
const BORE_Y := 0.014

## Hoehe der Visierlinie ueber dem Modellursprung — GEMESSEN, nicht geraten.
##
## Diese Zahl ist nach oben UND nach unten eingeklemmt, und beide Grenzen
## liegen nur drei Millimeter auseinander:
##
##   oben   Das Korn endet bei y = 0.0880. Wer die Linie hoeher legt, zielt
##          ueber die eigene Visierung hinweg.
##   unten  Zwischen den Visieren sitzt bei z = -0.32 ein Aufbau am Gehaeuse,
##          der bis y = 0.0858 reicht — und der steht dem Auge dreissig
##          Zentimeter naeher als das Korn. Liegt die Linie tiefer als 0.0855,
##          verdeckt dieser Aufbau das Korn vollstaendig.
##
## Diese Enge ist keine Schlamperei, sondern liegt am Modell: Es ist ein AK mit
## durchgehender Schiene, gebaut fuer eine Optik. Wer wirklich ein AK-Zielbild
## will, braucht in Blender ein hoeheres Korn — dann wird hier eine Zahl
## geaendert und sonst nichts.
const SIGHT_LINE := 0.0865

## Hinteres Ende der Visierlinie: die Schienenoberkante (gemessen y = 0.0824)
## kurz vor dem Schaft. Dort laege eine Kimme, wenn die Waffe eine haette.
const REAR_SIGHT_Z := -0.205

## Wo das Korn im Modell steckt — gemessen am hoechsten Punkt der Waffe.
const FRONT_SIGHT_Z := -0.530

## Gemessen mit einem Godot-Skript (nicht geschaetzt): Groesse und Mittelpunkt
## des Modells in seinem eigenen Raum. Daraus faellt die Lage in der Hand.
## Wird eine ANDERE Waffe exportiert, hier neu vermessen und eintragen.
const MODEL_SIZE := Vector3(0.071, 0.268, 1.017)
const MODEL_CENTRE := Vector3(-0.009, 0.106, -0.163)

# --- Anpassung, falls das Modell verdreht oder falsch gross sitzt ------------

## Gewuenschte Gesamtlaenge im Kameraraum. Das Modell wird darauf skaliert,
## egal wie gross es aus Blender kam.
const FIT_LENGTH := 0.56

## Neigt die Waffe um die Querachse. Zeigt der Lauf nach UNTEN oder OBEN statt
## nach vorn, hier drehen. Das Modell kam mit dem Lauf nach unten.
const FIT_PITCH_DEG := 0.0

## Dreht die Waffe um die Hochachse. Zeigt der Lauf nach HINTEN statt nach
## vorn, hier auf 180 stellen.
const FIT_YAW_DEG := 180.0

## Rollt die Waffe um die Laufachse. Steht sie auf dem Kopf oder auf der Seite,
## hier 180 oder 90 eintragen.
const FIT_ROLL_DEG := 0.0

## Verschiebt das Modell im Kameraraum, NACHDEM es gedreht und gesetzt wurde.
##
## Rueckt die VISIERUNG auf die Bildmitte — und sonst nichts.
##
## `weapon_view` zieht die Waffe beim Zielen auf x = 0 und senkt sie um
## `sight_height`. Das setzt voraus, dass die Visierung im Modell genau dort
## sitzt. Tut sie es nicht — weil das Modell sie leicht neben der Mitte hat —,
## wird der Versatz hier ausgeglichen.
##
## NICHT fuer den Bildausschnitt benutzen: Diese Verschiebung wirkt in JEDER
## Haltung, auch beim Zielen. Wie die Waffe im Hueftanschlag sitzt, gehoert in
## `hip_position`, die beim Zielen weggeblendet wird.
## GEMESSEN: Die Waffe steht in ihrer eigenen Datei nicht mittig. Ihre
## Laengsachse — Lauf, Schiene, Kornring — liegt bei x = -0.0053. Zentriert
## wurde beim Einpassen die HUELLE des Modells, und die ist unsymmetrisch,
## weil Ladehebel und Auswurffenster rechts sitzen.
##
## Ohne diesen Ausgleich zielt man 5 mm neben der eigenen Waffe vorbei: Die
## Kamera steht auf x = 0, die Visierung auf x = -0.0053.
const FIT_OFFSET := Vector3(0.0053, 0.0, 0.0)


func get_model_name() -> String:
	return "akm"


func _configure() -> void:
	# Dieselbe Zahl, auf der die Kerbe der Kimme steht. `weapon_view` senkt die
	# Waffe beim Zielen um genau diesen Wert ab — damit landet die Visierlinie
	# auf der Bildmitte, und zwar ohne dass hier irgendetwas nachjustiert
	# werden muesste. Wer SIGHT_LINE aendert, aendert beides zugleich.
	sight_height = SIGHT_LINE

	# Wie weit die Waffe beim Zielen vor dem Auge steht.
	#
	# Vorher stand hier 0.015 — die Waffe lag damit im Auge. Das hintere Ende
	# des Schaftes sass anderthalb Zentimeter vor der Kamera und fuellte den
	# halben Bildschirm; vom Zielbild war nichts uebrig. Naeher heisst hier
	# NICHT besser: Was dicht vor dem Auge steht, wird riesig, und die Waffe
	# ist von der Muendung bis zum Schaftende ueber einen halben Meter lang.
	#
	# NEGATIV — die Waffe wird beim Zielen hinter die Kamera gezogen.
	#
	# Das klingt falsch und ist genau der Punkt: Die Schulterstuetze reicht im
	# Modell von z = -0.16 bis z = 0 und stand sonst immer im Bild. Sie
	# verschwindet erst, wenn sie hinter die Nahgrenze der Kamera rutscht
	# (0.05, siehe scenes/player/player.tscn) — dort wird sie weggeschnitten.
	# Bei -0.09 ist von ihr nichts mehr zu sehen; uebrig bleiben Gehaeuse,
	# Gasblock, Handschutz und Korn.
	#
	# Nicht weiter zurueck: Ab etwa -0.12 schneidet die Nahgrenze mitten durch
	# das Gehaeuse, und man schaut von innen dagegen — als heller Fleck neben
	# dem Ladehebel deutlich zu sehen.
	#
	# Diese Zahl gilt NUR fuers Zielen. Wie die Waffe sonst in der Hand liegt,
	# steht in hip_position und bleibt davon unberuehrt.
	ads_distance = -0.09
	muzzle_z = -0.560
	# Erst stark gesenkt (1.35 -> 0.85), dann auf Wunsch ein Stueck wieder
	# angehoben — spuerbar mehr als 0.85, aber bei weitem nicht zurueck zum
	# anfaenglichen 1.35. rifle_akm.tres' recoil_vertical/recoil_horizontal
	# wurden im gleichen Schritt mit angehoben, damit Bild und tatsaechliche
	# Zielgenauigkeit weiterhin zusammenpassen.
	recoil_scale = 1.0

	# Erst auf ein ausgewogenes Verhaeltnis gebracht (0.45 gegen 1.6), dann auf
	# Wunsch das Hochreissen der Muendung wieder verstaerkt — rifle_akm.tres'
	# recoil_vertical (der tatsaechliche Aufschlag, der die Kamera hebt) wurde
	# im selben Schritt mit angehoben, damit Bild und echter Rueckstoss
	# weiterhin zusammenpassen.
	recoil_rise_scale = 0.8
	recoil_push_scale = 1.6
	action_travel = 0.090
	action_cycle_time = 0.062
	magazine_drop = 0.40

	# Eigene Zeitleiste fuer die leere Nachladung: `_animate_magazine_swap()`
	# ist hier ueberschrieben und braucht mit dem "Dog-Leg"-Kippschwung mehr
	# Platz als die geerbte Version (siehe dort und rifle_akm.tres, wo
	# reload_time_empty deshalb auf 4.2 s angehoben ist). Ohne mehr Zeit waere
	# fuer Drehen, Warten und Ziehen kaum mehr als eine Zehntelsekunde uebrig
	# gewesen — das lief alles wie eine einzige verwaschene Bewegung ab, statt
	# als getrennte Handgriffe erkennbar zu sein.
	#
	# MAG_IN_END (siehe unten) endet bei 0.63 statt der geerbten 0.85 — danach
	# bleiben 37 % der (laengeren) Zeit fuer Pause, Drehen, Pause und Ziehen,
	# statt der engen 15 % der Grundklasse.
	rack_turn_start_progress = 0.68
	handle_pull_start_progress = 0.88

	# Das Magazin sitzt hier schon bei MAG_IN_END (0.63), nicht erst bei der
	# geerbten 0.85 — siehe dort. weapon_view.gd braucht diese Zahl, um die
	# Stuetzhand rechtzeitig vor der Drehung an den Handschutz zurueckkehren
	# zu lassen (siehe magazine_seated_progress in weapon_viewmodel.gd) und um
	# das Magazin nur bis dahin an die Hand zu binden.
	magazine_seated_progress = MAG_IN_END

	# Der Bildausschnitt im Hueftanschlag gehoert HIERHER und nicht in die
	# Modellverschiebung: `weapon_view` blendet die Hueftposition beim Zielen
	# aus, die Modellverschiebung nicht. Wer die Waffe ueber das Modell
	# zurechtruecht, verschiebt die Visierung mit und zielt daneben.
	#
	# Weiter zur Mitte als die AR-15 (0.115) und nach hinten statt nach vorn
	# (die Grundwerte schieben um -0.22 nach vorn): Dieses Modell ist laenger
	# und ragt sonst mit dem Kolben ins Bild.
	hip_position = Vector3(0.075, -0.125, 0.06)


func _build_parts() -> void:
	_build_body()
	_build_sight_points()

	# Die Mündung sitzt am vorderen Ende der Laufachse — daran haengen
	# Muendungsfeuer und der Ausgangspunkt der Kugel.
	add_child(ViewmodelParts.pivot("MuzzlePoint", Vector3(0.0, BORE_Y, muzzle_z)))
	# Wo die Huelse ausgeworfen wird: rechts am Gehaeuse.
	add_child(ViewmodelParts.pivot("EjectPoint", Vector3(0.028, 0.030, -0.120)))

	# Leerer Ankerpunkt fuer den Verschluss.
	#
	# Fuer ihn gibt es im Modell keine eigene Geometrie — es gibt hier nichts,
	# was sich einzeln bewegt. Der Punkt existiert trotzdem: `_collect_parts()`
	# findet ihn, die Zusage "jede Waffe hat diese Teile" bleibt wahr, und wenn
	# das Modell spaeter in Blender zerlegt wird, haengt der Verschluss genau
	# hier. Solange er leer ist, bewegt die Mechanik nur Luft — ohne Schaden.
	add_child(ViewmodelParts.pivot("Action", Vector3(0.019, 0.030, -0.120)))
	add_child(ViewmodelParts.pivot("Trigger", Vector3(0.0, -0.020, -0.086)))

	_build_hand_points()


## Setzt die beiden Punkte, ueber die gezielt wird — ohne Geometrie.
##
## ---------------------------------------------------------------------------
## HIER STEHT ABSICHTLICH NICHTS IM BILD
##
## Diese Waffe hat keine sichtbare Kimme. Sie ist ein umgebautes AK mit
## durchgehender Schiene: vorn ein Korn im Ring, hinten eine leere Schiene.
## Gezielt wird ueber die Schiene, so wie bei der AR-15 auch.
##
## Es gab hier einmal eine aus Quadern gebaute Kimme. Sie hat getan, was sie
## sollte, und wurde trotzdem wieder entfernt: Lucas will die Waffe so sehen,
## wie sie aus Blender kommt. Die Zahlen, die sie hinterlassen hat, bleiben —
## an ihnen haengt die Zielhaltung, und sie sind gemessen, nicht geraten.
##
## Die Punkte selbst sind leer und im Spiel unsichtbar. Sie stehen trotzdem
## hier, weil `verify_weapon_handling` an ihnen die Visierlinie nachrechnet:
## gleiche Hoehe, mittig, Korn vor Kimme — und vor allem, ob zwischen beiden
## ueberhaupt freie Sicht besteht. Genau diese Pruefung haette den Fehler
## gefunden, an dem hier zwei Nachmittage draufgegangen sind.
func _build_sight_points() -> void:
	# Das Korn steckt im Modell und ist kein eigener Knoten. Dieser Punkt sagt,
	# wo es sitzt — gemessen, nicht gesetzt: Der Kornring endet bei y = 0.0880,
	# z = -0.53. Wer das Modell austauscht, sieht hier, welche Zahl nachgemessen
	# gehoert.
	add_child(ViewmodelParts.pivot("FrontSight",
			Vector3(0.0, SIGHT_LINE, FRONT_SIGHT_Z)))

	# Das hintere Ende der Visierlinie: die Schienenoberkante kurz vor dem
	# Schaft. Dort laege eine Kimme, wenn die Waffe eine haette.
	add_child(ViewmodelParts.pivot("RearSight",
			Vector3(0.0, SIGHT_LINE, REAR_SIGHT_Z)))


## Wo die Haende anfassen — wie bei der AR-15 (siehe dort), aber am
## AK-typischen Griff und Handschutz dieses Modells gemessen.
##
## ---------------------------------------------------------------------------
## AM MODELL GEMESSEN, NICHT VOM ANDEREN GEWEHR UEBERNOMMEN
##
## Der Pistolengriff ist ein eigenes Mesh im GLB ("agr47_001_agr47_0",
## gefunden wie Magazin und Ladehebel per Einfaerben und Rendern). Seine AABB
## im Kameraraum: z von -0,228 bis -0,179, y von -0,028 bis 0,042. GripPoint
## liegt in der Mitte der Tiefe und im unteren Drittel der Hoehe — dort, wo
## sich eine Faust um den Griff schliesst, nicht an seiner Oberkante, wo er
## in den Abzugsbuegel uebergeht.
##
## Der Handschutz ("cmrd_001_cmrd_0") reicht von z = -0,521 bis -0,330, y von
## 0,039 bis 0,082 — das ist die GANZE Rohrdicke samt Oberschiene, keine 4,3 cm
## Luft darueber. Eine erste Fassung setzte die Hoehe geschaetzt auf -0,015
## und liess die Stuetzhand sichtbar frei neben der Waffe schweben, weit
## unterhalb jeder Geometrie — sichtbar in einem Testrender mit Markierungen
## an allen drei Punkten, nicht erst im Spiel. Jetzt an der Unterkante des
## gemessenen Rohrs: Die Hand umschliesst es von unten.
##
## In der Tiefe sitzt sie in der Mitte des Handschutzes, nicht an seinem
## hinteren Ende: Anders als bei der AR-15 sitzt die AKM naeher an der
## Bildmitte (hip_position.x = 0,075 gegen 0,115), das Risiko, durch den
## eigenen Torso zu greifen, ist entsprechend kleiner.
##
## shows_hands wird erst HIER gesetzt, nicht vorher: Der Schalter gilt fuer
## das ganze Modell, aber die Begruendung gehoert zu den Punkten, die ihn
## rechtfertigen.
func _build_hand_points() -> void:
	shows_hands = true

	# Der Ladehebel steckt rechts am Gehaeuse (siehe MOUNT-Kommentar zu
	# "barrel_002_barrel_0_001" in _build_body()) — genau dort, wo die
	# Schiesshand liegt. Die zieht ihn, waehrend die Stuetzhand an den
	# Handschutz zurueckkehrt und die Waffe allein haelt. Anders als beim
	# AR-15, dessen Ladehebel mittig hinten sitzt und nur von der Stuetzhand
	# ueber das Gehaeuse zu erreichen ist.
	right_hand_racks_charging_handle = true

	add_child(ViewmodelParts.pivot("GripPoint", Vector3(0.0, -0.005, -0.204)))
	add_child(ViewmodelParts.pivot("SupportPoint", Vector3(0.0, 0.032, -0.425)))

	# Magazinschacht: am unteren Drittel des sitzenden Magazins (y von -0,060
	# bis 0,055), in der Mitte seiner Tiefe (z von -0,349 bis -0,264) — genau
	# wie bei der AR-15 gemessen, nur mit den Massen dieses Magazins.
	add_child(ViewmodelParts.pivot("MagwellPoint", Vector3(0.0, -0.022, -0.307)))


# --- Eigene Zeitleiste fuer den Magazinwechsel: der AK-typische "Dog-Leg" ---

## Bruchteile von notify_reload()s progress, an denen die drei Abschnitte
## enden. Anders als die geerbte Version (0/0.30/0.45/0.85) endet der
## Wechsel schon bei 0.63 — der Rest der (laengeren) Nachladezeit gehoert der
## Drehung und dem Ladehebelzug, siehe rack_turn_start_progress in
## _configure().
const MAG_OUT_END := 0.22
const MAG_GAP_END := 0.33
const MAG_IN_END := 0.63

## Wie weit das Magazin beim Kippen nach vorn (Richtung Muendung, -Z) wandert.
const MAG_FORWARD_PULL := 0.035

## Neigung im ersten Moment des Herausziehens — die vordere Nase loest sich
## aus dem Magazinschacht. Deutlich mehr als ein Wackeln, das ist die ganze
## Bewegung, die die AKM von einem AR-Magazin unterscheidet.
const MAG_TILT_DEG := 30.0

## Neigung, in der das Magazin haengt, waehrend es in der Luft ist — spuerbar
## weniger als der anfaengliche Kipp-Winkel, aber nicht ganz gerade.
const MAG_HANG_DEG := 10.0

## Der AK-typische Kippschwung statt eines geraden Zugs nach unten.
##
## ---------------------------------------------------------------------------
## WARUM DIESE WAFFE EINE EIGENE VERSION BRAUCHT
##
## Ein AR-Magazin haelt nur ein Widerlager im Schacht und ein Federknopf loest
## es — gerade rein, gerade raus, das kann die geerbte `_animate_magazine_
## swap()` in weapon_viewmodel.gd bereits. Ein AK-Magazin hat vorn zusaetzlich
## eine Nase, die in eine Aussparung im Schacht greift: Zum Entnehmen wird die
## Waffe (oder das Magazin) zuerst nach vorn gekippt, damit die Nase frei
## kommt — erst DANACH laesst sich das Magazin gerade herausziehen. Beim
## Einsetzen umgekehrt: Nase zuerst vorn einhaken, dann das Magazin nach
## hinten kippen, bis der hintere Fanghebel einrastet.
##
## Jeder der beiden sichtbaren Abschnitte (heraus, hinein) ist deshalb selbst
## nochmal zweigeteilt: erst die Kippbewegung (viel Drehung, wenig Versatz),
## dann der gerade Zug (viel Versatz, die Drehung faellt auf einen natuerlichen
## Haltewinkel zurueck). Die Werte an jeder Nahtstelle sind bewusst so
## gewaehlt, dass sie ineinander uebergehen, statt zu springen — sonst zuckt
## das Magazin sichtbar beim Wechsel zwischen den beiden Haelften.
func _animate_magazine_swap(progress: float) -> void:
	if magazine == null:
		return

	if progress < MAG_OUT_END:
		var half := MAG_OUT_END * 0.5
		if progress < half:
			# Kippen: die Nase loest sich, kaum Hoehenverlust.
			var t := _ramp(progress, 0.0, half)
			magazine.visible = true
			magazine.position = _magazine_home + Vector3(
					0.0, -magazine_drop * 0.12 * t, -MAG_FORWARD_PULL * t)
			magazine.rotation_degrees = Vector3(MAG_TILT_DEG * t, 0.0, 4.0 * t)
		else:
			# Gerader Zug: den Rest der Strecke nach unten und heraus, die
			# Neigung faellt auf den Haltewinkel in der Luft zurueck.
			var t := _ramp(progress, half, MAG_OUT_END)
			magazine.visible = true
			magazine.position = _magazine_home + Vector3(0.0,
					lerpf(-magazine_drop * 0.12, -magazine_drop, t),
					lerpf(-MAG_FORWARD_PULL, -MAG_FORWARD_PULL * 0.3, t))
			magazine.rotation_degrees = Vector3(
					lerpf(MAG_TILT_DEG, MAG_HANG_DEG, t), 0.0, lerpf(4.0, 2.0, t))
		magazine_held_by_hand = true
	elif progress < MAG_GAP_END:
		magazine.visible = false
		magazine_held_by_hand = false
	else:
		magazine_held_by_hand = progress < magazine_seated_progress
		var half := MAG_GAP_END + (MAG_IN_END - MAG_GAP_END) * 0.5
		if progress < half:
			# Das neue Magazin kommt von unten herauf, noch im Haltewinkel.
			var t := _ramp(progress, MAG_GAP_END, half)
			magazine.visible = true
			magazine.position = _magazine_home + Vector3(0.0,
					lerpf(-magazine_drop * 0.88, -magazine_drop * 0.20, t),
					-MAG_FORWARD_PULL * 0.3)
			magazine.rotation_degrees = Vector3(MAG_HANG_DEG, 0.0, 0.0)
		else:
			# Einrasten: nach hinten kippen, bis es sitzt.
			var t := _ramp(progress, half, MAG_IN_END)
			magazine.visible = true
			magazine.position = _magazine_home + Vector3(0.0,
					-magazine_drop * 0.20 * (1.0 - t), -MAG_FORWARD_PULL * 0.3 * (1.0 - t))
			magazine.rotation_degrees = Vector3(MAG_HANG_DEG * (1.0 - t), 0.0, 0.0)


## Laedt das Modell, vermisst es und setzt es passend in die Hand.
##
## Faellt das Modell aus (fehlt die Datei nach einem frischen Clone), bleibt die
## Waffe unsichtbar statt mit einem Fehler abzustuerzen — spielbar ist sie ueber
## die Werte in _configure() weiterhin.
func _build_body() -> void:
	var scene := load(MODEL) as PackedScene
	if scene == null:
		push_warning("[AKM] Modell fehlt: %s" % MODEL)
		return

	var instance := scene.instantiate()

	var body := Node3D.new()
	body.name = "Body"
	body.add_child(instance)
	body.transform = _fit_transform()
	add_child(body)

	# Beide stecken schon als eigene Mesh-Knoten im GLB, nur ohne beweglichen
	# Elternknoten — siehe _extract_part(). Ohne Treffer bleibt das jeweilige
	# Teil fest am Gehaeuse und die zugehoerige Animation laeuft ins Leere,
	# aber die Waffe stuerzt nicht ab.
	_extract_part(instance, "pmag_001_pmag7_0", "Magazine")
	_extract_part(instance, "barrel_002_barrel_0_001", "ChargingHandle")


## Loest ein Mesh aus dem Sketchfab-Teilebaum und haengt es unter einen neuen
## Knoten mit dem gegebenen Namen direkt an die Waffe — dort, wo
## WeaponViewmodel bewegliche Teile per Namen sucht (siehe _collect_parts()
## in weapon_viewmodel.gd: "Magazine", "ChargingHandle", ...).
##
## ---------------------------------------------------------------------------
## WARUM HERAUSLOESEN STATT NEU BAUEN
##
## Das GLB ist keine einzelne verschmolzene Mesh, sondern ein ganzer Baum aus
## Sketchfab — jedes Teil (Lauf, Gehaeuse, Magazin, Ladehebel, Schaft, ...)
## ist bereits ein eigener Knoten, nur alle unbeweglich unter einem
## gemeinsamen Wurzelknoten. Diese Teile muessen dafuer nicht neu aus Blender
## exportiert werden: Sie stecken schon da, sie haengen nur am falschen Ort
## im Baum.
##
## Der Knoten wird UMGEHAENGT, nicht kopiert — es bleibt exakt das Mesh aus
## Sketchfab, nur mit einem neuen Elternknoten. Seine bisherige Lage wird VOR
## dem Umhaengen von Hand ausgerechnet: die Transform-Kette von der Modell-
## wurzel bis zum Teil aufmultipliziert, genau wie es measure_sights.gd und
## inspect_viewmodel.gd tun. NICHT ueber global_transform — die verlangt einen
## echten Szenenbaum, den es beim Bauen ausserhalb des Spiels (Tests, render_-
## sight_picture.gd) nicht gibt, und genau dort muss diese Funktion auch
## laufen.
##
## ---------------------------------------------------------------------------
## POSITION AUF DEN PIVOT, DREHUNG AUF DAS MESH — NICHT BEIDES AUF DEN PIVOT
##
## Die Animationen in weapon_viewmodel.gd SETZEN die Rotation der beweglichen
## Teile (z. B. `magazine.rotation_degrees = ...` in `_animate_magazine_
## swap()`), sie ADDIEREN nicht dazu — und `notify_sequence_ended()` setzt sie
## danach hart auf `Vector3.ZERO` zurueck. Fuer ein Teil aus Blender ist das
## unproblematisch, weil es dort mit exakt null Grundrotation exportiert wird
## (siehe CLAUDE.md: "die Geometrie selbst um null").
##
## Ein aus Sketchfab herausgeloestes Teil bringt aus der FBX-Konvertierung
## dagegen oft eine krumme Grunddrehung mit (beim Magazin im eigenen
## `pmag_001`-Transform sichtbar gewesen). Laege diese Drehung auf dem Pivot,
## wuerde die Animation sie beim ersten Bild ueberschreiben — das Teil stuende
## verdreht in der Luft, als waere es um 180° gekippt. Genau das ist beim
## Magazin passiert, bevor diese Aufteilung eingefuehrt wurde.
##
## Deshalb bekommt der Pivot NUR die Position, die Drehung (und Skalierung)
## bleibt auf dem Mesh-Kindknoten. Die Animation ruehrt den Kindknoten nie an,
## also bleibt seine wahre Ausrichtung erhalten — der Pivot darf mit seiner
## Rotation machen, was er will.
func _extract_part(instance: Node, mesh_name: String, pivot_name: String) -> void:
	var mesh_node := _find_by_node_name(instance, mesh_name)
	if mesh_node == null:
		push_warning("[AKM] Mesh '%s' nicht gefunden — keine Animation fuer '%s'"
				% [mesh_name, pivot_name])
		return

	# Transform von der Modellwurzel (= instance) bis zum Teil, in Modellraum —
	# demselben Raum, in dem MODEL_SIZE/MODEL_CENTRE gemessen wurden.
	# _fit_transform() bildet genau diesen Raum auf den Kameraraum ab.
	var model_space := _accumulate_local_transforms(instance, mesh_node)
	var full := _fit_transform() * model_space

	var pivot := Node3D.new()
	pivot.name = pivot_name
	# NUR die Position — siehe Erklaerung oben.
	pivot.position = full.origin
	add_child(pivot)

	var parent := mesh_node.get_parent()
	parent.remove_child(mesh_node)
	# owner zeigt noch auf die Wurzel der urspruenglichen instantiate() — unter
	# dem neuen Elternknoten waere das inkonsistent (Godot warnt sonst beim
	# Umhaengen). Fuer ein zur Laufzeit gebautes Waffenmodell wird nichts
	# gebackt, der owner wird also ohnehin nie gebraucht.
	mesh_node.owner = null
	pivot.add_child(mesh_node)
	# Drehung und Skalierung wandern hierher — der Pivot bleibt bei Position
	# ohne Rotation, damit die Animation ihn frei drehen kann.
	(mesh_node as Node3D).transform = Transform3D(full.basis, Vector3.ZERO)


## Sucht einen Knoten anhand seines exakten Namens.
static func _find_by_node_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_by_node_name(child, target_name)
		if found != null:
			return found
	return null


## Multipliziert die lokalen Transforms von der Wurzel bis zum Zielknoten auf —
## ohne global_transform, das ausserhalb eines echten Szenenbaums nicht
## funktioniert (siehe _extract_magazine).
static func _accumulate_local_transforms(root_node: Node, target: Node) -> Transform3D:
	var chain: Array[Node3D] = []
	var walker := target
	while walker != root_node and walker != null:
		if walker is Node3D:
			chain.append(walker)
		walker = walker.get_parent()

	var result := Transform3D.IDENTITY
	for i in range(chain.size() - 1, -1, -1):
		result = result * (chain[i] as Node3D).transform
	return result


## Rechnet aus der gemessenen Groesse die Lage in der Hand.
##
## Der Lauf ist die laengste Achse. Skaliert auf FIT_LENGTH, um die eigene Mitte
## zentriert, gedreht — und so verschoben, dass die Muendung vorn auf muzzle_z
## und die Laufachse auf Borehoehe sitzt.
##
## Weil die AABB symmetrisch ums Zentrum liegt, stimmt die Muendungslage
## unabhaengig von FIT_YAW: Dreht man die Waffe, wechselt nur, WELCHES Ende
## vorn sitzt — vorn bleibt vorn.
func _fit_transform() -> Transform3D:
	var longest := maxf(MODEL_SIZE.x, maxf(MODEL_SIZE.y, MODEL_SIZE.z))
	var scale := FIT_LENGTH / maxf(0.0001, longest)

	var basis := Basis.from_euler(Vector3(
		deg_to_rad(FIT_PITCH_DEG), deg_to_rad(FIT_YAW_DEG), deg_to_rad(FIT_ROLL_DEG))) \
		* Basis().scaled(Vector3.ONE * scale)

	var half_length := longest * scale * 0.5
	var place := Vector3(0.0, BORE_Y, muzzle_z + half_length) + FIT_OFFSET

	# Erst um die eigene Mitte zentrieren, dann drehen/skalieren und an die
	# Einbaustelle schieben.
	return Transform3D(basis, place) * Transform3D(Basis.IDENTITY, -MODEL_CENTRE)
