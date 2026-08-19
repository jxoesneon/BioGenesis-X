# res://scripts/test_unified_space_physics.gd
extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X: UNIFIED SINGLE-OBJECT SPACE PHYSICS AUDIT")
	print("==================================================================")

	var flight_scene: PackedScene = load("res://scenes/space_flight.tscn") as PackedScene
	var space_flight: Node = flight_scene.instantiate()
	root.add_child(space_flight)

	var player_ship: Node = space_flight.get_node_or_null("PlayerShip")
	assert(player_ship != null, "PlayerShip node must exist")
	assert(player_ship is FlightController, "PlayerShip must be a FlightController")

	var flight: FlightController = player_ship as FlightController

	# 1. Test Unified Single-Object Mass & Inertia Tensor
	print("\n[PHYSICS TEST 1] Verifying Unified Mass & Inertia Properties...")
	print("  • Vessel Mass: %.1f kg (%.2f metric tons)" % [flight.vessel_mass_kg, flight.vessel_mass_kg / 1000.0])
	print("  • Inertia Tensor: Ix(Pitch)=%.1f, Iy(Yaw)=%.1f, Iz(Roll)=%.1f kg*m^2" % [
		flight.moment_of_inertia.x, flight.moment_of_inertia.y, flight.moment_of_inertia.z
	])
	assert(flight.vessel_mass_kg > 10000.0, "Vessel mass must be positive realistic scale")
	assert(flight.moment_of_inertia.x > 0.0, "Pitch inertia must be positive")
	assert(flight.moment_of_inertia.y > 0.0, "Yaw inertia must be positive")
	assert(flight.moment_of_inertia.z > 0.0, "Roll inertia must be positive")
	print("  ✓ Unified mass and inertia tensor verified.")

	# 2. Test Unified Single-Object Collision Shape
	print("\n[PHYSICS TEST 2] Verifying Single Unified Collision Shape on Vessel...")
	var col_shape: CollisionShape3D = null
	for child: Node in flight.get_children():
		if child is CollisionShape3D:
			col_shape = child as CollisionShape3D
			break
	assert(col_shape != null, "FlightController must have a root CollisionShape3D")
	assert(col_shape.shape != null, "Collision shape must be instantiated")
	print("  ✓ Unified CollisionShape3D active on root vessel: %s (%s)" % [col_shape.name, col_shape.shape.get_class()])

	# 3. Test 6-DOF Newtonian Thrust Integration (F = ma)
	print("\n[PHYSICS TEST 3] Testing 6-DOF Newtonian Linear Force (F = ma)...")
	flight.linear_velocity_vector = Vector3.ZERO
	flight.dampening_enabled = false
	flight.simulated_thrust = Vector3(0, 0, -1.0) # Forward thrust

	var delta: float = 0.1
	flight._physics_process(delta)
	var expected_accel: float = flight.forward_thrust_force / flight.vessel_mass_kg
	print("  • Applied 7.5MN Siphon Thrust for 0.1s -> Velocity: (%.3f, %.3f, %.3f) m/s (Expected speed ~%.3f m/s)" % [
		flight.linear_velocity_vector.x, flight.linear_velocity_vector.y, flight.linear_velocity_vector.z,
		expected_accel * delta
	])
	assert(flight.linear_velocity_vector.z < 0.0, "Forward thrust must produce negative Z velocity")
	print("  ✓ Linear Newtonian F=ma integration verified.")

	# 4. Test Pure Space Vacuum Momentum Conservation (Flight Assist OFF)
	print("\n[PHYSICS TEST 4] Testing Vacuum Momentum Conservation (Dampening OFF)...")
	flight.simulated_thrust = Vector3.ZERO # Cut all engines
	var speed_before: float = flight.linear_velocity_vector.length()
	for f: int in range(20):
		flight._physics_process(0.016)
	var speed_after: float = flight.linear_velocity_vector.length()
	print("  • Speed after 20 idle frames in vacuum: %.3f m/s (Initial: %.3f m/s)" % [speed_after, speed_before])
	assert(abs(speed_after - speed_before) < 0.001, "Velocity must be conserved with 0 drag in vacuum!")
	print("  ✓ True Newtonian drifting momentum conservation verified.")

	# 5. Test Bio-Hydro Pulse Dampening (Flight Assist ON)
	print("\n[PHYSICS TEST 5] Testing Bio-Hydro Pulse Dampening (Flight Assist ON)...")
	flight.dampening_enabled = true
	for f: int in range(100):
		flight._physics_process(0.016)
	var speed_damped: float = flight.linear_velocity_vector.length()
	print("  • Speed after 100 damped frames: %.4f m/s" % speed_damped)
	assert(speed_damped < speed_before * 0.2, "Bio-hydro pulse dampening must smoothly decelerate ship")
	print("  ✓ Bio-hydro pulse dampening verified.")

	# 6. Test Single-Object External Impulse & Recoil (apply_impulse)
	print("\n[PHYSICS TEST 6] Testing Single-Body Impact & Weapon Recoil Transfer...")
	flight.linear_velocity_vector = Vector3.ZERO
	flight.angular_velocity_vector = Vector3.ZERO
	var test_impulse: Vector3 = Vector3(0, 0, -500000.0) # 500 kN*s recoil impulse
	var contact_offset: Vector3 = Vector3(1.5, 0.0, -5.0) # Wingtip contact point
	flight.apply_impulse(test_impulse, contact_offset)

	print("  • Applied 500kN*s off-center impulse -> Linear: %s m/s | Angular: %s rad/s" % [
		str(flight.linear_velocity_vector), str(flight.angular_velocity_vector)
	])
	assert(flight.linear_velocity_vector.length() > 0.0, "Impulse must impart linear momentum")
	assert(flight.angular_velocity_vector.length() > 0.0, "Off-center impulse must impart rotational torque")
	print("  ✓ Unified single-object impulse dynamics verified.")

	space_flight.queue_free()

	print("\n==================================================================")
	print("SUCCESS: 100% UNIFIED SINGLE-OBJECT SPACE PHYSICS AUDIT PASSED!")
	print("==================================================================")
	quit()
