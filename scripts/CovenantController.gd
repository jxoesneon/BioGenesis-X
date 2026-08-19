class_name CovenantController
extends QuestFlowController

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
var _flight_controller: Node = null
var _has_granted_ship: bool = false
var _flight_objective_pending: bool = false


# ============================================================================
# VIRTUAL METHOD OVERRIDES
# ============================================================================

func _get_quest_id() -> String:
	if quest_definition:
		return quest_definition.quest_id
	return QUEST_ID


func _get_dialogue_path() -> String:
	if quest_definition:
		return quest_definition.dialogue_path
	return COVENANT_DIALOGUE_PATH


func _get_objective_ids() -> Dictionary:
	if quest_definition:
		return quest_definition.objective_ids
	return {
		"approach": OBJ_APPROACH,
		"dialogue": OBJ_DIALOGUE,
		"bond": OBJ_BOND,
		"flight": OBJ_FLIGHT,
	}


func _save_key() -> String:
	if quest_definition:
		return quest_definition.save_key
	return SAVE_KEY


func _on_flow_start() -> void:
	# Decide whether to trigger the intro sequence.
	_maybe_begin_intro()


func _on_flow_complete(result: Dictionary) -> void:
	on_dialogue_complete(result)


func _on_flow_abort() -> void:
	pass


func _serialize_state() -> Dictionary:
	return {
		"ship_granted": _has_granted_ship,
		"bond_accepted": bond_accepted,
		"refused_count": refused_count,
	}


func _deserialize_state(data: Dictionary) -> void:
	_has_granted_ship = bool(data.get("ship_granted", false))
	bond_accepted = bool(data.get("bond_accepted", false))
	refused_count = int(data.get("refused_count", 0))
	print("[CovenantController] Restored covenant state — completed=%s, ship_granted=%s" % [_flow_completed, _has_granted_ship])


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	super._ready()
	# Locate the player ship (FlightController) for flight-unlock hooks.
	_flight_controller = get_tree().get_nodes_in_group("player_ship").front() if get_tree().get_nodes_in_group("player_ship").size() > 0 else null
	if _flight_controller and _flight_controller.has_signal("boost_state_changed"):
		_flight_controller.boost_state_changed.connect(_on_player_boost)
	# Bridge the base flow_started signal to the covenant-specific signal so
	# covenant_started fires at the exact moment the dialogue begins.
	flow_started.connect(_on_flow_started)


func _exit_tree() -> void:
	super._exit_tree()
	# Disconnect covenant-specific signals to prevent orphaned connections.
	if _flight_controller and is_instance_valid(_flight_controller):
		if _flight_controller.is_connected("boost_state_changed", _on_player_boost):
			_flight_controller.boost_state_changed.disconnect(_on_player_boost)


func _on_flow_started() -> void:
	covenant_started.emit()


# ============================================================================
# PUBLIC API
# ============================================================================

## Begin the covenant conversation. Called automatically on first start, or
## manually when the player approaches a Void-Fauna.
func trigger_covenant_dialogue() -> void:
	# Reset dialogue variables for a fresh conversation.
	bond_accepted = false
	refused_count = 0
	asked_about_fauna = false
	asked_about_covenant = false
	asked_about_bond = false
	_begin_dialogue_flow()


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
		_save_flow_state()

	print("[CovenantController] Covenant dialogue complete — bond_accepted=%s" % bond_accepted)


# ============================================================================
# QUEST SIGNAL HANDLERS
# ============================================================================

## When the First Symbiosis quest reaches COMPLETED, grant the player their ship.
func _on_quest_completed(quest_id: String) -> void:
	if quest_id != QUEST_ID:
		return
	_grant_ship()
	super._on_quest_completed(quest_id)


## Track player choices for narrative logging / refusal handling.
func _on_choice_made(key: String) -> void:
	# `key` is the destination title (e.g. "offer_covenant", "first_refusal").
	print("[CovenantController] Player chose: %s" % key)


# ============================================================================
# FLIGHT HOOKS
# ============================================================================

## When the player first engages boost/thrust, complete the first-flight obj.
func _on_player_boost(_is_boosting: bool) -> void:
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
	if _flow_completed:
		print("[CovenantController] Covenant already completed — skipping intro.")
		return
	if QuestManager and QuestManager.is_quest_complete(QUEST_ID):
		_flow_completed = true
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
