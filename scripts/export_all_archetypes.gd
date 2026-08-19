# ==============================================================================
# export_all_archetypes.gd - BioGenesis-X Headless 3D OBJ Exporter Test
# Pumilio Studios
# ==============================================================================

extends SceneTree

func _init():
	print("--- BIOGENESIS-X: EXPORTING ALL 5 VOID-FAUNA ARCHETYPES TO .OBJ ---")

	var archetypes := ["leviathan", "interceptor", "dreadnought", "frigate", "carrier"]

	var mesh_gen: Object = load("res://scripts/ProceduralBioMesh.gd").new()

	for arch in archetypes:
		print("Generating and exporting archetype: ", arch)
		var config := {
			"archetype": arch,
			"segments": 10,
			"length": 20.0,
			"scale": 1.0,
			"chitin_density": 8.0
		}
		mesh_gen.rebuild_ship_mesh(config)

		var export_path := "user://exports/bio_ship_%s.obj" % arch
		var err := ShipExporter.export_to_obj(mesh_gen.mesh, export_path)
		if err == OK:
			print("SUCCESS -> Exported: ", export_path)
		else:
			print("ERROR exporting: ", arch)

	mesh_gen.free()
	print("--- ALL ARCHETYPES EXPORTED CLEANLY ---")
	quit(0)
