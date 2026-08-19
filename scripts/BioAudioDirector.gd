# ==============================================================================
# BioAudioDirector.gd - AAA+ Scene & Event Audio Transition Director
# BioGenesis-X Ciel Audio Architecture Division
# ==============================================================================
# Manages smooth audio transitions between scenes, events, and game states.
# Provides per-scene audio profiles with automated crossfades, bus-level
# automation, and event-driven DTI ramps.
#
# FEATURES:
# - Per-scene audio profiles (tension, reverb, stem sets, bus volumes)
# - Equal-power crossfade transitions (0.8s default, configurable)
# - Event-driven transitions (combat, discovery, wave engine, damage)
# - Bus-level automation (master volume, reverb sends, pause ducking)
# - Audio state cleanup on scene exit (stops stale wave engines, resets DTI)
# - Transition overlay (visual fade + audio fade synchronized)
# - Stinger hits on dramatic transitions (combat enter, discovery)
#
# USAGE:
#   BioAudioDirector.transition_to_scene("space_flight")
#   BioAudioDirector.transition_to_event("combat")
#   BioAudioDirector.set_pause_audio(true)
# ==============================================================================
extends Node

# ------------------------------------------------------------------------------
# Scene Audio Profile Definition
# ------------------------------------------------------------------------------
class SceneAudioProfile:
	var name: String
	var tension_index: float
	var music_bpm: float
	var music_theme: int        # MusicTheme enum: 0=EXPLORATION, 1=MENU, 2=CINEMATIC
	var reverb_send: float       # 0.0 = dry, 1.0 = full wet
	var reverb_space: bool       # true = Reverb_Space, false = Reverb_Cockpit
	var master_volume_db: float
	var music_volume_db: float
	var stethoscope: bool
	var wave_engine_off: bool    # force wave engine off on entry
	var ambient_boost: float     # extra noise bed level
	var pad_boost: float         # extra pad level
	var sub_bass_boost: float    # extra sub-bass level

	func _init(p_name: String = "default") -> void:
		name = p_name
		tension_index = 0.0
		music_bpm = 112.0
		music_theme = 0  # EXPLORATION
		reverb_send = 0.0
		reverb_space = false
		master_volume_db = 0.0
		music_volume_db = -3.0
		stethoscope = false
		wave_engine_off = true
		ambient_boost = 0.0
		pad_boost = 0.0
		sub_bass_boost = 0.0

# ------------------------------------------------------------------------------
# Event Transition Definition
# ------------------------------------------------------------------------------
class EventTransition:
	var name: String
	var target_tension: float
	var ramp_duration: float
	var stinger: bool       # play a stinger hit on transition
	var bus_duck_db: float  # temporary bus duck

	func _init(p_name: String = "default") -> void:
		name = p_name
		target_tension = 0.0
		ramp_duration = 2.0
		stinger = false
		bus_duck_db = 0.0

# ------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------
var _profiles: Dictionary = {}  # scene_name -> SceneAudioProfile
var _events: Dictionary = {}    # event_name -> EventTransition
var _current_profile: SceneAudioProfile
var _current_event: EventTransition
var _transition_active: bool = false
var _transition_time: float = 0.0
var _transition_duration: float = 0.8
var _pending_scene_path: String = ""
var _pending_profile: SceneAudioProfile
var _from_profile: SceneAudioProfile

# Bus volume tracking (for smooth fades)
var _master_vol_target: float = 0.0
var _master_vol_current: float = 0.0
var _music_vol_target: float = -3.0
var _music_vol_current: float = -3.0
var _reverb_send_target: float = 0.0
var _reverb_send_current: float = 0.0

# Event ramp state
var _event_tension_ramp_active: bool = false
var _event_tension_from: float = 0.0
var _event_tension_to: float = 0.0
var _event_tension_time: float = 0.0
var _event_tension_duration: float = 2.0
var _event_bus_duck_active: bool = false
var _event_bus_duck_time: float = 0.0
var _event_bus_duck_duration: float = 0.5
var _event_bus_duck_amount: float = 0.0

# Pause state
var _is_paused: bool = false
var _pause_duck_db: float = -6.0

# Visual transition overlay
var _overlay: ColorRect
var _overlay_tween: Tween

# Stinger state (brief dramatic hit)
var _stinger_active: bool = false
var _stinger_time: float = 0.0
var _stinger_phase: float = 0.0
var _stinger_freq: float = 0.0

# Current scene tracking
var _current_scene_name: String = "main_menu"


# ==============================================================================
# Lifecycle
# ==============================================================================
func _ready() -> void:
	_init_profiles()
	_init_events()
	_current_profile = _profiles["main_menu"]
	_current_event = null
	_apply_profile_immediate(_current_profile)
	# Create visual transition overlay
	_create_overlay()
	# Connect to scene tree changes
	get_tree().tree_changed.connect(_on_tree_changed)
	# Connect to UniverseManager system_loaded signal for star-type soundscape
	_connect_to_universe_manager()

func _connect_to_universe_manager() -> void:
	# UniverseManager is an autoload — connect to its system_loaded signal
	var tree := get_tree()
	if tree and tree.root:
		var um := tree.root.get_node_or_null("UniverseManager")
		if um and um.has_signal("system_loaded"):
			um.system_loaded.connect(_on_system_loaded)
			um.hyperjump_completed.connect(_on_hyperjump_completed)

## Called when UniverseManager loads a new star system
func _on_system_loaded(system_data: Dictionary) -> void:
	var synth = _get_synth()
	if synth == null:
		return
	# Extract spectral type from system data and set star soundscape
	var spectral_type: int = int(system_data.get("spectral_class", 4))  # Default: CLASS_G
	synth.set_star_type(spectral_type)
	# Clear any environment event from the previous system
	synth.clear_environment_event()
	synth.set_planet_proximity(-1, 0.0)  # Clear planet proximity

## Called when a hyperjump completes — triggers a discovery event transition
func _on_hyperjump_completed(_system_data: Dictionary) -> void:
	# Trigger a discovery event for the wonder of arriving in a new system
	transition_to_event("discovery")

func _process(delta: float) -> void:
	# Detect scene changes that happened outside our transition system
	# (e.g. launching directly into a scene from the editor/command line)
	if not _transition_active:
		_detect_current_scene()
	_update_transitions(delta)
	_update_event_ramps(delta)
	_update_bus_automation(delta)
	_update_stinger(delta)
	_render_stinger()

func _detect_current_scene() -> void:
	var tree := get_tree()
	if not tree:
		return
	var current_scene := tree.current_scene
	if not current_scene:
		return
	var scene_file: String = current_scene.scene_file_path
	if scene_file == "":
		return
	var detected_name: String = scene_name_from_path(scene_file)
	if detected_name != _current_scene_name and _profiles.has(detected_name):
		_current_scene_name = detected_name
		_current_profile = _profiles[detected_name]
		_apply_profile_immediate(_current_profile)

func _exit_tree() -> void:
	if _overlay:
		_overlay.queue_free()


# ==============================================================================
# Profile Initialization
# ==============================================================================
func _init_profiles() -> void:
	# --- Main Menu: Serene, expansive, oceanic — A Aeolian theme ---
	var menu := SceneAudioProfile.new("main_menu")
	menu.tension_index = 0.0
	menu.music_bpm = 72.0  # Slower than flight (112) for contemplative feel
	menu.music_theme = 1   # MENU theme (A Aeolian, Am-F-C-G progression)
	menu.reverb_send = 0.35
	menu.reverb_space = true
	menu.master_volume_db = 0.0
	menu.music_volume_db = -3.0
	menu.stethoscope = false
	menu.wave_engine_off = true
	menu.ambient_boost = 0.02
	menu.pad_boost = 0.10
	menu.sub_bass_boost = 0.05
	_profiles["main_menu"] = menu

	# --- Ship Builder: Creative, focused, warm — menu theme but slightly faster ---
	var builder := SceneAudioProfile.new("ship_builder")
	builder.tension_index = 0.05
	builder.music_bpm = 84.0
	builder.music_theme = 1   # MENU theme (shares the A Aeolian identity)
	builder.reverb_send = 0.15
	builder.reverb_space = false  # cockpit reverb (smaller)
	builder.master_volume_db = 0.0
	builder.music_volume_db = -4.0
	builder.stethoscope = false
	builder.wave_engine_off = true
	builder.ambient_boost = 0.01
	builder.pad_boost = 0.05
	builder.sub_bass_boost = 0.0
	_profiles["ship_builder"] = builder

	# --- Space Flight: Dynamic, cockpit ambience — D Dorian exploration theme ---
	var flight := SceneAudioProfile.new("space_flight")
	flight.tension_index = 0.0  # driven by FlightController
	flight.music_bpm = 112.0
	flight.music_theme = 0   # EXPLORATION theme (D Dorian)
	flight.reverb_send = 0.08
	flight.reverb_space = false  # cockpit reverb
	flight.master_volume_db = 0.0
	flight.music_volume_db = -3.0
	flight.stethoscope = false
	flight.wave_engine_off = false  # allow wave engine
	flight.ambient_boost = 0.0
	flight.pad_boost = 0.0
	flight.sub_bass_boost = 0.0
	_profiles["space_flight"] = flight

	# --- Organ Inspector: Stethoscope, intimate — exploration theme but calmer ---
	var inspector := SceneAudioProfile.new("organ_inspector")
	inspector.tension_index = 0.0
	inspector.music_bpm = 88.0
	inspector.music_theme = 0   # EXPLORATION (D Dorian, but quiet)
	inspector.reverb_send = 0.10
	inspector.reverb_space = false
	inspector.master_volume_db = 0.0
	inspector.music_volume_db = -6.0  # duck music for organ clarity
	inspector.stethoscope = true
	inspector.wave_engine_off = true
	inspector.ambient_boost = -0.02  # reduce ambience for organ focus
	inspector.pad_boost = -0.10  # reduce pads
	inspector.sub_bass_boost = -0.05
	_profiles["organ_inspector"] = inspector

	# --- Cinematic Intro: Dramatic, wide — cinematic theme ---
	var cinematic := SceneAudioProfile.new("cinematic_intro")
	cinematic.tension_index = 0.30
	cinematic.music_bpm = 120.0
	cinematic.music_theme = 2   # CINEMATIC theme
	cinematic.reverb_send = 0.45
	cinematic.reverb_space = true
	cinematic.master_volume_db = 0.0
	cinematic.music_volume_db = -2.0
	cinematic.stethoscope = false
	cinematic.wave_engine_off = true
	cinematic.ambient_boost = 0.03
	cinematic.pad_boost = 0.15
	cinematic.sub_bass_boost = 0.10
	_profiles["cinematic_intro"] = cinematic

	# --- Pause Menu: Frozen, ducked — keeps current scene's theme ---
	var pause := SceneAudioProfile.new("pause_menu")
	pause.tension_index = 0.0
	pause.music_bpm = 96.0
	pause.music_theme = 0   # Will be overridden to match current scene's theme
	pause.reverb_send = 0.20
	pause.reverb_space = true
	pause.master_volume_db = -6.0  # duck everything
	pause.music_volume_db = -8.0
	pause.stethoscope = false
	pause.wave_engine_off = true
	pause.ambient_boost = -0.01
	pause.pad_boost = -0.05
	pause.sub_bass_boost = -0.03
	_profiles["pause_menu"] = pause


# ==============================================================================
# Event Initialization
# ==============================================================================
func _init_events() -> void:
	# --- Combat Start: ramp tension, stinger ---
	var combat_start := EventTransition.new("combat_start")
	combat_start.target_tension = 0.65
	combat_start.ramp_duration = 3.0
	combat_start.stinger = true
	combat_start.bus_duck_db = -2.0
	_events["combat_start"] = combat_start

	# --- Combat End: relax tension ---
	var combat_end := EventTransition.new("combat_end")
	combat_end.target_tension = 0.15
	combat_end.ramp_duration = 4.0
	combat_end.stinger = false
	combat_end.bus_duck_db = 0.0
	_events["combat_end"] = combat_end

	# --- Climax: maximum tension ---
	var climax := EventTransition.new("climax")
	climax.target_tension = 0.90
	climax.ramp_duration = 2.0
	climax.stinger = true
	climax.bus_duck_db = -3.0
	_events["climax"] = climax

	# --- Discovery: wonder, gentle uplift ---
	var discovery := EventTransition.new("discovery")
	discovery.target_tension = 0.20
	discovery.ramp_duration = 5.0
	discovery.stinger = false
	discovery.bus_duck_db = 0.0
	_events["discovery"] = discovery

	# --- Wave Engine Engage: power-up surge ---
	var wave_engage := EventTransition.new("wave_engage")
	wave_engage.target_tension = 0.40
	wave_engage.ramp_duration = 2.5
	wave_engage.stinger = true
	wave_engage.bus_duck_db = -1.0
	_events["wave_engage"] = wave_engage

	# --- Wave Engine Disengage: settle back ---
	var wave_disengage := EventTransition.new("wave_disengage")
	wave_disengage.target_tension = 0.10
	wave_disengage.ramp_duration = 3.0
	wave_disengage.stinger = false
	wave_disengage.bus_duck_db = 0.0
	_events["wave_disengage"] = wave_disengage

	# --- Damage Critical: spike then settle ---
	var damage_critical := EventTransition.new("damage_critical")
	damage_critical.target_tension = 0.75
	damage_critical.ramp_duration = 0.5
	damage_critical.stinger = true
	damage_critical.bus_duck_db = -2.0
	_events["damage_critical"] = damage_critical

	# --- Calm Exploration: serene ---
	var calm := EventTransition.new("calm")
	calm.target_tension = 0.05
	calm.ramp_duration = 6.0
	calm.stinger = false
	calm.bus_duck_db = 0.0
	_events["calm"] = calm

	# --- Anomaly: strange, unsettling (EnvironmentEvent.ANOMALY) ---
	var anomaly := EventTransition.new("anomaly")
	anomaly.target_tension = 0.30
	anomaly.ramp_duration = 4.0
	anomaly.stinger = false
	anomaly.bus_duck_db = 0.0
	_events["anomaly"] = anomaly

	# --- Docking: mechanical, focused (EnvironmentEvent.DOCKING) ---
	var docking := EventTransition.new("docking")
	docking.target_tension = 0.15
	docking.ramp_duration = 3.0
	docking.stinger = false
	docking.bus_duck_db = -1.0
	_events["docking"] = docking

	# --- Derelict: eerie, cold (EnvironmentEvent.DERELICT) ---
	var derelict := EventTransition.new("derelict")
	derelict.target_tension = 0.08
	derelict.ramp_duration = 5.0
	derelict.stinger = false
	derelict.bus_duck_db = 0.0
	_events["derelict"] = derelict

	# --- Distress Signal: urgent, alarming (EnvironmentEvent.DISTRESS_SIGNAL) ---
	var distress_signal := EventTransition.new("distress_signal")
	distress_signal.target_tension = 0.55
	distress_signal.ramp_duration = 0.5
	distress_signal.stinger = true
	distress_signal.bus_duck_db = -2.0
	_events["distress_signal"] = distress_signal

	# --- Combat Ambush: sudden, intense (EnvironmentEvent.COMBAT_AMBUSH) ---
	var combat_ambush := EventTransition.new("combat_ambush")
	combat_ambush.target_tension = 0.75
	combat_ambush.ramp_duration = 0.3
	combat_ambush.stinger = true
	combat_ambush.bus_duck_db = -3.0
	_events["combat_ambush"] = combat_ambush

	# --- Solar Flare: dramatic, bright (EnvironmentEvent.SOLAR_FLARE) ---
	var solar_flare := EventTransition.new("solar_flare")
	solar_flare.target_tension = 0.45
	solar_flare.ramp_duration = 1.0
	solar_flare.stinger = true
	solar_flare.bus_duck_db = -1.5
	_events["solar_flare"] = solar_flare

	# --- Gravitational Wave: cosmic, awe (EnvironmentEvent.GRAVITATIONAL_WAVE) ---
	var gravitational_wave := EventTransition.new("gravitational_wave")
	gravitational_wave.target_tension = 0.20
	gravitational_wave.ramp_duration = 6.0
	gravitational_wave.stinger = false
	gravitational_wave.bus_duck_db = 0.0
	_events["gravitational_wave"] = gravitational_wave


# ==============================================================================
# Visual Transition Overlay
# ==============================================================================
func _create_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.color.a = 0.0
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 1000
	# Add to canvas layer so it renders above everything
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.name = "AudioDirectorOverlay"
	add_child(canvas)
	canvas.add_child(_overlay)

func _fade_overlay_to(alpha: float, duration: float) -> void:
	if _overlay_tween:
		_overlay_tween.kill()
	_overlay_tween = create_tween()
	_overlay_tween.tween_property(_overlay, "color:a", alpha, duration)
	_overlay_tween.set_ease(Tween.EASE_IN_OUT)
	_overlay_tween.set_trans(Tween.TRANS_SINE)


# ==============================================================================
# Public API: Scene Transitions
# ==============================================================================

## Returns the scene name from a scene path (e.g. "res://scenes/main_menu.tscn" -> "main_menu")
func scene_name_from_path(path: String) -> String:
	var fname: String = path.get_file().get_basename()
	return fname

## Prepares audio profile for a scene without triggering the scene change.
## Used by LoadingScreenManager when it handles the scene transition itself.
func prepare_audio_for_scene(scene_path: String) -> void:
	var scene_name: String = scene_name_from_path(scene_path)
	if not _profiles.has(scene_name):
		_pending_profile = SceneAudioProfile.new(scene_name)
	else:
		_pending_profile = _profiles[scene_name]
	_current_scene_name = scene_name
	_current_profile = _pending_profile
	_apply_profile_immediate(_current_profile)
	_master_vol_target = _pending_profile.master_volume_db

## Transitions to a new scene with synchronized audio + visual crossfade
func transition_to_scene(scene_path: String, fade_duration: float = 0.8) -> void:
	var scene_name: String = scene_name_from_path(scene_path)
	if not _profiles.has(scene_name):
		push_warning("[BioAudioDirector] No audio profile for scene '%s', using default" % scene_name)
		_pending_profile = SceneAudioProfile.new(scene_name)
	else:
		_pending_profile = _profiles[scene_name]

	_pending_scene_path = scene_path
	_transition_duration = fade_duration
	_transition_active = true
	_transition_time = 0.0
	_from_profile = _current_profile

	# Fade visual overlay to black
	_fade_overlay_to(1.0, fade_duration * 0.5)

	# Start audio fade-out (will crossfade to new profile)
	_master_vol_target = -80.0  # fade to silence during transition

## Instantly applies a profile (used on first load or emergency reset)
func _apply_profile_immediate(profile: SceneAudioProfile) -> void:
	var synth = _get_synth()
	if synth == null:
		return
	synth.tension_index = profile.tension_index
	synth.music_bpm = profile.music_bpm
	synth.set_music_theme(profile.music_theme)
	synth.stethoscope_mode = profile.stethoscope
	if profile.wave_engine_off:
		synth.set_wave_engine_state(0)
		synth.set_hyperwave_tunnel(false)
	# Bus volumes
	_master_vol_target = profile.master_volume_db
	_master_vol_current = profile.master_volume_db
	_music_vol_target = profile.music_volume_db
	_music_vol_current = profile.music_volume_db
	_reverb_send_target = profile.reverb_send
	_reverb_send_current = profile.reverb_send
	_apply_bus_volumes()

## Applies bus volumes to AudioServer
func _apply_bus_volumes() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	var music_idx := AudioServer.get_bus_index("Music")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, _master_vol_current + (_event_bus_duck_amount if _event_bus_duck_active else 0.0))
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, _music_vol_current)


# ==============================================================================
# Public API: Event Transitions
# ==============================================================================

## Triggers a smooth transition to an event state (combat, discovery, etc.)
func transition_to_event(event_name: String) -> void:
	if not _events.has(event_name):
		push_warning("[BioAudioDirector] Unknown event '%s'" % event_name)
		return
	var evt: EventTransition = _events[event_name]
	_current_event = evt

	# Start tension ramp
	_event_tension_ramp_active = true
	_event_tension_from = _get_synth().tension_index if _get_synth() else 0.0
	_event_tension_to = evt.target_tension
	_event_tension_time = 0.0
	_event_tension_duration = evt.ramp_duration

	# Bus duck if specified
	if evt.bus_duck_db != 0.0:
		_event_bus_duck_active = true
		_event_bus_duck_time = 0.0
		_event_bus_duck_amount = evt.bus_duck_db

	# Stinger hit
	if evt.stinger:
		_trigger_stinger()

## Resets to the current scene's base tension (cancels event ramp)
func reset_to_scene_base() -> void:
	_event_tension_ramp_active = false
	_current_event = null
	_event_bus_duck_active = false
	var synth = _get_synth()
	if synth and _current_profile:
		synth.set_tension_index(_current_profile.tension_index)


# ==============================================================================
# Public API: System Soundscape (star type, planet proximity, environment events)
# ==============================================================================

## Sets the current star type for soundscape modulation.
## Values mirror ProceduralGalaxy.SpectralClass (0-9).
func set_star_type(star_type: int) -> void:
	var synth = _get_synth()
	if synth:
		synth.set_star_type(star_type)

## Sets planet proximity for ambient soundscape.
## planet_type mirrors ProceduralGalaxy.PlanetArchetype (0-7). Use -1 for "no planet".
## proximity is 0.0 (far) to 1.0 (very close).
func set_planet_proximity(planet_type: int, proximity: float) -> void:
	var synth = _get_synth()
	if synth:
		synth.set_planet_proximity(planet_type, proximity)

## Sets an environment event (nebula, asteroid field, anomaly, etc.)
## event values mirror BioAudioSynth.EnvironmentEvent enum.
func set_environment_event(event: int, intensity: float = 1.0) -> void:
	var synth = _get_synth()
	if synth:
		synth.set_environment_event(event, intensity)

## Clears the current environment event
func clear_environment_event() -> void:
	var synth = _get_synth()
	if synth:
		synth.clear_environment_event()

## Triggers an environment event transition by name and sets the synth
## environment event in a single call. synth_event should be a
## BioAudioSynth.EnvironmentEvent enum value.
func trigger_environment_event(event_name: String, synth_event: int, intensity: float = 1.0) -> void:
	transition_to_event(event_name)
	set_environment_event(synth_event, intensity)


# ==============================================================================
# Public API: Pause Control
# ==============================================================================

## Sets pause audio state (ducks all audio, freezes tension)
func set_pause_audio(paused: bool) -> void:
	_is_paused = paused
	if _current_profile == null:
		return
	if paused:
		_master_vol_target = _current_profile.master_volume_db + _pause_duck_db
		_music_vol_target = _current_profile.music_volume_db + _pause_duck_db
	else:
		_master_vol_target = _current_profile.master_volume_db
		_music_vol_target = _current_profile.music_volume_db


# ==============================================================================
# Transition Update Logic
# ==============================================================================
func _update_transitions(delta: float) -> void:
	if not _transition_active:
		return

	_transition_time += delta
	var t: float = clampf(_transition_time / _transition_duration, 0.0, 1.0)

	# Phase 1 (0-50%): Fade out current scene audio + visual to black
	# Phase 2 (50-100%): Change scene, fade in new scene audio + visual from black
	if t >= 0.5 and _pending_scene_path != "":
		# Mid-point: change the scene
		var tree := get_tree()
		if tree:
			tree.change_scene_to_file(_pending_scene_path)
		_pending_scene_path = ""
		_current_scene_name = _pending_profile.name
		_current_profile = _pending_profile
		_apply_profile_immediate(_current_profile)
		# Fade visual overlay back to transparent
		_fade_overlay_to(0.0, _transition_duration * 0.5)
		# Restore master volume target
		_master_vol_target = _pending_profile.master_volume_db

	if t >= 1.0:
		_transition_active = false
		_transition_time = 0.0

func _on_tree_changed() -> void:
	# Fallback detector for scene changes that happen outside our transition
	# system (e.g. editor launches, autoload swaps, debug reloads). The primary
	# detector runs every frame in _process(); this signal-based check is a
	# low-cost complement that reacts immediately to tree mutations.
	if _transition_active:
		return
	# tree_changed fires during teardown when this node may already be detached
	# from the tree; bail out before get_tree() pushes a null error.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var current_scene: Node = tree.current_scene
	if current_scene == null:
		return
	# Compare against the scene file basename (same convention as _detect_current_scene)
	# rather than the node name, which may differ from the file basename.
	var scene_file: String = current_scene.scene_file_path
	if scene_file == "":
		return
	var scene_name: String = scene_name_from_path(scene_file)
	if scene_name != _current_scene_name:
		_detect_current_scene()


# ==============================================================================
# Event Ramp Updates
# ==============================================================================
func _update_event_ramps(delta: float) -> void:
	# Tension ramp
	if _event_tension_ramp_active:
		_event_tension_time += delta
		var t: float = clampf(_event_tension_time / _event_tension_duration, 0.0, 1.0)
		# Ease-in-out curve for smooth musical transitions
		var eased: float = t * t * (3.0 - 2.0 * t)
		var current_tension: float = lerpf(_event_tension_from, _event_tension_to, eased)
		var synth = _get_synth()
		if synth:
			synth.set_tension_index(current_tension)
		if t >= 1.0:
			_event_tension_ramp_active = false

	# Bus duck ramp
	if _event_bus_duck_active:
		_event_bus_duck_time += delta
		var duck_t: float = clampf(_event_bus_duck_time / _event_bus_duck_duration, 0.0, 1.0)
		# Fade in the duck, then fade out after 2x duration
		if duck_t < 1.0:
			_event_bus_duck_amount = _current_event.bus_duck_db * duck_t
		else:
			var release_t: float = clampf((_event_bus_duck_time - _event_bus_duck_duration) / _event_bus_duck_duration, 0.0, 1.0)
			_event_bus_duck_amount = _current_event.bus_duck_db * (1.0 - release_t)
			if release_t >= 1.0:
				_event_bus_duck_active = false
				_event_bus_duck_amount = 0.0


# ==============================================================================
# Bus Automation
# ==============================================================================
func _update_bus_automation(delta: float) -> void:
	# Smooth volume ramps toward targets (exponential approach for natural feel)
	var rate: float = delta * 6.0  # 6x per second = ~0.15s time constant
	_master_vol_current = lerpf(_master_vol_current, _master_vol_target, rate)
	_music_vol_current = lerpf(_music_vol_current, _music_vol_target, rate)
	_reverb_send_current = lerpf(_reverb_send_current, _reverb_send_target, rate)
	_apply_bus_volumes()

	# Update reverb bus volumes based on current profile
	var reverb_space_idx := AudioServer.get_bus_index("Reverb_Space")
	var reverb_cockpit_idx := AudioServer.get_bus_index("Reverb_Cockpit")
	var reverb_amount_db: float = linear_to_db(_reverb_send_current) if _reverb_send_current > 0.001 else -80.0
	if _current_profile.reverb_space:
		if reverb_space_idx >= 0:
			AudioServer.set_bus_volume_db(reverb_space_idx, reverb_amount_db)
		if reverb_cockpit_idx >= 0:
			AudioServer.set_bus_volume_db(reverb_cockpit_idx, -80.0)
	else:
		if reverb_cockpit_idx >= 0:
			AudioServer.set_bus_volume_db(reverb_cockpit_idx, reverb_amount_db)
		if reverb_space_idx >= 0:
			AudioServer.set_bus_volume_db(reverb_space_idx, -80.0)


# ==============================================================================
# Stinger Hit (dramatic transition accent)
# ==============================================================================
func _trigger_stinger() -> void:
	_stinger_active = true
	_stinger_time = 0.0
	_stinger_phase = 0.0
	# Rising Shepard-tone stinger: 220 Hz → 880 Hz over 0.5s
	_stinger_freq = 220.0

func _update_stinger(delta: float) -> void:
	if not _stinger_active:
		return
	_stinger_time += delta
	if _stinger_time > 0.6:
		_stinger_active = false

func _render_stinger() -> void:
	# Stinger is rendered as a brief rising tone through the synth
	# We use the synth's existing laser FM mechanism for the stinger
	if not _stinger_active:
		return
	var synth = _get_synth()
	if synth and _stinger_time < 0.05:
		# Trigger a laser fire as the stinger (it has FM synthesis built in)
		synth.play_laser_fire(0.0)


# ==============================================================================
# Helpers
# ==============================================================================
func _get_synth() -> Node:
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("BioAudioSynth"):
		return tree.root.get_node("BioAudioSynth")
	return null

## Returns the current scene name
func get_current_scene_name() -> String:
	return _current_scene_name

## Returns the current scene audio profile
func get_current_profile() -> SceneAudioProfile:
	return _current_profile

## Forces immediate profile update (for debugging)
func force_profile_update() -> void:
	if _current_profile:
		_apply_profile_immediate(_current_profile)
