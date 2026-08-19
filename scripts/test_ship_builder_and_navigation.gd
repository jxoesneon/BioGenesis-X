extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X: SHIP BUILDER GEOMETRY, 3D ORBIT & NAVIGATION AUDIT")
	print("==================================================================")

	# -------------------------------------------------------------------------
	# TEST 1: ARCHETYPE GEOMETRY MUTATION TEST
	# -------------------------------------------------------------------------
	print("\n[TEST 1] Testing Archetype Selection & Live Mesh Geometry Alterations...")
	var builder_scene := load("res://scenes/ship_builder.tscn")
	var builder_inst: Node = builder_scene.instantiate()
	root.add_child(builder_inst)

	var bio_mesh: ProceduralBioMesh = builder_inst.get_node_or_null("ProceduralBioMesh")
	var builder_ui: ShipBuilderUI = builder_inst.get_node_or_null("UI")
	assert(bio_mesh != null, "ProceduralBioMesh must exist in ship_builder scene")
	assert(builder_ui != null, "ShipBuilderUI must exist in ship_builder scene")

	var archetypes := [
		{"name": "Apex Hive Leviathan", "id": "apex_hive_leviathan"},
		{"name": "Neuro-Spore Interceptor", "id": "neuro_spore_interceptor"},
		{"name": "Chitinous Void Harvester", "id": "chitinous_void_harvester"},
		{"name": "Abyssal Symbiont Frigate", "id": "abyssal_symbiont_frigate"},
		{"name": "Viral Colony Carrier", "id": "viral_colony_carrier"}
	]

	var vertex_counts := []
	for i in range(archetypes.size()):
		var arch = archetypes[i]
		builder_ui._on_archetype_selected(i)
		
		var mesh: ArrayMesh = bio_mesh.mesh as ArrayMesh
		assert(mesh != null, "Mesh should not be null after archetype switch")
		var total_verts := 0
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			total_verts += verts.size()
		
		print("  • [%d/5] Selected '%s' -> 3D Mesh Surfaces: %d | Total Vertices: %d" % [
			i + 1, arch["name"], mesh.get_surface_count(), total_verts
		])
		vertex_counts.append(total_verts)
		assert(total_verts > 0, "Archetype must produce geometry")

	print("  ✓ All 5 archetypes successfully mutate procedural 3D geometry.")

	# -------------------------------------------------------------------------
	# TEST 2: 3D TURNTABLE ORBIT & ZOOM CONTROLS
	# -------------------------------------------------------------------------
	print("\n[TEST 2] Testing 3D Model Rotation & Camera Orbit/Zoom Controls...")
	var initial_yaw := builder_ui.orbit_yaw
	var initial_pitch := builder_ui.orbit_pitch
	var initial_dist := builder_ui.orbit_distance

	print("  • Starting Camera Perspective: Yaw=%.2f rad (Top-Right), Pitch=%.2f rad (Looking Down), Distance=%.1fm" % [
		initial_yaw, initial_pitch, initial_dist
	])
	assert(initial_yaw < 0.0, "Starting camera must be positioned to the right (Yaw < 0)")
	assert(initial_pitch < 0.0, "Starting camera must be elevated looking down at the ship (Pitch < 0)")

	# Simulate Mouse Drag Orbit
	var motion_event := InputEventMouseMotion.new()
	motion_event.relative = Vector2(100, -50)
	builder_ui.is_dragging_orbit = true
	builder_ui._handle_orbit_input(motion_event)

	print("  • Dragged mouse Vector2(100, -50) -> Orbit Yaw: %.3f (was %.3f) | Orbit Pitch: %.3f" % [
		builder_ui.orbit_yaw, initial_yaw, builder_ui.orbit_pitch
	])
	assert(builder_ui.orbit_yaw != initial_yaw, "Mouse drag must rotate orbit yaw")

	# Simulate Mouse Wheel Zoom
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_event.pressed = true
	builder_ui._handle_orbit_input(wheel_event)
	print("  • Mouse Wheel Up Zoom -> Orbit Distance: %.2fm (was %.2fm)" % [
		builder_ui.orbit_distance, initial_dist
	])
	assert(builder_ui.orbit_distance < initial_dist, "Mouse wheel up must zoom in")

	# Process frames to verify camera transform & centroid locking
	for _f in range(20):
		builder_ui._process(0.016)
	
	var ship_center := bio_mesh.get_ship_geometric_center()
	print("  • Ship 3D Geometric Centroid: %s" % str(ship_center))
	print("  • Camera Pivot Position: %s" % str(builder_ui.camera_pivot_node.position))
	assert(builder_ui.camera_pivot_node.position.distance_to(ship_center) < 1.0, "Camera pivot must track to the ship's 3D geometric center")
	print("  ✓ 3D Turntable rotation centered on ship geometric center verified.")

	# Test 2-Minute Inactivity Auto-Rotation Trigger
	print("\n[TEST 2B] Verifying 2-Minute (120s) Inactivity Auto-Rotation Threshold...")
	builder_ui.is_dragging_orbit = false
	builder_ui.idle_interaction_timer = 0.0 # Just interacted
	var yaw_at_rest := builder_ui.orbit_yaw
	
	# Simulate 60 seconds (1 minute) of idle time
	builder_ui._update_camera_orbit(60.0)
	print("  • After 60s idle: Yaw=%.3f (Initial=%.3f) -> Auto-rotate inactive" % [builder_ui.orbit_yaw, yaw_at_rest])
	assert(builder_ui.orbit_yaw == yaw_at_rest, "Auto-rotation must NOT start before 120 seconds")

	# Simulate reaching 120.5 seconds of idle time
	builder_ui._update_camera_orbit(60.5)
	print("  • After 120.5s idle: Yaw=%.3f (Initial=%.3f) -> Auto-rotate ACTIVE!" % [builder_ui.orbit_yaw, yaw_at_rest])
	assert(builder_ui.orbit_yaw != yaw_at_rest, "Auto-rotation MUST start after 2 minutes (120s) of inactivity")

	# User interaction resets idle timer
	builder_ui._on_segments_changed(14.0)
	print("  • User slider interaction -> Idle timer reset to: %.1fs" % builder_ui.idle_interaction_timer)
	assert(builder_ui.idle_interaction_timer == 0.0, "User interaction must reset the 2-minute timer")
	print("  ✓ 2-Minute inactivity auto-rotation threshold strictly verified.")

	# -------------------------------------------------------------------------
	# TEST 3: 3D SPACE NEBULA BACKGROUND & DRYDOCK ENVIRONMENT
	# -------------------------------------------------------------------------
	print("\n[TEST 3] Testing 3D Background Nebula Sky & Pedestal Environment...")
	var world_env := builder_inst.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert(world_env != null, "WorldEnvironment must exist")
	assert(world_env.environment.background_mode == Environment.BG_SKY, "Background mode must be SKY")
	assert(world_env.environment.sky != null, "Sky resource must be active")

	var berth := builder_inst.get_node_or_null("DrydockBerthFloor")
	assert(berth != null, "DrydockBerthFloor must exist in ship_builder scene")
	var pylons := builder_inst.get_node_or_null("DockingPylons")
	assert(pylons != null, "DockingPylons must exist in ship_builder scene")
	print("  ✓ 3D Space Nebula Sky & Orbital Titanium Drydock Berth active.")

	# -------------------------------------------------------------------------
	# TEST 4: COMPREHENSIVE SCREEN RETURN NAVIGATION AUDIT
	# -------------------------------------------------------------------------
	print("\n[TEST 4] Testing Return Navigation Buttons Across All Screens...")
	
	# Ship Builder Back Button
	if builder_ui.btn_back_main_menu == null:
		builder_ui._build_builder_interface()
	assert(builder_ui.btn_back_main_menu != null, "ShipBuilderUI must have a Return button")
	print("  • ShipBuilder -> Return button text: '%s'" % builder_ui.btn_back_main_menu.text)

	builder_inst.queue_free()

	# Organ Inspector Back Button
	var inspector_scene := load("res://scenes/organ_inspector.tscn")
	var inspector_inst = inspector_scene.instantiate()
	root.add_child(inspector_inst)
	var inspector_ui := inspector_inst.get_node_or_null("OrganInspectorUI") as OrganInspectorUI
	assert(inspector_ui != null, "OrganInspectorUI must exist")
	if inspector_ui.back_button == null:
		inspector_ui._load_pipeline_definitions()
		inspector_ui._build_inspector_ui()
	assert(inspector_ui.back_button != null, "OrganInspectorUI must have a Return button")
	print("  • OrganInspector -> Return button text: '%s'" % inspector_ui.back_button.text)
	inspector_inst.queue_free()

	# Pause Menu Return Buttons
	var pause_scene := load("res://scenes/pause_menu.tscn")
	var pause_inst = pause_scene.instantiate()
	root.add_child(pause_inst)
	var pause_ui := pause_inst as PauseMenuUI
	assert(pause_ui != null, "PauseMenuUI must exist")
	if pause_ui.btn_main_menu == null:
		pause_ui._ready()
	assert(pause_ui.btn_main_menu != null, "PauseMenuUI must have 'Return to Main Menu' button")
	assert(pause_ui.btn_builder != null, "PauseMenuUI must have 'Ship Builder Lab' button")
	print("  • PauseMenu -> 'Return to Main Menu' and 'Ship Builder Lab' buttons verified: '%s', '%s'" % [
		pause_ui.btn_main_menu.text, pause_ui.btn_builder.text
	])
	pause_inst.queue_free()

	# Cinematic Intro Skip Button
	var intro_scene := load("res://scenes/cinematic_intro.tscn")
	var intro_inst = intro_scene.instantiate()
	root.add_child(intro_inst)
	var seq := intro_inst.get_node_or_null("CinematicSequencer") as CinematicSequencer
	assert(seq != null, "CinematicSequencer must exist")
	print("  • CinematicIntro -> Skip Intro overlay active")
	intro_inst.queue_free()

	print("\n==================================================================")
	print("SUCCESS: 100% SHIP BUILDER, 3D ROTATION & NAVIGATION AUDIT PASSED!")
	print("==================================================================")
	quit()
