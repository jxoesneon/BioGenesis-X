# res://addons/quest_weaver/editor/node_type_registry.gd
@tool
class_name NodeTypeRegistry
extends Resource

# ==============================================================================
# 1. STATIC NODE DEFINITIONS
# ==============================================================================
# This is the "Source of Truth". All nodes must be registered here.
# We use string paths with lazy load() to avoid preload() holding script
# references in bytecode at exit (GDScript cache leak, Godot #77513).
# ==============================================================================

const DEFINITIONS = [
	# --- COMMON ---
	{
		"resource": "res://addons/quest_weaver/nodes/common/start_node/start_node_resource.gd",
		"executor": null,  # Start Node is handled by the Controller logic directly
		"editor": "res://addons/quest_weaver/nodes/common/start_node/start_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/common/end_node/end_node_resource.gd",
		"executor": null,
		"editor": null
	},
	{
		"resource": "res://addons/quest_weaver/nodes/common/backdrop/backdrop_node_resource.gd",
		"executor": null,
		"editor": "res://addons/quest_weaver/nodes/common/backdrop/backdrop_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/common/comment/comment_node_resource.gd",
		"executor": null,
		"editor": "res://addons/quest_weaver/nodes/common/comment/comment_node_editor.tscn"
	},
	# --- ACTION ---
	{
		"resource": "res://addons/quest_weaver/nodes/action/event_node/event_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/action/event_node/event_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/action/event_node/event_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/action/give_take_item_node/give_take_item_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/action/give_take_item_node/give_take_item_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/action/give_take_item_node/give_take_item_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/action/play_cutscene_node/play_cutscene_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/action/play_cutscene_node/play_cutscene_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/action/play_cutscene_node/play_cutscene_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/action/task_node/task_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/action/task_node/task_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/action/task_node/task_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/action/show_ui_message_node/show_ui_message_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/action/show_ui_message_node/show_ui_message_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/action/show_ui_message_node/show_ui_message_node_editor.tscn"
	},
	# --- FLOW ---
	{
		"resource": "res://addons/quest_weaver/nodes/flow/anchor_node/anchor_node_resource.gd",
		"executor": null,
		"editor": "res://addons/quest_weaver/nodes/flow/anchor_node/anchor_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/flow/all_complete_node/all_complete_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/flow/all_complete_node/all_complete_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/flow/all_complete_node/all_complete_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/flow/any_complete_node/any_complete_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/flow/any_complete_node/any_complete_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/flow/any_complete_node/any_complete_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/flow/branch_node/branch_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/flow/branch_node/branch_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/flow/branch_node/branch_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/flow/event_listener_node/event_listener_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/flow/event_listener_node/event_listener_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/flow/event_listener_node/event_listener_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/flow/jump_node/jump_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/flow/jump_node/jump_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/flow/jump_node/jump_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/flow/parallel_node/parallel_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/flow/parallel_node/parallel_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/flow/parallel_node/parallel_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/flow/random_node/random_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/flow/random_node/random_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/flow/random_node/random_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/flow/synchronize_node/synchronize_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/flow/synchronize_node/synchronize_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/flow/synchronize_node/synchronize_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/flow/switch_node/switch_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/flow/switch_node/switch_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/flow/switch_node/switch_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/flow/timer_node/timer_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/flow/timer_node/timer_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/flow/timer_node/timer_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/flow/wait_node/wait_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/flow/wait_node/wait_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/flow/wait_node/wait_node_editor.tscn"
	},
	# --- LOGIC ---
	{
		"resource":
		"res://addons/quest_weaver/nodes/logic/cancel_scope_node/cancel_scope_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/logic/cancel_scope_node/cancel_scope_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/logic/cancel_scope_node/cancel_scope_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/logic/end_scope_node/end_scope_node_resource.gd",
		"executor": null,
		"editor": "res://addons/quest_weaver/nodes/logic/end_scope_node/end_scope_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/logic/objective_node/objective_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/logic/objective_node/objective_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/logic/objective_node/objective_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/logic/quest_context_node/quest_context_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/logic/quest_node/quest_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/logic/quest_node/quest_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/logic/quest_node/quest_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/logic/reset_progress_node/reset_progress_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/logic/reset_progress_node/reset_progress_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/logic/reset_progress_node/reset_progress_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/logic/set_variable_node/set_variable_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/logic/set_variable_node/set_variable_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/logic/set_variable_node/set_variable_node_editor.tscn"
	},
	{
		"resource":
		"res://addons/quest_weaver/nodes/logic/start_scope_node/start_scope_node_resource.gd",
		"executor":
		"res://addons/quest_weaver/nodes/logic/start_scope_node/start_scope_node_executor.gd",
		"editor":
		"res://addons/quest_weaver/nodes/logic/start_scope_node/start_scope_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/logic/sub_graph_node/sub_graph_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/logic/sub_graph_node/sub_graph_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/logic/sub_graph_node/sub_graph_node_editor.tscn"
	},
	{
		"resource": "res://addons/quest_weaver/nodes/logic/text_node/text_node_resource.gd",
		"executor": "res://addons/quest_weaver/nodes/logic/text_node/text_node_executor.gd",
		"editor": "res://addons/quest_weaver/nodes/logic/text_node/text_node_editor.tscn"
	},
]

# ==============================================================================
# 2. RUNTIME LOOKUP (Fast & Robust)
# ==============================================================================

# Array<NodeTypeInfo>
# Cached list for the Editor UI
var node_types: Array[NodeTypeInfo] = []

# Dictionary<Script(Resource) or String(path), NodeExecutor or String(path)>
# In editor: maps Script resource → executor instance (eager loading).
# At runtime: maps resource path String → executor path String (lazy loading),
# then replaced with executor instance on first access via get_executor_for_node.
var _resource_to_executor_map: Dictionary = {}

# Dictionary<Script(Resource), NodeTypeInfo>
# Cached metadata for the Editor (Name, Icon, Size)
var _resource_to_info_map: Dictionary = {}

# Dictionary<String(NodeName), Script(Resource)>
# Used by the Editor "Add Node" menu to spawn nodes by name
var _name_to_resource_map: Dictionary = {}

var _is_initialized: bool = false


func _init() -> void:
	# Automatically initialize on creation to ensure maps are ready
	_build_lookup_tables()


func _build_lookup_tables() -> void:
	if _is_initialized:
		return

	_resource_to_executor_map.clear()
	_resource_to_info_map.clear()
	_name_to_resource_map.clear()
	node_types.clear()

	var is_editor: bool = Engine.is_editor_hint()

	for entry in DEFINITIONS:
		# Lazy-load scripts from string paths instead of preload() to avoid
		# holding GDScript references in bytecode at exit (Godot #77513).
		var res_path: String = entry.get("resource") if entry.get("resource") is String else ""
		var exec_path: String = entry.get("executor") if entry.get("executor") is String else ""
		var editor_path: String = entry.get("editor") if entry.get("editor") is String else ""

		# At runtime, only load the executor script and key the map by the
		# resource script PATH (not the Script resource itself). This avoids
		# loading resource scripts that pull in heavy editor dependencies
		# (e.g. branch_node_resource.gd → ConditionResource via typed arrays).
		# In the editor, we load everything for the full UI experience.
		var res_script: Script = null
		if is_editor:
			if not res_path.is_empty() and ResourceLoader.exists(res_path):
				res_script = load(res_path)
		var exec_script: Script = null
		if not exec_path.is_empty() and ResourceLoader.exists(exec_path):
			exec_script = load(exec_path)
		var editor_packed: PackedScene = null
		if is_editor and not editor_path.is_empty() and ResourceLoader.exists(editor_path):
			editor_packed = load(editor_path)

		if is_editor:
			if not is_instance_valid(res_script):
				push_error("QuestWeaver: Invalid resource script in NodeTypeRegistry definition.")
				continue
		elif res_path.is_empty():
			push_error("QuestWeaver: Invalid resource path in NodeTypeRegistry definition.")
			continue

		# 1. Register Executor (Runtime Logic)
		# At runtime: store executor PATH for lazy loading to avoid loading
		# executor scripts that pull in ConditionResource via typed casts.
		# In editor: key by Script resource for direct lookup.
		if is_editor:
			if is_instance_valid(exec_script):
				_resource_to_executor_map[res_script] = exec_script.new()
			else:
				_resource_to_executor_map[res_script] = NodeExecutor.new()
		else:
			# Store the executor path — it will be loaded on first access.
			_resource_to_executor_map[res_path] = exec_path

		# 2. Register Editor Info (Editor Logic) — only in the editor.
		if not is_editor:
			continue

		# We create a temporary instance to access property getters
		var temp_node = res_script.new()
		if temp_node is GraphNodeResource:
			var info = NodeTypeInfo.new()
			info.node_script = res_script
			info.node_name = temp_node.get_display_name()
			info.category = temp_node.category
			info.icon = temp_node.get_icon()
			info.default_size = temp_node.determine_default_size()
			info.description = temp_node.get_description()

			if not editor_path.is_empty():
				info.editor_scene_path = editor_path

			if temp_node is StartNodeResource:
				info.role = NodeTypeInfo.Role.START
			elif temp_node is EndNodeResource:
				info.role = NodeTypeInfo.Role.END
			else:
				info.role = NodeTypeInfo.Role.NORMAL

			# Intern maps (always register these so existing nodes work)
			_resource_to_info_map[res_script] = info
			_name_to_resource_map[info.node_name] = res_script

			# Public List for "Add Node" Menu
			if info.role != NodeTypeInfo.Role.START:
				node_types.append(info)

	_is_initialized = true


# ==============================================================================
# 3. PUBLIC API
# ==============================================================================


## Returns the Executor instance for a specific node definition.
## Called by QuestController during execution.
func get_executor_for_node(node_data: GraphNodeResource) -> NodeExecutor:
	if not _is_initialized:
		_build_lookup_tables()

	if not is_instance_valid(node_data):
		return NodeExecutor.new()

	var script = node_data.get_script()
	# In editor mode, the map is keyed by Script resources.
	if _resource_to_executor_map.has(script):
		return _resource_to_executor_map[script]

	# At runtime, the map is keyed by resource script path (String).
	# The value may be a String (executor path, not yet loaded) or an
	# already-instantiated NodeExecutor (loaded on a previous call).
	if is_instance_valid(script):
		var script_path: String = script.resource_path
		if not script_path.is_empty() and _resource_to_executor_map.has(script_path):
			var entry = _resource_to_executor_map[script_path]
			if entry is NodeExecutor:
				return entry as NodeExecutor
			if entry is String:
				var exec_path: String = entry
				if not exec_path.is_empty() and ResourceLoader.exists(exec_path):
					var exec_script = load(exec_path)
					if is_instance_valid(exec_script):
						var executor = exec_script.new()
						_resource_to_executor_map[script_path] = executor
						return executor
				# No executor for this node type — use default.
				var default_exec = NodeExecutor.new()
				_resource_to_executor_map[script_path] = default_exec
				return default_exec

	push_warning("QuestWeaver: No executor found for %s. Using default." % node_data.id)
	return NodeExecutor.new()


## Returns info by name (used by Add Node Menu).
func get_script_for_name(name: String) -> Script:
	if not _is_initialized:
		_build_lookup_tables()
	return _name_to_resource_map.get(name)


## Returns info by script (used by GraphController to draw nodes).
func get_info_for_script(script: Script) -> NodeTypeInfo:
	if not _is_initialized:
		_build_lookup_tables()
	return _resource_to_info_map.get(script)


## Returns the display name for a script (Helper).
func get_name_for_script(script: Script) -> String:
	var info = get_info_for_script(script)
	return info.node_name if info else "Unknown Node"


## Returns the custom editor scene path (Helper).
func get_editor_path_for_script(script: Script) -> String:
	var info = get_info_for_script(script)
	return info.editor_scene_path if info else ""


## Validates the registry.
func validate_registry() -> void:
	_is_initialized = false
	_build_lookup_tables()
