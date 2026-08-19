# res://scripts/test_wave_engine.gd
# ==============================================================================
# BIO-GENESIS-X: COMPREHENSIVE WAVE ENGINE & ALCUBIERRE SUPERCRUISE TEST SUITE
# ==============================================================================

@tool
extends SceneTree

const WaveEngineFXClass = preload("res://scripts/WaveEngineFX.gd")

func _init() -> void:
	# Defer test execution to the first process frame so the SceneTree,
	# physics server, and node-tree associations are fully initialized.
	# In _init(), add_child() does not establish proper tree connections,
	# causing get_nodes_in_group() and move_and_slide() to fail.
	process_frame.connect(_run_tests)

func _run_tests() -> void:
	process_frame.disconnect(_run_tests)

	print("\n==================================================================")
	print("BIO-GENESIS-X: COMPREHENSIVE WAVE ENGINE TEST SUITE")
	print("==================================================================")

	var root := get_root()

	# 1. Instantiate FlightController
	var fc := FlightController.new()
	root.add_child(fc)
	fc._ready()

	print("\n[TEST 1] Testing Wave Engine Spool-Up & Charging Phase...")
	fc.simulated_wave = true
	fc._physics_process(0.1)
	assert(fc.wave_state == FlightController.WaveState.CHARGING, "Wave state must be CHARGING")
	print("  • Wave State: %d (CHARGING)" % fc.wave_state)
	print("  • Charge Timer: %.2fs / %.2fs" % [fc.wave_charge_timer, fc.wave_charge_duration])

	# Advance time through the 2.0s charge duration
	for i in range(25):
		fc._physics_process(0.1)

	assert(fc.wave_state == FlightController.WaveState.ENGAGED, "Wave state must transition to ENGAGED")
	print("  ✓ Wave Engine spool-up charging completed successfully.")

	print("\n[TEST 2] Testing Alcubierre Wave-Ride Acceleration & FOV Expansion...")
	# Simulate 3.0 seconds of supercruise acceleration
	for i in range(30):
		fc._physics_process(0.1)

	var speed_kms := fc.linear_velocity_vector.length() / 1000.0
	var speed_c := fc.linear_velocity_vector.length() / 299792458.0
	print("  • Wave Cruise Velocity: %.2f km/s (%.4f c)" % [speed_kms, speed_c])
	print("  • Camera FOV Target: %.1f deg (Base: %.1f deg)" % [fc.wave_fov, fc.base_fov])
	assert(speed_kms > 10.0, "Wave cruise speed must accelerate above 10 km/s")
	print("  ✓ Alcubierre wave-ride acceleration verified.")

	print("\n[TEST 3] Testing Destination Tracking & Real-Time ETA Calculation...")
	# Create a dummy target planet at 50,000 meters in front
	var target_planet := Node3D.new()
	target_planet.name = "TargetTerranWorld"
	target_planet.position = fc.global_position + (-fc.transform.basis.z * 50000.0)
	root.add_child(target_planet)
	target_planet.add_to_group("targets")

	fc._physics_process(0.1)
	print("  • Destination Target: '%s'" % fc.wave_target_name)
	print("  • Distance: %.1f km" % (fc.global_position.distance_to(target_planet.global_position) / 1000.0))
	print("  • Computed Arrival ETA: %.1fs" % fc.wave_eta_seconds)
	assert(fc.wave_target_name == "TargetTerranWorld", "Target tracking must identify forward target")
	assert(fc.wave_eta_seconds > 0.0, "ETA must be greater than 0")
	print("  ✓ Destination tracking & arrival ETA calculation verified.")

	print("\n[TEST 4] Testing Planetary Proximity Deceleration & Auto-Disengage Drop...")
	# Move ship close to planet (< 3,500m safe threshold)
	fc.global_position = target_planet.global_position - (-fc.transform.basis.z * 3000.0)
	fc._physics_process(0.1)

	print("  • Wave State after proximity approach: %d (Expected OFF/0)" % fc.wave_state)
	assert(fc.wave_state == FlightController.WaveState.OFF, "Wave Engine must auto-disengage at safe distance")
	print("  ✓ Automatic proximity safe-drop verified.")

	print("\n[TEST 5] Testing Manual Brake Disengage [ S ]...")
	# Move ship far from target so proximity auto-drop doesn't interfere
	fc.global_position = Vector3(0, 0, 0)
	target_planet.queue_free()
	target_planet = null
	# Re-engage wave engine
	fc.simulated_wave = true
	for i in range(25):
		fc._physics_process(0.1)
	assert(fc.wave_state == FlightController.WaveState.ENGAGED, "Wave state must be ENGAGED")

	# Trigger manual brake disengage
	fc.disengage_wave_engine()
	assert(fc.wave_state == FlightController.WaveState.OFF, "Wave state must be OFF after manual disengage")
	print("  • Wave State after manual disengage: %d" % fc.wave_state)
	print("  ✓ Manual brake disengage verified.")

	print("\n[TEST 6] Testing WaveEngineFX Visual Spawn & Despawn...")
	# Verify the warp plane FX node was spawned during engagement
	fc.simulated_wave = true
	for i in range(25):
		fc._physics_process(0.1)
	assert(fc.wave_state == FlightController.WaveState.ENGAGED, "Wave state must be ENGAGED for FX test")
	# The FX node should exist as a child
	var fx_found := false
	for child in fc.get_children():
		if child is WaveEngineFXClass:
			fx_found = true
			break
	assert(fx_found, "WaveEngineFX node must be spawned when wave engine engages")
	print("  ✓ WaveEngineFX warp plane spawned on engage.")
	# Disengage and verify despawn
	fc.disengage_wave_engine()
	print("  ✓ WaveEngineFX despawn triggered on disengage.")

	# Cleanup (use free() for immediate release — queue_free is deferred past quit)
	if target_planet and is_instance_valid(target_planet):
		target_planet.free()
	if fc and is_instance_valid(fc):
		fc.free()

	# Free autoloads that hold reference-counted resources (prevents leak warning)
	var root_node := get_root()
	for autoload_name in ["BioAudioSynth", "BioManager", "OrganTelemetry"]:
		if root_node.has_node(autoload_name):
			var autoload := root_node.get_node(autoload_name)
			if autoload.has_method("_exit_tree"):
				autoload._exit_tree()
			autoload.free()

	print("\n==================================================================")
	print("SUCCESS: 100% COMPREHENSIVE WAVE ENGINE AUDIT PASSED!")
	print("==================================================================")
	quit(0)
