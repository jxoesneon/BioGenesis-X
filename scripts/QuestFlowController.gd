class_name QuestFlowController
extends Node

## ============================================================================
## BioGenesis-X Quest Flow Controller (Abstract Base)
## ----------------------------------------------------------------------------
## Reusable base class for dialogue-led quest flow controllers. It owns the
## common plumbing shared by every quest beat: locating the DialogueUI, wiring
## QuestManager signals, running the conversation, advancing MANUAL objectives,
## and persisting flow state through SaveSystem with transactional safety.
##
## Subclasses override the virtual methods below to supply quest-specific data
## and behavior. The base class drives the lifecycle; the subclass injects the
## specifics.
##
## Built-in lifecycle:
##   _ready()    — finds DialogueUI, connects QuestManager signals, loads
##                 state, then calls _on_flow_start() for intro sequencing.
##   _exit_tree()— disconnects every signal it owns (with is_connected guards).
##
## Virtual methods (override in subclasses):
##   _get_quest_id() -> String          — logical quest ID
##   _get_dialogue_path() -> String     — res:// path to the DialogueResource
##   _get_objective_ids() -> Dictionary — role -> objective id map
##                                         (roles used by the base: "approach")
##   _save_key() -> String              — SaveSystem key for this flow
##   _on_flow_start()                   — called once after _ready (intro)
##   _on_flow_complete(result)          — called when the dialogue ends
##   _on_flow_abort()                   — called if the dialogue fails to load
##   _serialize_state() -> Dictionary   — flow-specific fields to persist
##   _deserialize_state(data)           — apply restored flow-specific fields
##
## Signals:
##   flow_started   — emitted right before the dialogue begins
##   flow_completed — emitted when the quest reaches COMPLETED
##   flow_aborted   — emitted if the dialogue resource fails to load
## ============================================================================

signal flow_started
signal flow_completed
signal flow_aborted

# --- Shared internal state ---
var _dialogue_ui: DialogueUI = null
var _flow_in_progress: bool = false
var _flow_completed: bool = false
var _pending_save: bool = false

## Optional data-driven quest definition. When set, the base class reads
## quest_id, dialogue_path, objective_ids, and save_key from this resource
## instead of the virtual method overrides.
@export var quest_definition: QuestDefinition = null

## Static registry of quest definitions keyed by quest_id.
static var _definition_registry: Dictionary = {}


## Registers a QuestDefinition in the static registry.
static func register_definition(def: QuestDefinition) -> void:
	if def and def.quest_id != "":
		_definition_registry[def.quest_id] = def


## Looks up a registered QuestDefinition by quest ID.
static func get_definition(quest_id: String) -> QuestDefinition:
	return _definition_registry.get(quest_id, null) as QuestDefinition


## Loads all QuestDefinition resources from a directory.
static func load_definitions_from_dir(dir_path: String = "res://data/quests") -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path := dir_path + "/" + file_name
			var res := load(full_path)
			if res is QuestDefinition:
				register_definition(res)
		file_name = dir.get_next()
	dir.list_dir_end()


# ============================================================================
# VIRTUAL METHODS (override in subclasses)
# ============================================================================

func _get_quest_id() -> String:
	if quest_definition:
		return quest_definition.quest_id
	return ""


func _get_dialogue_path() -> String:
	if quest_definition:
		return quest_definition.dialogue_path
	return ""


func _get_objective_ids() -> Dictionary:
	if quest_definition:
		return quest_definition.objective_ids
	return {}


func _save_key() -> String:
	if quest_definition:
		return quest_definition.save_key
	return ""


func _on_flow_start() -> void:
	pass


func _on_flow_complete(_result: Dictionary) -> void:
	pass


func _on_flow_abort() -> void:
	pass


func _serialize_state() -> Dictionary:
	return {}


func _deserialize_state(_data: Dictionary) -> void:
	pass


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	_find_dialogue_ui()
	_connect_quest_manager_signals()
	_load_flow_state()
	_on_flow_start()


func _exit_tree() -> void:
	# Disconnect all signals to prevent orphaned connections.
	if _dialogue_ui and is_instance_valid(_dialogue_ui):
		if _dialogue_ui.is_connected("dialogue_ended", _on_dialogue_ended):
			_dialogue_ui.dialogue_ended.disconnect(_on_dialogue_ended)
		if _dialogue_ui.is_connected("choice_made", _on_choice_made):
			_dialogue_ui.choice_made.disconnect(_on_choice_made)
	if QuestManager:
		if QuestManager.is_connected("quest_completed", _on_quest_completed):
			QuestManager.quest_completed.disconnect(_on_quest_completed)
		if QuestManager.is_connected("objective_completed", _on_objective_completed):
			QuestManager.objective_completed.disconnect(_on_objective_completed)


# ============================================================================
# DIALOGUE UI LOOKUP & SIGNAL WIRING
# ============================================================================

## Locate the DialogueUI sibling (added in the scene) and wire its signals.
func _find_dialogue_ui() -> void:
	_dialogue_ui = get_node_or_null("DialogueUI")
	if _dialogue_ui == null:
		# Fall back to searching the parent for a DialogueUI child.
		for child in get_parent().get_children():
			if child is DialogueUI:
				_dialogue_ui = child
				break
	if _dialogue_ui:
		_dialogue_ui.dialogue_ended.connect(_on_dialogue_ended)
		_dialogue_ui.choice_made.connect(_on_choice_made)
	else:
		push_warning("[QuestFlowController] No DialogueUI found — dialogue flow will not run.")


## Hook into QuestManager signals to advance objectives / finalize the flow.
func _connect_quest_manager_signals() -> void:
	if QuestManager:
		if QuestManager.has_signal("quest_completed"):
			QuestManager.quest_completed.connect(_on_quest_completed)
		if QuestManager.has_signal("objective_completed"):
			QuestManager.objective_completed.connect(_on_objective_completed)


# ============================================================================
# FLOW LIFECYCLE
# ============================================================================

## Begin the dialogue flow: guard checks, advance the approach objective, load
## the dialogue resource, and start the conversation. Emits `flow_started`
## right before the dialogue begins. Returns true if the dialogue was started.
func _begin_dialogue_flow() -> bool:
	if _flow_completed:
		print("[QuestFlowController] Flow already completed — skipping dialogue.")
		return false
	if _dialogue_ui == null or not is_instance_valid(_dialogue_ui):
		push_warning("[QuestFlowController] DialogueUI unavailable — cannot trigger flow.")
		return false
	_flow_in_progress = true
	# Mark the approach objective done as the player has reached the beat.
	var obj_ids: Dictionary = _get_objective_ids()
	if obj_ids.has("approach"):
		_complete_objective_safe(_get_quest_id(), obj_ids["approach"])
	var dialogue_res: DialogueResource = load(_get_dialogue_path()) as DialogueResource
	if dialogue_res == null:
		push_error("[QuestFlowController] Failed to load dialogue: %s" % _get_dialogue_path())
		_flow_in_progress = false
		_on_flow_abort()
		flow_aborted.emit()
		return false
	# Pass `self` as an extra game state so the dialogue can mutate our vars.
	flow_started.emit()
	_dialogue_ui.start(dialogue_res, "start", [self])
	return true


## Handle the end of the dialogue — delegate to the subclass then finalize.
func _on_dialogue_ended(result: Dictionary) -> void:
	_on_flow_complete(result)
	_flow_in_progress = false
	_flush_deferred_save()


## Track player choices for narrative logging. Subclasses may override.
func _on_choice_made(key: String) -> void:
	print("[QuestFlowController] Player chose: %s" % key)


# ============================================================================
# QUEST SIGNAL HANDLERS
# ============================================================================

## When an objective completes, persist flow progress (deferred if mid-flow).
func _on_objective_completed(quest_id: String, _objective_id: String) -> void:
	if quest_id != _get_quest_id():
		return
	_save_flow_state()


## When the quest reaches COMPLETED, mark the flow done and persist. Subclasses
## may override to inject a final beat (e.g. grant ship) before calling super.
func _on_quest_completed(quest_id: String) -> void:
	if quest_id != _get_quest_id():
		return
	_flow_completed = true
	_save_flow_state()
	flow_completed.emit()


# ============================================================================
# SAVE / LOAD (TRANSACTIONAL)
# ============================================================================

## Restore flow state from SaveSystem. The base reads the `completed` flag and
## hands the rest of the payload to _deserialize_state().
func _load_flow_state() -> void:
	if SaveSystem == null:
		return
	var data: Dictionary = SaveSystem.current_save_data.get(_save_key(), {})
	if data.is_empty():
		return
	_flow_completed = bool(data.get("completed", false))
	_deserialize_state(data)


## Persist flow state through SaveSystem. If a flow is in progress, the save is
## deferred until the flow completes (transactional safety).
func _save_flow_state() -> void:
	if _flow_in_progress:
		_pending_save = true
		return
	if SaveSystem == null:
		return
	var data: Dictionary = _serialize_state()
	data["completed"] = _flow_completed
	SaveSystem.current_save_data[_save_key()] = data
	if SaveSystem.has_method("save_game"):
		SaveSystem.save_game()


## Flush a save that was deferred while a flow was in progress.
func _flush_deferred_save() -> void:
	if not _pending_save:
		return
	_pending_save = false
	_save_flow_state()


# ============================================================================
# INTERNAL HELPERS
# ============================================================================

## Complete a MANUAL objective via QuestManager, guarded for pre-init calls.
func _complete_objective_safe(quest_id: String, obj_id: String) -> void:
	if QuestManager == null:
		return
	if not bool(QuestManager.get("_is_initialized")):
		# QuestManager not ready yet — defer until it is.
		await _await_quest_manager_ready()
	QuestManager.complete_objective(quest_id, obj_id)


## Waits (with a timeout) for QuestManager._is_initialized to become true.
func _await_quest_manager_ready() -> void:
	if QuestManager == null:
		return
	var elapsed: float = 0.0
	const TIMEOUT: float = 6.0
	while is_instance_valid(QuestManager) and not bool(QuestManager.get("_is_initialized")):
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
		if elapsed >= TIMEOUT:
			push_warning("[QuestFlowController] Timed out waiting for QuestManager init.")
			return
