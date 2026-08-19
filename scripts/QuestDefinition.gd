class_name QuestDefinition
extends Resource

## ============================================================================
## BioGenesis-X Quest Definition (Data-Driven Resource)
## ----------------------------------------------------------------------------
## A data-driven quest configuration resource. Instead of hardcoding quest IDs,
## dialogue paths, and objective IDs in script subclasses, a QuestDefinition
## resource encodes them as data that can be authored in the editor or loaded
## from .tres files.
##
## Usage:
##   1. Create a QuestDefinition resource in res://data/quests/<name>.tres
##   2. Assign it to a QuestFlowController subclass via the quest_definition
##      export property, or register it with QuestFlowController.register_definition()
##   3. The base class reads quest_id, dialogue_path, objective_ids, and
##      save_key from the definition instead of virtual method overrides.
## ============================================================================

@export var quest_id: String = ""
@export var dialogue_path: String = ""
@export var save_key: String = ""

## Role -> objective ID mapping. Roles used by the base class:
##   "approach"  — the approach objective (completed when dialogue starts)
##   "dialogue"  — the dialogue completion objective
##   "bond"      — the bonding/commitment objective
##   "flight"    — the final flight verification objective
@export var objective_ids: Dictionary = {}

## Optional: quest title for UI display (localized via tr()).
@export var title: String = ""

## Optional: quest description for UI display (localized via tr()).
@export var description: String = ""

## Optional: prerequisite quest IDs that must be completed before this one.
@export var prerequisites: PackedStringArray = PackedStringArray()

## Optional: rewards granted on completion (item_id -> count).
@export var rewards: Dictionary = {}

## Optional: minimum bond level required to start (for covenant-style quests).
@export var min_bond_level: int = 0


func get_quest_id() -> String:
	return quest_id


func get_dialogue_path() -> String:
	return dialogue_path


func get_save_key() -> String:
	return save_key


func get_objective(role: String) -> String:
	return objective_ids.get(role, "")


func has_prerequisite(other_quest_id: String) -> bool:
	return other_quest_id in prerequisites
