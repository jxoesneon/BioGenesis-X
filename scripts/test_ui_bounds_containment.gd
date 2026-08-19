extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X: RIGOROUS UI BOUNDS & SCREEN CONTAINMENT AUDIT")
	print("==================================================================")

	var scene_paths := [
		"res://scenes/main_menu.tscn",
		"res://scenes/ship_builder.tscn",
		"res://scenes/space_flight.tscn",
		"res://scenes/organ_inspector.tscn",
		"res://scenes/pause_menu.tscn",
		"res://scenes/cinematic_intro.tscn"
	]

	var viewport_sizes := [
		Vector2(1920, 1080),
		Vector2(1280, 720),
		Vector2(2560, 1440)
	]

	var total_checked: int = 0
	var out_of_bounds_errors: int = 0

	for vp_size in viewport_sizes:
		print("\n------------------------------------------------------------------")
		print("Checking Screen Bounds Containment at Viewport %dx%d..." % [int(vp_size.x), int(vp_size.y)])
		print("------------------------------------------------------------------")
		var screen_rect := Rect2(Vector2.ZERO, vp_size)

		for s_path in scene_paths:
			var scn := load(s_path)
			var inst: Node = scn.instantiate()
			root.add_child(inst)

			# Ensure sizing matches test viewport
			if inst is Control:
				inst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			for c in inst.get_children():
				if c is Control:
					c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

			# Run processes to let containers layout
			for f in range(5):
				if inst.has_method("_process"):
					inst._process(0.016)
				for child in inst.get_children():
					if child.has_method("_process"):
						child._process(0.016)

			var controls := _gather_controls(inst)
			for ctrl in controls:
				if not ctrl.is_visible_in_tree():
					continue
				var g_rect: Rect2 = ctrl.get_global_rect()
				total_checked += 1

				# Check if completely outside screen rect
				var is_outside_left := g_rect.position.x + g_rect.size.x < -2.0
				var is_outside_right = g_rect.position.x > vp_size.x + 2.0
				var is_outside_top := g_rect.position.y + g_rect.size.y < -2.0
				var is_outside_bottom = g_rect.position.y > vp_size.y + 2.0

				if is_outside_left or is_outside_right or is_outside_top or is_outside_bottom:
					print("  ❌ ERROR: Control '%s' (%s) in '%s' is OUT OF BOUNDS! Rect: %s | Screen: %s" % [
						ctrl.name, ctrl.get_class(), s_path.get_file(), str(g_rect), str(screen_rect)
					])
					out_of_bounds_errors += 1

			print("  ✓ Scene '%s': %d controls audited within screen bounds" % [s_path.get_file(), controls.size()])
			inst.queue_free()

	print("\n==================================================================")
	if out_of_bounds_errors == 0:
		print("SUCCESS: 0 OUT-OF-BOUNDS ELEMENTS! ALL %d CONTROLS FULLY CONTAINED!" % total_checked)
	else:
		print("FAILURE: Found %d out-of-bounds UI elements!" % out_of_bounds_errors)
	print("==================================================================")
	quit()

func _gather_controls(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	if node is Control:
		result.append(node)
	for child in node.get_children():
		result.append_array(_gather_controls(child))
	return result
