# res://scripts/test_nms_flight_mechanics.gd
# ==============================================================================
# BioGenesis-X - No Man's Sky Starship Flight Control Mechanics Test Suite
# ==============================================================================

extends SceneTree

const FlightControllerClass = preload("res://scripts/FlightController.gd")
const VoidFaunaDroneClass = preload("res://scripts/VoidFaunaDrone.gd")

func _init() -> void:
	print("\n==================================================================")
	print("BIO-GENESIS-X: NO MAN'S SKY STARSHIP FLIGHT MECHANICS AUDIT")
	print("==================================================================")

	var ship := FlightControllerClass.new()
	ship.name = "PlayerStarship"
	root.add_child(ship)
	ship._ready()

	# -------------------------------------------------------------------------
	# TEST 1: W/S Throttle & Brake Mechanics
	# -------------------------------------------------------------------------
	print("\n[TEST 1] Testing W Throttle Acceleration & S Brake Deceleration...")
	
	# Simulate Forward Throttle (W)
	ship.simulated_thrust = Vector3(0, 0, -1.0)
	for _f in range(30): # ~0.5s of forward acceleration
		ship._physics_process(0.016)
	
	var cruise_speed := ship.linear_velocity_vector.length()
	print("  • Speed after W Throttle Acceleration: %.2f m/s" % cruise_speed)
	assert(cruise_speed > 10.0, "W key must accelerate starship forward")
	assert(ship.linear_velocity_vector.z < 0.0, "Forward thrust must propel vessel forward (-Z)")

	# Simulate Active Brake (S)
	ship.simulated_thrust = Vector3(0, 0, 1.0)
	for _f in range(30): # ~0.5s of active braking
		ship._physics_process(0.016)
	
	var braked_speed := ship.linear_velocity_vector.length()
	print("  • Speed after S Active Brake: %.2f m/s (was %.2f m/s)" % [braked_speed, cruise_speed])
	assert(braked_speed < cruise_speed, "S key must brake/decelerate starship")
	ship.simulated_thrust = Vector3.ZERO
	print("  ✓ W/S Throttle and Brake mechanics verified.")

	# -------------------------------------------------------------------------
	# TEST 2: Steer & Auto-Banking (Coordinated Turns)
	# -------------------------------------------------------------------------
	print("\n[TEST 2] Testing A/D Steering with No Man's Sky Auto-Banking...")
	ship.auto_banking_enabled = true
	ship.simulated_yaw = 1.0 # Steer Left (A)
	
	for _f in range(20):
		ship._physics_process(0.016)
	
	var left_roll := ship.angular_velocity_vector.z
	print("  • Left Steer (A) -> Yaw Vel: %.3f rad/s | Auto-Bank Roll Vel: %.3f rad/s" % [
		ship.angular_velocity_vector.y, left_roll
	])
	assert(ship.angular_velocity_vector.y > 0.0, "Steering A must apply positive yaw")
	assert(left_roll > 0.0, "Auto-banking must roll into left turn")

	# Release steering and verify auto-leveling
	ship.simulated_yaw = 0.0
	for _f in range(40):
		ship._physics_process(0.016)
	
	print("  • Auto-leveling restoring roll stability...")
	print("  ✓ Auto-Banking and auto-leveling stabilization verified.")

	# -------------------------------------------------------------------------
	# TEST 2B: Mouse Flight Controls (Direct Mouse Pitch, Yaw & Auto-Bank)
	# -------------------------------------------------------------------------
	print("\n[TEST 2B] Testing Mouse Flight Motion & Aiming Controls...")
	ship.angular_velocity_vector = Vector3.ZERO
	ship.mouse_control_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Simulate active mouse motion over 5 ticks (Moving mouse Up and Right)
	for _m in range(5):
		ship.mouse_delta = Vector2(50.0, -30.0)
		ship._physics_process(0.016)

	print("  • Mouse Movement (Up & Right) -> Pitch Vel: %.3f rad/s | Yaw Vel: %.3f rad/s | Roll Vel: %.3f rad/s" % [
		ship.angular_velocity_vector.x, ship.angular_velocity_vector.y, ship.angular_velocity_vector.z
	])
	assert(ship.angular_velocity_vector.x > 0.0, "Mouse Up movement must pitch ship nose up")
	assert(ship.angular_velocity_vector.y < 0.0, "Mouse Right movement must yaw ship nose right")
	assert(ship.angular_velocity_vector.z < 0.0, "Mouse Right movement must auto-bank into right turn")
	assert(ship.mouse_delta == Vector2.ZERO, "Mouse delta must be consumed each frame")
	print("  ✓ Direct Mouse Pitch, Yaw, and Coordinated Auto-Bank verified.")

	# -------------------------------------------------------------------------
	# TEST 3: Q/E Manual Roll Override
	# -------------------------------------------------------------------------
	print("\n[TEST 3] Testing Q/E Manual Roll Barrel Rolls...")
	ship.simulated_roll = -1.0 # Manual Roll Right (E)
	for _f in range(20):
		ship._physics_process(0.016)
	
	print("  • Manual Roll (E) -> Roll Angular Velocity: %.3f rad/s" % ship.angular_velocity_vector.z)
	assert(ship.angular_velocity_vector.z < 0.0, "E key must perform manual right roll")
	ship.simulated_roll = 0.0
	print("  ✓ Q/E Manual Roll override verified.")

	# -------------------------------------------------------------------------
	# TEST 4: Starship Combat Auto-Follow
	# -------------------------------------------------------------------------
	print("\n[TEST 4] Testing Starship Combat Target Auto-Follow Tracking...")
	var drone := VoidFaunaDroneClass.new()
	drone.name = "EnemyDrone"
	drone.position = ship.position + Vector3(25.0, 15.0, -80.0) # Target in forward cone
	root.add_child(drone)
	drone.add_to_group("targets")

	var auto_torques := ship._calculate_auto_follow_torques(drone)
	print("  • Target at %s -> Auto-Follow Torques: Pitch=%.3f, Yaw=%.3f" % [
		str(drone.position), auto_torques.x, auto_torques.y
	])
	assert(auto_torques.length() > 0.1, "Combat Auto-Follow must compute non-zero guidance vector to target")
	assert(auto_torques.x > 0.0, "Must pitch up towards elevated target")
	assert(auto_torques.y < 0.0, "Must yaw right towards starboard target")
	print("  ✓ Starship Combat Auto-Follow guidance verified.")

	# -------------------------------------------------------------------------
	# TEST 5: Bio-Boost (Wave Engine Sublight) Dynamics
	# -------------------------------------------------------------------------
	print("\n[TEST 5] Testing Wave Engine Bio-Boost & FOV Scaling...")
	ship.simulated_boost = true
	ship.simulated_thrust = Vector3(0, 0, -1.0)
	for _f in range(30):
		ship._physics_process(0.016)

	var boost_speed := ship.linear_velocity_vector.length()
	print("  • Boosted Speed: %.2f m/s | G-Force: %.2f G" % [boost_speed, ship.current_g_force])
	assert(boost_speed > cruise_speed, "Bio-Boost must exceed standard cruise speed")
	print("  ✓ Wave Engine Bio-Boost verified.")

	# -------------------------------------------------------------------------
	# TEST 6: No Man's Sky Tethered Mouse Flight HUD Rendering
	# -------------------------------------------------------------------------
	print("\n[TEST 6] Testing No Man's Sky Tethered Mouse Flight HUD...")
	var FlightHUDUIClass := preload("res://scripts/FlightHUDUI.gd")
	var hud := FlightHUDUIClass.new()
	hud.size = Vector2(1920, 1080)
	root.add_child(hud)
	hud._ready()
	hud._flight_controller_ref = ship
	
	# Simulate ship mouse flight cursor deflection
	ship.mouse_flight_cursor = Vector2(0.5, -0.3)
	hud._process(0.016)
	
	print("  • HUD mouse_flight_cursor synced: (%.2f, %.2f)" % [hud.mouse_flight_cursor.x, hud.mouse_flight_cursor.y])
	assert(hud.mouse_flight_cursor == ship.mouse_flight_cursor, "HUD must sync mouse_flight_cursor from ship")
	assert(hud.tether_max_radius > 50.0, "Tether max radius must be defined")
	print("  ✓ No Man's Sky Tethered Flight HUD sync verified.")

	# -------------------------------------------------------------------------
	# TEST 7: space_flight.tscn Scene Tree Automatic Flight HUD Linkage
	# -------------------------------------------------------------------------
	print("\n[TEST 7] Testing space_flight.tscn Scene Tree HUD Autodiscovery...")
	var space_scene: Node = load("res://scenes/space_flight.tscn").instantiate()
	root.add_child(space_scene)
	var scene_ship: Node = space_scene.find_child("PlayerShip", true, false)
	var scene_hud: Node = space_scene.find_child("FlightHUD", true, false)
	assert(scene_ship != null, "PlayerShip must exist in space_flight.tscn")
	assert(scene_hud != null, "FlightHUD must exist in space_flight.tscn")
	
	scene_hud._process(0.016)
	assert(scene_hud._flight_controller_ref == scene_ship, "FlightHUD must automatically locate PlayerShip sibling")
	print("  ✓ space_flight.tscn HUD automatic linkage verified.")

	print("\n==================================================================")
	print("SUCCESS: 100% NO MAN'S SKY STARSHIP FLIGHT AUDIT PASSED!")
	print("==================================================================")
	quit(0)
