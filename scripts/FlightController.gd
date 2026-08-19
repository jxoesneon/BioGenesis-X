@tool
class_name FlightController
extends CharacterBody3D

## FlightController.gd
## 6-DOF 3D Newtonian Space Flight Controller with Bio-Hydro Pulse Dampening
## Part of BioGenesis-X gameplay mechanics.

signal boost_state_changed(is_boosting: bool)
signal fuel_changed(current_fuel: float, max_fuel: float)
signal g_force_updated(g_force: float)
signal dampening_toggled(is_enabled: bool)
signal camera_mode_changed(new_mode: int)
signal wave_state_changed(new_state: int, charge_pct: float)
signal wave_arrival_eta_updated(eta_seconds: float, distance_m: float, target_name: String)
signal atmospheric_entry(layer: int)
signal heating_intensity_changed(intensity: float)
signal stall_warning(stall_factor: float)

enum CameraMode {
	FPV,   ## Command Center / Cranial Bridge First-Person View
	CHASE  ## External Tactical 3rd-Person Follow Camera
}

enum WaveState {
	OFF,         ## Standard sublight flight
	CHARGING,    ## Spool-up countdown (2.0s alignment phase)
	ENGAGED,     ## Alcubierre wave-ride supercruise (up to 38,000 m/s)
	DISENGAGING, ## Dropping back to sublight flight
	INHIBITED    ## Mass locked by dense obstacle
}

@export_group("Unified Vessel Mass & Inertia")
## Total physical mass of the single unified bio-ship in kilograms.
@export var vessel_mass_kg: float = 125000.0 ## 125 metric tons baseline
## Principal moments of inertia (Ix=Pitch, Iy=Yaw, Iz=Roll) in kg*m^2.
@export var moment_of_inertia: Vector3 = Vector3(450000.0, 520000.0, 220000.0)
@export var center_of_mass_offset: Vector3 = Vector3.ZERO

@export_group("Flight Physics (Forces & Torques)")
@export var forward_thrust_force: float = 7500000.0 ## 7.5 MN forward bio-plasma siphon force
@export var reverse_thrust_force: float = 4200000.0 ## 4.2 MN retro-thrust force
@export var strafe_thrust_force: float = 4800000.0  ## 4.8 MN lateral maneuvering force
@export var pitch_torque: float = 1200000.0         ## 1.2 MN*m pitch control torque
@export var yaw_torque: float = 1350000.0           ## 1.35 MN*m yaw control torque
@export var roll_torque: float = 850000.0           ## 0.85 MN*m roll control torque
@export var boost_multiplier: float = 2.2
@export var max_speed: float = 500000.0 ## 500 km/s — Newtonian combat & orbital maneuvering
@export var max_boost_speed: float = 2000000.0 ## 2,000 km/s — boost for combat / evasion

@export_group("Rotation & Sensitivity")
@export var mouse_sensitivity: float = 0.003
@export var mouse_control_enabled: bool = true

@export_group("No Man's Sky Flight Mechanics")
## Automatic banking / rolling into turns for intuitive aerodynamic starship handling
@export var auto_banking_enabled: bool = true
@export var auto_banking_strength: float = 0.65
@export var auto_level_speed: float = 2.6

## Starship Combat Auto-Follow (Holding RMB or Auto-Follow key tracks targeted enemy)
@export var combat_auto_follow_enabled: bool = true
@export var auto_follow_strength: float = 3.5
@export var auto_follow_cone_degrees: float = 55.0

@export_group("Bio-Hydro Pulse Dampening (Flight Assist)")
## Bio-hydro pulse dampener simulates intelligent counter-vector retro-thrust.
## When disabled (Flight Assist OFF), the ship preserves pure Newtonian drifting momentum in vacuum.
@export var dampening_enabled: bool = true
@export var linear_dampening_rate: float = 1.4
@export var angular_dampening_rate: float = 3.5

@export_group("Bio-Boost Plasma Reserve")
@export var max_bio_plasma_fuel: float = 100.0
@export var bio_plasma_fuel: float = 100.0
@export var boost_drain_rate: float = 25.0
@export var boost_recharge_rate: float = 12.0
@export var recharge_delay: float = 1.5

@export_group("Wave Engine (Alcubierre In-System Transit)")
## Alcubierre-style wave engine: contracts space ahead, expands space behind.
## The ship rides a spacetime wave inside a flat-region warp bubble.
@export var wave_engine_enabled: bool = true
@export var wave_charge_duration: float = 2.0 ## 2.0 second spool-up countdown
@export var wave_max_speed: float = 200000000000.0 ## 200M km/s (~668c) — Alcubierre warp: 1 AU in 0.8s, 50 AU in 41s, 400 AU in 5.5min
@export var wave_acceleration: float = 40000000000.0 ## 40M km/s^2 forward wave acceleration (reaches max in ~5s)
@export var wave_safe_disengage_distance: float = 5000000.0 ## 5,000km auto-drop proximity distance
@export var wave_fuel_cost_per_sec: float = 3.0 ## Bio-plasma consumption rate
@export var wave_fov: float = 108.0 ## Dynamic FOV expansion during wave cruise

@export_group("Atmospheric Flight (Aerodynamics)")
## Wing reference area (m^2) used to scale aerodynamic lift forces.
@export var wing_area: float = 15.0
## Cross-sectional reference area (m^2) used to scale aerodynamic drag forces.
@export var cross_section_area: float = 3.0
## User-tunable lift coefficient multiplier (scales the model's Cl).
@export var lift_coefficient: float = 1.2
## User-tunable drag coefficient multiplier (scales the model's Cd).
@export var drag_coefficient: float = 0.3

@export_group("Camera Follower & FPV")
@export var camera_mode: CameraMode = CameraMode.CHASE
@export var camera_node: Camera3D
@export var fpv_camera: Camera3D
@export var chase_camera: Camera3D
@export var camera_spring_arm: SpringArm3D
@export var base_fov: float = 80.0
@export var boost_fov: float = 98.0
@export var fov_lerp_speed: float = 5.0
@export var camera_shake_decay: float = 5.0
@export var max_camera_shake_offset: float = 0.25

# Internal Physics State
var linear_velocity_vector: Vector3 = Vector3.ZERO
var angular_velocity_vector: Vector3 = Vector3.ZERO
var accumulated_external_impulse: Vector3 = Vector3.ZERO
var accumulated_external_torque: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO
var current_g_force: float = 1.0 # 1G baseline
var is_boosting: bool = false
var recharge_timer: float = 0.0
var camera_shake_intensity: float = 0.0
var camera_shake_multiplier: float = 1.0  # Accessibility: scales shake (0=off, 1=full)
var invert_y: bool = false  # Accessibility: invert mouse Y axis
var hull_integrity: float = 100.0  # Hull health [0-100], drives audio DTI
## True once the Covenant of Symbiosis is sealed — set by CovenantController.
## Until bonded, the Leviathan is not yet the player's ship.
var is_bonded: bool = false
var bio_shield: float = 100.0  # Bio-shield energy [0-100], absorbs damage before hull
var bio_shield_max: float = 100.0
var bio_shield_regen_rate: float = 8.0  # Shield regen per second when not taking damage
var bio_shield_regen_delay: float = 3.0  # Seconds after damage before regen resumes
var bio_shield_regen_timer: float = 0.0  # Countdown to regen
var damage_flash_timer: float = 0.0  # Transient damage indicator
# Energy shield bubble visual (uses the nojoule energy-shield shader). Child of
# the ship body so it follows the vessel. Driven by bio_shield strength.
var _shield_visual: BioShieldVisual = null
# Bio-plasma fuel tank visual — a translucent caustic-fluid sphere mounted on
# the ship hull whose fill level (Y scale) tracks the bio_plasma_fuel reserve.
# Uses bio_caustic_fluid.gdshader. Null when the shader isn't available.
var _fuel_tank_visual: MeshInstance3D = null
var _fuel_tank_mat: ShaderMaterial = null
var _fuel_tank_base_scale: float = 1.0
var _last_fuel_ratio: float = -1.0  # Dirty flag for fuel tank visual updates
# Cached Juicee autoload reference (looked up dynamically so the script parses
# cleanly even when the Juicee singleton isn't registered, e.g. headless tests).
var _juicee_node: Node = null
signal shield_hit(absorbed: float, remaining: float)
signal hull_hit(damage: float, remaining: float)
signal ship_destroyed
var mouse_delta: Vector2 = Vector2.ZERO
var mouse_flight_cursor: Vector2 = Vector2.ZERO ## Normalized 2D tethered flight reticle offset [-1.0, 1.0]
var fpv_base_pos: Vector3 = Vector3(0.0, 0.65, 4.8) # Default cranial helm pilot eye position

# Wave Engine Runtime State
var wave_state: WaveState = WaveState.OFF
var wave_charge_timer: float = 0.0
var wave_current_speed: float = 0.0
var wave_target_node: Node3D = null
var wave_target_name: String = ""
var wave_eta_seconds: float = 0.0
var simulated_wave: bool = false
var wave_fx_node: Node3D = null ## WaveEngineFX visual plane child (spawned on engage)

# Simulated Inputs for AI / Playtesting
var simulated_pitch: float = 0.0
var simulated_yaw: float = 0.0
var simulated_roll: float = 0.0
var simulated_thrust: Vector3 = Vector3.ZERO
var simulated_boost: bool = false
var simulated_inputs_enabled: bool = false

# Reference to OrganTelemetry node if present
var organ_telemetry_node: Node = null

# Atmospheric Flight Integration
var _atmospheric_model: AtmosphericFlightModel = null
var _planet_descent_controller: Node = null ## PlanetDescentController instance (autoload or scene node)
var _current_atmosphere_layer: int = 0 ## AtmosphericFlightModel.Layer enum (0 = EXOSPHERE)
var _current_heating_intensity: float = 0.0
var _current_stall_factor: float = 0.0
var _altitude_above_surface: float = 0.0
var _nearest_planet_node: Node3D = null
var _nearest_planet_archetype: int = 0
var _nearest_planet_radius: float = 100.0

func _ready() -> void:
	add_to_group("flight_controller")
	add_to_group("player_ship")
	
	if Engine.is_editor_hint():
		return
		
	if get_tree().root.has_node("SaveSystem"):
		var save_sys := get_tree().root.get_node("SaveSystem")
		if save_sys.has_method("get_upgrade"):
			max_speed = save_sys.get_upgrade("max_speed", max_speed)
			forward_thrust_force = save_sys.get_upgrade("forward_thrust_force", forward_thrust_force)
	
	if mouse_control_enabled and not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	_init_vessel_physical_properties()
	_setup_camera()
	_find_organ_telemetry()
	_ensure_unified_collision()
	_setup_shield_visual()
	_setup_fuel_tank_visual()
	_init_atmospheric_integration()

## Calculates physical mass and principal moments of inertia for the entire ship as a single rigid body
func _init_vessel_physical_properties() -> void:
	var cfg := {}
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioManager"):
		var bm = ml.root.get_node("BioManager")
		if bm and bm.has_method("get_ship_config"):
			cfg = bm.get_ship_config()

	var ship_len: float = cfg.get("length", 28.0)
	var segs: int = cfg.get("segments", 16)
	var chitin_dens: float = cfg.get("chitin_density", 0.95)
	var armor_thick: float = cfg.get("armor_thickness", 4.5)
	var archetype_str: String = cfg.get("archetype", "apex_leviathan")

	var archetype_mass_mult := 1.0
	match archetype_str:
		"apex_leviathan": archetype_mass_mult = 1.8
		"neuro_interceptor": archetype_mass_mult = 0.65
		"void_harvester": archetype_mass_mult = 1.3
		"abyssal_frigate": archetype_mass_mult = 1.1
		"colony_carrier": archetype_mass_mult = 2.4

	# Calculate unified single-body vessel mass in kilograms
	var len_ratio := ship_len / 28.0
	var seg_ratio := float(segs) / 16.0
	vessel_mass_kg = 120000.0 * archetype_mass_mult * len_ratio * (0.5 + 0.5 * seg_ratio) * (0.7 + 0.3 * chitin_dens) * (0.8 + 0.2 * (armor_thick / 4.5))

	# Approximate bounding dimensions for inertia tensor calculation
	var w: float = 6.5 * (ship_len / 28.0)
	var h: float = 4.8 * (ship_len / 28.0)
	var l: float = ship_len

	# Moments of inertia for solid ellipsoid / biomechanical fuselage:
	# Ix (Pitch) = 1/5 * m * (h^2 + l^2)
	# Iy (Yaw)   = 1/5 * m * (w^2 + l^2)
	# Iz (Roll)  = 1/5 * m * (w^2 + h^2)
	moment_of_inertia = Vector3(
		0.2 * vessel_mass_kg * (h * h + l * l),
		0.2 * vessel_mass_kg * (w * w + l * l),
		0.2 * vessel_mass_kg * (w * w + h * h)
	)

	# Scale thrust forces to maintain balanced maneuverability across ship sizes.
	# Newtonian max speed is 500 km/s — reach it in ~10s, so a = 50,000 m/s^2.
	# F = m * a, so thrust = mass * 50K for forward, scaled down for reverse/strafe.
	forward_thrust_force = vessel_mass_kg * 50000.0
	reverse_thrust_force = vessel_mass_kg * 30000.0
	strafe_thrust_force = vessel_mass_kg * 35000.0
	pitch_torque = moment_of_inertia.x * 3.0
	yaw_torque = moment_of_inertia.y * 3.0
	roll_torque = moment_of_inertia.z * 4.0

func _ensure_unified_collision() -> void:
	var col_shape: CollisionShape3D = get_node_or_null("UnifiedShipCollisionShape")
	if col_shape == null:
		for child in get_children():
			if child is CollisionShape3D:
				col_shape = child
				break
	if col_shape == null:
		col_shape = CollisionShape3D.new()
		col_shape.name = "UnifiedShipCollisionShape"
		add_child(col_shape)

	for child in get_children():
		if child is ProceduralBioMesh:
			child.generate_collision()
			if col_shape.shape == null and child.mesh:
				var shape = child.mesh.create_convex_shape(true, true)
				if shape:
					col_shape.shape = shape

	if col_shape.shape == null:
		var hull_box := BoxShape3D.new()
		hull_box.size = Vector3(6.5, 4.8, 28.0)
		col_shape.shape = hull_box

## Spawns the energy-shield bubble visual as a child of the ship body so it
## follows the vessel. Sized to encompass the bio mesh AABB.
func _setup_shield_visual() -> void:
	# Compute a bubble radius + center from the bio mesh AABB when available so
	# the shield fully encloses the ship. Fall back to vessel dimensions.
	var bubble_radius: float = 16.0
	var bubble_center: Vector3 = Vector3.ZERO
	var bio_mesh: MeshInstance3D = null
	for child: Node in get_children():
		if child is ProceduralBioMesh:
			bio_mesh = child as MeshInstance3D
			break
		elif child is MeshInstance3D and bio_mesh == null:
			bio_mesh = child as MeshInstance3D
	if bio_mesh and bio_mesh.mesh:
		var aabb: AABB = bio_mesh.get_aabb()
		if aabb.size != Vector3.ZERO:
			bubble_center = aabb.get_center()
			bubble_radius = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.62 + 2.0
	# Clamp to a sensible range (ship is ~28m long, shield should be 12–40m radius).
	bubble_radius = clampf(bubble_radius, 12.0, 40.0)

	_shield_visual = BioShieldVisual.new()
	_shield_visual.name = "BioShieldVisual"
	_shield_visual.bubble_radius = bubble_radius
	_shield_visual.position = bubble_center
	# Shield renders behind/around the ship; don't let it affect collision or picking.
	_shield_visual.set_process_input(false)
	add_child(_shield_visual)
	_shield_visual.set_strength(bio_shield / maxf(1.0, bio_shield_max))

## Spawns the bio-plasma fuel tank visual — a translucent caustic-fluid reservoir
## mounted on the dorsal hull whose fill level tracks the bio_plasma_fuel reserve.
## Uses bio_caustic_fluid.gdshader. Null-safe: no-ops if the shader isn't
## registered, so the ship still flies normally without the visual.
func _setup_fuel_tank_visual() -> void:
	var shader: Shader = ShaderRegistry.get_shader(ShaderRegistry.ID_CAUSTIC_FLUID)
	if shader == null:
		return
	# Size the tank relative to the vessel so it reads on interceptors & leviathans.
	var tank_radius: float = clampf(vessel_mass_kg / 125000.0, 0.6, 1.6) * 0.9
	_fuel_tank_base_scale = tank_radius
	_fuel_tank_visual = MeshInstance3D.new()
	_fuel_tank_visual.name = "BioPlasmaFuelTank"
	var sphere := SphereMesh.new()
	sphere.radius = tank_radius
	sphere.height = tank_radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 32
	_fuel_tank_mat = ShaderMaterial.new()
	_fuel_tank_mat.shader = shader
	_fuel_tank_mat.set_shader_parameter("caustic_scale", 10.0)
	_fuel_tank_mat.set_shader_parameter("caustic_speed", 0.5)
	_fuel_tank_mat.set_shader_parameter("caustic_intensity", 1.6)
	_fuel_tank_mat.set_shader_parameter("deep_color", Color(0.0, 0.18, 0.22, 0.85))
	_fuel_tank_mat.set_shader_parameter("shallow_color", Color(0.0, 0.9, 0.7, 0.9))
	_fuel_tank_mat.set_shader_parameter("caustic_color", Color(1.0, 0.75, 0.2, 1.0))
	_fuel_tank_mat.set_shader_parameter("emission_boost", 1.4)
	sphere.material = _fuel_tank_mat
	_fuel_tank_visual.mesh = sphere
	_fuel_tank_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Mount the tank on the dorsal spine, slightly forward of the geometric center.
	_fuel_tank_visual.position = Vector3(0.0, 2.2, 1.4)
	add_child(_fuel_tank_visual)
	_update_fuel_tank_visual()

## Updates the fuel tank visual fill level from the current bio_plasma_fuel ratio.
## The tank squashes vertically as the reserve depletes so the player can read
## fuel state at a glance. No-ops when the visual isn't present.
func _update_fuel_tank_visual() -> void:
	if _fuel_tank_visual == null or not is_instance_valid(_fuel_tank_visual):
		return
	var ratio: float = clampf(bio_plasma_fuel / maxf(1.0, max_bio_plasma_fuel), 0.0, 1.0)
	# Squash Y from 1.0 (full) down to 0.15 (near-empty); keep X/Z at full radius.
	var fill_y: float = lerp(0.15, 1.0, ratio)
	_fuel_tank_visual.scale = Vector3(1.0, fill_y, 1.0)
	# Brighten the caustics as the tank empties so low fuel reads as agitated glow.
	if _fuel_tank_mat:
		_fuel_tank_mat.set_shader_parameter("emission_boost", lerp(1.0, 2.6, 1.0 - ratio))
		_fuel_tank_mat.set_shader_parameter("caustic_speed", lerp(0.4, 1.2, 1.0 - ratio))

## Returns the Juicee autoload node if present (dynamic lookup so the script
## parses without the singleton registered). Returns null in headless/test runs.
func _get_juicee() -> Node:
	if _juicee_node and is_instance_valid(_juicee_node):
		return _juicee_node
	if not is_inside_tree() or not get_tree():
		return null
	var root_node: Node = get_tree().root
	if root_node.has_node("Juicee"):
		_juicee_node = root_node.get_node("Juicee")
		return _juicee_node
	return null

## Fire Juicee impact juice (3D camera shake + hit-stop + FOV punch) scaled by
## [param intensity] (0..1). No-ops when Juicee is unavailable or screenshake is
## disabled via the accessibility multiplier.
func _trigger_impact_juice(intensity: float, heavy: bool) -> void:
	if camera_shake_multiplier <= 0.0:
		return
	var juicee: Node = _get_juicee()
	if juicee == null:
		return
	var i: float = clampf(intensity, 0.0, 1.0)
	if i <= 0.0:
		return
	# 3D camera shake — snappy impact punch on top of the sustained manual shake.
	juicee.call("shake_camera_3d", self, 0.06 + i * 0.22, 0.18 + i * 0.18)
	# Brief hit-stop for weighty impacts (heavier on hull breaches / big hits).
	if heavy:
		juicee.call("hit_stop", self, 0.03 + i * 0.05, 0.0)
	# FOV punch — zoom-in kick that springs back for a satisfying impact zoom.
	juicee.call("fov_3d", self, -3.0 - i * 6.0, 0.25 + i * 0.2)

## Fire Juicee boost-ignition juice: a brief FOV widen + light shake for the
## exothermal siphon surge. No-ops when Juicee is unavailable or shake is disabled.
func _trigger_boost_juice() -> void:
	if camera_shake_multiplier <= 0.0:
		return
	var juicee: Node = _get_juicee()
	if juicee == null:
		return
	juicee.call("fov_3d", self, 6.0, 0.35)
	juicee.call("shake_camera_3d", self, 0.05, 0.2)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_control_enabled:
		mouse_delta += event.relative
		# Accumulate normalized mouse flight cursor for NMS tethered HUD
		mouse_flight_cursor.x = clampf(mouse_flight_cursor.x + event.relative.x * 0.006, -1.0, 1.0)
		mouse_flight_cursor.y = clampf(mouse_flight_cursor.y + event.relative.y * 0.006, -1.0, 1.0)

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Engine.is_editor_hint():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if event is InputEventKey and not event.echo and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_Z:
			dampening_enabled = not dampening_enabled
			dampening_toggled.emit(dampening_enabled)
		elif event.keycode == KEY_V or event.keycode == KEY_C:
			toggle_camera_mode()
		elif event.keycode == KEY_F3:
			toggle_collision_debug()

func _process(delta: float) -> void:
	# Guard against running during scene teardown.
	if not is_inside_tree():
		return
	# Damp mouse_flight_cursor at render rate (not physics rate) so the HUD
	# reticle smooths consistently regardless of physics/render frame timing.
	if mouse_control_enabled and wave_state == WaveState.OFF:
		mouse_flight_cursor = mouse_flight_cursor.lerp(Vector2.ZERO, clampf(delta * 4.5, 0.0, 1.0))

	# NeuralRegen self-healing system — handles shield regen, hull regen, and
	# organ healing. Replaces the legacy inline shield regen logic below.
	# (Kept as fallback if NeuralRegen autoload is not present.)
	var ml := Engine.get_main_loop()
	var neural_regen: Node = null
	if ml is SceneTree and ml.root:
		neural_regen = ml.root.get_node_or_null("NeuralRegen")
	if neural_regen and neural_regen.has_method("process_regeneration"):
		neural_regen.process_regeneration(delta, self)
	else:
		# Legacy shield regeneration — delayed after taking damage
		if bio_shield < bio_shield_max:
			if bio_shield_regen_timer > 0.0:
				bio_shield_regen_timer = maxf(0.0, bio_shield_regen_timer - delta)
			else:
				bio_shield = minf(bio_shield_max, bio_shield + bio_shield_regen_rate * delta)
				# Keep the shield visual strength in sync as it regenerates.
				if _shield_visual and is_instance_valid(_shield_visual):
					_shield_visual.set_strength(bio_shield / maxf(1.0, bio_shield_max))
	# Keep the bio-plasma fuel tank visual fill in sync with the reserve (fuel
	# changes in both _handle_bio_boost and the Wave Engine cruise).
	# Dirty flag: only update when fuel ratio actually changes.
	var fuel_ratio := bio_plasma_fuel / maxf(1.0, max_bio_plasma_fuel)
	if !is_equal_approx(fuel_ratio, _last_fuel_ratio):
		_last_fuel_ratio = fuel_ratio
		_update_fuel_tank_visual()

func _physics_process(delta: float) -> void:
	# Skip normal rotation during wave engine CHARGING/ENGAGED — auto-align handles all rotation
	if wave_state == WaveState.OFF or wave_state == WaveState.INHIBITED:
		_handle_rotation(delta)
	if wave_state == WaveState.ENGAGED:
		_handle_wave_engine(delta)
	else:
		_handle_wave_engine(delta)
		if wave_state == WaveState.OFF:
			_handle_thrust(delta)
			_handle_dampening(delta)
			_handle_bio_boost(delta)

	_handle_atmospheric_physics(delta)
	_integrate_movement(delta)
	_calculate_g_forces(delta)
	_update_camera_effects(delta)
	_sync_organ_telemetry(delta)
	# Skip planet proximity audio scan during wave engine — at relativistic
	# speeds the scan is wasteful (ship passes planets in milliseconds) and
	# the proximity soundscape is irrelevant during warp.
	if wave_state != WaveState.ENGAGED:
		_update_planet_proximity_audio()
	# Decay damage flash timer
	damage_flash_timer = maxf(0.0, damage_flash_timer - delta * 1.2)

## Scans for nearby planets and updates BioAudioDirector with proximity soundscape data.
func _update_planet_proximity_audio() -> void:
	var tree: SceneTree = null
	if is_inside_tree() and get_tree():
		tree = get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return
	var director := tree.root.get_node_or_null("BioAudioDirector")
	if director == null:
		return
	var my_pos := global_position if is_inside_tree() else position
	var targets := tree.get_nodes_in_group("targets")
	var nearest_planet: Node3D = null
	var nearest_dist: float = 999999.0
	for t in targets:
		if not is_instance_valid(t) or not (t is Node3D):
			continue
		# Check if this target has a planet archetype property
		if not t.get("archetype") != null:
			if t.get("archetype") == null:
				continue
		var t_pos: Vector3 = (t as Node3D).global_position if (t as Node3D).is_inside_tree() and is_inside_tree() else (t as Node3D).position
		var dist: float = my_pos.distance_to(t_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_planet = t as Node3D
	if nearest_planet and nearest_dist < 5000.0:
		# Proximity: 1.0 at 500 units, 0.0 at 5000 units
		var proximity: float = clampf(1.0 - (nearest_dist - 500.0) / 4500.0, 0.0, 1.0)
		var archetype: int = int(nearest_planet.get("archetype") if nearest_planet.get("archetype") != null else -1)
		director.set_planet_proximity(archetype, proximity)
	else:
		director.set_planet_proximity(-1, 0.0)

## Handles the Alcubierre-style Wave Engine for in-system supercruise transit.
## Contracts spacetime ahead of the ship and expands it behind, riding a wave
## inside a flat-region warp bubble. A translucent warp plane materializes
## around the hull — front dips down (contraction), back raises up (expansion).
func _handle_wave_engine(delta: float) -> void:
	if not wave_engine_enabled:
		return

	# Wave Engine Trigger: Holding Space (when pressing W or holding Shift+Space) or J key
	var wave_input := simulated_wave or Input.is_key_pressed(KEY_J) or (Input.is_key_pressed(KEY_SPACE) and (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_W)))
	var brake_input := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_K)

	if wave_state == WaveState.OFF:
		if wave_input and bio_plasma_fuel > 10.0:
			wave_state = WaveState.CHARGING
			wave_charge_timer = wave_charge_duration
			wave_state_changed.emit(int(WaveState.CHARGING), 0.0)
			_notify_audio_wave_state(1)

	elif wave_state == WaveState.CHARGING:
		if not wave_input and not simulated_wave:
			# Cancelled charging before spool-up complete
			wave_state = WaveState.OFF
			wave_state_changed.emit(int(WaveState.OFF), 0.0)
			_notify_audio_wave_state(0)
		else:
			wave_charge_timer -= delta
			var charge_ratio := clampf(1.0 - (wave_charge_timer / maxf(0.01, wave_charge_duration)), 0.0, 1.0)
			camera_shake_intensity = clamp(camera_shake_intensity + delta * 1.5, 0.0, 0.6)
			wave_state_changed.emit(int(WaveState.CHARGING), charge_ratio)

			# Select target using forward cone — picks whatever you're aiming at through the reticle.
			# Once locked, don't re-scan — prevents target-switching spin.
			# If no forward target found, fall back to nearest celestial body (omnidirectional).
			if not wave_target_node or not is_instance_valid(wave_target_node):
				_update_wave_navigation(delta, false)
			if not wave_target_node or not is_instance_valid(wave_target_node):
				_update_wave_navigation(delta, true)
			if wave_target_node and is_instance_valid(wave_target_node):
				_auto_align_to_target(delta, wave_target_node, 2.0)

			if wave_charge_timer <= 0.0:
				wave_state = WaveState.ENGAGED
				wave_current_speed = max_boost_speed * 1.5
				camera_shake_intensity = 1.0
				wave_state_changed.emit(int(WaveState.ENGAGED), 1.0)
				_notify_audio_wave_state(2)
				_spawn_wave_fx()

	elif wave_state == WaveState.ENGAGED:
		# Manual Disengage on Brake (S)
		if brake_input:
			disengage_wave_engine()
			return

		# Consume bio-plasma fuel during wave cruise
		bio_plasma_fuel = max(0.0, bio_plasma_fuel - wave_fuel_cost_per_sec * delta)
		fuel_changed.emit(bio_plasma_fuel, max_bio_plasma_fuel)
		if bio_plasma_fuel <= 0.0:
			disengage_wave_engine()
			return

		# Keep the locked target from CHARGING — don't re-scan unless target is lost.
		# This prevents the ship from spinning to new targets as its heading changes.
		if not wave_target_node or not is_instance_valid(wave_target_node):
			# Target lost — try to find a new one in the forward cone
			_update_wave_navigation(delta, false)
		else:
			# Update ETA/distance on the locked target only
			_update_wave_eta()

		# Gravitational Well Deceleration: compute maximum safe speed based on remaining
		# distance so the ship can always brake to sublight before reaching the target.
		var target_cruise_speed := wave_max_speed
		if wave_target_node and is_instance_valid(wave_target_node):
			var my_pos := global_position if is_inside_tree() else position
			var t_pos := wave_target_node.global_position if wave_target_node.is_inside_tree() else wave_target_node.position
			var dist := my_pos.distance_to(t_pos)

			# Compute effective safe distance: drop at 3x planet radius from center.
			# This gives enough distance to see the whole planet when you exit warp,
			# instead of spawning inside the atmosphere.
			var planet_radius := 0.0
			if "radius_m" in wave_target_node:
				planet_radius = wave_target_node.radius_m
			var safe_dist := maxf(wave_safe_disengage_distance, planet_radius * 3.0)

			# Auto-drop safe threshold — also catch overshoot: if we'd cross safe_dist
			# this frame at current speed, drop now to prevent blowing past the planet.
			var frame_travel := wave_current_speed * delta
			if dist <= safe_dist or dist - frame_travel < safe_dist:
				# Snap to safe distance along approach vector
				var approach_dir := (t_pos - my_pos).normalized()
				global_position = t_pos - approach_dir * safe_dist
				disengage_wave_engine()
				return

			# Dynamic kinematic braking: compute required braking distance from CURRENT speed.
			# v² = u² + 2as → required_distance = (v² - v_target²) / (2 * decel)
			# This ensures braking starts early enough at any speed, not just near the planet.
			var brake_distance := dist - safe_dist
			var required_brake_dist := (wave_current_speed * wave_current_speed) / (2.0 * wave_acceleration)
			if brake_distance <= required_brake_dist + planet_radius * 2.0:
				# Need to brake now — compute max safe speed for remaining distance
				var safe_speed := sqrt(2.0 * wave_acceleration * brake_distance) + max_boost_speed
				target_cruise_speed = clampf(safe_speed, max_boost_speed, wave_max_speed)

			# Auto-steer: gradually align ship heading toward locked target during cruise
			_auto_align_to_target(delta, wave_target_node, 1.5)

		# Accelerate/decelerate toward target cruise speed
		wave_current_speed = move_toward(wave_current_speed, target_cruise_speed, wave_acceleration * delta)
		# Hard clamp: never exceed the kinematic safe speed (prevents overshoot at high velocity)
		wave_current_speed = minf(wave_current_speed, target_cruise_speed)
		var fwd := -transform.basis.z.normalized()
		linear_velocity_vector = fwd * wave_current_speed
		_update_wave_fx(delta)

## Updates ETA and distance on the currently locked target without re-scanning for new targets.
## Used during ENGAGED state to keep the locked target stable (prevents target-switching spin).
func _update_wave_eta() -> void:
	if not wave_target_node or not is_instance_valid(wave_target_node):
		wave_eta_seconds = 0.0
		return
	var my_pos: Vector3 = position
	if is_inside_tree():
		my_pos = global_position
	var t_pos: Vector3 = wave_target_node.position
	if wave_target_node.is_inside_tree():
		t_pos = wave_target_node.global_position
	var dist := my_pos.distance_to(t_pos)
	var cur_spd := maxf(10.0, wave_current_speed)
	wave_eta_seconds = dist / cur_spd
	wave_arrival_eta_updated.emit(wave_eta_seconds, dist, wave_target_name)

## Tracks targeted celestial bodies or forward objects to compute real-time Wave cruise ETA.
## Forward cone selection: picks the target most directly ahead (highest dot product) within
## a wide 75° half-angle cone. This ensures whatever you're aiming at through the reticle
## gets selected, not just the nearest target. Once locked, the target stays locked.
func _update_wave_navigation(_delta: float, omnidirectional: bool = false) -> void:
	wave_target_node = null
	wave_target_name = ""
	wave_eta_seconds = 0.0

	var my_pos: Vector3 = position
	if is_inside_tree():
		my_pos = global_position
	var fwd := -transform.basis.z.normalized()

	var tree: SceneTree = null
	if is_inside_tree() and get_tree():
		tree = get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree

	if not tree:
		return

	var targets := tree.get_nodes_in_group("targets")
	var best_dot: float = 0.25 # Wide forward cone (~75 deg half-angle)
	var best_dist: float = INF

	for t in targets:
		if is_instance_valid(t) and t is Node3D and not t.is_queued_for_deletion():
			var t_pos: Vector3 = (t as Node3D).position
			if t.is_inside_tree():
				t_pos = (t as Node3D).global_position
			var dir_to := (t_pos - my_pos).normalized()
			var dot := fwd.dot(dir_to)
			var dist := my_pos.distance_to(t_pos)

			# Skip targets within the safe disengage radius — too close for supercruise.
			# The wave engine is for traveling to distant destinations, not nearby objects.
			if dist <= wave_safe_disengage_distance:
				continue

			if omnidirectional:
				# Nearest target regardless of facing
				if dist < best_dist:
					best_dist = dist
					best_dot = dot
					wave_target_node = t as Node3D
					if "planet_name" in t:
						wave_target_name = t.planet_name
					else:
						wave_target_name = t.name
			else:
				# Forward cone: prioritize most directly ahead (highest dot), not nearest
				if dot > best_dot:
					best_dist = dist
					best_dot = dot
					wave_target_node = t as Node3D
					if "planet_name" in t:
						wave_target_name = t.planet_name
					else:
						wave_target_name = t.name

	if wave_target_node:
		var cur_spd := maxf(10.0, wave_current_speed)
		wave_eta_seconds = best_dist / cur_spd
		wave_arrival_eta_updated.emit(wave_eta_seconds, best_dist, wave_target_name)

## Auto-aligns the ship's heading toward the target node during wave engine charging/cruise.
## Uses proportional steering with angular velocity damping to prevent overshoot/oscillation.
func _auto_align_to_target(delta: float, target: Node3D, strength: float) -> void:
	var my_pos: Vector3 = position
	if is_inside_tree():
		my_pos = global_position
	var t_pos: Vector3 = target.position
	if target.is_inside_tree():
		t_pos = target.global_position

	var fwd := -transform.basis.z.normalized()
	var dir_to_target := (t_pos - my_pos).normalized()

	# Convert direction to local space to get pitch/yaw error
	var local_dir := transform.basis.inverse() * dir_to_target

	# Proportional steering: torque proportional to angular error
	# In Godot's right-handed system: positive X rotation = pitch UP, positive Y rotation = turn LEFT
	var pitch_correction: float
	var yaw_correction: float
	if local_dir.z > 0.0:
		# Target is BEHIND the ship — apply consistent turn to flip around.
		# Yaw in the direction of the target's lateral offset to turn the shortest way.
		# Once the target crosses into the forward hemisphere (z < 0), normal control takes over.
		var yaw_dir := 1.0 if local_dir.x >= 0.0 else -1.0
		yaw_correction = yaw_dir * strength
		pitch_correction = local_dir.y * strength * 0.5  # Mild pitch while flipping
	else:
		# Target is AHEAD — proportional steering to center it in the forward (-Z) view
		pitch_correction = local_dir.y * strength  # Target above (y>0) → positive pitch → nose up
		yaw_correction = -local_dir.x * strength   # Target right (x>0) → negative yaw → turn right

	# Apply torques for alignment
	var torque_net := Vector3(
		pitch_correction * pitch_torque,
		yaw_correction * yaw_torque,
		0.0 # No roll correction
	)

	var ang_accel := Vector3(
		torque_net.x / maxf(1.0, moment_of_inertia.x),
		torque_net.y / maxf(1.0, moment_of_inertia.y),
		torque_net.z / maxf(1.0, moment_of_inertia.z)
	)

	angular_velocity_vector += ang_accel * delta

	# Critical damping: counteract angular velocity to prevent overshoot.
	# Damping factor scales with how misaligned we are — more damping when close to aligned,
	# less when far away (so the ship can actually turn toward a target behind it).
	var alignment_dot := fwd.dot(dir_to_target)
	var damping_factor = clamp(2.0 + (1.0 - alignment_dot) * 3.0, 2.0, 5.0)
	angular_velocity_vector = angular_velocity_vector.lerp(Vector3.ZERO, delta * damping_factor)

	# Apply rotation
	rotate_object_local(Vector3.RIGHT, angular_velocity_vector.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity_vector.y * delta)
	rotate_object_local(Vector3.BACK, angular_velocity_vector.z * delta)
	transform.basis = transform.basis.orthonormalized()

## Safely drops out of the Wave Engine supercruise back into sublight dogfight flight.
func disengage_wave_engine() -> void:
	if wave_state != WaveState.OFF:
		wave_state = WaveState.OFF
		wave_current_speed = 0.0
		linear_velocity_vector = linear_velocity_vector.normalized() * max_boost_speed
		camera_shake_intensity = 0.8
		wave_state_changed.emit(int(WaveState.OFF), 0.0)
		_notify_audio_wave_state(0)
		_despawn_wave_fx()
	# Clear locked target so next engagement re-scans fresh
	wave_target_node = null
	wave_target_name = ""
	wave_eta_seconds = 0.0

func _notify_audio_wave_state(new_state: int) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		if ml.root.has_node("BioAudioSynth"):
			ml.root.get_node("BioAudioSynth").set_wave_engine_state(new_state)
		# Notify BioAudioDirector of wave engine events for smooth tension transitions
		if ml.root.has_node("BioAudioDirector"):
			var director = ml.root.get_node("BioAudioDirector")
			if new_state == 2:  # ENGAGED
				director.transition_to_event("wave_engage")
			elif new_state == 0:  # OFF / DISENGAGED
				director.transition_to_event("wave_disengage")

## Spawns the translucent Alcubierre warp plane visual effect around the ship.
func _spawn_wave_fx() -> void:
	_despawn_wave_fx()
	if not is_inside_tree():
		return
	var WaveEngineFXClass := load("res://scripts/WaveEngineFX.gd")
	if not WaveEngineFXClass:
		return
	wave_fx_node = WaveEngineFXClass.new()
	add_child(wave_fx_node)

## Despawns the warp plane visual effect (triggers fade-out then free).
func _despawn_wave_fx() -> void:
	if wave_fx_node and is_instance_valid(wave_fx_node):
		if wave_fx_node.has_method("despawn"):
			wave_fx_node.despawn()
		else:
			wave_fx_node.queue_free()
	wave_fx_node = null

## Updates the warp plane effect each frame during ENGAGED state.
func _update_wave_fx(delta: float) -> void:
	if wave_fx_node and is_instance_valid(wave_fx_node) and wave_fx_node.has_method("update_wave_state"):
		var speed_ratio := clampf(wave_current_speed / maxf(1.0, wave_max_speed), 0.0, 1.0)
		wave_fx_node.update_wave_state(speed_ratio, delta)

## Applies an instantaneous physical impulse at a given contact point (in local or global coordinates)
func apply_impulse(impulse_global: Vector3, contact_local: Vector3 = Vector3.ZERO) -> void:
	if vessel_mass_kg <= 0.0:
		return
	# Linear impulse: Delta v = J / m
	linear_velocity_vector += impulse_global / vessel_mass_kg
	
	# Angular impulse: Delta omega = I^-1 * (r x J_local)
	if contact_local.length_squared() > 0.001 and moment_of_inertia.x > 0.0:
		var impulse_local := transform.basis.inverse() * impulse_global
		var torque_impulse := (contact_local - center_of_mass_offset).cross(impulse_local)
		angular_velocity_vector += Vector3(
			torque_impulse.x / moment_of_inertia.x,
			torque_impulse.y / moment_of_inertia.y,
			torque_impulse.z / moment_of_inertia.z
		)

## Returns current normalized mouse flight cursor [-1.0, 1.0].
func get_mouse_flight_cursor() -> Vector2:
	return mouse_flight_cursor

## Processes 6-DOF Pitch, Yaw, and Roll rotational torque dynamics with No Man's Sky auto-banking.
func _handle_rotation(delta: float) -> void:
	var pitch_input: float = 0.0
	var yaw_input: float = 0.0
	var roll_input: float = 0.0

	# Mouse input for Pitch and Yaw (No Man's Sky Direct & Tethered Flight Model)
	if mouse_control_enabled:
		var y_sign: float = -1.0 if invert_y else 1.0
		if mouse_delta.length_squared() > 0.0:
			pitch_input += y_sign * mouse_delta.y * mouse_sensitivity
			yaw_input -= mouse_delta.x * mouse_sensitivity
			mouse_delta = Vector2.ZERO
		elif mouse_flight_cursor.length_squared() > 0.001:
			pitch_input += y_sign * mouse_flight_cursor.y * 1.5
			yaw_input -= mouse_flight_cursor.x * 1.5
		
		# Smooth spring return to center for floating HUD reticle
		# (Damping now handled in _process for render-rate smoothing)

	# Keyboard Pitch (Arrow keys)
	if Input.is_key_pressed(KEY_UP):
		pitch_input += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pitch_input -= 1.0

	# Keyboard Yaw / Steering (A / D or Left / Right Arrow keys)
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		yaw_input += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		yaw_input -= 1.0

	# Keyboard Manual Roll controls (Q / E)
	var manual_roll: bool = false
	if Input.is_key_pressed(KEY_Q):
		roll_input += 1.0
		manual_roll = true
	if Input.is_key_pressed(KEY_E):
		roll_input -= 1.0
		manual_roll = true

	# Apply simulated inputs for AI / Playtest scripts
	pitch_input += simulated_pitch
	yaw_input += simulated_yaw
	if simulated_roll != 0.0:
		manual_roll = true
		roll_input += simulated_roll

	# No Man's Sky Style: Automatic Coordinated Banking during turns
	if auto_banking_enabled and not manual_roll:
		roll_input += yaw_input * auto_banking_strength
		
		# Auto-leveling restoring roll stability when no roll input is given
		if abs(yaw_input) < 0.05:
			var roll_tilt := transform.basis.x.y # X-axis tilt relative to world horizon
			roll_input -= roll_tilt * auto_level_speed

	# Starship Combat Auto-Follow (Holding RMB or F or holding S with combat target nearby)
	if combat_auto_follow_enabled:
		var is_tracking := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_F)
		if is_tracking:
			var tracking_torques := _calculate_auto_follow_torques()
			pitch_input += tracking_torques.x * auto_follow_strength
			yaw_input += tracking_torques.y * auto_follow_strength

	# Net control torques applied to single rigid vessel (N*m)
	var torque_net := Vector3(
		pitch_input * pitch_torque,
		yaw_input * yaw_torque,
		roll_input * roll_torque
	)

	# Angular acceleration: alpha = torque / I
	var ang_accel := Vector3(
		torque_net.x / maxf(1.0, moment_of_inertia.x),
		torque_net.y / maxf(1.0, moment_of_inertia.y),
		torque_net.z / maxf(1.0, moment_of_inertia.z)
	)

	# Integrate angular velocity
	angular_velocity_vector += ang_accel * delta

	# Apply rotation to 3D basis and orthonormalize to prevent matrix scaling drift
	rotate_object_local(Vector3.RIGHT, angular_velocity_vector.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity_vector.y * delta)
	rotate_object_local(Vector3.BACK, angular_velocity_vector.z * delta)
	transform.basis = transform.basis.orthonormalized()

## Calculates steering corrections for No Man's Sky combat target auto-follow.
func _calculate_auto_follow_torques(explicit_target: Node3D = null) -> Vector2:
	var best_target: Node3D = explicit_target
	var my_pos := global_position if is_inside_tree() else position
	var fwd := -transform.basis.z.normalized()
	
	if not best_target:
		var tree: SceneTree = null
		if is_inside_tree() and get_tree():
			tree = get_tree()
		elif Engine.get_main_loop() is SceneTree:
			tree = Engine.get_main_loop() as SceneTree
			
		if tree:
			var targets := tree.get_nodes_in_group("targets")
			var best_dot: float = cos(deg_to_rad(auto_follow_cone_degrees))
			for t in targets:
				if is_instance_valid(t) and t is Node3D and not t.is_queued_for_deletion():
					var target_pos := (t as Node3D).global_position if (t.is_inside_tree() and is_inside_tree()) else (t as Node3D).position
					var dir_to := (target_pos - my_pos).normalized()
					var dot := fwd.dot(dir_to)
					if dot > best_dot:
						best_dot = dot
						best_target = t
						
	if not best_target:
		return Vector2.ZERO

	# Convert target vector into local ship coordinate space
	var final_target_pos := best_target.global_position if (best_target.is_inside_tree() and is_inside_tree()) else best_target.position
	var local_dir := transform.basis.inverse() * (final_target_pos - my_pos).normalized()
	var pitch_corr := clampf(local_dir.y * 3.0, -1.0, 1.0)
	var yaw_corr := clampf(-local_dir.x * 3.0, -1.0, 1.0)
	return Vector2(pitch_corr, yaw_corr)

## Handles No Man's Sky style throttle & linear thrust (W=Throttle, S=Brake/Reverse, Shift=Boost).
func _handle_thrust(delta: float) -> void:
	var thrust_dir: Vector3 = Vector3.ZERO

	# No Man's Sky Forward Throttle (W) & Reverse Brake / Siphons (S)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_I) or Input.is_key_pressed(KEY_KP_8):
		thrust_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_K) or Input.is_key_pressed(KEY_KP_2):
		thrust_dir.z += 1.0

	# Horizontal Strafe (J / L or Numpad 4/6)
	if Input.is_key_pressed(KEY_J) or Input.is_key_pressed(KEY_KP_4):
		thrust_dir.x -= 1.0
	if Input.is_key_pressed(KEY_L) or Input.is_key_pressed(KEY_KP_6):
		thrust_dir.x += 1.0

	# Vertical Maneuver Siphons (SPACE / R for Ascend, CTRL / C / F for Descend)
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_R):
		thrust_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_F):
		thrust_dir.y -= 1.0

	# Apply simulated thrust vector
	thrust_dir += simulated_thrust

	if thrust_dir.length_squared() > 0.001:
		thrust_dir = thrust_dir.normalized()

	# Net thrust force in local coordinates (Newtons)
	var current_force_z := (forward_thrust_force * boost_multiplier) if (thrust_dir.z < 0 and is_boosting) else (forward_thrust_force if thrust_dir.z < 0 else reverse_thrust_force)
	var current_force_x := strafe_thrust_force
	var current_force_y := strafe_thrust_force

	var local_force := Vector3(
		thrust_dir.x * current_force_x,
		thrust_dir.y * current_force_y,
		thrust_dir.z * current_force_z
	)
	var global_force := transform.basis * local_force

	# Linear acceleration: a = F_net / m
	var linear_accel := global_force / maxf(1.0, vessel_mass_kg)

	# Apply acceleration to velocity
	linear_velocity_vector += linear_accel * delta

	# Clamp max speed limit
	var current_max_speed := max_boost_speed if is_boosting else max_speed
	if linear_velocity_vector.length() > current_max_speed:
		linear_velocity_vector = linear_velocity_vector.normalized() * current_max_speed

	# Audio Telemetry: 6-DOF Siphon Thrusters & Bio-Boost
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		var audio = ml.root.get_node("BioAudioSynth")
		var fwd_t := clampf(-thrust_dir.z, 0.0, 1.0)
		var strafe_t := clampf(Vector2(thrust_dir.x, thrust_dir.y).length(), 0.0, 1.0)
		var retro_t := clampf(thrust_dir.z, 0.0, 1.0)
		audio.set_6dof_thrust(fwd_t, strafe_t, retro_t, current_g_force)
		audio.set_bio_boost(is_boosting)
		# Drive Dynamic Tension Index from hull integrity, boost, and G-force
		var dti: float = clampf(
			(1.0 - hull_integrity / 100.0) * 0.45 +
			(1.0 if is_boosting else 0.0) * 0.20 +
			(current_g_force / 8.0) * 0.20 +
			damage_flash_timer * 0.15,
			0.0, 1.0
		)
		audio.set_tension_index(dti)
		audio.set_pilot_stamina(clampf(bio_plasma_fuel / maxf(1.0, max_bio_plasma_fuel), 0.0, 1.0))

## Called when the ship takes damage (from BioPlasmaProjectile, collisions, etc.)
## Shield absorbs damage first, then hull. Triggers shield_hit/hull_hit signals.
## [param hit_pos] is the world-space impact location (optional; defaults to a
## plausible surface point) used to place the energy-shield ripple effect.
func take_damage(amount: float, hit_pos: Vector3 = Vector3.ZERO) -> void:
	CombatStats.register_damage_received(amount)
	# Notify NeuralRegen self-healing system (resets regen timers, injects damage map)
	var _ml := Engine.get_main_loop()
	var _nr: Node = null
	if _ml is SceneTree and _ml.root:
		_nr = _ml.root.get_node_or_null("NeuralRegen")
	if _nr and _nr.has_method("on_damage_taken"):
		_nr.on_damage_taken(amount)
	var remaining_damage: float = amount
	var shield_absorbed: bool = false
	# Shield absorbs first
	if bio_shield > 0.0:
		var absorbed: float = minf(bio_shield, remaining_damage)
		bio_shield = maxf(0.0, bio_shield - absorbed)
		remaining_damage -= absorbed
		bio_shield_regen_timer = bio_shield_regen_delay
		shield_absorbed = absorbed > 0.0
		shield_hit.emit(absorbed, bio_shield)
		# Energy shield visual: ripple at the hit location + strength update.
		if _shield_visual and is_instance_valid(_shield_visual):
			_shield_visual.trigger_impact(hit_pos)
			_shield_visual.set_strength(bio_shield / maxf(1.0, bio_shield_max))
	# Remaining damage goes to hull
	if remaining_damage > 0.0:
		hull_integrity = maxf(0.0, hull_integrity - remaining_damage)
		damage_flash_timer = minf(1.0, damage_flash_timer + remaining_damage / 50.0)
		camera_shake_intensity = maxf(camera_shake_intensity, remaining_damage * 0.05)
		hull_hit.emit(remaining_damage, hull_integrity)
		# Hull breach — heavy impact juice (hit-stop + bigger shake/zoom).
		_trigger_impact_juice(clampf(remaining_damage / 50.0, 0.2, 1.0), true)
	else:
		# Shield absorbed all — smaller shake, no hull flash
		camera_shake_intensity = maxf(camera_shake_intensity, amount * 0.02)
		damage_flash_timer = minf(0.3, damage_flash_timer + amount / 100.0)
		# Lighter juice for shield-only hits (no hit-stop unless it was a big hit).
		if shield_absorbed:
			_trigger_impact_juice(clampf(amount / 80.0, 0.1, 0.6), amount >= 40.0)

	# Audio feedback
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		var audio = ml.root.get_node("BioAudioSynth")
		audio.trigger_damage(clampf(amount / 50.0, 0.0, 1.0))

	# Death check
	if hull_integrity <= 0.0 and not _is_dead:
		_is_dead = true
		ship_destroyed.emit()
		_on_ship_death()

var _is_dead: bool = false

func _on_ship_death() -> void:
	# Register death in combat stats
	CombatStats.register_death()
	# Spawn explosion at ship position
	CombatVFX.spawn_explosion(global_position, Color(0.0, 1.0, 0.75, 1.0), 2.0)
	# Big camera shake
	camera_shake_intensity = 5.0
	# Audio
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		var audio = ml.root.get_node("BioAudioSynth")
		audio.trigger_damage(1.0)
		audio.play_shield_impact()
	# Disable controls
	mouse_control_enabled = false
	# Respawn after 3 seconds
	if is_inside_tree() and get_tree():
		await get_tree().create_timer(3.0).timeout
		_respawn()

func _respawn() -> void:
	_is_dead = false
	hull_integrity = 100.0
	bio_shield = bio_shield_max
	bio_plasma_fuel = max_bio_plasma_fuel
	damage_flash_timer = 0.0
	camera_shake_intensity = 0.0
	mouse_control_enabled = true
	# Restore the energy shield visual to full strength.
	if _shield_visual and is_instance_valid(_shield_visual):
		_shield_visual.set_strength(1.0)
	# Reset velocity
	linear_velocity_vector = Vector3.ZERO
	angular_velocity_vector = Vector3.ZERO
	# Move to a safe position (near world origin)
	global_position = Vector3.ZERO

## Bio-hydro pulse dampening counteracts Newtonian drifting when dampening is enabled.
func _handle_dampening(delta: float) -> void:
	if dampening_enabled:
		var lin_weight := clampf(linear_dampening_rate * delta, 0.0, 1.0)
		var ang_weight := clampf(angular_dampening_rate * delta, 0.0, 1.0)
		linear_velocity_vector = linear_velocity_vector.lerp(Vector3.ZERO, lin_weight)
		angular_velocity_vector = angular_velocity_vector.lerp(Vector3.ZERO, ang_weight)

## Manages exothermal siphon surge (Bio-Boost) and fuel reserve.
func _handle_bio_boost(delta: float) -> void:
	var boost_requested := simulated_boost or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_TAB)
	
	if boost_requested and bio_plasma_fuel > 0.0:
		if not is_boosting:
			is_boosting = true
			boost_state_changed.emit(true)
			# Boost ignition juice: subtle FOV widen + light shake for a sense of surge.
			_trigger_boost_juice()
		
		bio_plasma_fuel = max(0.0, bio_plasma_fuel - boost_drain_rate * delta)
		fuel_changed.emit(bio_plasma_fuel, max_bio_plasma_fuel)
		recharge_timer = recharge_delay
		camera_shake_intensity = clamp(camera_shake_intensity + delta * 2.0, 0.0, 1.0)
	else:
		if is_boosting:
			is_boosting = false
			boost_state_changed.emit(false)
		
		if recharge_timer > 0.0:
			recharge_timer -= delta
		elif bio_plasma_fuel < max_bio_plasma_fuel:
			bio_plasma_fuel = min(max_bio_plasma_fuel, bio_plasma_fuel + boost_recharge_rate * delta)
			fuel_changed.emit(bio_plasma_fuel, max_bio_plasma_fuel)

## Applies velocity to body as a single unified physical object.
func _integrate_movement(_delta: float) -> void:
	if wave_state == WaveState.ENGAGED:
		# Wave Engine: bypass move_and_slide() — at relativistic speeds
		# (wave_max_speed = 200M km/s), physics collision sweeping is
		# catastrophically expensive. The Alcubierre warp doesn't use
		# normal collision detection; directly translate position.
		if is_inside_tree():
			global_position += linear_velocity_vector * _delta
		_apply_floating_origin()
		return
	velocity = linear_velocity_vector
	if is_inside_tree():
		move_and_slide()
		linear_velocity_vector = velocity
	# Floating origin: when the ship gets too far from the world origin,
	# shift all celestial bodies and the ship back so the ship stays near (0,0,0).
	# This prevents float32 precision breakdown at real-scale distances.
	_apply_floating_origin()

## Floating origin system: shifts all celestial bodies by the inverse of the
## ship's position when the ship exceeds the precision threshold. This keeps
## the ship near the world origin where float32 precision is highest (~0.01m).
## At 1 AU (149.6M km) without floating origin, precision would be ~16km.
const _FLOATING_ORIGIN_THRESHOLD_M: float = 50000.0 ## 50km from origin triggers shift
var _floating_origin_bodies: Array[Node3D] = []
var _floating_origin_populated: bool = false
func _apply_floating_origin() -> void:
	if not is_inside_tree():
		return
	var ship_pos: Vector3 = global_position
	var dist_from_origin: float = ship_pos.length()
	if dist_from_origin < _FLOATING_ORIGIN_THRESHOLD_M:
		return
	# Shift everything by the inverse of the ship's position.
	var shift: Vector3 = -ship_pos
	# Move the ship to near-origin.
	global_position = Vector3.ZERO
	# Cache celestial bodies on first use to avoid get_nodes_in_group() every frame.
	if not _floating_origin_populated:
		var tree: SceneTree = get_tree()
		if tree == null or tree.root == null:
			return
		for body: Node in tree.get_nodes_in_group("celestial_bodies"):
			if body is Node3D:
				_floating_origin_bodies.append(body as Node3D)
		_floating_origin_populated = true
	# Shift all cached celestial bodies.
	for body: Node3D in _floating_origin_bodies:
		if is_instance_valid(body):
			body.global_position += shift
	# Shift the UniverseManager if it has a global position.
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var universe: Node = tree.root.get_node_or_null("SpaceFlight/UniverseManager")
	if universe != null and universe is Node3D:
		(universe as Node3D).global_position += shift

## Calculates acceleration and resultant G-Forces.
func _calculate_g_forces(delta: float) -> void:
	if delta <= 0.0001:
		return
	var accel_vec := (linear_velocity_vector - last_velocity) / delta
	last_velocity = linear_velocity_vector
	
	# Convert acceleration magnitude to Gs (Earth gravity ~9.81 m/s^2)
	var accel_g := clampf(accel_vec.length() / 9.81, 0.0, 50.0)
	var g_weight := clampf(delta * 5.0, 0.0, 1.0)
	current_g_force = lerp(current_g_force, 1.0 + accel_g, g_weight)
	g_force_updated.emit(current_g_force)

	if accel_g > 3.0:
		camera_shake_intensity = clamp(camera_shake_intensity + (accel_g / 20.0), 0.0, 1.0)

func toggle_camera_mode() -> void:
	if camera_mode == CameraMode.FPV:
		set_camera_mode(CameraMode.CHASE)
	else:
		set_camera_mode(CameraMode.FPV)

func set_camera_mode(new_mode: CameraMode) -> void:
	camera_mode = new_mode
	if camera_mode == CameraMode.FPV:
		if fpv_camera:
			fpv_camera.current = true
			camera_node = fpv_camera
		elif camera_node:
			camera_node.current = true
	else: # CHASE
		if chase_camera:
			chase_camera.current = true
			camera_node = chase_camera
		elif camera_node:
			camera_node.current = true
	camera_mode_changed.emit(int(camera_mode))

# ------------------------------------------------------------------------------
# Collision Debug Visualization (F3 to toggle)
# ------------------------------------------------------------------------------
var _collision_debug_active: bool = false
var _collision_debug_meshes: Array[MeshInstance3D] = []

func toggle_collision_debug() -> void:
	_collision_debug_active = not _collision_debug_active
	if _collision_debug_active:
		_enable_collision_debug()
		print("[CollisionDebug] ENABLED — green=ship, orange=asteroids, red=spawn exclusion")
	else:
		_disable_collision_debug()
		print("[CollisionDebug] DISABLED")

func _enable_collision_debug() -> void:
	# 1. Ship collision wireframe (green)
	var ship_col: CollisionShape3D = null
	for child: Node in get_children():
		if child is CollisionShape3D:
			ship_col = child as CollisionShape3D
			break
	if ship_col != null and ship_col.shape is ConvexPolygonShape3D:
		ship_col.visible = true  # Also show the original debug shape
		var wf: MeshInstance3D = _create_convex_wireframe(ship_col.shape as ConvexPolygonShape3D, Color(0.0, 1.0, 0.3, 0.8))
		wf.name = "DEBUG_ShipCollision"
		add_child(wf)
		_collision_debug_meshes.append(wf)
		var aabb: AABB = _compute_shape_aabb(ship_col.shape as ConvexPolygonShape3D)
		print("  Ship collision: %d points, AABB size=%s, max_dim=%.1fm" % [
			(ship_col.shape as ConvexPolygonShape3D).points.size(),
			str(aabb.size),
			maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		])

	# 2. List all child meshes of the ship (check for external meshes inside collision)
	print("  Ship child meshes:")
	for child: Node in get_children(true):
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			var local_pos: Vector3 = mi.position
			var mesh_aabb: AABB = mi.get_aabb()
			print("    %s: local_pos=%s, AABB_size=%s" % [mi.name, str(local_pos), str(mesh_aabb.size)])

	# 3. Asteroid collision wireframes (orange)
	var asteroid_count: int = 0
	var asteroid_field: Node3D = null
	if get_tree() and get_tree().root:
		asteroid_field = get_tree().root.get_node_or_null("SpaceFlight/AsteroidField")
	if asteroid_field == null and get_tree() and get_tree().root:
		asteroid_field = get_tree().root.get_node_or_null("AsteroidField")
	if asteroid_field == null:
		print("  AsteroidField: NOT FOUND in scene tree")
	else:
		print("  AsteroidField found: %s, children=%d" % [asteroid_field.name, asteroid_field.get_child_count()])
	if asteroid_field != null:
		# Search recursively for RigidBody3D asteroids (they're inside an "Asteroids" container)
		var all_nodes: Array[Node] = asteroid_field.find_children("*", "RigidBody3D", true, false)
		for body_node: Node in all_nodes:
			if not (body_node is RigidBody3D):
				continue
			if not body_node.name.begins_with("Asteroid_"):
				continue
			var body: RigidBody3D = body_node as RigidBody3D
			for sub: Node in body.get_children():
				if sub is CollisionShape3D and (sub as CollisionShape3D).shape is ConvexPolygonShape3D:
					var awf: MeshInstance3D = _create_convex_wireframe(
						(sub as CollisionShape3D).shape as ConvexPolygonShape3D,
						Color(1.0, 0.5, 0.0, 0.6)
					)
					awf.name = "DEBUG_" + body.name + "_Collision"
					body.add_child(awf)
					_collision_debug_meshes.append(awf)
					asteroid_count += 1
					# Check distance to ship
					var dist: float = body.global_position.distance_to(global_position)
					var ast_radius: float = 6.0 * body.scale.x
					if dist < ast_radius + 150.0:
						print("    WARN: %s at %.1fm (radius=%.1fm) — near ship!" % [body.name, dist, ast_radius])
					break
	print("  Asteroid collision wireframes: %d" % asteroid_count)

	# 4. Spawn exclusion zone (red sphere)
	var exclusion: MeshInstance3D = MeshInstance3D.new()
	exclusion.name = "DEBUG_SpawnExclusionZone"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 150.0
	sphere.height = 300.0
	sphere.radial_segments = 32
	sphere.rings = 16
	exclusion.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 0.0, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	exclusion.material_override = mat
	exclusion.global_position = Vector3(0.0, -48.0, 2.0)  # Ship spawn point in field space
	if get_tree() and get_tree().root:
		get_tree().root.add_child(exclusion)
	_collision_debug_meshes.append(exclusion)

func _disable_collision_debug() -> void:
	for mi: MeshInstance3D in _collision_debug_meshes:
		if is_instance_valid(mi):
			mi.queue_free()
	_collision_debug_meshes.clear()
	# Restore ship collision shape visibility
	for child: Node in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).visible = false
			break

func _create_convex_wireframe(shape: ConvexPolygonShape3D, color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var points: PackedVector3Array = shape.points
	if points.size() < 3:
		return mi
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = points
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(points.size() - 1):
		indices.append(i)
		indices.append(i + 1)
	indices.append(points.size() - 1)
	indices.append(0)
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	mi.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mi.material_override = mat
	return mi

func _compute_shape_aabb(shape: ConvexPolygonShape3D) -> AABB:
	var points: PackedVector3Array = shape.points
	if points.size() == 0:
		return AABB()
	var aabb: AABB = AABB(points[0], Vector3.ZERO)
	for p: Vector3 in points:
		aabb = aabb.expand(p)
	return aabb

## Smooth camera follower, FOV boost, and G-force shake effect.
func _update_camera_effects(delta: float) -> void:
	if not camera_node or not is_instance_valid(camera_node):
		return
	
	# FOV scaling based on speed, boost, and Wave Engine supercruise
	var target_fov := base_fov
	if wave_state == WaveState.ENGAGED:
		var wave_ratio := clampf(wave_current_speed / maxf(1.0, wave_max_speed), 0.0, 1.0)
		target_fov = lerp(boost_fov, wave_fov, wave_ratio)
	else:
		var speed_ratio := linear_velocity_vector.length() / maxf(1.0, max_boost_speed)
		target_fov = lerp(base_fov, boost_fov, speed_ratio)
	camera_node.fov = lerp(camera_node.fov, target_fov, delta * fov_lerp_speed)

	# Dynamic far clip: adjust based on distance to nearest celestial body.
	# In deep space: 5,000km far (enough for approach views, safe ratio).
	# Near a planet: increase to 3x planet radius + 500km so the planet is visible
	# from the wave-engine drop distance.
	var target_far: float = 5000000.0  # Default: 5,000 km
	if _nearest_planet_node != null and is_instance_valid(_nearest_planet_node):
		var dist_to_planet: float = global_position.distance_to(_nearest_planet_node.global_position)
		var planet_r: float = _nearest_planet_radius
		# If we're further than the current far clip, extend it to see the planet
		if dist_to_planet > target_far:
			target_far = dist_to_planet + planet_r
	# Clamp to safe ratio (far/near <= 5M:1 to avoid frustum culler errors)
	target_far = clampf(target_far, 100000.0, 5000000.0)
	camera_node.far = lerp(camera_node.far, target_far, delta * 2.0)
	if fpv_camera and is_instance_valid(fpv_camera):
		fpv_camera.far = camera_node.far

	# FPV Inertia & G-force head-lag
	if camera_mode == CameraMode.FPV and fpv_camera and is_instance_valid(fpv_camera):
		var local_accel := transform.basis.inverse() * (linear_velocity_vector - last_velocity) / maxf(0.0001, delta)
		var lag_offset := Vector3(
			clampf(-local_accel.x * 0.002, -0.06, 0.06),
			clampf(-local_accel.y * 0.002, -0.04, 0.04),
			clampf(-local_accel.z * 0.003, -0.08, 0.08)
		)
		var target_fpv_pos := fpv_base_pos + lag_offset
		fpv_camera.transform.origin = fpv_camera.transform.origin.lerp(target_fpv_pos, delta * 12.0)

	# Camera Shake (scaled by accessibility multiplier)
	if camera_shake_intensity > 0.0 and camera_shake_multiplier > 0.0:
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * camera_shake_intensity * max_camera_shake_offset * camera_shake_multiplier
		camera_node.transform.origin += offset * delta * 10.0
		camera_shake_intensity = move_toward(camera_shake_intensity, 0.0, delta * camera_shake_decay)

## Interacts with OrganTelemetry.gd to affect pilot biometrics during G-force shifts.
var _organ_telemetry_accum: float = 0.0
func _sync_organ_telemetry(delta: float) -> void:
	# Throttle to 10Hz during wave engine — biometric updates are not
	# perceptible at warp speeds and the call overhead adds up.
	if wave_state == WaveState.ENGAGED:
		_organ_telemetry_accum += delta
		if _organ_telemetry_accum < 0.1:
			return
		_organ_telemetry_accum = 0.0
	if not organ_telemetry_node:
		_find_organ_telemetry()
		if not organ_telemetry_node:
			return
	
	if organ_telemetry_node.has_method("on_g_force_changed"):
		organ_telemetry_node.call("on_g_force_changed", current_g_force, delta)
	elif organ_telemetry_node.has_method("record_g_force"):
		organ_telemetry_node.call("record_g_force", current_g_force)

func _find_organ_telemetry() -> void:
	if not is_inside_tree() or not get_tree():
		return
	if get_node_or_null("/root/OrganTelemetry"):
		organ_telemetry_node = get_node("/root/OrganTelemetry")
	elif get_tree().has_group("organ_telemetry"):
		var nodes := get_tree().get_nodes_in_group("organ_telemetry")
		if nodes.size() > 0:
			organ_telemetry_node = nodes[0]

func _setup_camera() -> void:
	# Check for mesh eye position if ProceduralBioMesh is attached
	var bio_mesh := get_node_or_null("ProceduralBioMesh")
	if bio_mesh and bio_mesh.has_method("get_pilot_eye_position"):
		fpv_base_pos = bio_mesh.call("get_pilot_eye_position")

	# Find or construct FPV Camera
	fpv_camera = get_node_or_null("CommandCenterFPVCamera") as Camera3D
	if not fpv_camera:
		fpv_camera = Camera3D.new()
		fpv_camera.name = "CommandCenterFPVCamera"
		fpv_camera.transform.origin = fpv_base_pos
		fpv_camera.fov = base_fov
		add_child(fpv_camera)

	# Find Chase Camera
	chase_camera = get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if not chase_camera:
		chase_camera = get_node_or_null("SpringArm3D/Camera3D") as Camera3D

	# Activate default camera mode
	set_camera_mode(camera_mode)

# ==============================================================================
# Atmospheric Flight Integration
# ==============================================================================
## Initializes the atmospheric flight model and resolves the PlanetDescentController.
func _init_atmospheric_integration() -> void:
	_atmospheric_model = AtmosphericFlightModel.new()
	_find_planet_descent_controller()
	_connect_descent_controller_signals()

## Searches the scene tree (and autoloads) for a PlanetDescentController instance.
func _find_planet_descent_controller() -> void:
	if not is_inside_tree() or not get_tree():
		return
	var tree := get_tree()
	if tree.root == null:
		return
	# Autoloads are direct children of the scene tree root.
	if tree.root.has_node("PlanetDescentController"):
		_planet_descent_controller = tree.root.get_node("PlanetDescentController")
		return
	# Fallback: search the scene tree by script class name.
	_planet_descent_controller = _find_node_by_script_class(tree.root, "PlanetDescentController")

## Recursively searches for a node whose script global name matches target_class.
func _find_node_by_script_class(start: Node, target_class: String) -> Node:
	if start == null:
		return null
	var scr: Script = start.get_script()
	if scr != null and scr.get_global_name() == target_class:
		return start
	for child in start.get_children():
		var found: Node = _find_node_by_script_class(child, target_class)
		if found != null:
			return found
	return null

## Connects to the PlanetDescentController's descent_state_changed signal.
func _connect_descent_controller_signals() -> void:
	if _planet_descent_controller == null or not is_instance_valid(_planet_descent_controller):
		return
	if not _planet_descent_controller.has_signal("descent_state_changed"):
		return
	if not _planet_descent_controller.is_connected("descent_state_changed", _on_descent_state_changed):
		_planet_descent_controller.descent_state_changed.connect(_on_descent_state_changed)

## Called when the PlanetDescentController changes descent state.
## Emits atmospheric_entry so visual/audio systems can react to layer transitions.
func _on_descent_state_changed(_old_state: int, new_state: int) -> void:
	atmospheric_entry.emit(new_state)

## Returns true if the given descent state places the ship inside a meaningful atmosphere.
## States: THERMOSPHERE(2), TROPOSPHERE(3), SURFACE_APPROACH(4), ABORT_ASCENT(8), GAS_GIANT_DESCENT(9).
func _is_in_atmosphere(descent_state: int) -> bool:
	match descent_state:
		2, 3, 4, 8, 9:
			return true
		_:
			return false

## Finds the nearest planet node in the "targets" group and caches its archetype/radius.
func _update_nearest_planet() -> void:
	_nearest_planet_node = null
	var tree: SceneTree = null
	if is_inside_tree() and get_tree():
		tree = get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var my_pos: Vector3 = global_position if is_inside_tree() else position
	var nearest_dist: float = INF
	var targets: Array[Node] = tree.get_nodes_in_group("targets")
	for t in targets:
		if not is_instance_valid(t) or not (t is Node3D):
			continue
		var arch: Variant = t.get("archetype")
		if arch == null:
			continue
		var t_node: Node3D = t as Node3D
		var t_pos: Vector3 = t_node.global_position if (t_node.is_inside_tree() and is_inside_tree()) else t_node.position
		var dist: float = my_pos.distance_to(t_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			_nearest_planet_node = t_node
			_nearest_planet_archetype = int(arch)
			var r: Variant = t_node.get("radius_m")
			_nearest_planet_radius = float(r) if r != null else 100.0

	# Notify PlanetEntryManager of the nearest planet for proximity tracking so
	# the flight HUD can render a directional marker toward it.
	if _nearest_planet_node != null:
		var entry_mgr: Node = null
		if tree != null and tree.root != null:
			entry_mgr = tree.root.get_node_or_null("/root/PlanetEntryManager")
		if entry_mgr != null and entry_mgr.has_method("set_nearest_planet"):
			entry_mgr.call("set_nearest_planet", _nearest_planet_node, nearest_dist)

## Main atmospheric physics handler. Computes and applies aerodynamic lift/drag forces
## additively to the existing Newtonian thrust when the ship is inside a planet's atmosphere.
## Falls back to pure space physics when no atmosphere model, no nearby planet, or no
## descent controller is available.
func _handle_atmospheric_physics(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Skip during wave engine supercruise — the ship rides a warp bubble (no aero).
	if wave_state == WaveState.ENGAGED or wave_state == WaveState.CHARGING:
		_current_heating_intensity = 0.0
		_current_stall_factor = 0.0
		return
	# Lazy-init the atmospheric model if it wasn't created in _ready.
	if _atmospheric_model == null:
		_atmospheric_model = AtmosphericFlightModel.new()
	# Lazily resolve the descent controller if it wasn't available at _ready time.
	if _planet_descent_controller == null or not is_instance_valid(_planet_descent_controller):
		_find_planet_descent_controller()
		_connect_descent_controller_signals()
	# Find the nearest planet to compute altitude and archetype.
	_update_nearest_planet()
	if _nearest_planet_node == null:
		_current_atmosphere_layer = AtmosphericFlightModel.Layer.EXOSPHERE
		_current_heating_intensity = 0.0
		_current_stall_factor = 0.0
		_altitude_above_surface = 0.0
		return
	# Compute altitude above the planet surface.
	var my_pos: Vector3 = global_position if is_inside_tree() else position
	var planet_center: Vector3 = _nearest_planet_node.global_position if _nearest_planet_node.is_inside_tree() else _nearest_planet_node.position
	var dist_to_center: float = my_pos.distance_to(planet_center)
	_altitude_above_surface = maxf(0.0, dist_to_center - _nearest_planet_radius)
	# Query the descent controller for the current descent state.
	var descent_state: int = 0 # PlanetDescentController.DescentState.ORBITAL
	var has_controller: bool = false
	if _planet_descent_controller != null and is_instance_valid(_planet_descent_controller):
		has_controller = true
		if _planet_descent_controller.has_method("get_current_state"):
			descent_state = _planet_descent_controller.get_current_state()
		# Feed altitude and vertical speed back to the descent controller so its
		# state machine can evaluate transitions.
		if _planet_descent_controller.has_method("update_altitude"):
			_planet_descent_controller.update_altitude(my_pos, planet_center, _nearest_planet_radius, 0.0)
		if _planet_descent_controller.has_method("set_vertical_speed"):
			var radial_dir: Vector3 = (my_pos - planet_center).normalized()
			var v_speed: float = linear_velocity_vector.dot(radial_dir)
			_planet_descent_controller.set_vertical_speed(v_speed)
	# Takeoff detection: when the ship is LANDED and the player applies upward
	# thrust, notify the descent controller so it transitions back to atmospheric
	# flight. The PlanetDescentController.takeoff_complete signal then cascades to
	# the LandingSequenceController (cinematic takeoff animation) and
	# PlanetEntryManager (character/camera cleanup). This must run before the
	# in_atmosphere early-out below, since LANDED is not classified as an
	# atmospheric layer by _is_in_atmosphere().
	if has_controller and _planet_descent_controller.has_method("notify_takeoff_thrust"):
		# PlanetDescentController.DescentState.LANDED == 5
		if descent_state == 5:
			var up_thrust: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_R) or simulated_thrust.y > 0.1
			if up_thrust:
				_planet_descent_controller.notify_takeoff_thrust(1.0)
	# Determine whether the ship is in a meaningful atmospheric layer.
	var in_atmosphere: bool = false
	if has_controller:
		in_atmosphere = _is_in_atmosphere(descent_state)
	else:
		# Fallback when no descent controller is available: use the aero model's
		# layer computation directly.
		var fallback_layer: int = _atmospheric_model.get_atmosphere_layer(
			_altitude_above_surface, _nearest_planet_radius, _nearest_planet_archetype)
		in_atmosphere = fallback_layer != AtmosphericFlightModel.Layer.EXOSPHERE
	if not in_atmosphere:
		_current_atmosphere_layer = AtmosphericFlightModel.Layer.EXOSPHERE
		_current_heating_intensity = 0.0
		_current_stall_factor = 0.0
		return
	# Compute aerodynamic forces from the atmospheric model.
	var ship_forward: Vector3 = -transform.basis.z.normalized()
	var ship_up: Vector3 = transform.basis.y.normalized()
	var aero_result: Dictionary = _atmospheric_model.compute_aero_forces(
		linear_velocity_vector, ship_forward, ship_up,
		_altitude_above_surface, _nearest_planet_archetype, _nearest_planet_radius
	)
	var lift_force: Vector3 = aero_result.get("lift", Vector3.ZERO)
	var drag_force: Vector3 = aero_result.get("drag", Vector3.ZERO)
	var stall_factor: float = float(aero_result.get("stall_factor", 0.0))
	var layer: int = int(aero_result.get("layer", AtmosphericFlightModel.Layer.EXOSPHERE))
	_current_atmosphere_layer = layer
	_current_stall_factor = stall_factor
	# Scale forces by user-configured aerodynamic coefficients and reference areas.
	var wing_scale: float = wing_area / maxf(1.0, AtmosphericFlightModel.REFERENCE_WING_AREA_M2)
	var cross_scale: float = cross_section_area / maxf(1.0, AtmosphericFlightModel.REFERENCE_CROSS_SECTION_M2)
	var lift_scale: float = wing_scale * (lift_coefficient / maxf(0.01, AtmosphericFlightModel.MAX_LIFT_COEFFICIENT))
	var drag_scale: float = cross_scale * (drag_coefficient / maxf(0.01, AtmosphericFlightModel.BASE_DRAG_COEFFICIENT))
	lift_force *= lift_scale
	drag_force *= drag_scale
	# Stall effect: turbulent airflow reduces control authority (damps angular velocity).
	if stall_factor > 0.0:
		var stall_damp: float = clampf(stall_factor * delta * 2.0, 0.0, 1.0)
		angular_velocity_vector = angular_velocity_vector.lerp(Vector3.ZERO, stall_damp)
	# Apply aero forces as acceleration — additive to the existing Newtonian thrust.
	var aero_force: Vector3 = lift_force + drag_force
	var aero_accel: Vector3 = aero_force / maxf(1.0, vessel_mass_kg)
	linear_velocity_vector += aero_accel * delta
	# Compute heating intensity for visual/audio systems.
	var heating: float = _atmospheric_model.get_heating_intensity(
		linear_velocity_vector.length(), _altitude_above_surface, _nearest_planet_archetype)
	_current_heating_intensity = lerp(_current_heating_intensity, heating, clampf(delta * 4.0, 0.0, 1.0))
	heating_intensity_changed.emit(_current_heating_intensity)
	# Emit stall warning for HUD/audio when the ship is stalling.
	if stall_factor > 0.1:
		stall_warning.emit(stall_factor)

## Returns the current altitude above the nearest planet's surface in meters.
func get_altitude_above_surface() -> float:
	return _altitude_above_surface

## Returns the current atmospheric layer index (AtmosphericFlightModel.Layer enum).
func get_current_atmosphere_layer() -> int:
	return _current_atmosphere_layer

## Returns the current heating intensity (0.0 to 1.0) for visual/audio systems.
func get_current_heating_intensity() -> float:
	return _current_heating_intensity

## Returns the current stall factor (0.0 = clean, 1.0 = fully stalled).
func get_current_stall_factor() -> float:
	return _current_stall_factor
