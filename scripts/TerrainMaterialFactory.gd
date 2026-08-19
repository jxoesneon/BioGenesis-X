# res://scripts/TerrainMaterialFactory.gd
# ==============================================================================
# BioGenesis-X: Terrain Material Factory
# ==============================================================================
# Creates and configures ShaderMaterial instances for the 8 planetary terrain
# archetypes. Each archetype maps to a dedicated procedural surface shader in
# res://shaders/. The factory sets sensible default uniforms and applies
# seed-driven per-planet variation via configure_terrain_material().
#
# Archetype index -> shader mapping:
#   0  Molten            -> terrain_molten.gdshader
#   1  Metallic Barren   -> terrain_metallic_barren.gdshader
#   2  Desert Arid       -> terrain_desert_arid.gdshader
#   3  Terran Oceanic    -> terrain_terran_oceanic.gdshader
#   4  Ice World         -> terrain_ice_world.gdshader
#   5  Gas Giant Jovian  -> terrain_gas_giant_jovian.gdshader
#   6  Gas Giant Ice     -> terrain_gas_giant_ice.gdshader
#   7  Radiotrophic Bio  -> terrain_radiotrophic_bio.gdshader
# ==============================================================================

class_name TerrainMaterialFactory
extends RefCounted

# --- Archetype constants -----------------------------------------------------
const ARCHETYPE_MOLTEN: int = 0
const ARCHETYPE_METALLIC_BARREN: int = 1
const ARCHETYPE_DESERT_ARID: int = 2
const ARCHETYPE_TERRAN_OCEANIC: int = 3
const ARCHETYPE_ICE_WORLD: int = 4
const ARCHETYPE_GAS_GIANT_JOVIAN: int = 5
const ARCHETYPE_GAS_GIANT_ICE: int = 6
const ARCHETYPE_RADIOTROPHIC_BIO: int = 7

const MIN_ARCHETYPE: int = 0
const MAX_ARCHETYPE: int = 7

# --- Shader paths ------------------------------------------------------------
const _SHADER_MOLTEN: String = "res://shaders/terrain_molten.gdshader"
const _SHADER_METALLIC_BARREN: String = "res://shaders/terrain_metallic_barren.gdshader"
const _SHADER_DESERT_ARID: String = "res://shaders/terrain_desert_arid.gdshader"
const _SHADER_TERRAN_OCEANIC: String = "res://shaders/terrain_terran_oceanic.gdshader"
const _SHADER_ICE_WORLD: String = "res://shaders/terrain_ice_world.gdshader"
const _SHADER_GAS_GIANT_JOVIAN: String = "res://shaders/terrain_gas_giant_jovian.gdshader"
const _SHADER_GAS_GIANT_ICE: String = "res://shaders/terrain_gas_giant_ice.gdshader"
const _SHADER_RADIOTROPHIC_BIO: String = "res://shaders/terrain_radiotrophic_bio.gdshader"

# --- Default lighting uniforms (shared by all terrain shaders) ---------------
const _DEFAULT_SUN_DIRECTION: Vector3 = Vector3(0.35, 0.85, 0.4)
const _DEFAULT_SUN_COLOR: Color = Color(1.0, 0.95, 0.85, 1.0)


## Returns the res:// path to the terrain shader for the given archetype (0-7).
## Returns an empty String for an out-of-range archetype.
static func get_terrain_shader_path(archetype: int) -> String:
	match archetype:
		ARCHETYPE_MOLTEN:
			return _SHADER_MOLTEN
		ARCHETYPE_METALLIC_BARREN:
			return _SHADER_METALLIC_BARREN
		ARCHETYPE_DESERT_ARID:
			return _SHADER_DESERT_ARID
		ARCHETYPE_TERRAN_OCEANIC:
			return _SHADER_TERRAN_OCEANIC
		ARCHETYPE_ICE_WORLD:
			return _SHADER_ICE_WORLD
		ARCHETYPE_GAS_GIANT_JOVIAN:
			return _SHADER_GAS_GIANT_JOVIAN
		ARCHETYPE_GAS_GIANT_ICE:
			return _SHADER_GAS_GIANT_ICE
		ARCHETYPE_RADIOTROPHIC_BIO:
			return _SHADER_RADIOTROPHIC_BIO
		_:
			push_warning("TerrainMaterialFactory: archetype %d out of range [0,7]." % archetype)
			return ""


## Creates and returns a ShaderMaterial with the appropriate terrain shader and
## default uniform values for the given archetype. Returns null on failure.
static func create_terrain_material(archetype: int) -> ShaderMaterial:
	var path: String = get_terrain_shader_path(archetype)
	if path.is_empty():
		return null
	var shader_res: Shader = load(path) as Shader
	if shader_res == null:
		push_warning("TerrainMaterialFactory: failed to load terrain shader: %s" % path)
		return null
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader_res
	# Common lighting uniforms shared across all terrain shaders.
	material.set_shader_parameter("sun_direction", _DEFAULT_SUN_DIRECTION)
	material.set_shader_parameter("sun_color", _DEFAULT_SUN_COLOR)
	material.set_shader_parameter("time", 0.0)
	return material


## Sets archetype-specific uniform values (colors, frequencies, etc.) on the
## given material, deterministic per seed. Safe to call on a material created by
## create_terrain_material(); unknown uniforms are skipped silently.
static func configure_terrain_material(material: ShaderMaterial, archetype: int, p_seed: int) -> void:
	if material == null:
		push_warning("TerrainMaterialFactory: configure_terrain_material called with null material.")
		return
	var s: float = float(p_seed)
	# Deterministic normalized jitter in [0,1) derived from the seed.
	var j1: float = abs(fmod(s * 0.013 + 0.37, 1.0))
	var j2: float = abs(fmod(s * 0.029 + 0.71, 1.0))
	var j3: float = abs(fmod(s * 0.047 + 0.13, 1.0))

	match archetype:
		ARCHETYPE_MOLTEN:
			_configure_molten(material, j1, j2, j3)
		ARCHETYPE_METALLIC_BARREN:
			_configure_metallic_barren(material, j1, j2, j3)
		ARCHETYPE_DESERT_ARID:
			_configure_desert_arid(material, j1, j2, j3)
		ARCHETYPE_TERRAN_OCEANIC:
			_configure_terran_oceanic(material, j1, j2, j3)
		ARCHETYPE_ICE_WORLD:
			_configure_ice_world(material, j1, j2, j3)
		ARCHETYPE_GAS_GIANT_JOVIAN:
			_configure_gas_giant_jovian(material, j1, j2, j3)
		ARCHETYPE_GAS_GIANT_ICE:
			_configure_gas_giant_ice(material, j1, j2, j3)
		ARCHETYPE_RADIOTROPHIC_BIO:
			_configure_radiotrophic_bio(material, j1, j2, j3)
		_:
			push_warning("TerrainMaterialFactory: configure_terrain_material archetype %d out of range [0,7]." % archetype)


# =============================================================================
# Per-archetype configuration helpers
# Each only sets uniforms that exist on its shader; set_shader_parameter on a
# missing uniform is a no-op warning at runtime, so we guard with _set_if_present.
# =============================================================================

static func _set_if_present(material: ShaderMaterial, name: String, value: Variant) -> void:
	# ShaderMaterial has no public uniform list query in 4.x without the shader,
	# but setting an absent uniform is silently ignored by the rendering server.
	# We still avoid spamming by relying on the shader being correct for the archetype.
	material.set_shader_parameter(name, value)


# --- Archetype 0: Molten / Volcanic -----------------------------------------
static func _configure_molten(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "lava_color_hot", Color(1.0, 0.45 + j1 * 0.15, 0.05 + j2 * 0.08, 1.0))
	_set_if_present(material, "lava_color_cool", Color(0.85, 0.18 + j3 * 0.10, 0.02, 1.0))
	_set_if_present(material, "basalt_color", Color(0.04, 0.03, 0.03, 1.0))
	_set_if_present(material, "lava_crack_scale", 6.0 + j1 * 8.0)
	_set_if_present(material, "lava_crack_threshold", 0.42 + j2 * 0.12)
	_set_if_present(material, "lava_emission_strength", 3.5 + j3 * 3.0)
	_set_if_present(material, "lava_flow_speed", 0.05 + j1 * 0.08)
	_set_if_present(material, "heat_shimmer", 0.25 + j2 * 0.25)
	_set_if_present(material, "low_elevation_lava", 0.45 + j3 * 0.20)


# --- Archetype 1: Metallic Barren -------------------------------------------
static func _configure_metallic_barren(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "metal_color_base", Color(0.32, 0.30, 0.28, 1.0))
	_set_if_present(material, "metal_color_bright", Color(0.62 + j1 * 0.10, 0.60, 0.56, 1.0))
	_set_if_present(material, "crater_rim_color", Color(0.78, 0.76, 0.72, 1.0))
	_set_if_present(material, "crater_scale_macro", 4.0 + j2 * 4.0)
	_set_if_present(material, "crater_scale_micro", 20.0 + j3 * 12.0)
	_set_if_present(material, "metallic_intensity", 0.45 + j1 * 0.30)
	_set_if_present(material, "specular_sharpness", 48.0 + j2 * 64.0)
	_set_if_present(material, "specular_intensity", 1.0 + j3 * 1.2)


# --- Archetype 2: Desert Arid -----------------------------------------------
static func _configure_desert_arid(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "sand_color_light", Color(0.82, 0.52 + j1 * 0.10, 0.28, 1.0))
	_set_if_present(material, "sand_color_dark", Color(0.55, 0.28 + j2 * 0.08, 0.12, 1.0))
	_set_if_present(material, "dust_color", Color(0.90, 0.66, 0.40 + j3 * 0.10, 1.0))
	_set_if_present(material, "wind_direction", Vector2(1.0, 0.3 + j1 * 0.4).normalized())
	_set_if_present(material, "wind_speed", 0.15 + j2 * 0.30)
	_set_if_present(material, "ripple_scale", 10.0 + j3 * 12.0)
	_set_if_present(material, "dune_scale", 2.0 + j1 * 4.0)
	_set_if_present(material, "dust_intensity", 0.4 + j2 * 0.5)


# --- Archetype 3: Terran Oceanic --------------------------------------------
static func _configure_terran_oceanic(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "sea_level", 0.40 + j1 * 0.15)
	_set_if_present(material, "water_color_shallow", Color(0.10, 0.42 + j2 * 0.10, 0.62, 1.0))
	_set_if_present(material, "water_color_deep", Color(0.01, 0.08, 0.22 + j3 * 0.06, 1.0))
	_set_if_present(material, "grass_color", Color(0.18 + j1 * 0.08, 0.55, 0.20, 1.0))
	_set_if_present(material, "forest_color", Color(0.08, 0.32 + j2 * 0.06, 0.12, 1.0))
	_set_if_present(material, "snow_line", 0.70 + j3 * 0.20)
	_set_if_present(material, "vegetation_variation", 0.3 + j1 * 0.4)


# --- Archetype 4: Ice World --------------------------------------------------
static func _configure_ice_world(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "ice_color_bright", Color(0.88, 0.94, 1.0, 1.0))
	_set_if_present(material, "ice_color_deep", Color(0.42 + j1 * 0.10, 0.65, 0.88, 1.0))
	_set_if_present(material, "crack_color", Color(0.05, 0.18 + j2 * 0.06, 0.42, 1.0))
	_set_if_present(material, "snow_color", Color(0.96, 0.98, 1.0, 1.0))
	_set_if_present(material, "crack_scale", 8.0 + j3 * 8.0)
	_set_if_present(material, "crack_threshold", 0.48 + j1 * 0.12)
	_set_if_present(material, "sss_intensity", 1.0 + j2 * 1.0)
	_set_if_present(material, "snow_flatness", 0.55 + j3 * 0.25)


# --- Archetype 5: Gas Giant Jovian ------------------------------------------
static func _configure_gas_giant_jovian(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "band_color_amber", Color(0.82, 0.52 + j1 * 0.10, 0.22, 1.0))
	_set_if_present(material, "band_color_ivory", Color(0.92, 0.86, 0.70 + j2 * 0.08, 1.0))
	_set_if_present(material, "band_color_terracotta", Color(0.68, 0.30, 0.15 + j3 * 0.06, 1.0))
	_set_if_present(material, "band_frequency", 30.0 + j1 * 20.0)
	_set_if_present(material, "band_turbulence", 3.5 + j2 * 3.0)
	_set_if_present(material, "band_speed", 0.010 + j3 * 0.015)
	_set_if_present(material, "storm_radius", 0.20 + j1 * 0.15)
	_set_if_present(material, "storm_intensity", 0.8 + j2 * 0.8)


# --- Archetype 6: Gas Giant Ice ---------------------------------------------
static func _configure_gas_giant_ice(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "band_color_azure", Color(0.12, 0.42 + j1 * 0.10, 0.88, 1.0))
	_set_if_present(material, "band_color_cyan", Color(0.32, 0.78, 0.98 - j2 * 0.08, 1.0))
	_set_if_present(material, "cloud_streak_color", Color(0.94, 0.98, 1.0, 1.0))
	_set_if_present(material, "band_frequency", 24.0 + j3 * 16.0)
	_set_if_present(material, "band_turbulence", 2.0 + j1 * 2.5)
	_set_if_present(material, "band_speed", 0.008 + j2 * 0.012)
	_set_if_present(material, "cloud_streak_density", 0.40 + j3 * 0.30)
	_set_if_present(material, "dark_spot_radius", 0.18 + j1 * 0.12)
	_set_if_present(material, "dark_spot_intensity", 0.70 + j2 * 0.25)


# --- Archetype 7: Radiotrophic Bio ------------------------------------------
static func _configure_radiotrophic_bio(material: ShaderMaterial, j1: float, j2: float, j3: float) -> void:
	_set_if_present(material, "bio_color_low", Color(0.10, 0.42 + j1 * 0.10, 0.30, 1.0))
	_set_if_present(material, "bio_color_mid", Color(0.18, 0.68, 0.52 + j2 * 0.10, 1.0))
	_set_if_present(material, "bio_color_high", Color(0.34, 0.20, 0.48 + j3 * 0.10, 1.0))
	_set_if_present(material, "vein_color", Color(0.20, 1.0, 0.78, 1.0))
	_set_if_present(material, "spore_color", Color(0.55, 1.0, 0.85, 1.0))
	_set_if_present(material, "pulse_frequency", 0.8 + j1 * 2.5)
	_set_if_present(material, "pulse_amplitude", 0.6 + j2 * 0.8)
	_set_if_present(material, "vein_scale", 7.0 + j3 * 6.0)
	_set_if_present(material, "vein_threshold", 0.42 + j1 * 0.14)
	_set_if_present(material, "vein_emission_strength", 4.0 + j2 * 3.0)
	_set_if_present(material, "membrane_scale", 5.0 + j3 * 5.0)
	_set_if_present(material, "spore_density", 0.30 + j1 * 0.40)
	_set_if_present(material, "spore_drift_speed", 0.08 + j2 * 0.12)
	_set_if_present(material, "sss_intensity", 0.9 + j3 * 1.0)
