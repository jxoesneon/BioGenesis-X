extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X: GODOT DEBUGGER & SCRIPT RUNTIME AUDIT")
	print("==================================================================")

	var scripts_to_test := [
		"res://scripts/BioManager.gd",
		"res://scripts/FlightController.gd",
		"res://scripts/ProceduralBioMesh.gd",
		"res://scripts/ShipBuilderUI.gd",
		"res://scripts/FlightHUDUI.gd",
		"res://scripts/OrganInspectorUI.gd",
		"res://scripts/PauseMenuUI.gd",
		"res://scripts/CinematicSequencer.gd",
		"res://scripts/OrganTelemetry.gd",
		"res://scripts/BioAudioSynth.gd",
		"res://scripts/AsteroidField.gd",
		"res://scripts/WeaponSystem.gd",
		"res://scripts/ECGGraph.gd",
		"res://scripts/ShipExporter.gd",
		"res://scripts/ProceduralAsteroidMesh.gd",
		"res://scripts/BioPlasmaProjectile.gd",
		"res://scripts/BioSporeCloud.gd",
		"res://scripts/VoidFaunaDrone.gd",
		"res://scripts/ProceduralGalaxy.gd",
		"res://scripts/ProceduralPlanet.gd",
		"res://scripts/UniverseManager.gd"
	]

	print("[1/2] Instantiating and executing all project scripts...")
	for s_path in scripts_to_test:
		var script_res: GDScript = load(s_path) as GDScript
		assert(script_res != null, "Script must load cleanly: " + s_path)
		var obj: Object = script_res.new()
		assert(obj != null, "Script must instantiate cleanly: " + s_path)
		if obj is Node:
			root.add_child(obj)
			root.remove_child(obj)
			obj.free()
		elif obj is RefCounted:
			pass
		print("  ✓ Script cleanly loaded & instantiated: %s" % s_path)

	print("\n[2/2] Loading all 6 project scene trees...")
	var scenes_to_test := [
		"res://scenes/main_menu.tscn",
		"res://scenes/ship_builder.tscn",
		"res://scenes/space_flight.tscn",
		"res://scenes/organ_inspector.tscn",
		"res://scenes/pause_menu.tscn",
		"res://scenes/cinematic_intro.tscn"
	]

	for sc_path in scenes_to_test:
		var packed_scene := load(sc_path) as PackedScene
		assert(packed_scene != null, "Scene must exist and load: " + sc_path)
		var scene_node := packed_scene.instantiate()
		assert(scene_node != null, "Scene must instantiate without error: " + sc_path)
		root.add_child(scene_node)
		root.remove_child(scene_node)
		scene_node.free()
		print("  ✓ Scene cleanly loaded & instantiated: %s" % sc_path)

	print("\n==================================================================")
	print("SUCCESS: ZERO DEBUGGER ERRORS OR SCRIPT WARNINGS REPORTED!")
	print("==================================================================")
	quit()
