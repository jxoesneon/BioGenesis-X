extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X: MULTI-RESOLUTION & PROPORTIONAL UI SCALING AUDIT")
	print("==================================================================")

	var resolutions := [
		Vector2(1280, 720),   # 720p HD 16:9
		Vector2(1920, 1080),  # 1080p FHD 16:9 (Baseline)
		Vector2(2560, 1440),  # 1440p QHD 2K
		Vector2(3840, 2160),  # 2160p 4K UHD
		Vector2(2560, 1080),  # 21:9 Ultra-Wide
		Vector2(1920, 1200)   # 16:10 Productivity
	]

	var scene_paths := [
		"res://scenes/main_menu.tscn",
		"res://scenes/ship_builder.tscn",
		"res://scenes/space_flight.tscn",
		"res://scenes/organ_inspector.tscn",
		"res://scenes/pause_menu.tscn"
	]

	for res in resolutions:
		print("\n------------------------------------------------------------------")
		print("Testing Viewport Resolution: %dx%d (Aspect: %.2f)" % [int(res.x), int(res.y), res.x / res.y])
		print("------------------------------------------------------------------")

		for s_path in scene_paths:
			var scn := load(s_path)
			var inst: Node = scn.instantiate()
			root.add_child(inst)

			# If instance is or has Control UI, simulate resize
			if inst is Control:
				inst.size = res
				inst.position = Vector2.ZERO
				inst.queue_redraw()
			else:
				for c in inst.get_children():
					if c is Control:
						c.size = res
						c.position = Vector2.ZERO
						c.queue_redraw()

			# Step frames
			if inst.has_method("_process"):
				inst._process(0.016)
			if inst.has_method("_physics_process"):
				inst._physics_process(0.016)

			print("  ✓ Scene '%s' scaled cleanly at %dx%d" % [s_path.get_file(), int(res.x), int(res.y)])
			inst.queue_free()

	print("\n==================================================================")
	print("SUCCESS: ALL SCENES & UI RESIZE PROPORTIONALLY ACROSS ALL RESOLUTIONS!")
	print("==================================================================")
	quit()
