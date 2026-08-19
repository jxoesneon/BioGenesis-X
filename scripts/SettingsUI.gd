# res://scripts/SettingsUI.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# SettingsUI.gd — AAA+ Settings Screen with Tabbed Sections
# ==============================================================================
# Full settings menu with five sections matching AAA standards:
#   - GRAPHICS: quality preset, fullscreen, vsync, MSAA, FXAA, shadows, render
#               scale, max FPS, textures, anisotropic, volumetric fog, reflections,
#               occlusion culling, LOD bias, motion blur, DOF, bloom, chromatic
#               aberration, film grain, vignette, FOV
#   - AUDIO: master/music/sfx/ui volume, reverb send, subtitles, subtitle bg,
#            audio device
#   - GAMEPLAY: difficulty, POI scan radius, max POI indicators, HUD opacity,
#               auto-aim, camera sensitivity, flight damping, debug overlay,
#               minimap, damage numbers, crosshair style, noise map, scanner
#   - CONTROLS: invert Y, mouse sensitivity, controller enabled, deadzone,
#               vibration, vibration intensity
#   - ACCESSIBILITY: color blind mode, UI scale, text size, high contrast,
#                     reduce motion, screen shake intensity
#
# All settings are persisted via SettingsSystem autoload to user://settings.json.
# Changes apply immediately and are saved on every adjustment.
# ==============================================================================

@tool
class_name SettingsUI
extends Control

# --- Theme constants (biopunk palette matching MainMenuUI) ---
const COLOR_BG := Color(0.015, 0.035, 0.03, 1.0)
const COLOR_PANEL_BG := Color(0.02, 0.05, 0.04, 0.92)
const COLOR_BORDER := Color(0.0, 0.9, 0.7, 0.8)
const COLOR_TITLE := Color(0.0, 1.0, 0.75)
const COLOR_SUBTITLE := Color(0.0, 0.75, 0.6)
const COLOR_LABEL := Color(0.85, 1.0, 0.95)
const COLOR_VALUE := Color(0.0, 0.9, 0.7)
const COLOR_ACCENT_GRAPHICS := Color(0.8, 0.4, 1.0)
const COLOR_ACCENT_AUDIO := Color(0.0, 0.9, 1.0)
const COLOR_ACCENT_GAMEPLAY := Color(0.0, 1.0, 0.6)
const COLOR_ACCENT_CONTROLS := Color(1.0, 0.8, 0.2)
const COLOR_ACCENT_ACCESS := Color(1.0, 0.5, 0.3)
const COLOR_ACCENT_BACK := Color(1.0, 0.3, 0.3)
const COLOR_ACCENT_DEBUG := Color(1.0, 0.85, 0.2)  # Yellow — caution/debug convention
const COLOR_HEADER := Color(0.0, 0.85, 0.65)

# --- UI References ---
var _tab_container: TabContainer
var _animation_time: float = 0.0
var _scroll_graphics: ScrollContainer
var _scroll_audio: ScrollContainer
var _scroll_gameplay: ScrollContainer
var _scroll_controls: ScrollContainer
var _scroll_accessibility: ScrollContainer
var _scroll_language: ScrollContainer
var _scroll_debug: ScrollContainer

# --- Section inner VBoxes ---
var _section_graphics: VBoxContainer
var _section_audio: VBoxContainer
var _section_gameplay: VBoxContainer
var _section_controls: VBoxContainer
var _section_accessibility: VBoxContainer
var _section_language: VBoxContainer
var _section_debug: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_settings_ui()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _exit_tree() -> void:
	if resized.is_connected(_on_resized):
		resized.disconnect(_on_resized)

func _on_resized() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	_animation_time += delta
	queue_redraw()

# ------------------------------------------------------------------------------
# UI Construction
# ------------------------------------------------------------------------------

func _build_settings_ui() -> void:
	for child in get_children():
		child.queue_free()

	# Full-screen center container
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)

	# Main glass card panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 620)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_expand_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(root_vbox)

	# Title header
	var lbl_title := Label.new()
	lbl_title.text = tr("SETTINGS")
	lbl_title.add_theme_color_override("font_color", COLOR_TITLE)
	lbl_title.add_theme_font_size_override("font_size", 28)
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(lbl_title)

	var lbl_subtitle := Label.new()
	lbl_subtitle.text = "Configure your BioGenesis-X experience"
	lbl_subtitle.add_theme_color_override("font_color", COLOR_SUBTITLE)
	lbl_subtitle.add_theme_font_size_override("font_size", 11)
	lbl_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(lbl_subtitle)

	root_vbox.add_child(HSeparator.new())

	# Tab container with sections
	_tab_container = TabContainer.new()
	_tab_container.custom_minimum_size = Vector2(760, 440)
	root_vbox.add_child(_tab_container)

	# Build each section — GRAPHICS first (most used in AAA)
	_scroll_graphics = _build_section_scroll(tr("GRAPHICS"), COLOR_ACCENT_GRAPHICS)
	_tab_container.add_child(_scroll_graphics)
	_section_graphics = _get_inner_vbox(_scroll_graphics)
	_populate_graphics_section()

	_scroll_audio = _build_section_scroll(tr("AUDIO"), COLOR_ACCENT_AUDIO)
	_tab_container.add_child(_scroll_audio)
	_section_audio = _get_inner_vbox(_scroll_audio)
	_populate_audio_section()

	_scroll_gameplay = _build_section_scroll(tr("GAMEPLAY"), COLOR_ACCENT_GAMEPLAY)
	_tab_container.add_child(_scroll_gameplay)
	_section_gameplay = _get_inner_vbox(_scroll_gameplay)
	_populate_gameplay_section()

	_scroll_controls = _build_section_scroll(tr("CONTROLS"), COLOR_ACCENT_CONTROLS)
	_tab_container.add_child(_scroll_controls)
	_section_controls = _get_inner_vbox(_scroll_controls)
	_populate_controls_section()

	_scroll_accessibility = _build_section_scroll(tr("ACCESSIBILITY"), COLOR_ACCENT_ACCESS)
	_tab_container.add_child(_scroll_accessibility)
	_section_accessibility = _get_inner_vbox(_scroll_accessibility)
	_populate_accessibility_section()

	# LANGUAGE section (LocGuard Lite localization)
	var lang_accent := Color(0.4, 0.9, 1.0)
	_scroll_language = _build_section_scroll(tr("LANGUAGE"), lang_accent)
	_tab_container.add_child(_scroll_language)
	_section_language = _get_inner_vbox(_scroll_language)
	_populate_language_section()

	# DEBUG section (developer tools — only visible in debug builds)
	if OS.is_debug_build():
		_scroll_debug = _build_section_scroll(tr("DEBUG"), COLOR_ACCENT_DEBUG)
		_tab_container.add_child(_scroll_debug)
		_section_debug = _get_inner_vbox(_scroll_debug)
		_populate_debug_section()

	root_vbox.add_child(HSeparator.new())

	# Bottom button bar
	var button_bar := HBoxContainer.new()
	button_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	button_bar.add_theme_constant_override("separation", 16)
	root_vbox.add_child(button_bar)

	var btn_reset := _create_action_button("RESET TO DEFAULTS", COLOR_ACCENT_BACK)
	btn_reset.pressed.connect(_on_reset_pressed)
	button_bar.add_child(btn_reset)

	var btn_back := _create_action_button("BACK TO MENU", COLOR_ACCENT_AUDIO)
	btn_back.pressed.connect(_on_back_pressed)
	button_bar.add_child(btn_back)

func _build_section_scroll(tab_name: String, _accent: Color) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.custom_minimum_size = Vector2(740, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.08, 0.06, 0.6)
	style.set_corner_radius_all(4)
	scroll.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 10)
	inner_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(inner_vbox)

	scroll.set_meta("inner_vbox", inner_vbox)
	return scroll

func _get_inner_vbox(scroll: ScrollContainer) -> VBoxContainer:
	return scroll.get_meta("inner_vbox") as VBoxContainer

# ------------------------------------------------------------------------------
# GRAPHICS Section
# ------------------------------------------------------------------------------

func _populate_graphics_section() -> void:
	var vbox := _section_graphics

	# --- Quality Preset ---
	_add_section_header(vbox, "Quality Preset")
	_add_dropdown(vbox, "Preset", "graphics", "quality_preset",
		["Custom", "Low", "Medium", "High", "Ultra"], [0, 1, 2, 3, 4])

	# --- Display ---
	_add_section_header(vbox, "Display")
	_add_checkbox(vbox, "Fullscreen", "graphics", "fullscreen")
	_add_dropdown(vbox, "V-Sync", "graphics", "vsync",
		["Disabled", "Enabled"], [false, true])
	_add_slider(vbox, "Max FPS (0=Unlimited)", "graphics", "max_fps", 0, 240, 5, _format_fps)
	_add_slider(vbox, "Field of View", "graphics", "fov", 60.0, 110.0, 1.0, _format_fov)

	# --- Anti-Aliasing ---
	_add_section_header(vbox, "Anti-Aliasing")
	_add_dropdown(vbox, "MSAA", "graphics", "msaa",
		["Disabled", "2x", "4x", "8x"], [0, 2, 4, 8])
	_add_checkbox(vbox, "FXAA", "graphics", "fxaa")

	# --- Shadows & Lighting ---
	_add_section_header(vbox, "Shadows & Lighting")
	_add_dropdown(vbox, "Shadow Quality", "graphics", "shadow_quality",
		["Off", "Low", "Medium", "High", "Ultra"], [0, 1, 2, 3, 4])
	_add_dropdown(vbox, "Volumetric Fog", "graphics", "volumetric_fog",
		["Off", "Low", "Medium", "High"], [0, 1, 2, 3])
	_add_dropdown(vbox, "Reflections (SSR)", "graphics", "reflection_quality",
		["Off", "Low", "Medium", "High"], [0, 1, 2, 3])

	# --- Textures & Geometry ---
	_add_section_header(vbox, "Textures & Geometry")
	_add_dropdown(vbox, "Texture Quality", "graphics", "texture_quality",
		["Low", "Medium", "High", "Ultra"], [0, 1, 2, 3])
	_add_dropdown(vbox, "Anisotropic Filter", "graphics", "anisotropic_filter",
		["Off", "1x", "2x", "4x", "8x", "16x"], [0, 1, 2, 4, 8, 16])
	_add_checkbox(vbox, "Occlusion Culling", "graphics", "occlusion_culling")
	_add_slider(vbox, "LOD Bias", "graphics", "lod_bias", 0.5, 2.0, 0.1, _format_scale)

	# --- Resolution ---
	_add_section_header(vbox, "Resolution")
	_add_slider(vbox, "Render Scale", "graphics", "render_scale", 0.5, 1.5, 0.05, _format_scale)

	# --- Post-Processing ---
	_add_section_header(vbox, "Post-Processing")
	_add_checkbox(vbox, "Motion Blur", "graphics", "motion_blur")
	_add_checkbox(vbox, "Depth of Field", "graphics", "depth_of_field")
	_add_slider(vbox, "Bloom Intensity", "graphics", "bloom_intensity", 0.0, 2.0, 0.05, _format_scale)
	_add_slider(vbox, "Chromatic Aberration", "graphics", "chromatic_aberration", 0.0, 1.0, 0.05, _format_percent)
	_add_slider(vbox, "Film Grain", "graphics", "film_grain", 0.0, 1.0, 0.05, _format_percent)
	_add_slider(vbox, "Vignette", "graphics", "vignette", 0.0, 1.0, 0.05, _format_percent)

# ------------------------------------------------------------------------------
# AUDIO Section
# ------------------------------------------------------------------------------

func _populate_audio_section() -> void:
	var vbox := _section_audio

	_add_section_header(vbox, "Volume Levels")
	_add_slider(vbox, "Master Volume", "audio", "master_volume", 0.0, 1.0, 0.01, _format_percent)
	_add_slider(vbox, "Music Volume", "audio", "music_volume", 0.0, 1.0, 0.01, _format_percent)
	_add_slider(vbox, "SFX Volume", "audio", "sfx_volume", 0.0, 1.0, 0.01, _format_percent)
	_add_slider(vbox, "UI Volume", "audio", "ui_volume", 0.0, 1.0, 0.01, _format_percent)

	_add_section_header(vbox, "Effects")
	_add_slider(vbox, "Reverb Send", "audio", "reverb_send", 0.0, 1.0, 0.01, _format_percent)

	_add_section_header(vbox, "Subtitles & Captions")
	_add_checkbox(vbox, "Enable Subtitles", "audio", "subtitles_enabled")
	_add_slider(vbox, "Subtitle Background Opacity", "audio", "subtitle_bg_opacity", 0.0, 1.0, 0.05, _format_percent)

# ------------------------------------------------------------------------------
# GAMEPLAY Section
# ------------------------------------------------------------------------------

func _populate_gameplay_section() -> void:
	var vbox := _section_gameplay

	_add_section_header(vbox, "Difficulty")
	_add_dropdown(vbox, "Difficulty Mode", "gameplay", "difficulty",
		["Casual", "Normal", "Veteran", "Hardcore"], [0, 1, 2, 3])

	_add_section_header(vbox, "HUD & UI")
	_add_slider(vbox, "HUD Opacity", "gameplay", "hud_opacity", 0.3, 1.0, 0.05, _format_percent)
	_add_checkbox(vbox, "Show Minimap", "gameplay", "minimap_enabled")
	_add_checkbox(vbox, "Show Damage Numbers", "gameplay", "damage_numbers")
	_add_dropdown(vbox, "Crosshair Style", "gameplay", "crosshair_style",
		["Default", "Minimal", "Cross", "Circle"], [0, 1, 2, 3])
	_add_checkbox(vbox, "Show Debug Overlay (F3)", "gameplay", "show_debug_overlay")

	_add_section_header(vbox, "Flight & Combat")
	_add_slider(vbox, "Auto-Aim Assist", "gameplay", "auto_aim_assist", 0.0, 1.0, 0.05, _format_percent)
	_add_slider(vbox, "Camera Sensitivity", "gameplay", "camera_sensitivity", 0.1, 3.0, 0.1, _format_multiplier)
	_add_slider(vbox, "Flight Damping", "gameplay", "flight_damping", 0.0, 1.0, 0.05, _format_percent)

	_add_section_header(vbox, "Scanner & POI")
	_add_slider(vbox, "External POI Scan Radius (ly)", "gameplay", "poi_scan_radius_ly",
		10.0, 500.0, 5.0, _format_ly)
	_add_slider(vbox, "Max POI Indicators (0=Unlimited)", "gameplay", "poi_max_indicators",
		0.0, 200.0, 1.0, _format_int)

	_add_section_header(vbox, "Noise Map Overlay (F4)")
	_add_slider(vbox, "Overlay Opacity", "gameplay", "noise_overlay_opacity", 0.1, 1.0, 0.05, _format_percent)
	_add_checkbox(vbox, "Show Resources (Green)", "gameplay", "noise_show_resources")
	_add_checkbox(vbox, "Show Enemies (Red)", "gameplay", "noise_show_enemies")
	_add_checkbox(vbox, "Show Anomalies (Purple)", "gameplay", "noise_show_anomalies")
	_add_checkbox(vbox, "Show Hazards (Yellow)", "gameplay", "noise_show_hazards")

	_add_section_header(vbox, "Ship Scanner (Tab)")
	_add_slider(vbox, "Scanner Range (km)", "gameplay", "scanner_range_km", 1.0, 50.0, 0.5, _format_km)
	_add_slider(vbox, "Scanner Opacity", "gameplay", "scanner_opacity", 0.1, 1.0, 0.05, _format_percent)

# ------------------------------------------------------------------------------
# CONTROLS Section
# ------------------------------------------------------------------------------

func _populate_controls_section() -> void:
	var vbox := _section_controls

	_add_section_header(vbox, "Mouse & Keyboard")
	_add_checkbox(vbox, "Invert Y Axis", "controls", "invert_y")
	_add_slider(vbox, "Mouse Sensitivity", "controls", "mouse_sensitivity", 0.001, 0.01, 0.0005, _format_mouse_sens)

	_add_section_header(vbox, "Controller")
	_add_checkbox(vbox, "Enable Controller", "controls", "controller_enabled")
	_add_slider(vbox, "Controller Deadzone", "controls", "controller_deadzone", 0.0, 1.0, 0.05, _format_percent)
	_add_checkbox(vbox, "Vibration Enabled", "controls", "vibration_enabled")
	_add_slider(vbox, "Vibration Intensity", "controls", "vibration_intensity", 0.0, 1.0, 0.05, _format_percent)

# ------------------------------------------------------------------------------
# ACCESSIBILITY Section
# ------------------------------------------------------------------------------

func _populate_accessibility_section() -> void:
	var vbox := _section_accessibility

	_add_section_header(vbox, "Visual")
	_add_dropdown(vbox, "Color Blind Mode", "accessibility", "color_blind_mode",
		["None", "Protanopia", "Deuteranopia", "Tritanopia"], [0, 1, 2, 3])
	_add_checkbox(vbox, "High Contrast UI", "accessibility", "high_contrast")
	_add_slider(vbox, "UI Scale", "accessibility", "ui_scale", 0.75, 1.5, 0.05, _format_scale)
	_add_slider(vbox, "Text Size", "accessibility", "text_size", 0.8, 1.4, 0.05, _format_scale)

	_add_section_header(vbox, "Motion")
	_add_checkbox(vbox, "Reduce Motion", "accessibility", "reduce_motion")
	_add_slider(vbox, "Screen Shake Intensity", "accessibility", "screen_shake_intensity", 0.0, 1.0, 0.05, _format_percent)

# ------------------------------------------------------------------------------
# LANGUAGE Section (LocGuard Lite localization)
# ------------------------------------------------------------------------------

func _populate_language_section() -> void:
	var vbox := _section_language

	_add_section_header(vbox, "Interface Language")
	_add_language_dropdown(vbox)

	_add_section_header(vbox, "About")
	var info := Label.new()
	info.text = "Translations are validated by LocGuard Lite in the editor.\nMissing keys and empty translations are reported automatically."
	info.add_theme_color_override("font_color", COLOR_SUBTITLE)
	info.add_theme_font_size_override("font_size", 11)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(600, 0)
	vbox.add_child(info)

# ------------------------------------------------------------------------------
# DEBUG Section (Developer Tools — debug builds only)
# ------------------------------------------------------------------------------

func _populate_debug_section() -> void:
	var vbox := _section_debug

	# Warning banner
	var warning := Label.new()
	warning.text = "⚠ Developer tools — for testing only. Cheats and overlays may break gameplay balance."
	warning.add_theme_color_override("font_color", COLOR_ACCENT_DEBUG)
	warning.add_theme_font_size_override("font_size", 12)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(600, 0)
	vbox.add_child(warning)

	# --- Performance Overlays ---
	_add_section_header(vbox, "Performance Overlays")
	_add_checkbox(vbox, "Show FPS Counter", "debug", "show_fps_counter")
	_add_checkbox(vbox, "Show Frame Time (ms)", "debug", "show_frame_time")
	_add_checkbox(vbox, "Show Draw Calls", "debug", "show_draw_calls")

	# --- Collision & Physics Debug ---
	_add_section_header(vbox, "Collision & Physics")
	_add_checkbox(vbox, "Show Collision Shapes (F3)", "debug", "show_collision_shapes")
	_add_checkbox(vbox, "Show Physics Debug (Jolt)", "debug", "show_physics_debug")

	# --- Noise Map Overlay (F4) ---
	_add_section_header(vbox, "Noise Map Overlay (F4)")
	_add_checkbox(vbox, "Enable Noise Overlay", "debug", "noise_overlay_enabled")
	_add_slider(vbox, "Overlay Opacity", "debug", "noise_overlay_opacity", 0.1, 1.0, 0.05, _format_percent)
	_add_checkbox(vbox, "Show Resources (Green)", "debug", "noise_show_resources")
	_add_checkbox(vbox, "Show Enemies (Red)", "debug", "noise_show_enemies")
	_add_checkbox(vbox, "Show Anomalies (Purple)", "debug", "noise_show_anomalies")
	_add_checkbox(vbox, "Show Hazards (Yellow)", "debug", "noise_show_hazards")

	# --- Debug Panel (F12) ---
	_add_section_header(vbox, "Debug Panel (F12)")
	_add_checkbox(vbox, "Auto-show Debug Panel", "debug", "debug_panel_enabled")
	_add_slider(vbox, "Panel Update Rate (s)", "debug", "debug_panel_update_rate", 0.05, 1.0, 0.05, _format_seconds)

	# --- Telemetry Overlays ---
	_add_section_header(vbox, "Telemetry Overlays")
	_add_checkbox(vbox, "Show Organ Telemetry", "debug", "show_organ_telemetry")
	_add_checkbox(vbox, "Show Wave Engine State", "debug", "show_wave_engine_state")
	_add_checkbox(vbox, "Show Flight Debug (vel/accel/G)", "debug", "show_flight_debug")

	# --- Cheats / Developer Tools ---
	_add_section_header(vbox, "Cheats / Developer Tools")
	_add_checkbox(vbox, "God Mode (no hull damage)", "debug", "god_mode")
	_add_checkbox(vbox, "Infinite Fuel (no plasma drain)", "debug", "infinite_fuel")
	_add_checkbox(vbox, "Infinite Boost (no reserve drain)", "debug", "infinite_boost")

	# --- Event Progression ---
	_add_section_header(vbox, "Event Progression (Skip / Jump To)")
	_add_debug_button(vbox, "Skip Intro Cinematic", Color(0.3, 0.85, 1.0), _on_debug_skip_cinematic)
	_add_debug_button(vbox, "Skip Covenant Dialogue", Color(0.3, 0.85, 1.0), _on_debug_skip_dialogue)
	_add_debug_button(vbox, "Complete Covenant (Bond + Grant Ship)", Color(0.0, 1.0, 0.6), _on_debug_complete_covenant)
	_add_debug_button(vbox, "Complete 'Approach' Objective", Color(0.0, 0.9, 0.7), _on_debug_complete_approach)
	_add_debug_button(vbox, "Complete 'Dialogue' Objective", Color(0.0, 0.9, 0.7), _on_debug_complete_dialogue_obj)
	_add_debug_button(vbox, "Complete 'Bond' Objective", Color(0.0, 0.9, 0.7), _on_debug_complete_bond)
	_add_debug_button(vbox, "Complete 'First Flight' Objective", Color(0.0, 0.9, 0.7), _on_debug_complete_flight)
	_add_debug_button(vbox, "Complete Entire 'First Symbiosis' Quest", Color(0.0, 1.0, 0.6), _on_debug_complete_quest)
	_add_debug_button(vbox, "Reset Covenant + Quest State", Color(1.0, 0.5, 0.2), _on_debug_reset_progression)

	# --- Time Scale ---
	_add_section_header(vbox, "Time Scale (Slow-Mo / Fast-Forward)")
	_add_slider(vbox, "Time Scale (1.0 = real-time)", "debug", "time_scale", 0.1, 4.0, 0.1, _format_multiplier)

	# --- Logging ---
	_add_section_header(vbox, "Logging")
	_add_checkbox(vbox, "Verbose Logging", "debug", "verbose_logging")
	_add_dropdown(vbox, "Log Level", "debug", "log_level",
		["Errors Only", "Warnings", "Info", "Debug"], [0, 1, 2, 3])

func _add_language_dropdown(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = "Language"
	label.custom_minimum_size = Vector2(280, 0)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)

	var dropdown := OptionButton.new()
	dropdown.custom_minimum_size = Vector2(240, 32)
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dropdown)

	var settings_node := _get_settings_system()
	var supported: Array = []
	if settings_node and settings_node.has_method("get_supported_languages"):
		supported = settings_node.get_supported_languages()
	if supported.is_empty():
		supported = ["en", "es"]

	var current_code := "en"
	if settings_node and settings_node.has_method("get_language"):
		current_code = settings_node.get_language()

	var select_idx := 0
	for i in range(supported.size()):
		var code := String(supported[i])
		var display := code
		if settings_node and settings_node.has_method("get_language_display_name"):
			display = settings_node.get_language_display_name(code)
		dropdown.add_item(display, i)
		dropdown.set_item_metadata(i, code)
		if code == current_code:
			select_idx = i
	dropdown.select(select_idx)

	dropdown.item_selected.connect(func(idx: int):
		var code: String = String(dropdown.get_item_metadata(idx))
		if settings_node and settings_node.has_method("set_language"):
			settings_node.set_language(code)
		_play_ui_click(true)
	)

# ------------------------------------------------------------------------------
# UI Widget Factory
# ------------------------------------------------------------------------------

func _add_slider(parent: VBoxContainer, label_text: String, section: String, key: String,
		min_val: float, max_val: float, step: float, formatter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(280, 0)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(90, 0)
	value_label.add_theme_color_override("font_color", COLOR_VALUE)
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.custom_minimum_size = Vector2(240, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	# Load current value
	var current: float = float(_get_settings_value(section, key))
	slider.value = current
	value_label.text = formatter.call(current)

	slider.value_changed.connect(func(val: float):
		value_label.text = formatter.call(val)
		_set_settings_value(section, key, val)
		# Changing individual graphics settings switches to Custom preset
		if section == "graphics" and key != "quality_preset":
			_mark_preset_custom()
		_play_ui_click(false)
	)

func _add_checkbox(parent: VBoxContainer, label_text: String, section: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(280, 0)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)

	var checkbox := CheckBox.new()
	checkbox.custom_minimum_size = Vector2(32, 32)
	row.add_child(checkbox)

	# Load current value
	var current: bool = bool(_get_settings_value(section, key))
	checkbox.button_pressed = current

	checkbox.toggled.connect(func(pressed: bool):
		_set_settings_value(section, key, pressed)
		if section == "graphics":
			_mark_preset_custom()
		_play_ui_click(true)
	)

func _add_dropdown(parent: VBoxContainer, label_text: String, section: String, key: String,
		labels: Array, values: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(280, 0)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)

	var dropdown := OptionButton.new()
	dropdown.custom_minimum_size = Vector2(200, 32)
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dropdown)

	for i in range(labels.size()):
		dropdown.add_item(labels[i], i)

	# Load current value
	var current_val: Variant = _get_settings_value(section, key)
	for i in range(values.size()):
		if typeof(values[i]) == typeof(current_val) and values[i] == current_val:
			dropdown.select(i)
			break

	dropdown.item_selected.connect(func(idx: int):
		var val: Variant = values[idx]
		_set_settings_value(section, key, val)
		_play_ui_click(true)
	)

func _create_action_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 44)
	btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.95))
	btn.add_theme_color_override("font_hover_color", accent)
	btn.add_theme_font_size_override("font_size", 13)

	var style_norm := StyleBoxFlat.new()
	style_norm.bg_color = Color(0.04, 0.1, 0.08, 0.8)
	style_norm.border_color = accent * Color(1, 1, 1, 0.5)
	style_norm.set_border_width_all(1)
	style_norm.set_corner_radius_all(6)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.08, 0.22, 0.16, 0.95)
	style_hover.border_color = accent
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(6)

	btn.add_theme_stylebox_override("normal", style_norm)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	return btn

## Adds a full-width debug action button to a section. The callback is invoked
## when the button is pressed.
func _add_debug_button(parent: VBoxContainer, label_text: String, accent: Color, callback: Callable) -> void:
	var btn := _create_action_button(label_text, accent)
	btn.custom_minimum_size = Vector2(680, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	parent.add_child(btn)

# ------------------------------------------------------------------------------
# Event Progression Handlers
# ------------------------------------------------------------------------------

## Skip the intro cinematic if it is currently playing.
func _on_debug_skip_cinematic() -> void:
	_play_ui_click(true)
	var tree := get_tree()
	if not tree or not tree.root:
		return
	var cinematic: Node = tree.root.get_node_or_null("CinematicIntro/CinematicSequencer")
	if cinematic == null:
		# Try as a direct child of root
		cinematic = tree.root.get_node_or_null("CinematicSequencer")
	if cinematic and cinematic.has_method("stop_cinematic"):
		cinematic.stop_cinematic()
		print("[Debug] Skipped intro cinematic.")
	else:
		print("[Debug] No active cinematic found to skip.")

## Skip any active dialogue (covenant or otherwise).
func _on_debug_skip_dialogue() -> void:
	_play_ui_click(true)
	var tree := get_tree()
	if not tree or not tree.root:
		return
	# DialogueUI is a CanvasLayer — search the root for it.
	var dialogue: Node = null
	for child in tree.root.get_children():
		if child is DialogueUI:
			dialogue = child
			break
	if dialogue == null:
		# Search deeper
		var found: Array = tree.root.find_children("*", "DialogueUI", true, false)
		if found.size() > 0:
			dialogue = found[0]
	if dialogue and dialogue.has_method("hide_dialogue"):
		dialogue.hide_dialogue()
		print("[Debug] Skipped active dialogue.")
	else:
		print("[Debug] No active dialogue found to skip.")

## Complete the entire covenant flow: bond + grant ship + complete all objectives.
func _on_debug_complete_covenant() -> void:
	_play_ui_click(true)
	var tree := get_tree()
	if not tree or not tree.root:
		return
	# First skip any active dialogue
	_on_debug_skip_dialogue()
	# Complete all covenant objectives in sequence
	var quest_id := "first_symbiosis"
	var objectives := ["obj_approach_void_fauna", "obj_complete_covenant_dialogue",
		"obj_bond_with_void_fauna", "obj_take_first_flight"]
	if tree.root.has_node("QuestManager"):
		var qm: Node = tree.root.get_node("QuestManager")
		for obj_id in objectives:
			if qm.has_method("complete_objective"):
				qm.complete_objective(quest_id, obj_id)
	# Mark the covenant controller as bonded + ship granted
	var covenant: Node = tree.root.get_node_or_null("CovenantController")
	if covenant == null:
		# Search by group
		var arr := tree.get_nodes_in_group("covenant_controller")
		if arr.size() > 0:
			covenant = arr[0]
	if covenant:
		if "bond_accepted" in covenant:
			covenant.set("bond_accepted", true)
		if "_has_granted_ship" in covenant:
			covenant.set("_has_granted_ship", true)
		if "_flow_completed" in covenant:
			covenant.set("_flow_completed", true)
		if covenant.has_signal("covenant_bonded"):
			covenant.emit_signal("covenant_bonded")
		if covenant.has_signal("ship_granted"):
			covenant.emit_signal("ship_granted")
	# Mark the flight controller as bonded
	var fc: Node = null
	var fc_arr := tree.get_nodes_in_group("flight_controller")
	if fc_arr.size() > 0:
		fc = fc_arr[0]
	if fc and "is_bonded" in fc:
		fc.set("is_bonded", true)
	print("[Debug] Covenant completed — ship bonded and granted.")

## Complete a single objective by ID.
func _complete_objective_by_id(obj_id: String) -> void:
	var tree := get_tree()
	if not tree or not tree.root:
		return
	if tree.root.has_node("QuestManager"):
		var qm: Node = tree.root.get_node("QuestManager")
		if qm.has_method("complete_objective"):
			qm.complete_objective("first_symbiosis", obj_id)
			print("[Debug] Completed objective: %s" % obj_id)

func _on_debug_complete_approach() -> void:
	_play_ui_click(true)
	_complete_objective_by_id("obj_approach_void_fauna")

func _on_debug_complete_dialogue_obj() -> void:
	_play_ui_click(true)
	_on_debug_skip_dialogue()
	_complete_objective_by_id("obj_complete_covenant_dialogue")

func _on_debug_complete_bond() -> void:
	_play_ui_click(true)
	_complete_objective_by_id("obj_bond_with_void_fauna")
	# Also mark the ship as bonded
	var tree := get_tree()
	if tree:
		var fc_arr := tree.get_nodes_in_group("flight_controller")
		if fc_arr.size() > 0 and "is_bonded" in fc_arr[0]:
			fc_arr[0].set("is_bonded", true)

func _on_debug_complete_flight() -> void:
	_play_ui_click(true)
	_complete_objective_by_id("obj_take_first_flight")

## Complete the entire first_symbiosis quest by completing all objectives.
func _on_debug_complete_quest() -> void:
	_play_ui_click(true)
	_on_debug_skip_dialogue()
	var objectives := ["obj_approach_void_fauna", "obj_complete_covenant_dialogue",
		"obj_bond_with_void_fauna", "obj_take_first_flight"]
	for obj_id in objectives:
		_complete_objective_by_id(obj_id)
	# Mark covenant as fully completed
	var tree := get_tree()
	if tree:
		var covenant: Node = tree.root.get_node_or_null("CovenantController")
		if covenant == null:
			var arr := tree.get_nodes_in_group("covenant_controller")
			if arr.size() > 0:
				covenant = arr[0]
		if covenant:
			if "bond_accepted" in covenant:
				covenant.set("bond_accepted", true)
			if "_has_granted_ship" in covenant:
				covenant.set("_has_granted_ship", true)
			if "_flow_completed" in covenant:
				covenant.set("_flow_completed", true)
		var fc_arr := tree.get_nodes_in_group("flight_controller")
		if fc_arr.size() > 0 and "is_bonded" in fc_arr[0]:
			fc_arr[0].set("is_bonded", true)
	print("[Debug] Entire 'First Symbiosis' quest completed.")

## Reset all covenant and quest progression to the initial state.
func _on_debug_reset_progression() -> void:
	_play_ui_click(true)
	var tree := get_tree()
	if not tree or not tree.root:
		return
	# Reset covenant controller state
	var covenant: Node = tree.root.get_node_or_null("CovenantController")
	if covenant == null:
		var arr := tree.get_nodes_in_group("covenant_controller")
		if arr.size() > 0:
			covenant = arr[0]
	if covenant:
		if "bond_accepted" in covenant:
			covenant.set("bond_accepted", false)
		if "refused_count" in covenant:
			covenant.set("refused_count", 0)
		if "_has_granted_ship" in covenant:
			covenant.set("_has_granted_ship", false)
		if "_flow_completed" in covenant:
			covenant.set("_flow_completed", false)
	# Reset flight controller bonded state
	var fc_arr := tree.get_nodes_in_group("flight_controller")
	if fc_arr.size() > 0 and "is_bonded" in fc_arr[0]:
		fc_arr[0].set("is_bonded", false)
	# Clear quest save data
	if tree.root.has_node("SaveSystem"):
		var ss: Node = tree.root.get_node("SaveSystem")
		if "current_save_data" in ss:
			var data: Dictionary = ss.get("current_save_data")
			data.erase("covenant")
			data.erase("quest_weaver")
			ss.set("current_save_data", data)
		if ss.has_method("save_game"):
			ss.call("save_game")
	print("[Debug] Covenant + quest progression reset to initial state.")

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_color_override("font_color", COLOR_HEADER)
	header.add_theme_font_size_override("font_size", 14)
	parent.add_child(header)

# ------------------------------------------------------------------------------
# Preset Management
# ------------------------------------------------------------------------------

func _mark_preset_custom() -> void:
	# When a user changes an individual graphics setting, switch preset to Custom
	var settings_node := _get_settings_system()
	if settings_node and settings_node.has_method("set_setting"):
		# Avoid triggering _apply_quality_preset recursion
		settings_node.set_setting("graphics", "quality_preset", 0)

# ------------------------------------------------------------------------------
# Value Formatters
# ------------------------------------------------------------------------------

func _format_percent(val: float) -> String:
	return "%d%%" % int(val * 100.0)

func _format_scale(val: float) -> String:
	return "%.2fx" % val

func _format_fps(val: float) -> String:
	if val <= 0:
		return "Unlimited"
	return "%d FPS" % int(val)

func _format_fov(val: float) -> String:
	return "%d°" % int(val)

func _format_ly(val: float) -> String:
	return "%.0f ly" % val

func _format_int(val: float) -> String:
	if val <= 0:
		return "Unlimited"
	return "%d" % int(val)

func _format_multiplier(val: float) -> String:
	return "%.1fx" % val

func _format_mouse_sens(val: float) -> String:
	return "%.4f" % val

func _format_km(val: float) -> String:
	return "%.1f km" % val

func _format_seconds(val: float) -> String:
	return "%.2fs" % val

# ------------------------------------------------------------------------------
# Settings Bridge
# ------------------------------------------------------------------------------

func _get_settings_value(section: String, key: String) -> Variant:
	var settings_node := _get_settings_system()
	if settings_node and settings_node.has_method("get_setting"):
		return settings_node.get_setting(section, key)
	return null

func _set_settings_value(section: String, key: String, value: Variant) -> void:
	var settings_node := _get_settings_system()
	if settings_node and settings_node.has_method("set_setting"):
		settings_node.set_setting(section, key, value)

func _get_settings_system() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("SettingsSystem"):
		return ml.root.get_node("SettingsSystem")
	return null

# ------------------------------------------------------------------------------
# Button Handlers
# ------------------------------------------------------------------------------

func _on_reset_pressed() -> void:
	_play_ui_click(false)
	var settings_node := _get_settings_system()
	if settings_node and settings_node.has_method("reset_to_defaults"):
		settings_node.reset_to_defaults()
	# Rebuild UI to reflect defaults
	_build_settings_ui()

func _on_back_pressed() -> void:
	_play_ui_click(true)
	_change_scene("res://scenes/main_menu.tscn")

func _change_scene(path: String) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioDirector"):
		ml.root.get_node("BioAudioDirector").transition_to_scene(path)
	elif is_inside_tree() and get_tree():
		get_tree().change_scene_to_file(path)
	elif ml and ml.has_method("change_scene_to_file"):
		ml.call("change_scene_to_file", path)

func _play_ui_click(is_confirm: bool = true) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(is_confirm)

# ------------------------------------------------------------------------------
# Animated Background
# ------------------------------------------------------------------------------

func _draw() -> void:
	if size.x <= 10.0 or size.y <= 10.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG, true)

	# Subtle pulsing radial energy
	var center := size * 0.5
	for i in range(4):
		var ring_r: float = (200.0 + float(i) * 90.0 + sin(_animation_time * 1.5 + float(i)) * 15.0)
		var alpha: float = 0.06 - (float(i) * 0.012)
		draw_arc(center, ring_r, 0, PI * 2.0, 64, Color(0.0, 0.9, 0.7, alpha), 1.5)
