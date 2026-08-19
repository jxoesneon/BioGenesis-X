# res://scripts/ShipBuilderUI.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# ShipBuilderUI.gd - 3D Biopunk Genetic Ship Synthesis & Builder Studio UI
# ==============================================================================
# Extends Control to provide a 3D Biopunk Ship Builder interface.
# - Sidebar Panel: Archetype Selector OptionButton.
# - Sliders: Body Segments, Ship Length, Chitin Density, Armor Thickness, Eye Pod Count, Glow Color.
# - Action Buttons: Randomize Genetics, Export 3D Model (.OBJ), Test Flight in Void, Inspect Organ Systems.
# Synchronizes parameters in real-time with BioManager.gd.
# ==============================================================================

@tool
class_name ShipBuilderUI
extends Control

## Signal emitted when user clicks "Test Flight in Void"
signal test_flight_requested()
## Signal emitted when user clicks "Inspect Organ Systems"
signal inspect_organs_requested()
## Signal emitted when user exports ship 3D model (.OBJ)
signal export_obj_requested(file_path: String)
## Signal emitted when genetic seed is randomized
signal genetics_randomized(seed_value: int)

# UI Control References
var sidebar_panel: PanelContainer
var archetype_option: OptionButton

var slider_segments: HSlider
var lbl_segments_val: Label

var slider_length: HSlider
var lbl_length_val: Label

var slider_chitin: HSlider
var lbl_chitin_val: Label

var slider_armor: HSlider
var lbl_armor_val: Label

var slider_eyepods: HSlider
var lbl_eyepods_val: Label

var color_picker_btn: ColorPickerButton

var btn_randomize: Button
var btn_export_obj: Button
var btn_test_flight: Button
var btn_inspect_organs: Button

var lbl_status_msg: Label
var lbl_mesh_stats: Label
var btn_back_main_menu: Button
var _bio_manager_ref: Node = null
var _animation_time: float = 0.0
## Bio-scan hologram overlay mesh (shares the procedural bio-mesh geometry).
var _hologram_overlay: MeshInstance3D = null
## ShaderMaterial for the bio-scan hologram overlay (bio_scan_hologram shader).
var _hologram_mat: ShaderMaterial = null

# 3D Turntable Orbit & Camera Controls
@export var camera_pivot_node: Node3D = null
@export var turntable_camera_node: Camera3D = null
@export var procedural_mesh_node: ProceduralBioMesh = null
var is_dragging_orbit: bool = false
var orbit_yaw: float = -0.65 ## Top-right starboard quarter perspective
var orbit_pitch: float = -0.45 ## Elevated top-down pitch looking down at the starship
var orbit_distance: float = 34.0 ## Default 34m distance frames 14m-35m starships with cinematic margins
var auto_rotate_speed: float = 0.18
var idle_timeout_seconds: float = 120.0 ## 2 minutes (120 seconds) of inactivity before auto-rotation starts
var idle_interaction_timer: float = 0.0

func _reset_idle_timer() -> void:
	idle_interaction_timer = 0.0

func inject_dependencies(camera_pivot: Node3D = null, turntable_cam: Camera3D = null, bio_mesh: ProceduralBioMesh = null) -> void:
	if camera_pivot != null:
		camera_pivot_node = camera_pivot
	if turntable_cam != null:
		turntable_camera_node = turntable_cam
	if bio_mesh != null:
		procedural_mesh_node = bio_mesh

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_builder_interface()
	_locate_bio_manager()
	_find_camera_nodes()
	_find_mesh_node()
	_load_initial_values()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _find_camera_nodes() -> void:
	var parent := get_parent()
	if camera_pivot_node == null and parent:
		camera_pivot_node = parent.get_node_or_null("CameraPivot")
	if camera_pivot_node and turntable_camera_node == null:
		turntable_camera_node = camera_pivot_node.get_node_or_null("TurntableCamera")
	if turntable_camera_node:
		var dist := turntable_camera_node.position.length()
		if dist >= 10.0:
			orbit_distance = dist
		else:
			orbit_distance = 34.0

func _on_resized() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	_animation_time += delta
	_update_mesh_stats()
	_update_camera_orbit(delta)
	queue_redraw()

func _update_camera_orbit(delta: float) -> void:
	if not camera_pivot_node or not is_instance_valid(camera_pivot_node):
		_find_camera_nodes()
		if not camera_pivot_node: return

	# 1. Dynamically lock camera pivot to the exact 3D geometric center of the ship
	if not procedural_mesh_node:
		_find_mesh_node()
	
	var ship_target_center := Vector3.ZERO
	if procedural_mesh_node and is_instance_valid(procedural_mesh_node):
		if procedural_mesh_node.has_method("get_ship_geometric_center"):
			ship_target_center = procedural_mesh_node.position + procedural_mesh_node.get_ship_geometric_center()
		else:
			ship_target_center = procedural_mesh_node.position
	
	camera_pivot_node.position = camera_pivot_node.position.lerp(ship_target_center, delta * 12.0)

	# 2. Inactivity Auto-rotation check
	if not is_dragging_orbit:
		idle_interaction_timer += delta
		if idle_interaction_timer >= idle_timeout_seconds:
			orbit_yaw += auto_rotate_speed * delta

	# 3. Apply orbit rotation around ship center
	camera_pivot_node.rotation = Vector3(orbit_pitch, orbit_yaw, 0.0)
	if turntable_camera_node and is_instance_valid(turntable_camera_node):
		var target_pos := Vector3(0.0, 0.0, orbit_distance)
		turntable_camera_node.position = turntable_camera_node.position.lerp(target_pos, delta * 8.0)
		turntable_camera_node.rotation = Vector3.ZERO

func _update_mesh_stats() -> void:
	# Keep the bio-scan hologram overlay in sync with the procedural mesh after
	# rebuilds (the bio-mesh swaps its ArrayMesh on every rebuild_ship_mesh).
	_sync_hologram_overlay()
	if not lbl_mesh_stats:
		return
	var verts: int = 0
	var faces: int = 0
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		if "mesh_vertex_count" in _bio_manager_ref:
			verts = _bio_manager_ref.mesh_vertex_count
		if "mesh_face_count" in _bio_manager_ref:
			faces = _bio_manager_ref.mesh_face_count
	# Estimate from UI parameters if BioManager doesn't expose mesh data
	if verts == 0 and slider_segments and slider_length:
		var segs: int = int(slider_segments.value)
		var rings: int = 8
		verts = segs * rings * 2
		faces = segs * rings * 2
	lbl_mesh_stats.text = "MESH: %d VERTS | %d FACES" % [verts, faces]

func _locate_bio_manager() -> void:
	_bio_manager_ref = get_tree().root.get_node("BioManager")

	if _bio_manager_ref and _bio_manager_ref.has_signal("ship_configuration_changed"):
		if not _bio_manager_ref.is_connected("ship_configuration_changed", Callable(self, "_on_ship_config_changed")):
			_bio_manager_ref.connect("ship_configuration_changed", Callable(self, "_on_ship_config_changed"))

func _exit_tree() -> void:
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		if _bio_manager_ref.is_connected("ship_configuration_changed", Callable(self, "_on_ship_config_changed")):
			_bio_manager_ref.disconnect("ship_configuration_changed", Callable(self, "_on_ship_config_changed"))
	# Free the hologram overlay we parented to the scene root (not our child).
	# Deferred so it's safe during scene teardown (overlay's parent may already
	# be mid-free when our _exit_tree runs).
	if _hologram_overlay and is_instance_valid(_hologram_overlay) and not _hologram_overlay.is_queued_for_deletion():
		_hologram_overlay.call_deferred("queue_free")
	_hologram_overlay = null

func _load_initial_values() -> void:
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		var config: Dictionary = _bio_manager_ref.call("get_ship_config")
		_apply_config_to_ui(config)

func _apply_config_to_ui(config: Dictionary) -> void:
	if archetype_option and config.has("archetype_name"):
		var archetype_keys := [
			"Apex Hive Leviathan",
			"Neuro-Spore Interceptor",
			"Chitinous Void Harvester",
			"Abyssal Symbiont Frigate",
			"Viral Colony Carrier"
		]
		var idx := archetype_keys.find(config["archetype_name"])
		if idx >= 0 and idx < archetype_option.item_count:
			archetype_option.select(idx)

	if config.has("segment_count") and slider_segments and lbl_segments_val:
		var clamped_v := clampf(float(config["segment_count"]), slider_segments.min_value, slider_segments.max_value)
		slider_segments.set_value_no_signal(clamped_v)
		lbl_segments_val.text = str(int(clamped_v))

	if config.has("length") and slider_length and lbl_length_val:
		var clamped_v := clampf(float(config["length"]), slider_length.min_value, slider_length.max_value)
		slider_length.set_value_no_signal(clamped_v)
		lbl_length_val.text = "%.1fm" % clamped_v

	if config.has("chitin_density") and slider_chitin and lbl_chitin_val:
		var raw_v := float(config["chitin_density"]) * 10.0
		var clamped_v := clampf(raw_v, slider_chitin.min_value, slider_chitin.max_value)
		slider_chitin.set_value_no_signal(clamped_v)
		lbl_chitin_val.text = "%.1f" % clamped_v

	if config.has("armor_thickness") and slider_armor and lbl_armor_val:
		var clamped_v := clampf(float(config["armor_thickness"]), slider_armor.min_value, slider_armor.max_value)
		slider_armor.set_value_no_signal(clamped_v)
		lbl_armor_val.text = "%.1f" % clamped_v

	if config.has("eye_pod_count") and slider_eyepods and lbl_eyepods_val:
		var clamped_v := clampf(float(config["eye_pod_count"]), slider_eyepods.min_value, slider_eyepods.max_value)
		slider_eyepods.set_value_no_signal(clamped_v)
		lbl_eyepods_val.text = str(int(clamped_v))

# ------------------------------------------------------------------------------
# Interface Layout & Construction
# ------------------------------------------------------------------------------

func _build_builder_interface() -> void:
	for child in get_children():
		child.queue_free()

	# Create Left Sidebar Glass Panel
	sidebar_panel = PanelContainer.new()
	sidebar_panel.set_anchors_and_offsets_preset(PRESET_LEFT_WIDE)
	sidebar_panel.grow_horizontal = Control.GROW_DIRECTION_END
	sidebar_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	sidebar_panel.offset_top = 20
	sidebar_panel.offset_bottom = -20
	sidebar_panel.offset_left = 20
	sidebar_panel.offset_right = 400
	sidebar_panel.custom_minimum_size = Vector2(380, 0)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.04, 0.90)
	style.border_color = Color(0.0, 0.8, 0.6, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_expand_margin_all(8)
	sidebar_panel.add_theme_stylebox_override("panel", style)
	add_child(sidebar_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sidebar_panel.add_child(scroll)

	var main_vb := VBoxContainer.new()
	main_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vb.add_theme_constant_override("separation", 14)
	scroll.add_child(main_vb)

	# Return to Main Menu Navigation Button
	btn_back_main_menu = _create_styled_button("◀ RETURN TO MAIN MENU", Color(0.2, 0.85, 1.0))
	btn_back_main_menu.pressed.connect(_on_back_to_main_menu_pressed)
	main_vb.add_child(btn_back_main_menu)

	# Studio Header Title
	var lbl_title := Label.new()
	lbl_title.text = "GENETIC SHIP BUILDER"
	lbl_title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.75))
	lbl_title.add_theme_font_size_override("font_size", 18)
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vb.add_child(lbl_title)

	var separator := HSeparator.new()
	main_vb.add_child(separator)

	# 1. Archetype Selector OptionButton
	var lbl_arch := Label.new()
	lbl_arch.text = "ORGANISM ARCHETYPE"
	lbl_arch.add_theme_color_override("font_color", Color(0.0, 0.8, 0.9))
	lbl_arch.add_theme_font_size_override("font_size", 12)
	main_vb.add_child(lbl_arch)

	archetype_option = OptionButton.new()
	archetype_option.custom_minimum_size.y = 32
	archetype_option.add_item("Apex Hive Leviathan", 0)
	archetype_option.add_item("Neuro-Spore Interceptor", 1)
	archetype_option.add_item("Chitinous Void Harvester", 2)
	archetype_option.add_item("Abyssal Symbiont Frigate", 3)
	archetype_option.add_item("Viral Colony Carrier", 4)
	archetype_option.item_selected.connect(_on_archetype_selected)
	main_vb.add_child(archetype_option)

	# 2. Sliders Section
	var res1 := _create_slider_row(main_vb, "BODY SEGMENTS (4-20)", 4, 20, 1, 16, _on_segments_changed)
	slider_segments = res1[0]
	lbl_segments_val = res1[1]

	var res2 := _create_slider_row(main_vb, "SHIP LENGTH (5-50m)", 5, 50, 0.5, 28, _on_length_changed)
	slider_length = res2[0]
	lbl_length_val = res2[1]

	var res3 := _create_slider_row(main_vb, "CHITIN PLATE DENSITY (1-10)", 1, 10, 0.5, 9.5, _on_chitin_changed)
	slider_chitin = res3[0]
	lbl_chitin_val = res3[1]

	var res4 := _create_slider_row(main_vb, "ARMOR THICKNESS (1-5)", 1, 5, 0.1, 4.5, _on_armor_changed)
	slider_armor = res4[0]
	lbl_armor_val = res4[1]

	var res5 := _create_slider_row(main_vb, "EYE POD COUNT (2-12)", 2, 12, 1, 8, _on_eyepods_changed)
	slider_eyepods = res5[0]
	lbl_eyepods_val = res5[1]

	# Bioluminescent Glow ColorPickerButton
	var glow_hb := HBoxContainer.new()
	var lbl_glow := Label.new()
	lbl_glow.text = "BIOLUMINESCENT GLOW"
	lbl_glow.add_theme_color_override("font_color", Color(0.0, 0.8, 0.9))
	lbl_glow.add_theme_font_size_override("font_size", 12)
	lbl_glow.size_flags_horizontal = SIZE_EXPAND_FILL

	color_picker_btn = ColorPickerButton.new()
	color_picker_btn.custom_minimum_size = Vector2(60, 26)
	color_picker_btn.color = Color(0.0, 1.0, 0.75, 1.0)
	color_picker_btn.color_changed.connect(_on_glow_color_changed)

	glow_hb.add_child(lbl_glow)
	glow_hb.add_child(color_picker_btn)
	main_vb.add_child(glow_hb)

	var separator2 := HSeparator.new()
	main_vb.add_child(separator2)

	# 3. Action Buttons Section
	btn_randomize = _create_styled_button("RANDOMIZE GENETICS", Color(0.0, 0.9, 0.7))
	btn_randomize.pressed.connect(_on_randomize_pressed)
	main_vb.add_child(btn_randomize)

	btn_export_obj = _create_styled_button("EXPORT 3D MODEL (.OBJ)", Color(0.8, 0.9, 0.2))
	btn_export_obj.pressed.connect(_on_export_obj_pressed)
	main_vb.add_child(btn_export_obj)

	btn_test_flight = _create_styled_button("TEST FLIGHT IN VOID", Color(0.0, 0.8, 1.0))
	btn_test_flight.pressed.connect(_on_test_flight_pressed)
	main_vb.add_child(btn_test_flight)

	btn_inspect_organs = _create_styled_button("INSPECT ORGAN SYSTEMS", Color(0.9, 0.4, 1.0))
	btn_inspect_organs.pressed.connect(_on_inspect_organs_pressed)
	main_vb.add_child(btn_inspect_organs)

	# Status Label
	lbl_status_msg = Label.new()
	lbl_status_msg.text = "GENETIC SHIP CONFIGURATION ACTIVE"
	lbl_status_msg.add_theme_color_override("font_color", Color(0.0, 0.7, 0.5))
	lbl_status_msg.add_theme_font_size_override("font_size", 10)
	lbl_status_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vb.add_child(lbl_status_msg)

	# Live Mesh Statistics Readout Label
	lbl_mesh_stats = Label.new()
	lbl_mesh_stats.text = "MESH: 0 VERTS | 0 FACES"
	lbl_mesh_stats.add_theme_color_override("font_color", Color(0.0, 0.85, 0.65, 0.75))
	lbl_mesh_stats.add_theme_font_size_override("font_size", 10)
	lbl_mesh_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vb.add_child(lbl_mesh_stats)

func _create_slider_row(parent: Node, label_title: String, min_v: float, max_v: float, step_v: float, default_v: float, callback: Callable) -> Array:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)

	var hb := HBoxContainer.new()
	var lbl_title := Label.new()
	lbl_title.text = label_title
	lbl_title.add_theme_color_override("font_color", Color(0.0, 0.85, 0.8))
	lbl_title.add_theme_font_size_override("font_size", 11)
	lbl_title.size_flags_horizontal = SIZE_EXPAND_FILL

	var lbl_val := Label.new()
	lbl_val.text = str(default_v)
	lbl_val.add_theme_color_override("font_color", Color(0.0, 1.0, 0.6))
	lbl_val.add_theme_font_size_override("font_size", 11)

	hb.add_child(lbl_title)
	hb.add_child(lbl_val)
	vb.add_child(hb)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = default_v
	slider.value_changed.connect(callback)
	vb.add_child(slider)

	parent.add_child(vb)
	return [slider, lbl_val]

func _create_styled_button(text: String, accent_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size.y = 44
	btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.95))
	btn.add_theme_color_override("font_hover_color", accent_color)
	
	var style_norm := StyleBoxFlat.new()
	style_norm.bg_color = Color(0.04, 0.1, 0.08, 0.8)
	style_norm.border_color = accent_color * Color(1, 1, 1, 0.6)
	style_norm.set_border_width_all(1)
	style_norm.set_corner_radius_all(4)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.08, 0.18, 0.14, 0.95)
	style_hover.border_color = accent_color
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(4)

	btn.add_theme_stylebox_override("normal", style_norm)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)

	return btn

# ------------------------------------------------------------------------------
# Event Handlers & Callbacks
# ------------------------------------------------------------------------------



func _find_mesh_node() -> void:
	var parent := get_parent()
	if parent:
		procedural_mesh_node = parent.get_node_or_null("ProceduralBioMesh")
	# Once the bio-mesh is located, attach the bio-scan hologram overlay so the
	# builder preview reads as a diagnostic scan of the specimen.
	if procedural_mesh_node and is_instance_valid(procedural_mesh_node) and _hologram_overlay == null:
		_setup_hologram_overlay()

## Builds the bio-scan hologram overlay mesh that shares the procedural bio-mesh
## geometry and renders an additive scan-line + wireframe grid shell on top of
## it. Null-safe: no-ops if the bio_scan_hologram shader isn't registered.
func _setup_hologram_overlay() -> void:
	if procedural_mesh_node == null or not is_instance_valid(procedural_mesh_node):
		return
	var shader: Shader = ShaderRegistry.get_shader(ShaderRegistry.ID_SCAN_HOLOGRAM)
	if shader == null:
		return
	var parent: Node = procedural_mesh_node.get_parent()
	if parent == null:
		return
	_hologram_overlay = MeshInstance3D.new()
	_hologram_overlay.name = "BioScanHologramOverlay"
	# Share the procedural mesh geometry so the overlay always matches the hull.
	_hologram_overlay.mesh = procedural_mesh_node.mesh
	_hologram_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Inherit the same world transform as the bio-mesh (sibling, same position).
	_hologram_overlay.transform = procedural_mesh_node.transform
	_hologram_mat = ShaderMaterial.new()
	_hologram_mat.shader = shader
	_hologram_mat.set_shader_parameter("scan_speed", 1.2)
	_hologram_mat.set_shader_parameter("scan_width", 0.06)
	_hologram_mat.set_shader_parameter("scan_axis", 2.0) # Sweep along Z (ship length)
	_hologram_mat.set_shader_parameter("flicker_amount", 0.12)
	_hologram_mat.set_shader_parameter("grid_scale", 34.0)
	_hologram_mat.set_shader_parameter("grid_intensity", 1.0)
	_hologram_mat.set_shader_parameter("scan_color", Color(0.0, 0.95, 0.55, 1.0))
	_hologram_mat.set_shader_parameter("grid_color", Color(0.1, 0.8, 1.0, 1.0))
	_hologram_mat.set_shader_parameter("rim_color", Color(0.0, 1.0, 0.85, 1.0))
	_hologram_mat.set_shader_parameter("rim_boost", 1.6)
	_hologram_overlay.material_override = _hologram_mat
	# Use call_deferred to avoid "Parent node is busy setting up children" when
	# _setup_hologram_overlay() is called during _ready().
	parent.add_child.call_deferred(_hologram_overlay)

## Keeps the hologram overlay mesh in sync with the procedural bio-mesh after
## each rebuild (the bio-mesh swaps its ArrayMesh on every rebuild_ship_mesh).
func _sync_hologram_overlay() -> void:
	if _hologram_overlay == null or not is_instance_valid(_hologram_overlay):
		return
	if procedural_mesh_node == null or not is_instance_valid(procedural_mesh_node):
		return
	if _hologram_overlay.mesh != procedural_mesh_node.mesh:
		_hologram_overlay.mesh = procedural_mesh_node.mesh
		_hologram_overlay.transform = procedural_mesh_node.transform

func _on_archetype_selected(index: int) -> void:
	_reset_idle_timer()
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		var audio = ml.root.get_node("BioAudioSynth")
		audio.play_ui_click(true)
		audio.play_creature_vocalization(1.0 + float(index) * 0.2)

	var archetype_keys: Array[String] = [
		"Apex Hive Leviathan",
		"Neuro-Spore Interceptor",
		"Chitinous Void Harvester",
		"Abyssal Symbiont Frigate",
		"Viral Colony Carrier"
	]
	if index >= 0 and index < archetype_keys.size():
		var key: String = archetype_keys[index]
		if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
			_bio_manager_ref.call("load_archetype", key)
			lbl_status_msg.text = "LOADED ARCHETYPE: " + key.to_upper()
		
		if not procedural_mesh_node:
			_find_mesh_node()
		if procedural_mesh_node and is_instance_valid(procedural_mesh_node):
			var cfg: Dictionary = {}
			if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
				cfg = _bio_manager_ref.call("get_ship_config")
			else:
				cfg = {"archetype_name": key}
			procedural_mesh_node.rebuild_ship_mesh(cfg)

func _play_ui_tick() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(false)

func _play_ui_confirm() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(true)

func _on_segments_changed(val: float) -> void:
	_reset_idle_timer()
	_play_ui_tick()
	if lbl_segments_val:
		lbl_segments_val.text = str(int(val))
	_update_bio_param("segment_count", int(val))

func _on_length_changed(val: float) -> void:
	_reset_idle_timer()
	_play_ui_tick()
	if lbl_length_val:
		lbl_length_val.text = "%.1fm" % val
	_update_bio_param("length", val)

func _on_chitin_changed(val: float) -> void:
	_reset_idle_timer()
	_play_ui_tick()
	if lbl_chitin_val:
		lbl_chitin_val.text = "%.1f" % val
	_update_bio_param("chitin_density", val / 10.0)

func _on_armor_changed(val: float) -> void:
	_reset_idle_timer()
	_play_ui_tick()
	if lbl_armor_val:
		lbl_armor_val.text = "%.1f" % val
	_update_bio_param("armor_thickness", val)

func _on_eyepods_changed(val: float) -> void:
	_reset_idle_timer()
	_play_ui_tick()
	if lbl_eyepods_val:
		lbl_eyepods_val.text = str(int(val))
	_update_bio_param("eye_pod_count", int(val))

func _on_glow_color_changed(col: Color) -> void:
	_reset_idle_timer()
	_update_bio_param("glow_color", col)

func _update_bio_param(param_name: String, value: Variant) -> void:
	_reset_idle_timer()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		_bio_manager_ref.call("update_ship_parameter", param_name, value)
	if not procedural_mesh_node:
		_find_mesh_node()
	if procedural_mesh_node and is_instance_valid(procedural_mesh_node):
		var cfg := {}
		if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
			cfg = _bio_manager_ref.call("get_ship_config")
		procedural_mesh_node.rebuild_ship_mesh(cfg)

func _on_ship_config_changed(config: Dictionary) -> void:
	_apply_config_to_ui(config)
	if not procedural_mesh_node:
		_find_mesh_node()
	if procedural_mesh_node and is_instance_valid(procedural_mesh_node):
		procedural_mesh_node.rebuild_ship_mesh(config)

func _on_randomize_pressed() -> void:
	_reset_idle_timer()
	_play_ui_confirm()
	var new_seed: int = randi()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		new_seed = _bio_manager_ref.call("randomize_seed")
	genetics_randomized.emit(new_seed)
	lbl_status_msg.text = "GENETICS RANDOMIZED (SEED: %d)" % new_seed

func _on_export_obj_pressed() -> void:
	_play_ui_confirm()
	var path := "user://ship_export_%d.obj" % Time.get_ticks_msec()
	export_obj_requested.emit(path)
	lbl_status_msg.text = "MODEL EXPORTED TO " + path

func _change_scene(path: String) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioDirector"):
		ml.root.get_node("BioAudioDirector").transition_to_scene(path)
	else:
		if is_inside_tree() and get_tree():
			get_tree().change_scene_to_file(path)
		elif ml and ml.has_method("change_scene_to_file"):
			ml.call("change_scene_to_file", path)

func _on_back_to_main_menu_pressed() -> void:
	_play_ui_confirm()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		_bio_manager_ref.call("set_game_mode", 0) # BUILDER / MAIN_MENU
	_change_scene("res://scenes/main_menu.tscn")

func _on_test_flight_pressed() -> void:
	_play_ui_confirm()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		_bio_manager_ref.call("set_game_mode", 1) # FLIGHT_MODE
	test_flight_requested.emit()
	_change_scene("res://scenes/space_flight.tscn")

func _on_inspect_organs_pressed() -> void:
	_play_ui_confirm()
	if _bio_manager_ref and is_instance_valid(_bio_manager_ref):
		_bio_manager_ref.call("set_game_mode", 2) # INSPECTOR_MODE
	inspect_organs_requested.emit()
	_change_scene("res://scenes/organ_inspector.tscn")

func _gui_input(event: InputEvent) -> void:
	_handle_orbit_input(event)

func _unhandled_input(event: InputEvent) -> void:
	_handle_orbit_input(event)

func _handle_orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			is_dragging_orbit = event.pressed
			idle_interaction_timer = 0.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = clampf(orbit_distance - 2.5, 10.0, 85.0)
			idle_interaction_timer = 0.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = clampf(orbit_distance + 2.5, 10.0, 85.0)
			idle_interaction_timer = 0.0

	elif event is InputEventMouseMotion:
		if is_dragging_orbit or (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
			orbit_yaw -= event.relative.x * 0.008
			orbit_pitch = clampf(orbit_pitch - event.relative.y * 0.008, -1.35, 1.35)
			idle_interaction_timer = 0.0

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_ship_builder_close"):
			_on_back_to_main_menu_pressed()
		elif event.is_action_pressed("galmap_left"):
			orbit_yaw += 0.12
			idle_interaction_timer = 0.0
		elif event.is_action_pressed("galmap_right"):
			orbit_yaw -= 0.12
			idle_interaction_timer = 0.0
		elif event.is_action_pressed("galmap_forward"):
			orbit_pitch = clampf(orbit_pitch + 0.12, -1.35, 1.35)
			idle_interaction_timer = 0.0
		elif event.is_action_pressed("galmap_back"):
			orbit_pitch = clampf(orbit_pitch - 0.12, -1.35, 1.35)
			idle_interaction_timer = 0.0

# ------------------------------------------------------------------------------
# Animated Sidebar Border Glow
# ------------------------------------------------------------------------------

func _draw() -> void:
	if size.x <= 10.0 or size.y <= 10.0:
		return
	if not sidebar_panel or not is_instance_valid(sidebar_panel):
		return

	# Animated border glow pulse on the sidebar panel
	var panel_rect := Rect2(sidebar_panel.position, sidebar_panel.size)
	var glow_alpha: float = 0.25 + sin(_animation_time * 2.0) * 0.15
	var glow_col := Color(0.0, 1.0, 0.7, glow_alpha)

	# Draw multiple expanding glow outlines for depth
	for i in range(3):
		var expand: float = float(i + 1) * 3.0
		var alpha_falloff: float = glow_alpha * (1.0 - float(i) * 0.3)
		var glow_rect := Rect2(
			panel_rect.position - Vector2(expand, expand),
			panel_rect.size + Vector2(expand * 2.0, expand * 2.0)
		)
		draw_rect(glow_rect, Color(glow_col.r, glow_col.g, glow_col.b, alpha_falloff * 0.3), false, 1.5)

	# Subtle animated energy line along bottom edge of sidebar
	var energy_y: float = panel_rect.position.y + panel_rect.size.y + 4.0
	var energy_progress: float = fmod(_animation_time * 0.5, 1.0)
	var energy_x_start: float = panel_rect.position.x
	var energy_x_end: float = panel_rect.position.x + panel_rect.size.x * energy_progress
	draw_line(Vector2(energy_x_start, energy_y), Vector2(energy_x_end, energy_y), Color(glow_col.r, glow_col.g, glow_col.b, glow_alpha * 0.6), 2.0)
