# res://scripts/GalacticNoiseField.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# GalacticNoiseField.gd — Gameplay Distribution Noise Maps (Galactic Scale)
# ==============================================================================
# Generates 4 deterministic noise channels for GAMEPLAY element distribution
# at the galactic scale (for the galaxy map meta-layer). These noise maps
# determine per-system gameplay characteristics and do NOT affect the real
# astrophysical star generation in ProceduralGalaxy.gd.
#
# Channels (same as SystemNoiseField but at galactic scale):
#   - RESOURCES: Average resource richness per star system
#   - ENEMIES:   Hostile activity level per region
#   - ANOMALIES: Anomaly probability per region
#   - HAZARDS:   Environmental hazard level per region
#
# The noise is sampled at galactic coordinates (light-years) on the galactic
# plane (XZ). Values are in [0, 1].
#
# Used by: GalaxyMapVisuals for overlay rendering, UniverseManager for
#          system selection weighting, mission generation.
# ==============================================================================

extends Node

# --- Channel IDs (mirror SystemNoiseField) ---
enum Channel {
	RESOURCES,
	ENEMIES,
	ANOMALIES,
	HAZARDS,
}

const CHANNEL_COUNT: int = 4

const CHANNEL_COLORS: Dictionary = {
	Channel.RESOURCES: Color(0.0, 1.0, 0.4),
	Channel.ENEMIES: Color(1.0, 0.3, 0.1),
	Channel.ANOMALIES: Color(0.7, 0.3, 1.0),
	Channel.HAZARDS: Color(1.0, 0.8, 0.0),
}

const CHANNEL_NAMES: Dictionary = {
	Channel.RESOURCES: "resources",
	Channel.ENEMIES: "enemies",
	Channel.ANOMALIES: "anomalies",
	Channel.HAZARDS: "hazards",
}

# --- Grid configuration ---
const GRID_RESOLUTION: int = 512           # 512x512 covers a large galactic region
const GALACTIC_EXTENT_LY: float = 5000.0   # 5000 LY radius from current position
const GALAXY_SEED: int = 0x50756D69         # Matches ProceduralGalaxy master seed

# --- Noise parameters per channel (galactic scale, gameplay only) ---
const NOISE_PARAMS: Dictionary = {
	Channel.RESOURCES: {
		"type": FastNoiseLite.TYPE_SIMPLEX,
		"fractal": FastNoiseLite.FRACTAL_FBM,
		"octaves": 5,
		"lacunarity": 2.0,
		"gain": 0.5,
		"frequency": 0.002,   # Large resource-rich regions
	},
	Channel.ENEMIES: {
		"type": FastNoiseLite.TYPE_CELLULAR,
		"fractal": FastNoiseLite.FRACTAL_NONE,
		"octaves": 1,
		"lacunarity": 2.0,
		"gain": 0.5,
		"frequency": 0.0015,  # Large hostile territories
	},
	Channel.ANOMALIES: {
		"type": FastNoiseLite.TYPE_SIMPLEX,
		"fractal": FastNoiseLite.FRACTAL_RIDGED,
		"octaves": 4,
		"lacunarity": 2.5,
		"gain": 0.55,
		"frequency": 0.0025,  # Anomaly-rich zones
	},
	Channel.HAZARDS: {
		"type": FastNoiseLite.TYPE_PERLIN,
		"fractal": FastNoiseLite.FRACTAL_FBM,
		"octaves": 4,
		"lacunarity": 2.0,
		"gain": 0.45,
		"frequency": 0.0018,  # Hazard regions
	},
}

# --- State ---
var _noise_generators: Dictionary = {}
var _grids: Dictionary = {}
var _is_generated: bool = false
var _center_ly: Vector3 = Vector3.ZERO

signal grids_generated()

func _ready() -> void:
	# Use default galactic coordinates (Sol reference).
	# UniverseManager is a scene node that loads after autoloads,
	# so we use the default position and regenerate if needed.
	_center_ly = Vector3(0.0, 15.0, 26000.0)
	# Generate the galactic noise field
	_generate_all_grids()

# --- Noise generator initialization ---
func _get_noise_generator(channel: Channel) -> FastNoiseLite:
	if _noise_generators.has(channel):
		return _noise_generators[channel]

	var params: Dictionary = NOISE_PARAMS[channel]
	var noise := FastNoiseLite.new()

	# Use the galaxy master seed + channel offset for deterministic galactic noise
	var channel_seed: int = GALAXY_SEED ^ (int(channel) + 1) * 0x9E3779B9
	noise.seed = channel_seed
	noise.noise_type = params["type"]
	noise.fractal_type = params["fractal"]
	noise.fractal_octaves = int(params["octaves"])
	noise.fractal_lacunarity = float(params["lacunarity"])
	noise.fractal_gain = float(params["gain"])
	noise.frequency = float(params["frequency"])

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
	print("[GalacticNoiseField] Generated %d galactic noise channels centered at %s LY" % [CHANNEL_COUNT, _center_ly])

func _generate_grid(channel: Channel) -> PackedByteArray:
	var noise := _get_noise_generator(channel)
	var grid := PackedByteArray()
	grid.resize(GRID_RESOLUTION * GRID_RESOLUTION)

	var half_res: float = float(GRID_RESOLUTION) * 0.5
	for y in range(GRID_RESOLUTION):
		for x in range(GRID_RESOLUTION):
			# Map grid coordinates to galactic coordinates (LY)
			var gx_ly: float = _center_ly.x + (float(x) - half_res) / half_res * GALACTIC_EXTENT_LY
			var gz_ly: float = _center_ly.z + (float(y) - half_res) / half_res * GALACTIC_EXTENT_LY

			var raw: float = noise.get_noise_2d(gx_ly, gz_ly)
			var normalized: float = (raw + 1.0) * 0.5
			normalized = clampf(normalized, 0.0, 1.0)

			grid[y * GRID_RESOLUTION + x] = int(normalized * 255.0)

	return grid

# --- Public API ---
## Returns the noise value [0.0, 1.0] for a channel at galactic coordinates (LY).
func sample_channel(channel: Channel, galactic_pos_ly: Vector3) -> float:
	if not _is_generated:
		return 0.0
	var grid_x: float = (galactic_pos_ly.x - _center_ly.x + GALACTIC_EXTENT_LY) / (2.0 * GALACTIC_EXTENT_LY) * float(GRID_RESOLUTION)
	var grid_z: float = (galactic_pos_ly.z - _center_ly.z + GALACTIC_EXTENT_LY) / (2.0 * GALACTIC_EXTENT_LY) * float(GRID_RESOLUTION)
	return _sample_grid_bilinear(channel, grid_x, grid_z)

func _sample_grid_bilinear(channel: Channel, gx: float, gy: float) -> float:
	if not _grids.has(channel):
		return 0.0
	var grid: PackedByteArray = _grids[channel]
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

	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)

func get_grid(channel: Channel) -> PackedByteArray:
	return _grids.get(channel, PackedByteArray())

func get_grid_resolution() -> int:
	return GRID_RESOLUTION

func get_galactic_extent_ly() -> float:
	return GALACTIC_EXTENT_LY

func get_center_ly() -> Vector3:
	return _center_ly

func is_generated() -> bool:
	return _is_generated

## Returns all 4 channel values at a galactic position.
func sample_all_channels(galactic_pos_ly: Vector3) -> Dictionary:
	return {
		"resources": sample_channel(Channel.RESOURCES, galactic_pos_ly),
		"enemies": sample_channel(Channel.ENEMIES, galactic_pos_ly),
		"anomalies": sample_channel(Channel.ANOMALIES, galactic_pos_ly),
		"hazards": sample_channel(Channel.HAZARDS, galactic_pos_ly),
	}

## Creates a colored Image from a channel grid for galaxy map overlay.
func get_channel_colored_image(channel: Channel) -> Image:
	var grid: PackedByteArray = _grids.get(channel, PackedByteArray())
	if grid.is_empty():
		return Image.new()
	var base_color: Color = CHANNEL_COLORS[channel]
	var img := Image.create(GRID_RESOLUTION, GRID_RESOLUTION, false, Image.FORMAT_RGBA8)
	for y in range(GRID_RESOLUTION):
		for x in range(GRID_RESOLUTION):
			var val: float = float(grid[y * GRID_RESOLUTION + x]) / 255.0
			var c := Color(base_color.r * val, base_color.g * val, base_color.b * val, val * 0.6)
			img.set_pixel(x, y, c)
	return img

## Regenerates grids centered on a new galactic position (after hyperjump).
func regenerate_for_position(new_center_ly: Vector3) -> void:
	_center_ly = new_center_ly
	_noise_generators.clear()
	_generate_all_grids()
