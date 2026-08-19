# res://addons/quest_weaver/core/qw_constants.gd
class_name QWConstants
extends RefCounted

## Central constants and static resource loaders for Quest-Weaver.
## Call clear_static_references() before plugin shutdown.

# ==============================================================================
# UI Scenes (.tscn) - String paths for lazy loading
# ==============================================================================
# NOTE: These were previously const preload() calls, but preload() embeds
# resource references in bytecode which causes resource leaks at exit
# (Godot #77513). Use load_scene(path) to get the PackedScene on demand.
const MainViewScenePath = "res://addons/quest_weaver/editor/quest_weaver_editor.tscn"
const ValidatorDockScenePath = "res://addons/quest_weaver/editor/validation/validator_dock.tscn"
const AutoCompleteLineEditScenePath = "res://addons/quest_weaver/editor/components/auto_complete_line_edit.tscn"
const QuestFileDialogScenePath = "res://addons/quest_weaver/editor/dialogs/quest_file_dialog.tscn"
const QuestConfirmationDialogScenePath = "res://addons/quest_weaver/editor/dialogs/quest_confirmation_dialog.tscn"
const ObjectiveEditorEntryScenePath = "res://addons/quest_weaver/editor/conditions/objective_editor_entry.tscn"
const ItemStackEntryScenePath = "res://addons/quest_weaver/editor/components/item_stack_entry.tscn"
const RewardEntryScenePath = "res://addons/quest_weaver/editor/components/reward_entry.tscn"

# Editor Scenes for specific components
const OutputEntryScenePath = "res://addons/quest_weaver/editor/components/parallel_output_editor_entry.tscn"
const RandomOutputEntryScenePath = "res://addons/quest_weaver/editor/components/random_output_editor_entry.tscn"
const SyncInputEntryScenePath = "res://addons/quest_weaver/editor/components/synchronize_input_editor_entry.tscn"
const SyncOutputEntryScenePath = "res://addons/quest_weaver/editor/components/synchronize_output_editor_entry.tscn"
const SyncConditionEditorScenePath = "res://addons/quest_weaver/editor/conditions/synchronize_condition_editor.tscn"
const SimpleConditionEntryScenePath = "res://addons/quest_weaver/editor/components/simple_condition_entry.tscn"


## Lazily loads a PackedScene by path. Returns null if the path is empty or invalid.
static func load_scene(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene

# ==============================================================================
# Strings, Paths & Identifiers
# ==============================================================================
const VALIDATOR_DOCK_NAME = "QuestWeaverValidatorDock"
const MODIFIED_SUFFIX = " (*)"
const FILE_EXTENSION = "quest"
const ICON_PATH = "res://addons/quest_weaver/assets/icons/icon.svg"
const RESOURCE_TYPE_NAME = "QuestWeaver.QuestGraph"
const DEBUG_SETTINGS_PATH = "res://addons/quest_weaver/core/debug_settings.tres"
const QUEST_CONTEXT_NODE_SCRIPT_PATH = "res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_resource.gd"

# ==============================================================================
# Data Structures
# ==============================================================================
const TRANSLATABLE_FIELDS = {
	"quest_context_node_resource": ["quest_title", "quest_description", "log_on_start"],
	"text_node_resource": ["text_content"],
	"objective_resource": ["description"],
	"show_ui_message_node_resource": ["title_override", "message_override"]
}

# ==============================================================================
# Settings & Resources
# ==============================================================================
static var _settings: QuestWeaverSettings = null
static var _graph_node_category: GraphNodeCategory = null
static var _is_shutting_down: bool = false


## Returns QuestWeaverSettings resource. Returns null if settings file is missing or during shutdown. Callers must use is_instance_valid().
static func get_settings() -> QuestWeaverSettings:
	if _is_shutting_down:
		return null
	if not is_instance_valid(_settings):
		_settings = (
			ResourceLoader.load("res://addons/quest_weaver/quest_weaver_settings.tres")
			as QuestWeaverSettings
		)
		if not is_instance_valid(_settings):
			push_warning("QWConstants: Could not load quest_weaver_settings.tres.")
	return _settings


## Returns GraphNodeCategory resource. Returns null if file is missing or during shutdown. Callers must use is_instance_valid().
static func get_graph_node_category() -> GraphNodeCategory:
	if _is_shutting_down:
		return null
	if not is_instance_valid(_graph_node_category):
		_graph_node_category = (
			ResourceLoader.load("res://addons/quest_weaver/assets/graph_node_category.tres")
			as GraphNodeCategory
		)
		if not is_instance_valid(_graph_node_category):
			push_warning("QWConstants: Could not load graph_node_category.tres.")
	return _graph_node_category


static func clear_static_references():
	# Explicitly set to null to drop the static reference count
	_is_shutting_down = true
	_settings = null
	_graph_node_category = null
