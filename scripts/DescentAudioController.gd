# ==============================================================================
# DescentAudioController.gd - Planet Descent Soundscape Audio Controller
# BioGenesis-X Ciel Audio Architecture Division
# ==============================================================================
# Bridges the PlanetDescentController 4-layer atmospheric descent state machine
# to the BioAudioDirector / BioAudioSynth procedural audio engine, producing a
# continuous soundscape that evolves through:
#   ORBITAL -> EXOSPHERE -> THERMOSPHERE -> TROPOSPHERE -> SURFACE -> UNDERWATER
#
# Responsibilities:
# - Translates PlanetDescentController layer/state signals into audio layer
#   changes (wind noise, heating hum, star-ambient fade, creature calls).
# - Plays transition stingers (whoosh / thud / splash) on layer changes.
# - Drives per-archetype surface ambience for all 8 planet archetypes.
# - Activates a lowpass underwater filter on water entry / removes on exit.
# - Coordinates tension index, planet proximity, and environment events with
#   the existing BioAudioDirector / BioAudioSynth APIs.
#
# This controller does NOT modify BioAudioSynth or BioAudioDirector; it only
# consumes their public APIs and a small set of directly-set synth parameters
# (wind / noise / star-ambient amplitudes) for fine-grained descent blending.
#
# NOTE: PlanetDescentController enum values are mirrored as integer constants
# below (rather than referenced via the class_name) to keep this script fully
# self-contained and avoid a hard compile-time dependency on the controller
# script. The values are stable and documented in PlanetDescentController.gd.
# ==============================================================================
extends Node

# ------------------------------------------------------------------------------
# Descent Audio Layer Enum
# ------------------------------------------------------------------------------
enum DescentAudioLayer {
	ORBITAL,      ## 0 — silence + existing star-type ambient soundscape
	EXOSPHERE,    ## 1 — star ambient + faint atmospheric whisper begins
	THERMOSPHERE, ## 2 — wind noise building, heating hum, star ambient fading
	TROPOSPHERE,  ## 3 — full wind, muffled thunder, creature calls, star gone
	SURFACE,      ## 4 — ground ambience, creature sounds, wind through grass, breathing
	UNDERWATER,   ## 5 — muffled everything, bubbles, pressure creaks, whale-song
}

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal audio_layer_changed(old_layer: int, new_layer: int)
signal stinger_played(stinger_name: String)

# ------------------------------------------------------------------------------
# PlanetDescentController enum mirrors (see NOTE in file header)
# ------------------------------------------------------------------------------
# AtmosphereLayer
const _ATMO_SPACE: int = 0
const _ATMO_EXOSPHERE: int = 1
const _ATMO_THERMOSPHERE: int = 2
const _ATMO_TROPOSPHERE: int = 3
const _ATMO_SURFACE: int = 4
const _ATMO_UNDERWATER: int = 5
const _ATMO_GAS_GIANT_DEEP: int = 6
# DescentState
const _STATE_ORBITAL: int = 0
const _STATE_EXOSPHERE_ENTRY: int = 1
const _STATE_THERMOSPHERE: int = 2
const _STATE_TROPOSPHERE: int = 3
const _STATE_SURFACE_APPROACH: int = 4
const _STATE_LANDED: int = 5
const _STATE_ON_FOOT: int = 6
const _STATE_SUBMERSIBLE: int = 7
const _STATE_ABORT_ASCENT: int = 8
const _STATE_GAS_GIANT_DESCENT: int = 9
# PlanetArchetype
const _ARCH_MOLTEN: int = 0
const _ARCH_METALLIC_BARREN: int = 1
const _ARCH_DESERT_ARID: int = 2
const _ARCH_TERRAN_OCEANIC: int = 3
const _ARCH_ICE_WORLD: int = 4
const _ARCH_GAS_GIANT_JOVIAN: int = 5
const _ARCH_GAS_GIANT_ICE: int = 6
const _ARCH_RADIOTROPHIC_BIO: int = 7

# ------------------------------------------------------------------------------
# EnvironmentEvent integer constants (mirror BioAudioSynth.EnvironmentEvent)
# ------------------------------------------------------------------------------
const _ENV_MOLECULAR_CLOUD: int = 5   ## dense, muffled, deep — underwater / dense atmosphere
const _ENV_SOLAR_FLARE: int = 12      ## radiation surge — atmospheric heating crackle

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _descent_controller: Node = null
var _audio_director: Node = null
var _audio_synth: Node = null
var _current_layer: int = DescentAudioLayer.ORBITAL
var _previous_layer: int = DescentAudioLayer.ORBITAL
var _active: bool = false
var _target_archetype: int = _ARCH_TERRAN_OCEANIC
var _has_archetype: bool = false

# Periodic ambient event timers (seconds)
var _creature_call_timer: float = 0.0
var _creature_call_interval: float = 8.0
var _creak_timer: float = 0.0
var _creak_interval: float = 12.0
var _breath_timer: float = 0.0
var _breath_interval: float = 5.0
var _bubble_timer: float = 0.0
var _bubble_interval: float = 3.0

# Underwater lowpass filter (applied to Master bus dynamically)
var _underwater_lp: AudioEffectLowPassFilter = null
var _underwater_lp_bus_idx: int = -1
var _underwater_lp_effect_idx: int = -1
var _underwater_filter_active: bool = false

# Cached base star-ambient amplitudes (captured once so we can scale them
# during descent without compounding the scaling each frame).
var _star_base_radiation_amp: float = 0.0
var _star_base_gravity_amp: float = 0.0
var _star_base_shimmer_amp: float = 0.0
var _star_base_cached: bool = false

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	set_process(false)  # Only process when active and initialized
	# Auto-connect to the PlanetDescentController autoload so the descent
	# soundscape is wired as soon as the game starts. PlanetDescentController is
	# registered before this autoload, so it is already in the scene tree here.
	call_deferred("_auto_initialize")

func _exit_tree() -> void:
	# Ensure the underwater filter is never left on the bus when freed.
	_deactivate_underwater_filter()
	_disconnect_signals()

## Resolves the PlanetDescentController autoload from the scene tree and
## initializes the descent audio bridge automatically on game start.
func _auto_initialize() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var dc: Node = tree.root.get_node_or_null("/root/PlanetDescentController")
	if dc != null:
		initialize(dc)

func _process(delta: float) -> void:
	if not _active:
		return
	_update_periodic_ambience(delta)

# ==============================================================================
# Public API
# ==============================================================================

## Connects to a PlanetDescentController instance and resolves audio autoloads.
## Call this once after the descent controller and audio autoloads are available.
func initialize(descent_controller: Node) -> void:
	_descent_controller = descent_controller
	_resolve_audio_nodes()
	_connect_signals()
	# Seed archetype from the descent controller if a target is already set.
	if _descent_controller and _descent_controller.has_method("has_target_planet") and _descent_controller.has_target_planet():
		_target_archetype = _descent_controller.get_target_archetype()
		_has_archetype = true

## Enables or disables the descent soundscape. When deactivated, audio is
## gently returned to the orbital/flight baseline.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	set_process(active)
	if active:
		_resolve_audio_nodes()
		_apply_layer(_current_layer)
	else:
		# Return to orbital baseline.
		_deactivate_underwater_filter()
		_apply_orbital_baseline()

## Manually sets the audio layer (clamped to the DescentAudioLayer enum).
func update_layer(layer: int) -> void:
	var clamped: int = clampi(layer, DescentAudioLayer.ORBITAL, DescentAudioLayer.UNDERWATER)
	if clamped == _current_layer:
		return
	_previous_layer = _current_layer
	_current_layer = clamped
	_play_layer_transition_stinger(_previous_layer, _current_layer)
	_apply_layer(_current_layer)
	audio_layer_changed.emit(_previous_layer, _current_layer)

## Returns the current DescentAudioLayer index.
func get_current_layer() -> int:
	return _current_layer

## Returns the previous DescentAudioLayer index.
func get_previous_layer() -> int:
	return _previous_layer

## Returns true when the descent soundscape is active.
func is_active() -> bool:
	return _active

# ==============================================================================
# Signal Connection
# ==============================================================================

func _connect_signals() -> void:
	if _descent_controller == null:
		return
	if not _descent_controller.is_connected("descent_state_changed", _on_descent_state_changed):
		_descent_controller.descent_state_changed.connect(_on_descent_state_changed)
	if not _descent_controller.is_connected("layer_transition", _on_layer_transition):
		_descent_controller.layer_transition.connect(_on_layer_transition)
	if not _descent_controller.is_connected("landing_complete", _on_landing_complete):
		_descent_controller.landing_complete.connect(_on_landing_complete)
	if not _descent_controller.is_connected("takeoff_complete", _on_takeoff_complete):
		_descent_controller.takeoff_complete.connect(_on_takeoff_complete)
	if not _descent_controller.is_connected("entered_water", _on_entered_water):
		_descent_controller.entered_water.connect(_on_entered_water)
	if not _descent_controller.is_connected("exited_water", _on_exited_water):
		_descent_controller.exited_water.connect(_on_exited_water)

func _disconnect_signals() -> void:
	if _descent_controller == null:
		return
	if _descent_controller.is_connected("descent_state_changed", _on_descent_state_changed):
		_descent_controller.descent_state_changed.disconnect(_on_descent_state_changed)
	if _descent_controller.is_connected("layer_transition", _on_layer_transition):
		_descent_controller.layer_transition.disconnect(_on_layer_transition)
	if _descent_controller.is_connected("landing_complete", _on_landing_complete):
		_descent_controller.landing_complete.disconnect(_on_landing_complete)
	if _descent_controller.is_connected("takeoff_complete", _on_takeoff_complete):
		_descent_controller.takeoff_complete.disconnect(_on_takeoff_complete)
	if _descent_controller.is_connected("entered_water", _on_entered_water):
		_descent_controller.entered_water.disconnect(_on_entered_water)
	if _descent_controller.is_connected("exited_water", _on_exited_water):
		_descent_controller.exited_water.disconnect(_on_exited_water)

# ==============================================================================
# Audio Node Resolution
# ==============================================================================

func _resolve_audio_nodes() -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	if _audio_director == null:
		_audio_director = tree.root.get_node_or_null("/root/BioAudioDirector")
	if _audio_synth == null:
		_audio_synth = tree.root.get_node_or_null("/root/BioAudioSynth")

# ==============================================================================
# Signal Handlers
# ==============================================================================

func _on_descent_state_changed(_old_state: int, new_state: int) -> void:
	if not _active:
		return
	# Refresh archetype from the descent controller whenever the state changes.
	if _descent_controller and _descent_controller.has_method("get_target_archetype"):
		_target_archetype = _descent_controller.get_target_archetype()
		_has_archetype = true
	# Drive tension from the descent state (heating phases raise tension).
	_apply_state_tension(new_state)

func _on_layer_transition(new_layer: int, _layer_name: String) -> void:
	if not _active:
		return
	var mapped: int = _map_atmosphere_layer(new_layer)
	update_layer(mapped)

func _on_landing_complete(planet_archetype: int, _position: Vector3) -> void:
	_target_archetype = planet_archetype
	_has_archetype = true
	if not _active:
		return
	# Landing thud stinger.
	_play_landing_thud()
	# Shift to surface ambience.
	update_layer(DescentAudioLayer.SURFACE)

func _on_takeoff_complete() -> void:
	if not _active:
		return
	# Shift back to flight / orbital audio.
	_deactivate_underwater_filter()
	update_layer(DescentAudioLayer.ORBITAL)
	# Restore flight baseline via the director.
	if _audio_director and _audio_director.has_method("clear_environment_event"):
		_audio_director.clear_environment_event()
	if _audio_director and _audio_director.has_method("reset_to_scene_base"):
		_audio_director.reset_to_scene_base()

func _on_entered_water(_depth_m: float) -> void:
	if not _active:
		return
	_activate_underwater_filter()
	_play_splash_stinger()
	update_layer(DescentAudioLayer.UNDERWATER)

func _on_exited_water() -> void:
	if not _active:
		return
	_deactivate_underwater_filter()
	# Return to the troposphere/surface layer depending on current state.
	if _descent_controller and _descent_controller.has_method("get_current_layer"):
		var atmo: int = _descent_controller.get_current_layer()
		update_layer(_map_atmosphere_layer(atmo))
	else:
		update_layer(DescentAudioLayer.TROPOSPHERE)

# ==============================================================================
# Layer Mapping
# ==============================================================================

## Maps a PlanetDescentController.AtmosphereLayer index to a DescentAudioLayer.
func _map_atmosphere_layer(atmo_layer: int) -> int:
	match atmo_layer:
		_ATMO_SPACE:
			return DescentAudioLayer.ORBITAL
		_ATMO_EXOSPHERE:
			return DescentAudioLayer.EXOSPHERE
		_ATMO_THERMOSPHERE:
			return DescentAudioLayer.THERMOSPHERE
		_ATMO_TROPOSPHERE:
			return DescentAudioLayer.TROPOSPHERE
		_ATMO_SURFACE:
			return DescentAudioLayer.SURFACE
		_ATMO_UNDERWATER:
			return DescentAudioLayer.UNDERWATER
		_ATMO_GAS_GIANT_DEEP:
			# Gas-giant deep descent behaves like an intensified troposphere.
			return DescentAudioLayer.TROPOSPHERE
		_:
			return DescentAudioLayer.ORBITAL

# ==============================================================================
# Layer Application
# ==============================================================================

## Applies the full audio profile for the given descent audio layer.
func _apply_layer(layer: int) -> void:
	_resolve_audio_nodes()
	match layer:
		DescentAudioLayer.ORBITAL:
			_apply_orbital_baseline()
		DescentAudioLayer.EXOSPHERE:
			_apply_exosphere()
		DescentAudioLayer.THERMOSPHERE:
			_apply_thermosphere()
		DescentAudioLayer.TROPOSPHERE:
			_apply_troposphere()
		DescentAudioLayer.SURFACE:
			_apply_surface()
		DescentAudioLayer.UNDERWATER:
			_apply_underwater()
		_:
			_apply_orbital_baseline()

# ------------------------------------------------------------------------------
# ORBITAL — silence + existing star-type ambient soundscape
# ------------------------------------------------------------------------------
func _apply_orbital_baseline() -> void:
	# Clear any descent environment event; star ambient is managed by the director.
	if _audio_director and _audio_director.has_method("clear_environment_event"):
		_audio_director.clear_environment_event()
	# Remove planet proximity influence.
	if _audio_director and _audio_director.has_method("set_planet_proximity"):
		_audio_director.set_planet_proximity(-1, 0.0)
	# Low tension for serene orbit.
	_set_tension(0.02)
	# Reset direct synth parameters to neutral.
	_set_synth_noise_levels(0.0, 0.0, 0.0)
	_set_synth_planet_ambient(0.0, 0.0)
	_set_synth_star_ambient_scale(1.0)  # full star ambient

# ------------------------------------------------------------------------------
# EXOSPHERE — star ambient + faint atmospheric whisper begins
# ------------------------------------------------------------------------------
func _apply_exosphere() -> void:
	# Keep star ambient at near-full; begin a faint whisper via mid noise.
	if _audio_director and _audio_director.has_method("set_planet_proximity"):
		_audio_director.set_planet_proximity(_planet_type_for_director(), 0.25)
	_set_tension(0.08)
	_set_synth_noise_levels(0.0, 0.04, 0.0)  # faint whisper
	_set_synth_planet_ambient(0.05, 0.0)
	_set_synth_star_ambient_scale(0.9)  # star ambient still strong

# ------------------------------------------------------------------------------
# THERMOSPHERE — wind noise building, heating hum, star ambient fading
# ------------------------------------------------------------------------------
func _apply_thermosphere() -> void:
	# Heating crackle via the SOLAR_FLARE environment event (radiation surge).
	if _audio_director and _audio_director.has_method("set_environment_event"):
		_audio_director.set_environment_event(_ENV_SOLAR_FLARE, 0.5)
	if _audio_director and _audio_director.has_method("set_planet_proximity"):
		_audio_director.set_planet_proximity(_planet_type_for_director(), 0.55)
	# Higher tension — atmospheric entry heating.
	_set_tension(0.35)
	# Wind building (mid noise), heating hum (high noise hiss).
	_set_synth_noise_levels(0.05, 0.18, 0.10)
	_set_synth_planet_ambient(0.12, 0.0)
	_set_synth_star_ambient_scale(0.5)  # star ambient fading

# ------------------------------------------------------------------------------
# TROPOSPHERE — full wind, muffled thunder, creature calls, star gone
# ------------------------------------------------------------------------------
func _apply_troposphere() -> void:
	# Dense atmosphere: use MOLECULAR_CLOUD muffled bed for gas giants / dense worlds.
	var is_dense: bool = _is_dense_atmosphere_archetype()
	if is_dense and _audio_director and _audio_director.has_method("set_environment_event"):
		_audio_director.set_environment_event(_ENV_MOLECULAR_CLOUD, 0.4)
	elif _audio_director and _audio_director.has_method("clear_environment_event"):
		_audio_director.clear_environment_event()
	if _audio_director and _audio_director.has_method("set_planet_proximity"):
		_audio_director.set_planet_proximity(_planet_type_for_director(), 0.8)
	_set_tension(0.18)
	# Full wind (mid), muffled thunder (sub rumble).
	_set_synth_noise_levels(0.12, 0.30, 0.02)
	_set_synth_planet_ambient(0.22, 0.0)
	_set_synth_star_ambient_scale(0.0)  # star ambient gone

# ------------------------------------------------------------------------------
# SURFACE — per-archetype ground ambience, creature sounds, breathing
# ------------------------------------------------------------------------------
func _apply_surface() -> void:
	# Clear atmospheric environment events; surface is its own ambience.
	if _audio_director and _audio_director.has_method("clear_environment_event"):
		_audio_director.clear_environment_event()
	# Full planet proximity when on the surface.
	if _audio_director and _audio_director.has_method("set_planet_proximity"):
		_audio_director.set_planet_proximity(_planet_type_for_director(), 1.0)
	# Lower tension on the surface (serene ground ambience).
	_set_tension(0.05)
	# Apply per-archetype surface noise + ambient parameters.
	_apply_archetype_surface_ambience()
	_set_synth_star_ambient_scale(0.0)

# ------------------------------------------------------------------------------
# UNDERWATER — muffled everything, bubbles, pressure creaks, whale-song
# ------------------------------------------------------------------------------
func _apply_underwater() -> void:
	# Muffled, dense, deep — MOLECULAR_CLOUD environment bed.
	if _audio_director and _audio_director.has_method("set_environment_event"):
		_audio_director.set_environment_event(_ENV_MOLECULAR_CLOUD, 0.7)
	if _audio_director and _audio_director.has_method("set_planet_proximity"):
		_audio_director.set_planet_proximity(_planet_type_for_director(), 1.0)
	_set_tension(0.06)
	# Muffled: sub rumble preserved, mid heavily reduced, high almost gone.
	_set_synth_noise_levels(0.10, 0.05, 0.01)
	_set_synth_planet_ambient(0.08, 0.0)
	_set_synth_star_ambient_scale(0.0)

## Returns the target archetype for the director's set_planet_proximity call,
## or -1 when no archetype is set (meaning "no planet nearby").
func _planet_type_for_director() -> int:
	return _target_archetype if _has_archetype else -1

# ==============================================================================
# Per-Archetype Surface Ambience
# ==============================================================================

## Applies the noise-bed and ambient-frequency profile for the target archetype
## while on the SURFACE layer.
func _apply_archetype_surface_ambience() -> void:
	if not _has_archetype:
		_set_synth_noise_levels(0.05, 0.10, 0.0)
		_set_synth_planet_ambient(0.10, 200.0)
		return
	match _target_archetype:
		_ARCH_MOLTEN:
			# Lava crackling (high hiss), volcanic rumble (sub), heat distortion.
			_set_synth_noise_levels(0.18, 0.06, 0.14)
			_set_synth_planet_ambient(0.20, 80.0)
		_ARCH_METALLIC_BARREN:
			# Metallic echo (ambient resonance), wind whistling, occasional rock clatter.
			_set_synth_noise_levels(0.02, 0.12, 0.04)
			_set_synth_planet_ambient(0.16, 440.0)
		_ARCH_DESERT_ARID:
			# Sand wind (mid), distant dune rumble (sub), occasional creature.
			_set_synth_noise_levels(0.06, 0.22, 0.02)
			_set_synth_planet_ambient(0.08, 0.0)
		_ARCH_TERRAN_OCEANIC:
			# Ocean waves (sub + mid), bird calls, wind through trees, insects.
			_set_synth_noise_levels(0.10, 0.16, 0.03)
			_set_synth_planet_ambient(0.18, 200.0)
		_ARCH_ICE_WORLD:
			# Ice cracking (high), wind howling (mid), crystalline chimes (ambient 880).
			_set_synth_noise_levels(0.03, 0.20, 0.08)
			_set_synth_planet_ambient(0.14, 880.0)
		_ARCH_GAS_GIANT_JOVIAN:
			# Massive storm turbulence (all bands), deep thunder (sub).
			_set_synth_noise_levels(0.22, 0.28, 0.06)
			_set_synth_planet_ambient(0.20, 50.0)
		_ARCH_GAS_GIANT_ICE:
			# Methane wind (mid higher), higher-pitched storms.
			_set_synth_noise_levels(0.14, 0.24, 0.10)
			_set_synth_planet_ambient(0.16, 70.0)
		_ARCH_RADIOTROPHIC_BIO:
			# Bioluminescent hum (ambient 330), organic pulses, spore whispers.
			_set_synth_noise_levels(0.04, 0.08, 0.05)
			_set_synth_planet_ambient(0.20, 330.0)
		_:
			_set_synth_noise_levels(0.05, 0.10, 0.0)
			_set_synth_planet_ambient(0.10, 200.0)

## Returns true for archetypes with dense / turbulent atmospheres.
func _is_dense_atmosphere_archetype() -> bool:
	if not _has_archetype:
		return false
	return _target_archetype == _ARCH_GAS_GIANT_JOVIAN \
		or _target_archetype == _ARCH_GAS_GIANT_ICE \
		or _target_archetype == _ARCH_MOLTEN \
		or _target_archetype == _ARCH_RADIOTROPHIC_BIO

# ==============================================================================
# State Tension
# ==============================================================================

## Applies a tension index appropriate for the descent state (heating phases).
func _apply_state_tension(descent_state: int) -> void:
	if _descent_controller == null:
		return
	# Use the controller's live heating intensity when available for accuracy.
	var heating: float = 0.0
	if _descent_controller.has_method("get_heating_intensity"):
		heating = _descent_controller.get_heating_intensity()
	match descent_state:
		_STATE_ORBITAL, _STATE_EXOSPHERE_ENTRY:
			_set_tension(0.02)
		_STATE_THERMOSPHERE, _STATE_ABORT_ASCENT:
			_set_tension(clampf(0.25 + heating * 0.4, 0.0, 0.7))
		_STATE_TROPOSPHERE:
			_set_tension(clampf(0.12 + heating * 0.25, 0.0, 0.5))
		_STATE_GAS_GIANT_DESCENT:
			_set_tension(clampf(0.30 + heating * 0.4, 0.0, 0.8))
		_STATE_SURFACE_APPROACH:
			_set_tension(clampf(0.10 + heating * 0.2, 0.0, 0.4))
		_STATE_LANDED, _STATE_ON_FOOT, _STATE_SUBMERSIBLE:
			_set_tension(0.05)
		_:
			_set_tension(0.02)

# ==============================================================================
# Transition Stingers
# ==============================================================================

## Plays the appropriate stinger for a layer transition.
func _play_layer_transition_stinger(old_layer: int, new_layer: int) -> void:
	# Splash: entering water.
	if new_layer == DescentAudioLayer.UNDERWATER:
		_play_splash_stinger()
		return
	# Thud: landing on the surface.
	if new_layer == DescentAudioLayer.SURFACE and old_layer != DescentAudioLayer.UNDERWATER:
		_play_landing_thud()
		return
	# Whoosh: entering / advancing through the atmosphere.
	if _is_atmospheric_entry(old_layer, new_layer):
		_play_whoosh_stinger()

func _is_atmospheric_entry(old_layer: int, new_layer: int) -> bool:
	# Any forward progression into a denser atmospheric layer is an entry whoosh.
	return new_layer > old_layer and new_layer != DescentAudioLayer.SURFACE \
		and new_layer != DescentAudioLayer.UNDERWATER

## Whoosh stinger for atmospheric entry — uses the director's wave_engage event
## (which carries its own rising Shepard-tone stinger) for a dramatic transition.
func _play_whoosh_stinger() -> void:
	if _audio_director and _audio_director.has_method("transition_to_event"):
		_audio_director.transition_to_event("wave_engage")
	stinger_played.emit("whoosh")

## Thud stinger for landing — a sub-bass boom via the synth's hyperwave boom.
func _play_landing_thud() -> void:
	if _audio_synth and _audio_synth.has_method("play_hyperwave_boom"):
		_audio_synth.play_hyperwave_boom()
	stinger_played.emit("thud")

## Splash stinger for water entry — shield impact (splash transient) + spore
## release (water spray diffusion).
func _play_splash_stinger() -> void:
	if _audio_synth and _audio_synth.has_method("play_shield_impact"):
		_audio_synth.play_shield_impact()
	if _audio_synth and _audio_synth.has_method("play_spore_cloud_release"):
		_audio_synth.play_spore_cloud_release()
	stinger_played.emit("splash")

# ==============================================================================
# Periodic Ambient Events
# ==============================================================================

func _update_periodic_ambience(delta: float) -> void:
	# Creature calls — bio planets in troposphere / surface / underwater.
	if _should_play_creature_calls():
		_creature_call_timer -= delta
		if _creature_call_timer <= 0.0:
			_creature_call_timer = _creature_call_interval + randf_range(-2.0, 2.0)
			_play_creature_call()
	else:
		_creature_call_timer = 0.0

	# Creaks / cracks — ice, metallic, underwater pressure, gas giants.
	if _should_play_creaks():
		_creak_timer -= delta
		if _creak_timer <= 0.0:
			_creak_timer = _creak_interval + randf_range(-3.0, 3.0)
			_play_creak()
	else:
		_creak_timer = 0.0

	# Breathing — on the surface (on foot / landed).
	if _current_layer == DescentAudioLayer.SURFACE:
		_breath_timer -= delta
		if _breath_timer <= 0.0:
			_breath_timer = _breath_interval + randf_range(-1.0, 1.0)
			_play_breath()
	else:
		_breath_timer = 0.0

	# Bubbles — underwater.
	if _current_layer == DescentAudioLayer.UNDERWATER:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_bubble_timer = _bubble_interval + randf_range(-0.8, 0.8)
			_play_bubble()
	else:
		_bubble_timer = 0.0

func _should_play_creature_calls() -> bool:
	if not _has_archetype:
		return false
	if _current_layer == DescentAudioLayer.ORBITAL or _current_layer == DescentAudioLayer.EXOSPHERE:
		return false
	# Bio and oceanic planets have rich creature choruses.
	if _target_archetype == _ARCH_TERRAN_OCEANIC \
		or _target_archetype == _ARCH_RADIOTROPHIC_BIO:
		return true
	# Desert worlds have occasional creatures.
	if _target_archetype == _ARCH_DESERT_ARID \
		and _current_layer == DescentAudioLayer.SURFACE:
		return true
	return false

func _should_play_creaks() -> bool:
	if not _has_archetype:
		return false
	if _current_layer == DescentAudioLayer.UNDERWATER:
		return true  # pressure creaks
	if _current_layer == DescentAudioLayer.SURFACE:
		if _target_archetype == _ARCH_ICE_WORLD:
			return true  # ice cracking
		if _target_archetype == _ARCH_METALLIC_BARREN:
			return true  # rock clatter
	if _current_layer == DescentAudioLayer.TROPOSPHERE:
		if _target_archetype == _ARCH_GAS_GIANT_JOVIAN \
			or _target_archetype == _ARCH_GAS_GIANT_ICE:
			return true  # deep thunder creaks
	return false

func _play_creature_call() -> void:
	if _audio_synth and _audio_synth.has_method("play_creature_vocalization"):
		# Whale-song is lower-pitched for oceanic underwater; higher for bio.
		var pitch: float = 1.0
		if _current_layer == DescentAudioLayer.UNDERWATER:
			pitch = 0.6  # deep whale-song
		elif _target_archetype == _ARCH_RADIOTROPHIC_BIO:
			pitch = 1.3  # ethereal bio pulses
		_audio_synth.play_creature_vocalization(pitch)

func _play_creak() -> void:
	if _audio_synth and _audio_synth.has_method("play_chitin_creak"):
		_audio_synth.play_chitin_creak()

func _play_breath() -> void:
	# A breath is represented by a soft heartbeat pulse (lub-dub = inhale-exhale).
	if _audio_synth and _audio_synth.has_method("play_heartbeat_pulse"):
		_audio_synth.play_heartbeat_pulse()

func _play_bubble() -> void:
	# Bubbles are represented by a soft UI chirp (glassy water-drop micro-transient).
	if _audio_synth and _audio_synth.has_method("play_ui_click"):
		_audio_synth.play_ui_click(true)

# ==============================================================================
# Underwater Lowpass Filter
# ==============================================================================

func _activate_underwater_filter() -> void:
	if _underwater_filter_active:
		return
	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx < 0:
		return
	if _underwater_lp == null:
		_underwater_lp = AudioEffectLowPassFilter.new()
		_underwater_lp.cutoff_hz = 850.0
		_underwater_lp.resonance = 1.2
	AudioServer.add_bus_effect(bus_idx, _underwater_lp)
	_underwater_lp_bus_idx = bus_idx
	_underwater_lp_effect_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
	_underwater_filter_active = true

func _deactivate_underwater_filter() -> void:
	if not _underwater_filter_active:
		return
	if _underwater_lp_bus_idx >= 0 and _underwater_lp_effect_idx >= 0:
		var count: int = AudioServer.get_bus_effect_count(_underwater_lp_bus_idx)
		if _underwater_lp_effect_idx < count:
			AudioServer.remove_bus_effect(_underwater_lp_bus_idx, _underwater_lp_effect_idx)
	_underwater_lp_bus_idx = -1
	_underwater_lp_effect_idx = -1
	_underwater_filter_active = false

# ==============================================================================
# Synth Parameter Helpers (direct parameter setting)
# ==============================================================================

## Sets the 3-band noise texture bed amplitudes (sub, mid, high).
func _set_synth_noise_levels(sub: float, mid: float, high: float) -> void:
	if _audio_synth == null:
		return
	if "_noise_sub_amp" in _audio_synth:
		_audio_synth.set("_noise_sub_amp", clampf(sub, 0.0, 1.0))
	if "_noise_mid_amp" in _audio_synth:
		_audio_synth.set("_noise_mid_amp", clampf(mid, 0.0, 1.0))
	if "_noise_high_amp" in _audio_synth:
		_audio_synth.set("_noise_high_amp", clampf(high, 0.0, 1.0))

## Sets the planet ambient amplitude and carrier frequency.
func _set_synth_planet_ambient(amp: float, freq: float) -> void:
	if _audio_synth == null:
		return
	if "_planet_ambient_amp" in _audio_synth:
		_audio_synth.set("_planet_ambient_amp", clampf(amp, 0.0, 1.0))
	if "_planet_ambient_freq" in _audio_synth:
		_audio_synth.set("_planet_ambient_freq", maxf(freq, 0.0))

## Scales the star-type ambient amplitudes (radiation, gravity drone, shimmer)
## by the given factor so the star soundscape fades during atmospheric descent.
func _set_synth_star_ambient_scale(scale: float) -> void:
	if _audio_synth == null:
		return
	_cache_star_base_amplitudes()
	var s: float = clampf(scale, 0.0, 1.0)
	if "_star_radiation_amp" in _audio_synth:
		_audio_synth.set("_star_radiation_amp", s * _star_base_radiation_amp)
	if "_star_gravity_drone_amp" in _audio_synth:
		_audio_synth.set("_star_gravity_drone_amp", s * _star_base_gravity_amp)
	if "_star_shimmer_amp" in _audio_synth:
		_audio_synth.set("_star_shimmer_amp", s * _star_base_shimmer_amp)

## Captures the current star-ambient amplitudes as the baseline so subsequent
## scaling operations are non-destructive.
func _cache_star_base_amplitudes() -> void:
	if _star_base_cached or _audio_synth == null:
		return
	if "_star_radiation_amp" in _audio_synth:
		_star_base_radiation_amp = float(_audio_synth.get("_star_radiation_amp"))
	if "_star_gravity_drone_amp" in _audio_synth:
		_star_base_gravity_amp = float(_audio_synth.get("_star_gravity_drone_amp"))
	if "_star_shimmer_amp" in _audio_synth:
		_star_base_shimmer_amp = float(_audio_synth.get("_star_shimmer_amp"))
	_star_base_cached = true

## Sets the tension index via the synth (it owns the DTI stem-queue logic).
func _set_tension(dti: float) -> void:
	var clamped: float = clampf(dti, 0.0, 1.0)
	if _audio_synth and _audio_synth.has_method("set_tension_index"):
		_audio_synth.set_tension_index(clamped)
	elif _audio_synth and "tension_index" in _audio_synth:
		_audio_synth.set("tension_index", clamped)
