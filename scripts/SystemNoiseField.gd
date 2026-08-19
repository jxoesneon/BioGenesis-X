# res://scripts/SystemNoiseField.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# SystemNoiseField.gd — Gameplay Distribution Noise Maps (System Scale)
# ==============================================================================
# Generates 4 deterministic noise channels for GAMEPLAY element distribution
# within a star system. These noise maps are PURELY for sci-fi gameplay
# (resources, enemies, anomalies, hazards) and do NOT affect or replace
# any real astrophysical formulas in ProceduralGalaxy.gd or UniverseManager.gd.
#
# Channels:
#   - RESOURCES: Mineral/bio-matter density (where harvestable asteroids spawn)
#   - ENEMIES:   Hostile Void-Fauna density (combat encounter probability)
#   - ANOMALIES: Special event density (derelicts, ruins, distress signals)
#   - HAZARDS:   Environmental danger density (radiation, gravity wells)
#
# The noise is sampled on a 2D grid covering the system's orbital plane
# (ecliptic, XZ plane in world space). Values are in [0, 1].
#
# Visualization: NoiseMapDebugOverlay renders these as colored planes (F4).
# Gameplay: Systems query sample_channel() at world positions to determine
#           spawn probability, resource richness, hazard intensity, etc.
# ==============================================================================

class_name SystemNoiseField
extends Node

# --- Channel IDs ---
enum Channel {
	RESOURCES,
	ENEMIES,
	ANOMALIES,
	HAZARDS,
}

const CHANNEL_COUNT: int = 4

# --- Channel colors (for debug visualization) ---
const CHANNEL_COLORS: Dictionary = {
	Channel.RESOURCES: Color(0.0, 1.0, 0.4),    # Green — resources
	Channel.ENEMIES: Color(1.0, 0.3, 0.1),       # Red — enemies
	Channel.ANOMALIES: Color(0.7, 0.3, 1.0),     # Purple — anomalies
	Channel.HAZARDS: Color(1.0, 0.8, 0.0),       # Yellow — hazards
}

const CHANNEL_NAMES: Dictionary = {
	Channel.RESOURCES: "resources",
	Channel.ENEMIES: "enemies",
	Channel.ANOMALIES: "anomalies",
	Channel.HAZARDS: "hazards",
}

# --- Grid configuration ---
const GRID_RESOLUTION: int = 256          # 256x256 noise grid
const SYSTEM_EXTENT_AU: float = 60.0      # Covers out to ~Neptune+ orbit
const AU_TO_METERS: float = 149597870700.0

# --- Noise parameters per channel (tuned for gameplay, not realism) ---
const NOISE_PARAMS: Dictionary = {
	Channel.RESOURCES: {
		"type": FastNoiseLite.TYPE_SIMPLEX,
		"fractal": FastNoiseLite.FRACTAL_FBM,
		"octaves": 4,
		"lacunarity": 2.0,
		"gain": 0.5,
		"frequency": 0.015,   # Moderate patches of mineral-rich space
	},
	Channel.ENEMIES: {
		"type": FastNoiseLite.TYPE_CELLULAR,
		"fractal": FastNoiseLite.FRACTAL_NONE,
		"octaves": 1,
		"lacunarity": 2.0,
		"gain": 0.5,
		"frequency": 0.008,   # Large territories for hostile fauna
	},
	Channel.ANOMALIES: {
		"type": FastNoiseLite.TYPE_SIMPLEX,
		"fractal": FastNoiseLite.FRACTAL_RIDGED,
		"octaves": 3,
		"lacunarity": 2.5,
		"gain": 0.6,
		"frequency": 0.012,   # Rare ridge features for special events
	},
	Channel.HAZARDS: {
		"type": FastNoiseLite.TYPE_PERLIN,
		"fractal": FastNoiseLite.FRACTAL_FBM,
		"octaves": 3,
		"lacunarity": 2.0,
		"gain": 0.45,
		"frequency": 0.010,   # Smooth danger zones
	},
}

# --- State ---
var _system_seed: int = 0
var _noise_generators: Dictionary = {}  # Channel -> FastNoiseLite
var _grids: Dictionary = {}             # Channel -> PackedByteArray (GRID_RESOLUTION^2)
var _is_generated: bool = false
var _system_extent_m: float = SYSTEM_EXTENT_AU * AU_TO_METERS

signal grids_generated()

func _ready() -> void:
	# Connect to UniverseManager system loading (sibling node under SpaceFlight)
	var um := get_node_or_null("../UniverseManager")
	if um and um.has_signal("system_loaded"):
		um.system_loaded.connect(_on_system_loaded)
	# UniverseManager._ready() runs before this node (earlier in tree order),
	# so the system is already loaded. Generate immediately.
	call_deferred("_check_and_generate")

func _check_and_generate() -> void:
	if _is_generated:
		return
	var um := get_node_or_null("../UniverseManager")
	if um:
		var sys_data: Dictionary = um.get("current_system_data")
		if not sys_data.is_empty():
			_on_system_loaded(sys_data)

func _on_system_loaded(system_data: Dictionary) -> void:
	var seed_val: int = int(system_data.get("seed", 0))
	if seed_val == _system_seed and _is_generated:
		return  # Already generated for this system
	_system_seed = seed_val
	_generate_all_grids()

# --- Noise generator initialization ---
func _get_noise_generator(channel: Channel) -> FastNoiseLite:
	if _noise_generators.has(channel):
		return _noise_generators[channel]

	var params: Dictionary = NOISE_PARAMS[channel]
	var noise := FastNoiseLite.new()

	# Derive a unique seed per channel from the system seed
	# This ensures each channel has independent noise patterns
	var channel_seed: int = _system_seed ^ (int(channel) + 1) * 0x9E3779B9
	noise.seed = channel_seed
	noise.noise_type = params["type"]
	noise.fractal_type = params["fractal"]
	noise.fractal_octaves = int(params["octaves"])
	noise.fractal_lacunarity = float(params["lacunarity"])
	noise.fractal_gain = float(params["gain"])
	noise.frequency = float(params["frequency"])

	# Cellular distance function for enemy territories
	if params["type"] == FastNoiseLite.TYPE_CELLULAR:
		noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE

	_noise_generators[channel] = noise
	return noise

# --- Grid generation ---
func _generate_all_grids() -> void:
	_grids.clear()
	for channel in [Channel.RESOURCES, Channel.ENEMIES, Channel.ANOMALIES, Channel.HAZARDS]:
		_grids[channel] = _generate_grid(channel)
	_is_generated = true
	grids_generated.emit()
	print("[SystemNoiseField] Generated %d noise channels for system seed %d" % [CHANNEL_COUNT, _system_seed])

func _generate_grid(channel: Channel) -> PackedByteArray:
	var noise := _get_noise_generator(channel)
	var grid := PackedByteArray()
	grid.resize(GRID_RESOLUTION * GRID_RESOLUTION)

	var half_res: float = float(GRID_RESOLUTION) * 0.5
	for y in range(GRID_RESOLUTION):
		for x in range(GRID_RESOLUTION):
			# Map grid coordinates to noise space
			# Center the grid at system origin (star)
			var nx: float = (float(x) - half_res) / half_res  # [-1, 1]
			var ny: float = (float(y) - half_res) / half_res  # [-1, 1]

			# Sample noise and normalize to [0, 255]
			var raw: float = noise.get_noise_2d(nx * SYSTEM_EXTENT_AU, ny * SYSTEM_EXTENT_AU)
			# FastNoiseLite returns roughly [-1, 1]; normalize to [0, 1]
			var normalized: float = (raw + 1.0) * 0.5
			normalized = clampf(normalized, 0.0, 1.0)

			grid[y * GRID_RESOLUTION + x] = int(normalized * 255.0)

	return grid

# --- Public API: Sample at a world position ---
## Returns the noise value [0.0, 1.0] for the given channel at a world position.
## Position should be in system-local meters (relative to the star).
func sample_channel(channel: Channel, world_pos_m: Vector3) -> float:
	if not _is_generated:
		return 0.0
	# Map world position to grid coordinates
	# The grid covers [-SYSTEM_EXTENT_M, +SYSTEM_EXTENT_M] on XZ plane
	var grid_x: float = (world_pos_m.x / _system_extent_m + 1.0) * 0.5 * float(GRID_RESOLUTION)
	var grid_z: float = (world_pos_m.z / _system_extent_m + 1.0) * 0.5 * float(GRID_RESOLUTION)
	return _sample_grid_bilinear(channel, grid_x, grid_z)

func _sample_grid_bilinear(channel: Channel, gx: float, gy: float) -> float:
	if not _grids.has(channel):
		return 0.0
	var grid: PackedByteArray = _grids[channel]

	# Clamp to grid bounds
	gx = clampf(gx, 0.0, float(GRID_RESOLUTION) - 1.001)
	gy = clampf(gy, 0.0, float(GRID_RESOLUTION) - 1.001)

	var x0: int = int(gx)
	var y0: int = int(gy)
	var x1: int = x0 + 1
	var y1: int = y0 + 1
	var fx: float = gx - float(x0)
	var fy: float = gy - float(y0)

	var v00: float = float(grid[y0 * GRID_RESOLUTION + x0]) / 255.0
	var v10: float = float(grid[y0 * GRID_RESOLUTION + x1]) / 255.0
	var v01: float = float(grid[y1 * GRID_RESOLUTION + x0]) / 255.0
	var v11: float = float(grid[y1 * GRID_RESOLUTION + x1]) / 255.0

	var v0: float = lerpf(v00, v10, fx)
	var v1: float = lerpf(v01, v11, fx)
	return lerpf(v0, v1, fy)

# --- Public API: Get raw grid data ---
func get_grid(channel: Channel) -> PackedByteArray:
	return _grids.get(channel, PackedByteArray())

## Bulk sample a channel over a circular region. Returns average, min, max.
## Used by ChunkStreamManager for chunk-level density queries.
func sample_channel_region(channel: Channel, center_m: Vector3, radius_m: float) -> Dictionary:
	if not _is_generated:
		return {"avg": 0.0, "min": 0.0, "max": 0.0, "samples": 0}

	# Map center to grid coordinates
	var cgx: float = (center_m.x / _system_extent_m + 1.0) * 0.5 * float(GRID_RESOLUTION)
	var cgy: float = (center_m.z / _system_extent_m + 1.0) * 0.5 * float(GRID_RESOLUTION)
	# Map radius to grid units
	var grid_radius: float = (radius_m / _system_extent_m) * 0.5 * float(GRID_RESOLUTION)
	grid_radius = maxf(grid_radius, 1.0)

	# Sample on a sparse grid within the circle (step = max(1, grid_radius/8))
	var step: int = maxi(1, int(grid_radius / 8.0))
	var total: float = 0.0
	var count: int = 0
	var min_val: float = 1.0
	var max_val: float = 0.0

	var x_start: int = maxi(0, int(cgx - grid_radius))
	var x_end: int = mini(GRID_RESOLUTION - 1, int(cgx + grid_radius))
	var y_start: int = maxi(0, int(cgy - grid_radius))
	var y_end: int = mini(GRID_RESOLUTION - 1, int(cgy + grid_radius))

	for gy in range(y_start, y_end + 1, step):
		for gx in range(x_start, x_end + 1, step):
			# Check if within circle
			var dx: float = float(gx) - cgx
			var dy: float = float(gy) - cgy
			if dx * dx + dy * dy > grid_radius * grid_radius:
				continue
			var val: float = _sample_grid_nearest(channel, gx, gy)
			total += val
			count += 1
			if val < min_val:
				min_val = val
			if val > max_val:
				max_val = val

	if count == 0:
		return {"avg": 0.0, "min": 0.0, "max": 0.0, "samples": 0}
	return {"avg": total / float(count), "min": min_val, "max": max_val, "samples": count}

func _sample_grid_nearest(channel: Channel, gx: int, gy: int) -> float:
	if not _grids.has(channel):
		return 0.0
	var grid: PackedByteArray = _grids[channel]
	gx = clampi(gx, 0, GRID_RESOLUTION - 1)
	gy = clampi(gy, 0, GRID_RESOLUTION - 1)
	return float(grid[gy * GRID_RESOLUTION + gx]) / 255.0

## Bulk sample all 4 channels over a region. Returns Dictionary per channel.
func sample_all_channels_region(center_m: Vector3, radius_m: float) -> Dictionary:
	return {
		"resources": sample_channel_region(Channel.RESOURCES, center_m, radius_m),
		"enemies": sample_channel_region(Channel.ENEMIES, center_m, radius_m),
		"anomalies": sample_channel_region(Channel.ANOMALIES, center_m, radius_m),
		"hazards": sample_channel_region(Channel.HAZARDS, center_m, radius_m),
	}

func get_grid_resolution() -> int:
	return GRID_RESOLUTION

func get_system_extent_m() -> float:
	return _system_extent_m

func get_system_extent_au() -> float:
	return SYSTEM_EXTENT_AU

func is_generated() -> bool:
	return _is_generated

func get_system_seed() -> int:
	return _system_seed

## Returns all 4 channel values at a position as a Dictionary.
func sample_all_channels(world_pos_m: Vector3) -> Dictionary:
	return {
		"resources": sample_channel(Channel.RESOURCES, world_pos_m),
		"enemies": sample_channel(Channel.ENEMIES, world_pos_m),
		"anomalies": sample_channel(Channel.ANOMALIES, world_pos_m),
		"hazards": sample_channel(Channel.HAZARDS, world_pos_m),
	}

## Creates an Image from a channel grid for texture generation.
func get_channel_image(channel: Channel) -> Image:
	var grid: PackedByteArray = _grids.get(channel, PackedByteArray())
	if grid.is_empty():
		return Image.new()
	var img := Image.create(GRID_RESOLUTION, GRID_RESOLUTION, false, Image.FORMAT_L8)
	for y in range(GRID_RESOLUTION):
		for x in range(GRID_RESOLUTION):
			img.set_pixel(x, y, Color(float(grid[y * GRID_RESOLUTION + x]) / 255.0, 0.0, 0.0))
	return img

## Creates a colored Image from a channel grid for debug visualization.
func get_channel_colored_image(channel: Channel) -> Image:
	var grid: PackedByteArray = _grids.get(channel, PackedByteArray())
	if grid.is_empty():
		return Image.new()
	var base_color: Color = CHANNEL_COLORS[channel]
	var img := Image.create(GRID_RESOLUTION, GRID_RESOLUTION, false, Image.FORMAT_RGBA8)
	for y in range(GRID_RESOLUTION):
		for x in range(GRID_RESOLUTION):
			var val: float = float(grid[y * GRID_RESOLUTION + x]) / 255.0
			var c := Color(base_color.r * val, base_color.g * val, base_color.b * val, val * 0.7)
			img.set_pixel(x, y, c)
	return img
