extends Node

## LOD Benchmark — measures real frame times
## Usage: godot --path . --resolution 1280x800 -- res://scenes/galaxy_map.tscn
## This script auto-injects into the scene via autoload

const FRAMES_TO_TEST := 300
const WARMUP_FRAMES := 30

var frame_times_us: PackedInt64Array = []
var _frame_count: int = 0
var _prev_time: int = 0
var _visuals: Node = null

func _ready() -> void:
	print("=== LOD FRAME BENCHMARK ===")
	print("Frames: %d (warmup: %d)" % [FRAMES_TO_TEST, WARMUP_FRAMES])

	# Wait a few frames for scene to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# Find GalaxyMapVisuals
	_visuals = _find_node_by_script(get_tree().root, "GalaxyMapVisuals.gd")
	if _visuals:
		print("Found GalaxyMapVisuals")
		_report_node_stats()
		# Move camera CLOSE to galactic center — optimized creates FogVolumes dynamically
		var cam := _find_node_by_type(get_tree().root, "Camera3D")
		if cam:
			cam.global_position = Vector3(20, 10, 40)
			cam.look_at(Vector3.ZERO)
			print("Camera moved to: ", cam.global_position, " (CLOSE to center — tests FogVolume LOD)")
	else:
		print("WARNING: GalaxyMapVisuals not found")

	_prev_time = Time.get_ticks_usec()
	frame_times_us.clear()
	_frame_count = 0
	set_process(true)

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

func _report_node_stats() -> void:
	var fog_count: int = 0
	var mesh_count: int = 0
	var mm_count: int = 0
	var total: int = 0
	_walk_count(_visuals, total, fog_count, mesh_count, mm_count)
	print("Nodes: %d (Fog: %d, Mesh: %d, MultiMesh: %d)" % [total, fog_count, mesh_count, mm_count])

func _walk_count(node: Node, total: int, fog: int, mesh: int, mm: int) -> void:
	total += 1
	if node is FogVolume:
		fog += 1
	elif node is MeshInstance3D:
		mesh += 1
	elif node is MultiMeshInstance3D:
		mm += 1
	for child in node.get_children():
		_walk_count(child, total, fog, mesh, mm)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_time := now - _prev_time
	_prev_time = now

	if _frame_count >= WARMUP_FRAMES:
		frame_times_us.append(frame_time)
	_frame_count += 1

	if _frame_count % 60 == 0 and _frame_count > 0:
		var recent_start := maxi(frame_times_us.size() - 60, 0)
		var recent := frame_times_us.slice(recent_start)
		var avg_us: float = 0.0
		for t in recent:
			avg_us += float(t)
		avg_us /= maxf(recent.size(), 1.0)
		# Count active fog volumes
		var fog_count: int = 0
		if _visuals and _visuals.has_method("get_active_fog_count"):
			fog_count = _visuals.get_active_fog_count()
		print("Frame %d — last 60 avg: %.2f ms (%.0f fps) — active fog: %d" % [_frame_count, avg_us / 1000.0, 1000000.0 / avg_us, fog_count])

	if _frame_count >= WARMUP_FRAMES + FRAMES_TO_TEST:
		_report()
		get_tree().quit()

func _report() -> void:
	print("\n=== BENCHMARK RESULTS ===")
	if frame_times_us.is_empty():
		print("No frames measured!")
		return

	var total_us: int = 0
	var min_us: int = frame_times_us[0]
	var max_us: int = frame_times_us[0]
	for t in frame_times_us:
		total_us += t
		if t < min_us: min_us = t
		if t > max_us: max_us = t

	var avg_ms: float = float(total_us) / frame_times_us.size() / 1000.0
	var min_ms: float = float(min_us) / 1000.0
	var max_ms: float = float(max_us) / 1000.0
	var fps: float = 1000.0 / avg_ms

	var sorted_arr := frame_times_us.duplicate()
	sorted_arr.sort()
	var p95_idx: int = clampi(int(sorted_arr.size() * 0.95), 0, sorted_arr.size() - 1)
	var p99_idx: int = clampi(int(sorted_arr.size() * 0.99), 0, sorted_arr.size() - 1)
	var p95_ms: float = float(sorted_arr[p95_idx]) / 1000.0
	var p99_ms: float = float(sorted_arr[p99_idx]) / 1000.0

	print("Frames: %d (after %d warmup)" % [frame_times_us.size(), WARMUP_FRAMES])
	print("Avg: %.2f ms (%.1f fps)" % [avg_ms, fps])
	print("Min: %.2f ms" % min_ms)
	print("Max: %.2f ms" % max_ms)
	print("P95: %.2f ms" % p95_ms)
	print("P99: %.2f ms" % p99_ms)
	if _visuals:
		_report_node_stats()
	print("=========================")
