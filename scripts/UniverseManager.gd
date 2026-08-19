# res://scripts/UniverseManager.gd
# ==============================================================================
# BioGenesis-X: Universe & Dynamic Star System Streaming Manager
# ==============================================================================
# Controls procedural galaxy generation, local star system instantiation,
# host star illumination, planetary orbits, and interstellar hyper-jumps.
# ==============================================================================

@tool
class_name UniverseManager
extends Node3D

const ProceduralGalaxyClass = preload("res://scripts/ProceduralGalaxy.gd")
const ProceduralPlanetClass = preload("res://scripts/ProceduralPlanet.gd")
const HostStarCoronaShader = preload("res://shaders/host_star_corona.gdshader")

signal system_loaded(system_data: Dictionary)
signal hyperjump_started(target_system_name: String)
signal hyperjump_completed(new_system_data: Dictionary)

@export var galactic_coordinates_ly: Vector3 = Vector3(0.0, 15.0, 26000.0) # Sol Sector
@export var current_system_seed: int = 0x50756D69 ^ 1337
@export var auto_spawn_on_ready: bool = true

# Current active star system data
var current_system_data: Dictionary = {}
var host_star_node: Node3D = null
var planets_container: Node3D = null

func _ready() -> void:
	# Route system_loaded to the PlanetEntryManager autoload so it knows the
	# star type and planet positions whenever a new system is instantiated.
	if not Engine.is_editor_hint():
		if not system_loaded.is_connected(_on_system_loaded_for_planet_entry):
			system_loaded.connect(_on_system_loaded_for_planet_entry)
	if auto_spawn_on_ready:
		load_star_system_by_seed(current_system_seed)

## Forwards freshly-loaded star system data to the PlanetEntryManager autoload
## so the descent coordinator is aware of the active star type and planet layout.
func _on_system_loaded_for_planet_entry(system_data: Dictionary) -> void:
	if Engine.is_editor_hint():
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var entry_mgr: Node = tree.root.get_node_or_null("/root/PlanetEntryManager")
	if entry_mgr != null and entry_mgr.has_method("set_current_system"):
		entry_mgr.call("set_current_system", system_data)

## Loads and instantiates a complete star system from its deterministic seed.
func load_star_system_by_seed(seed_val: int) -> void:
	current_system_seed = seed_val
	current_system_data = ProceduralGalaxyClass.generate_star_system(current_system_seed, galactic_coordinates_ly)
	
	_clear_current_system()
	_instantiate_host_star()
	_instantiate_planets()
	
	system_loaded.emit(current_system_data)

## Returns true if a star system has been loaded and is ready.
func is_system_loaded() -> bool:
	return current_system_data.size() > 0

## Clears previous celestial bodies.
func _clear_current_system() -> void:
	if host_star_node and is_instance_valid(host_star_node):
		host_star_node.queue_free()
		host_star_node = null

	if planets_container and is_instance_valid(planets_container):
		planets_container.queue_free()
		planets_container = null

## Spawns the central stellar host star with PBR emissive corona and directional sunlight.
func _instantiate_host_star() -> void:
	host_star_node = Node3D.new()
	host_star_node.name = "HostStar_" + current_system_data.get("name", "Star")
	add_child(host_star_node)
	
	# Host Star Position: At the system origin — planets orbit the star, not empty space
	host_star_node.position = Vector3.ZERO

	var star_col: Color = current_system_data.get("star_color", Color(1.0, 0.9, 0.6))

	# 1. Emissive Star Core Sphere Mesh — scaled relative to real stellar radius
	# Visual scale: real stellar radii range from 12km (neutron star) to 8,500,000km (O-class hypergiant)
	# Map to game space: 800m to 12000m radius (15x max, so gas giants at 6500m are still smaller than most stars)
	var star_rad_norm := clampf(current_system_data.get("radius_km", 696340.0) / 8500000.0, 0.001, 1.0)
	var star_visual_radius := 800.0 + star_rad_norm * 11200.0

	var star_mesh_inst := MeshInstance3D.new()
	star_mesh_inst.name = "StarSphere"
	host_star_node.add_child(star_mesh_inst)

	var s_mesh := SphereMesh.new()
	s_mesh.radius = star_visual_radius
	s_mesh.height = star_visual_radius * 2.0
	s_mesh.radial_segments = 64
	s_mesh.rings = 32
	star_mesh_inst.mesh = s_mesh

	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = star_col
	star_mat.emission_enabled = true
	star_mat.emission = star_col
	star_mat.emission_energy_multiplier = 5.0
	star_mesh_inst.material_override = star_mat

	# 2. Dynamic Noise-Driven Photospheric Solar Corona Shell (1.2x core radius)
	var corona_mesh_inst := MeshInstance3D.new()
	corona_mesh_inst.name = "StarCoronaShell"
	host_star_node.add_child(corona_mesh_inst)

	var corona_radius := star_visual_radius * 1.2
	var c_mesh := SphereMesh.new()
	c_mesh.radius = corona_radius
	c_mesh.height = corona_radius * 2.0
	c_mesh.radial_segments = 64
	c_mesh.rings = 32
	corona_mesh_inst.mesh = c_mesh

	var corona_mat := ShaderMaterial.new()
	corona_mat.shader = HostStarCoronaShader
	corona_mat.set_shader_parameter("star_core_color", star_col)
	corona_mat.set_shader_parameter("star_corona_color", Color(star_col.r, star_col.g * 0.6, star_col.b * 0.2))
	corona_mesh_inst.material_override = corona_mat

	# 3. Main System Directional Sun Light — star is at origin, light radiates outward
	# Use a fixed offset position for the directional light to give consistent lighting direction
	var sun_light := DirectionalLight3D.new()
	sun_light.name = "SystemSunLight"
	sun_light.light_color = star_col
	sun_light.light_energy = 2.0
	sun_light.shadow_enabled = true
	# Directional light looks from a position toward origin — since star is at origin,
	# offset the light to illuminate from the star's "surface" outward
	sun_light.look_at_from_position(Vector3(0.0, star_visual_radius * 0.5, star_visual_radius), Vector3.ZERO, Vector3.UP)
	host_star_node.add_child(sun_light)

	# 4. Omni-Light Point Fill — centered on the star at origin
	var omni := OmniLight3D.new()
	omni.name = "StarOmniFill"
	omni.light_color = star_col
	omni.light_energy = 3.0
	omni.omni_range = 500000.0
	omni.omni_attenuation = 1.0
	host_star_node.add_child(omni)

## Spawns procedural planets in orbital resonance.
func _instantiate_planets() -> void:
	planets_container = Node3D.new()
	planets_container.name = "PlanetaryBodies"
	add_child(planets_container)

	var planet_list: Array = current_system_data.get("planets", [])
	
	# Scale planetary distances appropriately for authentic celestial exploration
	for p_data in planet_list:
		var planet_node := ProceduralPlanetClass.new()
		planet_node.name = "Planet_" + str(p_data.get("name", "Unknown")).replace(" ", "_")
		planets_container.add_child(planet_node)

		planet_node.planet_name = p_data.get("name", "Planet")
		planet_node.archetype = p_data.get("archetype", 3)
		
		# Realistic Astronomical Properties
		planet_node.real_radius_km = p_data.get("radius_km", 6371.0)
		planet_node.real_mass_earth = p_data.get("mass_earth", 1.0)
		planet_node.surface_gravity_g = p_data.get("surface_gravity_g", 1.0)
		planet_node.surface_gravity_ms2 = p_data.get("surface_gravity_ms2", 9.81)
		planet_node.surface_temp_k = p_data.get("surface_temp_k", 288.0)
		planet_node.surface_pressure_bar = p_data.get("surface_pressure_bar", 1.0)
		planet_node.real_orbit_au = p_data.get("orbit_au", 1.0)
		planet_node.real_orbit_km = p_data.get("orbit_km", 149597870.7)
		planet_node.orbital_period_days = p_data.get("orbital_period_days", 365.25)
		planet_node.escape_velocity_kms = p_data.get("escape_velocity_kms", 11.2)
		
		# REAL-SCALE CELESTIAL BODIES — use actual astronomical radii in meters.
		# Earth: 6,371km → 6,371,000m. Jupiter: 69,911km → 69,911,000m.
		# Floating-origin physics keeps the ship near the origin to avoid
		# float32 precision breakdown at these distances.
		var real_rad_km := planet_node.real_radius_km
		planet_node.radius_m = maxf(real_rad_km * 1000.0, 100000.0) # min 100km radius

		var p_idx: int = p_data.get("index", 0)
		# REAL-SCALE ORBITAL DISTANCES — 1.0 AU = 149,597,870,700 meters (true AU).
		# The wave-warp drive handles interplanetary travel at 0.01c-0.1c.
		# Normal Newtonian flight is for in-system maneuvering and combat.
		var orbit_au: float = p_data.get("orbit_au", 1.0)
		var sim_au_scale_m: float = 149597870700.0 # 1 AU in meters (true astronomical unit)
		planet_node.semi_major_axis_m = orbit_au * sim_au_scale_m
		planet_node.orbit_distance_m = planet_node.semi_major_axis_m
		
		planet_node.eccentricity = clampf(p_data.get("eccentricity", 0.03), 0.0, 0.22)
		planet_node.inclination_deg = p_data.get("inclination_deg", 2.0)
		planet_node.longitude_ascending_node_deg = p_data.get("longitude_ascending_node_deg", 0.0)
		planet_node.argument_periapsis_deg = p_data.get("argument_periapsis_deg", 0.0)
		planet_node.mean_anomaly_epoch_rad = p_data.get("mean_anomaly_epoch_rad", float(p_idx) * 1.618)
		planet_node.axial_tilt_deg = p_data.get("axial_tilt_deg", 23.4)
		planet_node.sidereal_rotation_period_hours = p_data.get("sidereal_rotation_period_hours", 24.0)
		planet_node.moon_data_list = p_data.get("moons", [])
		
		planet_node.has_rings = p_data.get("has_rings", false)
		planet_node.ring_inner_radius_m = planet_node.radius_m * 1.35
		planet_node.ring_outer_radius_m = planet_node.radius_m * 2.25

		planet_node.surface_primary_color = p_data.get("surface_color", Color(0.2, 0.6, 0.8))
		planet_node.surface_secondary_color = Color(
			planet_node.surface_primary_color.g,
			planet_node.surface_primary_color.b,
			planet_node.surface_primary_color.r
		)
		planet_node.add_to_group("celestial_bodies")
		planet_node.add_to_group("targets")
		planet_node._ready()

## Initiates an interstellar hyperjump to a target star system.
func hyperjump_to_system(target_system_seed: int) -> void:
	var target_data := ProceduralGalaxyClass.generate_star_system(target_system_seed, galactic_coordinates_ly)
	hyperjump_started.emit(target_data.get("name", "Hyperjump Target"))

	# Audio Telemetry: Interstellar Jump Acoustic Boom
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_interstellar_jump()
	
	# Load new system
	load_star_system_by_seed(target_system_seed)
	hyperjump_completed.emit(current_system_data)

## Scans the surrounding galactic volume for nearby star systems within a given light-year radius.
func get_nearby_systems(radius_ly: float = 80.0) -> Array[Dictionary]:
	var nearby: Array[Dictionary] = []
	var sec_r := int(ceil(radius_ly / ProceduralGalaxyClass.SECTOR_SIZE_LY))
	
	var cur_sec_x := int(floor(galactic_coordinates_ly.x / ProceduralGalaxyClass.SECTOR_SIZE_LY))
	var cur_sec_y := int(floor(galactic_coordinates_ly.y / ProceduralGalaxyClass.SECTOR_SIZE_LY))
	var cur_sec_z := int(floor(galactic_coordinates_ly.z / ProceduralGalaxyClass.SECTOR_SIZE_LY))

	for dz in range(-sec_r, sec_r + 1):
		for dy in range(-sec_r, sec_r + 1):
			for dx in range(-sec_r, sec_r + 1):
				var systems := ProceduralGalaxyClass.get_systems_in_sector(cur_sec_x + dx, cur_sec_y + dy, cur_sec_z + dz)
				for sys in systems:
					var dist := galactic_coordinates_ly.distance_to(sys.get("galactic_position_ly", Vector3.ZERO))
					if dist <= radius_ly:
						sys["distance_from_vessel_ly"] = dist
						nearby.append(sys)

	# Sort by distance
	nearby.sort_custom(func(a, b): return a.get("distance_from_vessel_ly", 0.0) < b.get("distance_from_vessel_ly", 0.0))
	return nearby
