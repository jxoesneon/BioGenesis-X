# res://scripts/test_collision_debug.gd
# ==============================================================================
# BioGenesis-X: Collision Debug Visualizer
# ==============================================================================
# Adds visible debug wireframes for:
#   1. The ship's collision shape (ConvexPolygonShape3D)
#   2. All asteroid collision shapes in the field
#   3. Any external meshes that intersect the ship's collision bounds
#
# Usage:
#   Run as a headless script to get a report:
#     Godot --headless --script res://scripts/test_collision_debug.gd
#   Or add to the scene at runtime for visual debug.
# ==============================================================================

extends SceneTree

const DEBUG_COLOR_SHIP: Color = Color(0.0, 1.0, 0.3, 0.8)     # Green for ship
const DEBUG_COLOR_ASTEROID: Color = Color(1.0, 0.5, 0.0, 0.6) # Orange for asteroids
const DEBUG_COLOR_OVERLAP: Color = Color(1.0, 0.0, 0.0, 0.9)  # Red for overlaps

var _debug_meshes: Array[MeshInstance3D] = []
var _ship: CharacterBody3D = null
var _asteroid_field: Node3D = null

func _ready() -> void:
	print("==================================================================")
	print("BIO-GENESIS-X: COLLISION DEBUG VISUALIZER")
	print("==================================================================")

	# Load the space_flight scene so we can inspect the ship and asteroids
	print("[LOAD] Loading space_flight scene...")
	var scene: PackedScene = load("res://scenes/space_flight.tscn")
	if scene == null:
		print("FAIL: Could not load space_flight.tscn")
		_do_quit()
		return
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	# Wait a few frames for _ready to run on the instantiated nodes and asteroids to generate
	for i: int in range(120):  # ~2 seconds at 60fps
		await process_frame
	_run_analysis()

func _run_analysis() -> void:
	# Find the ship
	var tree: SceneTree = self
	if tree == null or tree.root == null:
		print("FAIL: No scene tree")
		_do_quit()
		return

	_ship = tree.root.get_node_or_null("SpaceFlight/PlayerShip")
	if _ship == null:
		# Try without SpaceFlight prefix (might be added directly)
		_ship = tree.root.get_node_or_null("PlayerShip")

	if _ship == null:
		print("FAIL: PlayerShip not found in scene")
		_do_quit()
		return

	print("PASS: Found PlayerShip at %s" % str(_ship.global_position))

	# Analyze ship collision
	_analyze_ship_collision()

	# Find and analyze asteroid field
	_asteroid_field = tree.root.get_node_or_null("SpaceFlight/AsteroidField")
	if _asteroid_field == null:
		_asteroid_field = tree.root.get_node_or_null("AsteroidField")

	if _asteroid_field != null:
		print("PASS: Found AsteroidField")
		_analyze_asteroid_collisions()
	else:
		print("WARN: AsteroidField not found (may not be in this scene)")

	# Check for external meshes inside ship collision
	_check_external_meshes_in_ship()

	# Create visual debug wireframes (only visible in non-headless mode)
	if not DisplayServer.get_name() == "headless":
		_create_visual_debug()

	print("==================================================================")
	print("COLLISION DEBUG: COMPLETE")
	print("==================================================================")
	# Auto-quit in headless mode
	if DisplayServer.get_name() == "headless":
		_do_quit()

func _do_quit() -> void:
	SceneTree.quit.call(self)

# ------------------------------------------------------------------------------
# Ship Collision Analysis
# ------------------------------------------------------------------------------
func _analyze_ship_collision() -> void:
	print("\n--- SHIP COLLISION ANALYSIS ---")

	var col_shape: CollisionShape3D = null
	for child: Node in _ship.get_children():
		if child is CollisionShape3D:
			col_shape = child as CollisionShape3D
			break

	if col_shape == null:
		print("FAIL: No CollisionShape3D found on PlayerShip")
		return

	print("PASS: CollisionShape3D found: %s" % col_shape.name)
	print("  visible: %s" % str(col_shape.visible))
	print("  disabled: %s" % str(col_shape.disabled))

	var shape: Shape3D = col_shape.shape
	if shape == null:
		print("FAIL: CollisionShape3D has no shape resource")
		return

	if shape is ConvexPolygonShape3D:
		var convex: ConvexPolygonShape3D = shape as ConvexPolygonShape3D
		var points: PackedVector3Array = convex.points
		print("  shape type: ConvexPolygonShape3D")
		print("  point count: %d" % points.size())

		# Compute AABB of the collision shape
		var aabb: AABB = AABB()
		if points.size() > 0:
			aabb = AABB(points[0], Vector3.ZERO)
			for p: Vector3 in points:
				aabb = aabb.expand(p)
		print("  local AABB: pos=%s size=%s" % [str(aabb.position), str(aabb.size)])
		print("  world AABB: pos=%s size=%s" % [
			str(_ship.global_position + aabb.position),
			str(aabb.size)
		])

		# Check if the collision shape is reasonable (not too large/small)
		var max_dim: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		print("  max dimension: %.2fm" % max_dim)
		if max_dim > 100.0:
			print("  WARN: Collision shape is very large (>100m) — may cause issues")
		if max_dim < 1.0:
			print("  WARN: Collision shape is very small (<1m) — may not collide properly")

		# Check for degenerate points (NaN, zero, or extreme values)
		var degenerate_count: int = 0
		for p: Vector3 in points:
			if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
				degenerate_count += 1
			elif p.length() > 10000.0:
				degenerate_count += 1
		if degenerate_count > 0:
			print("  FAIL: %d degenerate points found (NaN or extreme values)" % degenerate_count)
		else:
			print("  PASS: No degenerate points")
	else:
		print("  shape type: %s (not ConvexPolygonShape3D)" % shape.get_class())

	# List all child meshes of the ship
	print("\n  --- Ship child meshes ---")
	var mesh_count: int = 0
	for child: Node in _ship.get_children(true):
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			var mesh_aabb: AABB = mi.get_aabb()
			# Transform to ship-local space
			var local_pos: Vector3 = mi.global_position - _ship.global_position
			print("  mesh: %s" % mi.name)
			print("    local_pos: %s" % str(local_pos))
			print("    AABB size: %s" % str(mesh_aabb.size))
			print("    AABB local: pos=%s size=%s" % [str(mesh_aabb.position), str(mesh_aabb.size)])
			mesh_count += 1
	if mesh_count == 0:
		print("  (no MeshInstance3D children found)")

# ------------------------------------------------------------------------------
# Asteroid Collision Analysis
# ------------------------------------------------------------------------------
func _analyze_asteroid_collisions() -> void:
	print("\n--- ASTEROID COLLISION ANALYSIS ---")

	var asteroids: Array[Node3D] = []
	for child: Node in _asteroid_field.get_children(true):
		if child is RigidBody3D and child.name.begins_with("Asteroid_"):
			asteroids.append(child as Node3D)

	print("  asteroid count: %d" % asteroids.size())

	var total_bounds: AABB = AABB()
	var checked: int = 0
	var issues: int = 0

	for asteroid: Node3D in asteroids:
		var body: RigidBody3D = asteroid as RigidBody3D
		if body == null:
			continue

		# Find collision shape
		var col: CollisionShape3D = null
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				col = child as CollisionShape3D
				break

		if col == null:
			print("  WARN: %s has no CollisionShape3D" % body.name)
			issues += 1
			continue

		var shape: Shape3D = col.shape
		if shape == null:
			print("  WARN: %s CollisionShape3D has no shape" % body.name)
			issues += 1
			continue

		if shape is ConvexPolygonShape3D:
			var convex: ConvexPolygonShape3D = shape as ConvexPolygonShape3D
			var points: PackedVector3Array = convex.points

			# Compute AABB
			var aabb: AABB = AABB()
			if points.size() > 0:
				aabb = AABB(points[0], Vector3.ZERO)
				for p: Vector3 in points:
					aabb = aabb.expand(p)
			# Scale by body scale
			aabb = aabb.abs()
			var scaled_size: Vector3 = aabb.size * body.scale
			var world_pos: Vector3 = body.global_position

			if checked == 0:
				total_bounds = AABB(world_pos, Vector3.ZERO)
			total_bounds = total_bounds.expand(world_pos)
			total_bounds = total_bounds.expand(world_pos + scaled_size)
			total_bounds = total_bounds.expand(world_pos - scaled_size)

			# Check for degenerate shapes
			if points.size() < 4:
				print("  WARN: %s has only %d collision points (need >=4)" % [body.name, points.size()])
				issues += 1

			# Check for NaN
			for p: Vector3 in points:
				if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
					print("  FAIL: %s has NaN in collision points" % body.name)
					issues += 1
					break

			# Check if collision is much larger than visual mesh
			var mesh_inst: MeshInstance3D = null
			for child: Node in body.get_children():
				if child is MeshInstance3D:
					mesh_inst = child as MeshInstance3D
					break
			if mesh_inst != null and mesh_inst.mesh != null:
				var mesh_aabb: AABB = mesh_inst.mesh.get_aabb()
				var mesh_max: float = maxf(mesh_aabb.size.x, maxf(mesh_aabb.size.y, mesh_aabb.size.z))
				var col_max: float = maxf(scaled_size.x, maxf(scaled_size.y, scaled_size.z))
				if col_max > mesh_max * 2.0:
					print("  WARN: %s collision (%.1fm) much larger than mesh (%.1fm)" % [body.name, col_max, mesh_max])
					issues += 1
				elif col_max < mesh_max * 0.3:
					print("  WARN: %s collision (%.1fm) much smaller than mesh (%.1fm)" % [body.name, col_max, mesh_max])
					issues += 1

			checked += 1

	print("  checked: %d / %d" % [checked, asteroids.size()])
	print("  issues found: %d" % issues)
	if checked > 0:
		print("  field total bounds: pos=%s size=%s" % [str(total_bounds.position), str(total_bounds.size)])

	# Check if any asteroids overlap the ship
	print("\n  --- Asteroid-Ship overlap check ---")
	var ship_pos: Vector3 = _ship.global_position
	var overlap_count: int = 0
	for asteroid: Node3D in asteroids:
		var dist: float = asteroid.global_position.distance_to(ship_pos)
		var body: RigidBody3D = asteroid as RigidBody3D
		if body == null:
			continue
		# Estimate asteroid radius from scale
		var ast_radius: float = 6.0 * body.scale.x  # base_radius * scale
		if dist < ast_radius + 20.0:  # within 20m of ship + asteroid radius
			print("  WARN: %s is %.1fm from ship (radius=%.1fm)" % [body.name, dist, ast_radius])
			overlap_count += 1
	if overlap_count == 0:
		print("  PASS: No asteroids within overlap range of ship")
	else:
		print("  FAIL: %d asteroids too close to ship" % overlap_count)

# ------------------------------------------------------------------------------
# External Mesh Intersection Check
# ------------------------------------------------------------------------------
func _check_external_meshes_in_ship() -> void:
	print("\n--- EXTERNAL MESH / SHIP COLLISION CHECK ---")

	# Get ship collision AABB in world space
	var ship_col: CollisionShape3D = null
	for child: Node in _ship.get_children():
		if child is CollisionShape3D:
			ship_col = child as CollisionShape3D
			break
	if ship_col == null or ship_col.shape == null:
		print("FAIL: No ship collision shape to check against")
		return

	var ship_aabb: AABB = AABB()
	if ship_col.shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (ship_col.shape as ConvexPolygonShape3D).points
		if points.size() > 0:
			ship_aabb = AABB(points[0], Vector3.ZERO)
			for p: Vector3 in points:
				ship_aabb = ship_aabb.expand(p)
	# Transform to world space
	ship_aabb.position += _ship.global_position

	print("  ship collision world AABB: pos=%s size=%s" % [str(ship_aabb.position), str(ship_aabb.size)])

	# Find all MeshInstance3D nodes in the scene that are NOT children of the ship
	var tree: SceneTree = self
	if tree == null:
		return

	var external_count: int = 0
	var intersecting: int = 0
	_find_external_meshes(tree.root, _ship, ship_aabb, external_count, intersecting)

	print("  external meshes found: %d" % external_count)
	print("  intersecting ship AABB: %d" % intersecting)
	if intersecting == 0:
		print("  PASS: No external meshes intersecting ship collision")
	else:
		print("  FAIL: External meshes found inside ship collision bounds")

func _find_external_meshes(node: Node, ship: Node, ship_aabb: AABB, count: int, intersecting: int) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		# Skip if this mesh is a child of the ship
		if not _is_child_of(mi, ship):
			count += 1
			var mesh_aabb: AABB = mi.get_aabb()
			mesh_aabb.position += mi.global_position
			if ship_aabb.intersects(mesh_aabb):
				print("  OVERLAP: %s at %s (AABB=%s)" % [mi.name, str(mi.global_position), str(mesh_aabb.size)])
				intersecting += 1
	for child: Node in node.get_children():
		_find_external_meshes(child, ship, ship_aabb, count, intersecting)

func _is_child_of(node: Node, parent: Node) -> bool:
	var current: Node = node
	while current != null:
		if current == parent:
			return true
		current = current.get_parent()
	return false

# ------------------------------------------------------------------------------
# Visual Debug (non-headless only)
# ------------------------------------------------------------------------------
func _create_visual_debug() -> void:
	print("\n--- CREATING VISUAL DEBUG WIREFRAMES ---")

	# Ship collision wireframe (green)
	var ship_col: CollisionShape3D = null
	for child: Node in _ship.get_children():
		if child is CollisionShape3D:
			ship_col = child as CollisionShape3D
			break
	if ship_col != null and ship_col.shape is ConvexPolygonShape3D:
		var wireframe: MeshInstance3D = _create_convex_wireframe(
			ship_col.shape as ConvexPolygonShape3D,
			DEBUG_COLOR_SHIP
		)
		wireframe.name = "DEBUG_ShipCollision"
		_ship.add_child(wireframe)
		_debug_meshes.append(wireframe)
		print("  PASS: Ship collision wireframe created (green)")

	# Asteroid collision wireframes (orange)
	if _asteroid_field != null:
		var count: int = 0
		for child: Node in _asteroid_field.get_children(true):
			if child is RigidBody3D and child.name.begins_with("Asteroid_"):
				var body: RigidBody3D = child as RigidBody3D
				for sub: Node in body.get_children():
					if sub is CollisionShape3D and (sub as CollisionShape3D).shape is ConvexPolygonShape3D:
						var wf: MeshInstance3D = _create_convex_wireframe(
							(sub as CollisionShape3D).shape as ConvexPolygonShape3D,
							DEBUG_COLOR_ASTEROID
						)
						wf.name = "DEBUG_" + body.name + "_Collision"
						body.add_child(wf)
						_debug_meshes.append(wf)
						count += 1
						break
		print("  PASS: %d asteroid collision wireframes created (orange)" % count)

	# Ship spawn exclusion zone (red sphere)
	var exclusion: MeshInstance3D = MeshInstance3D.new()
	exclusion.name = "DEBUG_SpawnExclusionZone"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 150.0  # matches ship_clearance in AsteroidField
	sphere.height = 300.0
	sphere.radial_segments = 32
	sphere.rings = 16
	exclusion.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = DEBUG_COLOR_OVERLAP
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	exclusion.material_override = mat
	exclusion.global_position = _ship.global_position
	root.add_child(exclusion)
	_debug_meshes.append(exclusion)
	print("  PASS: Spawn exclusion zone wireframe created (red, 150m radius)")

	# Schedule cleanup after 30 seconds
	create_timer(30.0).timeout.connect(_cleanup_debug)

func _create_convex_wireframe(shape: ConvexPolygonShape3D, color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	# Create a wireframe mesh from the convex shape points
	var points: PackedVector3Array = shape.points
	if points.size() < 3:
		return mi

	# Use a simple approach: create lines between consecutive points
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = points

	# Create edge indices (connect each point to the next)
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(points.size() - 1):
		indices.append(i)
		indices.append(i + 1)
	# Close the loop
	indices.append(points.size() - 1)
	indices.append(0)
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	mi.mesh = mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mi.material_override = mat
	return mi

func _cleanup_debug() -> void:
	for mi: MeshInstance3D in _debug_meshes:
		if is_instance_valid(mi):
			mi.queue_free()
	_debug_meshes.clear()
	print("[CollisionDebug] Visual debug wireframes cleaned up")
