@tool
class_name ItemDefinition
extends Resource

## ============================================================================
## BioGenesis-X Item Definition
## ----------------------------------------------------------------------------
## Data-driven resource describing a single inventory item type. Loaded by
## BioInventoryController's static registry from `res://data/items/*.tres`.
## ============================================================================

@export var item_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var max_stack: int = 99
@export var category: String = "general"
@export var rarity: int = 0
@export var tags: PackedStringArray = PackedStringArray()
@export var bio_effect: String = ""
@export var quest_relevance: String = ""
@export var icon_path: String = ""


func get_display_name() -> String:
	return tr(display_name)
