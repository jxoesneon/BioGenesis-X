extends Node

## ============================================================================
## BioGenesis-X Quest Manager
## ----------------------------------------------------------------------------
## Bridge between Quest Weaver and the game. Initializes the QuestController
## on boot, loads/saves quest state through SaveSystem, and exposes a clean
## API for gameplay code to start quests, complete objectives, and query state.
##
## Signals:
##   quest_started(quest_id)        — a quest entered the ACTIVE state
##   quest_completed(quest_id)      — a quest reached the COMPLETED state
##   objective_completed(quest_id, objective_id) — an objective was completed
##
## Public API:
##   start_quest(id)                          — activate a quest by logical ID
##   complete_objective(quest_id, obj_id)     — mark a MANUAL objective done
##   is_quest_complete(id)                    — true if quest is COMPLETED
##   is_quest_active(id)                      — true if quest is ACTIVE
##   is_objective_complete(obj_id)            — true if objective is COMPLETED
##   save_quest_state()                       — flush quest state to SaveSystem
## ============================================================================

signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal objective_completed(quest_id: String, objective_id: String)

const QuestControllerScene: PackedScene = preload("res://addons/quest_weaver/core/quest_controller.tscn")
const SAVE_KEY := "quest_weaver"

var _controller: Node = null
var _global_bus: Node = null
var _is_initialized: bool = false


func _exit_tree() -> void:
	# Gracefully shut down the QuestController before the tree is destroyed.
	# This prevents ObjectDB/resource leaks from static caches and node refs.
	if is_instance_valid(_controller):
		if _controller.has_method("shutdown"):
			_controller.shutdown()
		if _controller.has_method("_on_exit_cleanup"):
			_controller._on_exit_cleanup()
	# Clear Quest Weaver static script caches that hold GDScript references.
	# These clear functions are safe to call multiple times.
	if ClassDB.class_exists("QWConstants"):
		QWConstants.clear_static_references()
	if ClassDB.class_exists("QuestValidator"):
		QuestValidator.clear_graph_cache()
	if ClassDB.class_exists("QWEditorUtils"):
		QWEditorUtils.clear_cache()


func _ready() -> void:
	# Instantiate the Quest Weaver runtime controller and parent it to this autoload.
	_controller = QuestControllerScene.instantiate()
	add_child(_controller)

	# Forward QuestController lifecycle signals.
	if _controller.has_signal("quest_started"):
		_controller.quest_started.connect(_on_quest_started)
	if _controller.has_signal("quest_completed"):
		_controller.quest_completed.connect(_on_quest_completed)

	# Locate the Quest Weaver global event bus (autoload).
	_global_bus = get_tree().root.get_node_or_null("QuestWeaverGlobal")
	if is_instance_valid(_global_bus):
		if _global_bus.has_signal("quest_objective_state_changed"):
			_global_bus.quest_objective_state_changed.connect(_on_objective_state_changed)

	# Hook into SaveSystem so quest state is injected before every save.
	if SaveSystem.has_signal("about_to_save"):
		SaveSystem.about_to_save.connect(_on_about_to_save)

	# Wait for the QuestController to finish its async initialization, then
	# restore any persisted quest state from the save file.
	await _await_controller_initialized()
	# Defer one extra frame so the quest registry cache and auto-start graphs
	# are fully processed before we try to restore quest state. Without this,
	# load_quest_data() can race with _load_registry_cache() and log
	# "no definition found" warnings for quests that haven't been instantiated yet.
	await get_tree().process_frame
	_load_quest_state()
	_is_initialized = true
	print("[QuestManager] Initialized — QuestController ready, quest state restored.")


# ============================================================================
# PUBLIC API
# ============================================================================

## Activate a quest by its logical ID (e.g. "first_symbiosis").
func start_quest(id: String) -> void:
	if not _is_ready():
		push_warning("[QuestManager] start_quest called before initialization: '%s'" % id)
		return
	if is_instance_valid(_global_bus) and _global_bus.has_method("start_quest_id"):
		_global_bus.start_quest_id(StringName(id))
	else:
		push_warning("[QuestManager] Cannot start quest '%s' — QuestWeaverGlobal unavailable." % id)


## Mark a MANUAL objective as completed. The quest_id is used for validation
## and signal routing; the objective is completed via its objective_id.
func complete_objective(_quest_id: String, obj_id: String) -> void:
	if not _is_ready():
		push_warning("[QuestManager] complete_objective called before initialization.")
		return
	if is_instance_valid(_global_bus) and _global_bus.has_method("complete_objective"):
		_global_bus.complete_objective(StringName(obj_id))
	else:
		push_warning("[QuestManager] Cannot complete objective '%s' — QuestWeaverGlobal unavailable." % obj_id)


## Returns true if the quest with the given ID is in the COMPLETED state.
func is_quest_complete(id: String) -> bool:
	if not _is_ready():
		return false
	if is_instance_valid(_global_bus) and _global_bus.has_method("is_quest_completed"):
		return _global_bus.is_quest_completed(StringName(id))
	return false


## Returns true if the quest with the given ID is in the ACTIVE state.
func is_quest_active(id: String) -> bool:
	if not _is_ready():
		return false
	if is_instance_valid(_global_bus) and _global_bus.has_method("is_quest_active"):
		return _global_bus.is_quest_active(StringName(id))
	return false


## Returns true if the objective with the given ID is COMPLETED.
func is_objective_complete(obj_id: String) -> bool:
	if not _is_ready():
		return false
	if is_instance_valid(_global_bus) and _global_bus.has_method("is_objective_completed"):
		return _global_bus.is_objective_completed(StringName(obj_id))
	return false


## Flush quest state into SaveSystem and persist to disk.
func save_quest_state() -> void:
	_inject_quest_save_data()
	if SaveSystem.has_method("save_game"):
		SaveSystem.save_game()


## Returns the underlying QuestController node (or null).
func get_controller() -> Node:
	return _controller


# ============================================================================
# SAVE / LOAD INTEGRATION
# ============================================================================

## Restore quest state from SaveSystem.current_save_data after the controller
## has finished initializing and loaded the quest registry.
func _load_quest_state() -> void:
	if not is_instance_valid(_global_bus) or not _global_bus.has_method("load_quest_data"):
		return
	var data: Dictionary = SaveSystem.current_save_data.get(SAVE_KEY, {})
	if data.is_empty():
		print("[QuestManager] No persisted quest state found — starting fresh.")
		return
	_global_bus.load_quest_data(data)
	print("[QuestManager] Restored quest state from save (keys: %d)." % data.size())


## Collect quest save data from QuestWeaverGlobal and inject it into
## SaveSystem.current_save_data under the SAVE_KEY. Called on about_to_save.
func _inject_quest_save_data() -> void:
	if not is_instance_valid(_global_bus) or not _global_bus.has_method("get_quest_save_data"):
		return
	var qw_data: Dictionary = _global_bus.get_quest_save_data()
	SaveSystem.current_save_data[SAVE_KEY] = qw_data


# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_quest_started(quest_id: StringName) -> void:
	quest_started.emit(String(quest_id))


func _on_quest_completed(quest_id: StringName) -> void:
	quest_completed.emit(String(quest_id))
	# Persist the completed state immediately.
	save_quest_state()


func _on_objective_state_changed(quest_id: StringName, objective_id: StringName, new_status: int) -> void:
	# ObjectiveResource.Status.COMPLETED == 2
	if new_status == 2:
		objective_completed.emit(String(quest_id), String(objective_id))
		# Persist objective progress.
		_inject_quest_save_data()


func _on_about_to_save() -> void:
	_inject_quest_save_data()


# ============================================================================
# INTERNAL HELPERS
# ============================================================================

func _is_ready() -> bool:
	return _is_initialized and is_instance_valid(_controller)


## Waits (with a timeout) for the QuestController._is_initialized flag.
func _await_controller_initialized() -> void:
	if not is_instance_valid(_controller):
		return
	var elapsed: float = 0.0
	const TIMEOUT: float = 5.0
	const FRAME_STEP: float = 0.016
	while is_instance_valid(_controller) and not bool(_controller.get("_is_initialized")):
		await get_tree().process_frame
		elapsed += FRAME_STEP
		if elapsed >= TIMEOUT:
			push_warning("[QuestManager] Timed out waiting for QuestController initialization.")
			return
