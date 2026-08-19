class_name DialogueUI
extends CanvasLayer

## ============================================================================
## BioGenesis-X Dialogue UI
## ----------------------------------------------------------------------------
## A self-contained biopunk-styled dialogue balloon built on the Dialogue
## Manager 3 API. Renders a dark organic panel with cyan-green bioluminescent
## text and choice buttons over any game scene.
##
## Signals:
##   dialogue_started()              — emitted when a conversation begins
##   dialogue_ended(result: Dictionary) — emitted when a conversation ends
##                                       (contains dialogue variables snapshot)
##   choice_made(key: String)        — emitted when the player picks a choice;
##                                       `key` is the destination title/next_id
##
## Usage:
##   dialogue_ui.start(dialogue_resource, "start", [state_owner])
##   dialogue_ui.hide_dialogue()
## ============================================================================

signal dialogue_started
signal dialogue_ended(result: Dictionary)
signal choice_made(key: String)

## The action used to advance a line of dialogue when no choices are shown.
@export var next_action: StringName = &"ui_accept"

## If true, all other input is consumed while the dialogue panel is visible.
@export var block_other_input: bool = true

## Typing speed in characters per second (0 = instant).
@export var typing_speed_cps: float = 60.0

# --- Internal state ---
var _resource: DialogueResource = null
var _extra_game_states: Array = []
var _line: DialogueLine = null
var _is_active: bool = false
var _is_typing: bool = false
var _typed_chars: int = 0
var _type_accum: float = 0.0
var _result_snapshot: Dictionary = {}

# --- UI nodes (built in code) ---
var _root: Control = null
var _panel: Panel = null
var _vbox: VBoxContainer = null
var _character_label: Label = null
var _dialogue_label: RichTextLabel = null
var _responses_container: VBoxContainer = null
var _advance_hint: Label = null

# Biopunk palette
const _COLOR_BG := Color(0.018, 0.045, 0.038, 0.94)
const _COLOR_BORDER := Color(0.0, 0.78, 0.70, 0.85)
const _COLOR_TEXT := Color(0.55, 1.0, 0.92, 1.0)
const _COLOR_CHARACTER := Color(0.0, 0.95, 0.85, 1.0)
const _COLOR_CHOICE := Color(0.05, 0.18, 0.15, 0.9)
const _COLOR_CHOICE_HOVER := Color(0.0, 0.32, 0.27, 0.95)
const _COLOR_CHOICE_TEXT := Color(0.62, 1.0, 0.9, 1.0)
const _COLOR_HINT := Color(0.0, 0.85, 0.75, 0.7)


func _ready() -> void:
	layer = 50
	_build_ui()
	_hide_panel()
	# Pause the game world while dialogue is shown so narrative beats land.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _exit_tree() -> void:
	# Mark inactive — nodes are being torn down by the tree, no need to
	# manually free children (queue_free during _exit_tree causes stack underflow).
	_is_active = false


# ============================================================================
# PUBLIC API
# ============================================================================

## Begin a conversation from [param resource], optionally starting at
## [param title]. [param extra_game_states] is forwarded to Dialogue Manager so
## dialogue variables can be read/mutated on the provided objects.
func start(resource: DialogueResource, title: String = "", extra_game_states: Array = []) -> void:
	if not is_instance_valid(resource):
		push_error("[DialogueUI] Cannot start — dialogue resource is null.")
		return
	# If _ready() hasn't run yet (sibling node ordering race), defer until ready.
	if _root == null:
		call_deferred("start", resource, title, extra_game_states)
		return
	_resource = resource
	_extra_game_states = extra_game_states
	_result_snapshot.clear()
	_is_active = true
	_show_panel()
	dialogue_started.emit()
	_advance_to(title)


## Hide the panel and end any active conversation immediately.
func hide_dialogue() -> void:
	_end_conversation()


## Returns true while a conversation is actively being shown.
func is_active() -> bool:
	return _is_active


# ============================================================================
# CONVERSATION FLOW
# ============================================================================

## Request the next dialogue line from Dialogue Manager starting at [param key].
func _advance_to(key: String) -> void:
	if not is_instance_valid(_resource):
		_end_conversation()
		return
	var dm: Node = Engine.get_singleton("DialogueManager")
	if dm == null:
		push_error("[DialogueUI] DialogueManager singleton unavailable.")
		_end_conversation()
		return
	# Forward the extra game states so dialogue variables resolve/mutate there.
	_line = await dm.get_next_dialogue_line(_resource, key, _extra_game_states)
	if not _is_valid_line(_line):
		_end_conversation()
		return
	_apply_line(_line)


## Render the current [param line] — character name, typed text, and choices.
func _apply_line(line: DialogueLine) -> void:
	_clear_responses()

	# Character name
	if line.character.is_empty():
		_character_label.hide()
	else:
		_character_label.text = line.character
		_character_label.show()

	# Dialogue text (typed out for a biopunk terminal feel)
	_dialogue_label.text = line.text
	_dialogue_label.visible_ratio = 0.0
	_typed_chars = 0
	_type_accum = 0.0
	_is_typing = true
	_advance_hint.hide()

	# Choices
	if line.responses.size() > 0:
		_is_typing = false
		_dialogue_label.visible_ratio = 1.0
		_build_responses(line.responses)


## Per-frame typing animation and advance-hint visibility.
func _process(delta: float) -> void:
	if not _is_active:
		return

	if _is_typing:
		_type_accum += delta * typing_speed_cps
		var target_chars: int = int(_type_accum)
		while _typed_chars < target_chars:
			_typed_chars += 1
			_dialogue_label.visible_ratio = float(_typed_chars) / float(max(1, _dialogue_label.get_total_character_count()))
			if _typed_chars >= _dialogue_label.get_total_character_count():
				_is_typing = false
				break
		if not _is_typing:
			_on_typing_finished()


func _on_typing_finished() -> void:
	_dialogue_label.visible_ratio = 1.0
	if _line and _line.responses.size() == 0:
		_advance_hint.show()


## Build a button for each response and wire selection.
func _build_responses(responses: Array) -> void:
	for response in responses:
		if not is_instance_valid(response):
			continue
		if not response.is_allowed:
			continue
		var btn := Button.new()
		btn.text = response.text
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", _COLOR_CHOICE_TEXT)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_stylebox_override("normal", _make_choice_stylebox(_COLOR_CHOICE))
		btn.add_theme_stylebox_override("hover", _make_choice_stylebox(_COLOR_CHOICE_HOVER))
		btn.add_theme_stylebox_override("pressed", _make_choice_stylebox(_COLOR_CHOICE_HOVER))
		btn.add_theme_stylebox_override("focus", _make_choice_stylebox(_COLOR_CHOICE_HOVER))
		btn.custom_minimum_size = Vector2(0, 38)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_response_selected.bind(response))
		_responses_container.add_child(btn)
	# Focus the first choice for keyboard navigation.
	if _responses_container.get_child_count() > 0:
		_responses_container.get_child(0).grab_focus()


func _clear_responses() -> void:
	for child in _responses_container.get_children():
		child.queue_free()


func _on_response_selected(response: DialogueResponse) -> void:
	var key: String = response.next_id
	choice_made.emit(key)
	_advance_to(key)


## Advance to the next line when the player triggers the next action and no
## choices are currently shown.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_active or not _is_visible_panel():
		return
	if block_other_input:
		get_viewport().set_input_as_handled()

	# Skip typing on any accept/click
	if _is_typing:
		if event.is_action_pressed(next_action) or _is_mouse_click(event):
			_is_typing = false
			_dialogue_label.visible_ratio = 1.0
			_on_typing_finished()
			get_viewport().set_input_as_handled()
		return

	# Only auto-advance when there are no choices
	if _line and _line.responses.size() > 0:
		return

	if event.is_action_pressed(next_action) or _is_mouse_click(event):
		if is_instance_valid(_line):
			_advance_to(_line.next_id)


func _is_mouse_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()


# ============================================================================
# CONVERSATION END
# ============================================================================

## Tear down the active conversation, snapshot dialogue variables from the
## extra game states, and emit dialogue_ended.
func _end_conversation() -> void:
	if not _is_active:
		return
	_is_active = false
	_is_typing = false
	_line = null
	# Collect a snapshot of any scalar properties from the provided game states
	# so callers can inspect dialogue outcomes (e.g. bond_accepted).
	_result_snapshot = _snapshot_game_states()
	_hide_panel()
	dialogue_ended.emit(_result_snapshot)


## Build a shallow snapshot of scalar properties from extra game states.
func _snapshot_game_states() -> Dictionary:
	var snap: Dictionary = {}
	for state in _extra_game_states:
		if state == null:
			continue
		if typeof(state) == TYPE_DICTIONARY:
			for k in state:
				snap[k] = state[k]
		else:
			for prop in state.get_property_list():
				var pname: String = prop.name
				if pname in [&"script", &"script_name", &"resource_path", &"type", &"name"]:
					continue
				var value: Variant = state.get(pname)
				var t: int = typeof(value)
				# Only snapshot plain scalars/containers to keep it serializable.
				if t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_NIL, TYPE_ARRAY, TYPE_DICTIONARY]:
					snap[pname] = value
	return snap


# ============================================================================
# UI CONSTRUCTION (biopunk aesthetic)
# ============================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "DialogueUIRoot"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_panel = Panel.new()
	_panel.name = "DialoguePanel"
	_panel.anchor_left = 0.08
	_panel.anchor_top = 0.62
	_panel.anchor_right = 0.92
	_panel.anchor_bottom = 0.94
	_panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	_root.add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.name = "DialogueVBox"
	_vbox.anchor_right = 1.0
	_vbox.anchor_bottom = 1.0
	_vbox.offset_left = 28
	_vbox.offset_top = 22
	_vbox.offset_right = -28
	_vbox.offset_bottom = -22
	_vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(_vbox)

	# Character name label
	_character_label = Label.new()
	_character_label.name = "CharacterLabel"
	_character_label.add_theme_font_size_override("font_size", 19)
	_character_label.add_theme_color_override("font_color", _COLOR_CHARACTER)
	_character_label.add_theme_color_override("font_shadow_color", Color(0, 0.3, 0.25, 0.6))
	_character_label.add_theme_constant_override("shadow_offset_x", 2)
	_character_label.add_theme_constant_override("shadow_offset_y", 2)
	_character_label.add_theme_constant_override("shadow_outline_size", 1)
	_character_label.hide()
	_vbox.add_child(_character_label)

	# Dialogue text (RichTextLabel for bbcode + visible_ratio typing)
	_dialogue_label = RichTextLabel.new()
	_dialogue_label.name = "DialogueLabel"
	_dialogue_label.bbcode_enabled = true
	_dialogue_label.fit_content = false
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.add_theme_font_size_override("normal_font_size", 17)
	_dialogue_label.add_theme_color_override("default_color", _COLOR_TEXT)
	_dialogue_label.add_theme_color_override("font_shadow_color", Color(0, 0.25, 0.2, 0.5))
	_dialogue_label.add_theme_constant_override("shadow_offset_x", 1)
	_dialogue_label.add_theme_constant_override("shadow_offset_y", 1)
	_dialogue_label.custom_minimum_size = Vector2(0, 90)
	_dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(_dialogue_label)

	# Responses container
	_responses_container = VBoxContainer.new()
	_responses_container.name = "ResponsesContainer"
	_responses_container.add_theme_constant_override("separation", 8)
	_responses_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_vbox.add_child(_responses_container)

	# Advance hint
	_advance_hint = Label.new()
	_advance_hint.name = "AdvanceHint"
	_advance_hint.text = "▶  [SPACE / CLICK]  to continue"
	_advance_hint.add_theme_font_size_override("font_size", 13)
	_advance_hint.add_theme_color_override("font_color", _COLOR_HINT)
	_advance_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_advance_hint.hide()
	_vbox.add_child(_advance_hint)


func _show_panel() -> void:
	if _root:
		_root.visible = true
	if _panel:
		_panel.visible = true


func _hide_panel() -> void:
	if _root:
		_root.visible = false
	if _panel:
		_panel.visible = false


func _is_visible_panel() -> bool:
	return _root != null and _root.visible


## Dark organic panel stylebox with a cyan-green bioluminescent border.
func _make_panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _COLOR_BG
	sb.border_color = _COLOR_BORDER
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 18
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0.45, 0.4, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2.ZERO
	sb.expand_margin_left = 2
	sb.expand_margin_right = 2
	return sb


## Choice button stylebox — organic rounded, semi-transparent.
func _make_choice_stylebox(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.0, 0.7, 0.62, 0.6)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


# ============================================================================
# HELPERS
# ============================================================================

func _is_valid_line(line: DialogueLine) -> bool:
	return line != null and is_instance_valid(line)


## Expose the last result snapshot for callers that connect after the fact.
func get_last_result() -> Dictionary:
	return _result_snapshot
