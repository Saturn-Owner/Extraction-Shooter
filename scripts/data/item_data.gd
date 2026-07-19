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
