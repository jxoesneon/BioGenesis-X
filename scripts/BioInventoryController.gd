extends Node

## ============================================================================
## BioGenesis-X Bio Inventory Controller
## ----------------------------------------------------------------------------
## Minimal inventory controller for Quest Weaver's SimpleInventoryAdapter.
## Joins the "inventory_controller" group so the adapter can find it.
## Stores bio-resources (spores, plasma fuel, tissue samples, etc.) that quests
## can give/take/check via Quest Weaver's Give/Take/Check Item nodes.
##
## Registered as an autoload singleton (see project.godot) so it is available
## before Quest Weaver initializes. Access globally as `BioInventoryController`.
## ============================================================================

signal inventory_changed

# In-memory inventory: { "item_id": quantity }
var _inventory: Dictionary = {
	"bio_spore": 0,
	"plasma_fuel": 100,
	"tissue_sample": 0,
	"void_crystal": 0,
}

# Static registry: { "item_id": ItemDefinition }
static var _registry: Dictionary = {}


static func register_item(def: ItemDefinition) -> void:
	if def == null or def.item_id.is_empty():
		return
	_registry[def.item_id] = def


static func get_item_definition(item_id: String) -> ItemDefinition:
	return _registry.get(item_id, null)


static func load_definitions_from_dir(dir_path: String = "res://data/items") -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res_path := dir_path.path_join(file_name)
			var def := load(res_path) as ItemDefinition
			if def != null:
				register_item(def)
		file_name = dir.get_next()
	dir.list_dir_end()


func _ready() -> void:
	add_to_group("inventory_controller")
	load_definitions_from_dir()


func print_inventory() -> void:
	print("\n--- Bio Inventory ---")
	for item_id in _inventory:
		print("  - %s: %d" % [item_id, _inventory[item_id]])
	print("---------------------\n")


# --- PUBLIC API FOR THE ADAPTER ---

func get_all_items() -> Dictionary:
	return _inventory.duplicate()


func count_item(item_id: String) -> int:
	return _inventory.get(item_id, 0)


func check_item(item_id: String, amount: int) -> bool:
	return count_item(item_id) >= amount


func give_item(item_id: String, amount: int) -> void:
	var current_amount := count_item(item_id)
	_inventory[item_id] = current_amount + amount
	inventory_changed.emit()


func take_item(item_id: String, amount: int) -> bool:
	if not check_item(item_id, amount):
		return false
	_inventory[item_id] -= amount
	inventory_changed.emit()
	return true


# --- ITEM DEFINITION REGISTRY ACCESS ---

func get_item_definition_for(item_id: String) -> ItemDefinition:
	return get_item_definition(item_id)


func get_all_known_items() -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for item_id in _registry:
		out.append(_registry[item_id])
	return out
