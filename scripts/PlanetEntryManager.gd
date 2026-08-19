# ==============================================================================
# PlanetEntryManager.gd
# BioGenesis-X: Central Planet Entry / Descent Coordinator
# ==============================================================================
# Detects when the player ship approaches a planet, activates the descent
# sequence, and spawns/configures PlanetSurfaceManager, OceanSystem, and
# PlanetTerrainGenerator. Routes signals between every descent subsystem and
# manages the full transition from orbital space flight to on-foot surface
# exploration and back to orbit.
#
# LORE CONNECTION:
#   The Void-Fauna are deep-vacuum organisms (LORE.md "Evolutionary Origins")
#   — they evolved in molecular clouds, not on planets. So why does the player
#   land on planets? Three reasons from the lore:
#   1. COMET ICE HARVESTING: The Void-Fauna's Ingestion Gizzard harvests water
#      and hydrogen from icy bodies (ORGAN_SYSTEMS.md pipeline 4). Planets with
#      water oceans are rich refueling stops — the ship can ingest ocean water
#      directly, processed through the Electrolysis Gland into bio-plasma fuel.
#   2. RADIOTROPHIC FEEDING: The chitin carapace converts radiation to energy
#      (LORE.md "Immaculate Radiation Protection"). Planets close to their star
#      offer high radiation flux — the ship can "graze" on stellar radiation
#      while in planetary orbit, replenishing its metabolic reserves.
#   3. COVENANT MISSIONS: The Covenant of Symbiosis requires human pilots for
#      navigational intent. Human missions often involve planetary exploration
#      for resources, research, or contact with other life forms. The ship
#      carries its crew to planets because the crew needs to go there.
#
#   The descent itself is biologically stressful for the Void-Fauna —
#   atmospheric friction heats the carapace, gravity strains the vertebral
#   column, and the ship's radiotrophic cells must work harder to process
#   the higher radiation flux near a star. This is why descent has a
#   dedicated state machine and audio soundscape (DescentAudioController).
#
# Designed to be added to the scene tree (e.g. as a child of the space-flight
# scene root or registered as an autoload). All subsystems are resolved lazily
# and gracefully degraded: if any subsystem class is unavailable, a warning is
# logged and the manager continues with whatever is present.
# ==============================================================================
extends Node

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal descent_activated(planet_name: String, archetype: int)
signal player_on_foot()
signal player_in_ship()
signal returned_to_orbit()
signal terrain_chunk_loaded(count: int)
## Emitted when the ship enters the approach zone (between trigger_distance * 2
## and trigger_distance) of a planet, before descent actually activates.
## Gives the HUD a chance to warn the player that descent is imminent.
signal planet_approaching(planet_name: String, distance_m: float)

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
## Distance multiplier of the planet radius at which descent prep triggers.
## 5.0 means descent triggers at 5x planet radius from center (e.g. 1500-32500m
## Real-scale: trigger descent at 2x planet radius (atmosphere + approach buffer).
## For Earth (6,371km radius), descent triggers at ~12,742km — well into the
## exosphere, giving the descent system time to activate before surface.
@export var atmosphere_trigger_multiplier: float = 2.0
## When true, the landing-assist damping from PlanetDescentController is honored.
@export var auto_landing_assist: bool = true
## Target LOD follow distance passed through to the terrain generator each frame.
## Real-scale: terrain LOD follows at 50km from the player.
@export var terrain_lod_distance: float = 50000.0

# ------------------------------------------------------------------------------
# Archetypes that possess a surface ocean (mirrors OceanSystem support).
# ------------------------------------------------------------------------------
const _WATER_ARCHETYPES: Array[int] = [3, 4, 7]

# ------------------------------------------------------------------------------
# PlanetDescentController script + enum mirrors.
# ------------------------------------------------------------------------------
# PlanetDescentController is an autoload without class_name, so its type
# identifier is not reliably available at parse time in headless/test contexts
# (same class_name resolution issue documented for PlanetHUDUI above). We
# preload the script for instantiation and mirror the DescentState enum values
# we reference as integer constants. Values are stable and documented in
# PlanetDescentController.gd.
const _PDC_SCRIPT: GDScript = preload("res://scripts/PlanetDescentController.gd")
const _DS_ORBITAL: int = 0
const _DS_EXOSPHERE_ENTRY: int = 1
const _DS_ABORT_ASCENT: int = 8

# ------------------------------------------------------------------------------
# Preloaded GDScript resources for descent subsystem instantiation.
# ------------------------------------------------------------------------------
# In Godot 4.7, ClassDB.class_exists() only inspects the C++ class registry, not
# GDScript class_name registrations, so it returns false for every GDScript
# class and causes all subsystem spawns to be skipped. We preload the scripts
# and instantiate via .new() instead, casting to the base engine class. The
# class_name type annotations on the member variables still resolve at parse
# time, so they are retained.
const _PSM_SCRIPT: GDScript = preload("res://scripts/PlanetSurfaceManager.gd")
const _OS_SCRIPT: GDScript = preload("res://scripts/OceanSystem.gd")
const _PTG_SCRIPT: GDScript = preload("res://scripts/PlanetTerrainGenerator.gd")
const _AVS_SCRIPT: GDScript = preload("res://scripts/AtmosphereVisualSystem.gd")
const _PCC_SCRIPT: GDScript = preload("res://scripts/PlanetCharacterController.gd")
const _PC_SCRIPT: GDScript = preload("res://scripts/PlanetCamera.gd")
const _PHUD_SCRIPT: GDScript = preload("res://scripts/PlanetHUDUI.gd")

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _descent_controller: Node = null
var _surface_manager: PlanetSurfaceManager = null
var _ocean_system: OceanSystem = null
var _terrain_generator: PlanetTerrainGenerator = null
var _character_controller: PlanetCharacterController = null
var _planet_camera: PlanetCamera = null
# Typed as CanvasLayer (the base class) rather than PlanetHUDUI to avoid a
# parse-time class_name resolution issue: PlanetEntryManager is an autoload
# parsed before PlanetHUDUI.gd registers its class_name.
var _planet_hud: CanvasLayer = null

var _flight_controller: FlightController = null
var _active_planet: ProceduralPlanet = null
var _active_planet_name: String = ""
var _active_archetype: int = 3
var _active_planet_radius: float = 100.0
var _active_has_water: bool = false
var _active_seed: int = 0

var _descent_active: bool = false
var _on_foot: bool = false
var _character_spawned: bool = false
var _chunks_loaded_count: int = 0
var _last_lod_position: Vector3 = Vector3.ZERO

# Approach-zone tracking: avoids re-emitting planet_approaching every frame for
# the same planet. Cleared when descent activates or the ship leaves the zone.
var _approaching_planet_name: String = ""

# Nearest-planet info pushed by FlightController._update_nearest_planet() so the
# flight HUD can render a directional marker without re-scanning the tree.
var _nearest_planet_node: Node3D = null
var _nearest_planet_distance: float = INF

# ------------------------------------------------------------------------------
# Pre-computed descent data
# ------------------------------------------------------------------------------
# When FlightController identifies a new nearest planet we pre-compute the
# archetype / radius / seed / atmosphere values that activate_descent() will
# need, moving that work out of the descent-activation hot path. The terrain
# shader for the archetype is also requested via a non-blocking
# ResourceLoader.load_threaded_request() so it is resident by the time descent
# fires. _precomputed_valid is only true while _precomputed_planet is still
# alive and the cached values are usable.
var _precomputed_planet: Node3D = null
var _precomputed_archetype: int = -1
var _precomputed_radius: float = 0.0
var _precomputed_seed: int = 0
var _precomputed_has_water: bool = false
var _precomputed_atmosphere_height: float = 0.0
var _precomputed_valid: bool = false

# Subsystem references resolved lazily from autoloads / scene tree.
var _atmosphere_visual_system: AtmosphereVisualSystem = null
var _landing_sequence_controller: Node = null
var _descent_audio_controller: Node = null

# Current star system data (star type, planet positions) provided by
# UniverseManager via set_current_system() whenever a new system loads.
var _current_system_data: Dictionary = {}

# ------------------------------------------------------------------------------
# Shader Pre-Warm State
# ------------------------------------------------------------------------------
# Descent activates four GPU-shader-bearing subsystems (AtmosphereVisualSystem,
# PlanetSurfaceManager, OceanSystem, PlanetTerrainGenerator) whose pipelines
# Godot compiles lazily on first render, causing a ~45ms frame hitch the first
# time descent fires. To eliminate that hitch we pre-compile every descent
# shader at scene load by assigning each to a hidden MeshInstance3D for one
# frame, spread across multiple _process ticks (2 per frame) so the cost is
# amortized rather than concentrated in a single long frame.
var _shader_warm_queue: PackedStringArray = PackedStringArray()
var _shader_warm_index: int = 0


# ==============================================================================
# Lifecycle
# ==============================================================================
func _ready() -> void:
	set_process(true)
	_resolve_descent_controller()
	# Pre-warm all descent shaders after the scene tree is ready so the
	# temporary warm mesh can be parented and rendered. call_deferred()
	# guarantees the manager is inside the tree before we add children.
	call_deferred("_preload_descent_shaders")

func _exit_tree() -> void:
	_shader_warm_queue.clear()
	_shader_warm_index = 0

func _process(_delta: float) -> void:
	# Pre-warm descent shaders (1 per frame) BEFORE the proximity check so the
	# pipeline compilation cost is spread across early frames and never
	# coincides with the first real descent activation.
	_process_shader_warm()

	if _flight_controller == null or not is_instance_valid(_flight_controller):
		_flight_controller = _find_flight_controller()
	if _flight_controller == null:
		return

	var ship_pos: Vector3 = _flight_controller.global_position

	if not _descent_active:
		_check_planet_proximity(ship_pos)
		return

	# Descent is active: feed altitude + LOD updates every frame.
	_update_descent_altitude(ship_pos)
	if _terrain_generator != null and is_instance_valid(_terrain_generator):
		# Gate LOD recompute by terrain_lod_distance to avoid per-frame churn.
		if ship_pos.distance_to(_last_lod_position) > terrain_lod_distance * 0.02:
			var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
			_terrain_generator.update_lod(ship_pos, cam)
			_last_lod_position = ship_pos

# ==============================================================================
# Shader Pre-Warm
# ==============================================================================

## Queues every descent-related shader for pipeline pre-compilation and creates
## a persistent hidden MeshInstance3D used to "touch" each shader for one render
## frame. The actual per-frame warming is driven by _process_shader_warm(),
## which processes 1 shader per _process tick to amortize the compilation cost
## across multiple frames instead of a single long hitch.
func _preload_descent_shaders() -> void:
	# Only run once; guard against a double call_deferred() invocation.
	if _shader_warm_queue.size() > 0:
		return
	_shader_warm_queue.clear()
	# Terrain shaders (all 8 archetypes) via the shared factory path resolver.
	for i: int in range(8):
		var path: String = TerrainMaterialFactory.get_terrain_shader_path(i)
		if not path.is_empty() and ResourceLoader.exists(path):
			_shader_warm_queue.append(path)
	# Atmosphere scattering + cloud layer shaders.
	if ResourceLoader.exists("res://shaders/atmosphere_scattering.gdshader"):
		_shader_warm_queue.append("res://shaders/atmosphere_scattering.gdshader")
	if ResourceLoader.exists("res://shaders/cloud_layer.gdshader"):
		_shader_warm_queue.append("res://shaders/cloud_layer.gdshader")
	# Ocean surface + underwater post-process shaders (guarded; only present if
	# the ocean subsystem ships with this build).
	if ResourceLoader.exists("res://shaders/ocean_surface.gdshader"):
		_shader_warm_queue.append("res://shaders/ocean_surface.gdshader")
	if ResourceLoader.exists("res://shaders/underwater_post.gdshader"):
		_shader_warm_queue.append("res://shaders/underwater_post.gdshader")
	# Wave engine (Alcubierre warp plane) shader.
	if ResourceLoader.exists("res://shaders/wave_engine.gdshader"):
		_shader_warm_queue.append("res://shaders/wave_engine.gdshader")
	_shader_warm_index = 0
	# No warm mesh needed — Godot 4.4+ auto-precompiles pipelines when shader
	# resources are loaded. We just need to load() each shader to cache it.

## Processes the shader warm queue, loading 1 shader resource per frame.
## Called at the top of _process() so loading completes within the first few
## frames after scene load, well before the player can trigger descent.
## Godot 4.4+ will detect the loaded shaders and precompile their pipelines
## in background threads.
func _process_shader_warm() -> void:
	if _shader_warm_queue.size() == 0:
		return
	if _shader_warm_index >= _shader_warm_queue.size():
		_shader_warm_queue.clear()
		_shader_warm_index = 0
		return
	# Load 1 shader per frame to cache the resource and let Godot's
	# automatic pipeline precompilation system detect it.
	var path: String = _shader_warm_queue[_shader_warm_index]
	if not ResourceLoader.has_cached(path):
		load(path)
	_shader_warm_index += 1

# ==============================================================================
# Pre-Computation Pipeline
# ==============================================================================

## Pre-computes descent data for a planet before descent activates. Called when
## FlightController identifies a new nearest planet (via set_nearest_planet()).
## This moves archetype / radius / seed / atmosphere computation out of the
## descent-activation hot path and kicks off a non-blocking threaded load of the
## terrain shader for the planet's archetype so it is resident by the time
## descent fires. Safe to call repeatedly; it short-circuits when the planet has
## not changed.
func precompute_descent_data(planet: Node3D) -> void:
	if planet == _precomputed_planet:
		return  # Already precomputed for this planet
	_precomputed_planet = planet
	if planet == null or not is_instance_valid(planet):
		_precomputed_valid = false
		return
	_precomputed_archetype = int(planet.get("archetype"))
	_precomputed_radius = float(planet.get("radius_m"))
	_precomputed_seed = _resolve_planet_seed(planet)
	_precomputed_has_water = _is_water_archetype(_precomputed_archetype)
	_precomputed_atmosphere_height = maxf(_precomputed_radius * 0.02, 1000.0)
	_precomputed_valid = true
	# Preload the terrain shader for this archetype via a non-blocking threaded
	# request so it is cached by the time descent activates.
	var shader_path: String = TerrainMaterialFactory.get_terrain_shader_path(_precomputed_archetype)
	if not shader_path.is_empty() and not ResourceLoader.has_cached(shader_path):
		ResourceLoader.load_threaded_request(shader_path, "Shader")

## Pre-loads the wave engine shader for a wave-warp target planet in the
## background. Called when the wave warp targeting system identifies a
## destination so the Alcubierre warp plane material is ready on engage.
func preload_wave_target(_planet: Node3D) -> void:
	# The wave engine shader is global (not per-planet), but we still ensure it
	# is resident so the warp plane materializes without a first-load hitch.
	var shader_path: String = "res://shaders/wave_engine.gdshader"
	if ResourceLoader.exists(shader_path) and not ResourceLoader.has_cached(shader_path):
		ResourceLoader.load_threaded_request(shader_path, "Shader")

# ==============================================================================
# 1. Planet Approach Detection
# ==============================================================================

## Monitors the player ship's distance to all planets in the "targets" group.
## When the distance drops below planet_radius * atmosphere_trigger_multiplier,
## descent preparation is triggered via activate_descent().
func _check_planet_proximity(ship_position: Vector3) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var targets: Array[Node] = tree.get_nodes_in_group("targets")
	var approaching_emitted: bool = false
	for node: Node in targets:
		if not (node is ProceduralPlanet):
			continue
		var planet: ProceduralPlanet = node as ProceduralPlanet
		if not is_instance_valid(planet):
			continue
		var planet_radius: float = maxf(planet.radius_m, 1.0)
		var trigger_distance: float = planet_radius * atmosphere_trigger_multiplier
		var distance: float = ship_position.distance_to(planet.global_position)
		if distance < trigger_distance:
			# Clear approach tracking on descent activation.
			_approaching_planet_name = ""
			activate_descent(planet)
			return
		# Approach zone: within 2x trigger distance but not yet at trigger.
		# Emit planet_approaching once per planet entry to avoid per-frame spam.
		var approach_distance: float = trigger_distance * 2.0
		if distance < approach_distance and distance >= trigger_distance:
			approaching_emitted = true
			if _approaching_planet_name != planet.planet_name:
				_approaching_planet_name = planet.planet_name
				planet_approaching.emit(planet.planet_name, distance)
	# If no planet is in the approach zone this frame, clear the tracking name so
	# a future re-entry re-emits the notification.
	if not approaching_emitted:
		_approaching_planet_name = ""

# ==============================================================================
# 2. Descent Activation
# ==============================================================================

## Activates the descent sequence for the given planet node. Spawns and
## configures PlanetSurfaceManager, OceanSystem (if the planet has water), and
## PlanetTerrainGenerator. Wires all subsystem signals. Gracefully degrades if
## any subsystem class is unavailable.
func activate_descent(planet_node: Node3D) -> void:
	if _descent_active:
		return
	if planet_node == null or not is_instance_valid(planet_node):
		push_error("PlanetEntryManager: activate_descent called with invalid planet node.")
		return
	if not (planet_node is ProceduralPlanet):
		push_error("PlanetEntryManager: activate_descent expects a ProceduralPlanet node.")
		return

	var planet: ProceduralPlanet = planet_node as ProceduralPlanet
	_active_planet = planet
	_active_planet_name = planet.planet_name
	# Use pre-computed descent data when it matches this planet so the
	# archetype/radius/seed/water lookups (and the threaded shader request) are
	# skipped on the descent-activation hot path. Falls back to computing now if
	# the precomputed cache is missing or stale.
	if _precomputed_valid and is_instance_valid(_precomputed_planet) and _precomputed_planet == planet_node:
		_active_archetype = _precomputed_archetype
		_active_planet_radius = maxf(_precomputed_radius, 1.0)
		_active_seed = _precomputed_seed
		_active_has_water = _precomputed_has_water
	else:
		_active_archetype = planet.archetype
		_active_planet_radius = maxf(planet.radius_m, 1.0)
		_active_has_water = _is_water_archetype(_active_archetype)
		_active_seed = _resolve_planet_seed(planet)
	_descent_active = true
	_chunks_loaded_count = 0
	_last_lod_position = Vector3(INF, INF, INF) # force first-frame LOD update

	# --- Descent Controller -------------------------------------------------
	_resolve_descent_controller()
	if _descent_controller != null and is_instance_valid(_descent_controller):
		_descent_controller.set_target_planet(
			planet,
			_active_archetype,
			_active_planet_radius,
			_active_has_water,
		)
		_connect_descent_signals()
	else:
		push_warning("PlanetEntryManager: PlanetDescentController unavailable; descent state machine disabled.")

	# --- Surface Manager ----------------------------------------------------
	_spawn_surface_manager(planet)

	# --- Ocean System (only for water-bearing archetypes) -------------------
	if _active_has_water:
		_spawn_ocean_system(planet)
	else:
		_ocean_system = null

	# --- Terrain Generator --------------------------------------------------
	_spawn_terrain_generator(planet)

	# --- Atmosphere Visual System -------------------------------------------
	_spawn_atmosphere_visual_system(planet)

	# --- Landing Sequence Controller ----------------------------------------
	_resolve_landing_sequence_controller()

	# --- Descent Audio Controller -------------------------------------------
	_resolve_descent_audio_controller()
	_set_descent_audio_active(true)

	# --- Planet HUD UI ------------------------------------------------------
	_spawn_planet_hud()

	# --- Force HIGH-detail LOD on the descent target planet -----------------
	planet.set_high_detail(true)

	descent_activated.emit(_active_planet_name, _active_archetype)

# ==============================================================================
# Subsystem Spawning
# ==============================================================================

func _spawn_surface_manager(planet: ProceduralPlanet) -> void:
	var mgr: Node3D = _PSM_SCRIPT.new() as Node3D
	if mgr == null:
		push_warning("PlanetEntryManager: PlanetSurfaceManager failed to instantiate; surface environment skipped.")
		_surface_manager = null
		return
	mgr.name = "PlanetSurfaceManager"
	mgr.visible = false
	add_child(mgr)
	mgr.configure_for_archetype(_active_archetype, _active_seed, _active_planet_radius)
	mgr.global_position = planet.global_position
	if not mgr.surface_ready.is_connected(_on_surface_ready):
		mgr.surface_ready.connect(_on_surface_ready)
	if not mgr.time_of_day_changed.is_connected(_on_time_of_day_changed):
		mgr.time_of_day_changed.connect(_on_time_of_day_changed)
	_surface_manager = mgr as PlanetSurfaceManager

func _spawn_ocean_system(planet: ProceduralPlanet) -> void:
	var ocean: Node3D = _OS_SCRIPT.new() as Node3D
	if ocean == null:
		push_warning("PlanetEntryManager: OceanSystem failed to instantiate; ocean skipped.")
		_ocean_system = null
		return
	ocean.name = "OceanSystem"
	add_child(ocean)
	ocean.set_planet_archetype(_active_archetype)
	ocean.set_ocean_active(true)
	ocean.global_position = planet.global_position
	if not ocean.layer_changed.is_connected(_on_ocean_layer_changed):
		ocean.layer_changed.connect(_on_ocean_layer_changed)
	if not ocean.entered_water.is_connected(_on_ocean_entered_water):
		ocean.entered_water.connect(_on_ocean_entered_water)
	if not ocean.exited_water.is_connected(_on_ocean_exited_water):
		ocean.exited_water.connect(_on_ocean_exited_water)
	_ocean_system = ocean as OceanSystem

func _spawn_terrain_generator(planet: ProceduralPlanet) -> void:
	var terrain: Node3D = _PTG_SCRIPT.new() as Node3D
	if terrain == null:
		push_warning("PlanetEntryManager: PlanetTerrainGenerator failed to instantiate; GPU terrain skipped.")
		_terrain_generator = null
		return
	terrain.name = "PlanetTerrainGenerator"
	terrain.planet_radius_m = _active_planet_radius
	add_child(terrain)
	terrain.set_planet_data(_active_seed, _active_archetype, _active_planet_radius)
	terrain.global_position = planet.global_position
	if not terrain.chunk_loaded.is_connected(_on_terrain_chunk_loaded):
		terrain.chunk_loaded.connect(_on_terrain_chunk_loaded)
	if not terrain.chunk_unloaded.is_connected(_on_terrain_chunk_unloaded):
		terrain.chunk_unloaded.connect(_on_terrain_chunk_unloaded)
	_terrain_generator = terrain as PlanetTerrainGenerator

func _spawn_atmosphere_visual_system(planet: ProceduralPlanet) -> void:
	var atmo: Node3D = _AVS_SCRIPT.new() as Node3D
	if atmo == null:
		push_warning("PlanetEntryManager: AtmosphereVisualSystem failed to instantiate; atmosphere visuals skipped.")
		_atmosphere_visual_system = null
		return
	atmo.name = "AtmosphereVisualSystem"
	add_child(atmo)
	var atmo_height: float = _resolve_atmosphere_height()
	atmo.configure(_active_archetype, _active_planet_radius, atmo_height)
	atmo.global_position = planet.global_position
	atmo.set_active(true)
	# Connect time-of-day updates from the surface manager to the atmosphere system.
	if _surface_manager != null and is_instance_valid(_surface_manager):
		var set_tod: Callable = Callable(atmo, "set_time_of_day")
		if not _surface_manager.time_of_day_changed.is_connected(set_tod):
			_surface_manager.time_of_day_changed.connect(set_tod)
	_atmosphere_visual_system = atmo as AtmosphereVisualSystem
	# Signal the landing controller that the atmosphere visual system is built,
	# releasing the TOUCHDOWN phase hold.
	_notify_landing_phase_ready("notify_touchdown_ready")

## Returns a visual atmosphere height proportional to the planet radius.
## Real Earth atmosphere: ~100km visible, ~10,000km exosphere.
## We use 2% of radius as the visual scattering shell height.
func _resolve_atmosphere_height() -> float:
	return maxf(_active_planet_radius * 0.02, 1000.0)

## Spawns a PlanetHUDUI instance (a CanvasLayer that self-registers its
## signals in _ready()) so the descent/surface HUD is available during
## planetary entry. Instantiation goes through the preloaded script to avoid
## the Godot 4.7 ClassDB.class_exists() limitation for GDScript class_name
## registrations (it only inspects the C++ class registry).
func _spawn_planet_hud() -> void:
	if _planet_hud != null and is_instance_valid(_planet_hud):
		return # Already spawned for this descent.
	var hud: CanvasLayer = _PHUD_SCRIPT.new() as CanvasLayer
	if hud == null:
		push_warning("PlanetEntryManager: PlanetHUDUI failed to instantiate; descent HUD skipped.")
		_planet_hud = null
		return
	hud.name = "PlanetHUDUI"
	add_child(hud)
	_planet_hud = hud

# ==============================================================================
# 3. Signal Routing
# ==============================================================================

func _connect_descent_signals() -> void:
	if _descent_controller == null:
		return
	var dc: Node = _descent_controller
	if not dc.descent_state_changed.is_connected(_on_descent_state_changed):
		dc.descent_state_changed.connect(_on_descent_state_changed)
	if not dc.landing_complete.is_connected(_on_landing_complete):
		dc.landing_complete.connect(_on_landing_complete)
	if not dc.entered_water.is_connected(_on_descent_entered_water):
		dc.entered_water.connect(_on_descent_entered_water)
	if not dc.player_exited_ship.is_connected(_on_player_exited_ship):
		dc.player_exited_ship.connect(_on_player_exited_ship)
	if not dc.player_entered_ship.is_connected(_on_player_entered_ship):
		dc.player_entered_ship.connect(_on_player_entered_ship)
	if not dc.takeoff_complete.is_connected(_on_takeoff_complete):
		dc.takeoff_complete.connect(_on_takeoff_complete)

func _on_descent_state_changed(old_state: int, new_state: int) -> void:
	# Cleanup: when the player climbs back to orbit after an abort, tear down
	# all surface subsystems and emit returned_to_orbit.
	if old_state == _DS_ABORT_ASCENT and \
			new_state == _DS_ORBITAL:
		_cleanup_surface_systems()
		returned_to_orbit.emit()
		return
	# Surface visibility follows the layer.
	if _surface_manager != null and is_instance_valid(_surface_manager):
		match new_state:
			_DS_ORBITAL, \
			_DS_EXOSPHERE_ENTRY:
				_surface_manager.visible = false
			_:
				_surface_manager.visible = true
	# Audio hook (optional).
	_notify_audio_layer(new_state)

func _on_landing_complete(planet_archetype: int, position: Vector3) -> void:
	# Gas giants never land - ignore spurious calls.
	if planet_archetype == 5 or planet_archetype == 6:
		return
	# Default to UP so a missing surface manager never yields a zero (invalid)
	# normal that would corrupt the landing alignment math downstream.
	var normal: Vector3 = Vector3.UP
	if _surface_manager != null and is_instance_valid(_surface_manager):
		normal = _surface_manager.enter_surface(position)
	if auto_landing_assist and _descent_controller != null and is_instance_valid(_descent_controller):
		_descent_controller.set_surface_normal(normal)
	_spawn_character_and_camera(position)
	player_on_foot.emit()
	# Trigger the cinematic landing animation via the landing sequence controller.
	# The ship remains visible through the ALIGN->DESCEND->TOUCHDOWN->SETTLE
	# animation; it is hidden only after the LSC reports landing_complete.
	_trigger_landing_sequence(position)

func _on_player_exited_ship() -> void:
	# Activate the (already-spawned) character controller for on-foot control.
	if _character_controller != null and is_instance_valid(_character_controller):
		_character_controller.set_process(true)
		_character_controller.set_physics_process(true)
		_character_controller.visible = true
	_on_foot = true
	_disable_ship()
	player_on_foot.emit()

func _on_player_entered_ship() -> void:
	# Deactivate the character controller; the player is back in the ship.
	if _character_controller != null and is_instance_valid(_character_controller):
		_character_controller.return_to_ship()
		_character_controller.set_physics_process(false)
		_character_controller.set_process(false)
		_character_controller.visible = false
	_on_foot = false
	_enable_ship()
	player_in_ship.emit()

func _on_takeoff_complete() -> void:
	_remove_character_and_camera()
	_enable_ship()
	_on_foot = false
	player_in_ship.emit()

func _on_descent_entered_water(depth_m: float) -> void:
	if _ocean_system != null and is_instance_valid(_ocean_system):
		_ocean_system.set_water_depth(depth_m)

func _on_surface_ready() -> void:
	# The surface environment has been built and is ready for interaction.
	# Notify the HUD (if present) and ensure the descent audio controller is
	# active so the surface soundscape begins playing. All calls are null-safe.
	if _surface_manager != null and is_instance_valid(_surface_manager):
		# Surface manager is valid; make it visible for the descent phase.
		_surface_manager.visible = true

	# Notify the Planet HUD UI if it is present and valid in the tree.
	if _planet_hud != null and is_instance_valid(_planet_hud):
		if _planet_hud.has_method("show_surface_hud"):
			_planet_hud.call("show_surface_hud")
		elif _planet_hud.has_method("set_surface_ready"):
			_planet_hud.call("set_surface_ready", true)

	# Ensure the descent audio controller is active for the surface phase.
	if _descent_audio_controller != null and is_instance_valid(_descent_audio_controller):
		if _descent_audio_controller.has_method("set_active"):
			if not _descent_audio_controller.has_method("is_active") or \
					not bool(_descent_audio_controller.call("is_active")):
				_descent_audio_controller.call("set_active", true)

	# Signal the landing controller that the surface environment is built,
	# releasing the DESCEND phase hold.
	_notify_landing_phase_ready("notify_descend_ready")

func _on_time_of_day_changed(time_normalized: float) -> void:
	# Update sky shaders / audio for the day-night cycle.
	if _ocean_system != null and is_instance_valid(_ocean_system):
		# 0 = midnight, 0.5 = noon -> night factor 1.0 / 0.0.
		_ocean_system.night_factor = clampf(1.0 - absf((time_normalized - 0.5) * 2.0), 0.0, 1.0)
	_notify_audio_time_of_day(time_normalized)

func _on_ocean_layer_changed(_old_layer: int, new_layer: int) -> void:
	# Update underwater post-processing intensity + audio.
	_notify_audio_ocean_layer(new_layer)

func _on_ocean_entered_water(depth_m: float) -> void:
	if _descent_controller != null and is_instance_valid(_descent_controller):
		_descent_controller.notify_splashdown(depth_m)
	# Wire swimming mode on the character controller so buoyancy/water physics activate.
	if _character_controller != null and is_instance_valid(_character_controller):
		_character_controller.set_swimming(true, depth_m)

func _on_ocean_exited_water() -> void:
	if _descent_controller != null and is_instance_valid(_descent_controller):
		_descent_controller.notify_surfaced()
	# Disable swimming mode on the character controller.
	if _character_controller != null and is_instance_valid(_character_controller):
		_character_controller.set_swimming(false, 0.0)

func _on_terrain_chunk_loaded(_chunk_position: Vector3) -> void:
	_chunks_loaded_count += 1
	terrain_chunk_loaded.emit(_chunks_loaded_count)
	# Signal the landing controller that the terrain system is operational,
	# releasing the ALIGN phase hold.
	_notify_landing_phase_ready("notify_align_ready")

func _on_terrain_chunk_unloaded(_chunk_position: Vector3) -> void:
	_chunks_loaded_count = maxi(0, _chunks_loaded_count - 1)

# ==============================================================================
# 4. Terrain Integration
# ==============================================================================

func _update_descent_altitude(ship_position: Vector3) -> void:
	if _descent_controller == null or not is_instance_valid(_descent_controller):
		return
	if _active_planet == null or not is_instance_valid(_active_planet):
		return
	var planet_center: Vector3 = _active_planet.global_position
	var terrain_height: float = 0.0
	_descent_controller.update_altitude(
		ship_position,
		planet_center,
		_active_planet_radius,
		terrain_height,
	)

# ==============================================================================
# 5. Landing / Takeoff Management
# ==============================================================================

func _spawn_character_and_camera(landing_position: Vector3) -> void:
	if _character_spawned:
		return
	if _flight_controller == null or not is_instance_valid(_flight_controller):
		push_warning("PlanetEntryManager: cannot spawn character - no FlightController.")
		return

	# Character controller.
	var character: CharacterBody3D = _PCC_SCRIPT.new() as CharacterBody3D
	if character == null:
		push_warning("PlanetEntryManager: PlanetCharacterController failed to instantiate; on-foot skipped.")
	else:
		character.name = "PlanetCharacterController"
		add_child(character)
		var planet_center: Vector3 = Vector3.ZERO
		if _active_planet != null and is_instance_valid(_active_planet):
			planet_center = _active_planet.global_position
		var gravity: float = 9.81
		if _active_planet != null and is_instance_valid(_active_planet):
			gravity = _active_planet.surface_gravity_ms2
		character.set_planet(planet_center, _active_planet_radius, gravity)
		var ship_rot: Basis = _flight_controller.global_transform.basis
		character.enter_from_ship(landing_position, ship_rot)
		character.set_process(false)
		character.set_physics_process(false)
		character.visible = false
		_character_controller = character as PlanetCharacterController

	# Planet camera.
	if _character_controller != null:
		var cam: Camera3D = _PC_SCRIPT.new() as Camera3D
		if cam == null:
			push_warning("PlanetEntryManager: PlanetCamera failed to instantiate; surface camera skipped.")
		else:
			cam.name = "PlanetCamera"
			add_child(cam)
			cam.set_target(_character_controller)
			var up: Vector3 = Vector3.UP
			if _character_controller != null and is_instance_valid(_character_controller):
				up = _character_controller.get_surface_normal()
			cam.set_planet_up(up)
			# Hand the camera reference to the character for camera-relative movement.
			_character_controller.set_camera(cam)
			cam.current = true
			_planet_camera = cam as PlanetCamera
	else:
		push_warning("PlanetEntryManager: PlanetCamera skipped - no character controller spawned.")

	_character_spawned = true
	# Signal the landing controller that the character controller and camera
	# are spawned, releasing the SETTLE phase hold.
	_notify_landing_phase_ready("notify_settle_ready")

func _remove_character_and_camera() -> void:
	if _planet_camera != null and is_instance_valid(_planet_camera):
		_planet_camera.queue_free()
	_planet_camera = null
	if _character_controller != null and is_instance_valid(_character_controller):
		_character_controller.queue_free()
	_character_controller = null
	_character_spawned = false
	_on_foot = false

func _disable_ship() -> void:
	if _flight_controller == null or not is_instance_valid(_flight_controller):
		return
	_flight_controller.set_process(false)
	_flight_controller.set_physics_process(false)
	_flight_controller.visible = false

func _enable_ship() -> void:
	if _flight_controller == null or not is_instance_valid(_flight_controller):
		return
	_flight_controller.visible = true
	_flight_controller.set_process(true)
	_flight_controller.set_physics_process(true)

# ==============================================================================
# 6. Cleanup (return to orbit)
# ==============================================================================

func _cleanup_surface_systems() -> void:
	if _surface_manager != null and is_instance_valid(_surface_manager):
		_surface_manager.exit_surface()
		_surface_manager.queue_free()
	_surface_manager = null
	if _ocean_system != null and is_instance_valid(_ocean_system):
		_ocean_system.set_ocean_active(false)
		_ocean_system.queue_free()
	_ocean_system = null
	if _terrain_generator != null and is_instance_valid(_terrain_generator):
		_terrain_generator.queue_free()
	_terrain_generator = null
	if _atmosphere_visual_system != null and is_instance_valid(_atmosphere_visual_system):
		_atmosphere_visual_system.set_active(false)
		_atmosphere_visual_system.queue_free()
	_atmosphere_visual_system = null
	if _planet_hud != null and is_instance_valid(_planet_hud):
		_planet_hud.queue_free()
	_planet_hud = null
	_chunks_loaded_count = 0
	_remove_character_and_camera()
	_enable_ship()
	_set_descent_audio_active(false)
	# Reset the LandingSequenceController so no stale landing/takeoff phase
	# persists into the next descent. Safe to call even if the controller is
	# unavailable.
	if _landing_sequence_controller != null and is_instance_valid(_landing_sequence_controller):
		if _landing_sequence_controller.has_method("reset"):
			_landing_sequence_controller.reset()
	if _descent_controller != null and is_instance_valid(_descent_controller):
		_descent_controller.clear_target_planet()
	_descent_active = false
	_on_foot = false
	_active_planet = null

# ==============================================================================
# Audio Hooks (optional, graceful)
# ==============================================================================

func _notify_audio_layer(state: int) -> void:
	var director: Node = _get_audio_director()
	if director == null:
		return
	if director.has_method("on_descent_layer_changed"):
		director.call("on_descent_layer_changed", state)

func _notify_audio_time_of_day(time_normalized: float) -> void:
	var director: Node = _get_audio_director()
	if director == null:
		return
	if director.has_method("on_time_of_day_changed"):
		director.call("on_time_of_day_changed", time_normalized)

func _notify_audio_ocean_layer(layer: int) -> void:
	var director: Node = _get_audio_director()
	if director == null:
		return
	if director.has_method("on_ocean_layer_changed"):
		director.call("on_ocean_layer_changed", layer)

func _get_audio_director() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/BioAudioDirector")

# ==============================================================================
# Helpers
# ==============================================================================

## Returns true if the archetype possesses a surface ocean.
func _is_water_archetype(archetype: int) -> bool:
	return _WATER_ARCHETYPES.has(archetype)

## Resolves a deterministic seed for the planet from the UniverseManager system
## seed, falling back to a hash of the planet name. Accepts a Node3D so it can
## be used both from the pre-computation path (which receives a Node3D) and the
## regular descent-activation path (which passes a ProceduralPlanet).
func _resolve_planet_seed(planet: Node3D) -> int:
	var planet_name: String = String(planet.get("planet_name"))
	var tree: SceneTree = get_tree()
	if tree != null and tree.root != null:
		var universe: Node = tree.root.get_node_or_null("/root/UniverseManager")
		if universe != null and "current_system_seed" in universe:
			var sys_seed: int = int(universe.get("current_system_seed"))
			# Combine system seed with the planet name hash for per-planet uniqueness.
			return sys_seed ^ planet_name.hash()
	return planet_name.hash()

## Lazily resolves the PlanetDescentController from the scene tree. If none
## exists, creates one and adds it as a child so the manager is self-sufficient.
func _resolve_descent_controller() -> void:
	if _descent_controller != null and is_instance_valid(_descent_controller):
		return
	# Search the tree for an existing instance first (autoload or scene node).
	var tree: SceneTree = get_tree()
	if tree != null and tree.root != null:
		# Check the autoload singleton path first (most common case).
		var existing: Node = tree.root.get_node_or_null("/root/PlanetDescentController")
		if existing == null:
			# Fall back to a tree search by script resource path.
			existing = _find_node_by_script(tree.root, "res://scripts/PlanetDescentController.gd")
		if existing != null:
			_descent_controller = existing
			return
	# None found: create our own.
	var dc: Node = _PDC_SCRIPT.new() as Node
	dc.name = "PlanetDescentController"
	add_child(dc)
	_descent_controller = dc

func _find_node_by_class_name(start: Node, target_class: String) -> Node:
	if start == null:
		return null
	var scr: Script = start.get_script()
	if scr != null and scr.get_global_name() == target_class:
		return start
	for child: Node in start.get_children():
		var found: Node = _find_node_by_class_name(child, target_class)
		if found != null:
			return found
	return null

func _find_flight_controller() -> FlightController:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	var node: Node = _find_node_by_class_name(tree.root, "FlightController")
	if node != null and node is FlightController:
		return node as FlightController
	return null

## Searches the scene tree for a node whose script resource path matches.
func _find_node_by_script(start: Node, script_path: String) -> Node:
	if start == null:
		return null
	var scr: Script = start.get_script()
	if scr != null and scr.resource_path == script_path:
		return start
	for child: Node in start.get_children():
		var found: Node = _find_node_by_script(child, script_path)
		if found != null:
			return found
	return null

# ==============================================================================
# Landing Sequence Controller Integration
# ==============================================================================

## Resolves the LandingSequenceController from autoloads or the scene tree and
## connects its landing_complete / takeoff_complete signals.
func _resolve_landing_sequence_controller() -> void:
	if _landing_sequence_controller != null and is_instance_valid(_landing_sequence_controller):
		_connect_landing_sequence_signals()
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	# Check autoloads first.
	var autoload: Node = tree.root.get_node_or_null("/root/LandingSequenceController")
	if autoload != null:
		_landing_sequence_controller = autoload
		_connect_landing_sequence_signals()
		return
	# Search the scene tree by script resource path.
	var found: Node = _find_node_by_script(tree.root, "res://scripts/LandingSequenceController.gd")
	if found != null:
		_landing_sequence_controller = found
		_connect_landing_sequence_signals()
	else:
		push_warning("PlanetEntryManager: LandingSequenceController not found; cinematic landing animations skipped.")

func _connect_landing_sequence_signals() -> void:
	if _landing_sequence_controller == null or not is_instance_valid(_landing_sequence_controller):
		return
	var lsc: Node = _landing_sequence_controller
	if lsc.has_signal("landing_complete"):
		if not lsc.landing_complete.is_connected(_on_lsc_landing_complete):
			lsc.landing_complete.connect(_on_lsc_landing_complete)
	if lsc.has_signal("takeoff_complete"):
		if not lsc.takeoff_complete.is_connected(_on_lsc_takeoff_complete):
			lsc.takeoff_complete.connect(_on_lsc_takeoff_complete)

## Triggers the cinematic landing animation via the landing sequence controller.
## Guards against double-triggering if the controller already auto-connected to
## the descent controller's landing_complete signal.
func _trigger_landing_sequence(position: Vector3) -> void:
	if _landing_sequence_controller == null or not is_instance_valid(_landing_sequence_controller):
		return
	if not _landing_sequence_controller.has_method("start_landing_sequence"):
		return
	# Avoid double-triggering if the controller already started the animation.
	if _landing_sequence_controller.has_method("is_landing_sequence_active"):
		if _landing_sequence_controller.is_landing_sequence_active():
			return
	var ship: Node3D = _flight_controller
	if ship == null or not is_instance_valid(ship):
		return
	var normal: Vector3 = Vector3.UP
	if _descent_controller != null and is_instance_valid(_descent_controller) and _descent_controller.has_method("get_surface_normal"):
		normal = _descent_controller.get_surface_normal()
	_landing_sequence_controller.start_landing_sequence(ship, position, normal)

## Handler for LandingSequenceController.landing_complete(). The cinematic
## landing animation has finished; ensure the character controller and camera
## are spawned (idempotent via the _character_spawned guard).
func _on_lsc_landing_complete() -> void:
	var position: Vector3 = Vector3.ZERO
	if _flight_controller != null and is_instance_valid(_flight_controller):
		position = _flight_controller.global_position
	elif _descent_controller != null and is_instance_valid(_descent_controller) and _descent_controller.has_method("get_surface_lock_position"):
		position = _descent_controller.get_surface_lock_position()
	_spawn_character_and_camera(position)
	# Now that the cinematic ALIGN->DESCEND->TOUCHDOWN->SETTLE animation has
	# finished, hide/disable the ship. Hiding earlier would make the landing
	# cinematic invisible.
	_disable_ship()

## Handler for LandingSequenceController.takeoff_complete(). The takeoff
## animation has finished; re-enable the ship for flight.
func _on_lsc_takeoff_complete() -> void:
	_enable_ship()

## Notifies the LandingSequenceController that a staged-cinematics phase is
## ready to advance. Uses the cached controller reference with a fallback tree
## lookup so the call is safe even before _resolve_landing_sequence_controller()
## has run. All calls are null-safe and silently skipped if the controller or
## method is unavailable.
func _notify_landing_phase_ready(method_name: String) -> void:
	var ctrl: Node = _landing_sequence_controller
	if ctrl == null or not is_instance_valid(ctrl):
		var tree: SceneTree = get_tree()
		if tree != null and tree.root != null:
			ctrl = tree.root.get_node_or_null("/root/LandingSequenceController")
	if ctrl != null and ctrl.has_method(method_name):
		ctrl.call(method_name)

# ==============================================================================
# Descent Audio Controller Integration
# ==============================================================================

## Resolves the DescentAudioController from autoloads or the scene tree.
func _resolve_descent_audio_controller() -> void:
	if _descent_audio_controller != null and is_instance_valid(_descent_audio_controller):
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	# Check autoloads first.
	var autoload: Node = tree.root.get_node_or_null("/root/DescentAudioController")
	if autoload != null:
		_descent_audio_controller = autoload
		return
	# Search the scene tree by script resource path.
	var found: Node = _find_node_by_script(tree.root, "res://scripts/DescentAudioController.gd")
	if found != null:
		_descent_audio_controller = found
	else:
		push_warning("PlanetEntryManager: DescentAudioController not found; descent soundscape skipped.")

## Activates or deactivates the descent soundscape.
func _set_descent_audio_active(active: bool) -> void:
	if _descent_audio_controller == null or not is_instance_valid(_descent_audio_controller):
		return
	if _descent_audio_controller.has_method("set_active"):
		_descent_audio_controller.set_active(active)

# ==============================================================================
# Public API
# ==============================================================================

## Returns true while a descent sequence is active.
func is_descent_active() -> bool:
	return _descent_active

## Returns true while the player is on foot outside the ship.
func is_on_foot() -> bool:
	return _on_foot

## Returns the currently targeted planet node, or null.
func get_active_planet() -> ProceduralPlanet:
	return _active_planet

## Returns the resolved PlanetDescentController, or null.
func get_descent_controller() -> Node:
	return _descent_controller

## Returns the resolved PlanetSurfaceManager, or null.
func get_surface_manager() -> PlanetSurfaceManager:
	return _surface_manager

## Returns the resolved OceanSystem, or null.
func get_ocean_system() -> OceanSystem:
	return _ocean_system

## Returns the resolved PlanetTerrainGenerator, or null.
func get_terrain_generator() -> PlanetTerrainGenerator:
	return _terrain_generator

## Returns the resolved AtmosphereVisualSystem, or null.
func get_atmosphere_visual_system() -> AtmosphereVisualSystem:
	return _atmosphere_visual_system

## Returns the resolved LandingSequenceController, or null.
func get_landing_sequence_controller() -> Node:
	return _landing_sequence_controller

## Returns the resolved DescentAudioController, or null.
func get_descent_audio_controller() -> Node:
	return _descent_audio_controller

## Forces a full cleanup and return to orbit (e.g. for debug / abort).
func force_return_to_orbit() -> void:
	_cleanup_surface_systems()
	returned_to_orbit.emit()

## Stores the current star system data (star type, planet positions) so the
## manager can make informed descent decisions based on the active system.
## Called by UniverseManager whenever a new star system is loaded.
func set_current_system(system_data: Dictionary) -> void:
	_current_system_data = system_data

## Returns the most recently provided star system data, or an empty dictionary.
func get_current_system() -> Dictionary:
	return _current_system_data

## Called by FlightController._update_nearest_planet() to push the nearest
## planet node and its distance so the flight HUD can render a directional
## marker without re-scanning the scene tree every frame. Also kicks off
## pre-computation of the descent data for the nearest planet so the eventual
## descent activation is cheaper.
func set_nearest_planet(planet: Node, distance: float) -> void:
	_nearest_planet_node = planet
	_nearest_planet_distance = distance
	# Pre-compute descent data for the nearest planet so activation is faster.
	if planet != null and is_instance_valid(planet) and planet is Node3D:
		precompute_descent_data(planet as Node3D)

## Returns the nearest planet node most recently reported by the
## FlightController, or null. Used by the flight HUD directional marker.
func get_nearest_planet() -> Node3D:
	return _nearest_planet_node

## Returns the distance to the nearest planet most recently reported by the
## FlightController, or INF if none has been reported.
func get_nearest_planet_distance() -> float:
	return _nearest_planet_distance
