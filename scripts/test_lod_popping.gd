extends Node

## LOD Popping Test — spawns at a fixed point, logs all create/destroy events
## then dumps a filtered analysis to identify what's popping and why

const SPAWN_POS := Vector3(20, 10, 40)
const OBSERVE_DURATION := 15.0  # seconds to observe
const SIMULATE_SWEEP := false  # Let the real intro zoom run naturally
const SWEEP_START := Vector3(0, 1200, 0)  # Default camera position
const OVERRIDE_CAMERA := false  # If false, let intro zoom run naturally

var _visuals: Node = null
var _cam: Camera3D = null
var _elapsed: float = 0.0
var _phase: int = 0  # 0=init, 1=observe, 2=dump, 3=done
var _cam_positions: Array[Vector3] = []  # Track camera position each frame
var _prev_fog_count: int = 0

func _ready() -> void:
	print("=== LOD POPPING TEST ===")
	print("Spawn pos: ", SPAWN_POS)
	print("Observe duration: %.1fs" % OBSERVE_DURATION)

	# Wait for scene to load
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_visuals = _find_node_by_script(get_tree().root, "GalaxyMapVisuals.gd")
	_cam = _find_node_by_type(get_tree().root, "Camera3D")

	if not _visuals:
		print("ERROR: GalaxyMapVisuals not found")
		get_tree().quit()
		return
	if not _cam:
		print("ERROR: Camera3D not found")
		get_tree().quit()
		return

	# Position camera
	if OVERRIDE_CAMERA:
		if SIMULATE_SWEEP:
			_cam.global_position = SWEEP_START
			if "target_position" in _cam:
				_cam.target_position = SPAWN_POS
			print("Camera sweeping from: ", SWEEP_START, " to: ", SPAWN_POS)
		else:
			_cam.global_position = SPAWN_POS
			if "target_position" in _cam:
				_cam.target_position = SPAWN_POS
			_cam.look_at(Vector3.ZERO)
			print("Camera positioned at: ", _cam.global_position)
			if "target_position" in _cam:
				print("Camera target_position: ", _cam.target_position)
	else:
		# Let the real intro zoom run naturally — don't override camera
		print("Letting intro zoom run naturally (no camera override)")
		print("Camera initial pos: ", _cam.global_position)
		if "target_position" in _cam:
			print("Camera target_position: ", _cam.target_position)

	# Enable LOD logging
	_visuals.enable_lod_logging(true)
	_phase = 1
	_elapsed = 0.0

func _process(delta: float) -> void:
	if _phase == 1:
		_elapsed += delta
		_cam_positions.append(_cam.global_position)
		var fog_count: int = _visuals.get_active_fog_count()
		if fog_count != _prev_fog_count:
			print("[t=%.2fs] fog_count changed: %d -> %d  cam=(%.1f,%.1f,%.1f)" % [
				_elapsed, _prev_fog_count, fog_count,
				_cam.global_position.x, _cam.global_position.y, _cam.global_position.z
			])
			_prev_fog_count = fog_count
		if _elapsed >= OBSERVE_DURATION:
			_phase = 2
			_analyze_log()

func _analyze_log() -> void:
	var log_entries: Array[Dictionary] = _visuals.get_lod_log()
	print("\n=== LOD LOG ANALYSIS ===")

	# Camera position analysis — was it actually stationary?
	if not _cam_positions.is_empty():
		var first_pos: Vector3 = _cam_positions[0]
		var max_drift: float = 0.0
		var last_pos: Vector3 = first_pos
		for p in _cam_positions:
			var drift: float = p.distance_to(first_pos)
			if drift > max_drift:
				max_drift = drift
			last_pos = p
		print("Camera first pos: (%.2f, %.2f, %.2f)" % [first_pos.x, first_pos.y, first_pos.z])
		print("Camera last pos:  (%.2f, %.2f, %.2f)" % [last_pos.x, last_pos.y, last_pos.z])
		print("Camera max drift: %.4f units over %.1fs (%d frames)" % [max_drift, OBSERVE_DURATION, _cam_positions.size()])
		if max_drift > 0.1:
			print("WARNING: Camera was NOT stationary — drift detected!")

	print("Total LOD events: %d" % log_entries.size())

	# Count by event type
	var creates: int = 0
	var fade_outs: int = 0
	var fade_out_hyst: int = 0
	var recycles: int = 0
	for e in log_entries:
		match e["event"]:
			"create": creates += 1
			"fade_out_start": fade_outs += 1
			"fade_out_hysteresis": fade_out_hyst += 1
			"recycled": recycles += 1

	print("  creates: %d" % creates)
	print("  fade_out_start (not visible): %d" % fade_outs)
	print("  fade_out_hysteresis (dist > destroy): %d" % fade_out_hyst)
	print("  recycled: %d" % recycles)

	# Breakdown by type
	var type_counts: Dictionary = {}
	for e in log_entries:
		if e["event"] == "create":
			if not type_counts.has(e["type"]):
				type_counts[e["type"]] = 0
			type_counts[e["type"]] += 1
	print("  creates by type: ", type_counts)

	# Group creates by time bucket (0.1s buckets) to see bursts
	var time_buckets: Dictionary = {}
	for e in log_entries:
		if e["event"] == "create":
			var bucket: float = snappedf(e["time"], 0.1)
			if not time_buckets.has(bucket):
				time_buckets[bucket] = 0
			time_buckets[bucket] += 1

	print("\n--- Create events by time bucket (0.1s) ---")
	var bucket_keys: Array = time_buckets.keys()
	bucket_keys.sort()
	for bk in bucket_keys:
		print("  t=%.1fs: %d creates" % [bk, time_buckets[bk]])

	# Find objects that were created AND then faded out — these are the poppers
	var obj_lifecycle: Dictionary = {}  # key -> {create_time, fade_time, create_dist, fade_dist, pos, radius}
	for e in log_entries:
		var key: String = e["key"]
		if not obj_lifecycle.has(key):
			obj_lifecycle[key] = {"events": []}
		obj_lifecycle[key]["events"].append({"time": e["time"], "event": e["event"], "dist": e["dist"], "pos": e["pos"], "radius": e["radius"]})

	# Find poppers: created then faded out within the observation period
	var poppers: Array = []
	var stable: int = 0
	for key in obj_lifecycle.keys():
		var lifecycle: Dictionary = obj_lifecycle[key]
		var events: Array = lifecycle["events"]
		var has_create: bool = false
		var has_fade: bool = false
		var create_time: float = 0.0
		var fade_time: float = 0.0
		var create_dist: float = 0.0
		var fade_dist: float = 0.0
		var pos: Vector3 = Vector3.ZERO
		var radius: float = 0.0
		for ev in events:
			if ev["event"] == "create":
				has_create = true
				create_time = ev["time"]
				create_dist = ev["dist"]
				pos = ev["pos"]
				radius = ev["radius"]
			elif ev["event"] in ["fade_out_start", "fade_out_hysteresis"]:
				has_fade = true
				fade_time = ev["time"]
				fade_dist = ev["dist"]

		if has_create and has_fade:
			poppers.append({
				"key": key,
				"create_time": create_time,
				"fade_time": fade_time,
				"lifetime": fade_time - create_time,
				"create_dist": create_dist,
				"fade_dist": fade_dist,
				"pos": pos,
				"radius": radius
			})
		elif has_create and not has_fade:
			stable += 1

	print("\n--- POPPING ANALYSIS ---")
	print("Stable objects (created, never faded): %d" % stable)
	print("Popped objects (created then faded): %d" % poppers.size())

	if poppers.size() > 0:
		# Sort by lifetime (shortest first = most jarring)
		poppers.sort_custom(func(a, b): return a["lifetime"] < b["lifetime"])
		print("\n--- Top 20 shortest-lived objects (most jarring pops) ---")
		for i in range(mini(poppers.size(), 20)):
			var p: Dictionary = poppers[i]
			print("  %s: life=%.2fs create_d=%.1f fade_d=%.1f r=%.2f pos=(%.1f,%.1f,%.1f)" % [
				p["key"], p["lifetime"], p["create_dist"], p["fade_dist"],
				p["radius"], p["pos"].x, p["pos"].y, p["pos"].z
			])

		# Analyze WHY they popped
		print("\n--- Pop causes ---")
		var cause_hysteresis: int = 0
		var cause_not_visible: int = 0
		for p in poppers:
			# Check the fade event type
			var key: String = p["key"]
			var events: Array = obj_lifecycle[key]["events"]
			for ev in events:
				if ev["event"] == "fade_out_hysteresis":
					cause_hysteresis += 1
					break
				elif ev["event"] == "fade_out_start":
					cause_not_visible += 1
					break
		print("  Hysteresis (dist > %d): %d" % [390, cause_hysteresis])
		print("  Not visible (< 4px): %d" % cause_not_visible)

		# Distance distribution at creation
		print("\n--- Create distance distribution ---")
		var dist_buckets: Dictionary = {}
		for p in poppers:
			var bucket: int = int(p["create_dist"] / 50.0) * 50
			if not dist_buckets.has(bucket):
				dist_buckets[bucket] = 0
			dist_buckets[bucket] += 1
		var dist_keys: Array = dist_buckets.keys()
		dist_keys.sort()
		for dk in dist_keys:
			print("  %d-%d units: %d objects" % [dk, dk + 50, dist_buckets[dk]])

	print("\n=== DONE ===")
	_phase = 3
	get_tree().quit()

func _find_node_by_script(node: Node, script_name: String) -> Node:
	var scr = node.get_script()
	if scr and scr.resource_path.findn(script_name) >= 0:
		return node
	for child in node.get_children():
		var found := _find_node_by_script(child, script_name)
		if found:
			return found
	return null

func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_node_by_type(child, type_name)
		if found:
			return found
	return null
