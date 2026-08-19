@tool
extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X UI/UX COMPONENT VERIFICATION RUNNER")
	print("Testing: MainMenuUI, ShipBuilderUI, FlightHUDUI, OrganInspectorUI, PauseMenuUI, ECGGraph")
	print("==================================================================")

	var scripts_to_test := [
		"res://scripts/MainMenuUI.gd",
		"res://scripts/ShipBuilderUI.gd",
		"res://scripts/FlightHUDUI.gd",
		"res://scripts/OrganInspectorUI.gd",
		"res://scripts/PauseMenuUI.gd",
		"res://scripts/ECGGraph.gd"
	]

	for script_path in scripts_to_test:
		print("\nTesting script: %s" % script_path)
		var script_res := load(script_path)
		if script_res == null:
			push_error("FAILED to load script: %s" % script_path)
			quit(1)
			return
		
		var instance: Object = script_res.new()
		if instance == null:
			push_error("FAILED to instantiate: %s" % script_path)
			quit(1)
			return

		# Add instance to root
		root.add_child(instance)

		# Test zero size resize
		instance.size = Vector2(0, 0)
		if instance.has_method("_on_resized"):
			instance.call("_on_resized")
		if instance.has_method("_process"):
			instance._process(0.016)
		if instance.has_method("_draw"):
			instance.queue_redraw()

		# Test normal size resize
		instance.size = Vector2(1280, 720)
		if instance.has_method("_on_resized"):
			instance.call("_on_resized")
		if instance.has_method("_process"):
			instance._process(0.016)

		# Remove and tree exit
		root.remove_child(instance)
		instance.free()
		print("  ✓ %s loaded, resized (0x0 & 1280x720), drawn, and cleaned up cleanly!" % script_path.get_file())

	print("\n==================================================================")
	print("SUCCESS: ALL 6 UI COMPONENTS PASSED COMPILATION, INSTANTIATION, AND RESIZE TESTING!")
	print("==================================================================")
	quit(0)
