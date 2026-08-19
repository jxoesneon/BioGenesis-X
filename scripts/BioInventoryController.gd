class_name BioInventoryController
extends Node

## ============================================================================
## BioGenesis-X Bio Inventory Controller
## ----------------------------------------------------------------------------
## Minimal inventory controller for Quest Weaver's SimpleInventoryAdapter.
## Joins the "inventory_controller" group so the adapter can find it.
## Stores bio-resources (spores, plasma fuel, tissue samples, etc.) that quests
## can give/take/check via Quest Weaver's Give/Take/Check Item nodes.
## ============================================================================

signal inventory_changed

# In-memory inventory: { "item_id": quantity }
var _inventory: Dictionary = {
	"bio_spore": 0,
	"plasma_fuel": 100,
	"tissue_sample": 0,
	"void_crystal": 0,
}


func _ready() -> void:
	add_to_group("inventory_controller")


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
