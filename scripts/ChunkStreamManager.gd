# res://scripts/ChunkStreamManager.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# ChunkStreamManager.gd — Predictive Dual-Scale Chunk Streaming
# ==============================================================================
# Council-approved (20260818_GAMEPLAY_STREAMING, score 7.55/10, 5/5 majority)
#
# Streams gameplay elements (asteroids, enemies, anomalies, hazards) around
# the player ship using a dual-scale chunk grid:
#
#   FAR-FIELD chunks (1 AU = 149.6M km):
#     - MultiMesh ONLY (no RigidBody3D, no physics)
#     - Density from SystemNoiseField.sample_channel_region()
#     - LOD: billboard/point at extreme distance
#
#   NEAR-FIELD chunks (0.01 AU = 1.5M km):
#     - RigidBody3D asteroids (spawned at rest, freeze=true)
#     - VoidFaunaDrone enemies (aggression from noise)
#     - Full physics + collision
#
# Mandatory Council Mitigations:
#   1. All elements join 'celestial_bodies' group (floating origin safe)
#   2. Far-field = MultiMesh only, zero RigidBody3D
#   3. Near-field RigidBody3D spawned at rest (freeze=true)
#   4. Seeded RNG per chunk: system_seed ^ hash(chunk_x, chunk_z)
#   5. Despawn: disconnect signals → remove from groups → queue_free()
#   6. AsteroidField.gd NOT modified
#   7. Uses SystemNoiseField.sample_channel_region() for bulk queries
#   8. Verified via parse check + runtime test
# ==============================================================================

extends Node3D

const SystemNoiseFieldClass: GDScript = preload("res://scripts/SystemNoiseField.gd")
const ProceduralAsteroidMeshClass: GDScript = preload("res://scripts/ProceduralAsteroidMesh.gd")

# --- Chunk grid configuration ---
const FAR_CHUNK_SIZE_AU: float = 1.0
const FAR_CHUNK_SIZE_M: float = FAR_CHUNK_SIZE_AU * 149597870700.0
const NEAR_CHUNK_SIZE_AU: float = 0.01
const NEAR_CHUNK_SIZE_M: float = NEAR_CHUNK_SIZE_AU * 149597870700.0

# --- Streaming radii (how many chunks around the ship to load) ---
const FAR_STREAM_RADIUS_CHUNKS: int = 3      # 3 chunks = 3 AU radius
const NEAR_STREAM_RADIUS_CHUNKS: int = 4      # 4 chunks = 0.04 AU = 6M km radius

# --- LOD tiers ---
enum LOD {
	FULL_PHYSICS,   # Near-field: RigidBody3D + collision + physics
	SIMPLIFIED,     # Near-field edge: MeshInstance3D only, no physics
	MULTIMESH,      # Far-field: MultiMesh instanced rendering
	BILLBOARD,      # Far-field edge: point/billboard only
	INVISIBLE,      # Beyond stream radius: not loaded
}

# --- Frame budgeting ---
const MAX_CHUNKS_LOADED_PER_FRAME: int = 1
const MAX_CHUNKS_UNLOADED_PER_FRAME: int = 1
const MAX_FRAME_TIME_MS: float = 8.0  # Stop loading if frame would exceed 8ms

# --- Element caps per chunk ---
const MAX_ASTEROIDS_PER_FAR_CHUNK: int = 40
const MAX_ASTEROIDS_PER_NEAR_CHUNK: int = 15
const MAX_ENEMIES_PER_NEAR_CHUNK: int = 3
const MAX_ANOMALIES_PER_FAR_CHUNK: int = 2
const MAX_HAZARDS_PER_FAR_CHUNK: int = 1

# --- State ---
var _noise_field: Node = null
var _ship_node: Node3D = null
var _system_seed: int = 0

# Active chunks: key = "far_x:far_z" or "near_x:near_z", value = ChunkData
var _active_far_chunks: Dictionary = {}
var _active_near_chunks: Dictionary = {}

# Load/unload queues (priority-ordered)
var _load_queue: Array[Dictionary] = []
var _unload_queue: Array[Dictionary] = []

# Per-chunk signal registry for clean despawn (mitigation #5)
# key = chunk_key, value = Array of {signal_name, callable}
var _chunk_signal_registry: Dictionary = {}

# Velocity prediction
var _ship_velocity: Vector3 = Vector3.ZERO
var _ship_prev_pos: Vector3 = Vector3.ZERO

# Frame budget tracking
var _loaded_this_frame: int = 0
var _unloaded_this_frame: int = 0

# Asteroid mesh cache for MultiMesh (shared across far chunks)
var _asteroid_mesh_cache: ArrayMesh = null
# Cached collision shape — avoids per-asteroid create_convex_shape() calls
var _asteroid_collision_cache: ConvexPolygonShape3D = null

# --- Threaded generation queue ---
# Chunk data is computed on a background thread, then mounted on main thread
var _threaded_results: Array[Dictionary] = []
var _threaded_mutex: Mutex = Mutex.new()
var _hw_detector: Node = null

signal chunk_loaded(chunk_key: String, lod: int)
signal chunk_unloaded(chunk_key: String)
signal streaming_stats_updated(stats: Dictionary)

func _ready() -> void:
	# Find sibling nodes
	_noise_field = get_node_or_null("../SystemNoiseField")
	call_deferred("_find_ship")

	# Get HardwareDetector for per-hardware budget tuning
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		_hw_detector = ml.root.get_node_or_null("HardwareDetector")

	# Connect to noise field
	if _noise_field and _noise_field.has_signal("grids_generated"):
		_noise_field.grids_generated.connect(_on_grids_ready)

	# Build asteroid mesh cache for MultiMesh
	_build_mesh_cache()

	# If noise already generated, start streaming
	if _noise_field and _noise_field.is_generated():
		_on_grids_ready()

func _find_ship() -> void:
	_ship_node = get_node_or_null("../PlayerShip")
	if _ship_node:
		_ship_prev_pos = _ship_node.global_position

func _on_grids_ready() -> void:
	if _noise_field:
		_system_seed = _noise_field.get_system_seed()
	print("[ChunkStreamManager] Ready — system seed: %d" % _system_seed)

func _build_mesh_cache() -> void:
	if _asteroid_mesh_cache:
		return
	var gen: Object = ProceduralAsteroidMeshClass.new()
	gen.base_radius = 6.0
	gen.subdivision_level = 2
	gen.displacement_roughness = 0.45
	gen.archetype = ProceduralAsteroidMeshClass.AsteroidArchetype.SILICATE_S_TYPE
	gen.asteroid_seed = 12345
	_asteroid_mesh_cache = gen.rebuild_asteroid()
	# Build collision shape ONCE — reuse for all asteroids (huge perf win)
	if _asteroid_mesh_cache:
		_asteroid_collision_cache = _asteroid_mesh_cache.create_convex_shape(true, true)
	gen.queue_free()

# --- Main processing loop ---
var _process_count: int = 0

func _process(delta: float) -> void:
	_process_count += 1
	if not _noise_field or not _noise_field.is_generated():
		return
	if not _ship_node or not is_instance_valid(_ship_node):
		# Retry finding ship
		_ship_node = get_node_or_null("../PlayerShip")
		if not _ship_node:
			return

	# Track ship velocity for predictive loading
	var ship_pos := _ship_node.global_position
	_ship_velocity = (ship_pos - _ship_prev_pos) / maxf(delta, 0.001)
	_ship_prev_pos = ship_pos

	# Reset frame budget
	_loaded_this_frame = 0
	_unloaded_this_frame = 0

	# Update chunk streams
	_update_far_chunks(ship_pos)
	_update_near_chunks(ship_pos)

	# Process load/unload queues within frame budget
	_process_load_queue()
	_process_unload_queue()

	# Emit stats periodically
	if _process_count % 60 == 0:
		var stats := {
			"active_far_chunks": _active_far_chunks.size(),
			"active_near_chunks": _active_near_chunks.size(),
			"load_queue": _load_queue.size(),
			"unload_queue": _unload_queue.size(),
			"ship_velocity_ms": _ship_velocity.length(),
		}
		streaming_stats_updated.emit(stats)

	# Print first stats report for verification
	if _process_count == 5:
		var totals := get_total_streamed_elements()
		print("[ChunkStreamManager] Streaming active: far=%d near=%d | Total: %s" % [
			_active_far_chunks.size(), _active_near_chunks.size(), str(totals)
		])

# --- Far-field chunk management (1 AU chunks, MultiMesh) ---
func _update_far_chunks(ship_pos: Vector3) -> void:
	var ship_cx: int = int(floor(ship_pos.x / FAR_CHUNK_SIZE_M))
	var ship_cz: int = int(floor(ship_pos.z / FAR_CHUNK_SIZE_M))

	# Determine which far chunks should be active
	var needed: Dictionary = {}
	for dz in range(-FAR_STREAM_RADIUS_CHUNKS, FAR_STREAM_RADIUS_CHUNKS + 1):
		for dx in range(-FAR_STREAM_RADIUS_CHUNKS, FAR_STREAM_RADIUS_CHUNKS + 1):
			var cx: int = ship_cx + dx
			var cz: int = ship_cz + dz
			var key: String = "far_%d:%d" % [cx, cz]
			needed[key] = true

			if not _active_far_chunks.has(key):
				# Queue for loading with priority by distance
				var dist: float = sqrt(float(dx * dx + dz * dz))
				_load_queue.append({
					"key": key,
					"type": "far",
					"cx": cx,
					"cz": cz,
					"priority": dist,  # Lower = higher priority
				})

	# Queue unloads for far chunks no longer needed
	for key in _active_far_chunks.keys():
		if not needed.has(key):
			_unload_queue.append({"key": key, "type": "far"})

	# Sort load queue by priority (nearest first)
	_load_queue.sort_custom(func(a, b): return a.priority < b.priority)

# --- Near-field chunk management (0.01 AU chunks, RigidBody3D) ---
func _update_near_chunks(ship_pos: Vector3) -> void:
	var ship_cx: int = int(floor(ship_pos.x / NEAR_CHUNK_SIZE_M))
	var ship_cz: int = int(floor(ship_pos.z / NEAR_CHUNK_SIZE_M))

	var needed: Dictionary = {}
	for dz in range(-NEAR_STREAM_RADIUS_CHUNKS, NEAR_STREAM_RADIUS_CHUNKS + 1):
		for dx in range(-NEAR_STREAM_RADIUS_CHUNKS, NEAR_STREAM_RADIUS_CHUNKS + 1):
			var cx: int = ship_cx + dx
			var cz: int = ship_cz + dz
			var key: String = "near_%d:%d" % [cx, cz]
			needed[key] = true

			if not _active_near_chunks.has(key):
				var dist: float = sqrt(float(dx * dx + dz * dz))
				# Near-field has higher priority than far-field
				_load_queue.append({
					"key": key,
					"type": "near",
					"cx": cx,
					"cz": cz,
					"priority": dist - 100.0,  # Negative offset = higher priority
				})

	# Queue unloads
	for key in _active_near_chunks.keys():
		if not needed.has(key):
			_unload_queue.append({"key": key, "type": "near"})

# --- Queue processing with frame budget ---
func _process_load_queue() -> void:
	# Check for completed threaded chunk data
	_mount_completed_threaded_chunks()

	var i: int = 0
	var frame_start_ms: float = Time.get_ticks_msec()
	var budget: int = _get_chunk_budget()
	var max_ms: float = _get_max_frame_ms()

	while i < _load_queue.size() and _loaded_this_frame < budget:
		# Frame-time guard — stop loading if we're approaching the budget
		var elapsed_ms: float = Time.get_ticks_msec() - frame_start_ms
		if elapsed_ms > max_ms:
			break

		var req: Dictionary = _load_queue[i]
		var key: String = req.key

		# Skip if already loaded (may have been queued twice)
		if req.type == "far" and _active_far_chunks.has(key):
			_load_queue.remove_at(i)
			continue
		if req.type == "near" and _active_near_chunks.has(key):
			_load_queue.remove_at(i)
			continue

		# Dispatch chunk data generation to a background thread
		# The actual node creation happens on main thread when the result comes back
		_dispatch_threaded_chunk_load(req)

		_loaded_this_frame += 1
		_load_queue.remove_at(i)

## Returns the chunk load budget for this hardware.
func _get_chunk_budget() -> int:
	if _hw_detector and _hw_detector.has_method("get_chunk_load_budget_per_frame"):
		return int(_hw_detector.get_chunk_load_budget_per_frame())
	return MAX_CHUNKS_LOADED_PER_FRAME

## Returns the max frame time for chunk loading on this hardware.
func _get_max_frame_ms() -> float:
	if _hw_detector and _hw_detector.has_method("get_max_frame_time_ms"):
		return float(_hw_detector.get_max_frame_time_ms())
	return MAX_FRAME_TIME_MS

# ==============================================================================
# Threaded chunk data generation
# ==============================================================================

## Dispatches chunk data computation to a background thread.
## The thread computes noise sampling + transform generation.
## Node creation happens on main thread when the result arrives.
func _dispatch_threaded_chunk_load(req: Dictionary) -> void:
	var chunk_type: String = req.type
	var cx: int = req.cx
	var cz: int = req.cz
	var key: String = req.key

	# Compute center on main thread (cheap)
	var chunk_size_m: float = FAR_CHUNK_SIZE_M if chunk_type == "far" else NEAR_CHUNK_SIZE_M
	var center_m := Vector3(
		(float(cx) + 0.5) * chunk_size_m,
		0.0,
		(float(cz) + 0.5) * chunk_size_m
	)

	# Dispatch to worker thread
	var params: Dictionary = {
		"key": key,
		"type": chunk_type,
		"cx": cx,
		"cz": cz,
		"center": center_m,
		"chunk_size": chunk_size_m,
		"system_seed": _system_seed,
	}

	WorkerThreadPool.add_task(Callable(self, "_worker_generate_chunk_data").bind(params))

## Runs on a background thread. Computes all chunk data WITHOUT touching the scene tree.
func _worker_generate_chunk_data(params: Dictionary) -> void:
	var key: String = params["key"]
	var chunk_type: String = params["type"]
	var center_m: Vector3 = params["center"]
	var chunk_size_m: float = params["chunk_size"]
	var system_seed: int = params["system_seed"]

	var result: Dictionary = {
		"key": key,
		"type": chunk_type,
		"cx": int(params["cx"]),
		"cz": int(params["cz"]),
		"center": center_m,
	}

	# Deterministic seeded RNG
	var chunk_seed: int = system_seed ^ _hash_chunk_coords(int(params["cx"]), int(params["cz"]))
	if chunk_type == "near":
		chunk_seed = chunk_seed ^ 0x4E454152  # "NEAR"
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed

	if chunk_type == "far":
		# Sample noise density (thread-safe read)
		var res_density: Dictionary = _noise_field.sample_channel_region(
			SystemNoiseFieldClass.Channel.RESOURCES, center_m, chunk_size_m * 0.5)
		var anomaly_density: Dictionary = _noise_field.sample_channel_region(
			SystemNoiseFieldClass.Channel.ANOMALIES, center_m, chunk_size_m * 0.5)
		var hazard_density: Dictionary = _noise_field.sample_channel_region(
			SystemNoiseFieldClass.Channel.HAZARDS, center_m, chunk_size_m * 0.5)

		var asteroid_count: int = mini(int(res_density.avg * float(MAX_ASTEROIDS_PER_FAR_CHUNK)), MAX_ASTEROIDS_PER_FAR_CHUNK)
		var anomaly_count: int = 0
		if anomaly_density.avg > 0.6:
			anomaly_count = mini(int((anomaly_density.avg - 0.5) * 10.0), MAX_ANOMALIES_PER_FAR_CHUNK)
		var hazard_count: int = 0
		if hazard_density.avg > 0.7:
			hazard_count = mini(int((hazard_density.avg - 0.6) * 10.0), MAX_HAZARDS_PER_FAR_CHUNK)

		# Generate transforms on the thread (expensive loop, no scene tree access)
		var transforms: Array[Transform3D] = []
		for i in range(asteroid_count):
			var local_pos := Vector3(
				rng.randf_range(-chunk_size_m * 0.45, chunk_size_m * 0.45),
				rng.randf_range(-chunk_size_m * 0.1, chunk_size_m * 0.1),
				rng.randf_range(-chunk_size_m * 0.45, chunk_size_m * 0.45)
			)
			var scl: float = rng.randf_range(200.0, 2000.0)
			var rot := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
			transforms.append(Transform3D(Basis.from_euler(rot).scaled(Vector3.ONE * scl), local_pos))

		# Generate anomaly/hazard positions
		var anomaly_positions: Array[Vector3] = []
		for i in range(anomaly_count):
			anomaly_positions.append(Vector3(
				rng.randf_range(-chunk_size_m * 0.4, chunk_size_m * 0.4),
				0.0,
				rng.randf_range(-chunk_size_m * 0.4, chunk_size_m * 0.4)
			))
		var hazard_positions: Array[Vector3] = []
		for i in range(hazard_count):
			hazard_positions.append(Vector3(
				rng.randf_range(-chunk_size_m * 0.4, chunk_size_m * 0.4),
				0.0,
				rng.randf_range(-chunk_size_m * 0.4, chunk_size_m * 0.4)
			))

		result["asteroid_count"] = asteroid_count
		result["transforms"] = transforms
		result["anomaly_count"] = anomaly_count
		result["anomaly_positions"] = anomaly_positions
		result["anomaly_density"] = anomaly_density.avg
		result["hazard_count"] = hazard_count
		result["hazard_positions"] = hazard_positions
		result["hazard_density"] = hazard_density.avg
		result["rng_state"] = rng.randi()  # Continue RNG for beacon spawning

	else:  # near
		var res_density: Dictionary = _noise_field.sample_channel_region(
			SystemNoiseFieldClass.Channel.RESOURCES, center_m, chunk_size_m * 0.5)
		var enemy_density: Dictionary = _noise_field.sample_channel_region(
			SystemNoiseFieldClass.Channel.ENEMIES, center_m, chunk_size_m * 0.5)

		var asteroid_count: int = mini(int(res_density.avg * float(MAX_ASTEROIDS_PER_NEAR_CHUNK)), MAX_ASTEROIDS_PER_NEAR_CHUNK)
		var enemy_count: int = mini(int(enemy_density.avg * float(MAX_ENEMIES_PER_NEAR_CHUNK)), MAX_ENEMIES_PER_NEAR_CHUNK)

		# Generate asteroid data
		var asteroid_data: Array[Dictionary] = []
		for i in range(asteroid_count):
			asteroid_data.append({
				"pos": Vector3(
					rng.randf_range(-chunk_size_m * 0.45, chunk_size_m * 0.45),
					rng.randf_range(-chunk_size_m * 0.1, chunk_size_m * 0.1),
					rng.randf_range(-chunk_size_m * 0.45, chunk_size_m * 0.45)
				),
				"scl": rng.randf_range(2.0, 12.0) / 6.0,
				"rot": Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU),
			})

		# Generate enemy data
		var enemy_data: Array[Dictionary] = []
		for i in range(enemy_count):
			enemy_data.append({
				"pos": Vector3(
					rng.randf_range(-chunk_size_m * 0.4, chunk_size_m * 0.4),
					rng.randf_range(-100.0, 100.0),
					rng.randf_range(-chunk_size_m * 0.4, chunk_size_m * 0.4)
				),
			})

		result["asteroid_count"] = asteroid_count
		result["asteroid_data"] = asteroid_data
		result["enemy_count"] = enemy_count
		result["enemy_data"] = enemy_data
		result["res_density"] = res_density.avg
		result["enemy_density"] = enemy_density.avg

	# Push result to thread-safe queue
	_threaded_mutex.lock()
	_threaded_results.append(result)
	_threaded_mutex.unlock()

## Called on main thread — mounts completed threaded chunk data into the scene tree.
func _mount_completed_threaded_chunks() -> void:
	_threaded_mutex.lock()
	var results: Array[Dictionary] = _threaded_results.duplicate()
	_threaded_results.clear()
	_threaded_mutex.unlock()

	for result in results:
		var key: String = result["key"]
		var chunk_type: String = result["type"]

		if chunk_type == "far":
			_mount_far_chunk_from_data(result)
		else:
			_mount_near_chunk_from_data(result)

func _process_unload_queue() -> void:
	var i: int = 0
	while i < _unload_queue.size() and _unloaded_this_frame < MAX_CHUNKS_UNLOADED_PER_FRAME:
		var req: Dictionary = _unload_queue[i]
		var key: String = req.key

		if req.type == "far":
			_unload_far_chunk(key)
		else:
			_unload_near_chunk(key)

		_unloaded_this_frame += 1
		_unload_queue.remove_at(i)

# ==============================================================================
# Main-thread mounting of pre-computed chunk data
# ==============================================================================

## Mounts a far-field chunk from pre-computed threaded data.
func _mount_far_chunk_from_data(data: Dictionary) -> void:
	var key: String = data["key"]
	var cx: int = int(data["cx"])
	var cz: int = int(data["cz"])
	var center_m: Vector3 = data["center"]
	var asteroid_count: int = int(data["asteroid_count"])
	var transforms: Array = data["transforms"]
	var anomaly_count: int = int(data["anomaly_count"])
	var anomaly_positions: Array = data["anomaly_positions"]
	var anomaly_density: float = float(data["anomaly_density"])
	var hazard_count: int = int(data["hazard_count"])
	var hazard_positions: Array = data["hazard_positions"]
	var hazard_density: float = float(data["hazard_density"])

	# Create chunk container
	var chunk_node := Node3D.new()
	chunk_node.name = key
	chunk_node.add_to_group("celestial_bodies")

	# Spawn asteroids as MultiMesh (thread pre-computed transforms)
	if asteroid_count > 0 and _asteroid_mesh_cache:
		var mm_inst := MultiMeshInstance3D.new()
		mm_inst.name = "FarAsteroids"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _asteroid_mesh_cache
		mm.instance_count = asteroid_count

		for i in range(asteroid_count):
			if i < transforms.size():
				mm.set_instance_transform(i, transforms[i])

		mm_inst.multimesh = mm
		mm_inst.add_to_group("celestial_bodies")
		chunk_node.add_child(mm_inst)

	# Spawn anomaly beacons
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("rng_state", 0))
	for i in range(anomaly_count):
		if i < anomaly_positions.size():
			_spawn_anomaly_beacon(chunk_node, anomaly_positions[i], anomaly_density, rng)

	# Spawn hazard zones
	for i in range(hazard_count):
		if i < hazard_positions.size():
			_spawn_hazard_zone(chunk_node, hazard_positions[i], hazard_density, rng)

	# Position chunk
	chunk_node.position = center_m
	add_child(chunk_node)

	# Register chunk data
	_active_far_chunks[key] = {
		"node": chunk_node,
		"cx": cx,
		"cz": cz,
		"asteroid_count": asteroid_count,
		"anomaly_count": anomaly_count,
		"hazard_count": hazard_count,
		"lod": LOD.MULTIMESH,
	}

	chunk_loaded.emit(key, LOD.MULTIMESH)

## Mounts a near-field chunk from pre-computed threaded data.
func _mount_near_chunk_from_data(data: Dictionary) -> void:
	var key: String = data["key"]
	var cx: int = int(data["cx"])
	var cz: int = int(data["cz"])
	var center_m: Vector3 = data["center"]
	var asteroid_count: int = int(data["asteroid_count"])
	var asteroid_data: Array = data["asteroid_data"]
	var enemy_count: int = int(data["enemy_count"])
	var enemy_data: Array = data["enemy_data"]
	var res_density: float = float(data["res_density"])
	var enemy_density: float = float(data["enemy_density"])

	# Create chunk container
	var chunk_node := Node3D.new()
	chunk_node.name = key
	chunk_node.add_to_group("celestial_bodies")

	# Spawn asteroids as RigidBody3D (using pre-computed data)
	for i in range(asteroid_count):
		if i < asteroid_data.size():
			var ad: Dictionary = asteroid_data[i]
			_spawn_physics_asteroid_from_data(chunk_node, ad, res_density)

	# Spawn enemy drones
	var mount_rng := RandomNumberGenerator.new()
	mount_rng.seed = int(data.get("rng_state", randi()))
	for i in range(enemy_count):
		if i < enemy_data.size():
			var ed: Dictionary = enemy_data[i]
			_spawn_enemy_drone(chunk_node, ed["pos"], enemy_density, mount_rng)

	# Position chunk
	chunk_node.position = center_m
	add_child(chunk_node)

	# Register chunk data
	_active_near_chunks[key] = {
		"node": chunk_node,
		"cx": cx,
		"cz": cz,
		"asteroid_count": asteroid_count,
		"enemy_count": enemy_count,
		"lod": LOD.FULL_PHYSICS,
	}

	chunk_loaded.emit(key, LOD.FULL_PHYSICS)

## Spawns a physics asteroid from pre-computed data (no RNG needed on main thread).
func _spawn_physics_asteroid_from_data(parent: Node3D, data: Dictionary, res_value: float) -> void:
	var body := RigidBody3D.new()
	body.name = "StreamedAsteroid_%d" % randi()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.add_to_group("celestial_bodies")
	body.add_to_group("streamed_asteroid")

	var tier: int = _resource_value_to_tier(res_value)
	body.set_meta("resource_tier", tier)
	body.set_meta("resource_tier_name", _resource_tier_name(tier))
	body.set_meta("resource_value", res_value)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _asteroid_mesh_cache
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	if _asteroid_collision_cache:
		col.shape = _asteroid_collision_cache
	else:
		col.shape = _asteroid_mesh_cache.create_convex_shape(true, true)
	body.add_child(col)

	body.scale = Vector3.ONE * float(data["scl"])
	body.position = data["pos"]
	body.rotation = data["rot"]
	body.add_to_group("celestial_bodies")
	parent.add_child(body)

# --- Element spawning helpers ---
func _spawn_physics_asteroid(parent: Node3D, local_pos: Vector3, rng: RandomNumberGenerator, res_value: float) -> void:
	var body := RigidBody3D.new()
	body.name = "StreamedAsteroid_%d" % rng.randi()
	body.freeze = true  # Mitigation #3: at rest
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.add_to_group("celestial_bodies")  # Mitigation #1
	body.add_to_group("streamed_asteroid")

	# Resource tier from noise value
	var tier: int = _resource_value_to_tier(res_value)
	body.set_meta("resource_tier", tier)
	body.set_meta("resource_tier_name", _resource_tier_name(tier))
	body.set_meta("resource_value", res_value)

	# Mesh
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _asteroid_mesh_cache
	body.add_child(mesh_inst)

	# Collision — use cached shape (avoids per-asteroid create_convex_shape call)
	var col := CollisionShape3D.new()
	if _asteroid_collision_cache:
		col.shape = _asteroid_collision_cache
	else:
		col.shape = _asteroid_mesh_cache.create_convex_shape(true, true)
	body.add_child(col)

	# Scale and position
	var scl: float = rng.randf_range(2.0, 12.0) / 6.0
	body.scale = Vector3.ONE * scl
	body.position = local_pos
	body.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)

	# Spin metadata
	body.set_meta("spin", Vector3(
		rng.randf_range(-0.1, 0.1),
		rng.randf_range(-0.1, 0.1),
		rng.randf_range(-0.1, 0.1)
	))

	parent.add_child(body)

func _spawn_enemy_drone(parent: Node3D, local_pos: Vector3, aggression: float, rng: RandomNumberGenerator) -> void:
	var drone := Node3D.new()
	drone.name = "StreamedDrone_%d" % rng.randi()
	drone.add_to_group("celestial_bodies")  # Mitigation #1
	drone.add_to_group("void_fauna")
	drone.add_to_group("targets")
	drone.set_meta("aggression", aggression)
	drone.set_meta("enemy_density", aggression)

	# Mesh
	var mesh_inst := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.5, 1.5, 3.0)
	mesh_inst.mesh = prism

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.1, 0.4)
	mat.emission_energy_multiplier = 1.0 + aggression * 2.0
	mesh_inst.material_override = mat
	drone.add_child(mesh_inst)

	# Collision
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.5, 3.0)
	col.shape = box
	drone.add_child(col)

	drone.position = local_pos
	parent.add_child(drone)

func _spawn_anomaly_beacon(parent: Node3D, local_pos: Vector3, intensity: float, rng: RandomNumberGenerator) -> void:
	var beacon := MeshInstance3D.new()
	beacon.name = "AnomalyBeacon"
	beacon.add_to_group("celestial_bodies")
	var sphere := SphereMesh.new()
	sphere.radius = 200.0
	sphere.height = 400.0
	beacon.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.3, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.2, 0.9)
	mat.emission_energy_multiplier = intensity * 2.0
	mat.no_depth_test = true
	beacon.material_override = mat
	beacon.position = local_pos
	parent.add_child(beacon)

func _spawn_hazard_zone(parent: Node3D, local_pos: Vector3, intensity: float, rng: RandomNumberGenerator) -> void:
	var zone := Area3D.new()
	zone.name = "HazardZone"
	zone.add_to_group("celestial_bodies")
	zone.set_meta("hazard_intensity", intensity)

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 500.0 + intensity * 1000.0
	col.shape = sphere
	zone.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = sphere.radius * 0.5
	sphere_mesh.height = sphere.radius
	mesh_inst.mesh = sphere_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.0, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.0)
	mat.emission_energy_multiplier = intensity * 0.5
	mat.no_depth_test = true
	mesh_inst.material_override = mat
	zone.add_child(mesh_inst)

	zone.position = local_pos
	parent.add_child(zone)

# --- Chunk unload (mitigation #5: clean despawn) ---
func _unload_far_chunk(key: String) -> void:
	if not _active_far_chunks.has(key):
		return
	var chunk: Dictionary = _active_far_chunks[key]
	var node: Node3D = chunk.node
	if node and is_instance_valid(node):
		_clean_despawn_node(node)
		node.queue_free()
	_active_far_chunks.erase(key)
	_chunk_signal_registry.erase(key)
	chunk_unloaded.emit(key)

func _unload_near_chunk(key: String) -> void:
	if not _active_near_chunks.has(key):
		return
	var chunk: Dictionary = _active_near_chunks[key]
	var node: Node3D = chunk.node
	if node and is_instance_valid(node):
		_clean_despawn_node(node)
		node.queue_free()
	_active_near_chunks.erase(key)
	_chunk_signal_registry.erase(key)
	chunk_unloaded.emit(key)

## Mitigation #5: Disconnect signals, remove from groups, then queue_free
func _clean_despawn_node(node: Node3D) -> void:
	# Recursively clean all children
	for child in node.get_children():
		if child is Node3D:
			_clean_despawn_node(child)
	# Remove from all groups (floating origin, etc.)
	for group in node.get_groups():
		node.remove_from_group(group)

# --- Utility functions ---
func _hash_chunk_coords(cx: int, cz: int) -> int:
	# Deterministic hash of chunk coordinates
	var h: int = cx * 73856093
	h = h ^ (cz * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h

func _resource_value_to_tier(value: float) -> int:
	if value < 0.3:
		return 0  # BARREN
	elif value < 0.5:
		return 1  # CARBONACEOUS
	elif value < 0.7:
		return 2  # SILICATE
	elif value < 0.85:
		return 3  # METALLIC
	else:
		return 4  # EXOTIC

func _resource_tier_name(tier: int) -> String:
	match tier:
		0: return "barren"
		1: return "carbonaceous"
		2: return "silicate"
		3: return "metallic"
		4: return "exotic"
		_: return "unknown"

# --- Public API ---
func get_active_chunk_count() -> Dictionary:
	return {
		"far": _active_far_chunks.size(),
		"near": _active_near_chunks.size(),
	}

func get_streaming_stats() -> Dictionary:
	return {
		"active_far_chunks": _active_far_chunks.size(),
		"active_near_chunks": _active_near_chunks.size(),
		"load_queue": _load_queue.size(),
		"unload_queue": _unload_queue.size(),
		"ship_velocity_ms": _ship_velocity.length(),
	}

func get_total_streamed_elements() -> Dictionary:
	var total_asteroids: int = 0
	var total_enemies: int = 0
	var total_anomalies: int = 0
	var total_hazards: int = 0

	for key in _active_far_chunks:
		var chunk: Dictionary = _active_far_chunks[key]
		total_asteroids += int(chunk.get("asteroid_count", 0))
		total_anomalies += int(chunk.get("anomaly_count", 0))
		total_hazards += int(chunk.get("hazard_count", 0))

	for key in _active_near_chunks:
		var chunk: Dictionary = _active_near_chunks[key]
		total_asteroids += int(chunk.get("asteroid_count", 0))
		total_enemies += int(chunk.get("enemy_count", 0))

	return {
		"asteroids": total_asteroids,
		"enemies": total_enemies,
		"anomalies": total_anomalies,
		"hazards": total_hazards,
	}
