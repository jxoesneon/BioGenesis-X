# res://scripts/MainMenuUI.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# MainMenuUI.gd - Biopunk Title Screen & Primary Game Launch Navigation
# ==============================================================================
# Extends Control to render the BioGenesis-X main menu title screen.
# - Animated background bio-logo & pulsing radial particle energy.
# - Primary Navigation Buttons:
#   1. ENTER THE VOID (FLIGHT COMBAT)
#   2. GENETIC SHIP BUILDER
#   3. ORGAN SYSTEMS LAB
#   4. EXIT
# Communicates game mode state transitions with BioManager.gd.
# ==============================================================================

@tool
class_name MainMenuUI
extends Control

## Signal emitted when user selects "ENTER THE VOID (FLIGHT COMBAT)"
signal flight_combat_requested()
## Signal emitted when user selects "GENETIC SHIP BUILDER"
signal ship_builder_requested()
## Signal emitted when user selects "ORGAN SYSTEMS LAB"
signal organ_systems_requested()
## Signal emitted when user selects "EXIT"
signal exit_requested()

# Menu UI References
var menu_container: VBoxContainer
var btn_flight: Button
var btn_builder: Button
var btn_lab: Button
var btn_exit: Button

var lbl_version: Label
var _animation_time: float = 0.0
var _bio_manager_ref: Node = null

# Bioluminescent floating particles state
var _particle_positions: Array = []
var _particle_velocities: Array = []
var _particle_alphas: Array = []
const _PARTICLE_COUNT: int = 30

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_main_menu()
	_locate_bio_manager()
	_init_particles()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _exit_tree() -> void:
	if resized.is_connected(_on_resized):
		resized.disconnect(_on_resized)

func _on_resized() -> void:
	queue_redraw()

func _locate_bio_manager() -> void:
	if not _bio_manager_ref:
		_bio_manager_ref = get_tree().root.get_node("BioManager")

func _init_particles() -> void:
	_particle_positions.clear()
	_particle_velocities.clear()
	_particle_alphas.clear()
	for i in range(_PARTICLE_COUNT):
		_particle_positions.append(Vector2(randf() * 800.0, randf() * 600.0))
		_particle_velocities.append(Vector2(randf() * 0.4 - 0.2, -(randf() * 0.5 + 0.15)))
		_particle_alphas.append(randf() * 0.5 + 0.2)

func _process(delta: float) -> void:
	_animation_time += delta
	# Update bioluminescent particles
	for i in range(_particle_positions.size()):
		_particle_positions[i] += _particle_velocities[i] * delta * 60.0
		_particle_alphas[i] -= delta * 0.04
		if _particle_positions[i].y < -10.0 or _particle_alphas[i] <= 0.0:
			_particle_positions[i] = Vector2(randf() * size.x, size.y + randf() * 20.0)
			_particle_velocities[i] = Vector2(randf() * 0.4 - 0.2, -(randf() * 0.5 + 0.15))
			_particle_alphas[i] = randf() * 0.5 + 0.2
	queue_redraw()

# ------------------------------------------------------------------------------
# UI Layout Construction
# ------------------------------------------------------------------------------

func _build_main_menu() -> void:
	for child in get_children():
		child.queue_free()

	# Full-screen Center Container for perfect alignment
	var center_container := CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center_container)

	# Main Centered Glass Card Panel
	var center_panel := PanelContainer.new()
	center_panel.custom_minimum_size = Vector2(440, 480)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.04, 0.90)
	style.border_color = Color(0.0, 0.9, 0.7, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_expand_margin_all(12)
	center_panel.add_theme_stylebox_override("panel", style)
	center_container.add_child(center_panel)

	menu_container = VBoxContainer.new()
	menu_container.add_theme_constant_override("separation", 18)
	menu_container.alignment = BoxContainer.ALIGNMENT_CENTER
	center_panel.add_child(menu_container)

	# Main Game Title Header
	var lbl_title := Label.new()
	lbl_title.text = "BIOGENESIS-X"
	lbl_title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.75))
	lbl_title.add_theme_font_size_override("font_size", 32)
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_container.add_child(lbl_title)

	var lbl_subtitle := Label.new()
	lbl_subtitle.text = "LIVING STARSHIP SIMULATION ENGINE"
	lbl_subtitle.add_theme_color_override("font_color", Color(0.0, 0.75, 0.6))
	lbl_subtitle.add_theme_font_size_override("font_size", 11)
	lbl_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_container.add_child(lbl_subtitle)

	menu_container.add_child(HSeparator.new())

	# 1. ENTER THE VOID (FLIGHT COMBAT)
	btn_flight = _create_menu_button("ENTER THE VOID (FLIGHT COMBAT)", Color(0.0, 0.9, 1.0))
	btn_flight.pressed.connect(_on_flight_pressed)
	menu_container.add_child(btn_flight)

	# 2. GENETIC SHIP BUILDER
	btn_builder = _create_menu_button("GENETIC SHIP BUILDER", Color(0.0, 1.0, 0.6))
	btn_builder.pressed.connect(_on_builder_pressed)
	menu_container.add_child(btn_builder)

	# 3. ORGAN SYSTEMS LAB
	btn_lab = _create_menu_button("ORGAN SYSTEMS LAB", Color(0.8, 0.4, 1.0))
	btn_lab.pressed.connect(_on_lab_pressed)
	menu_container.add_child(btn_lab)

	# 4. WATCH CINEMATIC INTRO
	var btn_cinematic := _create_menu_button("WATCH CINEMATIC INTRO", Color(1.0, 0.8, 0.2))
	btn_cinematic.pressed.connect(_on_cinematic_pressed)
	menu_container.add_child(btn_cinematic)

	# 5. SETTINGS
	var btn_settings := _create_menu_button(tr("SETTINGS"), Color(0.6, 0.8, 1.0))
	btn_settings.pressed.connect(_on_settings_pressed)
	menu_container.add_child(btn_settings)

	# 6. EXIT
	btn_exit = _create_menu_button(tr("QUIT"), Color(1.0, 0.3, 0.3))
	btn_exit.pressed.connect(_on_exit_pressed)
	menu_container.add_child(btn_exit)

	menu_container.add_child(HSeparator.new())

	# Version & Engine Credits Footer
	lbl_version = Label.new()
	lbl_version.text = "v2.0.0-PROD | PUMILIO STUDIOS | GODOT 4.7"
	lbl_version.add_theme_color_override("font_color", Color(0.0, 0.6, 0.5, 0.8))
	lbl_version.add_theme_font_size_override("font_size", 10)
	lbl_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_container.add_child(lbl_version)

func _create_menu_button(text: String, accent_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(360, 48)
	btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.95))
	btn.add_theme_color_override("font_hover_color", accent_color)
	btn.add_theme_font_size_override("font_size", 13)

	var style_norm := StyleBoxFlat.new()
	style_norm.bg_color = Color(0.04, 0.1, 0.08, 0.8)
	style_norm.border_color = accent_color * Color(1, 1, 1, 0.5)
	style_norm.set_border_width_all(1)
	style_norm.set_corner_radius_all(6)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.08, 0.22, 0.16, 0.95)
	style_hover.border_color = accent_color
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(6)

	btn.add_theme_stylebox_override("normal", style_norm)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)

	return btn

# ------------------------------------------------------------------------------
# Button Signal Handlers
# ------------------------------------------------------------------------------

func _change_scene(path: String) -> void:
	# Route through LoadingScreenManager for scenes that need procedural generation time
	# (space_flight, galaxy_map). For simpler scenes, use BioAudioDirector's crossfade.
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree) or not ml.root:
		return

	var scene_name: String = path.get_file().get_basename()

	# Use LoadingScreenManager for heavy procedural scenes
	if ml.root.has_node("LoadingScreenManager") and scene_name in ["space_flight", "galaxy_map"]:
		ml.root.get_node("LoadingScreenManager").transition_to_scene(path)
	# Use BioAudioDirector for simpler scene transitions (settings, ship_builder, etc.)
	elif ml.root.has_node("BioAudioDirector"):
		ml.root.get_node("BioAudioDirector").transition_to_scene(path)
	else:
		if is_inside_tree() and get_tree():
			get_tree().change_scene_to_file(path)
		elif ml and ml.has_method("change_scene_to_file"):
			ml.call("change_scene_to_file", path)

func _play_ui_click(is_confirm: bool = true) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(is_confirm)

func _on_flight_pressed() -> void:
	_play_ui_click(true)
	if not _bio_manager_ref or not is_instance_valid(_bio_manager_ref):
		_locate_bio_manager()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		_bio_manager_ref.set_game_mode(1) # FLIGHT_MODE
	flight_combat_requested.emit()
	_change_scene("res://scenes/space_flight.tscn")

func _on_builder_pressed() -> void:
	_play_ui_click(true)
	if not _bio_manager_ref or not is_instance_valid(_bio_manager_ref):
		_locate_bio_manager()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		_bio_manager_ref.set_game_mode(0) # BUILDER_MODE
	ship_builder_requested.emit()
	_change_scene("res://scenes/ship_builder.tscn")

func _on_lab_pressed() -> void:
	_play_ui_click(true)
	if not _bio_manager_ref or not is_instance_valid(_bio_manager_ref):
		_locate_bio_manager()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		_bio_manager_ref.set_game_mode(2) # INSPECTOR_MODE
	organ_systems_requested.emit()
	_change_scene("res://scenes/organ_inspector.tscn")

func _on_cinematic_pressed() -> void:
	_play_ui_click(true)
	_change_scene("res://scenes/cinematic_intro.tscn")

func _on_settings_pressed() -> void:
	_play_ui_click(true)
	_change_scene("res://scenes/settings.tscn")

func _on_exit_pressed() -> void:
	_play_ui_click(false)
	exit_requested.emit()
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		(main_loop as SceneTree).quit()

# ------------------------------------------------------------------------------
# Animated Background & Biopunk Logo Drawing
# ------------------------------------------------------------------------------

func _draw() -> void:
	if size.x <= 10.0 or size.y <= 10.0:
		return

	var center := size * 0.5
	var ui_scale: float = clampf(size.y / 1080.0, 0.65, 2.5)
	var base_cyan := Color(0.0, 1.0, 0.75, 0.15)
	var glow_green := Color(0.0, 1.0, 0.4, 0.25)

	# 0. Solid Deep Biopunk Background Fill
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.035, 0.03, 1.0), true)

	# 1. Pulsing Background Radial Energy Rings
	for i in range(5):
		var ring_r: float = (140.0 + float(i) * 70.0 + sin(_animation_time * 1.8 + float(i) * 0.8) * 18.0) * ui_scale
		var alpha: float = 0.10 - (float(i) * 0.018)
		draw_arc(center, ring_r, 0, PI * 2.0, 64, Color(0.0, 0.9, 0.7, alpha), maxf(1.0, 1.5 * ui_scale))

	# 2. Rotating Organic Tentacle / Spine Rays behind Logo
	var num_rays := 16
	var ray_r_inner: float = 80.0 * ui_scale
	var ray_r_outer: float = 320.0 * ui_scale
	for i in range(num_rays):
		var angle := (float(i) / float(num_rays)) * PI * 2.0 + (_animation_time * 0.25)
		var p1 := center + Vector2(cos(angle), sin(angle)) * ray_r_inner
		var p2 := center + Vector2(cos(angle + 0.15), sin(angle + 0.15)) * ray_r_outer
		draw_line(p1, p2, Color(0.0, 0.8, 0.55, 0.06), maxf(1.0, 2.0 * ui_scale))

	# 3. Central Pulsing Organic Core Motif
	var orb_r := (50.0 + sin(_animation_time * 2.5) * 5.0) * ui_scale
	draw_circle(center, orb_r, base_cyan)
	draw_arc(center, orb_r + 6.0 * ui_scale, 0, PI * 2.0, 48, glow_green, maxf(1.0, 2.0 * ui_scale))

	# 4. Floating Bioluminescent Particle Dots
	for i in range(_particle_positions.size()):
		var p_pos: Vector2 = _particle_positions[i]
		var p_alpha: float = _particle_alphas[i]
		var flicker: float = 0.6 + sin(_animation_time * 3.0 + float(i) * 1.7) * 0.4
		var dot_alpha: float = p_alpha * flicker
		draw_circle(p_pos, 4.5 * ui_scale, Color(0.0, 1.0, 0.6, dot_alpha * 0.2))
		draw_circle(p_pos, 1.8 * ui_scale, Color(0.4, 1.0, 0.85, dot_alpha * 0.75))

	# 5. Pulsing DNA Double-Helix Spiral around Central Orb
	var helix_r: float = orb_r + 22.0 * ui_scale
	var helix_points_a: int = 48
	for i in range(helix_points_a):
		var t: float = float(i) / float(helix_points_a)
		var helix_angle: float = t * PI * 4.0 + _animation_time * 1.0
		var strand_r: float = helix_r + sin(helix_angle) * (14.0 * ui_scale)
		var pos_a := center + Vector2(cos(helix_angle), sin(helix_angle)) * strand_r
		var pos_b := center + Vector2(cos(helix_angle + PI), sin(helix_angle + PI)) * strand_r
		var strand_alpha: float = (0.3 + sin(t * PI) * 0.35) * 0.7
		draw_circle(pos_a, 2.0 * ui_scale, Color(0.0, 1.0, 0.8, strand_alpha))
		draw_circle(pos_b, 2.0 * ui_scale, Color(0.2, 0.8, 1.0, strand_alpha))
		if i % 6 == 0:
			draw_line(pos_a, pos_b, Color(0.0, 0.9, 0.7, strand_alpha * 0.4), maxf(1.0, 1.0 * ui_scale))
