# res://scripts/ProceduralPlanet.gd
# ==============================================================================
# BioGenesis-X: Procedural Celestial Planet & Keplerian Orbital Dynamics Engine
# ==============================================================================
# Solves Kepler's Equation (M = E - e*sin(E)) via Newton-Raphson iteration,
# calculates 3D orbital state vectors with true anomaly, eccentricity,
# orbital inclination, argument of periapsis, and axial obliquity tilt.
# ==============================================================================

@tool
class_name ProceduralPlanet
extends Node3D

const PlanetShaderResource = preload("res://shaders/procedural_planet.gdshader")
const AtmosphereShaderResource = preload("res://shaders/atmosphere_scattering.gdshader")
# Extremely Fast Atmosphere addon (fbcosentino screen-space scattering).
# Pre-baked ShaderMaterial with all height/direction profile curves + gradient
# textures. Duplicated per-planet so each gets its own sea_level / radius.
const FarAtmosphereMaterialResource = preload("res://addons/extremely_fast_atmosphere/example/atmosphere_material_example.tres")

@export var planet_name: String = "Terran Prime"
@export var archetype: int = 3 # 3: Terran Oceanic
@export var radius_m: float = 120.0
@export var orbit_distance_m: float = 850.0
@export var has_rings: bool = false
@export var ring_inner_radius_m: float = 180.0
@export var ring_outer_radius_m: float = 320.0
@export var surface_primary_color: Color = Color(0.12, 0.45, 0.75)
@export var surface_secondary_color: Color = Color(0.18, 0.65, 0.32)
@export var atmosphere_color: Color = Color(0.25, 0.65, 1.0)

# ------------------------------------------------------------------------------
# Keplerian Orbital Elements (Celestial Mechanics)
# ------------------------------------------------------------------------------
@export_group("Keplerian Orbital Elements")
@export var semi_major_axis_m: float = 850.0
@export var eccentricity: float = 0.035
@export var inclination_deg: float = 2.5
@export var longitude_ascending_node_deg: float = 45.0
@export var argument_periapsis_deg: float = 30.0
@export var mean_anomaly_epoch_rad: float = 0.0
@export var axial_tilt_deg: float = 23.44
@export var orbital_period_days: float = 365.25
@export var sidereal_rotation_period_hours: float = 24.0
@export var orbital_time_scale: float = 1.0 ## Realistic 1:1 astronomical time scale (1.0 = real-time, can be scaled smoothly)
@export var visual_axial_spin_speed: float = 0.004 ## Majestic visual planetary day/night rotation rate (rad/s)

# ------------------------------------------------------------------------------
# Real Astronomical Dimensions (SI Units)
# ------------------------------------------------------------------------------
@export_group("Real Astronomical Dimensions")
@export var real_radius_km: float = 6371.0
@export var real_mass_earth: float = 1.0
@export var surface_gravity_g: float = 1.0
@export var surface_gravity_ms2: float = 9.81
@export var surface_temp_k: float = 288.0
@export var surface_pressure_bar: float = 1.0
@export var real_orbit_au: float = 1.0
@export var real_orbit_km: float = 149597870.7
@export var escape_velocity_kms: float = 11.2

# Moons Data
var moon_data_list: Array = []
var moon_nodes: Array[Node3D] = []

# Node components
var body_tilt_node: Node3D
var planet_mesh_instance: MeshInstance3D
var ring_mesh_instance: MeshInstance3D
var orbit_line_instance: MeshInstance3D
var moons_container: Node3D
# Physical atmosphere scattering mesh (Sean O'Neil Rayleigh + Mie).
var _atmosphere_mesh_instance: MeshInstance3D = null
var _atmosphere_material: ShaderMaterial = null
# Far-field atmosphere mesh (Extremely Fast Atmosphere addon — screen-space
# scattering seen from space). Complements the near-field O'Neil sphere which
# takes over once the camera descends into the atmosphere / onto the surface.
var _far_atmosphere_mesh_instance: MeshInstance3D = null
var _far_atmosphere_material: ShaderMaterial = null
var _atmosphere_outer_radius_m: float = 0.0
# Sun direction for atmosphere scattering (updated by the star system manager).
var _sun_direction: Vector3 = Vector3(0.0, 0.0, 1.0)

var elapsed_simulation_seconds: float = 0.0

# ------------------------------------------------------------------------------
# Planet LOD (Level of Detail) — manual 3-level mesh swap + engine LOD bias.
# Reduces GPU vertex cost when rendering many planets simultaneously.
# ------------------------------------------------------------------------------
var _mesh_ultra: SphereMesh = null
var _mesh_high: SphereMesh = null
var _mesh_medium: SphereMesh = null
var _mesh_low: SphereMesh = null
var _force_high_detail: bool = false
var _lod_update_counter: int = 0
const _LOD_UPDATE_INTERVAL: int = 30
# Real-scale: planets are AU-distance apart. Cull at 50 AU (Pluto-distance).
const _VISIBILITY_RANGE_END_M: float = 7500000000000.0 # ~50 AU

func _ready() -> void:
	if semi_major_axis_m <= 0.0:
		semi_major_axis_m = orbit_distance_m

	_setup_hierarchical_nodes()
	_generate_planet_body()
	_generate_atmosphere_scattering()
	if has_rings:
		_generate_planetary_rings()
	_generate_orbit_trajectory_line()
	_spawn_hierarchical_moons()

	# Compute and set initial epoch position immediately
	position = compute_keplerian_position(0.0)

func _setup_hierarchical_nodes() -> void:
	# Clean up previous children
	for c in get_children():
		c.queue_free()

	# Body tilt container (Applies planetary obliquity / axial tilt)
	body_tilt_node = Node3D.new()
	body_tilt_node.name = "AxialTiltNode"
	body_tilt_node.rotation_degrees = Vector3(axial_tilt_deg, 0.0, 0.0)
	add_child(body_tilt_node)

	moons_container = Node3D.new()
	moons_container.name = "MoonsContainer"
	add_child(moons_container)

func _process(delta: float) -> void:
	elapsed_simulation_seconds += delta * orbital_time_scale

	# 1. Solve Keplerian Orbital Position around Host Star
	var current_pos := compute_keplerian_position(elapsed_simulation_seconds)
	position = current_pos

	# 2. Majestic Axial Sidereal Day/Night Rotation
	var spin_rate := visual_axial_spin_speed * (24.0 / maxf(1.0, sidereal_rotation_period_hours))
	if planet_mesh_instance:
		planet_mesh_instance.rotate_y(spin_rate * delta)

	if ring_mesh_instance:
		ring_mesh_instance.rotate_y(spin_rate * delta * 0.85)

	# 3. Update Hierarchical Moons in Hill Sphere
	_update_moons(elapsed_simulation_seconds)

	# 4. Throttled manual LOD mesh swap (every 30 frames to reduce CPU cost).
	if not _force_high_detail:
		_lod_update_counter += 1
		if _lod_update_counter >= _LOD_UPDATE_INTERVAL:
			_lod_update_counter = 0
			_update_lod()

	# 5. Update atmosphere scattering uniforms (camera position + sun direction).
	_update_atmosphere_uniforms()

## Solves Kepler's Equation M = E - e*sin(E) for Eccentric Anomaly using Newton-Raphson iteration.
static func solve_kepler_eccentric_anomaly(mean_anomaly: float, ecc: float) -> float:
	var M := fmod(mean_anomaly, TAU)
	if M < 0.0:
		M += TAU

	var E := M if ecc < 0.8 else PI
	var max_iterations := 8
	var tolerance := 1e-6

	for i in range(max_iterations):
		var delta_e := (E - ecc * sin(E) - M) / (1.0 - ecc * cos(E))
		E -= delta_e
		if abs(delta_e) < tolerance:
			break

	return E

## Computes instantaneous 3D Cartesian coordinates in system space via Keplerian orbital state vectors.
func compute_keplerian_position(sim_time_sec: float) -> Vector3:
	var period_sec := maxf(1.0, orbital_period_days * 86400.0)
	var mean_motion := TAU / period_sec
	var mean_anomaly := mean_anomaly_epoch_rad + mean_motion * sim_time_sec

	# 1. Eccentric Anomaly E
	var E := solve_kepler_eccentric_anomaly(mean_anomaly, eccentricity)

	# 2. True Anomaly nu and Radial Distance r
	var sin_half_E := sin(E * 0.5)
	var cos_half_E := cos(E * 0.5)
	var nu := 2.0 * atan2(sqrt(1.0 + eccentricity) * sin_half_E, sqrt(1.0 - eccentricity) * cos_half_E)
	var r := semi_major_axis_m * (1.0 - eccentricity * cos(E))

	# 3. Coordinates in Orbital Plane (periapsis along +X, motion towards +Z)
	var x_orb := r * cos(nu)
	var z_orb := r * sin(nu)
	var pos_orb := Vector3(x_orb, 0.0, z_orb)

	# 4. Transform into 3D Heliocentric Reference Frame:
	# Apply Argument of Periapsis (w), Inclination (i), and Longitude of Ascending Node (Omega)
	var rad_w := deg_to_rad(argument_periapsis_deg)
	var rad_i := deg_to_rad(inclination_deg)
	var rad_node := deg_to_rad(longitude_ascending_node_deg)

	# Rotate by argument of periapsis around orbital normal (+Y)
	var pos_w := pos_orb.rotated(Vector3.UP, rad_w)
	# Rotate by inclination around X-axis
	var pos_i := pos_w.rotated(Vector3.RIGHT, rad_i)
	# Rotate by longitude of ascending node around system Y-axis
	var pos_helio := pos_i.rotated(Vector3.UP, rad_node)

	return pos_helio

## Constructs high-resolution 3D spherified mesh with PBR planetary shader.
func _generate_planet_body() -> void:
	planet_mesh_instance = MeshInstance3D.new()
	planet_mesh_instance.name = "PlanetSphereMesh"
	body_tilt_node.add_child(planet_mesh_instance)

	# --- 4-level adaptive LOD meshes (ULTRA / HIGH / MEDIUM / LOW) -----------
	# Real-scale planets need much higher mesh density when close to show
	# surface features. Distant planets use low-poly to save GPU.
	# The material is applied via material_override on the MeshInstance3D, so
	# swapping the mesh resource preserves the material automatically.
	_mesh_ultra = SphereMesh.new()
	_mesh_ultra.radius = radius_m
	_mesh_ultra.height = radius_m * 2.0
	_mesh_ultra.radial_segments = 256
	_mesh_ultra.rings = 128

	_mesh_high = SphereMesh.new()
	_mesh_high.radius = radius_m
	_mesh_high.height = radius_m * 2.0
	_mesh_high.radial_segments = 128
	_mesh_high.rings = 64

	_mesh_medium = SphereMesh.new()
	_mesh_medium.radius = radius_m
	_mesh_medium.height = radius_m * 2.0
	_mesh_medium.radial_segments = 48
	_mesh_medium.rings = 24

	_mesh_low = SphereMesh.new()
	_mesh_low.radius = radius_m
	_mesh_low.height = radius_m * 2.0
	_mesh_low.radial_segments = 24
	_mesh_low.rings = 12

	planet_mesh_instance.mesh = _mesh_high  # Start at HIGH; LOD system upgrades to ULTRA when close

	# LOD bias for Godot's auto-generated screen-size LODs.
	planet_mesh_instance.lod_bias = 0.5
	# Cull distant planets — real-scale orbit distances are huge (AU-scale).
	# Use a generous cull distance so planets remain visible across the system.
	planet_mesh_instance.visibility_range_end = _VISIBILITY_RANGE_END_M
	planet_mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	var mat := ShaderMaterial.new()
	mat.shader = PlanetShaderResource
	mat.set_shader_parameter("planet_archetype", archetype)
	mat.set_shader_parameter("primary_surface_color", surface_primary_color)
	mat.set_shader_parameter("secondary_surface_color", surface_secondary_color)
	mat.set_shader_parameter("atmosphere_glow_color", atmosphere_color)
	# Vertex displacement uniforms (real-scale planets).
	mat.set_shader_parameter("planet_radius_m", radius_m)
	# Displacement amplitude: 2% of radius for rocky planets, 0.5% for gas giants.
	if archetype == 5 or archetype == 6:
		mat.set_shader_parameter("displacement_amplitude", 0.005)
	else:
		mat.set_shader_parameter("displacement_amplitude", 0.02)
	mat.set_shader_parameter("displacement_frequency", 2.5)
	mat.set_shader_parameter("displacement_octaves", 5)

	if archetype == 5: # Jovian Gas Giant
		mat.set_shader_parameter("atmosphere_thickness", 2.2)
		mat.set_shader_parameter("cloud_density", 0.0)
	elif archetype == 6: # Ice Giant
		mat.set_shader_parameter("atmosphere_thickness", 1.8)
	elif archetype == 0: # Molten
		mat.set_shader_parameter("atmosphere_thickness", 0.6)
		mat.set_shader_parameter("cloud_density", 0.3)
	elif archetype == 1: # Metallic Barren
		mat.set_shader_parameter("atmosphere_thickness", 0.0)
		mat.set_shader_parameter("cloud_density", 0.0)
	elif archetype == 4: # Ice World
		mat.set_shader_parameter("atmosphere_thickness", 0.4)
		mat.set_shader_parameter("cloud_density", 0.25)
	elif archetype == 7: # Radiotrophic Bio
		mat.set_shader_parameter("atmosphere_thickness", 2.0)
		mat.set_shader_parameter("cloud_density", 0.65)
		mat.set_shader_parameter("cloud_color", Color(0.1, 0.9, 0.7, 1.0))

	planet_mesh_instance.material_override = mat

	# --- Collision body so ships and characters collide with the planet surface ---
	var collision_body: StaticBody3D = StaticBody3D.new()
	collision_body.name = "PlanetCollisionBody"
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "PlanetCollisionShape"
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = radius_m
	collision_shape.shape = sphere_shape
	collision_body.add_child(collision_shape)
	body_tilt_node.add_child(collision_body)

## Generates a physical atmosphere scattering sphere using Sean O'Neil's
## Rayleigh + Mie technique. Superior to the simple Fresnel limb glow in the
## planet shader because it models wavelength-dependent scattering, optical
## depth, and ray marching through the atmosphere volume.
## Ported from the Procedural Planet Chunked LOD asset's atmosphere.gdshader.
func _generate_atmosphere_scattering() -> void:
	# Atmosphere height: scale by archetype (gas giants have huge atmospheres).
	var atm_height_m: float = radius_m * 0.15
	if archetype == 5 or archetype == 6: # Gas giants
		atm_height_m = radius_m * 0.5
	elif archetype == 1: # Barren — negligible atmosphere
		atm_height_m = radius_m * 0.02
	elif archetype == 0: # Molten — thick toxic atmosphere
		atm_height_m = radius_m * 0.25

	var outer_radius_m: float = radius_m + atm_height_m

	_atmosphere_mesh_instance = MeshInstance3D.new()
	_atmosphere_mesh_instance.name = "AtmosphereScattering"
	var sphere := SphereMesh.new()
	sphere.radius = outer_radius_m
	sphere.height = outer_radius_m * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_atmosphere_mesh_instance.mesh = sphere
	# Disable Godot's built-in culling — atmosphere should always render when
	# the planet is visible (the sphere is much larger than the planet body).
	_atmosphere_mesh_instance.visibility_range_end = _VISIBILITY_RANGE_END_M
	_atmosphere_mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	_atmosphere_material = ShaderMaterial.new()
	_atmosphere_material.shader = AtmosphereShaderResource
	_atmosphere_material.set_shader_parameter("inner_radius", radius_m)
	_atmosphere_material.set_shader_parameter("outer_radius", outer_radius_m)
	_atmosphere_material.set_shader_parameter("atm_scale", 1.0 / atm_height_m)
	_atmosphere_material.set_shader_parameter("sun_direction", _sun_direction)
	_atmosphere_material.set_shader_parameter("atmosphere_archetype", archetype)
	_atmosphere_material.set_shader_parameter("atmosphere_tint", atmosphere_color)
	_atmosphere_material.set_shader_parameter("camera_pos", Vector3.ZERO)
	_atmosphere_material.set_shader_parameter("camera_height", radius_m * 5.0)

	# Per-archetype scattering parameters
	if archetype == 1: # Barren — almost no atmosphere
		_atmosphere_material.set_shader_parameter("kr", 0.0005)
		_atmosphere_material.set_shader_parameter("km", 0.0002)
		_atmosphere_material.set_shader_parameter("sun_intensity", 5.0)
		_atmosphere_material.set_shader_parameter("tint_strength", 0.1)
	elif archetype == 5: # Jovian — thick amber atmosphere
		_atmosphere_material.set_shader_parameter("kr", 0.006)
		_atmosphere_material.set_shader_parameter("km", 0.002)
		_atmosphere_material.set_shader_parameter("sun_intensity", 25.0)
		_atmosphere_material.set_shader_parameter("tint_strength", 0.5)
	elif archetype == 6: # Ice Giant — methane blue
		_atmosphere_material.set_shader_parameter("kr", 0.005)
		_atmosphere_material.set_shader_parameter("km", 0.0015)
		_atmosphere_material.set_shader_parameter("sun_intensity", 22.0)
		_atmosphere_material.set_shader_parameter("tint_strength", 0.5)
	elif archetype == 7: # Radiotrophic — greenish organic
		_atmosphere_material.set_shader_parameter("kr", 0.005)
		_atmosphere_material.set_shader_parameter("km", 0.002)
		_atmosphere_material.set_shader_parameter("sun_intensity", 18.0)
		_atmosphere_material.set_shader_parameter("tint_strength", 0.4)

	_atmosphere_mesh_instance.material_override = _atmosphere_material
	body_tilt_node.add_child(_atmosphere_mesh_instance)

	# Far-field atmosphere (Extremely Fast Atmosphere addon) — screen-space
	# scattering visible from space. Complements the near-field O'Neil sphere.
	_atmosphere_outer_radius_m = outer_radius_m
	_generate_far_atmosphere(outer_radius_m)

## Generates the far-field atmosphere using the "Extremely Fast Atmosphere" addon
## (fbcosentino screen-space scattering). This is the atmosphere seen from space
## when approaching a planet — it complements the Sean O'Neil Rayleigh+Mie
## near-field scattering sphere (_atmosphere_mesh_instance) which takes over
## once the camera descends into the atmosphere / onto the surface.
func _generate_far_atmosphere(outer_radius_m: float) -> void:
	_far_atmosphere_mesh_instance = MeshInstance3D.new()
	_far_atmosphere_mesh_instance.name = "FarAtmosphereEFA"
	var box := BoxMesh.new()
	box.flip_faces = true
	box.size = Vector3.ONE * (2.1 * outer_radius_m)
	_far_atmosphere_mesh_instance.mesh = box
	# Disable Godot's built-in culling — the atmosphere box is much larger than
	# the planet body and should always render when the planet is visible.
	_far_atmosphere_mesh_instance.visibility_range_end = _VISIBILITY_RANGE_END_M
	_far_atmosphere_mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	# Start from the addon's pre-baked material (height/direction profile curves
	# + gradient textures) and duplicate it so each planet owns its own copy.
	var base_mat: ShaderMaterial = FarAtmosphereMaterialResource
	_far_atmosphere_material = base_mat.duplicate() as ShaderMaterial
	_far_atmosphere_material.set_shader_parameter("sea_level", radius_m)
	_far_atmosphere_material.set_shader_parameter("atmosphere_radius", outer_radius_m)
	_far_atmosphere_material.set_shader_parameter("atmosphere_density", 0.2)
	_far_atmosphere_material.set_shader_parameter("water_density_factor", 0.0)
	_far_atmosphere_mesh_instance.material_override = _far_atmosphere_material
	body_tilt_node.add_child(_far_atmosphere_mesh_instance)

## Updates the far-field Extremely Fast Atmosphere each frame: toggles visibility
## based on camera distance (only visible from outside the atmosphere) and
## orients the box mesh toward the sun so the scattering direction is correct.
func _update_far_atmosphere(cam_dist: float) -> void:
	if not is_instance_valid(_far_atmosphere_mesh_instance):
		return
	# The EFA shader is a screen-space overlay best viewed from outside the
	# atmosphere. Once the camera descends below the atmosphere edge, hide it
	# and let the near-field O'Neil scattering sphere handle the sky.
	var show_far: bool = cam_dist > _atmosphere_outer_radius_m * 1.02
	_far_atmosphere_mesh_instance.visible = show_far
	if not show_far:
		return
	# Orient the box mesh so its basis matches the addon's atmosphere.gd
	# set_sun_position convention: look_at(self - delta_pos) where delta_pos is
	# the sun-relative offset. This aligns the shader's light_direction varying.
	var self_pos: Vector3 = _far_atmosphere_mesh_instance.global_position
	var sun_world: Vector3 = self_pos + _sun_direction * 1.0e9
	var delta_pos: Vector3 = sun_world - self_pos
	_far_atmosphere_mesh_instance.look_at(self_pos - delta_pos)

## Updates the atmosphere scattering uniforms each frame. Call from _process
## after computing the planet position. The camera position is transformed to
## planet-local space for the shader.
func _update_atmosphere_uniforms() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var cam: Camera3D = viewport.get_camera_3d()
	if cam == null:
		return
	# Camera position in planet-local space (relative to planet center).
	var cam_local: Vector3 = to_local(cam.global_position)
	var cam_dist: float = cam_local.length()
	# Near-field Sean O'Neil atmosphere (Rayleigh + Mie).
	if _atmosphere_material != null and is_instance_valid(_atmosphere_mesh_instance):
		_atmosphere_material.set_shader_parameter("camera_pos", cam_local)
		_atmosphere_material.set_shader_parameter("camera_height", cam_dist)
		_atmosphere_material.set_shader_parameter("sun_direction", _sun_direction)
	# Far-field Extremely Fast Atmosphere (screen-space, seen from space).
	_update_far_atmosphere(cam_dist)

## Sets the sun direction for atmosphere scattering. Called by the star system
## manager or any script that knows the star's position.
func set_sun_direction(direction: Vector3) -> void:
	_sun_direction = direction.normalized()
	if _atmosphere_material != null:
		_atmosphere_material.set_shader_parameter("sun_direction", _sun_direction)

## Returns the atmosphere scattering mesh instance (or null if not created).
func get_atmosphere_mesh() -> MeshInstance3D:
	return _atmosphere_mesh_instance

## Generates 3D procedural equatorial planetary ring disk.
func _generate_planetary_rings() -> void:
	ring_mesh_instance = MeshInstance3D.new()
	ring_mesh_instance.name = "PlanetaryRingMesh"
	body_tilt_node.add_child(ring_mesh_instance)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 64
	for i in range(segments):
		var theta1 := (float(i) / float(segments)) * TAU
		var theta2 := (float(i + 1) / float(segments)) * TAU

		var inner_p1 := Vector3(cos(theta1) * ring_inner_radius_m, 0.0, sin(theta1) * ring_inner_radius_m)
		var outer_p1 := Vector3(cos(theta1) * ring_outer_radius_m, 0.0, sin(theta1) * ring_outer_radius_m)
		var inner_p2 := Vector3(cos(theta2) * ring_inner_radius_m, 0.0, sin(theta2) * ring_inner_radius_m)
		var outer_p2 := Vector3(cos(theta2) * ring_outer_radius_m, 0.0, sin(theta2) * ring_outer_radius_m)

		var u1 := float(i) / float(segments)
		var u2 := float(i + 1) / float(segments)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u1))
		st.add_vertex(inner_p1)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u1))
		st.add_vertex(outer_p1)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u2))
		st.add_vertex(outer_p2)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u1))
		st.add_vertex(inner_p1)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, u2))
		st.add_vertex(outer_p2)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, u2))
		st.add_vertex(inner_p2)

	st.generate_tangents()
	ring_mesh_instance.mesh = st.commit()

	var ring_mat := StandardMaterial3D.new()
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(surface_primary_color.r * 0.9, surface_primary_color.g * 0.85, surface_primary_color.b * 0.8, 0.72)
	ring_mat.roughness = 0.85
	ring_mesh_instance.material_override = ring_mat

## Generates glowing Keplerian orbital path spline trajectory in space.
func _generate_orbit_trajectory_line() -> void:
	orbit_line_instance = MeshInstance3D.new()
	orbit_line_instance.name = "OrbitTrajectorySpline"
	orbit_line_instance.top_level = true # Anchored at system origin
	add_child(orbit_line_instance)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)

	var samples := 96
	for i in range(samples + 1):
		var fraction := float(i) / float(samples)
		var test_time := fraction * (orbital_period_days * 86400.0)
		var pt := compute_keplerian_position(test_time)
		st.set_color(Color(surface_primary_color.r, surface_primary_color.g, surface_primary_color.b, 0.35))
		st.add_vertex(pt)

	orbit_line_instance.mesh = st.commit()

	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(surface_primary_color.r, surface_primary_color.g, surface_primary_color.b, 0.28)
	orbit_line_instance.material_override = line_mat

## Spawns Keplerian natural satellites / moons in the planet's Hill sphere.
func _spawn_hierarchical_moons() -> void:
	moon_nodes.clear()
	for m_data in moon_data_list:
		var moon_node := Node3D.new()
		moon_node.name = "Moon_" + str(m_data.get("name", "Moon")).replace(" ", "_")
		moons_container.add_child(moon_node)

		var moon_mesh_inst := MeshInstance3D.new()
		moon_mesh_inst.name = "MoonMesh"
		moon_node.add_child(moon_mesh_inst)

		var m_rad_km: float = m_data.get("radius_km", 1000.0)
		var rad_norm := clampf(m_rad_km / 3000.0, 0.1, 0.5)
		var m_radius_m := radius_m * 0.18 * rad_norm

		var sm := SphereMesh.new()
		sm.radius = maxf(4.0, m_radius_m)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 32
		sm.rings = 16
		moon_mesh_inst.mesh = sm

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.75, 0.8) # Basalt lunar grey
		mat.roughness = 0.85
		moon_mesh_inst.material_override = mat

		moon_nodes.append(moon_node)

## Updates moon positions along their sub-Keplerian orbits.
func _update_moons(sim_time_sec: float) -> void:
	for i in range(moon_nodes.size()):
		var m_node := moon_nodes[i]
		if i < moon_data_list.size():
			var m_data = moon_data_list[i]
			var m_period_sec := maxf(1.0, m_data.get("orbital_period_days", 28.0) * 86400.0)
			# Use real moon orbit distance from galaxy data, scaled to game space.
			# Real moon orbits range from ~100,000km to ~1,500,000km.
			# Scale: divide by 100,000 to get game meters (1000-15000m from planet center).
			# Ensure minimum distance is planet radius * 2.5 so moon is outside the planet surface.
			var real_moon_orbit_km = m_data.get("orbit_km", radius_m * 100.0)
			var m_dist_m := maxf(radius_m * 2.5, real_moon_orbit_km / 100000.0 * 1000.0)
			var m_angle = (TAU / m_period_sec) * sim_time_sec + m_data.get("mean_anomaly_epoch_rad", 0.0)

			var m_inc_rad := deg_to_rad(m_data.get("inclination_deg", 2.0))
			m_node.position = Vector3(
				cos(m_angle) * m_dist_m,
				sin(m_angle) * (m_dist_m * sin(m_inc_rad)),
				sin(m_angle) * m_dist_m
			)

# ==============================================================================
# Planet LOD (Level of Detail)
# ==============================================================================

## Manual 3-level mesh swap based on camera distance. Swaps the mesh resource
## on the existing MeshInstance3D, preserving the material_override. Called
## every _LOD_UPDATE_INTERVAL frames from _process() to reduce CPU cost.
func _update_lod() -> void:
	if planet_mesh_instance == null or not is_instance_valid(planet_mesh_instance):
		return
	if _force_high_detail:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var cam: Camera3D = viewport.get_camera_3d()
	if cam == null:
		return
	var dist: float = global_position.distance_to(cam.global_position)
	# Real-scale LOD: use radius multiples for distance thresholds.
	# ULTRA: within 1.5x radius (close orbit / descent approach)
	# HIGH: within 5x radius (orbital view)
	# MEDIUM: within 20x radius (far orbital)
	# LOW: beyond 20x radius (distant)
	if dist < radius_m * 1.5:
		if planet_mesh_instance.mesh != _mesh_ultra:
			planet_mesh_instance.mesh = _mesh_ultra
	elif dist < radius_m * 5.0:
		if planet_mesh_instance.mesh != _mesh_high:
			planet_mesh_instance.mesh = _mesh_high
	elif dist < radius_m * 20.0:
		if planet_mesh_instance.mesh != _mesh_medium:
			planet_mesh_instance.mesh = _mesh_medium
	else:
		if planet_mesh_instance.mesh != _mesh_low:
			planet_mesh_instance.mesh = _mesh_low

## Forces HIGH detail on the planet (used by PlanetEntryManager when descent
## activates). Disables the visibility-range cull so the target planet is never
## hidden during descent, and restores aggressive LOD bias when released.
func set_high_detail(enabled: bool) -> void:
	_force_high_detail = enabled
	if planet_mesh_instance == null or not is_instance_valid(planet_mesh_instance):
		return
	if enabled:
		if _mesh_ultra != null:
			planet_mesh_instance.mesh = _mesh_ultra
		planet_mesh_instance.lod_bias = 1.0
		# Disable distance culling so the descent target stays visible.
		planet_mesh_instance.visibility_range_end = 0.0
	else:
		planet_mesh_instance.lod_bias = 0.3
		planet_mesh_instance.visibility_range_end = _VISIBILITY_RANGE_END_M
		# Re-evaluate the appropriate LOD level on the next throttled tick.
