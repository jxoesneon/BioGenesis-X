# res://scripts/test_gpu_profile.gd
# ==============================================================================
# BioGenesis-X — Full GPU Profile Test
# ==============================================================================
# Profiles the full game session: boot → main menu → flight → galaxy map →
# warp to new system. Captures GPU/rendering metrics at each phase and
# prints a comprehensive report.
#
# Run headless:
#   Godot --headless --script res://scripts/test_gpu_profile.gd
# ==============================================================================

extends SceneTree

# --- Phase tracking ---
enum Phase {
	BOOT,
	MAIN_MENU,
	LOADING_FLIGHT,
	FLIGHT_IDLE,
	FLIGHT_MAP_OPEN,
	FLIGHT_MAP_WARP,
	FLIGHT_POST_WARP,
	COMPLETE,
}

var _phase: int = Phase.BOOT
var _phase_start: float = 0.0
var _phase_samples: Array[Dictionary] = []
var _phase_reports: Array[Dictionary] = []
var _elapsed: float = 0.0
var _sample_timer: float = 0.0
var _profile_timer: Timer = null

const SAMPLE_INTERVAL: float = 0.1  # 10 Hz sampling
const PHASE_DURATION: float = 5.0   # Seconds per phase

func _init() -> void:
	print("\n" + "=".repeat(80))
	print("  BioGenesis-X — Full GPU Profile")
	print("  Phases: Boot → Menu → Flight → Map → Warp → Post-Warp")
	print("=".repeat(80))
	# Defer phase entry to the first process tick so autoloads are ready
	call_deferred("_start_profiling")


func _start_profiling() -> void:
	_phase_start = 0.0
	_enter_phase(Phase.BOOT)
	# SceneTree._process isn't called automatically in Godot 4.
	# Use a Timer to drive the profiling loop.
	_profile_timer = Timer.new()
	_profile_timer.wait_time = SAMPLE_INTERVAL
	_profile_timer.autostart = true
	_profile_timer.timeout.connect(_on_profile_tick)
	root.add_child(_profile_timer)


func _on_profile_tick() -> void:
	_elapsed += SAMPLE_INTERVAL

	# Sample metrics at every tick
	_sample_gpu()

	# Phase transitions
	var phase_elapsed: float = _elapsed - _phase_start
	if phase_elapsed >= PHASE_DURATION:
		_advance_phase()


func _enter_phase(phase: int) -> void:
	_phase = phase
	_phase_start = _elapsed
	_phase_samples.clear()

	var phase_name: String = _phase_name(phase)
	print("\n[GPU Profile] === Phase: %s (t=%.1fs) ===" % [phase_name, _elapsed])

	match phase:
		Phase.BOOT:
			print("[GPU Profile] Collecting boot-time hardware and GPU info...")
			_collect_hardware_info()
		Phase.MAIN_MENU:
			# Try to load main menu
			print("[GPU Profile] Loading main menu scene...")
			change_scene_to_file("res://scenes/main_menu.tscn")
		Phase.LOADING_FLIGHT:
			print("[GPU Profile] Transitioning to flight scene...")
			var lsm := _get_autoload("LoadingScreenManager")
			if lsm and lsm.has_method("transition_to_scene"):
				lsm.transition_to_scene("res://scenes/space_flight.tscn")
			else:
				change_scene_to_file("res://scenes/space_flight.tscn")
		Phase.FLIGHT_IDLE:
			print("[GPU Profile] Flight scene active — sampling idle flight GPU usage...")
		Phase.FLIGHT_MAP_OPEN:
			print("[GPU Profile] Simulating galaxy map open...")
			_simulate_galaxy_map_open()
		Phase.FLIGHT_MAP_WARP:
			print("[GPU Profile] Simulating warp to new system...")
			_simulate_warp()
		Phase.FLIGHT_POST_WARP:
			print("[GPU Profile] Post-warp — sampling recovery GPU usage...")
		Phase.COMPLETE:
			_print_full_report()
			quit()


func _advance_phase() -> void:
	# Record phase summary
	if _phase_samples.size() > 0:
		_phase_reports.append(_summarize_phase(_phase, _phase_samples))
	match _phase:
		Phase.BOOT: _enter_phase(Phase.MAIN_MENU)
		Phase.MAIN_MENU: _enter_phase(Phase.LOADING_FLIGHT)
		Phase.LOADING_FLIGHT: _enter_phase(Phase.FLIGHT_IDLE)
		Phase.FLIGHT_IDLE: _enter_phase(Phase.FLIGHT_MAP_OPEN)
		Phase.FLIGHT_MAP_OPEN: _enter_phase(Phase.FLIGHT_MAP_WARP)
		Phase.FLIGHT_MAP_WARP: _enter_phase(Phase.FLIGHT_POST_WARP)
		Phase.FLIGHT_POST_WARP: _enter_phase(Phase.COMPLETE)
		_: _enter_phase(Phase.COMPLETE)


func _phase_name(phase: int) -> String:
	match phase:
		Phase.BOOT: return "BOOT"
		Phase.MAIN_MENU: return "MAIN_MENU"
		Phase.LOADING_FLIGHT: return "LOADING_FLIGHT"
		Phase.FLIGHT_IDLE: return "FLIGHT_IDLE"
		Phase.FLIGHT_MAP_OPEN: return "FLIGHT_MAP_OPEN"
		Phase.FLIGHT_MAP_WARP: return "FLIGHT_MAP_WARP"
		Phase.FLIGHT_POST_WARP: return "FLIGHT_POST_WARP"
		Phase.COMPLETE: return "COMPLETE"
		_: return "UNKNOWN"


func _collect_hardware_info() -> void:
	var hw := _get_autoload("HardwareDetector")
	if hw:
		print("  GPU: %s (%s)" % [hw.gpu_name, hw.gpu_vendor])
		print("  CPU cores: %d (perf: %d)" % [hw.cpu_cores, hw.cpu_performance_cores])
		print("  Memory: %.1f GB" % hw.total_memory_gb)
		print("  Quality tier: %s" % _quality_tier_name(hw.quality_tier))
		print("  Apple Silicon: %s" % hw.is_apple_silicon)
		print("  OS: %s" % hw.os_name)
	else:
		print("  [WARNING] HardwareDetector not found")

	# Rendering device info
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd:
		print("  RenderingDevice available: %s" % rd.get_device_name())
	else:
		print("  RenderingDevice: not available (headless mode)")

	# Project rendering settings
	var rs := RenderingServer
	print("  Renderer: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	print("  MSAA 3D: %s" % str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)))
	print("  Screen-space AA: %s" % str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)))
	print("  Occlusion culling: %s" % str(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)))
	print("  LOD strategy: %s" % str(ProjectSettings.get_setting("rendering/mesh_lod/lod_strategy", 0)))
	print("  Volumetric fog: %s" % str(ProjectSettings.get_setting("rendering/environment/volumetric_fog/use_filter", false)))
	print("  Physics engine: %s" % ProjectSettings.get_setting("physics/3d/physics_engine", "default"))
	print("  Physics threading: %s" % ProjectSettings.get_setting("physics/3d/threading", "single_threaded"))


func _quality_tier_name(tier: int) -> String:
	match tier:
		0: return "LOW"
		1: return "MEDIUM"
		2: return "HIGH"
		3: return "ULTRA"
		_: return "UNKNOWN"


func _sample_gpu() -> void:
	var sample: Dictionary = {
		"time": _elapsed,
		"phase": _phase_name(_phase),
	}

	# Built-in performance monitors (available in headless too)
	sample["fps"] = Performance.get_monitor(Performance.TIME_FPS)
	sample["frame_time_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	sample["frame_time_physics_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	sample["object_count"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	sample["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	sample["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	sample["video_mem_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	# RENDER_TEXTURE_MEM_USED returns garbage on Metal (uint64 overflow — known Godot bug).
	# Track buffer mem instead as a reliable GPU memory proxy.
	sample["buffer_mem_mb"] = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1024.0 / 1024.0

	# Physics monitors
	sample["physics_objects"] = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	sample["physics_pairs"] = Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
	sample["physics_islands"] = Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)

	# Audio
	sample["audio_latency_ms"] = Performance.get_monitor(Performance.AUDIO_OUTPUT_LATENCY) * 1000.0

	# NeuralRegen compute (if available)
	var neural := _get_autoload("NeuralRegen")
	if neural and neural.get("_compute_enabled"):
		sample["neural_compute"] = "enabled"

	# GPUComputeManager
	var _gpu_mgr := _get_autoload("GPUComputeManager")

	_phase_samples.append(sample)


func _summarize_phase(phase: int, samples: Array[Dictionary]) -> Dictionary:
	var report: Dictionary = {
		"phase": _phase_name(phase),
		"samples": samples.size(),
		"duration_s": _elapsed - _phase_start,
	}

	if samples.is_empty():
		return report

	# Compute averages and peaks
	var metrics: Array[String] = [
		"fps", "frame_time_ms", "frame_time_physics_ms",
		"object_count", "draw_calls", "primitives",
		"physics_objects", "physics_pairs", "physics_islands",
		"audio_latency_ms",
	]

	for metric in metrics:
		var values: Array[float] = []
		for s in samples:
			if s.has(metric) and s[metric] != null:
				values.append(float(s[metric]))
		if values.is_empty():
			continue
		var avg: float = 0.0
		var peak: float = 0.0
		var min_val: float = INF
		for v in values:
			avg += v
			peak = maxf(peak, v)
			min_val = minf(min_val, v)
		avg /= float(values.size())
		report["%s_avg" % metric] = avg
		report["%s_peak" % metric] = peak
		report["%s_min" % metric] = min_val

	return report


func _simulate_galaxy_map_open() -> void:
	var flight_hud := _find_node_in_scene("FlightHUDUI")
	if flight_hud and flight_hud.has_method("_toggle_galaxy_map"):
		flight_hud._toggle_galaxy_map()
		print("[GPU Profile] Galaxy map toggled open via FlightHUDUI")
	else:
		print("[GPU Profile] FlightHUDUI not found — cannot open galaxy map")


func _simulate_warp() -> void:
	# Try to trigger a wave engine jump via FlightController
	var flight_ctrl := _find_node_in_scene("FlightController")
	if flight_ctrl:
		if flight_ctrl.has_method("engage_wave_engine"):
			flight_ctrl.engage_wave_engine()
			print("[GPU Profile] Wave engine engaged via FlightController")
		elif "simulated_wave" in flight_ctrl:
			flight_ctrl.simulated_wave = true
			print("[GPU Profile] Wave engine simulated via property")
		else:
			print("[GPU Profile] FlightController found but no wave engine API")
	else:
		print("[GPU Profile] FlightController not found — cannot warp")


func _find_node_in_scene(node_name: String) -> Node:
	if not current_scene:
		return null
	return _find_node_recursive(current_scene, node_name)


func _find_node_recursive(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var result := _find_node_recursive(child, name)
		if result:
			return result
	return null


func _get_autoload(name: String) -> Node:
	if root and root.has_node(name):
		return root.get_node(name)
	return null


func _print_full_report() -> void:
	print("\n" + "=".repeat(80))
	print("  GPU PROFILE REPORT — BioGenesis-X")
	print("  Total elapsed: %.1fs | Phases: %d" % [_elapsed, _phase_reports.size()])
	print("=".repeat(80))

	# Hardware summary
	print("\n--- HARDWARE ---")
	_collect_hardware_info()

	# Phase-by-phase report
	print("\n--- PHASE METRICS ---")
	for report in _phase_reports:
		_print_phase_report(report)

	# Cross-phase comparison
	print("\n--- CROSS-PHASE COMPARISON ---")
	_print_comparison_table()

	print("\n" + "=".repeat(80))
	print("  GPU PROFILE COMPLETE")
	print("=".repeat(80) + "\n")


func _print_phase_report(report: Dictionary) -> void:
	print("\n  [%s] — %.1fs, %d samples" % [report.phase, report.duration_s, report.samples])

	var metrics: Array[Dictionary] = [
		{"key": "fps", "label": "FPS", "unit": "", "fmt": "%.1f"},
		{"key": "frame_time_ms", "label": "Frame Time", "unit": "ms", "fmt": "%.2f"},
		{"key": "frame_time_physics_ms", "label": "Physics Time", "unit": "ms", "fmt": "%.2f"},
		{"key": "draw_calls", "label": "Draw Calls", "unit": "", "fmt": "%.0f"},
		{"key": "object_count", "label": "Objects", "unit": "", "fmt": "%.0f"},
		{"key": "primitives", "label": "Primitives", "unit": "", "fmt": "%.0f"},
		{"key": "video_mem_mb", "label": "Video Mem", "unit": "MB", "fmt": "%.0f"},
		{"key": "buffer_mem_mb", "label": "Buffer Mem", "unit": "MB", "fmt": "%.0f"},
		{"key": "physics_objects", "label": "Physics Objects", "unit": "", "fmt": "%.0f"},
		{"key": "physics_pairs", "label": "Physics Pairs", "unit": "", "fmt": "%.0f"},
		{"key": "physics_islands", "label": "Physics Islands", "unit": "", "fmt": "%.0f"},
		{"key": "audio_latency_ms", "label": "Audio Latency", "unit": "ms", "fmt": "%.2f"},
	]

	for m in metrics:
		var avg_key: String = "%s_avg" % m.key
		var peak_key: String = "%s_peak" % m.key
		var min_key: String = "%s_min" % m.key
		if report.has(avg_key):
			var avg_val: float = report[avg_key]
			var peak_val: float = report[peak_key] if report.has(peak_key) else 0.0
			var min_val: float = report[min_key] if report.has(min_key) else 0.0
			print("    %-20s  avg: %s%s  peak: %s%s  min: %s%s" % [
				m.label,
				m.fmt % avg_val, m.unit,
				m.fmt % peak_val, m.unit,
				m.fmt % min_val, m.unit,
			])


func _print_comparison_table() -> void:
	# Print a compact table: rows = metrics, columns = phases
	var phases: Array[String] = []
	for r in _phase_reports:
		phases.append(r.phase)

	var metrics: Array[String] = [
		"fps", "frame_time_ms", "draw_calls", "primitives",
		"physics_objects", "physics_pairs",
	]

	# Header
	var header: String = "  %-22s" % "Metric"
	for p in phases:
		header += " | %12s" % p
	print(header)
	print("  " + "-".repeat(header.length() - 2))

	# Rows
	for m in metrics:
		var row: String = "  %-22s" % m.replace("_", " ").capitalize()
		for r in _phase_reports:
			var key: String = "%s_avg" % m
			if r.has(key):
				row += " | %12.1f" % float(r[key])
			else:
				row += " | %12s" % "—"
		print(row)
