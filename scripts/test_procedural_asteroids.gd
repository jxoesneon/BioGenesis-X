# res://scripts/test_procedural_asteroids.gd
# ==============================================================================
# BioGenesis-X - AAA+ Procedural Asteroid & Rock Generation Test Suite
# ==============================================================================

extends SceneTree

const ProceduralAsteroidMeshClass = preload("res://scripts/ProceduralAsteroidMesh.gd")
const AsteroidFieldClass = preload("res://scripts/AsteroidField.gd")

func _init() -> void:
	print("\n==================================================================")
	print("BIO-GENESIS-X: AAA+ PROCEDURAL ASTEROID & ROCK ENGINE AUDIT")
	print("==================================================================")

	# -------------------------------------------------------------------------
	# TEST 1: Procedural Asteroid Archetype Generation & Geometry Verification
	# -------------------------------------------------------------------------
	print("\n[TEST 1] Testing 4 Celestial Asteroid Archetypes...")
	
	var archetypes := [
		{"name": "Carbonaceous C-Type", "type": ProceduralAsteroidMeshClass.AsteroidArchetype.CARBONACEOUS_C_TYPE},
		{"name": "Silicate S-Type", "type": ProceduralAsteroidMeshClass.AsteroidArchetype.SILICATE_S_TYPE},
		{"name": "Contact Binary Spindle", "type": ProceduralAsteroidMeshClass.AsteroidArchetype.CONTACT_BINARY},
		{"name": "Rubble Regolith Pile", "type": ProceduralAsteroidMeshClass.AsteroidArchetype.RUBBLE_REGOLITH}
	]

	for item in archetypes:
		var gen := ProceduralAsteroidMeshClass.new()
		gen.archetype = item["type"]
		gen.base_radius = 8.0
		gen.subdivision_level = 2
		gen.generate_collision_shape = false

		var mesh_res := gen.rebuild_asteroid(42)
		assert(mesh_res != null, "Procedural asteroid mesh must generate successfully")
		assert(mesh_res.get_surface_count() > 0, "Procedural asteroid must have at least 1 surface")
		
		var arrays := mesh_res.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

		print("  • Archetype '%s': Vertices=%d | Normals=%d | UVs=%d" % [
			item["name"], verts.size(), norms.size(), uvs.size()
		])

		assert(verts.size() > 0, "Vertex count must be > 0")
		assert(norms.size() == verts.size(), "Each vertex must have a calculated normal")

		# Check for non-spherical deformation & domain warping
		var min_r := 999.0
		var max_r := 0.0
		for v in verts:
			var r := v.length()
			min_r = min(min_r, r)
			max_r = max(max_r, r)

		print("    - Radius variation: Min=%.2fm | Max=%.2fm (Aspect ratio: %.2f)" % [
			min_r, max_r, max_r / max(min_r, 0.001)
		])
		assert(max_r > min_r + 1.0, "Asteroid mesh must exhibit organic radial variation")

		# Test Convex Collision Shape Generation
		var shape := mesh_res.create_convex_shape(true, true)
		assert(shape != null, "Convex collision shape must be generated cleanly")
		print("    ✓ Convex collision hull generation verified.")

		gen.queue_free()

	print("  ✓ All 4 procedural asteroid archetypes verified.")

	# -------------------------------------------------------------------------
	# TEST 2: Triplanar PBR Shader Compilation & Material Binding
	# -------------------------------------------------------------------------
	print("\n[TEST 2] Testing Triplanar PBR Asteroid Shader Binding...")
	var test_gen := ProceduralAsteroidMeshClass.new()
	test_gen.base_radius = 5.0
	test_gen.subdivision_level = 2
	var test_mesh := test_gen.rebuild_asteroid(101)
	var mat := test_mesh.surface_get_material(0)

	assert(mat != null, "Asteroid surface must have a bound material")
	assert(mat is ShaderMaterial, "Material must be a ShaderMaterial")
	var sm := mat as ShaderMaterial
	assert(sm.shader != null, "ShaderMaterial must reference valid shader")
	print("  • Shader resource: %s" % sm.shader.resource_path)
	print("  ✓ Triplanar PBR Shader verified.")
	test_gen.queue_free()

	# -------------------------------------------------------------------------
	# TEST 3: Asteroid Field Generation & Physics Simulation Pass
	# -------------------------------------------------------------------------
	print("\n[TEST 3] Testing Full Asteroid Field Multi-Mesh / RigidBody Generation...")
	var field := AsteroidFieldClass.new()
	field.asteroid_count = 60
	field.drone_count = 6
	root.add_child(field)
	field._ready()

	# Simulate 10 physics frames
	for _f in range(10):
		field._process(0.016)

	print("  • Instantiated Asteroids: %d" % field.instantiated_asteroids.size())
	print("  • Instantiated Target Drones: %d" % field.target_drones.size())
	assert(field.instantiated_asteroids.size() == 60, "Field must generate exactly 60 physics asteroids")
	assert(field.target_drones.size() == 6, "Field must generate 6 void-fauna drones")
	print("  ✓ Asteroid Field with dynamic spin and collision bodies verified.")

	print("\n==================================================================")
	print("SUCCESS: 100% AAA+ PROCEDURAL ASTEROID & ROCK AUDIT PASSED!")
	print("==================================================================")
	quit(0)
