# res://scripts/test_primitive_audit.gd
# ==============================================================================
# BioGenesis-X — Per-Node Primitive Audit
# ==============================================================================
# Loads the space_flight scene and enumerates every MeshInstance3D, reporting
# primitive counts, vertex counts, and LOD usage. Identifies the heaviest
# contributors to the 5.75M primitive count observed in the GPU profile.
#
# Run non-headless for full mesh data:
#   Godot --script res://scripts/test_primitive_audit.gd
# ==============================================================================

extends SceneTree

const FLIGHT_SCENE := "res://scenes/space_flight.tscn"

func _init() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	print("\n" + "=".repeat(80))
	print("  BioGenesis-X — Per-Node Primitive Audit")
	print("  Scene: %s" % FLIGHT_SCENE)
	print("=".repeat(80))

	# Load and instantiate the scene
	var packed: PackedScene = load(FLIGHT_SCENE)
	if not packed:
		print("ERROR: Could not load scene")
		quit()
		return

	var scene: Node = packed.instantiate()
	root.add_child(scene)

	# Wait a few frames for _ready() and deferred calls to complete
	await process_frame
	await process_frame
	await process_frame

	# Allow procedural generation to kick in
	print("[Audit] Waiting 3s for procedural generation...")
	var timer := Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	root.add_child(timer)
	timer.start()
	await timer.timeout
	timer.queue_free()

	# Collect all MeshInstance3D nodes
	var meshes: Array[Dictionary] = []
	_collect_meshes(scene, "", meshes)

	# Sort by primitive count descending
	meshes.sort_custom(func(a, b): return a.primitives > b.primitives)

	# Print summary
	print("\n--- MESH SUMMARY (%d MeshInstance3D nodes) ---" % meshes.size())
	var total_prims: int = 0
	var total_verts: int = 0
	var total_lod_enabled: int = 0
	for m in meshes:
		total_prims += m.primitives
		total_verts += m.vertices
		if m.lod_enabled:
			total_lod_enabled += 1

	print("  Total primitives: %s (%.2fM)" % [_fmt_int(total_prims), float(total_prims) / 1_000_000.0])
	print("  Total vertices:   %s (%.2fM)" % [_fmt_int(total_verts), float(total_verts) / 1_000_000.0])
	print("  LOD enabled:      %d / %d" % [total_lod_enabled, meshes.size()])

	# Print top 30 contributors
	print("\n--- TOP 30 PRIMITIVE CONTRIBUTORS ---")
	print("  %-50s %12s %12s %8s %8s" % ["Node Path", "Primitives", "Vertices", "LOD", "Surf"])
	print("  " + "-".repeat(94))
	for i in range(mini(30, meshes.size())):
		var m = meshes[i]
		print("  %-50s %12s %12s %8s %8d" % [
			m.path,
			_fmt_int(m.primitives),
			_fmt_int(m.vertices),
			"Y" if m.lod_enabled else "N",
			m.surface_count,
		])

	# Group by parent/top-level system
	print("\n--- PRIMITIVES BY TOP-LEVEL SYSTEM ---")
	var by_system: Dictionary = {}
	for m in meshes:
		var top: String = m.path.split("/")[0]
		if top.is_empty():
			top = "(root)"
		if not by_system.has(top):
			by_system[top] = {"prims": 0, "verts": 0, "count": 0}
		by_system[top].prims += m.primitives
		by_system[top].verts += m.vertices
		by_system[top].count += 1

	var systems: Array = by_system.keys()
	systems.sort_custom(func(a, b): return by_system[a].prims > by_system[b].prims)
	print("  %-30s %12s %12s %8s" % ["System", "Primitives", "Vertices", "Meshes"])
	print("  " + "-".repeat(74))
	for sys in systems:
		var d = by_system[sys]
		print("  %-30s %12s %12s %8d" % [
			sys,
			_fmt_int(d.prims),
			_fmt_int(d.verts),
			d.count,
		])

	# Check for meshes without LOD
	var no_lod: Array[Dictionary] = meshes.filter(func(m): return not m.lod_enabled and m.primitives > 1000)
	if not no_lod.is_empty():
		print("\n--- HIGH-PRIMITIVE MESHES WITHOUT LOD (%d) ---" % no_lod.size())
		for m in no_lod:
			print("  %-50s %12s prims" % [m.path, _fmt_int(m.primitives)])

	# Check for MultiMeshInstance3D
	var multimeshes: Array[Dictionary] = []
	_collect_multimeshes(scene, "", multimeshes)
	if not multimeshes.is_empty():
		print("\n--- MULTIMESH INSTANCES (%d) ---" % multimeshes.size())
		for mm in multimeshes:
			print("  %-50s instances=%d  prims/inst=%d" % [
				mm.path, mm.instance_count, mm.primitives_per_instance
			])

	# Check GPU compute and shader-based systems
	print("\n--- PROCEDURAL SYSTEM STATUS ---")
	_check_procedural_systems(scene)

	print("\n" + "=".repeat(80))
	print("  AUDIT COMPLETE")
	print("=".repeat(80) + "\n")

	# Cleanup
	scene.queue_free()
	await process_frame
	quit()


func _collect_meshes(node: Node, path: String, out: Array[Dictionary]) -> void:
	var node_path: String = path + node.name if path.is_empty() else path + "/" + node.name

	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mesh: Mesh = mi.mesh
		var prim_count: int = 0
		var vert_count: int = 0
		var surface_count: int = 0
		var lod_enabled: bool = false

		if mesh:
			surface_count = mesh.get_surface_count()
			for s in range(surface_count):
				var arrays: Array = mesh.surface_get_arrays(s)
				if arrays.size() > ArrayMesh.ARRAY_VERTEX:
					var verts: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
					vert_count += verts.size()
					# Primitives = vertices / 3 (triangles) or vertices / 2 (lines)
					# For triangle meshes, primitives = index_count / 3
					if arrays.size() > ArrayMesh.ARRAY_INDEX:
						var indices: PackedInt32Array = arrays[ArrayMesh.ARRAY_INDEX]
						prim_count += indices.size() / 3
					else:
						prim_count += verts.size() / 3

			# Check LOD
			lod_enabled = mesh.get_lod_count() > 1
			if mi.lod_bias > 0:
				lod_enabled = true

		out.append({
			"path": node_path,
			"primitives": prim_count,
			"vertices": vert_count,
			"surface_count": surface_count,
			"lod_enabled": lod_enabled,
			"mesh_type": mesh.get_class() if mesh else "null",
		})

	for child in node.get_children():
		_collect_meshes(child, node_path, out)


func _collect_multimeshes(node: Node, path: String, out: Array[Dictionary]) -> void:
	var node_path: String = path + node.name if path.is_empty() else path + "/" + node.name

	if node is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = node
		var mm: MultiMesh = mmi.multimesh
		if mm:
			var mesh: Mesh = mm.mesh
			var prims_per: int = 0
			if mesh and mesh.get_surface_count() > 0:
				var arrays: Array = mesh.surface_get_arrays(0)
				if arrays.size() > ArrayMesh.ARRAY_INDEX:
					prims_per = (arrays[ArrayMesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif arrays.size() > ArrayMesh.ARRAY_VERTEX:
					prims_per = (arrays[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			out.append({
				"path": node_path,
				"instance_count": mm.instance_count,
				"primitives_per_instance": prims_per,
				"total_primitives": prims_per * mm.instance_count,
			})

	for child in node.get_children():
		_collect_multimeshes(child, node_path, out)


func _check_procedural_systems(scene: Node) -> void:
	# UniverseManager — planets, stars
	var universe := scene.get_node_or_null("UniverseManager")
	if universe:
		var children := universe.get_children()
		print("  UniverseManager: %d children" % children.size())
		for c in children:
			var mesh_info := ""
			if c is MeshInstance3D:
				var mi: MeshInstance3D = c
				if mi.mesh:
					var p: int = 0
					for s in range(mi.mesh.get_surface_count()):
						var arr: Array = mi.mesh.surface_get_arrays(s)
						if arr.size() > ArrayMesh.ARRAY_INDEX:
							p += (arr[ArrayMesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
					mesh_info = " (prims: %d)" % p
			print("    - %s [%s]%s" % [c.name, c.get_class(), mesh_info])

	# AsteroidField
	var asteroids := scene.get_node_or_null("AsteroidField")
	if asteroids:
		var children := asteroids.get_children()
		print("  AsteroidField: %d children" % children.size())
		var total_prims: int = 0
		for c in children:
			if c is MeshInstance3D:
				var mi: MeshInstance3D = c
				if mi.mesh:
					for s in range(mi.mesh.get_surface_count()):
						var arr: Array = mi.mesh.surface_get_arrays(s)
						if arr.size() > ArrayMesh.ARRAY_INDEX:
							total_prims += (arr[ArrayMesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("    Total asteroid prims: %s" % _fmt_int(total_prims))

	# ChunkStreamManager
	var chunks := scene.get_node_or_null("ChunkStreamManager")
	if chunks:
		var children := chunks.get_children()
		print("  ChunkStreamManager: %d children" % children.size())

	# ProceduralBioMesh (player ship)
	var bio_mesh := scene.get_node_or_null("PlayerShip/ProceduralBioMesh")
	if bio_mesh and bio_mesh is MeshInstance3D:
		var mi: MeshInstance3D = bio_mesh
		if mi.mesh:
			var p: int = 0
			var v: int = 0
			for s in range(mi.mesh.get_surface_count()):
				var arr: Array = mi.mesh.surface_get_arrays(s)
				if arr.size() > ArrayMesh.ARRAY_INDEX:
					p += (arr[ArrayMesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				if arr.size() > ArrayMesh.ARRAY_VERTEX:
					v += (arr[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("  ProceduralBioMesh: prims=%s verts=%s surfaces=%d LOD=%d" % [
				_fmt_int(p), _fmt_int(v), mi.mesh.get_surface_count(), mi.mesh.get_lod_count()
			])

	# Starfield
	var starfield := scene.get_node_or_null("Starfield")
	if starfield:
		var children := starfield.get_children()
		print("  Starfield: %d children" % children.size())
		for c in children:
			if c is MeshInstance3D:
				var mi: MeshInstance3D = c
				if mi.mesh:
					var p: int = 0
					for s in range(mi.mesh.get_surface_count()):
						var arr: Array = mi.mesh.surface_get_arrays(s)
						if arr.size() > ArrayMesh.ARRAY_INDEX:
							p += (arr[ArrayMesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
					print("    - %s: prims=%s" % [c.name, _fmt_int(p)])


func _fmt_int(n: int) -> String:
	var s: String = str(n)
	var result: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
