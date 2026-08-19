# res://scripts/playtest_ship_builder.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# playtest_ship_builder.gd - Headless Playtest & Quality Assurance Verification
# Pumilio Studios - 3D Ship Builder & Modder Playtester
# ==============================================================================

@tool
extends SceneTree

const ProceduralBioMesh = preload("res://scripts/ProceduralBioMesh.gd")
const ShipBuilderUI = preload("res://scripts/ShipBuilderUI.gd")
const ShipExporter = preload("res://scripts/ShipExporter.gd")

func _init() -> void:
	print("==================================================================")
	print("PUMILIO STUDIOS: 3D SHIP BUILDER & MESH CUSTOMIZATION PLAYTEST")
	print("==================================================================")

	# 1. Load and instantiate res://scenes/ship_builder.tscn
	var scene_res := load("res://scenes/ship_builder.tscn")
	if scene_res == null:
		push_error("PLAYTEST FAILED: Unable to load res://scenes/ship_builder.tscn")
		quit(1)
		return

	var ship_builder_instance: Node = scene_res.instantiate()
	root.add_child(ship_builder_instance)
	print("✓ Successfully loaded and instantiated res://scenes/ship_builder.tscn")

	# Locate ProceduralBioMesh and ShipBuilderUI nodes from scene hierarchy
	var bio_mesh: Node = ship_builder_instance.get_node_or_null("ProceduralBioMesh")
	var builder_ui: Control = ship_builder_instance.get_node_or_null("UI") as Control

	if bio_mesh == null:
		print("Creating standalone ProceduralBioMesh instance...")
		bio_mesh = ProceduralBioMesh.new()
		ship_builder_instance.add_child(bio_mesh)
	else:
		print("✓ Found ProceduralBioMesh in ship_builder.tscn scene tree")

	if builder_ui == null:
		print("Creating standalone ShipBuilderUI instance...")
		builder_ui = ShipBuilderUI.new()
		ship_builder_instance.add_child(builder_ui)
	else:
		print("✓ Found ShipBuilderUI in ship_builder.tscn scene tree")

	# The 5 standard archetypes to playtest
	var archetypes := ["interceptor", "frigate", "dreadnought", "carrier", "leviathan"]

	# Slider test matrix across allowed ranges:
	# - segments: 4 to 20
	# - length: 5 to 50
	# - chitin density: 1 to 10 (0.1 to 1.0 density factor)
	# - eye pods: 2 to 12
	var slider_test_cases := [
		{ "label": "Interceptor (Min Bounds)",   "segments": 4,  "length": 5.0,  "chitin": 1.0,  "eyepods": 2 },
		{ "label": "Frigate (Mid-Low Bounds)",   "segments": 8,  "length": 15.0, "chitin": 3.5,  "eyepods": 4 },
		{ "label": "Dreadnought (Standard)",     "segments": 12, "length": 25.0, "chitin": 6.0,  "eyepods": 6 },
		{ "label": "Carrier (High Bounds)",      "segments": 16, "length": 38.0, "chitin": 8.5,  "eyepods": 9 },
		{ "label": "Leviathan (Max Bounds)",     "segments": 20, "length": 50.0, "chitin": 10.0, "eyepods": 12 }
	]

	var results_summary: Array[Dictionary] = []

	# 2. Cycle through each archetype and apply customized slider values
	for i in range(archetypes.size()):
		var arch = archetypes[i]
		var case = slider_test_cases[i]

		print("\n------------------------------------------------------------------")
		print("Playtesting Archetype [%d/5]: '%s' | Custom Preset: %s" % [i + 1, arch.to_upper(), case["label"]])
		print("------------------------------------------------------------------")

		# Test mutating UI Sliders directly
		if builder_ui.get("slider_segments") != null:
			var s_seg = builder_ui.get("slider_segments")
			s_seg.set_value_no_signal(case["segments"])
			builder_ui.call("_on_segments_changed", case["segments"])
		if builder_ui.get("slider_length") != null:
			var s_len = builder_ui.get("slider_length")
			s_len.set_value_no_signal(case["length"])
			builder_ui.call("_on_length_changed", case["length"])
		if builder_ui.get("slider_chitin") != null:
			var s_chi = builder_ui.get("slider_chitin")
			s_chi.set_value_no_signal(case["chitin"])
			builder_ui.call("_on_chitin_changed", case["chitin"])
		if builder_ui.get("slider_eyepods") != null:
			var s_eye = builder_ui.get("slider_eyepods")
			s_eye.set_value_no_signal(case["eyepods"])
			builder_ui.call("_on_eyepods_changed", case["eyepods"])

		print("  • Mutated UI Sliders -> Segments: %d, Length: %.1fm, Chitin Density: %.1f, Eye Pods: %d" % [
			case["segments"], case["length"], case["chitin"], case["eyepods"]
		])

		# Rebuild ProceduralBioMesh and measure builder responsiveness
		var config := {
			"archetype": arch,
			"segments": case["segments"],
			"length": case["length"],
			"chitin_density": case["chitin"] / 10.0,
			"eye_pod_count": case["eyepods"],
			"scale": 1.0
		}

		var start_time := Time.get_ticks_usec()
		bio_mesh.call("rebuild_ship_mesh", config)
		var rebuild_ms := (Time.get_ticks_usec() - start_time) / 1000.0

		var mesh = bio_mesh.get("mesh")
		var vert_count := 0
		var face_count := 0
		var surf_count := 0

		if mesh:
			surf_count = mesh.get_surface_count()
			for s in range(surf_count):
				var arrays = mesh.surface_get_arrays(s)
				if not arrays.is_empty():
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					vert_count += verts.size()
					var raw_indices = arrays[Mesh.ARRAY_INDEX]
					if raw_indices != null and raw_indices is PackedInt32Array and (raw_indices as PackedInt32Array).size() > 0:
						face_count += (raw_indices as PackedInt32Array).size() / 3
					else:
						face_count += verts.size() / 3

		var aabb = mesh.get_aabb() if mesh else AABB()

		print("  • Builder Responsiveness: %.2f ms (Mesh Generation)" % rebuild_ms)
		print("  • Visual Customizer Feedback: %d surfaces, %d vertices, %d faces" % [surf_count, vert_count, face_count])
		print("  • Mesh Bounds (AABB): Vector3(%.2f, %.2f, %.2f)" % [aabb.size.x, aabb.size.y, aabb.size.z])

		# 3. Trigger .OBJ model export for customized ship
		var export_filename := "user://exports/playtest_%s_customized.obj" % arch
		var export_start := Time.get_ticks_usec()
		var err := ShipExporter.export_to_obj(bio_mesh, export_filename, false)
		var export_ms := (Time.get_ticks_usec() - export_start) / 1000.0

		var file_size_bytes := 0
		var absolute_export_path := ProjectSettings.globalize_path(export_filename)
		if FileAccess.file_exists(export_filename):
			var file := FileAccess.open(export_filename, FileAccess.READ)
			if file:
				file_size_bytes = file.get_length()
				file.close()

		if err == OK and file_size_bytes > 0:
			print("  ✓ OBJ Model Exported Successfully: '%s' (%.2f KB in %.2f ms)" % [
				export_filename, float(file_size_bytes) / 1024.0, export_ms
			])
		else:
			push_error("  ❌ OBJ Model Export Failed for archetype '%s' (Error %d)" % [arch, err])

		results_summary.append({
			"archetype": arch,
			"preset": case["label"],
			"segments": case["segments"],
			"length": case["length"],
			"chitin_density": case["chitin"],
			"eyepods": case["eyepods"],
			"rebuild_ms": rebuild_ms,
			"vertices": vert_count,
			"faces": face_count,
			"surfaces": surf_count,
			"export_path": absolute_export_path,
			"file_size_kb": float(file_size_bytes) / 1024.0,
			"export_ms": export_ms,
			"success": (err == OK and file_size_bytes > 0)
		})

	# 4. Generate Final Playtest Report
	print("\n==================================================================")
	print("PUMILIO STUDIOS - PLAYTEST SUMMARY & QA TELEMETRY REPORT")
	print("==================================================================")
	print("%-12s | %-12s | %-8s | %-8s | %-10s | %-10s" % [
		"ARCHETYPE", "REBUILD TIME", "VERTS", "FACES", "OBJ SIZE", "STATUS"
	])
	print("------------------------------------------------------------------")
	var total_rebuild_ms := 0.0
	var total_export_ms := 0.0
	var all_passed := true

	for res in results_summary:
		total_rebuild_ms += res["rebuild_ms"]
		total_export_ms += res["export_ms"]
		if not res["success"]:
			all_passed = false
		var status_str := "PASS ✓" if res["success"] else "FAIL ❌"
		print("%-12s | %8.2f ms   | %8d | %8d | %7.1f KB   | %-10s" % [
			res["archetype"],
			res["rebuild_ms"],
			res["vertices"],
			res["faces"],
			res["file_size_kb"],
			status_str
		])
	print("------------------------------------------------------------------")
	print("Total Rebuild Time: %.2f ms | Avg Rebuild per Ship: %.2f ms" % [total_rebuild_ms, total_rebuild_ms / archetypes.size()])
	print("Total Export Time:  %.2f ms | Avg Export per Ship:  %.2f ms" % [total_export_ms, total_export_ms / archetypes.size()])
	print("==================================================================")

	# Clean up scene tree
	root.remove_child(ship_builder_instance)
	ship_builder_instance.free()

	if all_passed:
		print("✓ ALL 5 ARCHETYPES CUSTOMIZED, REBUILT, AND EXPORTED CLEANLY!")
		quit(0)
	else:
		push_error("❌ PLAYTEST COMPLETED WITH ERRORS!")
		quit(1)
