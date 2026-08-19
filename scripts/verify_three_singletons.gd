@tool
extends SceneTree

func _init() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X ENGINE ARCHITECTURE VERIFICATION")
	print("Testing Core Scripts: BioManager.gd, OrganTelemetry.gd, ShipExporter.gd")
	print("==================================================================")
	
	# 1. Test BioManager.gd
	print("\n[1/3] Testing BioManager.gd...")
	var BioManagerScript := load("res://scripts/BioManager.gd")
	if BioManagerScript == null:
		push_error("Failed to load BioManager.gd")
		quit(1)
		return
	
	var bio_mgr: Object = BioManagerScript.new()
	bio_mgr._ready()
	print("  ✓ BioManager initialized successfully.")
	print("  ✓ Default Game Mode: %s" % bio_mgr.get_game_mode_name())
	
	var initial_config = bio_mgr.get_ship_config()
	print("  ✓ Active Archetype: %s" % initial_config.get("archetype_name"))
	print("  ✓ Classification: %s" % initial_config.get("classification"))
	print("  ✓ Segment Count: %d | Length: %.1f m" % [initial_config.get("segment_count"), initial_config.get("length")])
	
	var archetypes = bio_mgr.get_archetype_names()
	print("  ✓ Catalog size: %d archetypes loaded." % archetypes.size())
	for arch_name in archetypes:
		var loaded = bio_mgr.load_archetype(arch_name)
		if loaded:
			print("    - Successfully loaded archetype: '%s'" % arch_name)
		else:
			push_error("    - Failed to load archetype: '%s'" % arch_name)
			quit(1)
			return

	# 2. Test OrganTelemetry.gd
	print("\n[2/3] Testing OrganTelemetry.gd...")
	var OrganTelemetryScript := load("res://scripts/OrganTelemetry.gd")
	if OrganTelemetryScript == null:
		push_error("Failed to load OrganTelemetry.gd")
		quit(1)
		return

	var telemetry = OrganTelemetryScript.new()
	telemetry._ready()
	telemetry.set_ship_kinematics(220.0, 4.2, 0.15)
	telemetry._process(0.016)
	
	var snap = telemetry.get_telemetry_snapshot()
	print("  ✓ OrganTelemetry snapshot retrieved:")
	print("    - Heart Rate: %.1f BPM" % snap.get("heart_rate_bpm"))
	print("    - Oxygenation Yield: %.1f L/min" % snap.get("oxygenation_yield_lpm"))
	print("    - Hemolymph Pressure: %.2f Bar" % snap.get("hemolymph_pressure_bar"))
	print("    - Nanite Repair Rate: %.2f m³/s" % snap.get("nanite_repair_rate"))
	print("    - Radiotrophic Absorption: %.1f Gy/hr" % snap.get("radiotrophic_absorption_gy_hr"))
	print("    - Neural Sync Rate: %.2f%%" % snap.get("neural_sync_rate"))
	print("    - ECG Sample Value: %.4f" % snap.get("current_ecg_sample"))
	
	var ecg_buf = telemetry.get_ecg_buffer()
	print("  ✓ Real-time ECG buffer generated: %d samples." % ecg_buf.size())

	# 3. Test ShipExporter.gd
	print("\n[3/3] Testing ShipExporter.gd...")
	var ShipExporterScript := load("res://scripts/ShipExporter.gd")
	if ShipExporterScript == null:
		push_error("Failed to load ShipExporter.gd")
		quit(1)
		return

	var box_mesh := BoxMesh.new()
	var export_path := "user://exports/ship_export.obj"
	var err = ShipExporterScript.export_to_obj(box_mesh, export_path)
	if err == OK:
		print("  ✓ ShipExporter successfully exported BoxMesh to '%s'." % export_path)
	else:
		push_error("  - ShipExporter export failed with code: %d" % err)
		quit(1)
		return

	print("\n==================================================================")
	print("SUCCESS: ALL 3 CORE SINGLETON SCRIPTS COMPILED & EXECUTED CLEANLY!")
	print("==================================================================")
	quit(0)
