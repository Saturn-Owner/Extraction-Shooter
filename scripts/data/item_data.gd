## Basisklasse für ALLE Gegenstände im Spiel.
##
## Jeder Gegenstand ist eine eigene .tres-Datei unter assets/data/.
## Wer eine neue Munition oder Waffe hinzufügen will, legt eine neue Datei an —
## es muss dafür kein Code geändert werden.
##
## "extends Resource" bedeutet: Godot kann das als Datei speichern und im
## Inspector bearbeiten. Das ist der Kern unserer datengetriebenen Architektur.
class_name ItemData
extends Resource

## Grobe Einordnung — bestimmt u.a., in welchen Slots ein Item landen darf
## und wie der Händler es einsortiert.
enum Category {
	MISC,        ## Krimskrams, Wertsachen, Barter-Items
	AMMO,        ## Munition
	WEAPON,      ## Schusswaffen
	ARMOR_PLATE, ## Schutzplatten für Trägersysteme
	ARMOR_RIG,   ## Plattenträger / Westen
	CLOTHING,    ## Kleidung (Wärmedämmung)
	BACKPACK,    ## Rucksäcke (eigenes Innenraster)
	MEDICAL,     ## Verbände, Schienen, Schmerzmittel
	FOOD,        ## Essen und Trinken
	KEY,         ## Schlüssel für verschlossene Bereiche
	TOOL,        ## Eispickel, Brecheisen — schaltet Wege frei
}

## Seltenheitsstufe. Bestimmt Hintergrundfarbe im Inventar und den Klang
## beim Fund. Wird aus dem Preis ABGELEITET, nicht pro Item gepflegt —
## sonst müsste man bei jeder Preisänderung daran denken.
enum Rarity {
	COMMON,    ## Krimskrams, Pistolenmunition — grau, kein Fundgeräusch
	UNCOMMON,  ## brauchbare Ausrüstung
	RARE,      ## gute Munition, solide Waffen
	EPIC,      ## Platten, hochwertige Waffen — der Fund, für den man bleibt
}

## Eindeutige ID, z.B. "ammo_556x45_m995". Wird zum Speichern benutzt —
## darum NIEMALS nachträglich ändern, sonst brechen alte Spielstände.
@export var id: StringName = &""

## Name, der dem Spieler angezeigt wird.
@export var display_name: String = "Unbenannt"

## Beschreibungstext im Inventar und beim Händler.
@export_multiline var description: String = ""

@export var category: Category = Category.MISC

## Icon im Inventar. Darf am Anfang leer bleiben (Graybox).
@export var icon: Texture2D

@export_group("Inventar-Raster")

## Breite in Rasterfeldern (Tarkov-Stil). Eine Pistole ist z.B. 2x1,
## ein Sturmgewehr 5x2.
@export_range(1, 10) var grid_width: int = 1

## Höhe in Rasterfeldern.
@export_range(1, 10) var grid_height: int = 1

## Ob der Spieler das Item im Inventar drehen darf (90°).
@export var can_rotate: bool = true

@export_group("Container")

## Innenraster für Rucksäcke, Westen und Taschen.
## 0 = dieser Gegenstand kann nichts enthalten (der Normalfall).
## Ein Rucksack mit 6x5 hat innen 30 Felder — unabhängig davon,
## wie viel Platz er selbst im Inventar belegt.
@export_range(0, 12) var container_width: int = 0

@export_range(0, 12) var container_height: int = 0

@export_group("Physik & Wert")

## Gewicht in Kilogramm. Beeinflusst Ausdauer und Bewegungstempo —
## deshalb bei jedem Item ehrlich ausfüllen, nicht raten.
@export var weight_kg: float = 0.1

## Wie viele davon auf einen Rasterplatz passen. 1 = nicht stapelbar.
@export_range(1, 999) var max_stack: int = 1

## Grundwert in Spielwährung. Händler rechnen davon ihre Kauf- und
## Verkaufspreise ab (abhängig von Vertrauensstufe).
@export var base_price: int = 100


## Wie viele Rasterfelder das Item belegt — praktisch für Sortierung
## und für die Preis-pro-Platz-Anzeige.
func get_grid_area() -> int:
	return grid_width * grid_height


## Ob dieser Gegenstand andere aufnehmen kann (Rucksack, Weste, Tasche).
func is_container() -> bool:
	return container_width > 0 and container_height > 0


## Wie lange es dauert, diesen Gegenstand in einer Kiste zu finden.
##
## Bewusst berechnet statt pro Item gepflegt — bei hunderten Gegenständen
## würde niemand diese Werte aktuell halten, und sie wären inkonsistent.
##
## Zwei Einflüsse:
##   GRÖSSE     Ein Sturmgewehr ist sperrig und braucht länger als eine
##              einzelne Patrone.
##   SELTENHEIT Teure Dinge liegen nicht obenauf. Der Preis ist dabei ein
##              guter Näherungswert für Seltenheit, weil er ohnehin schon
##              gepflegt wird.
##
## Beispiele mit den aktuellen Daten:
##   9mm FMJ (1x1, 42)        ~0.7 s
##   M995 (1x1, 780)          ~1.3 s
##   Schutzplatte (2x3, 18500) ~3.3 s
##   AR-15 (5x2, 24000)       ~4.4 s
func get_search_time() -> float:
	var size_part := float(get_grid_area()) * 0.25

	# Zehnerlogarithmus des Preises, damit teure Ausreisser die Zeit nicht
	# ins Absurde treiben. Ab etwa 30 Spielwaehrung beginnt der Zuschlag.
	var rarity_part := 0.0
	if base_price > 0:
		rarity_part = clampf(log(float(base_price)) / log(10.0) - 1.5, 0.0, 3.0) * 0.5

	return clampf(0.4 + size_part + rarity_part, 0.4, 7.0)


## Seltenheit aus dem Preis abgeleitet.
##
## Bewusst am Preis festgemacht statt als eigenes Feld: Der Preis wird
## ohnehin gepflegt, und ein Gegenstand, der viel wert ist, IST selten.
## Zwei getrennte Felder würden früher oder später auseinanderlaufen.
##
## Die Grenzen orientieren sich an den vorhandenen Daten:
##   9mm FMJ 42        -> COMMON
##   M855A1 260        -> UNCOMMON
##   M995 780          -> RARE
##   Schutzplatte 18500 -> EPIC
func get_rarity() -> Rarity:
	if base_price >= 5000:
		return Rarity.EPIC
	if base_price >= 500:
		return Rarity.RARE
	if base_price >= 150:
		return Rarity.UNCOMMON
	return Rarity.COMMON


## Kurze Typbezeichnung für die Infoanzeige. Basisklasse: die Kategorie.
func get_type_label() -> String:
	match category:
		Category.AMMO: return "Munition"
		Category.WEAPON: return "Waffe"
		Category.ARMOR_PLATE: return "Schutzplatte"
		Category.ARMOR_RIG: return "Plattentraeger"
		Category.CLOTHING: return "Kleidung"
		Category.BACKPACK: return "Rucksack"
		Category.MEDICAL: return "Medizin"
		Category.FOOD: return "Verpflegung"
		Category.KEY: return "Schluessel"
		Category.TOOL: return "Werkzeug"
	return "Gegenstand"


## Zeilen für die Infoanzeige beim Darüberfahren.
## Unterklassen hängen ihre eigenen Werte an.
func get_info_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Gewicht:  %.2f kg" % weight_kg)
	lines.append("Platz:    %dx%d" % [grid_width, grid_height])
	lines.append("Wert:     %d" % base_price)
	return lines


## Kleine Selbstprüfung. Gibt eine Liste von Problemen zurück,
## damit wir Datenfehler früh finden statt erst im Spiel.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id ist leer")
	if display_name.strip_edges() == "":
		problems.append("display_name ist leer")
	if weight_kg < 0.0:
		problems.append("weight_kg ist negativ")
	return problems
