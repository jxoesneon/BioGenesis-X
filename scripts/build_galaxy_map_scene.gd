@tool
extends SceneTree

func _init():
	print("Building galaxy_map.tscn...")
	var packed_scene := load("res://scenes/galaxy_map.tscn") as PackedScene
	if not packed_scene:
		print("ERROR: Could not load galaxy_map.tscn")
		quit(1)
		return

	var root := packed_scene.instantiate()
	var manager := root.get_node("GalaxyMapManager")
	var ui_layer := root.get_node("UI")
	
	if not root.has_node("GalaxyMapVisuals"):
		var visuals: Node = load("res://scripts/GalaxyMapVisuals.gd").new()
		visuals.name = "GalaxyMapVisuals"
		root.add_child(visuals)
		visuals.owner = root
		
		# Connect manager signals to visuals
		if manager.has_signal("stars_updated") and visuals.has_method("generate_stars"):
			manager.connect("stars_updated", Callable(visuals, "generate_stars"))

	if not ui_layer.has_node("GalaxyMapUI"):
		var ui = load("res://scripts/GalaxyMapUI.gd").new()
		ui.name = "GalaxyMapUI"
		ui_layer.add_child(ui)
		ui.owner = root
		
		# Connect manager signals to UI
		if manager.has_signal("system_selected") and ui.has_method("display_system_info"):
			manager.connect("system_selected", Callable(ui, "display_system_info"))
			
	var new_scene := PackedScene.new()
	new_scene.pack(root)
	var err := ResourceSaver.save(new_scene, "res://scenes/galaxy_map.tscn")
	if err == OK:
		print("Successfully updated galaxy_map.tscn")
		quit(0)
	else:
		print("ERROR: Failed to save scene: ", err)
		quit(1)
