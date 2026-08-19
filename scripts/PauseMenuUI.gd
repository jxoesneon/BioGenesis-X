# ==============================================================================
# PauseMenuUI.gd - BioGenesis-X In-Game Pause Menu Controller
# Pumilio Studios - AAA UI/UX Division
# ==============================================================================

@tool
class_name PauseMenuUI
extends Control

var btn_resume: Button
var btn_builder: Button
var btn_main_menu: Button
var btn_quit: Button
var slider_volume: HSlider
var lbl_volume: Label

var _bio_manager_ref: Node = null
var _animation_time: float = 0.0

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false

	# Background Darkening Overlay with frosted glass feel
	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0.01, 0.03, 0.06, 0.88)
	bg_overlay.anchor_right = 1.0
	bg_overlay.anchor_bottom = 1.0
	add_child(bg_overlay)

	# Central Menu Container
	var center_box := CenterContainer.new()
	center_box.anchor_right = 1.0
	center_box.anchor_bottom = 1.0
	add_child(center_box)

	# Glass card panel container
	var panel_card := PanelContainer.new()
	panel_card.custom_minimum_size = Vector2(400, 440)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.02, 0.05, 0.04, 0.92)
	card_style.border_color = Color(0.0, 0.9, 0.7, 0.7)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(8)
	card_style.set_expand_margin_all(12)
	panel_card.add_theme_stylebox_override("panel", card_style)
	center_box.add_child(panel_card)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.custom_minimum_size = Vector2(380, 420)
	panel_vbox.add_theme_constant_override("separation", 16)
	panel_card.add_child(panel_vbox)

	# Header Title
	var lbl_title := Label.new()
	lbl_title.text = "BIOGENESIS-X PAUSED"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 24)
	lbl_title.add_theme_color_override("font_color", Color(0.0, 0.9, 0.75, 1.0))
	panel_vbox.add_child(lbl_title)

	var h_sep := HSeparator.new()
	panel_vbox.add_child(h_sep)

	# Audio Volume Control
	var vol_box := VBoxContainer.new()
	lbl_volume = Label.new()
	lbl_volume.text = "MASTER VOLUME: 100%"
	lbl_volume.add_theme_font_size_override("font_size", 12)
	lbl_volume.add_theme_color_override("font_color", Color(0.7, 0.9, 0.85, 0.9))
	vol_box.add_child(lbl_volume)

	slider_volume = HSlider.new()
	slider_volume.min_value = 0.0
	slider_volume.max_value = 1.0
	slider_volume.step = 0.05
	# Load current value from SettingsSystem
	var settings := _get_settings_system()
	var current_vol: float = 0.8
	if settings and settings.has_method("get_setting"):
		current_vol = float(settings.get_setting("audio", "master_volume", 0.8))
	slider_volume.value = current_vol
	slider_volume.value_changed.connect(_on_volume_changed)
	vol_box.add_child(slider_volume)
	panel_vbox.add_child(vol_box)

	# Buttons
	btn_resume = _create_menu_button("RESUME SIMULATION", _on_resume_pressed)
	panel_vbox.add_child(btn_resume)

	btn_builder = _create_menu_button("SHIP BUILDER LAB", _on_builder_pressed)
	panel_vbox.add_child(btn_builder)

	btn_main_menu = _create_menu_button("RETURN TO MAIN MENU", _on_main_menu_pressed)
	panel_vbox.add_child(btn_main_menu)

	btn_quit = _create_menu_button("EXIT GAME", _on_quit_pressed)
	panel_vbox.add_child(btn_quit)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		toggle_pause()

var _tree_ref: SceneTree = null

func toggle_pause() -> void:
	var tree: SceneTree = _tree_ref if _tree_ref else (get_tree() if is_inside_tree() else null)
	if tree == null:
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			tree = ml as SceneTree

	if tree:
		var new_paused_state := not tree.paused
		tree.paused = new_paused_state
		visible = new_paused_state
		if new_paused_state:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Notify BioAudioDirector for pause audio ducking
		var director := tree.root.get_node_or_null("BioAudioDirector")
		if director:
			director.set_pause_audio(new_paused_state)

func _process(delta: float) -> void:
	_animation_time += delta
	if visible:
		queue_redraw()

func _draw() -> void:
	# Biopunk decorative background: animated organic pulse rings + bio-grid
	var sz: Vector2 = size
	var center: Vector2 = sz * 0.5
	var t: float = _animation_time

	# 1. Dark vignette overlay — deeper at edges
	var _edge_fade: float = minf(sz.x, sz.y) * 0.45
	for i in range(6):
		var alpha: float = 0.04 * (1.0 - float(i) / 6.0)
		draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0.0, 0.05, 0.03, alpha), true)

	# 2. Animated organic pulse rings — bioluminescent teal-green
	for ring in range(4):
		var phase: float = t * 0.4 + ring * 0.7
		var radius: float = 80.0 + ring * 120.0 + sin(phase) * 20.0
		var alpha: float = 0.08 + sin(phase * 1.3) * 0.04
		var col: Color = Color(0.0, 0.8, 0.6, alpha)
		draw_arc(center, radius, 0, TAU, 64, col, 1.5)

	# 3. Bio-grid — subtle hexagonal pattern suggesting cellular structure
	var grid_spacing: float = 60.0
	var grid_alpha: float = 0.03 + sin(t * 0.5) * 0.01
	var grid_col: Color = Color(0.0, 0.6, 0.5, grid_alpha)
	var ox: float = fmod(t * 8.0, grid_spacing)
	for x in range(int(-grid_spacing + ox), int(sz.x + grid_spacing), int(grid_spacing)):
		draw_line(Vector2(x, 0), Vector2(x, sz.y), grid_col, 1.0)
	for y in range(0, int(sz.y + grid_spacing), int(grid_spacing)):
		draw_line(Vector2(0, y), Vector2(sz.x, y), grid_col, 1.0)

	# 4. Central glow — bioluminescent core behind menu
	var core_radius: float = 200.0 + sin(t * 0.8) * 15.0
	var core_alpha: float = 0.06 + sin(t * 1.2) * 0.02
	draw_circle(center, core_radius, Color(0.0, 0.9, 0.7, core_alpha))
	draw_circle(center, core_radius * 0.6, Color(0.0, 1.0, 0.8, core_alpha * 1.5))

func _create_menu_button(txt: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(0.0, 1.0, 0.75))
	btn.pressed.connect(callback)

	var style_norm := StyleBoxFlat.new()
	style_norm.bg_color = Color(0.04, 0.1, 0.08, 0.8)
	style_norm.border_color = Color(0.0, 0.7, 0.55, 0.5)
	style_norm.set_border_width_all(1)
	style_norm.set_corner_radius_all(6)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.08, 0.22, 0.16, 0.95)
	style_hover.border_color = Color(0.0, 1.0, 0.75, 0.9)
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(6)

	btn.add_theme_stylebox_override("normal", style_norm)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)

	return btn

func _on_volume_changed(val: float) -> void:
	lbl_volume.text = "MASTER VOLUME: %d%%" % int(val * 100.0)
	# Persist through SettingsSystem (which also applies to the bus)
	var settings := _get_settings_system()
	if settings and settings.has_method("set_setting"):
		settings.set_setting("audio", "master_volume", val)
	else:
		# Fallback: direct bus set if SettingsSystem not available
		var bus_idx := AudioServer.get_bus_index("Master")
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(0.001, val)))

func _get_settings_system() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("SettingsSystem"):
		return ml.root.get_node("SettingsSystem")
	return null

func _play_ui_click(is_confirm: bool = true) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(is_confirm)

func _on_resume_pressed() -> void:
	_play_ui_click(true)
	toggle_pause()

func _get_bio_manager() -> Node:
	if _bio_manager_ref:
		return _bio_manager_ref
	if is_inside_tree() and get_tree() and get_tree().root and get_tree().root.has_node("BioManager"):
		_bio_manager_ref = get_tree().root.get_node("BioManager")
	return _bio_manager_ref

func _on_builder_pressed() -> void:
	_play_ui_click(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		ml.set("paused", false)
		if ml.root and ml.root.has_node("BioAudioDirector"):
			ml.root.get_node("BioAudioDirector").set_pause_audio(false)
			ml.root.get_node("BioAudioDirector").transition_to_scene("res://scenes/ship_builder.tscn")
		elif ml.has_method("change_scene_to_file"):
			ml.call("change_scene_to_file", "res://scenes/ship_builder.tscn")
	var mgr := _get_bio_manager()
	if mgr and mgr.has_method("set_game_mode"):
		mgr.call("set_game_mode", 0) # BUILDER_MODE

func _on_main_menu_pressed() -> void:
	_play_ui_click(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		ml.set("paused", false)
		if ml.root and ml.root.has_node("BioAudioDirector"):
			ml.root.get_node("BioAudioDirector").set_pause_audio(false)
			ml.root.get_node("BioAudioDirector").transition_to_scene("res://scenes/main_menu.tscn")
		elif ml.has_method("change_scene_to_file"):
			ml.call("change_scene_to_file", "res://scenes/main_menu.tscn")
	var mgr := _get_bio_manager()
	if mgr and mgr.has_method("set_game_mode"):
		mgr.call("set_game_mode", 0) # BUILDER_MODE

func _on_quit_pressed() -> void:
	_play_ui_click(false)
	var ml := Engine.get_main_loop()
	if ml and ml.has_method("quit"):
		ml.call("quit")
