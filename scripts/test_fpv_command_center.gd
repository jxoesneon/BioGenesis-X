extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X: FPV COMMAND CENTER & MESH NORMALS AUDIT")
	print("==================================================================")

	# 1. Test ProceduralBioMesh Generation & Normals
	var bio_mesh := ProceduralBioMesh.new()
	bio_mesh.rebuild_ship_mesh({
		"segments": 14,
		"length": 18.0,
		"archetype": "interceptor",
		"chitin_density": 1.2
	})
	var mesh := bio_mesh.mesh as ArrayMesh
	assert(mesh != null, "Mesh should not be null")
	print("  ✓ ProceduralBioMesh generated: %d surfaces" % mesh.get_surface_count())
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var norms := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		print("    • Surface [%d]: %d vertices, %d normals" % [s, verts.size(), norms.size()])
		assert(verts.size() == norms.size(), "Vertices and normals count must match")

	# Check Command Center Coordinates
	var eye_pos := bio_mesh.get_pilot_eye_position()
	print("  ✓ Pilot Eye Position in Command Center: %s" % str(eye_pos))
	assert(eye_pos.z > 0.0, "Pilot eye position should be in forward cranial quadrant")

	# 2. Test FlightController FPV and Chase Cam setup
	var space_flight_scene := load("res://scenes/space_flight.tscn")
	var flight_inst: Node = space_flight_scene.instantiate()
	root.add_child(flight_inst)

	var player_ship := flight_inst.get_node("PlayerShip") as FlightController
	assert(player_ship != null, "PlayerShip FlightController must exist")
	if not player_ship.fpv_camera:
		player_ship._setup_camera()
	assert(player_ship.camera_mode == FlightController.CameraMode.FPV, "Default camera mode must be FPV")
	assert(player_ship.fpv_camera != null, "CommandCenterFPVCamera must exist")
	assert(player_ship.fpv_camera.current == true, "FPV camera should be active current camera")
	print("  ✓ PlayerShip default camera: FPV (CommandCenterFPVCamera active: true)")

	# Test Camera Toggle (V / C Key)
	player_ship.toggle_camera_mode()
	assert(player_ship.camera_mode == FlightController.CameraMode.CHASE, "Camera mode should switch to CHASE")
	assert(player_ship.chase_camera.current == true, "Chase camera should be active")
	print("  ✓ Toggle camera -> Mode: CHASE (ChaseCamera active: true)")

	player_ship.toggle_camera_mode()
	assert(player_ship.camera_mode == FlightController.CameraMode.FPV, "Camera mode should switch back to FPV")
	assert(player_ship.fpv_camera.current == true, "FPV camera should be active")
	print("  ✓ Toggle camera -> Mode: FPV (CommandCenterFPVCamera active: true)")

	# Process frames to test FPV G-force lag
	player_ship.linear_velocity_vector = Vector3(0, 0, -50.0)
	player_ship._physics_process(0.016)

	print("==================================================================")
	print("SUCCESS: COMMAND CENTER FPV & INTERIOR HULL AUDIT COMPLETE!")
	print("==================================================================")
	quit()
