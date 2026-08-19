class_name GalaxyMapVisuals
extends Node3D

## ============================================================================
## AAA+ Streaming Galaxy Map Visuals
## - Overview MultiMesh: persistent low-density galaxy shape (far LOD)
## - Sector Chunks: per-sector MultiMeshInstance3D with visibility_range LOD
## - SMBH core, dust clouds, indicators, route drawing preserved
## - Direct PackedFloat32Array buffer upload (zero GDScript transform loops)
## - LOD culling: objects < 4 pixels are skipped; FogVolumes created
##   dynamically only for nearby large objects
## ============================================================================

@export var star_shader: Shader = preload("res://scripts/star_glow.gdshader")

# --- Overview (persistent far-distance galaxy shape) ---
var overview_mmi: MultiMeshInstance3D
var overview_mm: MultiMesh

# --- Sector chunks (streamed in/out) ---
var sector_chunks: Dictionary = {} # Vector3i -> MultiMeshInstance3D
var star_quad_mesh: QuadMesh       # Shared mesh for all MultiMesh instances
var star_material: ShaderMaterial  # Shared material

# --- Indicators & Route ---
var current_indicator: MeshInstance3D
var selected_indicator: MeshInstance3D
var route_lines_instance: MeshInstance3D
var route_tracer_instance: MeshInstance3D
# Visited-system markers (MultiMesh of small rings highlighting explored stars)
var visited_mmi: MultiMeshInstance3D
var visited_mm: MultiMesh
var current_path: PackedVector3Array
var tracer_progress: float = 0.0

const MAP_SCALE = 0.01

# --- LOD Configuration ---
# Pixel threshold: objects smaller than this on screen are skipped
const PIXEL_THRESHOLD: float = 4.0
# FOV used for size calculations (must match camera FOV)
const CAMERA_FOV_DEG: float = 60.0
# Reference screen height for pixel calculations
const REF_SCREEN_HEIGHT: float = 1080.0
# Pre-computed: tan(pixel_threshold * fov_rad / screen_height)
# This converts object radius + distance to screen pixels
var _pixel_tan: float = 0.0
# Distance at which to switch from FogVolume to billboard LOD
# Objects closer than this get volumetric fog; farther get billboards
const FOG_LOD_DISTANCE: float = 300.0  # world units (create threshold)
# Hysteresis: destroy at 1.3x the create distance to prevent flickering
const FOG_LOD_DESTROY_DISTANCE: float = 390.0  # 300 * 1.3
# Fade duration in seconds — FogVolumes fade in/out smoothly
const FOG_FADE_DURATION: float = 0.5
# Maximum simultaneous FogVolumes — prevents GPU overload at dense galactic center
# Only the closest/largest FogVolumes are created when this limit is reached
const MAX_ACTIVE_FOG_VOLUMES: int = 100

# --- LOD Data Storage ---
# All galactic objects stored for per-frame culling
var _hii_data: Array[Dictionary] = []
var _snr_data: Array[Dictionary] = []
var _mc_data: Array[Dictionary] = []  # Molecular clouds

# MultiMesh billboards (always present, cheap)
var _hii_billboard_mm: MultiMesh = null
var _snr_billboard_mm: MultiMesh = null
var _mc_billboard_mm: MultiMesh = null

# Dynamic FogVolume tracking
# Each entry: { "fog": FogVolume, "mat": FogMaterial, "fade": float, "state": String }
# States: "fading_in", "visible", "fading_out"
var _active_fog_volumes: Dictionary = {}  # key -> Dictionary
var _fog_pool: Array[FogVolume] = []  # Reusable pool to avoid alloc/dealloc

# Spatial grid for fast LOD culling — buckets objects by cell
# Only cells near the camera are checked each frame
const GRID_CELL_SIZE: float = 200.0  # world units per cell
var _hii_grid: Dictionary = {}  # Vector3i -> Array[int] (indices into _hii_data)
var _snr_grid: Dictionary = {}  # Vector3i -> Array[int]
var _mc_grid: Dictionary = {}  # Vector3i -> Array[int] (molecular clouds)
var _grid_built: bool = false

# --- LOD Debug Logging ---
var _lod_log_enabled: bool = false
var _lod_log: Array[Dictionary] = []  # {time, event, key, type, pos, dist, radius}
var _lod_start_time: float = 0.0

# Camera reference for LOD calculations
var _lod_camera: Camera3D = null

func _ready() -> void:
	_setup_shared_mesh()
	_setup_overview_multimesh()
	_setup_galactic_core()
	_setup_dust_clouds()
	_setup_globular_clusters()
	_setup_hii_regions()
	_setup_molecular_clouds()
	_setup_satellite_galaxies()
	_setup_stellar_streams()
	_setup_supernova_remnants()
	_setup_planetary_nebulae()
	_setup_open_clusters()
	_setup_indicators()

	# Pre-compute pixel threshold constant
	# screen_pixels = radius / (distance * tan(fov/2)) * (screen_height / 2)
	# Solve for distance where screen_pixels = PIXEL_THRESHOLD:
	# max_distance = radius * screen_height / (2 * PIXEL_THRESHOLD * tan(fov/2))
	# We pre-compute the factor: screen_height / (2 * PIXEL_THRESHOLD * tan(fov/2))
	_pixel_tan = REF_SCREEN_HEIGHT / (2.0 * PIXEL_THRESHOLD * tan(deg_to_rad(CAMERA_FOV_DEG * 0.5)))

	# Find camera for LOD
	_find_camera()

	# Build spatial grid for fast culling
	_build_spatial_grid()

	# Start LOD processing
	set_process(true)

func _build_spatial_grid() -> void:
	_hii_grid.clear()
	_snr_grid.clear()
	for i in range(_hii_data.size()):
		var pos: Vector3 = _hii_data[i]["world_pos"]
		var cell := _grid_cell(pos)
		if not _hii_grid.has(cell):
			_hii_grid[cell] = []
		_hii_grid[cell].append(i)
	for i in range(_snr_data.size()):
		var pos: Vector3 = _snr_data[i]["world_pos"]
		var cell := _grid_cell(pos)
		if not _snr_grid.has(cell):
			_snr_grid[cell] = []
		_snr_grid[cell].append(i)
	for i in range(_mc_data.size()):
		var pos: Vector3 = _mc_data[i]["world_pos"]
		var cell := _grid_cell(pos)
		if not _mc_grid.has(cell):
			_mc_grid[cell] = []
		_mc_grid[cell].append(i)
	_grid_built = true

func _grid_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / GRID_CELL_SIZE)),
		int(floor(pos.y / GRID_CELL_SIZE)),
		int(floor(pos.z / GRID_CELL_SIZE))
	)

func _get_nearby_indices(grid: Dictionary, cam_pos: Vector3, max_dist: float) -> Array[int]:
	var cam_cell := _grid_cell(cam_pos)
	var cell_range: int = int(ceil(max_dist / GRID_CELL_SIZE)) + 1
	var result: Array[int] = []
	for x in range(cam_cell.x - cell_range, cam_cell.x + cell_range + 1):
		for y in range(cam_cell.y - cell_range, cam_cell.y + cell_range + 1):
			for z in range(cam_cell.z - cell_range, cam_cell.z + cell_range + 1):
				var cell := Vector3i(x, y, z)
				if grid.has(cell):
					result.append_array(grid[cell])
	return result

func _find_camera() -> void:
	# Search for Camera3D in parent or siblings
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is Camera3D:
				_lod_camera = child
				return
	# Fallback: search in self
	for child in get_children():
		if child is Camera3D:
			_lod_camera = child
			return

func get_active_fog_count() -> int:
	return _active_fog_volumes.size()

func enable_lod_logging(enabled: bool) -> void:
	_lod_log_enabled = enabled
	if enabled:
		_lod_log.clear()
		_lod_start_time = Time.get_ticks_msec() / 1000.0
		print("[LOD_LOG] Logging enabled at t=0.0")

func get_lod_log() -> Array[Dictionary]:
	return _lod_log

func _log_lod_event(event: String, key: String, obj_type: String, pos: Vector3, dist: float, radius: float) -> void:
	if not _lod_log_enabled:
		return
	var t: float = Time.get_ticks_msec() / 1000.0 - _lod_start_time
	_lod_log.append({
		"time": t,
		"event": event,
		"key": key,
		"type": obj_type,
		"pos": pos,
		"dist": dist,
		"radius": radius
	})

func _exit_tree() -> void:
	# Clean up all FogVolumes to prevent leaks
	for key in _active_fog_volumes.keys():
		var entry: Dictionary = _active_fog_volumes[key]
		var fog: FogVolume = entry["fog"]
		if fog.get_parent():
			remove_child(fog)
		fog.queue_free()
	_active_fog_volumes.clear()
	for fog in _fog_pool:
		fog.queue_free()
	_fog_pool.clear()

func _process(delta: float) -> void:
	# LOD culling
	if _lod_camera == null:
		_find_camera()
	if _lod_camera:
		_update_lod_culling(delta)

	# Route tracer animation
	if current_path.size() >= 2:
		tracer_progress += delta * 5.0
		var max_dist := current_path.size() - 1
		if tracer_progress >= max_dist:
			tracer_progress = 0.0

		var idx := int(tracer_progress)
		var next_idx = mini(idx + 1, current_path.size() - 1)
		var t := tracer_progress - idx

		var pos1 := current_path[idx] * MAP_SCALE
		var pos2 := current_path[next_idx] * MAP_SCALE
		route_tracer_instance.position = pos1.lerp(pos2, t)

func _update_lod_culling(delta: float) -> void:
	var cam_pos: Vector3 = _lod_camera.global_position
	var visible_keys: Dictionary = {}

	# Use spatial grid — only check objects in cells near the camera
	var check_dist: float = FOG_LOD_DESTROY_DISTANCE

	# Collect all nearby candidates with their distances
	# Format: Array of [distance, type, index] — we sort by distance to prioritize closest
	var candidates: Array = []

	# --- HII Regions (grid-accelerated) ---
	var hii_nearby: Array[int] = _get_nearby_indices(_hii_grid, cam_pos, check_dist)
	for idx in hii_nearby:
		var d: Dictionary = _hii_data[idx]
		var pos: Vector3 = d["world_pos"]
		var radius: float = d["vis_radius"]
		var dist: float = cam_pos.distance_to(pos)

		var max_dist: float = radius * _pixel_tan
		if dist > max_dist:
			continue

		var key := "hii_%d" % idx
		visible_keys[key] = true

		if _active_fog_volumes.has(key):
			var entry: Dictionary = _active_fog_volumes[key]
			if entry["state"] != "fading_out" and dist > FOG_LOD_DESTROY_DISTANCE:
				entry["state"] = "fading_out"
				_log_lod_event("fade_out_hysteresis", key, "hii", pos, dist, radius)
		elif dist < FOG_LOD_DISTANCE:
			candidates.append([dist, "hii", idx])

	# --- SNRs (grid-accelerated) ---
	var snr_nearby: Array[int] = _get_nearby_indices(_snr_grid, cam_pos, check_dist)
	for idx in snr_nearby:
		var d: Dictionary = _snr_data[idx]
		var pos: Vector3 = d["world_pos"]
		var radius: float = d["vis_radius"]
		var dist: float = cam_pos.distance_to(pos)

		var max_dist: float = radius * _pixel_tan
		if dist > max_dist:
			continue

		var key := "snr_%d" % idx
		visible_keys[key] = true

		if _active_fog_volumes.has(key):
			var entry: Dictionary = _active_fog_volumes[key]
			if entry["state"] != "fading_out" and dist > FOG_LOD_DESTROY_DISTANCE:
				entry["state"] = "fading_out"
				_log_lod_event("fade_out_hysteresis", key, "snr", pos, dist, radius)
		elif dist < FOG_LOD_DISTANCE:
			candidates.append([dist, "snr", idx])

	# --- Molecular Clouds (grid-accelerated) ---
	var mc_nearby: Array[int] = _get_nearby_indices(_mc_grid, cam_pos, check_dist)
	for idx in mc_nearby:
		var d: Dictionary = _mc_data[idx]
		var pos: Vector3 = d["world_pos"]
		var radius: float = d["vis_radius"]
		var dist: float = cam_pos.distance_to(pos)

		var max_dist: float = radius * _pixel_tan
		if dist > max_dist:
			continue

		var key := "mc_%d" % idx
		visible_keys[key] = true

		if _active_fog_volumes.has(key):
			var entry: Dictionary = _active_fog_volumes[key]
			if entry["state"] != "fading_out" and dist > FOG_LOD_DESTROY_DISTANCE:
				entry["state"] = "fading_out"
				_log_lod_event("fade_out_hysteresis", key, "mc", pos, dist, radius)
		elif dist < FOG_LOD_DISTANCE:
			candidates.append([dist, "mc", idx])

	# Sort candidates by distance (closest first) and create FogVolumes
	# up to the maximum cap — prevents GPU overload at dense galactic center
	if not candidates.is_empty():
		candidates.sort_custom(func(a, b): return a[0] < b[0])
		var current_fog_count: int = _active_fog_volumes.size()
		for c in candidates:
			if current_fog_count >= MAX_ACTIVE_FOG_VOLUMES:
				break
			var c_type: String = c[1]
			var c_idx: int = c[2]
			match c_type:
				"hii": _create_hii_fog(c_idx, _hii_data[c_idx])
				"snr": _create_snr_fog(c_idx, _snr_data[c_idx])
				"mc": _create_mc_fog(c_idx, _mc_data[c_idx])
			current_fog_count += 1

	# Start fading out any active fog that's no longer visible
	# Also fade out the farthest ones if we're over capacity
	for key in _active_fog_volumes.keys():
		if not visible_keys.has(key):
			var entry: Dictionary = _active_fog_volumes[key]
			if entry["state"] != "fading_out":
				entry["state"] = "fading_out"
				var fog_node: FogVolume = entry["fog"]
				var cam_pos3 := _lod_camera.global_position if _lod_camera else Vector3.ZERO
				var parts: PackedStringArray = key.split("_")
				var obj_type: String = parts[0]
				var obj_idx: int = int(parts[1])
				var data_d: Dictionary
				match obj_type:
					"hii": data_d = _hii_data[obj_idx]
					"snr": data_d = _snr_data[obj_idx]
					"mc":  data_d = _mc_data[obj_idx]
					_:    continue
				_log_lod_event("fade_out_start", key, obj_type, fog_node.position, cam_pos3.distance_to(fog_node.position), data_d["vis_radius"])

	# Update fade animations for all active fog volumes
	_update_fog_fades(delta)

func _update_fog_fades(delta: float) -> void:
	var fade_step: float = delta / FOG_FADE_DURATION
	var completed_keys: Array[String] = []

	for key in _active_fog_volumes.keys():
		var entry: Dictionary = _active_fog_volumes[key]
		var mat: FogMaterial = entry["mat"]
		var target_density: float = entry["target_density"]
		var fade: float = entry["fade"]
		var state: String = entry["state"]

		if state == "fading_in":
			fade = minf(fade + fade_step, 1.0)
			if fade >= 1.0:
				entry["state"] = "visible"
		elif state == "fading_out":
			fade = maxf(fade - fade_step, 0.0)
			if fade <= 0.0:
				completed_keys.append(key)

		entry["fade"] = fade
		# Apply fade to density — smoothstep for nicer transition
		var smooth: float = fade * fade * (3.0 - 2.0 * fade)
		mat.density = target_density * smooth

	for key in completed_keys:
		_recycle_fog(key)

func _create_hii_fog(idx: int, d: Dictionary) -> void:
	# Lazily create noise texture only when FogVolume is needed
	if d["noise_tex"] == null:
		var noise := FastNoiseLite.new()
		noise.seed = int(d["seed"])
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		noise.fractal_lacunarity = 2.0
		noise.fractal_gain = 0.5
		var noise_tex := NoiseTexture3D.new()
		noise_tex.noise = noise
		d["noise_tex"] = noise_tex

	var fog := _get_fog_from_pool()
	var mat := FogMaterial.new()
	mat.density_texture = d["noise_tex"]
	mat.density = 0.0  # Start at 0 — fade in
	mat.edge_fade = 0.4
	mat.albedo = d["color"]
	mat.emission = d["color"] * 1.5
	fog.material = mat
	fog.size = Vector3(d["vis_radius"] * 2.0, d["vis_radius"] * 0.6, d["vis_radius"] * 2.0)
	fog.position = d["world_pos"]
	add_child(fog)
	_active_fog_volumes["hii_%d" % idx] = {
		"fog": fog,
		"mat": mat,
		"fade": 0.0,
		"state": "fading_in",
		"target_density": 0.08
	}
	var cam_pos := _lod_camera.global_position if _lod_camera else Vector3.ZERO
	_log_lod_event("create", "hii_%d" % idx, "hii", d["world_pos"], cam_pos.distance_to(d["world_pos"]), d["vis_radius"])

func _create_snr_fog(idx: int, d: Dictionary) -> void:
	# Lazily create noise texture
	if d["noise_tex"] == null:
		var noise := FastNoiseLite.new()
		noise.seed = int(d["seed"])
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		noise.fractal_octaves = 3
		noise.fractal_lacunarity = 2.5
		noise.fractal_gain = 0.6
		var noise_tex := NoiseTexture3D.new()
		noise_tex.noise = noise
		d["noise_tex"] = noise_tex

	var fog := _get_fog_from_pool()
	var mat := FogMaterial.new()
	mat.density_texture = d["noise_tex"]
	mat.density = 0.0  # Start at 0 — fade in
	mat.edge_fade = 0.2
	mat.albedo = d["color"]
	mat.emission = d["color"] * 2.0
	fog.material = mat
	var age_factor: float = d["age_factor"]
	fog.size = Vector3(d["vis_radius"] * 2.0 * (1.0 + age_factor * 0.3),
		d["vis_radius"] * 2.0 * (1.0 - age_factor * 0.2),
		d["vis_radius"] * 2.0)
	fog.position = d["world_pos"]
	add_child(fog)
	_active_fog_volumes["snr_%d" % idx] = {
		"fog": fog,
		"mat": mat,
		"fade": 0.0,
		"state": "fading_in",
		"target_density": 0.06
	}
	var cam_pos2 := _lod_camera.global_position if _lod_camera else Vector3.ZERO
	_log_lod_event("create", "snr_%d" % idx, "snr", d["world_pos"], cam_pos2.distance_to(d["world_pos"]), d["vis_radius"])

func _create_mc_fog(idx: int, d: Dictionary) -> void:
	# Lazily create noise texture
	if d["noise_tex"] == null:
		var noise := FastNoiseLite.new()
		noise.seed = int(d["seed"])
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		noise.fractal_lacunarity = 2.0
		noise.fractal_gain = 0.5
		var noise_tex := NoiseTexture3D.new()
		noise_tex.noise = noise
		d["noise_tex"] = noise_tex

	var fog := _get_fog_from_pool()
	var mat := FogMaterial.new()
	mat.density_texture = d["noise_tex"]
	mat.density = 0.0  # Start at 0 — fade in
	mat.edge_fade = 0.3
	mat.albedo = d["color"]
	mat.emission = d["emission"]
	fog.material = mat
	fog.size = Vector3(d["vis_radius"] * 2.0, d["vis_radius"] * 0.5, d["vis_radius"] * 2.0)
	fog.position = d["world_pos"]
	add_child(fog)
	_active_fog_volumes["mc_%d" % idx] = {
		"fog": fog,
		"mat": mat,
		"fade": 0.0,
		"state": "fading_in",
		"target_density": 0.05
	}
	var cam_pos3 := _lod_camera.global_position if _lod_camera else Vector3.ZERO
	_log_lod_event("create", "mc_%d" % idx, "mc", d["world_pos"], cam_pos3.distance_to(d["world_pos"]), d["vis_radius"])

func _get_fog_from_pool() -> FogVolume:
	if not _fog_pool.is_empty():
		return _fog_pool.pop_back()
	return FogVolume.new()

func _recycle_fog(key: String) -> void:
	var entry: Dictionary = _active_fog_volumes[key]
	var fog: FogVolume = entry["fog"]
	if _lod_log_enabled:
		var cam_pos := _lod_camera.global_position if _lod_camera else Vector3.ZERO
		_log_lod_event("recycled", key, key.split("_")[0], fog.position, cam_pos.distance_to(fog.position), 0.0)
	if fog.get_parent():
		remove_child(fog)
	_fog_pool.append(fog)
	_active_fog_volumes.erase(key)

# ==========================================================================
# SHARED MESH & MATERIAL (one quad, one shader, reused by all MultiMeshes)
# ==========================================================================
func _setup_shared_mesh():
	star_quad_mesh = QuadMesh.new()
	star_quad_mesh.size = Vector2(0.5, 0.5)
	
	star_material = ShaderMaterial.new()
	if star_shader:
		star_material.shader = star_shader
		var noise := FastNoiseLite.new()
		var noise_tex := NoiseTexture2D.new()
		noise_tex.noise = noise
		star_material.set_shader_parameter("noise_texture", noise_tex)
	
	star_quad_mesh.material = star_material

# ==========================================================================
# OVERVIEW MULTIMESH: Persistent far-distance galaxy shape
# ==========================================================================
func _setup_overview_multimesh():
	overview_mm = MultiMesh.new()
	overview_mm.transform_format = MultiMesh.TRANSFORM_3D
	overview_mm.use_custom_data = true
	overview_mm.mesh = star_quad_mesh
	# instance_count set later when generate_stars() is called
	overview_mm.instance_count = 0
	
	overview_mmi = MultiMeshInstance3D.new()
	overview_mmi.multimesh = overview_mm
	# Overview is always visible — it's the far-distance galaxy shape
	add_child(overview_mmi)

## Called by GalaxyMapManager via stars_updated signal (overview cloud)
func generate_stars(star_data: Array) -> void:
	var count := star_data.size()
	if count == 0:
		return
	
	# Build PackedFloat32Array buffer directly
	# Layout: TRANSFORM_3D (12 floats) + custom_data (4 floats) = 16 floats per instance
	# Note: use_colors is false, use_custom_data is true
	overview_mm.instance_count = 0 # Reset
	overview_mm.instance_count = count
	
	for i in range(count):
		var data = star_data[i]
		var pos: Vector3 = data.get("position", Vector3.ZERO) * MAP_SCALE
		var xform := Transform3D(Basis(), pos)
		overview_mm.set_instance_transform(i, xform)
		var spec_idx = data.get("spectral_idx", 0.5)
		var lum = data.get("luminosity", 1.0)
		overview_mm.set_instance_custom_data(i, Color(spec_idx, lum, 0.0, 0.0))

# ==========================================================================
# SECTOR CHUNK MOUNTING (streamed MultiMesh per sector)
# ==========================================================================
func mount_sector_chunk(sec_key: Vector3i, stars: Array[Dictionary]) -> void:
	if sector_chunks.has(sec_key):
		return # Already mounted
	if stars.is_empty():
		return

	var count := stars.size()

	# Create a new MultiMesh for this sector
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = star_quad_mesh
	mm.instance_count = count

	# Populate using fast per-instance calls
	for i in range(count):
		var star = stars[i]
		var pos: Vector3 = star.get("position", Vector3.ZERO) * MAP_SCALE
		mm.set_instance_transform(i, Transform3D(Basis(), pos))
		var spec_idx = star.get("spectral_idx", 0.5)
		var lum = star.get("luminosity", 1.0)
		mm.set_instance_custom_data(i, Color(spec_idx, lum, 0.0, 0.0))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm

	# Automatic distance-based LOD: visible between 0 and 300 Godot units
	# (300 units = 30,000 LY at MAP_SCALE 0.01)
	mmi.visibility_range_begin = 0.0
	mmi.visibility_range_end = 300.0
	mmi.visibility_range_end_margin = 50.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	# Fade-in animation: start invisible, tween to visible over 0.5s
	# This prevents the "pop" when a sector chunk is mounted after the
	# camera has already stopped moving
	mmi.transparency = 1.0  # Fully transparent (GeometryInstance3D property)
	add_child(mmi)
	sector_chunks[sec_key] = mmi

	var tween := create_tween()
	tween.tween_property(mmi, "transparency", 0.0, 0.5)

func unmount_sector_chunk(sec_key: Vector3i) -> void:
	if sector_chunks.has(sec_key):
		var mmi: MultiMeshInstance3D = sector_chunks[sec_key]
		mmi.queue_free()
		sector_chunks.erase(sec_key)

# ==========================================================================
# GLOBULAR CLUSTERS — dense star clusters in the halo
# ==========================================================================
func _setup_globular_clusters():
	var clusters := ProceduralGalaxy.generate_globular_clusters()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_quad_mesh
	mm.use_custom_data = true
	mm.instance_count = clusters.size()

	for i in range(clusters.size()):
		var c = clusters[i]
		var pos := Vector3(c["position"]) * MAP_SCALE
		# Cluster visual size: half-light radius scaled, min 2 units for visibility
		var vis_radius: float = maxf(float(c["half_light_radius_ly"]) * MAP_SCALE, 2.0)
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(vis_radius, vis_radius, 1.0)), pos)
		mm.set_instance_transform(i, t)
		# Custom: warm yellow-orange (old Population II stars)
		mm.set_instance_custom_data(i, Color(0.8, 0.6, 0.3, 1.0))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = star_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 800.0  # Visible from far away (halo objects)
	mmi.visibility_range_end_margin = 100.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)

# ==========================================================================
# HII REGIONS — pink/red glowing nebulae in spiral arms
# LOD: billboard MultiMesh for all + dynamic FogVolumes for nearby
# ==========================================================================
func _setup_hii_regions():
	var regions := ProceduralGalaxy.generate_hii_regions()
	_hii_data.clear()

	# Pre-compute noise textures for all HII regions (done once at load)
	# Store data for per-frame LOD culling
	for i in range(regions.size()):
		var r = regions[i]
		var pos := Vector3(r["position"]) * MAP_SCALE
		var radius: float = maxf(float(r["radius_ly"]) * MAP_SCALE, 0.5)
		var color: Color = r["color"]

		# Store noise seed only — NoiseTexture3D is created lazily when
		# a FogVolume is actually needed (only for nearby objects)
		_hii_data.append({
			"world_pos": pos,
			"vis_radius": radius,
			"color": color,
			"seed": r["seed"],
			"noise_tex": null  # Lazy — created on first FogVolume creation
		})

	# Create billboard MultiMesh for ALL HII regions (cheap — one draw call)
	# These are always rendered; FogVolumes are added on top when close
	_hii_billboard_mm = MultiMesh.new()
	_hii_billboard_mm.transform_format = MultiMesh.TRANSFORM_3D
	_hii_billboard_mm.mesh = star_quad_mesh
	_hii_billboard_mm.use_custom_data = true
	_hii_billboard_mm.instance_count = regions.size()

	for i in range(regions.size()):
		var d: Dictionary = _hii_data[i]
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(d["vis_radius"], d["vis_radius"], 1.0)), d["world_pos"])
		_hii_billboard_mm.set_instance_transform(i, t)
		# Pink/red Hα color
		_hii_billboard_mm.set_instance_custom_data(i, Color(d["color"].r, d["color"].g, d["color"].b, 0.6))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _hii_billboard_mm
	mmi.material_override = star_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ==========================================================================
# MOLECULAR CLOUDS — dark absorption patches in spiral arms
# ==========================================================================
func _setup_molecular_clouds():
	var clouds := ProceduralGalaxy.generate_molecular_clouds()
	_mc_data.clear()

	# Store data for dynamic LOD — no FogVolumes created at load time
	for i in range(clouds.size()):
		var c = clouds[i]
		var pos := Vector3(c["position"]) * MAP_SCALE
		var radius: float = maxf(float(c["radius_ly"]) * MAP_SCALE, 0.5)

		_mc_data.append({
			"world_pos": pos,
			"vis_radius": radius,
			"color": Color(0.15, 0.1, 0.08),  # Dark brownish
			"emission": Color(0.01, 0.005, 0.0),  # Nearly black
			"seed": c.get("seed", i),
			"noise_tex": null  # Lazy
		})

	# Billboard MultiMesh for ALL molecular clouds (cheap — one draw call)
	# Use very dark custom data so they're subtle dark patches
	_mc_billboard_mm = MultiMesh.new()
	_mc_billboard_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mc_billboard_mm.mesh = star_quad_mesh
	_mc_billboard_mm.use_custom_data = true
	_mc_billboard_mm.instance_count = clouds.size()

	for i in range(clouds.size()):
		var d: Dictionary = _mc_data[i]
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(d["vis_radius"], d["vis_radius"], 1.0)), d["world_pos"])
		_mc_billboard_mm.set_instance_transform(i, t)
		# Dark brownish, low alpha — subtle dark patches
		_mc_billboard_mm.set_instance_custom_data(i, Color(0.15, 0.1, 0.08, 0.3))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mc_billboard_mm
	mmi.material_override = star_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 400.0
	mmi.visibility_range_end_margin = 60.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)

# ==========================================================================
# SATELLITE GALAXIES — LMC, SMC, and dwarf galaxies
# Rendered as MultiMesh star clusters (not single blobs) so they look
# like actual resolved galaxies rather than glowing balls.
# ==========================================================================
func _setup_satellite_galaxies():
	var galaxies := ProceduralGalaxy.generate_satellite_galaxies()

	# Group by type: irregular (blue) vs elliptical (yellow)
	# Use separate MultiMeshes so each type gets its own color
	var irregular_indices: Array[int] = []
	var elliptical_indices: Array[int] = []
	for i in range(galaxies.size()):
		var g = galaxies[i]
		if String(g["type"]).find("Irregular") >= 0:
			irregular_indices.append(i)
		else:
			elliptical_indices.append(i)

	# Stars per satellite: scale with diameter (bigger galaxy = more stars)
	# LMC (14k LY) → ~500 stars, small dwarf (500 LY) → ~20 stars
	var stars_per_galaxy := func(diameter_ly: float) -> int:
		return clampi(int(diameter_ly / 30.0), 15, 500)

	# Build a MultiMesh for each type
	for group_data in [
		{"indices": irregular_indices, "color": Color(0.5, 0.6, 0.9, 0.8)},  # Blue (young, irregular)
		{"indices": elliptical_indices, "color": Color(0.8, 0.7, 0.5, 0.7)},  # Yellow (old, elliptical)
	]:
		var indices: Array[int] = group_data["indices"]
		if indices.is_empty():
			continue
		var base_color: Color = group_data["color"]

		# Count total stars across all satellites in this group
		var total_stars: int = 0
		for idx in indices:
			total_stars += stars_per_galaxy.call(float(galaxies[idx]["diameter_ly"]))

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = star_quad_mesh
		mm.use_custom_data = true
		mm.instance_count = total_stars

		var instance_idx: int = 0
		for idx in indices:
			var g = galaxies[idx]
			var center := Vector3(g["position"]) * MAP_SCALE
			var diameter: float = maxf(float(g["diameter_ly"]) * MAP_SCALE, 0.5)
			var radius: float = diameter * 0.5
			var n_stars: int = stars_per_galaxy.call(float(g["diameter_ly"]))

			# Deterministic seed for this galaxy's star distribution
			var gal_seed: int = int(g["seed"])

			for j in range(n_stars):
				# Random position within the galaxy's sphere
				var s1 := hash_to_float01(gal_seed * 1000 + j * 7 + 1)
				var s2 := hash_to_float01(gal_seed * 1000 + j * 7 + 3)
				var s3 := hash_to_float01(gal_seed * 1000 + j * 7 + 5)
				# Uniform distribution in sphere
				var r: float = radius * pow(s1, 1.0 / 3.0)
				var phi: float = s2 * TAU
				var cos_th: float = 1.0 - 2.0 * s3
				var sin_th: float = sqrt(maxf(1.0 - cos_th * cos_th, 0.0))
				var offset := Vector3(r * sin_th * cos(phi), r * cos_th, r * sin_th * sin(phi))

				# Star size: small individual points
				var star_size: float = 0.3
				var t := Transform3D(Basis.IDENTITY.scaled(Vector3(star_size, star_size, 1.0)), center + offset)
				mm.set_instance_transform(instance_idx, t)
				# Slight color variation per star
				var variation: float = hash_to_float01(gal_seed * 1000 + j * 13) * 0.2 - 0.1
				mm.set_instance_custom_data(instance_idx, Color(
					clampf(base_color.r + variation, 0.0, 1.0),
					clampf(base_color.g + variation, 0.0, 1.0),
					clampf(base_color.b + variation, 0.0, 1.0),
					base_color.a
				))
				instance_idx += 1

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = star_material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 2000.0  # Visible from very far (satellites are distant)
		mmi.visibility_range_end_margin = 200.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)

# Simple deterministic hash to [0,1)
static func hash_to_float01(hash_seed: int) -> float:
	var s: int = hash_seed
	s = (s ^ 61) ^ (s >> 16)
	s = s + (s << 3)
	s = s ^ (s >> 4)
	s = s * 0x27d4eb2d
	s = s ^ (s >> 15)
	return (float(s & 0x00FFFFFF) / float(0x01000000))

# ==========================================================================
# STELLAR STREAMS — tidal debris from disrupted dwarf galaxies
# ==========================================================================
func _setup_stellar_streams():
	var streams := ProceduralGalaxy.generate_stellar_streams()
	for s in streams:
		var points: Array = s["points"]
		if points.size() < 2:
			continue

		# Render as a line of small star billboards
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = star_quad_mesh
		mm.use_custom_data = true
		mm.instance_count = points.size()

		for i in range(points.size()):
			var p: Vector3 = points[i] * MAP_SCALE
			var t := Transform3D(Basis.IDENTITY.scaled(Vector3(0.3, 0.3, 1.0)), p)
			mm.set_instance_transform(i, t)
			# Faint blue-white (old halo stars)
			mm.set_instance_custom_data(i, Color(0.6, 0.7, 0.9, 0.3))

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = star_material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 600.0
		mmi.visibility_range_end_margin = 80.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)

# ==========================================================================
# SUPERNOVA REMNANTS — expanding shells
# LOD: billboard MultiMesh for all + dynamic FogVolumes for nearby
# ==========================================================================
func _setup_supernova_remnants():
	var remnants := ProceduralGalaxy.generate_supernova_remnants()
	_snr_data.clear()

	for i in range(remnants.size()):
		var r = remnants[i]
		var pos := Vector3(r["position"]) * MAP_SCALE
		var radius: float = maxf(float(r["radius_ly"]) * MAP_SCALE, 0.3)
		var color: Color = r["color"]

		# Store seed only — NoiseTexture3D created lazily on FogVolume creation
		_snr_data.append({
			"world_pos": pos,
			"vis_radius": radius,
			"color": color,
			"age_factor": float(r["age_years"]) / 100000.0,
			"seed": r["seed"],
			"noise_tex": null  # Lazy
		})

	# Billboard MultiMesh for ALL SNRs
	_snr_billboard_mm = MultiMesh.new()
	_snr_billboard_mm.transform_format = MultiMesh.TRANSFORM_3D
	_snr_billboard_mm.mesh = star_quad_mesh
	_snr_billboard_mm.use_custom_data = true
	_snr_billboard_mm.instance_count = remnants.size()

	for i in range(remnants.size()):
		var d: Dictionary = _snr_data[i]
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(d["vis_radius"], d["vis_radius"], 1.0)), d["world_pos"])
		_snr_billboard_mm.set_instance_transform(i, t)
		_snr_billboard_mm.set_instance_custom_data(i, Color(d["color"].r, d["color"].g, d["color"].b, 0.5))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _snr_billboard_mm
	mmi.material_override = star_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ==========================================================================
# PLANETARY NEBULAE — shells from dying stars
# ==========================================================================
func _setup_planetary_nebulae():
	var nebulae := ProceduralGalaxy.generate_planetary_nebulae()

	# Only render the nearest/brightest PNe — 3000 individual ring meshes
	# would be far too heavy. Render the 200 largest ones as ring MultiMesh
	# + batch ALL central stars into a separate MultiMesh.
	var max_rings := 200
	# Sort by radius (largest first) — only render big ones as rings
	var sorted_nebulae := nebulae.duplicate()
	sorted_nebulae.sort_custom(func(a, b): return float(a["radius_ly"]) > float(b["radius_ly"]))

	# --- Ring shells (MultiMesh with shared torus) ---
	# Use a unit torus and scale per-instance via transform
	var ring_mm := MultiMesh.new()
	ring_mm.transform_format = MultiMesh.TRANSFORM_3D
	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius = 0.7
	torus_mesh.outer_radius = 1.0
	ring_mm.mesh = torus_mesh
	ring_mm.instance_count = mini(sorted_nebulae.size(), max_rings)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.4, 0.7, 0.5)
	ring_mat.emission = Color(0.3, 0.6, 0.4) * 2.5
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	ring_mat.no_depth_test = true
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for i in range(mini(sorted_nebulae.size(), max_rings)):
		var n = sorted_nebulae[i]
		var pos := Vector3(n["position"]) * MAP_SCALE
		var radius: float = maxf(float(n["radius_ly"]) * MAP_SCALE, 0.2)
		var pn_seed: int = int(n["seed"])

		# Random 3D orientation
		var rot_x: float = hash_to_float01(pn_seed * 7 + 1) * TAU
		var rot_y: float = hash_to_float01(pn_seed * 7 + 3) * TAU
		var rot_z: float = hash_to_float01(pn_seed * 7 + 5) * TAU
		var rot_basis := Basis(Vector3.RIGHT, rot_x) * Basis(Vector3.UP, rot_y) * Basis(Vector3.BACK, rot_z)
		rot_basis = rot_basis.scaled(Vector3(radius, radius, radius))
		ring_mm.set_instance_transform(i, Transform3D(rot_basis, pos))

	var ring_mmi := MultiMeshInstance3D.new()
	ring_mmi.multimesh = ring_mm
	ring_mmi.material_override = ring_mat
	ring_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_mmi.visibility_range_end = 500.0
	ring_mmi.visibility_range_end_margin = 80.0
	ring_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(ring_mmi)

	# --- Central stars (ALL planetary nebulae) ---
	var star_mm := MultiMesh.new()
	star_mm.transform_format = MultiMesh.TRANSFORM_3D
	star_mm.mesh = star_quad_mesh
	star_mm.use_custom_data = true
	star_mm.instance_count = nebulae.size()

	for i in range(nebulae.size()):
		var n = nebulae[i]
		var pos := Vector3(n["position"]) * MAP_SCALE
		var star_t := Transform3D(Basis.IDENTITY.scaled(Vector3(0.15, 0.15, 1.0)), pos)
		star_mm.set_instance_transform(i, star_t)
		# Central star: blue-white (hot white dwarf, T ~ 100,000 K)
		star_mm.set_instance_custom_data(i, Color(0.7, 0.8, 1.0, 1.0))

	var star_mmi := MultiMeshInstance3D.new()
	star_mmi.multimesh = star_mm
	star_mmi.material_override = star_material
	star_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star_mmi.visibility_range_end = 500.0
	star_mmi.visibility_range_end_margin = 80.0
	star_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(star_mmi)

# ==========================================================================
# OPEN CLUSTERS — young stellar associations in spiral arms
# ==========================================================================
func _setup_open_clusters():
	var clusters := ProceduralGalaxy.generate_open_clusters()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_quad_mesh
	mm.use_custom_data = true
	mm.instance_count = clusters.size()

	for i in range(clusters.size()):
		var c = clusters[i]
		var pos := Vector3(c["position"]) * MAP_SCALE
		var vis_radius: float = maxf(float(c["radius_ly"]) * MAP_SCALE, 1.0)
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(vis_radius, vis_radius, 1.0)), pos)
		mm.set_instance_transform(i, t)
		# Young clusters: blue-white (hot stars)
		mm.set_instance_custom_data(i, Color(0.7, 0.8, 1.0, 0.8))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = star_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 400.0
	mmi.visibility_range_end_margin = 60.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)

# ==========================================================================
# INDICATORS (current system, selected system)
# ==========================================================================
func _setup_indicators():
	# Current system indicator (green torus)
	current_indicator = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.6)
	mat.emission_energy_multiplier = 4.0
	torus.material = mat
	current_indicator.mesh = torus
	current_indicator.hide()
	add_child(current_indicator)
	
	# Route lines
	route_lines_instance = MeshInstance3D.new()
	add_child(route_lines_instance)
	
	# Selected system indicator (blue torus)
	selected_indicator = MeshInstance3D.new()
	var selected_mat := mat.duplicate()
	selected_mat.albedo_color = Color(0.2, 0.6, 1.0)
	selected_mat.emission = Color(0.2, 0.6, 1.0)
	var sel_mesh := TorusMesh.new()
	sel_mesh.inner_radius = 0.5
	sel_mesh.outer_radius = 0.6
	sel_mesh.material = selected_mat
	selected_indicator.mesh = sel_mesh
	selected_indicator.hide()
	add_child(selected_indicator)
	
	# Route tracer (animated sphere)
	route_tracer_instance = MeshInstance3D.new()
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.albedo_color = Color(1.0, 1.0, 1.0)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(1.0, 1.0, 1.0)
	tracer_mat.emission_energy_multiplier = 6.0
	var tracer_mesh := SphereMesh.new()
	tracer_mesh.radius = 0.2
	tracer_mesh.height = 0.4
	tracer_mesh.material = tracer_mat
	route_tracer_instance.mesh = tracer_mesh
	# Visited-system markers (small amber rings, MultiMesh for efficiency)
	visited_mm = MultiMesh.new()
	visited_mm.transform_format = MultiMesh.TRANSFORM_3D
	visited_mm.mesh = star_quad_mesh
	visited_mm.instance_count = 0
	visited_mmi = MultiMeshInstance3D.new()
	visited_mmi.multimesh = visited_mm
	var visited_mat := StandardMaterial3D.new()
	visited_mat.albedo_color = Color(1.0, 0.75, 0.2)
	visited_mat.emission_enabled = true
	visited_mat.emission = Color(1.0, 0.75, 0.2)
	visited_mat.emission_energy_multiplier = 3.0
	visited_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visited_mmi.material_override = visited_mat
	visited_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visited_mmi)
	route_tracer_instance.hide()
	add_child(route_tracer_instance)

# ==========================================================================
# ROUTE DRAWING & ANIMATION
# ==========================================================================
func draw_route(path: PackedVector3Array) -> void:
	current_path = path
	tracer_progress = 0.0
	
	if path.size() < 2:
		route_lines_instance.mesh = null
		route_tracer_instance.hide()
		return
		
	route_tracer_instance.show()
	var lines_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices := PackedVector3Array()
	for i in range(path.size() - 1):
		vertices.push_back(path[i] * MAP_SCALE)
		vertices.push_back(path[i+1] * MAP_SCALE)
		
	arrays[Mesh.ARRAY_VERTEX] = vertices
	lines_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.0, 0.8, 1.0)
	line_mat.emission_enabled = true
	line_mat.emission = Color(0.0, 0.8, 1.0)
	line_mat.emission_energy_multiplier = 3.0
	lines_mesh.surface_set_material(0, line_mat)
	
	route_lines_instance.mesh = lines_mesh

func set_selected_system(system_data: Dictionary) -> void:
	if system_data.has("position"):
		selected_indicator.position = system_data["position"] * MAP_SCALE
		selected_indicator.show()
	else:
		selected_indicator.hide()

func set_current_system(system_data: Dictionary) -> void:
	if system_data.has("position"):
		current_indicator.position = system_data["position"] * MAP_SCALE
		current_indicator.show()

## Highlights visited systems on the map. [param positions] is an array of
## Vector3 galactic positions (in light-years) for stars the player has visited.
## Renders them as a MultiMesh of small amber markers.
func highlight_visited_systems(positions: Array) -> void:
	if visited_mm == null:
		return
	var count := positions.size()
	if count == 0:
		visited_mm.instance_count = 0
		return
	visited_mm.instance_count = 0
	visited_mm.instance_count = count
	for i in range(count):
		var pos_ly: Vector3 = positions[i]
		var xform := Transform3D(Basis(), pos_ly * MAP_SCALE)
		visited_mm.set_instance_transform(i, xform)

# ==========================================================================
# HYPERLANE RENDERING (if needed)
# ==========================================================================
func generate_hyperlanes(connections: Array) -> void:
	if connections.is_empty():
		return
	var lines_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	for conn in connections:
		vertices.push_back(conn[0] * MAP_SCALE)
		vertices.push_back(conn[1] * MAP_SCALE)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	lines_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var lines_instance := MeshInstance3D.new()
	lines_instance.mesh = lines_mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.4)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lines_instance.material_override = line_mat
	add_child(lines_instance)

# ==========================================================================
# GALACTIC CORE: Supermassive Black Hole — Raymarched Gravitational Lensing
# ==========================================================================
# Based on the physics of Gargantua from Interstellar (Kip Thorne / DNEG).
# Uses a single raymarched sphere shader that simulates:
#   - Gravitational lensing (Schwarzschild geodesic ray bending)
#   - Accretion disk that wraps OVER and UNDER the black hole (the iconic
#     Gargantua look — only achievable through ray bending, not flat geometry)
#   - Doppler beaming (relativistic intensity boost on approaching side)
#   - Gravitational redshift (inner disk appears redder)
#   - Photon ring (light trapped in circular orbits at 1.5x Rs)
#   - Event horizon shadow (dark central region)
#
# The shader is applied to a large sphere encompassing the entire BH system.
# All physics happens per-pixel in the fragment shader.
#
# References:
#   James, von Tunzelmann, Franklin, Thorne (2015) Class. Quantum Grav. 32 065001
#   Bruneton (2020) "A Real-time High-quality Black Hole Shader"
# ==========================================================================
# Real Sgr A* values from ProceduralGalaxy.gd:
#   Mass: 4.15 × 10⁶ M_sun (Gravity Collaboration 2018)
#   Schwarzschild radius: 1.3e-9 LY (2GM/c²)
#   Sphere of influence: 10 LY (G×M_BH/σ², σ=75 km/s)
#
# At MAP_SCALE 0.01 (1 unit = 100 LY):
#   Sphere of influence: 10 LY = 0.1 units
#   Schwarzschild radius: 1.3e-11 units (physically invisible)
#
# The SMBH itself is physically invisible at galaxy map scale. We use a
# VISUAL_EXAGGERATION factor to make the lensing/disk effects visible.
# This is a rendering choice — all physics in the generator uses real values.
const SMBH_VISUAL_EXAGGERATION = 5000.0  # Visual scale-up factor for visibility
const SMBH_RS_LY = 1.3e-9               # Real Schwarzschild radius in LY
const SMBH_SPHERE_OF_INFLUENCE_LY = 10.0  # Real sphere of influence in LY
# Visual sphere radius in world units:
const SMBH_SPHERE_RADIUS = (SMBH_SPHERE_OF_INFLUENCE_LY * SMBH_VISUAL_EXAGGERATION) * MAP_SCALE  # 500.0 units
# Visual Schwarzschild radius in world units (scaled for shader):
const SMBH_RS = (SMBH_RS_LY * SMBH_VISUAL_EXAGGERATION) * MAP_SCALE  # ~6.5 units

func _setup_galactic_core() -> void:
	var core := Node3D.new()

	# 1. Opaque Event Horizon Shadow — a black sphere at the photon capture
	# radius (~2.6x Rs) that WRITES DEPTH, blocking stars behind the black hole.
	var SMBH_SHADOW_RADIUS = SMBH_RS * 2.6  # Photon capture radius
	var shadow := MeshInstance3D.new()
	var shadow_sphere := SphereMesh.new()
	shadow_sphere.radius = SMBH_SHADOW_RADIUS
	shadow_sphere.height = SMBH_SHADOW_RADIUS * 2.0
	shadow.mesh = shadow_sphere
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0)
	shadow_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.no_depth_test = false  # Write depth — block stars behind
	shadow.material_override = shadow_mat
	core.add_child(shadow)

	# 2. Raymarched Black Hole — sphere with gravitational lensing shader.
	# Renders accretion disk, photon ring, and lensing effects additively.
	# Uses depth_test (not disabled) so stars in front of the SMBH occlude
	# the effect properly. With cull_disabled + FRONT_FACING guard in the
	# shader, only back faces render, preventing doubled additive output.
	var bh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SMBH_SPHERE_RADIUS
	sphere.height = SMBH_SPHERE_RADIUS * 2.0
	bh.mesh = sphere

	var bh_mat := ShaderMaterial.new()
	bh_mat.shader = preload("res://shaders/smbh_raymarch.gdshader")

	# Black hole parameters — all derived from real Sgr A* values, scaled
	# by VISUAL_EXAGGERATION for visibility at galaxy map scale.
	bh_mat.set_shader_parameter("schwarzschild_radius", SMBH_RS)
	bh_mat.set_shader_parameter("photon_sphere_radius", SMBH_RS * 1.5)    # 1.5 Rs (GR)
	bh_mat.set_shader_parameter("disk_inner_radius", SMBH_RS * 1.27)      # ISCO = 3 Rs = 1.27 shadow
	bh_mat.set_shader_parameter("disk_outer_radius", SMBH_RS * 5.3)       # ~5.3 Rs outer disk
	bh_mat.set_shader_parameter("disk_thickness", SMBH_RS * 0.27)         # Disk thickness

	# Bounding sphere radius — MUST match the mesh radius
	bh_mat.set_shader_parameter("bounding_radius", SMBH_SPHERE_RADIUS)

	# Physics
	bh_mat.set_shader_parameter("ray_bend_strength", 1.0)       # Full lensing
	bh_mat.set_shader_parameter("doppler_boost", 1.5)           # Relativistic beaming
	bh_mat.set_shader_parameter("doppler_angle", 0.0)
	bh_mat.set_shader_parameter("gravitational_redshift", 0.8)
	bh_mat.set_shader_parameter("disk_rotation_speed", 2.0)

	# Visual quality
	bh_mat.set_shader_parameter("ray_steps", 160)
	bh_mat.set_shader_parameter("step_size", 5.0)
	bh_mat.set_shader_parameter("brightness", 1.0)
	bh_mat.set_shader_parameter("temperature_inner", 8000.0)    # Warm-white inner disk
	bh_mat.set_shader_parameter("temperature_outer", 2500.0)    # Deep orange outer disk
	bh_mat.set_shader_parameter("noise_scale", 6.0)
	bh_mat.set_shader_parameter("noise_speed", 0.5)
	bh_mat.set_shader_parameter("bloom_threshold", 2.0)

	# Disk tilt (Gargantua-style ~28° viewing angle)
	bh_mat.set_shader_parameter("disk_tilt_x", 0.5)
	bh_mat.set_shader_parameter("disk_tilt_z", -0.13)

	# Debug mode (0 = normal rendering)
	bh_mat.set_shader_parameter("debug_mode", 0)

	# Background star lensing (disabled by default)
	bh_mat.set_shader_parameter("background_enabled", 0.0)

	bh.material_override = bh_mat
	core.add_child(bh)

	# Note: Sgr A* has NO relativistic jets. It is in a quiescent state with
	# very low accretion rate. The EHT observations confirmed no jets.
	# Some AGN have jets (M87 famously), but not our galaxy's SMBH.
	# The Fermi bubbles (~25 kLY above/below the plane) are likely remnants
	# of past activity or supernova-driven outflows, not collimated jets.

	# Ambient point light to illuminate nearby dust
	var core_light := OmniLight3D.new()
	core_light.light_color = Color(1.0, 0.6, 0.3)
	core_light.light_energy = 8.0
	core_light.omni_range = 400.0
	core_light.omni_attenuation = 1.5
	core.add_child(core_light)

	add_child(core)

# ==========================================================================
# DUST CLOUDS: Volumetric Fog
# ==========================================================================
func _setup_dust_clouds() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var noise_tex := NoiseTexture3D.new()
	noise_tex.noise = noise
	
	# Dust cloud 1: Blue reflection nebula (scattered light from hot O/B stars)
	var mat1 := FogMaterial.new()
	mat1.density_texture = noise_tex
	mat1.density = 0.003
	mat1.edge_fade = 0.1
	mat1.albedo = Color(0.4, 0.5, 0.7)   # Blue-gray (Rayleigh scattering)
	mat1.emission = Color(0.05, 0.08, 0.15)
	var fog1 := FogVolume.new()
	fog1.material = mat1
	fog1.size = Vector3(1000.0, 40.0, 1000.0)
	add_child(fog1)

	# Dust cloud 2: Reddish-brown extinction dust (interstellar reddening)
	var noise2 := FastNoiseLite.new()
	noise2.seed = 84
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise2.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var noise_tex2 := NoiseTexture3D.new()
	noise_tex2.noise = noise2
	var mat2 := FogMaterial.new()
	mat2.density_texture = noise_tex2
	mat2.density = 0.002
	mat2.edge_fade = 0.1
	mat2.albedo = Color(0.6, 0.4, 0.25)  # Brownish-red (dust extinction)
	mat2.emission = Color(0.08, 0.04, 0.02)
	var fog2 := FogVolume.new()
	fog2.material = mat2
	fog2.size = Vector3(1000.0, 50.0, 1000.0)
	add_child(fog2)
