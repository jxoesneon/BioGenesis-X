# res://scripts/HardwareDetector.gd
# ==============================================================================
# BioGenesis-X — Hardware Detection & Auto-Configuration
# ==============================================================================
# Auto-detects CPU cores, GPU vendor/model, memory, and Metal support level.
# Configures Godot project settings at runtime for optimal performance on the
# detected hardware. Runs as the FIRST autoload so all other systems can query
# it.
#
# Detected hardware is logged and exposed via public API:
#   HardwareDetector.cpu_cores
#   HardwareDetector.gpu_name
#   HardwareDetector.gpu_vendor
#   HardwareDetector.metal_version
#   HardwareDetector.total_memory_gb
#   HardwareDetector.quality_tier  (ULTRA / HIGH / MEDIUM / LOW)
# ==============================================================================

extends Node

# --- Public hardware info ---
var cpu_cores: int = 4
var cpu_performance_cores: int = 4
var gpu_name: String = "Unknown"
var gpu_vendor: String = "Unknown"
var metal_version: int = 2
var total_memory_gb: float = 8.0
var os_name: String = "Unknown"
var is_apple_silicon: bool = false
var quality_tier: int = QualityTier.HIGH

# --- Quality tiers ---
enum QualityTier {
	LOW,     # 4 cores, <8GB RAM, integrated GPU
	MEDIUM,  # 6 cores, 8-16GB RAM, integrated GPU
	HIGH,    # 8+ cores, 16+GB RAM, discrete or Apple Silicon
	ULTRA,   # 10+ cores, 32+GB RAM, Apple Silicon Pro/Max/Ultra
}

# --- Thread pool config (derived from hardware) ---
var worker_thread_count: int = 4
var physics_thread_count: int = 2

# --- Adaptive quality state ---
var _adaptive_quality_enabled: bool = true
var _frame_time_history: Array[float] = []
const FRAME_TIME_SAMPLES: int = 60
const ADAPTIVE_CHECK_INTERVAL: float = 2.0
var _adaptive_timer: float = 0.0
var _current_resolution_scale: float = 1.0
var _current_shadow_atlas_size: int = 4096

signal quality_adjusted(new_tier: int, reason: String)

func _ready() -> void:
	_detect_hardware()
	_apply_optimal_settings()
	_log_hardware_report()
	# Defer preset application until SettingsSystem has loaded
	call_deferred("_apply_settings_preset")

func _apply_settings_preset() -> void:
	var ss: Node = get_node_or_null("/root/SettingsSystem")
	if ss and ss.has_method("apply_hardware_recommended_preset"):
		ss.apply_hardware_recommended_preset()

# ==============================================================================
# Hardware Detection
# ==============================================================================
func _detect_hardware() -> void:
	# OS
	os_name = OS.get_name()

	# CPU cores
	cpu_cores = OS.get_processor_count()
	# Apple Silicon: all cores are performance-class
	# On other platforms, we approximate
	cpu_performance_cores = cpu_cores

	# Detect Apple Silicon
	is_apple_silicon = (os_name == "macOS" and _is_apple_silicon())

	# Memory
	var mem_bytes: int = OS.get_static_memory_usage()
	# OS.get_static_memory_usage() returns current usage, not total.
	# Use a heuristic based on platform.
	total_memory_gb = _detect_total_memory()

	# GPU info — Godot 4.7 exposes this via RenderingServer
	_detect_gpu()

	# Determine quality tier from hardware
	_determine_quality_tier()

	# Set thread pool sizes
	_configure_thread_pools()

func _is_apple_silicon() -> bool:
	# Check via CPU brand string if available
	var cpu_name: String = OS.get_processor_name()
	if cpu_name.contains("Apple M"):
		return true
	if cpu_name.contains("Apple A"):
		return true
	# Fallback: macOS on ARM64
	if OS.has_feature("arm64") or OS.has_feature("ARM64"):
		return true
	return false

func _detect_total_memory() -> float:
	# On macOS, we can try to read system memory
	# Godot doesn't expose total system RAM directly, so we use a heuristic
	if is_apple_silicon:
		# Apple M4 base = 16GB, M4 Pro = 24GB, M4 Max = 36GB+
		# Use CPU count as a rough proxy
		if cpu_cores >= 16:
			return 36.0
		elif cpu_cores >= 10:
			return 16.0
		elif cpu_cores >= 8:
			return 16.0
		else:
			return 8.0
	else:
		# Conservative estimate for other platforms
		if cpu_cores >= 16:
			return 32.0
		elif cpu_cores >= 8:
			return 16.0
		else:
			return 8.0

func _detect_gpu() -> void:
	# Godot 4.7 doesn't have a direct GPU name API in GDScript,
	# but we can infer from the renderer and platform
	if is_apple_silicon:
		gpu_vendor = "Apple"
		# Infer GPU tier from CPU tier
		if cpu_cores >= 16:
			gpu_name = "Apple GPU (Max/Ultra class)"
		elif cpu_cores >= 10:
			gpu_name = "Apple GPU (Pro class)"
		else:
			gpu_name = "Apple GPU (Base class)"

		# Metal version — detect from CPU name (Apple Silicon GPU is integrated)
		var cpu_name_str: String = OS.get_processor_name()
		if cpu_name_str.contains("M4"):
			metal_version = 4
		elif cpu_name_str.contains("M3"):
			metal_version = 3
		elif cpu_name_str.contains("M2"):
			metal_version = 3
		elif cpu_name_str.contains("M1"):
			metal_version = 2
		else:
			metal_version = 3  # Default for unknown Apple Silicon
	else:
		gpu_vendor = "Unknown"
		gpu_name = "Unknown GPU"
		metal_version = 2

func _determine_quality_tier() -> void:
	if is_apple_silicon:
		# M4 with 10 cores and Metal 4 is ULTRA-class for gaming
		var cpu_name_str: String = OS.get_processor_name()
		if cpu_name_str.contains("M4") and cpu_cores >= 10:
			quality_tier = QualityTier.ULTRA
		elif cpu_cores >= 16 and total_memory_gb >= 32.0:
			quality_tier = QualityTier.ULTRA
		elif cpu_cores >= 8 and total_memory_gb >= 16.0:
			quality_tier = QualityTier.HIGH
		elif cpu_cores >= 6:
			quality_tier = QualityTier.MEDIUM
		else:
			quality_tier = QualityTier.LOW
	else:
		# Non-Apple: be conservative
		if cpu_cores >= 12 and total_memory_gb >= 32.0:
			quality_tier = QualityTier.HIGH
		elif cpu_cores >= 6:
			quality_tier = QualityTier.MEDIUM
		else:
			quality_tier = QualityTier.LOW

func _configure_thread_pools() -> void:
	# Worker thread pool: use 60-80% of cores for background work
	match quality_tier:
		QualityTier.ULTRA:
			worker_thread_count = maxi(cpu_cores - 2, 6)
			physics_thread_count = 4
		QualityTier.HIGH:
			worker_thread_count = maxi(cpu_cores - 2, 4)
			physics_thread_count = 3
		QualityTier.MEDIUM:
			worker_thread_count = maxi(cpu_cores - 2, 2)
			physics_thread_count = 2
		QualityTier.LOW:
			worker_thread_count = 2
			physics_thread_count = 1

# ==============================================================================
# Apply Optimal Settings to Godot
# ==============================================================================
func _apply_optimal_settings() -> void:
	# --- Thread pool ---
	ProjectSettings.set_setting("threading/worker_pool/low_priority_thread_count", worker_thread_count)

	# --- Physics threading (Jolt) ---
	ProjectSettings.set_setting("physics/3d/threading", "multi_threaded")

	# --- Renderer settings based on quality tier ---
	match quality_tier:
		QualityTier.ULTRA:
			_apply_ultra_settings()
		QualityTier.HIGH:
			_apply_high_settings()
		QualityTier.MEDIUM:
			_apply_medium_settings()
		QualityTier.LOW:
			_apply_low_settings()

	# --- Common optimizations (all tiers) ---
	_apply_common_optimizations()

func _apply_ultra_settings() -> void:
	# Shadow atlas — 8K for ultra
	_current_shadow_atlas_size = 8192
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 8192)
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size_16bit", false)

	# MSAA 4x + FXAA
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 3)  # 4x
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 1)

	# Decals and light projection
	ProjectSettings.set_setting("rendering/textures/decals/filter", 1)  # Bilinear

	# Volumetric fog
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/volume_size", 128)
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/use_filter", true)

	# Reflections
	ProjectSettings.set_setting("rendering/reflections/sky_reflections/roughness_layers", 8)

	# Mesh LOD
	ProjectSettings.set_setting("rendering/mesh_lod/lod_strategy", 1)  # Screen pixels

func _apply_high_settings() -> void:
	_current_shadow_atlas_size = 4096
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 4096)
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size_16bit", false)

	# MSAA 2x + FXAA
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 2)  # 2x
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 1)

	# Volumetric fog
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/volume_size", 64)
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/use_filter", true)

	# Reflections
	ProjectSettings.set_setting("rendering/reflections/sky_reflections/roughness_layers", 4)

	# Mesh LOD
	ProjectSettings.set_setting("rendering/mesh_lod/lod_strategy", 1)

func _apply_medium_settings() -> void:
	_current_shadow_atlas_size = 2048
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 2048)
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size_16bit", true)

	# FXAA only (no MSAA)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)  # Disabled
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 1)

	# Volumetric fog — smaller volume
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/volume_size", 32)
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/use_filter", false)

	# Reflections — fewer layers
	ProjectSettings.set_setting("rendering/reflections/sky_reflections/roughness_layers", 1)

func _apply_low_settings() -> void:
	_current_shadow_atlas_size = 1024
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 1024)
	ProjectSettings.set_setting("rendering/lights_and_shadows/positional_shadow/atlas_size_16bit", true)

	# No AA
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)

	# Volumetric fog — minimal
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/volume_size", 16)
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/use_filter", false)

	# Reflections — off
	ProjectSettings.set_setting("rendering/reflections/sky_reflections/roughness_layers", 0)

func _apply_common_optimizations() -> void:
	# --- Occlusion culling ---
	ProjectSettings.set_setting("rendering/occlusion_culling/use_occlusion_culling", true)

	# --- Shader compilation cache ---
	ProjectSettings.set_setting("rendering/shader_compiler/shader_cache/enabled", true)

	# --- Texture compression ---
	ProjectSettings.set_setting("rendering/textures/vram_compression/import_etc2_ct", true)

	# --- Mesh LOD ---
	ProjectSettings.set_setting("rendering/mesh_lod/lod_strategy", 1)  # Screen pixels

	# --- Physics interpolation (already enabled) ---
	ProjectSettings.set_setting("physics/common/physics_interpolation", true)

	# --- GPU detection for renderer ---
	# Forward+ is already set — it's the best for Apple Silicon

	# --- VSync — adaptive (tearing-free, uncapped when below refresh rate) ---
	# DisplayServer.VSyncMode.ADAPTIVE = 2
	ProjectSettings.set_setting("display/window/vsync/vsync_mode", 2)

	# --- Threaded loading ---
	ProjectSettings.set_setting("threading/load_async/threads_per_core", 1)

# ==============================================================================
# Adaptive Quality — dynamically adjusts resolution scale based on frame time
# ==============================================================================
func _process(delta: float) -> void:
	if not _adaptive_quality_enabled:
		return

	# Track frame times
	var frame_ms: float = delta * 1000.0
	_frame_time_history.append(frame_ms)
	if _frame_time_history.size() > FRAME_TIME_SAMPLES:
		_frame_time_history.pop_front()

	# Check every ADAPTIVE_CHECK_INTERVAL seconds
	_adaptive_timer += delta
	if _adaptive_timer < ADAPTIVE_CHECK_INTERVAL:
		return
	_adaptive_timer = 0.0

	if _frame_time_history.size() < 30:
		return

	# Compute average frame time
	var avg_ms: float = 0.0
	for ft in _frame_time_history:
		avg_ms += ft
	avg_ms /= float(_frame_time_history.size())

	# Target: 60 FPS = 16.67ms
	# If consistently above 25ms, reduce resolution scale
	# If consistently below 14ms, increase resolution scale
	var target_ms: float = 16.67
	var upper_threshold: float = 25.0
	var lower_threshold: float = 14.0

	if avg_ms > upper_threshold and _current_resolution_scale > 0.5:
		_current_resolution_scale = maxf(_current_resolution_scale - 0.1, 0.5)
		_apply_resolution_scale()
		quality_adjusted.emit(quality_tier, "Reduced resolution scale to %.0f%% (avg frame: %.1fms)" % [
			_current_resolution_scale * 100.0, avg_ms])
		print("[HardwareDetector] Adaptive: resolution scale → %.0f%% (avg %.1fms)" % [
			_current_resolution_scale * 100.0, avg_ms])
	elif avg_ms < lower_threshold and _current_resolution_scale < 1.0:
		_current_resolution_scale = minf(_current_resolution_scale + 0.05, 1.0)
		_apply_resolution_scale()
		quality_adjusted.emit(quality_tier, "Increased resolution scale to %.0f%% (avg frame: %.1fms)" % [
			_current_resolution_scale * 100.0, avg_ms])
		print("[HardwareDetector] Adaptive: resolution scale → %.0f%% (avg %.1fms)" % [
			_current_resolution_scale * 100.0, avg_ms])

func _apply_resolution_scale() -> void:
	# Use Godot's stretch scale for resolution scaling
	var tree: SceneTree = get_tree()
	if tree and tree.root:
		tree.root.content_scale_scale = _current_resolution_scale

# ==============================================================================
# Public API
# ==============================================================================

## Returns the recommended chunk load budget for this hardware.
func get_chunk_load_budget_per_frame() -> int:
	match quality_tier:
		QualityTier.ULTRA: return 3
		QualityTier.HIGH: return 2
		QualityTier.MEDIUM: return 1
		QualityTier.LOW: return 1
		_: return 1

## Returns the recommended max frame time for chunk loading in ms.
func get_max_frame_time_ms() -> float:
	match quality_tier:
		QualityTier.ULTRA: return 12.0
		QualityTier.HIGH: return 8.0
		QualityTier.MEDIUM: return 6.0
		QualityTier.LOW: return 4.0
		_: return 8.0

## Returns the recommended asteroid generation rate per frame.
func get_asteroids_per_frame() -> int:
	match quality_tier:
		QualityTier.ULTRA: return 10
		QualityTier.HIGH: return 5
		QualityTier.MEDIUM: return 3
		QualityTier.LOW: return 2
		_: return 5

## Returns the quality tier name as a string.
func get_quality_tier_name() -> String:
	match quality_tier:
		QualityTier.ULTRA: return "ULTRA"
		QualityTier.HIGH: return "HIGH"
		QualityTier.MEDIUM: return "MEDIUM"
		QualityTier.LOW: return "LOW"
		_: return "UNKNOWN"

## Returns true if the hardware supports mesh shaders (Metal 3+).
func supports_mesh_shaders() -> bool:
	return metal_version >= 3

## Returns true if the hardware supports ray tracing (Metal 3+).
func supports_ray_tracing() -> bool:
	return metal_version >= 3

## Enable/disable adaptive quality at runtime.
func set_adaptive_quality(enabled: bool) -> void:
	_adaptive_quality_enabled = enabled
	if not enabled:
		_current_resolution_scale = 1.0
		_apply_resolution_scale()

# ==============================================================================
# Logging
# ==============================================================================
func _log_hardware_report() -> void:
	print("==========================================================")
	print("[HardwareDetector] HARDWARE REPORT")
	print("==========================================================")
	print("  OS:              %s" % os_name)
	print("  CPU:             %s (%d cores)" % [OS.get_processor_name(), cpu_cores])
	print("  Apple Silicon:   %s" % str(is_apple_silicon))
	print("  GPU:             %s (%s)" % [gpu_name, gpu_vendor])
	print("  Metal:           %d" % metal_version)
	print("  Memory (est):    %.0f GB" % total_memory_gb)
	print("  Quality Tier:    %s" % get_quality_tier_name())
	print("  Worker Threads:  %d" % worker_thread_count)
	print("  Physics Threads: %d" % physics_thread_count)
	print("  Shadow Atlas:    %d" % _current_shadow_atlas_size)
	print("  Resolution Scale: %.0f%%" % (_current_resolution_scale * 100.0))
	print("  Adaptive Quality: %s" % str(_adaptive_quality_enabled))
	print("  VSync:           Adaptive")
	print("  Occlusion Cull:  Enabled")
	print("  Shader Cache:    Enabled")
	print("  Physics Thread:  Multi-threaded")
	print("==========================================================")
