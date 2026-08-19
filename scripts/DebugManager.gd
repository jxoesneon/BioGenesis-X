# res://scripts/DebugManager.gd
# ==============================================================================
# BioGenesis-X — Debug API Integration Manager (Autoload)
# ==============================================================================
# Bootstraps the Debug API addon on startup and registers live telemetry
# monitors for every core BioGenesis-X subsystem:
#
#   • Performance        — FPS, frame time, draw calls (built-in monitors)
#   • BioAudioSynth      — tension index, active voices, CPU load estimate
#   • FlightController   — velocity, shield, hull, wave engine state
#   • OrganTelemetry     — heart rate, oxygenation, adrenaline
#   • SaveSystem         — save slot (profile), schema version
#   • PlanetTerrainGen   — active chunks, pool size, split budget
#   • CombatStats        — kills, damage dealt, damage received
#
# The debug panel is hidden by default; press F12 to toggle it.
# The entire manager is a no-op in release (non-debug) builds.
# ==============================================================================

extends Node

# The Debug API script has no class_name (it shares its name with the autoload),
# so we preload it to resolve or create the shared instance robustly.
const _DebugAPIScript: GDScript = preload("res://addons/debug_api/DebugAPI.gd")

# F12 toggles the debug panel visibility.
const TOGGLE_KEY: int = KEY_F12

# WaveState enum mirror (FlightController.WaveState) for human-readable display.
const _WAVE_STATE_NAMES: Array[String] = [
	"OFF", "CHARGING", "ENGAGED", "DISENGAGING", "INHIBITED",
]

# BioAudioSynth boolean voice flags counted for the "active voices" monitor.
const _BIOAUDIO_VOICE_PROPS: Array[String] = [
	"_music_perc_active",
	"_reverb_tail_active",
	"_lub_active",
	"_dub_active",
	"_wave_sub_boom_active",
	"_hyper_tunnel_active",
	"_chitin_active",
	"_laser_active",
	"_spore_active",
	"_shield_impact_active",
	"_creature_vocal_active",
	"_ui_chirp_active",
	"_pulsar_pulse_active",
	"_derelict_creak_active",
]

# Cached subsystem references (re-resolved when invalidated).
# Accessed dynamically via get()/set() in _resolve_cached(), so the static
# analyzer reports them as unused — suppress with @warning_ignore.
@warning_ignore("unused_private_class_variable")
var _api: Node = null
@warning_ignore("unused_private_class_variable")
var _bioaudio: Node = null
@warning_ignore("unused_private_class_variable")
var _organ: Node = null
@warning_ignore("unused_private_class_variable")
var _save: Node = null
@warning_ignore("unused_private_class_variable")
var _combat: Node = null
@warning_ignore("unused_private_class_variable")
var _flight: Node = null
@warning_ignore("unused_private_class_variable")
var _terrain: Node = null


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	# Hard guard: never activate in release/exported builds.
	if not OS.is_debug_build():
		set_process(false)
		set_process_input(false)
		return

	# Defer initialization until the scene-tree root has finished setting up its
	# autoload children — add_child() on root during _ready otherwise fails with
	# "Parent node is busy setting up children".
	call_deferred("_initialize_debug_api")


func _initialize_debug_api() -> void:
	# Resolve the shared DebugAPI instance (autoload or bootstrap-created), or
	# create one and attach it to the scene-tree root so its _process runs.
	_api = _DebugAPIScript.instance()
	if _api == null:
		_api = _DebugAPIScript.new()
		_api.name = "DebugAPI"
		var st: SceneTree = get_tree()
		if st == null or st.root == null:
			push_error("DebugManager: no SceneTree root available to host DebugAPI.")
			_api = null
			return
		st.root.add_child(_api)

	# Configure the auto-panel appearance. Hidden by default; F12 reveals it.
	_api.configure_auto_panel({
		"toggle_key": TOGGLE_KEY,
		"start_visible": false,
		"anchor": DebugPanel.ANCHOR_TOP_RIGHT,
		"edge_margin": Vector2(8, 8),
		"min_width": 300,
		"max_height": 640,
		"layer": 100,
		"click_through": true,
		"show_title": true,
		"title_text": "BioGenesis-X Debug",
		"collapsible_sections": true,
		"update_interval": 0.1,   # 10 Hz widget refresh
	})

	# Register all BioGenesis-X custom monitors before enabling them.
	_register_custom_monitors()

	# Enable built-in performance/rendering monitors.
	_api.enable_monitor("fps")
	_api.enable_monitor("frame_time")
	_api.enable_monitor("total_draw_calls")

	# Enable custom subsystem monitors (order defines section grouping).
	_api.enable_monitors([
		"bioaudio_tension", "bioaudio_voices", "bioaudio_cpu",
		"flight_velocity", "flight_shield", "flight_hull", "flight_wave_state",
		"organ_heart_rate", "organ_oxygen", "organ_adrenaline",
		"save_slot", "save_schema",
		"terrain_chunks", "terrain_pool", "terrain_split_budget",
		"combat_kills", "combat_dmg_dealt", "combat_dmg_received",
	])

	print("DebugManager: Debug API initialized — %d monitors enabled (F12 to toggle panel)." \
		% _api.list_enabled_monitors().size())


## Set the debug panel visibility from SettingsSystem.
func set_panel_visible(visible: bool) -> void:
	if _api and _api.has_method("set_panel_visible"):
		_api.set_panel_visible(visible)

## Set the debug panel update rate (seconds between refreshes) from SettingsSystem.
func set_panel_update_rate(rate: float) -> void:
	if _api and _api.has_method("configure_auto_panel"):
		_api.configure_auto_panel({"update_interval": clampf(rate, 0.05, 1.0)})


# ==============================================================================
# Custom monitor registration
# ==============================================================================

func _register_custom_monitors() -> void:
	# --- BioAudioSynth -------------------------------------------------------
	_api.register_custom_monitor({
		"id": "bioaudio_tension", "label": "Tension Index", "category": "bioaudio",
		"widget_type": "progress", "format": "%.2f",
		"getter": Callable(self, "_get_bioaudio_tension"),
		"min": 0.0, "max": 1.0,
	})
	_api.register_custom_monitor({
		"id": "bioaudio_voices", "label": "Active Voices", "category": "bioaudio",
		"widget_type": "text", "format": "%d",
		"getter": Callable(self, "_get_bioaudio_voices"),
	})
	_api.register_custom_monitor({
		"id": "bioaudio_cpu", "label": "CPU Load (est)", "category": "bioaudio",
		"widget_type": "progress", "format": "%.1f%%",
		"getter": Callable(self, "_get_bioaudio_cpu"),
		"min": 0.0, "max": 100.0,
	})

	# --- FlightController ----------------------------------------------------
	_api.register_custom_monitor({
		"id": "flight_velocity", "label": "Velocity", "category": "flight",
		"widget_type": "text", "format": "%.1f m/s",
		"getter": Callable(self, "_get_flight_velocity"),
	})
	_api.register_custom_monitor({
		"id": "flight_shield", "label": "Bio-Shield", "category": "flight",
		"widget_type": "progress", "format": "%.1f%%",
		"getter": Callable(self, "_get_flight_shield"),
		"min": 0.0, "max": 100.0,
	})
	_api.register_custom_monitor({
		"id": "flight_hull", "label": "Hull Integrity", "category": "flight",
		"widget_type": "progress", "format": "%.1f%%",
		"getter": Callable(self, "_get_flight_hull"),
		"min": 0.0, "max": 100.0,
	})
	_api.register_custom_monitor({
		"id": "flight_wave_state", "label": "Wave Engine", "category": "flight",
		"widget_type": "text", "format": "%s",
		"getter": Callable(self, "_get_flight_wave_state"),
	})

	# --- OrganTelemetry ------------------------------------------------------
	_api.register_custom_monitor({
		"id": "organ_heart_rate", "label": "Heart Rate", "category": "organ",
		"widget_type": "text", "format": "%.1f BPM",
		"getter": Callable(self, "_get_organ_heart_rate"),
	})
	_api.register_custom_monitor({
		"id": "organ_oxygen", "label": "Oxygenation", "category": "organ",
		"widget_type": "text", "format": "%.0f L/min",
		"getter": Callable(self, "_get_organ_oxygen"),
	})
	_api.register_custom_monitor({
		"id": "organ_adrenaline", "label": "Adrenaline", "category": "organ",
		"widget_type": "progress", "format": "%.1f%%",
		"getter": Callable(self, "_get_organ_adrenaline"),
		"min": 0.0, "max": 100.0,
	})

	# --- SaveSystem ----------------------------------------------------------
	_api.register_custom_monitor({
		"id": "save_slot", "label": "Save Slot", "category": "save",
		"widget_type": "text", "format": "%s",
		"getter": Callable(self, "_get_save_slot"),
	})
	_api.register_custom_monitor({
		"id": "save_schema", "label": "Schema Version", "category": "save",
		"widget_type": "text", "format": "v%d",
		"getter": Callable(self, "_get_save_schema"),
	})

	# --- PlanetTerrainGenerator ----------------------------------------------
	_api.register_custom_monitor({
		"id": "terrain_chunks", "label": "Active Chunks", "category": "terrain",
		"widget_type": "text", "format": "%d",
		"getter": Callable(self, "_get_terrain_chunks"),
	})
	_api.register_custom_monitor({
		"id": "terrain_pool", "label": "Pool Size", "category": "terrain",
		"widget_type": "text", "format": "%d",
		"getter": Callable(self, "_get_terrain_pool"),
	})
	_api.register_custom_monitor({
		"id": "terrain_split_budget", "label": "Split Budget", "category": "terrain",
		"widget_type": "text", "format": "%d",
		"getter": Callable(self, "_get_terrain_split_budget"),
	})

	# --- CombatStats ---------------------------------------------------------
	_api.register_custom_monitor({
		"id": "combat_kills", "label": "Kills", "category": "combat",
		"widget_type": "text", "format": "%d",
		"getter": Callable(self, "_get_combat_kills"),
	})
	_api.register_custom_monitor({
		"id": "combat_dmg_dealt", "label": "Damage Dealt", "category": "combat",
		"widget_type": "text", "format": "%.0f",
		"getter": Callable(self, "_get_combat_dmg_dealt"),
	})
	_api.register_custom_monitor({
		"id": "combat_dmg_received", "label": "Damage Received", "category": "combat",
		"widget_type": "text", "format": "%.0f",
		"getter": Callable(self, "_get_combat_dmg_received"),
	})


# ==============================================================================
# Subsystem resolvers (cached, re-resolved on invalidation)
# ==============================================================================

func _resolve_cached(field: String, autoload_name: String) -> Node:
	var cached: Node = get(field)
	if is_instance_valid(cached):
		return cached
	var st: SceneTree = get_tree()
	if st == null or st.root == null:
		return null
	var node: Node = st.root.get_node_or_null(autoload_name)
	if node != null and is_instance_valid(node):
		set(field, node)
		return node
	set(field, null)
	return null


func _bio_audio() -> Node:
	return _resolve_cached("_bioaudio", "BioAudioSynth")


func _organ_telemetry() -> Node:
	return _resolve_cached("_organ", "OrganTelemetry")


func _save_system() -> Node:
	return _resolve_cached("_save", "SaveSystem")


func _combat_stats() -> Node:
	return _resolve_cached("_combat", "CombatStats")


func _flight_controller() -> Node:
	if is_instance_valid(_flight):
		return _flight
	var st: SceneTree = get_tree()
	if st == null:
		return null
	var arr: Array = st.get_nodes_in_group("flight_controller")
	if arr.size() > 0 and is_instance_valid(arr[0]):
		_flight = arr[0]
		return _flight
	_flight = null
	return null


func _terrain_generator() -> Node:
	if is_instance_valid(_terrain):
		return _terrain
	var st: SceneTree = get_tree()
	if st == null or st.root == null:
		return null
	# PlanetTerrainGenerator is a scene node (not an autoload); locate it by class.
	var found: Array = st.root.find_children("*", "PlanetTerrainGenerator", true, false)
	if found.size() > 0 and is_instance_valid(found[0]):
		_terrain = found[0]
		return _terrain
	_terrain = null
	return null


# ==============================================================================
# Monitor getters — BioAudioSynth
# ==============================================================================

func _get_bioaudio_tension() -> float:
	var s: Node = _bio_audio()
	if s == null:
		return 0.0
	return float(s.get("tension_index"))


func _get_bioaudio_voices() -> int:
	var s: Node = _bio_audio()
	if s == null:
		return 0
	var count: int = 0
	for prop in _BIOAUDIO_VOICE_PROPS:
		if bool(s.get(prop)):
			count += 1
	# Pad layers contribute 2 continuous voices when the synth is running.
	var player: Node = s.get("audio_player")
	if player != null and is_instance_valid(player) and player is AudioStreamPlayer and player.playing:
		count += 2
	return count


func _get_bioaudio_cpu() -> float:
	# Derived heuristic: base DSP overhead + per-voice load contribution.
	# Godot does not expose per-node audio CPU time; this estimates load from
	# the number of concurrently active synthesis voices.
	var voices: int = _get_bioaudio_voices()
	return clampf(4.0 + float(voices) * 6.5, 0.0, 100.0)


# ==============================================================================
# Monitor getters — FlightController
# ==============================================================================

func _get_flight_velocity() -> float:
	var s: Node = _flight_controller()
	if s == null:
		return 0.0
	var vel: Variant = s.get("linear_velocity_vector")
	if vel is Vector3:
		return (vel as Vector3).length()
	return 0.0


func _get_flight_shield() -> float:
	var s: Node = _flight_controller()
	if s == null:
		return 0.0
	return float(s.get("bio_shield"))


func _get_flight_hull() -> float:
	var s: Node = _flight_controller()
	if s == null:
		return 0.0
	return float(s.get("hull_integrity"))


func _get_flight_wave_state() -> String:
	var s: Node = _flight_controller()
	if s == null:
		return "—"
	var state: int = int(s.get("wave_state"))
	if state >= 0 and state < _WAVE_STATE_NAMES.size():
		return _WAVE_STATE_NAMES[state]
	return "UNKNOWN"


# ==============================================================================
# Monitor getters — OrganTelemetry
# ==============================================================================

func _get_organ_heart_rate() -> float:
	var s: Node = _organ_telemetry()
	if s == null:
		return 0.0
	return float(s.get("heart_rate_bpm"))


func _get_organ_oxygen() -> float:
	var s: Node = _organ_telemetry()
	if s == null:
		return 0.0
	return float(s.get("oxygenation_yield_lpm"))


func _get_organ_adrenaline() -> float:
	# Derived metric: adrenaline surge from elevated heart rate + damage stress.
	# OrganTelemetry has no explicit adrenaline field; this combines BPM elevation
	# above resting (68 BPM) with the damage_stress load indicator.
	var s: Node = _organ_telemetry()
	if s == null:
		return 0.0
	var bpm: float = float(s.get("heart_rate_bpm"))
	var stress: float = float(s.get("damage_stress"))
	var bpm_component: float = clampf((bpm - 68.0) / 112.0, 0.0, 1.0) * 70.0
	var stress_component: float = clampf(stress, 0.0, 1.0) * 30.0
	return clampf(bpm_component + stress_component, 0.0, 100.0)


# ==============================================================================
# Monitor getters — SaveSystem
# ==============================================================================

func _get_save_slot() -> String:
	var s: Node = _save_system()
	if s == null:
		return "—"
	var data: Variant = s.get("current_save_data")
	if data is Dictionary:
		return String((data as Dictionary).get("profile_name", "—"))
	return "—"


func _get_save_schema() -> int:
	var s: Node = _save_system()
	if s == null:
		return 0
	var data: Variant = s.get("current_save_data")
	if data is Dictionary:
		return int((data as Dictionary).get("schema_version", 0))
	return 0


# ==============================================================================
# Monitor getters — PlanetTerrainGenerator
# ==============================================================================

func _get_terrain_chunks() -> int:
	var s: Node = _terrain_generator()
	if s == null:
		return 0
	if s.has_method("get_active_chunk_count"):
		return int(s.get_active_chunk_count())
	var chunks: Variant = s.get("_chunks")
	if chunks is Dictionary:
		return (chunks as Dictionary).size()
	return 0


func _get_terrain_pool() -> int:
	var s: Node = _terrain_generator()
	if s == null:
		return 0
	var pool: Variant = s.get("_free_chunk_nodes")
	if pool is Array:
		return (pool as Array).size()
	return 0


func _get_terrain_split_budget() -> int:
	var s: Node = _terrain_generator()
	if s == null:
		return 0
	return int(s.get("split_budget"))


# ==============================================================================
# Monitor getters — CombatStats
# ==============================================================================

func _get_combat_kills() -> int:
	var s: Node = _combat_stats()
	if s == null:
		return 0
	return int(s.get("kills"))


func _get_combat_dmg_dealt() -> float:
	var s: Node = _combat_stats()
	if s == null:
		return 0.0
	return float(s.get("damage_dealt"))


func _get_combat_dmg_received() -> float:
	var s: Node = _combat_stats()
	if s == null:
		return 0.0
	return float(s.get("damage_received"))
