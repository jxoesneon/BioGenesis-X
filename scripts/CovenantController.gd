class_name CovenantController
extends Node

## ============================================================================
## BioGenesis-X Covenant Controller
## ----------------------------------------------------------------------------
## Orchestrates the "First Symbiosis" quest flow — the opening narrative beat
## where the player bonds with a drifting Void-Fauna Leviathan and it becomes
## their ship.
##
## Flow:
##   1. On first game start (no covenant save), triggers the covenant dialogue.
##   2. The covenant_symbiosis.dialogue mutates `bond_accepted` on this node.
##   3. On dialogue end, starts the intro quest via QuestManager and advances
##      the MANUAL objectives in sequence.
##   4. On quest completion, grants the player their ship (unlocks flight).
##
## Public API:
##   trigger_covenant_dialogue()   — begin the covenant conversation
##   on_dialogue_complete(result)  — handle dialogue outcome
##
## Signals:
##   covenant_started              — dialogue has begun
##   covenant_bonded               — the player accepted the bond
##   covenant_refused              — the player refused the bond
##   ship_granted                  — the quest completed; ship is unlocked
## ============================================================================

signal covenant_started
signal covenant_bonded
signal covenant_refused
signal ship_granted

const COVENANT_DIALOGUE_PATH := "res://dialogue/covenant_symbiosis.dialogue"
const QUEST_ID := "first_symbiosis"
const SAVE_KEY := "covenant"

# Objective IDs from quests/intro_quest.tres
const OBJ_APPROACH := "obj_approach_void_fauna"
const OBJ_DIALOGUE := "obj_complete_covenant_dialogue"
const OBJ_BOND := "obj_bond_with_void_fauna"
const OBJ_FLIGHT := "obj_take_first_flight"

# --- Dialogue variables (mutated by covenant_symbiosis.dialogue via game state) ---
## True if the player accepted the Covenant of Symbiosis.
var bond_accepted: bool = false
## Number of times the player refused before accepting.
var refused_count: int = 0
var asked_about_fauna: bool = false
var asked_about_covenant: bool = false
var asked_about_bond: bool = false

# --- Internal state ---
var _dialogue_ui: DialogueUI = null
var _flight_controller: Node = null
var _has_granted_ship: bool = false
var _flight_objective_pending: bool = false
var _covenant_completed: bool = false


func _ready() -> void:
	# Locate the DialogueUI sibling (added in space_flight.tscn).
	_dialogue_ui = get_node_or_null("DialogueUI")
	if _dialogue_ui == null:
		# Fall back to searching the parent for a DialogueUI child.
		for child in get_parent().get_children():
			if child is DialogueUI:
				_dialogue_ui = child
				break
	if _dialogue_ui:
		_dialogue_ui.dialogue_ended.connect(on_dialogue_complete)
		_dialogue_ui.choice_made.connect(_on_choice_made)
	else:
		push_warning("[CovenantController] No DialogueUI found — covenant dialogue will not run.")

	# Locate the player ship (FlightController) for flight-unlock hooks.
	_flight_controller = get_tree().get_nodes_in_group("player_ship").front() if get_tree().get_nodes_in_group("player_ship").size() > 0 else null
	if _flight_controller and _flight_controller.has_signal("boost_state_changed"):
		_flight_controller.boost_state_changed.connect(_on_player_boost)

	# Hook into QuestManager signals to advance objectives / grant ship.
	if QuestManager:
		if QuestManager.has_signal("quest_completed"):
			QuestManager.quest_completed.connect(_on_quest_completed)
		if QuestManager.has_signal("objective_completed"):
			QuestManager.objective_completed.connect(_on_objective_completed)

	# Restore covenant state from save.
	_load_covenant_state()

	# Decide whether to trigger the intro sequence.
	_maybe_begin_intro()


# ============================================================================
# PUBLIC API
# ============================================================================

## Begin the covenant conversation. Called automatically on first start, or
## manually when the player approaches a Void-Fauna.
func trigger_covenant_dialogue() -> void:
	if _covenant_completed:
		print("[CovenantController] Covenant already completed — skipping dialogue.")
		return
	if _dialogue_ui == null or not is_instance_valid(_dialogue_ui):
		push_warning("[CovenantController] DialogueUI unavailable — cannot trigger covenant.")
		return
	# Reset dialogue variables for a fresh conversation.
	bond_accepted = false
	refused_count = 0
	asked_about_fauna = false
	asked_about_covenant = false
	asked_about_bond = false

	# Mark the approach objective done as the player has reached the fauna.
	_complete_objective_safe(QUEST_ID, OBJ_APPROACH)

	var dialogue_res: DialogueResource = load(COVENANT_DIALOGUE_PATH) as DialogueResource
	if dialogue_res == null:
		push_error("[CovenantController] Failed to load covenant dialogue: %s" % COVENANT_DIALOGUE_PATH)
		return
	covenant_started.emit()
	# Pass `self` as an extra game state so the dialogue can mutate our vars.
	_dialogue_ui.start(dialogue_res, "start", [self])


## Handle the end of the covenant dialogue — read the outcome and advance quest.
func on_dialogue_complete(result: Dictionary) -> void:
	# `result` is the snapshot of our scalar properties (includes bond_accepted).
	var accepted: bool = bool(result.get("bond_accepted", bond_accepted))
	# Complete the dialogue objective regardless of outcome.
	_complete_objective_safe(QUEST_ID, OBJ_DIALOGUE)

	if accepted:
		bond_accepted = true
		covenant_bonded.emit()
		# The bond objective: the Void-Fauna becomes the player's ship.
		_complete_objective_safe(QUEST_ID, OBJ_BOND)
		# Unlock flight so the player can take their first flight.
		_unlock_flight()
		# The final objective completes once the player actually flies.
		_flight_objective_pending = true
		# If the flight controller isn't present (e.g. test scene), finalize now.
		if _flight_controller == null or not is_instance_valid(_flight_controller):
			_complete_objective_safe(QUEST_ID, OBJ_FLIGHT)
	else:
		bond_accepted = false
		covenant_refused.emit()
		# Refusal ends the intro without granting a ship. Persist the refusal.
		_save_covenant_state()

	print("[CovenantController] Covenant dialogue complete — bond_accepted=%s" % bond_accepted)


# ============================================================================
# QUEST SIGNAL HANDLERS
# ============================================================================

## When an objective completes, persist covenant progress.
func _on_objective_completed(quest_id: String, objective_id: String) -> void:
	if quest_id != QUEST_ID:
		return
	_save_covenant_state()


## When the First Symbiosis quest reaches COMPLETED, grant the player their ship.
func _on_quest_completed(quest_id: String) -> void:
	if quest_id != QUEST_ID:
		return
	_covenant_completed = true
	_grant_ship()
	_save_covenant_state()


## Track player choices for narrative logging / refusal handling.
func _on_choice_made(key: String) -> void:
	# `key` is the destination title (e.g. "offer_covenant", "first_refusal").
	print("[CovenantController] Player chose: %s" % key)


# ============================================================================
# FLIGHT HOOKS
# ============================================================================

## When the player first engages boost/thrust, complete the first-flight obj.
func _on_player_boost(is_boosting: bool) -> void:
	if not _flight_objective_pending:
		return
	# Any boost engagement counts as taking flight for the intro beat.
	_complete_objective_safe(QUEST_ID, OBJ_FLIGHT)
	_flight_objective_pending = false


## Unlock flight controls on the player ship (the bond is sealed).
func _unlock_flight() -> void:
	if _flight_controller == null or not is_instance_valid(_flight_controller):
		return
	# The FlightController is already active; the bond simply marks it as the
	# player's own organism. Only set the flag if the property exists.
	if "is_bonded" in _flight_controller:
		_flight_controller.set("is_bonded", true)


## Final ship-grant beat — emitted on quest completion.
func _grant_ship() -> void:
	if _has_granted_ship:
		return
	_has_granted_ship = true
	ship_granted.emit()
	if _flight_controller and is_instance_valid(_flight_controller):
		if "is_bonded" in _flight_controller:
			_flight_controller.set("is_bonded", true)
	print("[CovenantController] Ship granted — the Leviathan is now the player's vessel.")


# ============================================================================
# INTRO SEQUENCING
# ============================================================================

## On first game start (no completed covenant), trigger the intro. On
## subsequent loads where the covenant is already done, skip it.
func _maybe_begin_intro() -> void:
	if _covenant_completed:
		print("[CovenantController] Covenant already completed — skipping intro.")
		return
	if QuestManager and QuestManager.is_quest_complete(QUEST_ID):
		_covenant_completed = true
		_has_granted_ship = true
		print("[CovenantController] Quest already complete — ship already granted.")
		return
	# Wait for QuestManager to finish async init before starting the quest.
	await _await_quest_manager_ready()
	# Start the intro quest, then trigger the covenant dialogue.
	if QuestManager and not QuestManager.is_quest_active(QUEST_ID):
		QuestManager.start_quest(QUEST_ID)
	# Defer the dialogue trigger a frame so the quest start signal propagates.
	call_deferred("trigger_covenant_dialogue")


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
			push_warning("[CovenantController] Timed out waiting for QuestManager init.")
			return


# ============================================================================
# SAVE / LOAD
# ============================================================================

func _load_covenant_state() -> void:
	if SaveSystem == null:
		return
	var data: Dictionary = SaveSystem.current_save_data.get(SAVE_KEY, {})
	if data.is_empty():
		return
	_covenant_completed = bool(data.get("completed", false))
	_has_granted_ship = bool(data.get("ship_granted", false))
	bond_accepted = bool(data.get("bond_accepted", false))
	refused_count = int(data.get("refused_count", 0))
	print("[CovenantController] Restored covenant state — completed=%s, ship_granted=%s" % [_covenant_completed, _has_granted_ship])


func _save_covenant_state() -> void:
	if SaveSystem == null:
		return
	var data: Dictionary = {
		"completed": _covenant_completed,
		"ship_granted": _has_granted_ship,
		"bond_accepted": bond_accepted,
		"refused_count": refused_count,
	}
	SaveSystem.current_save_data[SAVE_KEY] = data
	if SaveSystem.has_method("save_game"):
		SaveSystem.save_game()


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
