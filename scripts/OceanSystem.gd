# ==============================================================================
# OceanSystem.gd - BioGenesis-X Planetary Ocean & Underwater Post-Process Manager
# Pumilio Studios & Ciel Aerospace Physics Division
# ==============================================================================
# Manages the large follow-plane ocean surface (Gerstner-wave shader) and the
# full-screen underwater post-processing CanvasLayer (depth fog, caustics,
# bioluminescence, pressure vignette). Drives per-archetype water palettes and
# 5 depth layers (SURFACE, SHALLOW, MID, DEEP, ABYSS) with floating-origin
# follow of the player camera.
#
# SHADERS DRIVEN:
#   res://shaders/ocean_surface.gdshader    (spatial, MeshInstance3D plane)
#   res://shaders/underwater_post.gdshader  (canvas_item, ColorRect overlay)
#
# PRESSURE MODEL:
#   P = P0 + rho * g * h   (P0 = 1.013 bar, rho = 1025 kg/m^3 seawater,
#    g = 9.80665 m/s^2). At 1000 m -> ~101 bar. Emits pressure_warning > 50 bar.
#
# ARCHETYPE SUPPORT:
#   3 TERRAN_OCEANIC    - Earth-like blue water, clear visibility
#   4 ICE_WORLD         - Dark cold water, ice particles, high clarity
#   7 RADIOTROPHIC_BIO  - Bioluminescent green/teal, spore particles
#   0 MOLTEN            - Lava surface, no diving (underwater post disabled)
#   Others              - No water (system deactivates gracefully)
# ==============================================================================
class_name OceanSystem
extends Node3D

# ------------------------------------------------------------------------------
# Ocean Depth Layers
# ------------------------------------------------------------------------------
## Ordered depth bands below the ocean surface. SURFACE is at/above the wave
## plane; ABYSS is beyond the deep_max threshold (default 1000 m).
enum OceanLayer {
	SURFACE, ## 0: At or above the wave plane (camera not yet submerged).
	SHALLOW, ## 1: 0-30 m, bright clear water, strong caustics.
	MID,     ## 2: 30-200 m, moderate light, blue-green.
	DEEP,    ## 3: 200-1000 m, dim, bioluminescence begins.
	ABYSS,   ## 4: 1000 m+, near black, heavy pressure vignette.
}

# ------------------------------------------------------------------------------
# Planet Archetype (mirrors ProceduralPlanet / AtmosphericFlightModel values)
# ------------------------------------------------------------------------------
enum PlanetArchetype {
	MOLTEN,           ## 0
	METALLIC_BARREN,  ## 1
	DESERT_ARID,      ## 2
	TERRAN_OCEANIC,   ## 3
	ICE_WORLD,        ## 4
	GAS_GIANT_JOVIAN, ## 5
	GAS_GIANT_ICE,    ## 6
	RADIOTROPHIC_BIO, ## 7
}

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal entered_water(depth_m: float)
signal exited_water()
signal layer_changed(old_layer: int, new_layer: int)
signal pressure_warning(pressure_bar: float)

# ------------------------------------------------------------------------------
# Physical Constants (SI Units)
# ------------------------------------------------------------------------------
## Standard atmospheric pressure at sea level (bar).
const SURFACE_PRESSURE_BAR: float = 1.013
## Seawater density (kg/m^3) used for hydrostatic pressure.
const SEAWATER_DENSITY: float = 1025.0
## Standard gravitational acceleration (m/s^2).
const STANDARD_GRAVITY: float = 9.80665
## Pressure (bar) above which pressure_warning is emitted.
const PRESSURE_WARNING_THRESHOLD_BAR: float = 50.0
## Conversion from Pascals to bar.
const PA_TO_BAR: float = 1.0e-4

# ------------------------------------------------------------------------------
# Shader Resource Paths
# ------------------------------------------------------------------------------
const OCEAN_SURFACE_SHADER_PATH: String = "res://shaders/ocean_surface.gdshader"
const UNDERWATER_POST_SHADER_PATH: String = "res://shaders/underwater_post.gdshader"

# ------------------------------------------------------------------------------
# Exported Tunables
# ------------------------------------------------------------------------------
@export_group("Surface Follow")
## Side length of the ocean follow-plane (metres). Large to hide the horizon edge.
@export var ocean_plane_size: float = 4000.0
## Subdivision of the follow-plane mesh (higher = smoother Gerstner displacement).
@export var ocean_plane_subdiv: int = 96
## Horizontal offset smoothing for floating-origin follow (1.0 = instant).
@export var follow_lerp_rate: float = 6.0

@export_group("Depth Thresholds (m)")
@export var shallow_max_m: float = 30.0
@export var mid_max_m: float = 200.0
@export var deep_max_m: float = 1000.0

@export_group("Weather")
## Normalized wind direction in the ocean local frame.
@export var wind_direction: Vector2 = Vector2(1.0, 0.0)
## Wind strength (0-15), drives Gerstner wave amplitude.
@export var wind_strength: float = 4.0
## Day-night blend (0 = full day, 1 = full night) for bioluminescence.
@export var night_factor: float = 0.0

@export_group("Time Of Day")
## Sun direction (normalized) in world space.
@export var sun_direction: Vector3 = Vector3(0.35, 0.85, 0.4)
## Sun color (linear, source_color).
@export var sun_color: Color = Color(1.0, 0.95, 0.82, 1.0)

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _ocean_active: bool = false
var _underwater: bool = false
var _current_layer: int = OceanLayer.SURFACE
var _planet_archetype: int = PlanetArchetype.TERRAN_OCEANIC
var _water_depth_m: float = 4000.0  ## Sea floor depth (m), drives water_depth uniform.
var _player_depth_m: float = 0.0    ## Player camera depth below surface (m).
var _elapsed_time: float = 0.0
var _last_pressure_warning_bar: float = 0.0
var _has_water: bool = true  ## False for archetypes with no ocean (graceful no-op).

# Node references
var _ocean_mesh: MeshInstance3D = null
var _ocean_material: ShaderMaterial = null
var _underwater_canvas: CanvasLayer = null
var _underwater_rect: ColorRect = null
var _underwater_material: ShaderMaterial = null
var _camera: Camera3D = null

# ------------------------------------------------------------------------------
# Per-Archetype Water Palette
# ------------------------------------------------------------------------------
class WaterProfile:
	var shallow_color: Color = Color(0.18, 0.78, 0.72, 1.0)
	var deep_color: Color = Color(0.01, 0.06, 0.22, 1.0)
	var foam_color: Color = Color(0.92, 0.97, 1.0, 1.0)
	var biome_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
	var fog_color: Color = Color(0.02, 0.18, 0.32, 1.0)
	var fog_density: float = 0.04
	var caustic_scale: float = 4.0
	var bioluminescence_intensity: float = 1.4
	var distortion_amount: float = 0.0025
	var wave_scale: float = 1.0
	var wave_speed: float = 1.0
	var choppiness: float = 0.65
	var is_lava: bool = false
	var has_water: bool = true

# ------------------------------------------------------------------------------
# Godot Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	_build_ocean_surface()
	_build_underwater_overlay()
	_apply_archetype_profile(_planet_archetype)
	# Start inactive until a planet with water is set.
	set_ocean_active(false)


func _process(delta: float) -> void:
	_elapsed_time += delta
	if not _ocean_active:
		return

	_update_camera_reference()
	_update_player_depth()
	_follow_player_horizontal(delta)
	_push_surface_uniforms()
	_push_underwater_uniforms()
	_evaluate_pressure_warning()


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------
## Activate or deactivate the ocean system (surface mesh + post overlay).
func set_ocean_active(active: bool) -> void:
	if active and not _has_water:
		# Archetype has no ocean - refuse gracefully.
		_ocean_active = false
		_set_surface_visible(false)
		_set_underwater_overlay_visible(false)
		return
	_ocean_active = active
	_set_surface_visible(active)
	# Underwater overlay visibility is driven by is_underwater() state, not active.
	if not active:
		_set_underwater_overlay_visible(false)
		if _underwater:
			_underwater = false
			exited_water.emit()


## Set the sea-floor depth (m) used for the water_depth uniform.
func set_water_depth(depth_m: float) -> void:
	_water_depth_m = clampf(depth_m, 0.0, 6000.0)


## Force the current ocean layer (clamped to OceanLayer enum range).
func set_ocean_layer(layer: int) -> void:
	var clamped: int = clampi(layer, OceanLayer.SURFACE, OceanLayer.ABYSS)
	if clamped == _current_layer:
		return
	var old: int = _current_layer
	_current_layer = clamped
	layer_changed.emit(old, _current_layer)


## Set the planet archetype and reconfigure water palette + availability.
func set_planet_archetype(archetype: int) -> void:
	_planet_archetype = clampi(archetype, 0, 7)
	_apply_archetype_profile(_planet_archetype)


## Returns the current OceanLayer the player is in.
func get_current_layer() -> int:
	return _current_layer


## Returns true when the player camera is below the ocean surface.
func is_underwater() -> bool:
	return _underwater


## Compute hydrostatic pressure (bar) at the current player depth.
func get_pressure_bar() -> float:
	var p_pa: float = SEAWATER_DENSITY * STANDARD_GRAVITY * _player_depth_m
	return SURFACE_PRESSURE_BAR + p_pa * PA_TO_BAR


# ------------------------------------------------------------------------------
# Construction
# ------------------------------------------------------------------------------
func _build_ocean_surface() -> void:
	_ocean_mesh = MeshInstance3D.new()
	_ocean_mesh.name = "OceanSurface"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(ocean_plane_size, ocean_plane_size)
	plane.subdivide_width = ocean_plane_subdiv
	plane.subdivide_depth = ocean_plane_subdiv
	plane.material = _create_surface_material()
	_ocean_mesh.mesh = plane
	_ocean_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ocean_mesh.visibility_range_end = ocean_plane_size * 1.5
	add_child(_ocean_mesh)
	_ocean_material = _ocean_mesh.get_active_material(0) as ShaderMaterial


func _create_surface_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = load(OCEAN_SURFACE_SHADER_PATH)
	if shader != null:
		mat.shader = shader
	return mat


func _build_underwater_overlay() -> void:
	_underwater_canvas = CanvasLayer.new()
	_underwater_canvas.name = "UnderwaterPost"
	_underwater_canvas.layer = 100
	add_child(_underwater_canvas)

	_underwater_rect = ColorRect.new()
	_underwater_rect.name = "UnderwaterRect"
	_underwater_rect.anchors_preset = Control.PRESET_FULL_RECT
	_underwater_rect.anchor_right = 1.0
	_underwater_rect.anchor_left = 0.0
	_underwater_rect.anchor_top = 0.0
	_underwater_rect.anchor_bottom = 1.0
	_underwater_rect.offset_right = 0.0
	_underwater_rect.offset_left = 0.0
	_underwater_rect.offset_top = 0.0
	_underwater_rect.offset_bottom = 0.0
	_underwater_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underwater_rect.material = _create_underwater_material()
	_underwater_canvas.add_child(_underwater_rect)
	_underwater_material = _underwater_rect.material as ShaderMaterial
	_set_underwater_overlay_visible(false)


func _create_underwater_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = load(UNDERWATER_POST_SHADER_PATH)
	if shader != null:
		mat.shader = shader
	return mat


# ------------------------------------------------------------------------------
# Archetype Profiles
# ------------------------------------------------------------------------------
func _apply_archetype_profile(archetype: int) -> void:
	var profile: WaterProfile = _get_archetype_profile(archetype)
	_has_water = profile.has_water
	if not _has_water:
		set_ocean_active(false)
		return

	if _ocean_material != null:
		_ocean_material.set_shader_parameter("water_color_shallow", profile.shallow_color)
		_ocean_material.set_shader_parameter("water_color_deep", profile.deep_color)
		_ocean_material.set_shader_parameter("foam_color", profile.foam_color)
		_ocean_material.set_shader_parameter("biome_tint", profile.biome_tint)
		_ocean_material.set_shader_parameter("wave_scale", profile.wave_scale)
		_ocean_material.set_shader_parameter("wave_speed", profile.wave_speed)
		_ocean_material.set_shader_parameter("choppiness", profile.choppiness)

	if _underwater_material != null:
		_underwater_material.set_shader_parameter("fog_color", profile.fog_color)
		_underwater_material.set_shader_parameter("fog_density", profile.fog_density)
		_underwater_material.set_shader_parameter("caustic_scale", profile.caustic_scale)
		_underwater_material.set_shader_parameter("bioluminescence_intensity", profile.bioluminescence_intensity)
		_underwater_material.set_shader_parameter("distortion_amount", profile.distortion_amount)
		_underwater_material.set_shader_parameter("shallow_max", shallow_max_m)
		_underwater_material.set_shader_parameter("mid_max", mid_max_m)
		_underwater_material.set_shader_parameter("deep_max", deep_max_m)


func _get_archetype_profile(archetype: int) -> WaterProfile:
	var p: WaterProfile = WaterProfile.new()
	match archetype:
		PlanetArchetype.TERRAN_OCEANIC:
			p.shallow_color = Color(0.18, 0.78, 0.72, 1.0)
			p.deep_color = Color(0.01, 0.06, 0.22, 1.0)
			p.foam_color = Color(0.92, 0.97, 1.0, 1.0)
			p.biome_tint = Color(1.0, 1.0, 1.0, 1.0)
			p.fog_color = Color(0.02, 0.18, 0.32, 1.0)
			p.fog_density = 0.04
			p.caustic_scale = 4.0
			p.bioluminescence_intensity = 1.4
			p.distortion_amount = 0.0025
			p.wave_scale = 1.0
			p.wave_speed = 1.0
			p.choppiness = 0.65
			p.is_lava = false
			p.has_water = true
		PlanetArchetype.ICE_WORLD:
			p.shallow_color = Color(0.45, 0.62, 0.78, 1.0)
			p.deep_color = Color(0.02, 0.08, 0.18, 1.0)
			p.foam_color = Color(0.88, 0.95, 1.0, 1.0)
			p.biome_tint = Color(0.85, 0.95, 1.05, 1.0)
			p.fog_color = Color(0.05, 0.22, 0.35, 1.0)
			p.fog_density = 0.018  # high clarity
			p.caustic_scale = 5.0
			p.bioluminescence_intensity = 0.4
			p.distortion_amount = 0.0015
			p.wave_scale = 0.7
			p.wave_speed = 0.6
			p.choppiness = 0.45
			p.is_lava = false
			p.has_water = true
		PlanetArchetype.RADIOTROPHIC_BIO:
			p.shallow_color = Color(0.22, 0.85, 0.55, 1.0)
			p.deep_color = Color(0.01, 0.12, 0.08, 1.0)
			p.foam_color = Color(0.6, 1.0, 0.7, 1.0)
			p.biome_tint = Color(0.7, 1.2, 0.85, 1.0)
			p.fog_color = Color(0.04, 0.22, 0.16, 1.0)
			p.fog_density = 0.06
			p.caustic_scale = 3.5
			p.bioluminescence_intensity = 3.2  # spore particles, strong glow
			p.distortion_amount = 0.0035
			p.wave_scale = 1.1
			p.wave_speed = 1.2
			p.choppiness = 0.7
			p.is_lava = false
			p.has_water = true
		PlanetArchetype.MOLTEN:
			# Lava instead of water - molten surface, no diving.
			p.shallow_color = Color(1.0, 0.35, 0.05, 1.0)
			p.deep_color = Color(0.35, 0.04, 0.0, 1.0)
			p.foam_color = Color(1.0, 0.6, 0.15, 1.0)
			p.biome_tint = Color(1.1, 0.6, 0.2, 1.0)
			p.fog_color = Color(0.4, 0.08, 0.02, 1.0)
			p.fog_density = 0.0
			p.caustic_scale = 1.0
			p.bioluminescence_intensity = 0.0
			p.distortion_amount = 0.0
			p.wave_scale = 0.4
			p.wave_speed = 0.3
			p.choppiness = 0.3
			p.is_lava = true
			p.has_water = true  # surface renders, but diving is blocked.
		_:
			# No water for barren / desert / gas giant archetypes.
			p.has_water = false
	return p


# ------------------------------------------------------------------------------
# Per-Frame Updates
# ------------------------------------------------------------------------------
func _update_camera_reference() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	_camera = get_viewport().get_camera_3d()


func _update_player_depth() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	# Ocean surface sits at this node's global Y (origin). Player depth is the
	# vertical distance below that plane.
	var surface_y: float = global_position.y
	var cam_y: float = _camera.global_position.y
	var depth: float = surface_y - cam_y

	var was_underwater: bool = _underwater
	if _planet_archetype == PlanetArchetype.MOLTEN:
		# Lava: no diving allowed. Never go underwater.
		_underwater = false
		_player_depth_m = 0.0
	else:
		_underwater = depth > 0.0
		_player_depth_m = maxf(depth, 0.0)

	if _underwater != was_underwater:
		if _underwater:
			entered_water.emit(_player_depth_m)
		else:
			exited_water.emit()
		_set_underwater_overlay_visible(_underwater and not (_planet_archetype == PlanetArchetype.MOLTEN))

	# Recompute layer from depth.
	_recompute_layer()


func _recompute_layer() -> void:
	var new_layer: int = OceanLayer.SURFACE
	if _underwater:
		if _player_depth_m < shallow_max_m:
			new_layer = OceanLayer.SHALLOW
		elif _player_depth_m < mid_max_m:
			new_layer = OceanLayer.MID
		elif _player_depth_m < deep_max_m:
			new_layer = OceanLayer.DEEP
		else:
			new_layer = OceanLayer.ABYSS
	if new_layer != _current_layer:
		var old: int = _current_layer
		_current_layer = new_layer
		layer_changed.emit(old, _current_layer)


func _follow_player_horizontal(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _ocean_mesh == null or not is_instance_valid(_ocean_mesh):
		return
	var target_x: float = _camera.global_position.x
	var target_z: float = _camera.global_position.z
	var current_pos: Vector3 = _ocean_mesh.global_position
	var rate: float = 1.0 - exp(-follow_lerp_rate * delta)
	var new_x: float = lerpf(current_pos.x, target_x, rate)
	var new_z: float = lerpf(current_pos.z, target_z, rate)
	# Keep the surface at this OceanSystem's origin Y (floating origin).
	_ocean_mesh.global_position = Vector3(new_x, global_position.y, new_z)


func _push_surface_uniforms() -> void:
	if _ocean_material == null:
		return
	_ocean_material.set_shader_parameter("time", _elapsed_time)
	_ocean_material.set_shader_parameter("wind_direction", wind_direction)
	_ocean_material.set_shader_parameter("wind_strength", wind_strength)
	_ocean_material.set_shader_parameter("sun_direction", sun_direction)
	_ocean_material.set_shader_parameter("sun_color", sun_color)
	_ocean_material.set_shader_parameter("night_factor", night_factor)
	if _camera != null and is_instance_valid(_camera):
		_ocean_material.set_shader_parameter("camera_position", _camera.global_position)


func _push_underwater_uniforms() -> void:
	if _underwater_material == null:
		return
	_underwater_material.set_shader_parameter("time", _elapsed_time)
	_underwater_material.set_shader_parameter("water_depth", _water_depth_m)
	_underwater_material.set_shader_parameter("camera_depth", _player_depth_m)
	# Pressure intensity ramps with depth, saturating near deep_max.
	var pressure_norm: float = clampf(_player_depth_m / deep_max_m, 0.0, 2.0)
	_underwater_material.set_shader_parameter("pressure_intensity", pressure_norm)


func _evaluate_pressure_warning() -> void:
	if not _underwater:
		_last_pressure_warning_bar = 0.0
		return
	var pressure_bar: float = get_pressure_bar()
	if pressure_bar > PRESSURE_WARNING_THRESHOLD_BAR and pressure_bar > _last_pressure_warning_bar + 1.0:
		_last_pressure_warning_bar = pressure_bar
		pressure_warning.emit(pressure_bar)


# ------------------------------------------------------------------------------
# Visibility Helpers
# ------------------------------------------------------------------------------
func _set_surface_visible(p_visible: bool) -> void:
	if _ocean_mesh != null and is_instance_valid(_ocean_mesh):
		_ocean_mesh.visible = p_visible


func _set_underwater_overlay_visible(p_visible: bool) -> void:
	if _underwater_rect != null and is_instance_valid(_underwater_rect):
		_underwater_rect.visible = p_visible
