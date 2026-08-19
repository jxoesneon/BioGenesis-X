# ==============================================================================
# PlanetDescentController.gd - 4-Layer Planetary Descent State Machine
# BioGenesis-X Atmospheric Entry & Surface Landing Orchestrator
# ==============================================================================
# Manages the seamless transition from orbital space flight to planet surface
# landing across 4 atmospheric layers (exosphere, thermosphere, troposphere,
# surface approach). Supports all 8 planet archetypes including gas giants
# (no solid surface) and oceanic worlds (splashdown / submersible diving).
#
# Designed as an autoload-ready singleton. Add to project.godot autoloads:
#   PlanetDescentController="*res://scripts/PlanetDescentController.gd"
#
# STATE DIAGRAM:
#   ORBITAL -> EXOSPHERE_ENTRY -> THERMOSPHERE -> TROPOSPHERE -> SURFACE_APPROACH
#                                                              -> LANDED -> ON_FOOT
#                                                              -> SUBMERSIBLE (oceanic)
#   Gas giants: TROPOSPHERE -> GAS_GIANT_DESCENT (endless, no landing)
#   Any state -> ABORT_ASCENT -> ORBITAL
# ==============================================================================
extends Node

# ------------------------------------------------------------------------------
# Planet Archetype Catalog (mirrors ProceduralPlanet archetypes)
# ------------------------------------------------------------------------------
enum PlanetArchetype {
	MOLTEN,            # 0 - Volcanic hellscape, thick toxic atmosphere, extreme heating
	METALLIC_BARREN,   # 1 - Airless/trace atmosphere, no drag, hard landing
	DESERT_ARID,       # 2 - Thin dusty atmosphere, moderate heating
	TERRAN_OCEANIC,    # 3 - Earth-like, water splashdown possible
	ICE_WORLD,         # 4 - Cryogenic atmosphere, low heating, slippery surface
	GAS_GIANT_JOVIAN,  # 5 - No solid surface, endless deep descent
	GAS_GIANT_ICE,     # 6 - No solid surface, cryogenic deep descent
	RADIOTROPHIC_BIO,  # 7 - Bioluminescent biosphere, dense organic atmosphere
}

# ------------------------------------------------------------------------------
# Descent State Machine
# ------------------------------------------------------------------------------
enum DescentState {
	ORBITAL,          ## In space near planet, normal space flight
	EXOSPHERE_ENTRY,  ## Crossing the Karman line, first atmospheric contact
	THERMOSPHERE,     ## Thin atmosphere, heating begins, slight drag
	TROPOSPHERE,      ## Full atmosphere, aerodynamic flight, clouds, weather
	SURFACE_APPROACH, ## Near ground, preparing to land
	LANDED,           ## On the surface, ship is parked
	ON_FOOT,          ## Player has exited ship, walking on surface
	SUBMERSIBLE,      ## Ship has splashed down and is diving underwater
	ABORT_ASCENT,     ## Emergency abort - climbing back to orbit
	GAS_GIANT_DESCENT,## Special state for gas giants - no landing, just deep diving
}

# ------------------------------------------------------------------------------
# Atmospheric Layer Index (for shader / audio coordination)
# ------------------------------------------------------------------------------
enum AtmosphereLayer {
	SPACE,        ## 0 - vacuum
	EXOSPHERE,    ## 1
	THERMOSPHERE, ## 2
	TROPOSPHERE,  ## 3
	SURFACE,      ## 4
	UNDERWATER,   ## 5
	GAS_GIANT_DEEP, ## 6
}

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal descent_state_changed(old_state: int, new_state: int)
signal layer_transition(new_layer: int, layer_name: String)
signal landing_complete(planet_archetype: int, position: Vector3)
signal takeoff_complete()
signal entered_water(depth_m: float)
signal exited_water()
signal player_exited_ship()
signal player_entered_ship()
signal heating_warning(intensity: float)
signal stall_warning(stall_factor: float)
signal landing_assist_engaged(active: bool)
signal surface_lock_engaged(locked: bool)
signal gas_giant_pressure_warning(pressure_bar: float)
## Emitted when the atmospheric density (0..1+) changes significantly during
## descent. Consumed by DescentAudioController for audio muffling/roaring.
signal atmosphere_density_changed(density: float)

# ------------------------------------------------------------------------------
# Tunable Parameters
# ------------------------------------------------------------------------------
@export_group("Descent Thresholds (multipliers of atmosphere_thickness)")
@export var exosphere_entry_multiplier: float = 1.5   ## ORBITAL -> EXOSPHERE_ENTRY (1.5x atmo)
@export var thermosphere_entry_multiplier: float = 0.8 ## EXOSPHERE_ENTRY -> THERMOSPHERE
@export var troposphere_entry_multiplier: float = 0.3 ## THERMOSPHERE -> TROPOSPHERE
@export var surface_approach_altitude_m: float = 10000.0 ## 10km — TROPOSPHERE -> SURFACE_APPROACH (real-scale)

@export_group("Landing Parameters")
@export var landing_altitude_threshold_m: float = 10.0 ## 10m above surface for landing
@export var landing_vertical_speed_threshold: float = 5.0 ## 5 m/s max vertical speed for landing
@export var landing_align_speed: float = 2.5         ## rad/s surface-normal alignment
@export var landing_vertical_damp: float = 3.0       ## vertical velocity damping rate
@export var landing_gear_deploy_altitude_m: float = 120.0

@export_group("Takeoff Parameters")
@export var takeoff_thrust_threshold: float = 0.35   ## thrust input fraction to trigger takeoff
@export var takeoff_release_altitude_m: float = 80.0 ## altitude where takeoff assist releases

@export_group("Input Actions")
@export var exit_ship_action: StringName = &"interact"
@export var enter_ship_action: StringName = &"interact"
@export var abort_ascent_action: StringName = &"abort_descent"

@export_group("Heating & Drag")
@export var max_heating_intensity: float = 1.0
@export var heating_rate_thermosphere: float = 0.4
@export var heating_rate_troposphere: float = 0.7
@export var stall_speed_threshold: float = 12.0      ## below this speed in atmosphere = stall risk

@export_group("Gas Giant Descent")
@export var gas_giant_max_pressure_bar: float = 80.0
@export var gas_giant_pressure_rate: float = 1.5     ## bar per second of descent
@export var gas_giant_crush_pressure_bar: float = 60.0 ## pressure that forces abort

@export_group("Submersible")
@export var max_dive_depth_m: float = 400.0
@export var underwater_drag: float = 1.8

@export_group("Transition Smoothing")
@export var state_transition_blend_time: float = 0.6 ## seconds for physics blend

@export_group("Atmosphere Scattering")
## Rate at which atmosphere intensity/blend/density smooth toward their
## per-state targets (higher = snappier). Applied each physics frame.
@export var atmosphere_smoothing_rate: float = 2.5
## Density change threshold (0..1) above which atmosphere_density_changed is
## re-emitted, to avoid flooding signal consumers every physics frame.
@export var atmosphere_density_emit_threshold: float = 0.02

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _current_state: int = DescentState.ORBITAL
var _previous_state: int = DescentState.ORBITAL
var _state_timer: float = 0.0
var _transition_blend: float = 0.0 ## 0..1 progress of current transition blend
var _is_transitioning: bool = false

var _current_layer: int = AtmosphereLayer.SPACE

# Altitude tracking
var _altitude_m: float = 0.0
var _previous_altitude_m: float = 0.0
var _vertical_speed_ms: float = 0.0
var _terrain_height_m: float = 0.0
var _planet_radius_m: float = 0.0
var _distance_to_planet_center_m: float = 0.0

# Descent progress (0.0 = orbit, 1.0 = surface) for shader uniforms
var _descent_progress: float = 0.0

# Atmosphere scattering drive (0..1). Tracks how much near-field O'Neil
# scattering should be visible, blended smoothly each physics frame toward a
# per-state target. Fed to ProceduralPlanet.set_atmosphere_intensity().
var _atmosphere_intensity: float = 0.0
# Far/near-field blend (0..1). 0 = far-field EFA dominates (space), 1 =
# near-field O'Neil dominates (atmosphere/surface). Fed to
# ProceduralPlanet.set_atmosphere_blend().
var _atmosphere_blend: float = 0.0
# Atmospheric density (0..1+) reported to DescentAudioController for audio
# muffling. Derived from descent progress and archetype pressure.
var _atmosphere_density: float = 0.0

# Star (sun) world position for atmosphere scattering sun-direction updates.
# Set via set_star_position(); defaults to a direction along +Z so the
# atmosphere has a valid light vector before the star system manager resolves.
var _star_position: Vector3 = Vector3(0.0, 0.0, 1.0e9)
var _has_star_position: bool = false

# Target planet
var _target_planet: Node3D = null
var _target_archetype: int = PlanetArchetype.TERRAN_OCEANIC
var _target_has_water: bool = false
var _atmosphere_thickness_m: float = 0.0
var _has_target: bool = false

# Per-archetype descent profile
var _profile: DescentProfile = null

# Landing assist
var _landing_assist_active: bool = false
var _surface_normal: Vector3 = Vector3.UP
var _surface_lock_position: Vector3 = Vector3.ZERO
var _surface_locked: bool = false

# Takeoff assist
var _takeoff_assist_active: bool = false

# Water / submersible
var _underwater_depth_m: float = 0.0
var _is_underwater: bool = false

# Gas giant
var _gas_giant_pressure_bar: float = 0.0
var _gas_giant_descent_depth_m: float = 0.0

# Heating
var _current_heating: float = 0.0
var _current_stall_factor: float = 0.0
var _last_emitted_stall_factor: float = 0.0

# Integration hooks (resolved lazily from scene tree)
var _flight_controller: Node = null
var _bio_audio_director: Node = null
var _bio_audio_synth: Node = null

# Cached layer names for signals
const _LAYER_NAMES: PackedStringArray = [
	"Space", "Exosphere", "Thermosphere", "Troposphere",
	"Surface", "Underwater", "Gas Giant Deep",
]

# ------------------------------------------------------------------------------
# Descent Profile - per-archetype parameters
# ------------------------------------------------------------------------------
class DescentProfile:
	var archetype: int = PlanetArchetype.TERRAN_OCEANIC
	var atmosphere_thickness_m: float = 60000.0
	var has_solid_surface: bool = true
	var has_water: bool = false
	var heating_coefficient: float = 1.0
	var drag_coefficient: float = 1.0
	var landing_difficulty: float = 1.0
	var surface_gravity_g: float = 1.0
	var pressure_surface_bar: float = 1.0
	var is_gas_giant: bool = false

	func _init(p_archetype: int) -> void:
		archetype = p_archetype
		_apply_archetype_defaults()

	func _apply_archetype_defaults() -> void:
		match archetype:
			PlanetArchetype.MOLTEN:
				atmosphere_thickness_m = 90000.0
				has_solid_surface = true
				has_water = false
				heating_coefficient = 2.4
				drag_coefficient = 1.6
				landing_difficulty = 1.8
				surface_gravity_g = 1.4
				pressure_surface_bar = 4.5
			PlanetArchetype.METALLIC_BARREN:
				atmosphere_thickness_m = 8000.0
				has_solid_surface = true
				has_water = false
				heating_coefficient = 0.2
				drag_coefficient = 0.05
				landing_difficulty = 1.5
				surface_gravity_g = 0.9
				pressure_surface_bar = 0.001
			PlanetArchetype.DESERT_ARID:
				atmosphere_thickness_m = 35000.0
				has_solid_surface = true
				has_water = false
				heating_coefficient = 1.1
				drag_coefficient = 0.7
				landing_difficulty = 1.2
				surface_gravity_g = 0.85
				pressure_surface_bar = 0.6
			PlanetArchetype.TERRAN_OCEANIC:
				atmosphere_thickness_m = 60000.0
				has_solid_surface = true
				has_water = true
				heating_coefficient = 1.0
				drag_coefficient = 1.0
				landing_difficulty = 1.0
				surface_gravity_g = 1.0
				pressure_surface_bar = 1.0
			PlanetArchetype.ICE_WORLD:
				atmosphere_thickness_m = 28000.0
				has_solid_surface = true
				has_water = false
				heating_coefficient = 0.4
				drag_coefficient = 0.8
				landing_difficulty = 1.3
				surface_gravity_g = 0.7
				pressure_surface_bar = 0.5
			PlanetArchetype.GAS_GIANT_JOVIAN:
				atmosphere_thickness_m = 200000.0
				has_solid_surface = false
				has_water = false
				heating_coefficient = 1.8
				drag_coefficient = 2.2
				landing_difficulty = 99.0
				surface_gravity_g = 2.5
				pressure_surface_bar = 1.0
				is_gas_giant = true
			PlanetArchetype.GAS_GIANT_ICE:
				atmosphere_thickness_m = 160000.0
				has_solid_surface = false
				has_water = false
				heating_coefficient = 0.9
				drag_coefficient = 1.9
				landing_difficulty = 99.0
				surface_gravity_g = 1.4
				pressure_surface_bar = 1.0
				is_gas_giant = true
			PlanetArchetype.RADIOTROPHIC_BIO:
				atmosphere_thickness_m = 75000.0
				has_solid_surface = true
				has_water = false
				heating_coefficient = 1.3
				drag_coefficient = 1.4
				landing_difficulty = 1.1
				surface_gravity_g = 1.1
				pressure_surface_bar = 1.8
			_:
				atmosphere_thickness_m = 60000.0
				has_solid_surface = true
				has_water = false
				heating_coefficient = 1.0
				drag_coefficient = 1.0
				landing_difficulty = 1.0
				surface_gravity_g = 1.0
				pressure_surface_bar = 1.0

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	_profile = DescentProfile.new(PlanetArchetype.TERRAN_OCEANIC)
	_atmosphere_thickness_m = _profile.atmosphere_thickness_m

func _process(delta: float) -> void:
	_state_timer += delta
	if _is_transitioning:
		_transition_blend = minf(_transition_blend + delta / state_transition_blend_time, 1.0)
		if _transition_blend >= 1.0:
			_is_transitioning = false

func _physics_process(delta: float) -> void:
	if not _has_target:
		return
	_update_vertical_speed(delta)
	_update_heating(delta)
	_update_stall_warning()
	_update_gas_giant_pressure(delta)
	_update_landing_assist(delta)
	_update_takeoff_assist(delta)
	_update_descent_progress()
	_update_atmosphere_descent(delta)
	_evaluate_state_transitions()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_event: InputEventKey = event
		if key_event.is_action(exit_ship_action):
			_handle_exit_ship_input()
		elif key_event.is_action(enter_ship_action):
			_handle_enter_ship_input()
		elif key_event.is_action(abort_ascent_action):
			trigger_abort_ascent()

# ------------------------------------------------------------------------------
# Public API - Target Planet Management
# ------------------------------------------------------------------------------
## Sets the planet the player is descending toward. Resolves integration hooks.
func set_target_planet(planet_node: Node3D, archetype: int, radius_m: float, has_water: bool) -> void:
	_target_planet = planet_node
	_target_archetype = archetype
	_target_has_water = has_water
	_planet_radius_m = radius_m
	_profile = DescentProfile.new(archetype)
	_profile.has_water = has_water
	_atmosphere_thickness_m = _profile.atmosphere_thickness_m
	_has_target = true
	_resolve_integration_hooks()
	_reset_descent_state()

## Clears the current target planet (e.g. when leaving vicinity).
func clear_target_planet() -> void:
	_target_planet = null
	_has_target = false
	_target_has_water = false
	_atmosphere_thickness_m = 0.0
	_altitude_m = 0.0
	_previous_altitude_m = 0.0
	_vertical_speed_ms = 0.0
	_descent_progress = 0.0
	_is_underwater = false
	_underwater_depth_m = 0.0
	_gas_giant_pressure_bar = 0.0
	_gas_giant_descent_depth_m = 0.0
	_landing_assist_active = false
	_takeoff_assist_active = false
	_surface_locked = false
	_current_heating = 0.0
	_current_stall_factor = 0.0
	_last_emitted_stall_factor = 0.0
	_atmosphere_intensity = 0.0
	_atmosphere_blend = 0.0
	_atmosphere_density = 0.0
	_set_state(DescentState.ORBITAL)

## Returns whether a target planet is currently set.
func has_target_planet() -> bool:
	return _has_target

## Returns the current target planet node, or null.
func get_target_planet() -> Node3D:
	return _target_planet

## Returns the current target archetype.
func get_target_archetype() -> int:
	return _target_archetype

# ------------------------------------------------------------------------------
# Public API - Altitude Tracking
# ------------------------------------------------------------------------------
## Updates altitude from the ship's world position relative to the planet.
## terrain_height is the height of terrain above sea level at the ship's location.
func update_altitude(ship_position: Vector3, planet_center: Vector3, planet_radius: float, terrain_height: float) -> void:
	_distance_to_planet_center_m = ship_position.distance_to(planet_center)
	_terrain_height_m = terrain_height
	var surface_radius: float = planet_radius + terrain_height
	_previous_altitude_m = _altitude_m
	_altitude_m = _distance_to_planet_center_m - surface_radius
	# Vertical speed derived from altitude delta (caller may override via set_vertical_speed)
	# Recomputed in physics step via _update_vertical_speed; here we store raw altitude.

## Explicitly sets the vertical speed (m/s) if the caller has a more accurate source.
func set_vertical_speed(speed_ms: float) -> void:
	_vertical_speed_ms = speed_ms

## Returns the current altitude above terrain in meters.
func get_altitude_m() -> float:
	return _altitude_m

## Returns the current vertical speed in m/s.
func get_vertical_speed_ms() -> float:
	return _vertical_speed_ms

# ------------------------------------------------------------------------------
# Public API - Descent Progress
# ------------------------------------------------------------------------------
## Returns normalized descent progress (0.0 = orbit, 1.0 = surface) for shaders.
func get_descent_progress() -> float:
	return _descent_progress

## Returns the current near-field atmosphere scattering intensity (0..1).
func get_atmosphere_intensity() -> float:
	return _atmosphere_intensity

## Returns the current far/near-field atmosphere blend (0..1).
func get_atmosphere_blend() -> float:
	return _atmosphere_blend

## Returns the current atmospheric density (0..1+) for audio/visual feedback.
## Derived from descent progress and archetype surface pressure.
func get_atmosphere_density() -> float:
	return _atmosphere_density

## Sets the star (sun) world-space position so the atmosphere scattering sun
## direction can be updated each frame relative to the target planet. Called by
## the star system manager / UniverseManager when a system loads.
func set_star_position(star_world_pos: Vector3) -> void:
	_star_position = star_world_pos
	_has_star_position = true

## Returns the current descent state.
func get_current_state() -> int:
	return _current_state

## Returns the previous descent state.
func get_previous_state() -> int:
	return _previous_state

## Returns time spent in the current state (seconds).
func get_state_timer() -> float:
	return _state_timer

## Returns the current atmosphere layer index.
func get_current_layer() -> int:
	return _current_layer

## Returns the current heating intensity (0..1+).
func get_heating_intensity() -> float:
	return _current_heating

## Returns the current stall factor (0..1, 1 = full stall).
func get_stall_factor() -> float:
	return _current_stall_factor

## Returns true if the ship is currently underwater.
func is_underwater() -> bool:
	return _is_underwater

## Returns the current underwater depth in meters.
func get_underwater_depth_m() -> float:
	return _underwater_depth_m

## Returns the current gas giant atmospheric pressure in bar.
func get_gas_giant_pressure_bar() -> float:
	return _gas_giant_pressure_bar

## Returns true if landing assist is currently active.
func is_landing_assist_active() -> bool:
	return _landing_assist_active

## Returns true if the ship is surface-locked (landed).
func is_surface_locked() -> bool:
	return _surface_locked

# ------------------------------------------------------------------------------
# Public API - Landing / Takeoff Control
# ------------------------------------------------------------------------------
## Sets the surface normal at the landing site (up vector for alignment).
func set_surface_normal(normal: Vector3) -> void:
	_surface_normal = normal.normalized()

## Sets the surface lock position (where the ship is parked).
func set_surface_lock_position(position: Vector3) -> void:
	_surface_lock_position = position

## Returns the locked surface position.
func get_surface_lock_position() -> Vector3:
	return _surface_lock_position

## Returns the surface normal at the landing site.
func get_surface_normal() -> Vector3:
	return _surface_normal

## Notifies the controller that the ship has splashed down into water.
func notify_splashdown(depth_m: float) -> void:
	if not _has_target:
		return
	if not _profile.has_water and not _target_has_water:
		return
	_is_underwater = true
	_underwater_depth_m = depth_m
	entered_water.emit(depth_m)
	if _current_state == DescentState.TROPOSPHERE:
		_set_state(DescentState.SUBMERSIBLE)

## Notifies the controller that the ship has surfaced from water.
func notify_surfaced() -> void:
	if not _is_underwater:
		return
	_is_underwater = false
	_underwater_depth_m = 0.0
	exited_water.emit()
	if _current_state == DescentState.SUBMERSIBLE:
		_set_state(DescentState.TROPOSPHERE)

## Updates the current underwater depth (called by the ship each physics frame).
func update_underwater_depth(depth_m: float) -> void:
	_underwater_depth_m = depth_m
	if _is_underwater and depth_m <= 0.0:
		notify_surfaced()

## Triggers an emergency abort - climbs back to orbit.
func trigger_abort_ascent() -> void:
	if _current_state == DescentState.ORBITAL:
		return
	if _current_state == DescentState.ABORT_ASCENT:
		return
	_set_state(DescentState.ABORT_ASCENT)
	_landing_assist_active = false
	_takeoff_assist_active = false
	_surface_locked = false
	landing_assist_engaged.emit(false)
	surface_lock_engaged.emit(false)

## Forces a state change (for cinematic / debug use).
func force_state(new_state: int) -> void:
	_set_state(new_state)

# ------------------------------------------------------------------------------
# State Machine Core
# ------------------------------------------------------------------------------
func _set_state(new_state: int) -> void:
	if new_state == _current_state:
		return
	_exit_state(_current_state)
	_previous_state = _current_state
	_current_state = new_state
	_state_timer = 0.0
	_transition_blend = 0.0
	_is_transitioning = true
	_enter_state(new_state)
	descent_state_changed.emit(_previous_state, new_state)

func _enter_state(state: int) -> void:
	match state:
		DescentState.ORBITAL:
			_set_layer(AtmosphereLayer.SPACE)
			_landing_assist_active = false
			_takeoff_assist_active = false
			_surface_locked = false
			landing_assist_engaged.emit(false)
			surface_lock_engaged.emit(false)
		DescentState.EXOSPHERE_ENTRY:
			_set_layer(AtmosphereLayer.EXOSPHERE)
		DescentState.THERMOSPHERE:
			_set_layer(AtmosphereLayer.THERMOSPHERE)
		DescentState.TROPOSPHERE:
			_set_layer(AtmosphereLayer.TROPOSPHERE)
		DescentState.SURFACE_APPROACH:
			_set_layer(AtmosphereLayer.SURFACE)
			_activate_landing_assist()
		DescentState.LANDED:
			_surface_locked = true
			surface_lock_engaged.emit(true)
			landing_complete.emit(_target_archetype, _surface_lock_position)
		DescentState.ON_FOOT:
			player_exited_ship.emit()
		DescentState.SUBMERSIBLE:
			_set_layer(AtmosphereLayer.UNDERWATER)
		DescentState.ABORT_ASCENT:
			_takeoff_assist_active = true
		DescentState.GAS_GIANT_DESCENT:
			_set_layer(AtmosphereLayer.GAS_GIANT_DEEP)
		_:
			push_warning("[PlanetDescentController] Unknown descent state entered: %d" % state)

func _exit_state(state: int) -> void:
	match state:
		DescentState.LANDED:
			_surface_locked = false
			surface_lock_engaged.emit(false)
		DescentState.ON_FOOT:
			player_entered_ship.emit()
		DescentState.SUBMERSIBLE:
			_is_underwater = false
			_underwater_depth_m = 0.0
			exited_water.emit()
		DescentState.SURFACE_APPROACH:
			_landing_assist_active = false
			landing_assist_engaged.emit(false)
		DescentState.ABORT_ASCENT:
			_takeoff_assist_active = false
		_:
			push_warning("[PlanetDescentController] Unknown descent state exited: %d" % state)

func _set_layer(new_layer: int) -> void:
	if new_layer == _current_layer:
		return
	_current_layer = new_layer
	var layer_name: String = "Unknown"
	if new_layer >= 0 and new_layer < _LAYER_NAMES.size():
		layer_name = _LAYER_NAMES[new_layer]
	layer_transition.emit(new_layer, layer_name)

# ------------------------------------------------------------------------------
# State Transition Evaluation
# ------------------------------------------------------------------------------
func _evaluate_state_transitions() -> void:
	if not _has_target:
		return
	# Gas giants never reach a solid surface.
	if _profile.is_gas_giant:
		# Loop to allow multi-state transitions in a single frame when the
		# ship is moving fast enough to cross multiple atmosphere layers.
		var prev_state: int = -1
		for _iteration: int in range(8):
			if _current_state == prev_state:
				break
			prev_state = _current_state
			_evaluate_gas_giant_transitions()
		return
	# Loop to allow multi-state transitions in a single frame when the
	# ship is moving fast enough to cross multiple atmosphere layers.
	var prev_state2: int = -1
	for _iteration2: int in range(8):
		if _current_state == prev_state2:
			break
		prev_state2 = _current_state
		_evaluate_normal_transitions()

func _evaluate_normal_transitions() -> void:
	match _current_state:
		DescentState.ORBITAL:
			if _altitude_m < _atmosphere_thickness_m * exosphere_entry_multiplier:
				_set_state(DescentState.EXOSPHERE_ENTRY)
		DescentState.EXOSPHERE_ENTRY:
			if _altitude_m < _atmosphere_thickness_m * thermosphere_entry_multiplier:
				_set_state(DescentState.THERMOSPHERE)
			elif _altitude_m >= _atmosphere_thickness_m * exosphere_entry_multiplier:
				_set_state(DescentState.ORBITAL)
		DescentState.THERMOSPHERE:
			if _altitude_m < _atmosphere_thickness_m * troposphere_entry_multiplier:
				_set_state(DescentState.TROPOSPHERE)
			elif _altitude_m >= _atmosphere_thickness_m * thermosphere_entry_multiplier:
				_set_state(DescentState.EXOSPHERE_ENTRY)
		DescentState.TROPOSPHERE:
			if _altitude_m < surface_approach_altitude_m:
				_set_state(DescentState.SURFACE_APPROACH)
			elif _altitude_m >= _atmosphere_thickness_m * troposphere_entry_multiplier:
				_set_state(DescentState.THERMOSPHERE)
		DescentState.SURFACE_APPROACH:
			if _altitude_m >= surface_approach_altitude_m:
				_set_state(DescentState.TROPOSPHERE)
			elif _altitude_m < landing_altitude_threshold_m and absf(_vertical_speed_ms) < landing_vertical_speed_threshold:
				_set_state(DescentState.LANDED)
		DescentState.LANDED:
			if _takeoff_assist_active and _altitude_m > takeoff_release_altitude_m:
				_set_state(DescentState.TROPOSPHERE)
				takeoff_complete.emit()
		DescentState.ABORT_ASCENT:
			if _altitude_m > _atmosphere_thickness_m * exosphere_entry_multiplier:
				_set_state(DescentState.ORBITAL)
		DescentState.SUBMERSIBLE:
			if not _is_underwater:
				_set_state(DescentState.TROPOSPHERE)
		_:
			push_warning("[PlanetDescentController] Unknown state in transition evaluation: %d" % _current_state)

func _evaluate_gas_giant_transitions() -> void:
	match _current_state:
		DescentState.ORBITAL:
			if _altitude_m < _atmosphere_thickness_m * exosphere_entry_multiplier:
				_set_state(DescentState.EXOSPHERE_ENTRY)
		DescentState.EXOSPHERE_ENTRY:
			if _altitude_m < _atmosphere_thickness_m * thermosphere_entry_multiplier:
				_set_state(DescentState.THERMOSPHERE)
			elif _altitude_m >= _atmosphere_thickness_m * exosphere_entry_multiplier:
				_set_state(DescentState.ORBITAL)
		DescentState.THERMOSPHERE:
			if _altitude_m < _atmosphere_thickness_m * troposphere_entry_multiplier:
				_set_state(DescentState.TROPOSPHERE)
			elif _altitude_m >= _atmosphere_thickness_m * thermosphere_entry_multiplier:
				_set_state(DescentState.EXOSPHERE_ENTRY)
		DescentState.TROPOSPHERE:
			# Gas giants transition to endless descent once below surface approach altitude.
			if _altitude_m < surface_approach_altitude_m:
				_set_state(DescentState.GAS_GIANT_DESCENT)
			elif _altitude_m >= _atmosphere_thickness_m * troposphere_entry_multiplier:
				_set_state(DescentState.THERMOSPHERE)
		DescentState.GAS_GIANT_DESCENT:
			# Endless descent; only abort or climbing back out exits.
			if _altitude_m > surface_approach_altitude_m * 2.0:
				_set_state(DescentState.TROPOSPHERE)
		DescentState.ABORT_ASCENT:
			if _altitude_m > _atmosphere_thickness_m * exosphere_entry_multiplier:
				_set_state(DescentState.ORBITAL)
		_:
			push_warning("[PlanetDescentController] Unknown gas giant state in transition: %d" % _current_state)

# ------------------------------------------------------------------------------
# Heating & Stall
# ------------------------------------------------------------------------------
func _update_heating(delta: float) -> void:
	if not _has_target or _profile == null:
		_current_heating = 0.0
		return
	var target_heating: float = 0.0
	var speed_factor: float = clampf(absf(_vertical_speed_ms) / 100.0, 0.0, 1.0)
	match _current_state:
		DescentState.EXOSPHERE_ENTRY:
			target_heating = 0.15 * _profile.heating_coefficient * speed_factor
		DescentState.THERMOSPHERE:
			target_heating = heating_rate_thermosphere * _profile.heating_coefficient * speed_factor
		DescentState.TROPOSPHERE:
			target_heating = heating_rate_troposphere * _profile.heating_coefficient * speed_factor
		DescentState.SURFACE_APPROACH:
			target_heating = heating_rate_troposphere * 0.5 * _profile.heating_coefficient * speed_factor
		DescentState.GAS_GIANT_DESCENT:
			target_heating = heating_rate_troposphere * 1.2 * _profile.heating_coefficient * speed_factor
		DescentState.ABORT_ASCENT:
			target_heating = heating_rate_thermosphere * 1.3 * _profile.heating_coefficient * speed_factor
		_:
			target_heating = 0.0
	target_heating = clampf(target_heating, 0.0, max_heating_intensity)
	_current_heating = lerp(_current_heating, target_heating, clampf(delta * 2.0, 0.0, 1.0))
	if _current_heating > 0.05:
		heating_warning.emit(_current_heating)

func _update_stall_warning() -> void:
	if not _has_target or _profile == null:
		_current_stall_factor = 0.0
		return
	var stall: float = 0.0
	if _current_state == DescentState.TROPOSPHERE or _current_state == DescentState.SURFACE_APPROACH:
		# Low speed in dense atmosphere risks aerodynamic stall. The PDC has no
		# true airspeed; vertical speed is used as a fallback proxy. The
		# FlightController emits its own stall_warning from actual velocity and
		# is the primary source when available.
		var speed_proxy: float = absf(_vertical_speed_ms)
		var threshold: float = maxf(stall_speed_threshold, 0.1)
		if speed_proxy < threshold:
			stall = 1.0 - (speed_proxy / threshold)
			stall = clampf(stall, 0.0, 1.0)
	_current_stall_factor = stall
	# Only emit when the factor is meaningful and has changed significantly,
	# to avoid flooding the HUD every physics frame.
	if stall > 0.1 and absf(stall - _last_emitted_stall_factor) > 0.05:
		_last_emitted_stall_factor = stall
		stall_warning.emit(stall)
	elif stall <= 0.1 and _last_emitted_stall_factor > 0.1:
		# Reset baseline once stall clears so future increases emit again.
		_last_emitted_stall_factor = 0.0

# ------------------------------------------------------------------------------
# Gas Giant Pressure
# ------------------------------------------------------------------------------
func _update_gas_giant_pressure(delta: float) -> void:
	if not _has_target or _profile == null or not _profile.is_gas_giant:
		_gas_giant_pressure_bar = 0.0
		_gas_giant_descent_depth_m = 0.0
		return
	if _current_state == DescentState.GAS_GIANT_DESCENT:
		_gas_giant_descent_depth_m += absf(_vertical_speed_ms) * delta
		_gas_giant_pressure_bar += gas_giant_pressure_rate * delta
		_gas_giant_pressure_bar = clampf(_gas_giant_pressure_bar, 0.0, gas_giant_max_pressure_bar)
		if _gas_giant_pressure_bar >= gas_giant_crush_pressure_bar:
			gas_giant_pressure_warning.emit(_gas_giant_pressure_bar)
			trigger_abort_ascent()
		elif _gas_giant_pressure_bar >= gas_giant_crush_pressure_bar * 0.7:
			gas_giant_pressure_warning.emit(_gas_giant_pressure_bar)
	else:
		# Pressure decays when ascending.
		_gas_giant_pressure_bar = maxf(_gas_giant_pressure_bar - gas_giant_pressure_rate * 2.0 * delta, 0.0)

# ------------------------------------------------------------------------------
# Landing Assist
# ------------------------------------------------------------------------------
func _activate_landing_assist() -> void:
	_landing_assist_active = true
	landing_assist_engaged.emit(true)

func _update_landing_assist(delta: float) -> void:
	if not _landing_assist_active:
		return
	# Damp vertical speed toward landing threshold.
	if _current_state == DescentState.SURFACE_APPROACH:
		var target_vspeed: float = -1.0
		_vertical_speed_ms = lerp(_vertical_speed_ms, target_vspeed, clampf(delta * landing_vertical_damp, 0.0, 1.0))
	# Surface-normal alignment is handled by the FlightController via signals;
	# here we only manage the descent-related damping.

# ------------------------------------------------------------------------------
# Takeoff Assist
# ------------------------------------------------------------------------------
func _update_takeoff_assist(delta: float) -> void:
	if not _takeoff_assist_active:
		return
	# While taking off, gradually release assist as altitude increases.
	if _current_state == DescentState.LANDED and _altitude_m > landing_altitude_threshold_m * 2.0:
		_surface_locked = false
		surface_lock_engaged.emit(false)
	# Abort ascent boosts vertical speed upward.
	if _current_state == DescentState.ABORT_ASCENT:
		_vertical_speed_ms = lerp(_vertical_speed_ms, 60.0, clampf(delta * 0.8, 0.0, 1.0))

## Called by the FlightController when the player applies upward thrust while LANDED.
func notify_takeoff_thrust(thrust_fraction: float) -> void:
	if _current_state != DescentState.LANDED:
		return
	if thrust_fraction >= takeoff_thrust_threshold:
		_takeoff_assist_active = true
		_surface_locked = false
		surface_lock_engaged.emit(false)
		_set_state(DescentState.TROPOSPHERE)
		takeoff_complete.emit()

# ------------------------------------------------------------------------------
# Player On Foot
# ------------------------------------------------------------------------------
func _handle_exit_ship_input() -> void:
	if _current_state == DescentState.LANDED:
		_set_state(DescentState.ON_FOOT)

func _handle_enter_ship_input() -> void:
	if _current_state == DescentState.ON_FOOT:
		_set_state(DescentState.LANDED)

# ------------------------------------------------------------------------------
# Descent Progress (shader uniform coordination)
# ------------------------------------------------------------------------------
func _update_descent_progress() -> void:
	if not _has_target or _atmosphere_thickness_m <= 0.0:
		_descent_progress = 0.0
		return
	match _current_state:
		DescentState.ORBITAL:
			_descent_progress = 0.0
		DescentState.EXOSPHERE_ENTRY:
			_descent_progress = 0.15
		DescentState.THERMOSPHERE:
			_descent_progress = 0.40
		DescentState.TROPOSPHERE:
			_descent_progress = 0.70
		DescentState.SURFACE_APPROACH:
			_descent_progress = 0.90
		DescentState.LANDED:
			_descent_progress = 1.0
		DescentState.ON_FOOT:
			_descent_progress = 1.0
		DescentState.SUBMERSIBLE:
			_descent_progress = clampf(1.0 + _underwater_depth_m / maxf(max_dive_depth_m, 1.0), 1.0, 1.5)
		DescentState.ABORT_ASCENT:
			var alt_frac: float = clampf(_altitude_m / _atmosphere_thickness_m, 0.0, 1.0)
			_descent_progress = lerp(1.0, 0.0, alt_frac)
		DescentState.GAS_GIANT_DESCENT:
			_descent_progress = clampf(0.90 + _gas_giant_descent_depth_m / 100000.0, 0.90, 1.5)
		_:
			_descent_progress = 0.0

# ------------------------------------------------------------------------------
# Atmosphere Scattering Drive (descent-state -> shader uniforms)
# ------------------------------------------------------------------------------
# Computes per-state target intensity/blend/density, smooths the current values
# toward them, and pushes the result to the target planet's atmosphere shader.
# Also updates the sun direction from the star position relative to the planet.
func _update_atmosphere_descent(delta: float) -> void:
	if not _has_target or _target_planet == null or not is_instance_valid(_target_planet):
		return
	# --- Per-state targets -------------------------------------------------
	var target_intensity: float = 0.0
	var target_blend: float = 0.0
	match _current_state:
		DescentState.ORBITAL:
			# Space: far-field EFA visible, near-field O'Neil at low intensity.
			target_intensity = 0.15
			target_blend = 0.0
		DescentState.EXOSPHERE_ENTRY:
			# Entering atmosphere: begin blending far->near, raise O'Neil.
			target_intensity = 0.45
			target_blend = 0.25
		DescentState.THERMOSPHERE:
			# Thin atmosphere: more near-field, haze building.
			target_intensity = 0.70
			target_blend = 0.55
		DescentState.TROPOSPHERE:
			# Full atmosphere: near-field O'Neil dominant, density affects visibility.
			target_intensity = 1.0
			target_blend = 0.85
		DescentState.SURFACE_APPROACH:
			# Near surface: full atmosphere, sky dome, horizon glow.
			target_intensity = 1.0
			target_blend = 1.0
		DescentState.LANDED:
			# On surface: full atmosphere, sky dome visible.
			target_intensity = 1.0
			target_blend = 1.0
		DescentState.ON_FOOT:
			target_intensity = 1.0
			target_blend = 1.0
		DescentState.SUBMERSIBLE:
			# Underwater: full near-field (sky still visible through water).
			target_intensity = 1.0
			target_blend = 1.0
		DescentState.ABORT_ASCENT:
			# Climbing back out: blend reverses with altitude.
			var alt_frac: float = clampf(_altitude_m / maxf(_atmosphere_thickness_m, 1.0), 0.0, 1.0)
			target_intensity = lerp(1.0, 0.15, alt_frac)
			target_blend = lerp(1.0, 0.0, alt_frac)
		DescentState.GAS_GIANT_DESCENT:
			# Endless deep descent: full near-field, dense.
			target_intensity = 1.0
			target_blend = 1.0
		_:
			target_intensity = 0.15
			target_blend = 0.0
	# --- Smooth toward targets --------------------------------------------
	var smooth_t: float = clampf(delta * atmosphere_smoothing_rate, 0.0, 1.0)
	_atmosphere_intensity = lerp(_atmosphere_intensity, target_intensity, smooth_t)
	_atmosphere_blend = lerp(_atmosphere_blend, target_blend, smooth_t)
	# --- Density (0..1+) from descent progress + archetype pressure --------
	var base_density: float = _descent_progress
	if _profile != null:
		# Dense atmospheres (gas giants, molten, radiotrophic) reach higher density.
		base_density *= clampf(_profile.pressure_surface_bar, 0.0, 4.0)
	# Underwater adds density above 1.0 for deeper muffling.
	if _current_state == DescentState.SUBMERSIBLE:
		base_density = 1.0 + clampf(_underwater_depth_m / maxf(max_dive_depth_m, 1.0), 0.0, 1.0)
	elif _current_state == DescentState.GAS_GIANT_DESCENT:
		base_density = 1.0 + clampf(_gas_giant_pressure_bar / maxf(gas_giant_max_pressure_bar, 1.0), 0.0, 1.0)
	var prev_density: float = _atmosphere_density
	_atmosphere_density = lerp(_atmosphere_density, base_density, smooth_t)
	# --- Push to the target planet ----------------------------------------
	if _target_planet.has_method("set_atmosphere_intensity"):
		_target_planet.set_atmosphere_intensity(_atmosphere_intensity)
	if _target_planet.has_method("set_atmosphere_blend"):
		_target_planet.set_atmosphere_blend(_atmosphere_blend)
	# --- Update sun direction from star position --------------------------
	if _has_star_position:
		var planet_pos: Vector3 = _target_planet.global_position if _target_planet is Node3D else Vector3.ZERO
		var sun_dir: Vector3 = (_star_position - planet_pos).normalized()
		if is_finite(sun_dir.length()) and sun_dir.length() > 0.001:
			if _target_planet.has_method("set_sun_direction"):
				_target_planet.set_sun_direction(sun_dir)
	# --- Emit density change signal (throttled) ---------------------------
	if absf(_atmosphere_density - prev_density) >= atmosphere_density_emit_threshold:
		atmosphere_density_changed.emit(_atmosphere_density)

# ------------------------------------------------------------------------------
# Integration Hooks
# ------------------------------------------------------------------------------
func _resolve_integration_hooks() -> void:
	# Lazily resolve autoloads / scene-tree nodes. These are optional.
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var root_node: Node = tree.root
	if root_node == null:
		return
	# Autoloads live as direct children of the scene tree root.
	_flight_controller = _find_node_by_class(root_node, "FlightController")
	_bio_audio_director = root_node.get_node_or_null("/root/BioAudioDirector")
	_bio_audio_synth = root_node.get_node_or_null("/root/BioAudioSynth")

func _find_node_by_class(start: Node, class_name_str: String) -> Node:
	if start == null:
		return null
	if start.is_class(class_name_str) or start.get_class() == class_name_str:
		return start
	# Check class_name via get_script
	var scr: Script = start.get_script()
	if scr != null and scr.get_global_name() == class_name_str:
		return start
	for child in start.get_children():
		var found: Node = _find_node_by_class(child, class_name_str)
		if found != null:
			return found
	return null

## Returns the resolved FlightController node, or null if not yet found.
func get_flight_controller() -> Node:
	return _flight_controller

## Returns the resolved BioAudioDirector node, or null if not yet found.
func get_bio_audio_director() -> Node:
	return _bio_audio_director

## Returns the resolved BioAudioSynth node, or null if not yet found.
func get_bio_audio_synth() -> Node:
	return _bio_audio_synth

# ------------------------------------------------------------------------------
# Internal Helpers
# ------------------------------------------------------------------------------
func _reset_descent_state() -> void:
	_current_state = DescentState.ORBITAL
	_previous_state = DescentState.ORBITAL
	_current_layer = AtmosphereLayer.SPACE
	_state_timer = 0.0
	_transition_blend = 0.0
	_is_transitioning = false
	_landing_assist_active = false
	_takeoff_assist_active = false
	_surface_locked = false
	_is_underwater = false
	_underwater_depth_m = 0.0
	_gas_giant_pressure_bar = 0.0
	_gas_giant_descent_depth_m = 0.0
	_current_heating = 0.0
	_current_stall_factor = 0.0
	_last_emitted_stall_factor = 0.0
	_descent_progress = 0.0
	_atmosphere_intensity = 0.0
	_atmosphere_blend = 0.0
	_atmosphere_density = 0.0

func _update_vertical_speed(delta: float) -> void:
	if delta <= 0.0:
		return
	_vertical_speed_ms = (_altitude_m - _previous_altitude_m) / delta
