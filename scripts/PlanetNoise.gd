# ==============================================================================
# BioGenesis-X: PlanetNoise — Seed-Deterministic Multi-Octave Terrain Noise Library
# ==============================================================================
# Production-grade deterministic noise foundation for true-scale planet terrain
# generation. All functions are 3D and evaluated directly on the unit-sphere
# surface (x,y,z with |v| == 1) so terrain wraps seamlessly with zero UV seams.
#
# Determinism contract: identical (seed, archetype, point) ALWAYS yields identical
# output across runs, platforms, and Godot sessions. FastNoiseLite is seeded and
# all custom hash noise uses pure integer arithmetic with no global state.
#
# Noise primitives:
#   - Perlin / Simplex fBm        (base elevation, continents)
#   - Ridged multifractal         (mountain ranges, lava channels)
#   - Voronoi / Worley            (biome boundaries, cell patterns, craters)
#   - Curl noise                  (cloud movement, water flow — gradient-derived)
#   - Domain-warped noise         (natural eroded terrain via coordinate displacement)
#
# Archetype presets (0..7) configure elevation, biome, color, sea level, and
# solid-surface flags for the 8 BioGenesis-X planet archetypes.
# ==============================================================================

class_name PlanetNoise
extends RefCounted

# ------------------------------------------------------------------------------
# Enums
# ------------------------------------------------------------------------------

## Canonical BioGenesis-X planet archetypes (see LORE.md).
enum Archetype {
	MOLTEN,            ## 0 — volcanic, extreme ridged noise, lava channels
	METALLIC_BARREN,   ## 1 — cratered, heavy Voronoi, low elevation variation
	DESERT_ARID,       ## 2 — dunes, low-frequency ridged, wind erosion
	TERRAN_OCEANIC,    ## 3 — continents via low-freq Perlin, ridged mountains
	ICE_WORLD,         ## 4 — smooth base with jagged ice formations
	GAS_GIANT_JOVIAN,  ## 5 — banded horizontal stripes, turbulent swirls
	GAS_GIANT_ICE,     ## 6 — banded methane storms, different color/scale
	RADIOTROPHIC_BIO,  ## 7 — organic bioluminescent Voronoi, smooth+spiky mix
}

## Surface biome identifiers returned by sample_terrain().
enum Biome {
	DEEP_OCEAN,          ## 0
	OCEAN,               ## 1
	SHALLOW_WATER,       ## 2
	BEACH,               ## 3
	GRASSLAND,           ## 4
	FOREST,              ## 5
	MOUNTAIN_ROCK,       ## 6
	SNOW,                ## 7
	ICE,                 ## 8
	DESERT,              ## 9
	DUNES,               ## 10
	VOLCANIC_ROCK,       ## 11
	LAVA,                ## 12
	CRATER,              ## 13
	BARREN_ROCK,         ## 14
	ICE_FORMATION,       ## 15
	GAS_BAND_LIGHT,      ## 16
	GAS_BAND_DARK,       ## 17
	METHANE_STORM,       ## 18
	BIOLUMINESCENT_CELL, ## 19
}

## Voronoi distance metric selector.
enum VoronoiMetric {
	EUCLIDEAN,   ## 0 — straight-line distance
	MANHATTAN,   ## 1 — grid distance (blocky cells)
	CHEBYSHEV,   ## 2 — square cells
}

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

const _LARGE_PRIME_X: int = 374761393
const _LARGE_PRIME_Y: int = 668265263
const _LARGE_PRIME_Z: int = 2147483647
const _LARGE_PRIME_SEED: int = 1274126177
const _HASH_MASK: int = 0x7FFFFFFF
const _HASH_DIVISOR: float = 2147483647.0
const _CURL_EPSILON: float = 1e-4
const _LATITUDE_FREEZE: float = 0.85  ## |latitude| above which polar ice dominates
const _TEMP_LAPSE: float = 0.45       ## elevation-driven temperature drop factor

# ------------------------------------------------------------------------------
# Internal noise-instance cache (keyed by deterministic param signature)
# ------------------------------------------------------------------------------

var _noise_cache: Dictionary = {}

# ==============================================================================
# PUBLIC API — Primary terrain sampling
# ==============================================================================

## Evaluate full terrain state for a point on the unit sphere.
## Returns: {"elevation": float, "moisture": float, "temperature": float, "biome_id": int}
func sample_terrain(point_on_unit_sphere: Vector3, seed: int, archetype: int) -> Dictionary:
	var p: Vector3 = point_on_unit_sphere.normalized()
	var preset: Dictionary = get_archetype_preset(archetype)
	var elev_params: Dictionary = preset["elevation_params"]
	var biome_params: Dictionary = preset["biome_params"]
	var sea_level: float = preset["sea_level"]

	# --- Elevation -----------------------------------------------------------
	var elevation: float = _compute_elevation(p, seed, archetype, elev_params)

	# Gas giants have no solid surface — return banded "elevation" for shading.
	if not bool(preset["has_solid_surface"]):
		var band: float = _gas_band_value(p, seed, archetype)
		elevation = band

	# --- Moisture (separate noise channel) -----------------------------------
	var moisture: float = _compute_moisture(p, seed, biome_params)

	# --- Temperature (latitude + altitude lapse) -----------------------------
	var latitude: float = p.y  # unit-sphere y ∈ [-1,1]
	var temperature: float = _compute_temperature(latitude, elevation, biome_params)

	# --- Biome identification ------------------------------------------------
	var biome_id: int = _determine_biome(elevation, moisture, temperature, sea_level, archetype)

	return {
		"elevation": elevation,
		"moisture": moisture,
		"temperature": temperature,
		"biome_id": biome_id,
	}

# ==============================================================================
# PUBLIC API — Noise primitives (all operate on arbitrary 3D coordinates)
# ==============================================================================

## Multi-octave fractal Brownian motion (fBm) using FastNoiseLite base noise.
## Returns roughly [-1, 1]. Deterministic for the given seed.
func fbm(point: Vector3, seed: int, base_frequency: float, octaves: int,
		persistence: float, lacunarity: float,
		noise_type: int = FastNoiseLite.TYPE_SIMPLEX) -> float:
	var noise: FastNoiseLite = _get_noise(seed, noise_type, base_frequency)
	var total: float = 0.0
	var frequency: float = 1.0
	var amplitude: float = 1.0
	var max_value: float = 0.0
	for _i: int in range(max(1, octaves)):
		var p: Vector3 = point * frequency
		total += noise.get_noise_3d(p.x, p.y, p.z) * amplitude
		max_value += amplitude
		amplitude *= persistence
		frequency *= lacunarity
	if max_value <= 0.0:
		return 0.0
	return total / max_value

## Ridged multifractal noise — produces sharp mountain ridges.
## ridged_power controls sharpness (1.0 = gentle, 2.0+ = jagged peaks).
## Returns [0, 1].
func ridged_noise(point: Vector3, seed: int, base_frequency: float, octaves: int,
		persistence: float, lacunarity: float, ridged_power: float,
		noise_type: int = FastNoiseLite.TYPE_SIMPLEX) -> float:
	var noise: FastNoiseLite = _get_noise(seed, noise_type, base_frequency)
	var total: float = 0.0
	var frequency: float = 1.0
	var amplitude: float = 1.0
	var max_value: float = 0.0
	for _i: int in range(max(1, octaves)):
		var p: Vector3 = point * frequency
		var n: float = noise.get_noise_3d(p.x, p.y, p.z)
		var ridge: float = 1.0 - abs(n)
		ridge = pow(clamp(ridge, 0.0, 1.0), ridged_power)
		total += ridge * amplitude
		max_value += amplitude
		amplitude *= persistence
		frequency *= lacunarity
	if max_value <= 0.0:
		return 0.0
	return total / max_value

## Hash-based Voronoi / Worley noise — distance to nearest feature point.
## Returns the F1 distance in [0, ~1.5] (metric-dependent). Deterministic.
func voronoi_noise(point: Vector3, seed: int, frequency: float,
		metric: int = VoronoiMetric.EUCLIDEAN) -> float:
	var sp: Vector3 = point * frequency
	var ix: int = int(floor(sp.x))
	var iy: int = int(floor(sp.y))
	var iz: int = int(floor(sp.z))
	var min_dist: float = 1e9
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				var cx: int = ix + dx
				var cy: int = iy + dy
				var cz: int = iz + dz
				var fx: float = _hash_to_float(_hash3(cx, cy, cz, seed, 0))
				var fy: float = _hash_to_float(_hash3(cx, cy, cz, seed, 1))
				var fz: float = _hash_to_float(_hash3(cx, cy, cz, seed, 2))
				var feature: Vector3 = Vector3(float(cx) + fx, float(cy) + fy, float(cz) + fz)
				var diff: Vector3 = sp - feature
				var d: float = _voronoi_distance(diff, metric)
				if d < min_dist:
					min_dist = d
	return min_dist

## Voronoi cell ID (integer hash of the nearest feature cell) — for biome tiling.
func voronoi_cell_id(point: Vector3, seed: int, frequency: float) -> int:
	var sp: Vector3 = point * frequency
	var ix: int = int(floor(sp.x))
	var iy: int = int(floor(sp.y))
	var iz: int = int(floor(sp.z))
	var best_cell: Vector3i = Vector3i(ix, iy, iz)
	var min_dist: float = 1e9
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				var cx: int = ix + dx
				var cy: int = iy + dy
				var cz: int = iz + dz
				var fx: float = _hash_to_float(_hash3(cx, cy, cz, seed, 0))
				var fy: float = _hash_to_float(_hash3(cx, cy, cz, seed, 1))
				var fz: float = _hash_to_float(_hash3(cx, cy, cz, seed, 2))
				var feature: Vector3 = Vector3(float(cx) + fx, float(cy) + fy, float(cz) + fz)
				var d: float = (sp - feature).length_squared()
				if d < min_dist:
					min_dist = d
					best_cell = Vector3i(cx, cy, cz)
	return _hash3(best_cell.x, best_cell.y, best_cell.z, seed, 3) & _HASH_MASK

## Curl noise — divergence-free vector field derived from a potential field
## via finite-difference gradients. Ideal for cloud / water flow advection.
func curl_noise(point: Vector3, seed: int, frequency: float) -> Vector3:
	# Three independent scalar potentials form a vector potential A = (Ax, Ay, Az).
	# curl(A) = (∂Az/∂y - ∂Ay/∂z, ∂Ax/∂z - ∂Az/∂x, ∂Ay/∂x - ∂Ax/∂y)
	# All partials use central finite differences for symmetry & accuracy.
	var eps: float = _CURL_EPSILON
	var inv_2eps: float = 1.0 / (2.0 * eps)

	var dAx_dy: float = _potential(point + Vector3(0.0, eps, 0.0), seed, 0, frequency) \
			- _potential(point - Vector3(0.0, eps, 0.0), seed, 0, frequency)
	var dAx_dz: float = _potential(point + Vector3(0.0, 0.0, eps), seed, 0, frequency) \
			- _potential(point - Vector3(0.0, 0.0, eps), seed, 0, frequency)
	var dAy_dx: float = _potential(point + Vector3(eps, 0.0, 0.0), seed, 1, frequency) \
			- _potential(point - Vector3(eps, 0.0, 0.0), seed, 1, frequency)
	var dAy_dz: float = _potential(point + Vector3(0.0, 0.0, eps), seed, 1, frequency) \
			- _potential(point - Vector3(0.0, 0.0, eps), seed, 1, frequency)
	var dAz_dx: float = _potential(point + Vector3(eps, 0.0, 0.0), seed, 2, frequency) \
			- _potential(point - Vector3(eps, 0.0, 0.0), seed, 2, frequency)
	var dAz_dy: float = _potential(point + Vector3(0.0, eps, 0.0), seed, 2, frequency) \
			- _potential(point - Vector3(0.0, eps, 0.0), seed, 2, frequency)

	var curl_x: float = (dAz_dy - dAy_dz) * inv_2eps
	var curl_y: float = (dAx_dz - dAz_dx) * inv_2eps
	var curl_z: float = (dAy_dx - dAx_dy) * inv_2eps
	return Vector3(curl_x, curl_y, curl_z)

## Domain-warped noise — displaces the sampling coordinates of another noise
## field using a warp field, producing natural, eroded-looking terrain.
func domain_warp(point: Vector3, seed: int, base_frequency: float, octaves: int,
		persistence: float, lacunarity: float, warp_strength: float,
		noise_type: int = FastNoiseLite.TYPE_SIMPLEX) -> float:
	var warp_x: float = fbm(point + Vector3(0.0, 0.0, 0.0), seed + 101, base_frequency * 2.0,
			max(1, octaves / 2), persistence, lacunarity, noise_type)
	var warp_y: float = fbm(point + Vector3(5.2, 1.3, 0.0), seed + 202, base_frequency * 2.0,
			max(1, octaves / 2), persistence, lacunarity, noise_type)
	var warp_z: float = fbm(point + Vector3(1.7, 9.2, 0.0), seed + 303, base_frequency * 2.0,
			max(1, octaves / 2), persistence, lacunarity, noise_type)
	var warped: Vector3 = point + Vector3(warp_x, warp_y, warp_z) * warp_strength
	return fbm(warped, seed, base_frequency, octaves, persistence, lacunarity, noise_type)

# ==============================================================================
# PUBLIC API — Biome blending
# ==============================================================================

## Blend biome factors (latitude, altitude, moisture) into a biome id.
## Latitude ∈ [-1,1] (unit-sphere y), altitude & moisture ∈ [0,1].
func blend_biome(latitude: float, altitude: float, moisture: float,
		sea_level: float, archetype: int) -> int:
	return _determine_biome(altitude, moisture,
			_compute_temperature(latitude, altitude, get_archetype_preset(archetype)["biome_params"]),
			sea_level, archetype)

## Sample a color ramp (Array of {"altitude": float, "color": Color}) at t ∈ [0,1].
func sample_color_ramp(ramp: Array, t: float) -> Color:
	if ramp.is_empty():
		return Color.BLACK
	if t <= float(ramp[0]["altitude"]):
		return ramp[0]["color"]
	for i: int in range(1, ramp.size()):
		if t <= float(ramp[i]["altitude"]):
			var a: Dictionary = ramp[i - 1]
			var b: Dictionary = ramp[i]
			var span: float = float(b["altitude"]) - float(a["altitude"])
			if span <= 0.0:
				return b["color"]
			var f: float = clamp((t - float(a["altitude"])) / span, 0.0, 1.0)
			return (a["color"] as Color).lerp(b["color"], f)
	return ramp[ramp.size() - 1]["color"]

# ==============================================================================
# PUBLIC API — Archetype presets
# ==============================================================================

## Returns the full configuration preset for a planet archetype.
func get_archetype_preset(archetype: int) -> Dictionary:
	match archetype:
		Archetype.MOLTEN:
			return _preset_molten()
		Archetype.METALLIC_BARREN:
			return _preset_metallic_barren()
		Archetype.DESERT_ARID:
			return _preset_desert_arid()
		Archetype.TERRAN_OCEANIC:
			return _preset_terran_oceanic()
		Archetype.ICE_WORLD:
			return _preset_ice_world()
		Archetype.GAS_GIANT_JOVIAN:
			return _preset_gas_giant_jovian()
		Archetype.GAS_GIANT_ICE:
			return _preset_gas_giant_ice()
		Archetype.RADIOTROPHIC_BIO:
			return _preset_radiotrophic_bio()
		_:
			return _preset_terran_oceanic()

# ==============================================================================
# INTERNAL — Elevation / moisture / temperature / biome computation
# ==============================================================================

func _compute_elevation(p: Vector3, seed: int, archetype: int,
		params: Dictionary) -> float:
	var freq: float = float(params["frequency"])
	var octaves: int = int(params["octaves"])
	var persistence: float = float(params["persistence"])
	var lacunarity: float = float(params["lacunarity"])
	var ridged_power: float = float(params["ridged_power"])
	var warp_strength: float = float(params["warp_strength"])

	var base: float = 0.0
	var ridged: float = 0.0
	var cells: float = 0.0

	match archetype:
		Archetype.MOLTEN:
			# Extreme ridged noise + lava channels (Voronoi troughs)
			ridged = ridged_noise(p, seed, freq, octaves, persistence, lacunarity, ridged_power)
			cells = voronoi_noise(p, seed + 7, freq * 0.5, VoronoiMetric.EUCLIDEAN)
			base = ridged * 0.8 - clamp(cells - 0.5, 0.0, 0.5) * 0.4
		Archetype.METALLIC_BARREN:
			# Heavy Voronoi craters, low elevation variation
			cells = voronoi_noise(p, seed, freq, VoronoiMetric.EUCLIDEAN)
			base = fbm(p, seed, freq * 0.5, octaves, persistence, lacunarity)
			base = base * 0.3 + (1.0 - clamp(cells, 0.0, 1.0)) * 0.5
		Archetype.DESERT_ARID:
			# Dunes (domain-warped low-freq ridged) + wind erosion
			ridged = ridged_noise(p, seed, freq * 0.5, octaves, persistence, lacunarity, ridged_power)
			var dunes: float = domain_warp(p, seed + 11, freq, octaves, persistence,
					lacunarity, warp_strength, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
			base = dunes * 0.6 + ridged * 0.4
		Archetype.TERRAN_OCEANIC:
			# Continents via low-freq Perlin, mountains via ridged
			var continents: float = fbm(p, seed, freq * 0.25, octaves, persistence, lacunarity,
					FastNoiseLite.TYPE_SIMPLEX)
			ridged = ridged_noise(p, seed + 3, freq, max(1, octaves - 1), persistence,
					lacunarity, ridged_power)
			base = continents * 0.7 + ridged * 0.3
		Archetype.ICE_WORLD:
			# Smooth base + jagged high-frequency ice formations
			var smooth_base: float = fbm(p, seed, freq * 0.5, octaves, persistence, lacunarity,
					FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
			ridged = ridged_noise(p, seed + 5, freq * 2.0, octaves, persistence, lacunarity,
					ridged_power)
			base = smooth_base * 0.6 + ridged * 0.4
		Archetype.GAS_GIANT_JOVIAN, Archetype.GAS_GIANT_ICE:
			# No solid surface — banded value computed in sample_terrain
			base = 0.0
		Archetype.RADIOTROPHIC_BIO:
			# Organic: smooth + spiky mix, bioluminescent Voronoi cells
			var smooth: float = fbm(p, seed, freq * 0.5, octaves, persistence, lacunarity,
					FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
			ridged = ridged_noise(p, seed + 9, freq, octaves, persistence, lacunarity, ridged_power)
			cells = voronoi_noise(p, seed + 13, freq * 0.75, VoronoiMetric.EUCLIDEAN)
			base = smooth * 0.4 + ridged * 0.4 + (1.0 - clamp(cells, 0.0, 1.0)) * 0.2
		_:
			base = fbm(p, seed, freq, octaves, persistence, lacunarity)

	# Normalize to [0,1] for solid-surface worlds
	return clamp(base * 0.5 + 0.5, 0.0, 1.0)

func _gas_band_value(p: Vector3, seed: int, archetype: int) -> float:
	# Horizontal banding driven by latitude (y), perturbed by turbulent swirls.
	var latitude: float = p.y
	var band_seed: int = seed + (archetype * 31)
	var turbulence: float = fbm(Vector3(p.x * 3.0, p.y * 8.0, p.z * 3.0), band_seed,
			1.5, 4, 0.5, 2.0, FastNoiseLite.TYPE_SIMPLEX)
	var bands: float = sin(latitude * 18.0 + turbulence * 2.5)
	return clamp(bands * 0.5 + 0.5, 0.0, 1.0)

func _compute_moisture(p: Vector3, seed: int, biome_params: Dictionary) -> float:
	var freq: float = float(biome_params["moisture_frequency"])
	var octaves: int = int(biome_params["moisture_octaves"])
	var m: float = fbm(p, seed + 555, freq, octaves, 0.5, 2.0, FastNoiseLite.TYPE_SIMPLEX)
	return clamp(m * 0.5 + 0.5, 0.0, 1.0)

func _compute_temperature(latitude: float, elevation: float,
		biome_params: Dictionary) -> float:
	var latitude_bias: float = float(biome_params["latitude_bias"])
	# Equator hot, poles cold; higher elevation = colder (lapse rate).
	var lat_temp: float = 1.0 - abs(latitude) * latitude_bias
	# Polar ice-cap guarantee: latitudes beyond the freeze line are always cold.
	if abs(latitude) > _LATITUDE_FREEZE:
		lat_temp = min(lat_temp, 0.15)
	var elev_temp: float = elevation * _TEMP_LAPSE
	return clamp(lat_temp - elev_temp, 0.0, 1.0)

func _determine_biome(elevation: float, moisture: float, temperature: float,
		sea_level: float, archetype: int) -> int:
	# Archetype-specific overrides first
	match archetype:
		Archetype.MOLTEN:
			if elevation < sea_level:
				return Biome.LAVA
			if elevation > 0.75:
				return Biome.VOLCANIC_ROCK
			return Biome.VOLCANIC_ROCK
		Archetype.METALLIC_BARREN:
			if elevation < sea_level:
				return Biome.SHALLOW_WATER
			if elevation > 0.8:
				return Biome.CRATER
			return Biome.BARREN_ROCK
		Archetype.DESERT_ARID:
			if elevation < sea_level:
				return Biome.SHALLOW_WATER
			if moisture < 0.35:
				return Biome.DUNES
			return Biome.DESERT
		Archetype.ICE_WORLD:
			if elevation < sea_level:
				return Biome.ICE
			if elevation > 0.7:
				return Biome.ICE_FORMATION
			return Biome.ICE
		Archetype.GAS_GIANT_JOVIAN:
			if elevation > 0.5:
				return Biome.GAS_BAND_LIGHT
			return Biome.GAS_BAND_DARK
		Archetype.GAS_GIANT_ICE:
			if elevation > 0.6:
				return Biome.METHANE_STORM
			if elevation > 0.4:
				return Biome.GAS_BAND_LIGHT
			return Biome.GAS_BAND_DARK
		Archetype.RADIOTROPHIC_BIO:
			if elevation < sea_level:
				return Biome.SHALLOW_WATER
			if elevation > 0.7:
				return Biome.BIOLUMINESCENT_CELL
			return Biome.BIOLUMINESCENT_CELL

	# Generic Terran-style blending (latitude + altitude + moisture)
	if elevation < sea_level:
		if temperature < 0.2:
			return Biome.ICE
		if elevation < sea_level * 0.5:
			return Biome.DEEP_OCEAN
		return Biome.OCEAN

	var land: float = (elevation - sea_level) / max(0.001, 1.0 - sea_level)
	if land < 0.05:
		return Biome.BEACH
	if temperature < 0.15:
		return Biome.SNOW
	if elevation > 0.78:
		return Biome.MOUNTAIN_ROCK
	if moisture < 0.3:
		return Biome.DESERT
	if moisture > 0.6:
		return Biome.FOREST
	return Biome.GRASSLAND

# ==============================================================================
# INTERNAL — Noise helpers
# ==============================================================================

## Cached FastNoiseLite accessor — deterministic per (seed, type, frequency).
func _get_noise(seed: int, noise_type: int, frequency: float) -> FastNoiseLite:
	var key: String = "%d|%d|%.6f" % [seed, noise_type, frequency]
	if _noise_cache.has(key):
		return _noise_cache[key] as FastNoiseLite
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed
	n.noise_type = noise_type
	n.frequency = frequency
	n.fractal_octaves = 1
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_noise_cache[key] = n
	return n

## Scalar potential field for curl noise (offset per axis via seed salt).
func _potential(point: Vector3, seed: int, axis: int, frequency: float) -> float:
	var salted: FastNoiseLite = _get_noise(seed + axis * 1009, FastNoiseLite.TYPE_SIMPLEX, frequency)
	return salted.get_noise_3d(point.x, point.y, point.z)

func _voronoi_distance(diff: Vector3, metric: int) -> float:
	match metric:
		VoronoiMetric.MANHATTAN:
			return abs(diff.x) + abs(diff.y) + abs(diff.z)
		VoronoiMetric.CHEBYSHEV:
			return max(abs(diff.x), max(abs(diff.y), abs(diff.z)))
		_:
			return diff.length()

# ------------------------------------------------------------------------------
# Deterministic integer hashing (pure arithmetic — no global state)
# ------------------------------------------------------------------------------

func _hash3(ix: int, iy: int, iz: int, seed: int, salt: int) -> int:
	var h: int = (ix * _LARGE_PRIME_X) ^ (iy * _LARGE_PRIME_Y) ^ (iz * _LARGE_PRIME_Z) ^ (seed * _LARGE_PRIME_SEED) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h

func _hash_to_float(h: int) -> float:
	return float(h & _HASH_MASK) / _HASH_DIVISOR

# ==============================================================================
# INTERNAL — Archetype preset definitions
# ==============================================================================

func _preset_molten() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 1.8,
			"octaves": 6,
			"persistence": 0.55,
			"lacunarity": 2.3,
			"ridged_power": 2.2,
			"warp_strength": 0.25,
		},
		"biome_params": {
			"moisture_frequency": 0.8,
			"moisture_octaves": 3,
			"latitude_bias": 0.3,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.9, 0.25, 0.05)},
			{"altitude": 0.3, "color": Color(0.6, 0.1, 0.02)},
			{"altitude": 0.6, "color": Color(0.35, 0.08, 0.02)},
			{"altitude": 0.85, "color": Color(0.2, 0.05, 0.02)},
			{"altitude": 1.0, "color": Color(0.1, 0.02, 0.01)},
		],
		"sea_level": 0.2,
		"has_solid_surface": true,
	}

func _preset_metallic_barren() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 2.5,
			"octaves": 4,
			"persistence": 0.4,
			"lacunarity": 2.0,
			"ridged_power": 1.5,
			"warp_strength": 0.1,
		},
		"biome_params": {
			"moisture_frequency": 0.5,
			"moisture_octaves": 2,
			"latitude_bias": 0.5,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.3, 0.3, 0.35)},
			{"altitude": 0.4, "color": Color(0.45, 0.45, 0.5)},
			{"altitude": 0.7, "color": Color(0.55, 0.55, 0.6)},
			{"altitude": 1.0, "color": Color(0.7, 0.7, 0.75)},
		],
		"sea_level": 0.0,
		"has_solid_surface": true,
	}

func _preset_desert_arid() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 1.2,
			"octaves": 5,
			"persistence": 0.5,
			"lacunarity": 2.1,
			"ridged_power": 1.8,
			"warp_strength": 0.4,
		},
		"biome_params": {
			"moisture_frequency": 0.6,
			"moisture_octaves": 3,
			"latitude_bias": 0.7,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.85, 0.7, 0.4)},
			{"altitude": 0.4, "color": Color(0.75, 0.55, 0.3)},
			{"altitude": 0.7, "color": Color(0.6, 0.4, 0.2)},
			{"altitude": 1.0, "color": Color(0.45, 0.3, 0.15)},
		],
		"sea_level": 0.0,
		"has_solid_surface": true,
	}

func _preset_terran_oceanic() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 1.5,
			"octaves": 6,
			"persistence": 0.5,
			"lacunarity": 2.0,
			"ridged_power": 2.0,
			"warp_strength": 0.3,
		},
		"biome_params": {
			"moisture_frequency": 1.0,
			"moisture_octaves": 4,
			"latitude_bias": 0.8,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.02, 0.1, 0.35)},
			{"altitude": 0.45, "color": Color(0.05, 0.25, 0.55)},
			{"altitude": 0.52, "color": Color(0.85, 0.78, 0.55)},
			{"altitude": 0.58, "color": Color(0.25, 0.55, 0.2)},
			{"altitude": 0.75, "color": Color(0.4, 0.35, 0.2)},
			{"altitude": 0.9, "color": Color(0.6, 0.55, 0.5)},
			{"altitude": 1.0, "color": Color(0.95, 0.95, 0.98)},
		],
		"sea_level": 0.5,
		"has_solid_surface": true,
	}

func _preset_ice_world() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 2.0,
			"octaves": 7,
			"persistence": 0.55,
			"lacunarity": 2.2,
			"ridged_power": 2.5,
			"warp_strength": 0.2,
		},
		"biome_params": {
			"moisture_frequency": 0.7,
			"moisture_octaves": 3,
			"latitude_bias": 0.6,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.4, 0.55, 0.7)},
			{"altitude": 0.4, "color": Color(0.6, 0.75, 0.9)},
			{"altitude": 0.7, "color": Color(0.8, 0.9, 1.0)},
			{"altitude": 1.0, "color": Color(0.95, 0.98, 1.0)},
		],
		"sea_level": 0.1,
		"has_solid_surface": true,
	}

func _preset_gas_giant_jovian() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 1.5,
			"octaves": 4,
			"persistence": 0.5,
			"lacunarity": 2.0,
			"ridged_power": 1.0,
			"warp_strength": 0.5,
		},
		"biome_params": {
			"moisture_frequency": 0.5,
			"moisture_octaves": 2,
			"latitude_bias": 0.2,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.55, 0.35, 0.2)},
			{"altitude": 0.4, "color": Color(0.75, 0.55, 0.35)},
			{"altitude": 0.6, "color": Color(0.85, 0.7, 0.5)},
			{"altitude": 1.0, "color": Color(0.95, 0.85, 0.65)},
		],
		"sea_level": 0.0,
		"has_solid_surface": false,
	}

func _preset_gas_giant_ice() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 1.2,
			"octaves": 5,
			"persistence": 0.55,
			"lacunarity": 2.1,
			"ridged_power": 1.0,
			"warp_strength": 0.6,
		},
		"biome_params": {
			"moisture_frequency": 0.6,
			"moisture_octaves": 3,
			"latitude_bias": 0.3,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.2, 0.4, 0.55)},
			{"altitude": 0.4, "color": Color(0.35, 0.55, 0.7)},
			{"altitude": 0.7, "color": Color(0.55, 0.75, 0.85)},
			{"altitude": 1.0, "color": Color(0.75, 0.9, 0.95)},
		],
		"sea_level": 0.0,
		"has_solid_surface": false,
	}

func _preset_radiotrophic_bio() -> Dictionary:
	return {
		"elevation_params": {
			"frequency": 1.6,
			"octaves": 6,
			"persistence": 0.5,
			"lacunarity": 2.2,
			"ridged_power": 2.3,
			"warp_strength": 0.35,
		},
		"biome_params": {
			"moisture_frequency": 1.1,
			"moisture_octaves": 4,
			"latitude_bias": 0.4,
		},
		"color_ramp": [
			{"altitude": 0.0, "color": Color(0.05, 0.15, 0.1)},
			{"altitude": 0.3, "color": Color(0.1, 0.3, 0.15)},
			{"altitude": 0.6, "color": Color(0.2, 0.6, 0.3)},
			{"altitude": 0.85, "color": Color(0.45, 0.9, 0.5)},
			{"altitude": 1.0, "color": Color(0.7, 1.0, 0.8)},
		],
		"sea_level": 0.15,
		"has_solid_surface": true,
	}
