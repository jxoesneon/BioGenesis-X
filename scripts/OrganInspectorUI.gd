# res://scripts/OrganInspectorUI.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# OrganInspectorUI.gd - Interactive 5 Organ System Pipeline Inspector Studio
# ==============================================================================
# Extends Control to provide an interactive anatomical pipeline inspector.
# Renders nodes for all 5 organ systems from ORGAN_SYSTEMS.md:
# 1. Bio-Plasma Power & Propulsion
# 2. Hemolymph Circulation & Thermal Regulation
# 3. Nervous & Cybernetic Synaptic System
# 4. Endosymbiotic Life Support & Metabolism
# 5. Exoskeleton, Armor & Shield Defense
# Interactive node selection opens a telemetry popup detailing metabolic output,
# pressure, flow rate, and upstream/downstream connections with 2D conduit links.
# ==============================================================================

@tool
class_name OrganInspectorUI
extends Control

## Signal emitted when user selects an organ node
signal organ_node_selected(node_data: Dictionary)
## Signal emitted when returning to ship builder or main menu
signal exit_inspector_requested()

# Color Palette for 5 Organ Pipelines
const PIPELINE_COLORS: Dictionary = {
	"bio_plasma": Color(0.0, 1.0, 0.7),     # Glowing Cyan
	"hemolymph": Color(1.0, 0.2, 0.4),      # Deep Crimson
	"nervous": Color(0.8, 0.4, 1.0),        # Synaptic Violet
	"life_support": Color(0.2, 1.0, 0.4),   # Bio-Moss Emerald
	"armor_defense": Color(1.0, 0.7, 0.1)   # Radiotrophic Amber
}

# Active Selected State
var active_pipeline_key: String = "bio_plasma"
var selected_node_id: String = ""
var selected_node_data: Dictionary = {}

# Node Dictionary & Visual Layout Map
var pipeline_definitions: Dictionary = {}
var node_ui_buttons: Dictionary = {}
var node_canvas_positions: Dictionary = {}

# UI Component References
var pipeline_tab_hb: HBoxContainer
var node_graph_panel: PanelContainer
var node_graph_container: Control
var details_popup_panel: PanelContainer
var back_button: Button

# Detail Popup Label References
var lbl_popup_name: Label
var lbl_popup_role: Label
var lbl_popup_layer: Label
var lbl_popup_coords: Label
var lbl_popup_output: Label
var lbl_popup_upstream: Label
var lbl_popup_downstream: Label

var _conduit_pulse_time: float = 0.0
var _telemetry_ref: Node = null

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_load_pipeline_definitions()
	_build_inspector_ui()
	_locate_telemetry()
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").stethoscope_mode = true
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _exit_tree() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").stethoscope_mode = false
	if resized.is_connected(_on_resized):
		resized.disconnect(_on_resized)

func _on_resized() -> void:
	_update_node_positions()
	queue_redraw()

func _locate_telemetry() -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root and main_loop.root.has_node("OrganTelemetry"):
		_telemetry_ref = main_loop.root.get_node("OrganTelemetry")

func _process(delta: float) -> void:
	_conduit_pulse_time += delta
	queue_redraw()

# ------------------------------------------------------------------------------
# Data Initialization from ORGAN_SYSTEMS.md
# ------------------------------------------------------------------------------

func _load_pipeline_definitions() -> void:
	pipeline_definitions = {
		"bio_plasma": {
			"id": "bio_plasma",
			"name": "1. BIO-PLASMA PROPULSION",
			"color": PIPELINE_COLORS["bio_plasma"],
			"nodes": [
				{
					"id": "plasma_gland", "name": "Bio-Plasma Electrolysis Gland", "role": "GENERATION",
					"layer": "organs", "coords": Vector3(0.0, -1.2, 4.0), "output": "850 kW Electrolysis",
					"upstream": "Ingestion Gizzard", "downstream": ["plasma_bladder"]
				},
				{
					"id": "plasma_bladder", "name": "Muscular Plasma Bladder", "role": "STORAGE",
					"layer": "organs", "coords": Vector3(0.0, -0.8, 1.5), "output": "140 Bar Fuel Buffer",
					"upstream": "plasma_gland", "downstream": ["plasma_trunk"]
				},
				{
					"id": "plasma_trunk", "name": "Primary Plasma Trunk Highway", "role": "DISTRIBUTION",
					"layer": "vascular", "coords": Vector3(0.0, -0.5, -2.0), "output": "2,400 L/min Flow",
					"upstream": "plasma_bladder", "downstream": ["caudal_manifold", "disruptor_glands"]
				},
				{
					"id": "caudal_manifold", "name": "Caudal Manifold Trunk", "role": "DISTRIBUTION",
					"layer": "vascular", "coords": Vector3(0.0, 0.0, -6.5), "output": "Hydrodynamic Splitting",
					"upstream": "plasma_trunk", "downstream": ["siphon_nozzles"]
				},
				{
					"id": "siphon_nozzles", "name": "Bio-Plasma Vent Nozzles", "role": "EFFECTOR",
					"layer": "exoskeleton", "coords": Vector3(0.0, -0.4, -9.0), "output": "1,700 kN Hydro-Pulse",
					"upstream": "caudal_manifold", "downstream": ["Vacuum"]
				},
				{
					"id": "disruptor_glands", "name": "Bio-Plasma Disruptor Glands", "role": "EFFECTOR",
					"layer": "organs", "coords": Vector3(0.0, 1.2, 3.5), "output": "450 MW Thermal Burst",
					"upstream": "plasma_trunk", "downstream": ["Tactical Reticle"]
				}
			]
		},
		"hemolymph": {
			"id": "hemolymph",
			"name": "2. HEMOLYMPH CIRCULATION",
			"color": PIPELINE_COLORS["hemolymph"],
			"nodes": [
				{
					"id": "heart_core", "name": "Aorta Central Heart Core", "role": "GENERATION",
					"layer": "vascular", "coords": Vector3(0.0, 0.2, 0.5), "output": "68 BPM Systolic Stroke",
					"upstream": "None", "downstream": ["hemolymph_atrium"]
				},
				{
					"id": "hemolymph_atrium", "name": "Hemolymph Atrium Reservoir", "role": "STORAGE",
					"layer": "vascular", "coords": Vector3(0.0, 0.6, 1.2), "output": "18.5 Bar Antifreeze Buffer",
					"upstream": "heart_core", "downstream": ["central_aorta"]
				},
				{
					"id": "central_aorta", "name": "Central Aorta Highway", "role": "DISTRIBUTION",
					"layer": "vascular", "coords": Vector3(0.0, 0.0, 0.0), "output": "Murray's Law Branching",
					"upstream": "hemolymph_atrium", "downstream": ["flank_arteries", "spiracle_vents"]
				},
				{
					"id": "flank_arteries", "name": "Luminescent Flank Arteries", "role": "DISTRIBUTION",
					"layer": "vascular", "coords": Vector3(1.5, 0.0, 0.0), "output": "Capillary Delivery",
					"upstream": "central_aorta", "downstream": ["Organ Mesh Beds"]
				},
				{
					"id": "spiracle_vents", "name": "Respiratory Spiracle Vents", "role": "EFFECTOR",
					"layer": "exoskeleton", "coords": Vector3(0.0, 1.5, 0.0), "output": "820 W/m² IR Radiation",
					"upstream": "central_aorta", "downstream": ["Space Vacuum"]
				}
			]
		},
		"nervous": {
			"id": "nervous",
			"name": "3. NERVOUS SYNAPTIC",
			"color": PIPELINE_COLORS["nervous"],
			"nodes": [
				{
					"id": "ganglion_brain", "name": "Primary Ganglion Brain Core", "role": "GENERATION",
					"layer": "organs", "coords": Vector3(0.0, 0.8, 5.5), "output": "98.4% Synaptic Coherence",
					"upstream": "Neuro-Link Pod", "downstream": ["neurolink_pod", "spinal_axon"]
				},
				{
					"id": "neurolink_pod", "name": "Human Neuro-Link Interface", "role": "INTERFACE",
					"layer": "organs", "coords": Vector3(0.0, 0.4, 4.8), "output": "Graphene Fiber Plug",
					"upstream": "Human Pilot", "downstream": ["ganglion_brain"]
				},
				{
					"id": "spinal_axon", "name": "Spinal Axon Cord Highway", "role": "DISTRIBUTION",
					"layer": "muscular", "coords": Vector3(0.0, 0.5, 0.0), "output": "120 m/s Nerve Impulse",
					"upstream": "ganglion_brain", "downstream": ["eye_pods", "muscle_tendons"]
				},
				{
					"id": "eye_pods", "name": "Ocular Beam Stalk Pods", "role": "EFFECTOR",
					"layer": "exoskeleton", "coords": Vector3(0.0, 1.0, 6.2), "output": "Multispectral Vision",
					"upstream": "spinal_axon", "downstream": ["Pilot Telemetry HUD"]
				},
				{
					"id": "muscle_tendons", "name": "Biomechanical Muscle Tendons", "role": "EFFECTOR",
					"layer": "muscular", "coords": Vector3(1.0, 0.0, 0.0), "output": "FABRIK IK Actuation",
					"upstream": "spinal_axon", "downstream": ["Chitin Vertebrae"]
				}
			]
		},
		"life_support": {
			"id": "life_support",
			"name": "4. LIFE SUPPORT METABOLISM",
			"color": PIPELINE_COLORS["life_support"],
			"nodes": [
				{
					"id": "ingestion_gizzard", "name": "Comet Ingestion Gizzard", "role": "GENERATION",
					"layer": "organs", "coords": Vector3(0.0, -1.5, 6.0), "output": "12.5 kg/min Mineral Ore",
					"upstream": "Exterior Mandibles", "downstream": ["biomoss_bed"]
				},
				{
					"id": "biomoss_bed", "name": "Photosynthetic Bio-Moss Bed", "role": "STORAGE",
					"layer": "organs", "coords": Vector3(0.0, 0.0, 0.0), "output": "420 L/min O₂ Output",
					"upstream": "ingestion_gizzard", "downstream": ["habitat_chambers"]
				},
				{
					"id": "habitat_chambers", "name": "Human Habitat Chambers", "role": "SOCIETAL",
					"layer": "organs", "coords": Vector3(0.0, 0.0, 0.0), "output": "1.0 atm / 12 Crew",
					"upstream": "biomoss_bed", "downstream": ["stomata_valves"]
				},
				{
					"id": "stomata_valves", "name": "Cyber-Airlock Stomata Valves", "role": "EFFECTOR",
					"layer": "exoskeleton", "coords": Vector3(1.2, 0.2, 0.0), "output": "Pressure Seal (0-1 atm)",
					"upstream": "habitat_chambers", "downstream": ["Space Vacuum"]
				}
			]
		},
		"armor_defense": {
			"id": "armor_defense",
			"name": "5. ARMOR & DEFENSE",
			"color": PIPELINE_COLORS["armor_defense"],
			"nodes": [
				{
					"id": "bone_vertebrae", "name": "Chitinous Bone Vertebrae", "role": "STRUCTURAL",
					"layer": "exoskeleton", "coords": Vector3(0.0, 0.0, 0.0), "output": "C3 NURBS Load Bear",
					"upstream": "Spinal Cord", "downstream": ["carapace_plates"]
				},
				{
					"id": "carapace_plates", "name": "Overlapping Carapace Plates", "role": "DEFENSE",
					"layer": "exoskeleton", "coords": Vector3(0.0, 0.0, 0.0), "output": "85 Gy/hr Gamma Shield",
					"upstream": "bone_vertebrae", "downstream": ["nanite_bed"]
				},
				{
					"id": "nanite_bed", "name": "Bio-Nanite Coagulation Bed", "role": "REPAIR",
					"layer": "vascular", "coords": Vector3(0.0, 0.0, 0.0), "output": "1.2 m³/s Breach Clotting",
					"upstream": "carapace_plates", "downstream": ["shield_emitters"]
				},
				{
					"id": "shield_emitters", "name": "Repulsion Shield Emitters", "role": "EFFECTOR",
					"layer": "exoskeleton", "coords": Vector3(0.0, 0.0, 0.0), "output": "450 MW Kinetic Deflection",
					"upstream": "nanite_bed", "downstream": ["Outer Barrier"]
				}
			]
		}
	}

# ------------------------------------------------------------------------------
# UI Layout Construction
# ------------------------------------------------------------------------------

func _build_inspector_ui() -> void:
	for child in get_children():
		child.queue_free()

	# Background dark glass tint
	var bg_panel: Panel = Panel.new()
	bg_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.02, 0.04, 0.04, 0.95)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	# Main Margin Container
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var outer_vb: VBoxContainer = VBoxContainer.new()
	outer_vb.add_theme_constant_override("separation", 14)
	margin.add_child(outer_vb)

	# Top Header Bar (Title, Pipeline Tabs, Back Button)
	var top_hb: HBoxContainer = HBoxContainer.new()
	top_hb.add_theme_constant_override("separation", 16)
	outer_vb.add_child(top_hb)

	var lbl_title: Label = Label.new()
	lbl_title.text = "ORGAN PIPELINE INSPECTOR"
	lbl_title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8))
	lbl_title.add_theme_font_size_override("font_size", 18)
	top_hb.add_child(lbl_title)

	var top_spacer: Control = Control.new()
	top_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	top_hb.add_child(top_spacer)

	var btn_ship_builder: Button = Button.new()
	btn_ship_builder.text = "🛠️ SHIP BUILDER LAB"
	btn_ship_builder.custom_minimum_size = Vector2(160, 32)
	btn_ship_builder.add_theme_color_override("font_color", Color(0.0, 0.9, 0.7))
	btn_ship_builder.pressed.connect(_on_ship_builder_pressed)
	top_hb.add_child(btn_ship_builder)

	back_button = Button.new()
	back_button.text = "◀ RETURN TO MAIN MENU"
	back_button.custom_minimum_size = Vector2(170, 32)
	back_button.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	back_button.pressed.connect(_on_back_pressed)
	top_hb.add_child(back_button)

	# Pipeline Selector Tabs
	pipeline_tab_hb = HBoxContainer.new()
	pipeline_tab_hb.add_theme_constant_override("separation", 10)
	outer_vb.add_child(pipeline_tab_hb)

	for p_key in ["bio_plasma", "hemolymph", "nervous", "life_support", "armor_defense"]:
		var p_data: Dictionary = pipeline_definitions[p_key]
		var btn: Button = Button.new()
		btn.text = p_data["name"]
		btn.custom_minimum_size = Vector2(180, 34)
		btn.add_theme_color_override("font_color", p_data["color"])
		btn.pressed.connect(Callable(self, "_select_pipeline").bind(p_key))
		pipeline_tab_hb.add_child(btn)

	# Middle Content (Node Graph + Details Popup Panel)
	var middle_hb: HBoxContainer = HBoxContainer.new()
	middle_hb.size_flags_vertical = SIZE_EXPAND_FILL
	middle_hb.add_theme_constant_override("separation", 16)
	outer_vb.add_child(middle_hb)

	# Node Graph Canvas Panel
	node_graph_panel = PanelContainer.new()
	node_graph_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	node_graph_panel.size_flags_vertical = SIZE_EXPAND_FILL
	
	var graph_style: StyleBoxFlat = StyleBoxFlat.new()
	graph_style.bg_color = Color(0.03, 0.07, 0.06, 0.85)
	graph_style.border_color = Color(0.0, 0.7, 0.6, 0.6)
	graph_style.set_border_width_all(1)
	graph_style.set_corner_radius_all(6)
	node_graph_panel.add_theme_stylebox_override("panel", graph_style)
	middle_hb.add_child(node_graph_panel)

	node_graph_container = Control.new()
	node_graph_container.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	node_graph_panel.add_child(node_graph_container)

	# Details Popup Panel
	details_popup_panel = PanelContainer.new()
	details_popup_panel.custom_minimum_size = Vector2(340, 0)
	details_popup_panel.size_flags_vertical = SIZE_EXPAND_FILL
	
	var pop_style: StyleBoxFlat = StyleBoxFlat.new()
	pop_style.bg_color = Color(0.04, 0.08, 0.07, 0.92)
	pop_style.border_color = Color(0.0, 0.9, 0.7, 0.8)
	pop_style.set_border_width_all(1)
	pop_style.set_corner_radius_all(6)
	pop_style.set_expand_margin_all(8)
	details_popup_panel.add_theme_stylebox_override("panel", pop_style)
	middle_hb.add_child(details_popup_panel)

	_build_details_popup_content()
	_select_pipeline("bio_plasma")

func _build_details_popup_content() -> void:
	var pop_vb: VBoxContainer = VBoxContainer.new()
	pop_vb.add_theme_constant_override("separation", 12)
	details_popup_panel.add_child(pop_vb)

	var lbl_pop_hdr: Label = Label.new()
	lbl_pop_hdr.text = "NODE TELEMETRY METRICS"
	lbl_pop_hdr.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8))
	lbl_pop_hdr.add_theme_font_size_override("font_size", 14)
	lbl_pop_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop_vb.add_child(lbl_pop_hdr)

	pop_vb.add_child(HSeparator.new())

	lbl_popup_name = Label.new()
	lbl_popup_name.text = "Select a node..."
	lbl_popup_name.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl_popup_name.add_theme_font_size_override("font_size", 15)
	lbl_popup_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pop_vb.add_child(lbl_popup_name)

	lbl_popup_role = _create_detail_row(pop_vb, "PIPELINE ROLE:", "N/A")
	lbl_popup_layer = _create_detail_row(pop_vb, "ANATOMICAL LAYER:", "N/A")
	lbl_popup_coords = _create_detail_row(pop_vb, "3D COORDINATES:", "(0, 0, 0)")
	lbl_popup_output = _create_detail_row(pop_vb, "METABOLIC OUTPUT:", "0.0")
	lbl_popup_upstream = _create_detail_row(pop_vb, "UPSTREAM SOURCE:", "None")
	lbl_popup_downstream = _create_detail_row(pop_vb, "DOWNSTREAM TARGET:", "None")

func _create_detail_row(parent: Node, header: String, default_val: String) -> Label:
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	
	var lbl_hdr: Label = Label.new()
	lbl_hdr.text = header
	lbl_hdr.add_theme_color_override("font_color", Color(0.0, 0.8, 0.85))
	lbl_hdr.add_theme_font_size_override("font_size", 10)

	var lbl_val: Label = Label.new()
	lbl_val.text = default_val
	lbl_val.add_theme_color_override("font_color", Color(0.9, 1.0, 0.95))
	lbl_val.add_theme_font_size_override("font_size", 12)
	lbl_val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	vb.add_child(lbl_hdr)
	vb.add_child(lbl_val)
	parent.add_child(vb)
	return lbl_val

# ------------------------------------------------------------------------------
# Interactive Node Graph Logic
# ------------------------------------------------------------------------------

func _select_pipeline(pipeline_key: String) -> void:
	if not pipeline_definitions.has(pipeline_key):
		return
		
	active_pipeline_key = pipeline_key
	var p_data: Dictionary = pipeline_definitions[pipeline_key]

	# Clear previous node buttons
	for n_id in node_ui_buttons:
		if is_instance_valid(node_ui_buttons[n_id]):
			node_ui_buttons[n_id].queue_free()
	node_ui_buttons.clear()
	node_canvas_positions.clear()

	# Re-create Node Buttons
	var nodes: Array = p_data["nodes"]
	for node_info: Dictionary in nodes:
		var btn: Button = Button.new()
		btn.text = "%s\n[%s]" % [node_info["name"], node_info["role"]]
		btn.custom_minimum_size = Vector2(160, 52)
		btn.add_theme_color_override("font_color", p_data["color"])
		btn.pressed.connect(Callable(self, "_select_node").bind(node_info))
		node_graph_container.add_child(btn)
		node_ui_buttons[node_info["id"]] = btn

	# Auto-select first node
	if nodes.size() > 0:
		_select_node(nodes[0])

	call_deferred("_update_node_positions")

func _update_node_positions() -> void:
	if not pipeline_definitions.has(active_pipeline_key):
		return

	var p_data: Dictionary = pipeline_definitions[active_pipeline_key]
	var nodes: Array = p_data["nodes"]
	var total: int = nodes.size()
	if total == 0:
		return

	var bounds: Vector2 = node_graph_panel.size
	if bounds.x <= 10.0 or bounds.y <= 10.0:
		bounds = Vector2(600, 400)

	# Arrange nodes horizontally in sequential flow: Generation -> Storage -> Distribution -> Effector
	var start_x: float = 40.0
	var available_w: float = maxf(40.0, bounds.x - 220.0)
	var step_x: float = available_w / float(max(1, total - 1)) if total > 1 else 0.0

	for i in range(total):
		var n_info: Dictionary = nodes[i]
		var n_id: String = n_info["id"]
		if node_ui_buttons.has(n_id):
			var btn: Button = node_ui_buttons[n_id]
			# Alternate y position for visual flow interest
			var offset_y: float = (bounds.y * 0.5 - 26.0) + sin(float(i) * 1.5) * 45.0
			var pos: Vector2 = Vector2(start_x + float(i) * step_x, offset_y)
			btn.position = pos
			node_canvas_positions[n_id] = pos + Vector2(80, 26) # Center of button

	queue_redraw()

func _select_node(node_info: Dictionary) -> void:
	selected_node_id = node_info["id"]
	selected_node_data = node_info
	organ_node_selected.emit(node_info)

	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		var audio = ml.root.get_node("BioAudioSynth")
		audio.play_ui_click(true)
		audio.play_heartbeat_pulse()

	lbl_popup_name.text = node_info["name"]
	lbl_popup_role.text = node_info["role"]
	lbl_popup_layer.text = node_info["layer"].to_upper()
	lbl_popup_coords.text = "(%.1f, %.1f, %.1f)" % [node_info["coords"].x, node_info["coords"].y, node_info["coords"].z]
	lbl_popup_output.text = node_info["output"]
	lbl_popup_upstream.text = str(node_info.get("upstream", "None"))
	
	var d_stream: Array = node_info.get("downstream", [])
	lbl_popup_downstream.text = ", ".join(d_stream)

	queue_redraw()

func _change_scene(path: String) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioDirector"):
		ml.root.get_node("BioAudioDirector").transition_to_scene(path)
	else:
		if is_inside_tree() and get_tree():
			get_tree().change_scene_to_file(path)
		elif ml and ml.has_method("change_scene_to_file"):
			ml.call("change_scene_to_file", path)

func _on_back_pressed() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(false)
	exit_inspector_requested.emit()
	_change_scene("res://scenes/main_menu.tscn")

func _on_ship_builder_pressed() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(true)
	_change_scene("res://scenes/ship_builder.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_organ_inspector_close"):
			_on_back_pressed()

# ------------------------------------------------------------------------------
# Canvas Drawing (Flow Conduits between nodes)
# ------------------------------------------------------------------------------

func _draw() -> void:
	if size.x <= 10.0 or size.y <= 10.0:
		return
	if not pipeline_definitions.has(active_pipeline_key):
		return

	var p_data: Dictionary = pipeline_definitions[active_pipeline_key]
	var pipe_col: Color = p_data["color"]
	var nodes: Array = p_data["nodes"]

	# Convert node graph local coordinates relative to Control
	var container_offset := node_graph_panel.global_position - global_position

	# Draw pulsing glow halos around the selected node button
	if selected_node_id != "" and node_canvas_positions.has(selected_node_id):
		var sel_center: Vector2 = container_offset + node_canvas_positions[selected_node_id]
		var glow_pulse: float = 0.4 + sin(_conduit_pulse_time * 3.5) * 0.25
		# Outer glow halo
		var halo_r1: float = 50.0 + sin(_conduit_pulse_time * 2.0) * 6.0
		draw_arc(sel_center, halo_r1, 0, PI * 2.0, 32, Color(pipe_col.r, pipe_col.g, pipe_col.b, glow_pulse * 0.3), 2.5)
		# Middle glow halo
		var halo_r2: float = 40.0 + sin(_conduit_pulse_time * 2.5) * 4.0
		draw_arc(sel_center, halo_r2, 0, PI * 2.0, 32, Color(pipe_col.r, pipe_col.g, pipe_col.b, glow_pulse * 0.5), 2.0)
		# Inner glow halo
		var halo_r3: float = 32.0 + sin(_conduit_pulse_time * 3.0) * 3.0
		draw_arc(sel_center, halo_r3, 0, PI * 2.0, 24, Color(pipe_col.r, pipe_col.g, pipe_col.b, glow_pulse * 0.7), 1.5)

	for n_info in nodes:
		var src_id: String = n_info["id"]
		if not node_canvas_positions.has(src_id):
			continue

		var src_pos: Vector2 = container_offset + node_canvas_positions[src_id]
		var downstream_ids: Array = n_info.get("downstream", [])

		for target_id in downstream_ids:
			if node_canvas_positions.has(target_id):
				var target_pos: Vector2 = container_offset + node_canvas_positions[target_id]
				
				# Highlight active selected node conduits
				var is_active_link: bool = (src_id == selected_node_id or target_id == selected_node_id)
				var line_col := pipe_col if is_active_link else pipe_col * Color(1, 1, 1, 0.4)
				var thickness := 3.0 if is_active_link else 1.8

				# Draw outer glow conduit line (subtle)
				var control_pt1: Vector2 = src_pos + Vector2(60, 0)
				var control_pt2: Vector2 = target_pos - Vector2(60, 0)
				if is_active_link:
					var glow_line_col := Color(pipe_col.r, pipe_col.g, pipe_col.b, 0.15)
					draw_polyline(_get_bezier_points(src_pos, control_pt1, control_pt2, target_pos, 24), glow_line_col, thickness + 4.0)

				# Draw Bezier / Curved Conduit Line
				draw_polyline(_get_bezier_points(src_pos, control_pt1, control_pt2, target_pos, 24), line_col, thickness)

				# Animated fluid flow: multiple staggered pulse particles along conduit
				var num_flow_particles: int = 3
				for p_idx in range(num_flow_particles):
					var phase_offset: float = float(p_idx) / float(num_flow_particles)
					var pulse_t := fmod(_conduit_pulse_time * 0.8 + phase_offset, 1.0)
					var pulse_pos := _sample_bezier(src_pos, control_pt1, control_pt2, target_pos, pulse_t)
					var p_size: float = (4.0 if is_active_link else 2.5) * (0.6 + sin(pulse_t * PI) * 0.4)
					var p_alpha: float = 0.5 + sin(pulse_t * PI) * 0.5
					draw_circle(pulse_pos, p_size, Color(pipe_col.r, pipe_col.g, pipe_col.b, p_alpha))

func _get_bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(steps + 1)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		pts[i] = _sample_bezier(p0, p1, p2, p3, t)
	return pts

func _sample_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	var tt := t * t
	var uu := u * u
	var uuu := uu * u
	var ttt := tt * t
	return uuu * p0 + 3.0 * uu * t * p1 + 3.0 * u * tt * p2 + ttt * p3
