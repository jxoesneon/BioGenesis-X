extends Node

## ============================================================================
## BioGenesis-X Keymap Manager (Autoload)
## ----------------------------------------------------------------------------
## Central registry for all game keybindings. Registers Godot InputActions
## on boot, manages context-aware binding groups, persists rebinding to
## user://keymap.json, and provides conflict detection within the active
## context.
##
## Contexts:
##   flight    — 6-DOF ship flight controls
##   combat    — weapon selection and firing
##   onfoot    — planetary on-foot movement
##   galmap    — galaxy map navigation
##   ui        — global UI / system actions (always active)
##
## Conflict detection:
##   A key conflict exists when two actions in the SAME context share an
##   InputEvent. Cross-context sharing is allowed (e.g. SPACE = flight_up
##   in flight context, onfoot_jump in onfoot context, ui_advance in ui).
##
## Public API:
##   get_active_context() -> String
##   set_active_context(ctx: String) -> void
##   get_contexts() -> Array[String]
##   get_actions_in_context(ctx: String) -> Array[Dictionary]
##   rebind_action(action: String, event: InputEvent) -> bool
##   reset_action(action: String) -> void
##   reset_all() -> void
##   find_conflicts(ctx: String) -> Array[Dictionary]
##   save_keymap() -> void
##   load_keymap() -> void
##   get_action_label(action: String) -> String
##   get_action_context(action: String) -> String
## ============================================================================

const KEYMAP_FILE := "user://keymap.json"

# --- Contexts ---
const CONTEXT_FLIGHT := "flight"
const CONTEXT_COMBAT := "combat"
const CONTEXT_ONFOOT := "onfoot"
const CONTEXT_GALMAP := "galmap"
const CONTEXT_UI := "ui"

var _active_context: String = CONTEXT_FLIGHT

# --- Binding registry ---
# Each entry: { "action": String, "label": String, "context": String,
#               "events": Array[InputEvent] }
# The events array holds the DEFAULT bindings. At runtime, the actual bindings
# live in Godot's InputMap (which we mutate on rebind).
var _registry: Array[Dictionary] = []
# Quick lookup: action -> registry index
var _action_index: Dictionary = {}
# Cached default events for reset: action -> Array[InputEvent]
var _defaults: Dictionary = {}

signal keymap_changed(action: String)
signal active_context_changed(context: String)


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	_build_registry()
	_register_all_actions()
	load_keymap()
	print("[KeymapManager] Initialized — %d actions across %d contexts." \
		% [_registry.size(), get_contexts().size()])


# ============================================================================
# REGISTRY DEFINITION
# ============================================================================

func _build_registry() -> void:
	# --- FLIGHT CONTEXT (FlightController) ---
	_add("flight_forward", "Thrust Forward", CONTEXT_FLIGHT, [
		_key(KEY_W), _key(KEY_I), _key(KEY_KP_8),
	])
	_add("flight_reverse", "Thrust Reverse / Brake", CONTEXT_FLIGHT, [
		_key(KEY_S), _key(KEY_K), _key(KEY_KP_2),
	])
	_add("flight_strafe_left", "Strafe Left", CONTEXT_FLIGHT, [
		_key(KEY_J), _key(KEY_KP_4),
	])
	_add("flight_strafe_right", "Strafe Right", CONTEXT_FLIGHT, [
		_key(KEY_L), _key(KEY_KP_6),
	])
	_add("flight_up", "Thrust Up", CONTEXT_FLIGHT, [
		_key(KEY_SPACE), _key(KEY_R),
	])
	_add("flight_down", "Thrust Down", CONTEXT_FLIGHT, [
		_key(KEY_CTRL), _key(KEY_F),
	])
	_add("flight_pitch_up", "Pitch Up", CONTEXT_FLIGHT, [
		_key(KEY_UP),
	])
	_add("flight_pitch_down", "Pitch Down", CONTEXT_FLIGHT, [
		_key(KEY_DOWN),
	])
	_add("flight_yaw_left", "Yaw Left", CONTEXT_FLIGHT, [
		_key(KEY_LEFT), _key(KEY_A),
	])
	_add("flight_yaw_right", "Yaw Right", CONTEXT_FLIGHT, [
		_key(KEY_RIGHT), _key(KEY_D),
	])
	_add("flight_roll_left", "Roll Left", CONTEXT_FLIGHT, [
		_key(KEY_Q),
	])
	_add("flight_roll_right", "Roll Right", CONTEXT_FLIGHT, [
		_key(KEY_E),
	])
	_add("flight_boost", "Boost (Bio-Plasma)", CONTEXT_FLIGHT, [
		_key(KEY_SHIFT), _key(KEY_TAB),
	])
	_add("flight_wave_engine", "Wave Engine Jump", CONTEXT_FLIGHT, [
		_key(KEY_B),
	])
	_add("flight_dampening_toggle", "Toggle Inertial Dampeners", CONTEXT_FLIGHT, [
		_key(KEY_Z),
	])
	_add("flight_camera_toggle", "Toggle Camera Mode", CONTEXT_FLIGHT, [
		_key(KEY_V), _key(KEY_C),
	])
	_add("flight_combat_track", "Combat Auto-Follow", CONTEXT_FLIGHT, [
		_key(KEY_T), _mouse(MOUSE_BUTTON_RIGHT),
	])
	_add("flight_collision_debug", "Toggle Collision Debug", CONTEXT_FLIGHT, [
		_key(KEY_F3),
	])

	# --- COMBAT CONTEXT (WeaponSystem) ---
	_add("weapon_fire", "Fire Weapon", CONTEXT_COMBAT, [
		_key(KEY_SPACE), _mouse(MOUSE_BUTTON_LEFT),
	])
	_add("weapon_fire_secondary", "Fire Secondary", CONTEXT_COMBAT, [
		_key(KEY_C), _mouse(MOUSE_BUTTON_RIGHT),
	])
	_add("weapon_slot_1", "Weapon Slot 1", CONTEXT_COMBAT, [
		_key(KEY_1),
	])
	_add("weapon_slot_2", "Weapon Slot 2", CONTEXT_COMBAT, [
		_key(KEY_2),
	])
	_add("weapon_slot_3", "Weapon Slot 3", CONTEXT_COMBAT, [
		_key(KEY_3),
	])
	_add("weapon_slot_4", "Weapon Slot 4", CONTEXT_COMBAT, [
		_key(KEY_4), _key(KEY_X),
	])
	_add("weapon_slot_5", "Weapon Slot 5", CONTEXT_COMBAT, [
		_key(KEY_5), _key(KEY_B),
	])
	_add("weapon_slot_6", "Weapon Slot 6", CONTEXT_COMBAT, [
		_key(KEY_6), _key(KEY_M),
	])
	_add("weapon_slot_next", "Next Weapon", CONTEXT_COMBAT, [
		_key(KEY_G),
	])

	# --- ON-FOOT CONTEXT (PlanetCharacterController) ---
	_add("onfoot_forward", "Walk Forward", CONTEXT_ONFOOT, [
		_key(KEY_W), _key(KEY_UP),
	])
	_add("onfoot_back", "Walk Back", CONTEXT_ONFOOT, [
		_key(KEY_S), _key(KEY_DOWN),
	])
	_add("onfoot_left", "Strafe Left", CONTEXT_ONFOOT, [
		_key(KEY_A), _key(KEY_LEFT),
	])
	_add("onfoot_right", "Strafe Right", CONTEXT_ONFOOT, [
		_key(KEY_D), _key(KEY_RIGHT),
	])
	_add("onfoot_run", "Sprint", CONTEXT_ONFOOT, [
		_key(KEY_SHIFT),
	])
	_add("onfoot_crouch", "Crouch", CONTEXT_ONFOOT, [
		_key(KEY_CTRL),
	])
	_add("onfoot_jump", "Jump", CONTEXT_ONFOOT, [
		_key(KEY_SPACE),
	])

	# --- GALAXY MAP CONTEXT (GalaxyMapCamera) ---
	_add("galmap_left", "Pan Left", CONTEXT_GALMAP, [
		_key(KEY_A),
	])
	_add("galmap_right", "Pan Right", CONTEXT_GALMAP, [
		_key(KEY_D),
	])
	_add("galmap_forward", "Pan Forward", CONTEXT_GALMAP, [
		_key(KEY_W),
	])
	_add("galmap_back", "Pan Back", CONTEXT_GALMAP, [
		_key(KEY_S),
	])
	_add("galmap_zoom_in", "Zoom In", CONTEXT_GALMAP, [
		_key(KEY_E), _key(KEY_SPACE),
	])
	_add("galmap_zoom_out", "Zoom Out", CONTEXT_GALMAP, [
		_key(KEY_Q), _key(KEY_CTRL),
	])
	_add("galmap_fast", "Fast Pan", CONTEXT_GALMAP, [
		_key(KEY_SHIFT),
	])

	# --- UI CONTEXT (always active) ---
	_add("ui_interact", "Interact", CONTEXT_UI, [
		_key(KEY_F),
	])
	_add("ui_pause", "Pause / Back", CONTEXT_UI, [
		_key(KEY_ESCAPE),
	])
	_add("ui_skip_dialogue", "Skip Dialogue", CONTEXT_UI, [
		_key(KEY_TAB),
	])
	_add("ui_advance_dialogue", "Advance Dialogue", CONTEXT_UI, [
		_key(KEY_SPACE), _key(KEY_ENTER),
	])
	_add("ui_scanner_toggle", "Toggle Scanner", CONTEXT_UI, [
		_key(KEY_QUOTELEFT),
	])
	_add("ui_galaxymap_toggle", "Toggle Galaxy Map", CONTEXT_UI, [
		_key(KEY_M),
	])
	_add("ui_skip_cinematic", "Skip Cinematic", CONTEXT_UI, [
		_key_ctrl(KEY_ENTER),
	])
	_add("ui_hyperspace_abort", "Abort Hyperspace Jump", CONTEXT_UI, [
		_key(KEY_BACKSPACE),
	])


## Register a single action with its defaults in the registry.
func _add(action: String, label: String, context: String, events: Array) -> void:
	var idx: int = _registry.size()
	_registry.append({
		"action": action,
		"label": label,
		"context": context,
		"events": events,
	})
	_action_index[action] = idx
	_defaults[action] = events.duplicate(true)


# ============================================================================
# INPUTMAP REGISTRATION
# ============================================================================

## Register all actions from the registry into Godot's InputMap.
## Preserves the built-in ui_* actions (ui_accept, ui_cancel, etc).
func _register_all_actions() -> void:
	for entry in _registry:
		var action: String = entry.action
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for event in entry.events:
			InputMap.action_add_event(action, event)


# ============================================================================
# CONTEXT MANAGEMENT
# ============================================================================

func get_active_context() -> String:
	return _active_context


func set_active_context(ctx: String) -> void:
	if ctx == _active_context:
		return
	_active_context = ctx
	active_context_changed.emit(ctx)
	print("[KeymapManager] Active context: %s" % ctx)


func get_contexts() -> Array[String]:
	var ctxs: Array[String] = []
	for entry in _registry:
		if not ctxs.has(entry.context):
			ctxs.append(entry.context)
	return ctxs


func get_context_label(ctx: String) -> String:
	match ctx:
		CONTEXT_FLIGHT: return "Flight"
		CONTEXT_COMBAT: return "Combat"
		CONTEXT_ONFOOT: return "On-Foot"
		CONTEXT_GALMAP: return "Galaxy Map"
		CONTEXT_UI: return "Interface"
		_: return ctx.capitalize()


# ============================================================================
# ACTION QUERIES
# ============================================================================

func get_actions_in_context(ctx: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _registry:
		if entry.context == ctx:
			# Return a copy with the CURRENT events from InputMap
			var live_events: Array[InputEvent] = []
			if InputMap.has_action(entry.action):
				live_events = InputMap.action_get_events(entry.action)
			result.append({
				"action": entry.action,
				"label": entry.label,
				"context": entry.context,
				"events": live_events,
			})
	return result


func get_action_label(action: String) -> String:
	if _action_index.has(action):
		return String(_registry[_action_index[action]].label)
	return action


func get_action_context(action: String) -> String:
	if _action_index.has(action):
		return String(_registry[_action_index[action]].context)
	return ""


func get_all_actions() -> Array[Dictionary]:
	return _registry.duplicate(true)


# ============================================================================
# REBINDING
# ============================================================================

## Rebind an action to a new InputEvent. Returns true on success.
## If the new event conflicts with another action in the same context,
## the rebind is rejected and returns false.
func rebind_action(action: String, event: InputEvent, allow_conflict: bool = false) -> bool:
	if not _action_index.has(action):
		push_warning("[KeymapManager] Unknown action: %s" % action)
		return false
	if not allow_conflict:
		var conflicts := _find_conflicts_for_event(action, event)
		if conflicts.size() > 0:
			push_warning("[KeymapManager] Conflict: %s would clash with %s" \
				% [action, ", ".join(conflicts)])
			return false
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	save_keymap()
	keymap_changed.emit(action)
	return true


## Add an additional binding to an action (multi-key support).
## Returns true on success. Rejects if the event conflicts within the same context.
func add_binding(action: String, event: InputEvent, allow_conflict: bool = false) -> bool:
	if not _action_index.has(action):
		return false
	if not allow_conflict:
		var conflicts := _find_conflicts_for_event(action, event)
		if conflicts.size() > 0:
			return false
	if InputMap.has_action(action):
		InputMap.action_add_event(action, event)
	save_keymap()
	keymap_changed.emit(action)
	return true


## Remove a specific binding from an action.
func remove_binding(action: String, event: InputEvent) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_event(action, event)
	save_keymap()
	keymap_changed.emit(action)


## Reset a single action to its default bindings.
func reset_action(action: String) -> void:
	if not _defaults.has(action):
		return
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for event in _defaults[action]:
		InputMap.action_add_event(action, event)
	save_keymap()
	keymap_changed.emit(action)


## Reset all actions to their default bindings.
func reset_all() -> void:
	for entry in _registry:
		reset_action(entry.action)
	save_keymap()


# ============================================================================
# CONFLICT DETECTION
# ============================================================================

## Find all conflicts within a context. Returns an array of conflict dicts:
##   { "actions": [String, String], "event": InputEvent, "event_label": String }
func find_conflicts(ctx: String) -> Array[Dictionary]:
	var actions := get_actions_in_context(ctx)
	var conflicts: Array[Dictionary] = []
	# Build a map: event_signature -> [action names]
	var event_map: Dictionary = {}
	for entry in actions:
		for event in entry.events:
			var sig := _event_signature(event)
			if not event_map.has(sig):
				event_map[sig] = []
			event_map[sig].append(entry.action)
	# Any signature with 2+ actions is a conflict
	for sig in event_map:
		var acts: Array = event_map[sig]
		if acts.size() > 1:
			conflicts.append({
				"actions": acts,
				"event_label": _event_label_string(_find_event_by_signature(acts[0], sig)),
			})
	return conflicts


## Find all conflicts across ALL contexts. Returns array of conflict dicts.
func find_all_conflicts() -> Array[Dictionary]:
	var all_conflicts: Array[Dictionary] = []
	for ctx in get_contexts():
		var ctx_conflicts := find_conflicts(ctx)
		for c in ctx_conflicts:
			c["context"] = ctx
			all_conflicts.append(c)
	return all_conflicts


## Check if binding `event` to `action` would conflict with another action
## in the same context. Returns the list of conflicting action names.
func _find_conflicts_for_event(action: String, event: InputEvent) -> Array[String]:
	var ctx: String = get_action_context(action)
	if ctx == "":
		return []
	var sig := _event_signature(event)
	var conflicts: Array[String] = []
	for entry in _registry:
		if entry.context != ctx:
			continue
		if entry.action == action:
			continue
		# Check if this action already has this event
		if InputMap.has_action(entry.action):
			for existing_event in InputMap.action_get_events(entry.action):
				if _event_signature(existing_event) == sig:
					conflicts.append(entry.action)
					break
	return conflicts


## Generate a unique signature for an InputEvent for conflict comparison.
func _event_signature(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		return "key:%d:ctrl:%s:shift:%s:alt:%s" % [k.keycode, k.ctrl_pressed, k.shift_pressed, k.alt_pressed]
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		return "mouse:%d" % m.button_index
	return str(event)


## Find an InputEvent on an action matching a signature string.
func _find_event_by_signature(action: String, sig: String) -> InputEvent:
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if _event_signature(event) == sig:
				return event
	return null


# ============================================================================
# PERSISTENCE
# ============================================================================

func save_keymap() -> void:
	var data: Dictionary = {}
	for entry in _registry:
		var action: String = entry.action
		if InputMap.has_action(action):
			var events: Array[InputEvent] = InputMap.action_get_events(action)
			var serialized: Array = []
			for event in events:
				serialized.append(_serialize_event(event))
			data[action] = serialized
	var file := FileAccess.open(KEYMAP_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		push_error("[KeymapManager] Failed to save keymap to " + KEYMAP_FILE)


func load_keymap() -> void:
	if not FileAccess.file_exists(KEYMAP_FILE):
		return
	var file := FileAccess.open(KEYMAP_FILE, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK or not (json.data is Dictionary):
		push_warning("[KeymapManager] Failed to parse keymap file, using defaults.")
		return
	var data: Dictionary = json.data
	for action in data:
		if not InputMap.has_action(action):
			continue
		var serialized: Array = data[action]
		if not (serialized is Array):
			continue
		InputMap.action_erase_events(action)
		for entry in serialized:
			var event := _deserialize_event(entry)
			if event != null:
				InputMap.action_add_event(action, event)
	print("[KeymapManager] Loaded custom keymap from %s (%d actions)." % [KEYMAP_FILE, data.size()])


func _serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k := event as InputEventKey
		return {
			"type": "key",
			"keycode": k.keycode,
			"ctrl": k.ctrl_pressed,
			"shift": k.shift_pressed,
			"alt": k.alt_pressed,
		}
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		return {
			"type": "mouse",
			"button": m.button_index,
		}
	return {}


func _deserialize_event(data: Dictionary) -> InputEvent:
	var type: String = String(data.get("type", ""))
	if type == "key":
		var k := InputEventKey.new()
		k.keycode = int(data.get("keycode", 0)) as Key
		k.ctrl_pressed = bool(data.get("ctrl", false))
		k.shift_pressed = bool(data.get("shift", false))
		k.alt_pressed = bool(data.get("alt", false))
		return k
	elif type == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(data.get("button", 0)) as MouseButton
		return m
	return null


# ============================================================================
# DISPLAY HELPERS
# ============================================================================

## Return a human-readable string for an InputEvent (e.g. "W", "SPACE", "LMB").
func event_to_string(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		var prefix := ""
		if k.ctrl_pressed:
			prefix += "Ctrl+"
		if k.shift_pressed:
			prefix += "Shift+"
		if k.alt_pressed:
			prefix += "Alt+"
		return prefix + OS.get_keycode_string(k.keycode)
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		match m.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			_: return "Mouse %d" % m.button_index
	return "—"


## Return a comma-separated string of all bindings for an action.
func action_bindings_string(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return "—"
	var parts: Array[String] = []
	for event in events:
		parts.append(event_to_string(event))
	return ", ".join(parts)


func _event_label_string(event: InputEvent) -> String:
	return event_to_string(event)


# ============================================================================
# EVENT FACTORY HELPERS
# ============================================================================

func _key(keycode: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = keycode as Key
	return k

func _key_ctrl(keycode: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = keycode as Key
	k.ctrl_pressed = true
	return k


func _mouse(button: int) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = button as MouseButton
	return m
