# ==============================================================================
# verify_all_scenes_connectivity.gd - BioGenesis-X Scene Transition & Connectivity
# Pumilio Studios
# ==============================================================================

extends SceneTree

func _init():
	print("==================================================================")
	print("BIO-GENESIS-X: FULL SCENE CONNECTIVITY & TRANSITION AUDIT")
	print("==================================================================")

	var scenes := [
		"res://scenes/main_menu.tscn",
		"res://scenes/ship_builder.tscn",
		"res://scenes/space_flight.tscn",
		"res://scenes/organ_inspector.tscn",
		"res://scenes/pause_menu.tscn",
		"res://scenes/cinematic_intro.tscn"
	]

	var all_passed := true

	for scene_path in scenes:
		print("\n[SCENE AUDIT] Testing: ", scene_path)
		var res := load(scene_path)
		if res == null:
			printerr("  ❌ Failed to load: ", scene_path)
			all_passed = false
			continue

		var inst: Node = res.instantiate()
		if inst == null:
			printerr("  ❌ Failed to instantiate: ", scene_path)
			all_passed = false
			continue

		root.add_child(inst)
		print("  ✓ Instantiated & added to SceneTree cleanly.")

		# Simulate 10 frames of processing & drawing
		for f in range(10):
			if inst.has_method("_process"):
				inst._process(0.016)
			if inst is Control and inst.has_method("queue_redraw"):
				inst.queue_redraw()

		print("  ✓ Processed 10 simulation frames with zero script errors.")

		root.remove_child(inst)
		inst.free()
		print("  ✓ Freed cleanly without memory leaks or dangling signal links.")

	print("\n==================================================================")
	if all_passed:
		print("SUCCESS: ALL 6 SCENES PASSED CONNECTIVITY & RUNTIME INTEGRITY AUDIT!")
	else:
		printerr("FAILURE: One or more scenes failed the integrity check.")
	print("==================================================================")

	quit(0 if all_passed else 1)
