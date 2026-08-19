# res://scripts/FlightHUDUI.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# FlightHUDUI.gd - Comprehensive 3D Space Flight HUD & Tactical Biometric Overlay
# ==============================================================================
# Extends Control to render a biopunk space flight HUD.
# - Top Bar: Speedometer, G-Force meter, Distance/Altitude, Bio-Plasma Fuel, Neural Sync.
# - Bottom Left: ECG Oscilloscope (ECGGraph), Heart Rate, Hemolymph Pressure, Oxygen Yield.
# - Bottom Right: Hull Integrity, Bio-Shield, Bio-Nanite Coagulation, Radiotrophic Absorption.
# - Center: Dynamic Reticle, Target Locking Bracket, Lead Indicator, Exothermal Heat Gauge.
# - Controls Banner: Keyboard & Mouse Flight Keybindings Hint Overlay.
# ==============================================================================

@tool
class_name FlightHUDUI
extends Control

## Signal emitted when user triggers keybinding for Organ Inspector (Tab)
signal inspect_organs_requested()

@export_group("Targeting & Kinematics State")
@export var current_speed_ms: float = 85.0
@export var max_speed_ms: float = 300.0
@export var current_g_force: float = 1.0
@export var altitude_m: float = 1420.0
@export var bio_plasma_fuel_pct: float = 88.0
@export var neural_sync_pct: float = 98.4

@export_group("Biometric & Defense Metrics")
@export var heart_rate_bpm: float = 72.0
@export var hemolymph_pressure_bar: float = 15.5
@export var oxygenation_yield_lpm: float = 420.0
@export var hull_integrity_pct: float = 100.0
@export var bio_shield_pct: float = 100.0
@export var nanite_coagulation_m3s: float = 1.2
@export var radiotrophic_abs_gy_hr: float = 45.0
@export var exothermal_heat_pct: float = 24.0

@export_group("No Man's Sky Flight Reticle & Tether")
@export var mouse_flight_cursor: Vector2 = Vector2.ZERO
@export var tether_max_radius: float = 140.0
@export var tether_deadzone_radius: float = 16.0

@export_group("Target Lock Reticle Animation")
@export var target_locked: bool = false
@export var target_distance_m: float = 450.0
@export var target_screen_position: Vector2 = Vector2.ZERO
@export var lead_indicator_position: Vector2 = Vector2.ZERO
var target_name: String = ""
var target_details: String = ""

# Smoothed screen positions for target indicators — eliminates jitter from
# 3D-to-2D projection at varying frame rates and camera micro-movements.
var _smoothed_target_pos: Vector2 = Vector2.ZERO
var _smoothed_lead_pos: Vector2 = Vector2.ZERO
var _smoothed_planet_marker_pos: Vector2 = Vector2.ZERO

# WeaponSystem signal state (wired from WeaponSystem signals in _locate_weapon_system)
var _weapon_overheated: bool = false
var _weapon_lock_state: String = "NONE"
var _weapon_lock_target: Node3D = null
var _in_combat: bool = false

# Hit marker state — set by projectile impact callbacks, consumed in _draw
var _hit_marker_timer: float = 0.0
var _hit_marker_is_shield: bool = false
var _hit_marker_is_kill: bool = false

# Damage flash overlay intensity (0-1), drives red screen vignette
var _damage_flash_visual: float = 0.0

# --- Advanced Targeting State ---
# Cached list of valid trackable targets in the "targets" group (refreshed each
# frame by _update_target_tracking_3d). Used by Tab cycling.
var _target_list_cache: Array = []
# Index into _target_list_cache for the manually-selected target (-1 = none).
var _current_target_index: int = -1
# The Node3D currently being tracked (set by auto-select or manual Tab cycling).
var _current_target_node: Node3D = null
# When set via Tab cycling, tracking follows this node instead of auto-selecting
# the nearest target. Cleared when the node becomes invalid.
var _manual_target_override: Node3D = null

# Threat assessment state — computed each frame in _process, consumed in _draw.
var _hostile_count: int = 0
var _threat_level: String = "LOW"
var _threat_color: Color = Color(0.2, 1.0, 0.4, 0.9)
var _incoming_fire_warning: bool = false

# Directional hit indicator — world-space position of the last damage source.
# Can be set by FlightController (via set_damage_source() or a
# "last_damage_source_pos" property) to render a directional damage arrow.
var _last_damage_source_pos: Vector3 = Vector3.ZERO
var _has_damage_source: bool = false

# Child Node References
var top_bar_panel: PanelContainer
var bottom_left_panel: PanelContainer
var bottom_right_panel: PanelContainer
var controls_banner: PanelContainer
var ecg_widget: ECGGraph

# UI Label References
var lbl_speed: Label
var lbl_gforce: Label
var lbl_altitude: Label
var bar_fuel: ProgressBar
var lbl_sync: Label

var lbl_bpm: Label
var lbl_pressure: Label
var lbl_oxygen: Label

var bar_hull: ProgressBar
var bar_shield: ProgressBar
var lbl_nanites: Label
var lbl_radio: Label
var lbl_cam_mode: Label

# Reticle animation timer
var _reticle_pulse_time: float = 0.0
var _telemetry_ref: Node = null
var _flight_controller_ref: Node = null
var _weapon_system_ref: Node = null
var galaxy_map_instance: Node = null

# Smoothed reticle position — lerps toward mouse_flight_cursor to eliminate
# jitter from physics/render rate mismatch and per-frame input variation.
var _smoothed_cursor: Vector2 = Vector2.ZERO

# Wave Engine HUD Telemetry
var wave_state: int = 0 ## 0=OFF, 1=CHARGING, 2=ENGAGED, 3=DISENGAGING
var wave_charge_progress: float = 0.0
var wave_eta_seconds: float = 0.0
var wave_target_dist_m: float = 0.0
var wave_target_name: String = ""

# Planet Directional Marker state — points toward the nearest planet when it is
# within range, with a distance readout and color-coded proximity indicator.
const _PLANET_MARKER_MAX_RANGE_M: float = 50000.0
var _planet_marker_active: bool = false
var _planet_marker_screen_pos: Vector2 = Vector2.ZERO
var _planet_marker_offscreen: bool = false
var _planet_marker_distance_m: float = INF
var _planet_marker_name: String = ""
var _planet_marker_color: Color = Color(0.2, 1.0, 0.5, 0.85)

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_to_group("flight_hud")
	_build_ui_layout()
	_locate_engine_autoloads()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _exit_tree() -> void:
	if resized.is_connected(_on_resized):
		resized.disconnect(_on_resized)
	if _telemetry_ref and is_instance_valid(_telemetry_ref):
		if _telemetry_ref.is_connected("telemetry_updated", Callable(self, "_on_telemetry_updated")):
			_telemetry_ref.disconnect("telemetry_updated", Callable(self, "_on_telemetry_updated"))
	_disconnect_weapon_signals()

func _disconnect_weapon_signals() -> void:
	if _weapon_system_ref and is_instance_valid(_weapon_system_ref):
		var ws: Object = _weapon_system_ref
		if ws.is_connected("heat_updated", Callable(self, "_on_heat_updated")):
			ws.disconnect("heat_updated", Callable(self, "_on_heat_updated"))
		if ws.is_connected("lock_on_state_changed", Callable(self, "_on_lock_on_state_changed")):
			ws.disconnect("lock_on_state_changed", Callable(self, "_on_lock_on_state_changed"))
		if ws.is_connected("combat_state_changed", Callable(self, "_on_combat_state_changed")):
			ws.disconnect("combat_state_changed", Callable(self, "_on_combat_state_changed"))
		if ws.is_connected("overheat_triggered", Callable(self, "_on_overheat_triggered")):
			ws.disconnect("overheat_triggered", Callable(self, "_on_overheat_triggered"))

func _on_heat_updated(heat: float, max_heat: float) -> void:
	var pct: float = max_heat > 0.0 and (heat / max_heat) * 100.0 or 0.0
	exothermal_heat_pct = clampf(pct, 0.0, 100.0)

func _on_overheat_triggered(is_overheated: bool) -> void:
	_weapon_overheated = is_overheated

func _on_lock_on_state_changed(state: String, target: Node3D) -> void:
	_weapon_lock_state = state
	_weapon_lock_target = target

func _on_combat_state_changed(in_combat: bool) -> void:
	_in_combat = in_combat

## Called by BioPlasmaProjectile when it hits a target — triggers hit marker display
func _on_projectile_hit(hit_shield: bool, target_killed: bool) -> void:
	_hit_marker_timer = 1.0
	_hit_marker_is_shield = hit_shield
	_hit_marker_is_kill = target_killed

## Public setter so FlightController (or any damage source) can report the
## world-space position of incoming damage for the directional hit indicator.
func set_damage_source(world_pos: Vector3) -> void:
	_last_damage_source_pos = world_pos
	_has_damage_source = true

## Cycles to the next available target in the "targets" group (Tab key).
## Builds a fresh cache of valid targets, advances the index, and pins the
## selected target as the manual tracking override.
func _cycle_target() -> void:
	_refresh_target_list_cache()
	if _target_list_cache.is_empty():
		_manual_target_override = null
		_current_target_index = -1
		return
	_current_target_index = (_current_target_index + 1) % _target_list_cache.size()
	_manual_target_override = _target_list_cache[_current_target_index]

## Rebuilds _target_list_cache with all valid, non-celestial Node3D targets in
## the "targets" group. Celestial bodies (planets) are excluded from combat
## cycling since they are navigation destinations, not hostiles.
func _refresh_target_list_cache() -> void:
	_target_list_cache.clear()
	var tree := get_tree()
	if tree == null:
		return
	for t in tree.get_nodes_in_group("targets"):
		if not is_instance_valid(t) or not (t is Node3D):
			continue
		if t.is_queued_for_deletion():
			continue
		# Skip celestial bodies — they are wave-jump destinations, not combat targets.
		var is_celestial: bool = ("planet_name" in t) or t.is_in_group("celestial_bodies")
		if is_celestial:
			continue
		_target_list_cache.append(t)

func _on_resized() -> void:
	queue_redraw()

func _locate_engine_autoloads() -> void:
	if is_inside_tree() and get_tree() and get_tree().root and get_tree().root.has_node("OrganTelemetry"):
		_telemetry_ref = get_tree().root.get_node("OrganTelemetry")
	else:
		var ml := Engine.get_main_loop()
		if ml and ml.get("root") and ml.root.has_node("OrganTelemetry"):
			_telemetry_ref = ml.root.get_node("OrganTelemetry")

	if _telemetry_ref and _telemetry_ref.has_signal("telemetry_updated"):
		if not _telemetry_ref.is_connected("telemetry_updated", Callable(self, "_on_telemetry_updated")):
			_telemetry_ref.connect("telemetry_updated", Callable(self, "_on_telemetry_updated"))

	# Look for parent/sibling FlightController
	_find_flight_controller()
	# Locate WeaponSystem and wire its signals
	_locate_weapon_system()

func _find_flight_controller() -> void:
	if _flight_controller_ref and is_instance_valid(_flight_controller_ref):
		return
	var parent := get_parent()
	if parent and parent is FlightController:
		_flight_controller_ref = parent
		return
	if parent:
		var sibling_ship := parent.find_child("PlayerShip", true, false)
		if sibling_ship and sibling_ship is FlightController:
			_flight_controller_ref = sibling_ship
			return
		for child in parent.get_children():
			if child is FlightController:
				_flight_controller_ref = child
				return
	if is_inside_tree() and get_tree():
		var nodes := get_tree().get_nodes_in_group("flight_controller")
		if nodes.size() > 0:
			_flight_controller_ref = nodes[0]
			return
		var ships := get_tree().get_nodes_in_group("player_ship")
		if ships.size() > 0:
			_flight_controller_ref = ships[0]
			return

func _locate_weapon_system() -> void:
	if _weapon_system_ref and is_instance_valid(_weapon_system_ref):
		return
	# Search siblings/children of the flight controller or parent
	if _flight_controller_ref and is_instance_valid(_flight_controller_ref):
		var fc: Node = _flight_controller_ref
		for child in fc.get_children():
			if child is WeaponSystem:
				_weapon_system_ref = child
				break
		if not _weapon_system_ref:
			var parent := fc.get_parent()
			if parent:
				for child in parent.get_children():
					if child is WeaponSystem:
						_weapon_system_ref = child
						break
	# Fallback: search the scene tree
	if not _weapon_system_ref and is_inside_tree() and get_tree():
		for ws in get_tree().get_nodes_in_group("weapon_system"):
			_weapon_system_ref = ws
			break
		if not _weapon_system_ref:
			var p := get_parent()
			if p:
				var found := p.find_child("WeaponSystem", true, false)
				if found and found is WeaponSystem:
					_weapon_system_ref = found
	# Wire signals
	if _weapon_system_ref and is_instance_valid(_weapon_system_ref):
		var ws: Object = _weapon_system_ref
		if not ws.is_connected("heat_updated", Callable(self, "_on_heat_updated")):
			ws.connect("heat_updated", Callable(self, "_on_heat_updated"))
		if not ws.is_connected("lock_on_state_changed", Callable(self, "_on_lock_on_state_changed")):
			ws.connect("lock_on_state_changed", Callable(self, "_on_lock_on_state_changed"))
		if not ws.is_connected("combat_state_changed", Callable(self, "_on_combat_state_changed")):
			ws.connect("combat_state_changed", Callable(self, "_on_combat_state_changed"))
		if not ws.is_connected("overheat_triggered", Callable(self, "_on_overheat_triggered")):
			ws.connect("overheat_triggered", Callable(self, "_on_overheat_triggered"))

func _input(event: InputEvent) -> void:
	# Mouse input is handled solely by FlightController to avoid double-update jitter.
	# The HUD reads mouse_flight_cursor from the controller in _process().
	# Target cycling (Tab): cycle through available combat targets. When targets
	# exist we consume the event so it does not also trigger the organ inspector
	# in _unhandled_input; with no targets present we let it fall through.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_refresh_target_list_cache()
			if not _target_list_cache.is_empty():
				_cycle_target()
				set_input_as_handled()

func _on_telemetry_updated(data: Dictionary) -> void:
	if data.has("heart_rate_bpm"): heart_rate_bpm = data["heart_rate_bpm"]
	if data.has("hemolymph_pressure_bar"): hemolymph_pressure_bar = data["hemolymph_pressure_bar"]
	if data.has("oxygenation_yield_lpm"): oxygenation_yield_lpm = data["oxygenation_yield_lpm"]
	if data.has("nanite_repair_rate"): nanite_coagulation_m3s = data["nanite_repair_rate"]
	if data.has("radiotrophic_absorption_gy_hr"): radiotrophic_abs_gy_hr = data["radiotrophic_absorption_gy_hr"]
	if data.has("neural_sync_rate"): neural_sync_pct = data["neural_sync_rate"]
	
	_update_ui_labels()

func _process(delta: float) -> void:
	_reticle_pulse_time += delta

	# Ensure reference to FlightController
	if not _flight_controller_ref or not is_instance_valid(_flight_controller_ref):
		_find_flight_controller()

	# Ensure WeaponSystem reference and signals
	if not _weapon_system_ref or not is_instance_valid(_weapon_system_ref):
		_locate_weapon_system()

	# Pull updates from FlightController if available
	if _flight_controller_ref and is_instance_valid(_flight_controller_ref):
		if "linear_velocity_vector" in _flight_controller_ref:
			current_speed_ms = _flight_controller_ref.linear_velocity_vector.length()
		if "current_g_force" in _flight_controller_ref:
			current_g_force = _flight_controller_ref.current_g_force
		if "bio_plasma_fuel" in _flight_controller_ref and "max_bio_plasma_fuel" in _flight_controller_ref:
			var max_f: float = maxf(0.001, _flight_controller_ref.max_bio_plasma_fuel)
			bio_plasma_fuel_pct = (_flight_controller_ref.bio_plasma_fuel / max_f) * 100.0
		if "mouse_flight_cursor" in _flight_controller_ref:
			mouse_flight_cursor = _flight_controller_ref.mouse_flight_cursor
		if "wave_state" in _flight_controller_ref:
			wave_state = _flight_controller_ref.wave_state
		if "wave_charge_timer" in _flight_controller_ref and "wave_charge_duration" in _flight_controller_ref:
			var dur: float = maxf(0.01, _flight_controller_ref.wave_charge_duration)
			wave_charge_progress = clampf(1.0 - (_flight_controller_ref.wave_charge_timer / dur), 0.0, 1.0)
		if "wave_eta_seconds" in _flight_controller_ref:
			wave_eta_seconds = _flight_controller_ref.wave_eta_seconds
		if "wave_target_name" in _flight_controller_ref:
			wave_target_name = _flight_controller_ref.wave_target_name
		# Combat: pull hull integrity and shield from FlightController
		if "hull_integrity" in _flight_controller_ref:
			hull_integrity_pct = clampf(_flight_controller_ref.hull_integrity, 0.0, 100.0)
		if "bio_shield" in _flight_controller_ref:
			bio_shield_pct = clampf(_flight_controller_ref.bio_shield, 0.0, 100.0)
		if "damage_flash_timer" in _flight_controller_ref:
			_damage_flash_visual = clampf(_flight_controller_ref.damage_flash_timer, 0.0, 1.0)
		# Pull directional damage source from FlightController if it exposes one.
		if "last_damage_source_pos" in _flight_controller_ref:
			var src: Vector3 = _flight_controller_ref.last_damage_source_pos
			if src != Vector3.ZERO:
				_last_damage_source_pos = src
				_has_damage_source = true
	else:
		mouse_flight_cursor = mouse_flight_cursor.lerp(Vector2.ZERO, delta * 3.5)
		wave_state = 0

	# Smooth the reticle cursor toward the target to eliminate jitter from
	# physics/render rate mismatch. High lerp factor = responsive but smooth.
	_smoothed_cursor = _smoothed_cursor.lerp(mouse_flight_cursor, clampf(delta * 18.0, 0.0, 1.0))

	# Smooth target and planet marker screen positions for stable indicators
	_smoothed_target_pos = _smoothed_target_pos.lerp(target_screen_position, clampf(delta * 20.0, 0.0, 1.0))
	_smoothed_lead_pos = _smoothed_lead_pos.lerp(lead_indicator_position, clampf(delta * 20.0, 0.0, 1.0))
	_smoothed_planet_marker_pos = _smoothed_planet_marker_pos.lerp(_planet_marker_screen_pos, clampf(delta * 15.0, 0.0, 1.0))

	# 3D World-to-Screen Target Tracking (Real Void Fauna Drones / Hostile Entities)
	_update_target_tracking_3d()

	# Planet directional marker — nearest celestial body indicator + distance.
	_update_nearest_planet_marker()

	# Threat assessment — hostile count, threat level, incoming-fire warning.
	_update_threat_assessment()

	# Decay hit marker timer
	if _hit_marker_timer > 0.0:
		_hit_marker_timer = maxf(0.0, _hit_marker_timer - delta * 3.5)

	# Dynamic Tension Index (DTI) Audio Telemetry
	var dti: float = 0.0
	if target_locked: dti += 0.35
	if current_speed_ms > 120.0: dti += 0.20
	if hull_integrity_pct < 50.0: dti += 0.30
	if bio_shield_pct < 50.0: dti += 0.25
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").tension_index = clampf(dti, 0.0, 1.0)

	_update_ui_labels()
	queue_redraw()

## Projects 3D world targets onto 2D screen coordinates for authentic space combat tracking.
func _update_target_tracking_3d() -> void:
	target_locked = false
	_current_target_node = null
	var cam: Camera3D = null
	if is_inside_tree() and get_viewport():
		cam = get_viewport().get_camera_3d()

	if not cam:
		return

	var tree := get_tree()
	if not tree:
		return

	var center := size * 0.5

	# If the wave engine has a locked target, show that target's indicator
	# regardless of screen position or distance — it's where we're going.
	if _flight_controller_ref and "wave_target_node" in _flight_controller_ref:
		var wave_target = _flight_controller_ref.wave_target_node
		if wave_target and is_instance_valid(wave_target) and wave_target is Node3D:
			var t_pos := (wave_target as Node3D).global_position
			if not cam.is_position_behind(t_pos):
				target_locked = true
				target_screen_position = cam.unproject_position(t_pos)
				target_distance_m = cam.global_position.distance_to(t_pos)
				_current_target_node = wave_target as Node3D
				if "planet_name" in wave_target:
					target_name = wave_target.planet_name
					var r_km = wave_target.real_radius_km if "real_radius_km" in wave_target else 6371.0
					var grav = wave_target.surface_gravity_g if "surface_gravity_g" in wave_target else 1.0
					var temp = wave_target.surface_temp_k if "surface_temp_k" in wave_target else 288.0
					target_details = "R: %d km | G: %.2fG | T: %dK" % [int(r_km), grav, int(temp)]
				else:
					target_name = wave_target.name
					target_details = "WAVE JUMP DESTINATION"
				return

	# Refresh the combat-target cache (non-celestial Node3D targets) for Tab cycling.
	_refresh_target_list_cache()

	# Manual override (Tab cycling): if a specific target was selected, track it
	# exclusively instead of auto-selecting the nearest. Drop the override if the
	# node is no longer valid.
	if _manual_target_override != null:
		if is_instance_valid(_manual_target_override) and _manual_target_override is Node3D and not _manual_target_override.is_queued_for_deletion():
			var mt: Node3D = _manual_target_override
			var mt_pos := mt.global_position
			if not cam.is_position_behind(mt_pos):
				var mt_screen := cam.unproject_position(mt_pos)
				var mt_dist := cam.global_position.distance_to(mt_pos)
				target_locked = true
				target_screen_position = mt_screen
				target_distance_m = mt_dist
				_current_target_node = mt
				_apply_target_telemetry(mt, mt_screen, mt_dist, cam)
			return
		else:
			_manual_target_override = null
			_current_target_index = -1

	var targets := tree.get_nodes_in_group("targets")
	var best_dist := INF
	
	for t in targets:
		if is_instance_valid(t) and t is Node3D and not t.is_queued_for_deletion():
			var t_pos := (t as Node3D).global_position
			if not cam.is_position_behind(t_pos):
				var screen_pos := cam.unproject_position(t_pos)
				var d_center := screen_pos.distance_to(center)
				var is_celestial := ("planet_name" in t) or t.is_in_group("celestial_bodies")
				var max_lock_range := 50000000.0 if is_celestial else 2500.0
				var d_world := cam.global_position.distance_to(t_pos)
				if d_world < max_lock_range and d_center < (size.y * 0.48):
					if d_world < best_dist:
						best_dist = d_world
						target_locked = true
						target_distance_m = d_world
						target_screen_position = screen_pos
						_current_target_node = t as Node3D
						_apply_target_telemetry(t as Node3D, screen_pos, d_world, cam)

## Populates target_name, target_details, and lead_indicator_position for the
## given tracked target. Shared by the auto-select and manual-override paths.
func _apply_target_telemetry(t: Node3D, screen_pos: Vector2, d_world: float, cam: Camera3D) -> void:
	if "planet_name" in t:
		target_name = t.planet_name
		var r_km = t.real_radius_km if "real_radius_km" in t else 6371.0
		var grav = t.surface_gravity_g if "surface_gravity_g" in t else 1.0
		var temp = t.surface_temp_k if "surface_temp_k" in t else 288.0
		target_details = "R: %d km | G: %.2fG | T: %dK" % [int(r_km), grav, int(temp)]
	else:
		target_name = t.name
		target_details = "VOID-FAUNA HOSTILE"
	# Lead prediction pip calculation based on projectile speed
	var projectile_speed := 200.0
	var t_vel := Vector3.ZERO
	if "linear_velocity" in t:
		t_vel = t.linear_velocity
	elif "velocity" in t:
		t_vel = t.velocity
	var time_to_hit := d_world / maxf(10.0, projectile_speed)
	var lead_world_pos := t.global_position + t_vel * time_to_hit
	if not cam.is_position_behind(lead_world_pos):
		lead_indicator_position = cam.unproject_position(lead_world_pos)
	else:
		lead_indicator_position = screen_pos

## Computes threat assessment state each frame: hostile count (void_fauna in
## CHASE/ATTACK states, or any void_fauna if ai_state is unavailable), threat
## level (LOW/MEDIUM/HIGH), and an incoming-fire warning when an enemy
## projectile is within 50m of the player and heading toward them.
func _update_threat_assessment() -> void:
	_hostile_count = 0
	_incoming_fire_warning = false
	var tree := get_tree()
	if tree == null:
		return

	# Count hostile void_fauna. Prefer the ai_state enum (CHASE=1, ATTACK=2);
	# fall back to counting any void_fauna node if the property is absent.
	for n in tree.get_nodes_in_group("void_fauna"):
		if not is_instance_valid(n):
			continue
		if n is Node3D and n.is_queued_for_deletion():
			continue
		if "ai_state" in n:
			var st: int = int(n.ai_state)
			# AIState: PATROL=0, CHASE=1, ATTACK=2, FLEE=3, DEAD=4
			if st == 1 or st == 2:
				_hostile_count += 1
		else:
			_hostile_count += 1

	# Threat level: LOW (0-1), MEDIUM (2-4), HIGH (5+)
	if _hostile_count <= 1:
		_threat_level = "LOW"
		_threat_color = Color(0.2, 1.0, 0.4, 0.9)
	elif _hostile_count <= 4:
		_threat_level = "MEDIUM"
		_threat_color = Color(1.0, 0.85, 0.2, 0.95)
	else:
		_threat_level = "HIGH"
		_threat_color = Color(1.0, 0.25, 0.2, 0.95)

	# Incoming fire warning: any BioPlasmaProjectile within 50m of the player
	# that is traveling toward the player (excludes player-fired outgoing bolts).
	var player_pos := Vector3.ZERO
	if _flight_controller_ref and is_instance_valid(_flight_controller_ref) and _flight_controller_ref is Node3D:
		player_pos = (_flight_controller_ref as Node3D).global_position
	else:
		return
	var current_scene := tree.current_scene
	if current_scene == null:
		return
	for child in current_scene.get_children():
		if not (child is BioPlasmaProjectile):
			continue
		if not is_instance_valid(child):
			continue
		var proj := child as BioPlasmaProjectile
		var to_player: Vector3 = player_pos - proj.global_position
		var dist: float = to_player.length()
		if dist > 50.0:
			continue
		# Direction of travel — if heading toward the player, flag as incoming.
		var dir: Vector3 = proj.direction
		if dir.length_squared() > 1e-6 and to_player.length_squared() > 1e-6:
			if dir.normalized().dot(to_player.normalized()) > 0.0:
				_incoming_fire_warning = true
				break


## Tracks the nearest celestial body in the "targets" group for the directional
## marker. Populates _planet_marker_* state consumed by _draw(). Prefers the
## nearest-planet info pushed by PlanetEntryManager (via FlightController) and
## falls back to a direct tree scan when the manager is unavailable.
func _update_nearest_planet_marker() -> void:
	_planet_marker_active = false
	var tree := get_tree()
	if tree == null:
		return
	var cam: Camera3D = null
	if is_inside_tree() and get_viewport():
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var best_dist: float = INF
	var best_pos := Vector3.ZERO
	var best_name := ""

	# Prefer PlanetEntryManager's cached nearest planet (updated by
	# FlightController every physics frame) to avoid a redundant tree scan.
	var pem: Node = null
	if tree.root != null:
		pem = tree.root.get_node_or_null("/root/PlanetEntryManager")
	if pem != null and pem.has_method("get_nearest_planet"):
		var cached: Node3D = pem.call("get_nearest_planet") as Node3D
		if cached != null and is_instance_valid(cached):
			var cached_dist: float = INF
			if pem.has_method("get_nearest_planet_distance"):
				cached_dist = float(pem.call("get_nearest_planet_distance"))
			best_pos = cached.global_position
			best_dist = cached_dist if cached_dist < INF else cam.global_position.distance_to(best_pos)
			best_name = cached.get("planet_name") if "planet_name" in cached else cached.name

	# Fallback: scan the "targets" group for celestial bodies directly.
	if best_dist == INF:
		var targets := tree.get_nodes_in_group("targets")
		for t in targets:
			if not is_instance_valid(t) or not (t is Node3D):
				continue
			var is_celestial: bool = ("planet_name" in t) or t.is_in_group("celestial_bodies")
			if not is_celestial:
				continue
			var t_pos := (t as Node3D).global_position
			var d_world := cam.global_position.distance_to(t_pos)
			if d_world < best_dist:
				best_dist = d_world
				best_pos = t_pos
				best_name = t.get("planet_name") if "planet_name" in t else t.name

	if best_dist > _PLANET_MARKER_MAX_RANGE_M:
		return

	_planet_marker_active = true
	_planet_marker_distance_m = best_dist
	_planet_marker_name = best_name

	# Color-code by proximity: red (descent imminent), yellow (approaching), green (far).
	if best_dist < 5000.0:
		_planet_marker_color = Color(1.0, 0.2, 0.2, 0.95)
	elif best_dist < 20000.0:
		_planet_marker_color = Color(1.0, 0.85, 0.2, 0.9)
	else:
		_planet_marker_color = Color(0.2, 1.0, 0.5, 0.85)

	# Project the planet position to screen space.
	var behind: bool = cam.is_position_behind(best_pos)
	if not behind:
		var sp := cam.unproject_position(best_pos)
		# Treat positions outside the viewport as off-screen (edge indicator).
		if sp.x < 0.0 or sp.x > size.x or sp.y < 0.0 or sp.y > size.y:
			_planet_marker_offscreen = true
		else:
			_planet_marker_offscreen = false
		_planet_marker_screen_pos = sp
	else:
		_planet_marker_offscreen = true
		_planet_marker_screen_pos = Vector2.ZERO

func _change_scene(path: String) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioDirector"):
		ml.root.get_node("BioAudioDirector").transition_to_scene(path)
	else:
		if is_inside_tree() and get_tree():
			get_tree().change_scene_to_file(path)
		elif ml and ml.has_method("change_scene_to_file"):
			ml.call("change_scene_to_file", path)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			inspect_organs_requested.emit()
			_change_scene("res://scenes/organ_inspector.tscn")
		elif event.keycode == KEY_M:
			_toggle_galaxy_map()

func _toggle_galaxy_map() -> void:
	if galaxy_map_instance and is_instance_valid(galaxy_map_instance):
		galaxy_map_instance.queue_free()
		galaxy_map_instance = null
		
		# Show flight HUD
		top_bar_panel.show()
		bottom_left_panel.show()
		bottom_right_panel.show()
		controls_banner.show()
		queue_redraw()
		
		if _flight_controller_ref and is_instance_valid(_flight_controller_ref):
			_flight_controller_ref.set_process_unhandled_input(true)
			_flight_controller_ref.set_process_input(true)
			_flight_controller_ref.set_physics_process(true)
			if "camera_node" in _flight_controller_ref and _flight_controller_ref.camera_node:
				_flight_controller_ref.camera_node.current = true
				
		var root_scene := get_tree().current_scene
		if root_scene:
			var asteroid_field := root_scene.get_node_or_null("AsteroidField")
			if asteroid_field:
				asteroid_field.show()
	else:
		# Hide flight HUD
		top_bar_panel.hide()
		bottom_left_panel.hide()
		bottom_right_panel.hide()
		controls_banner.hide()
		queue_redraw()
		
		var root_scene := get_tree().current_scene
		
		var map_packed := load("res://scenes/galaxy_map.tscn")
		if map_packed:
			galaxy_map_instance = map_packed.instantiate()
			# Add to the root 3D scene, NOT the 2D UI CanvasLayer
			if root_scene:
				root_scene.add_child(galaxy_map_instance)
			else:
				add_child(galaxy_map_instance)
				
			# Explicitly set the map's camera to current so it receives input and renders
			var map_cam := galaxy_map_instance.get_node_or_null("CameraPivot/Camera3D")
			if map_cam:
				map_cam.current = true
			elif galaxy_map_instance.get_node_or_null("GalaxyMapCamera"):
				galaxy_map_instance.get_node("GalaxyMapCamera").current = true
			
			var map_manager := galaxy_map_instance.get_node_or_null("GalaxyMapManager")
			var map_ui := galaxy_map_instance.get_node_or_null("UI/GalaxyMapUI")
			
			if map_manager and map_ui:
				# Disconnect the map's own debug jump sequence and hook it into the true flight controller
				if map_ui.is_connected("wave_ride_engaged", Callable(map_manager, "_on_wave_ride_engaged")):
					map_ui.disconnect("wave_ride_engaged", Callable(map_manager, "_on_wave_ride_engaged"))
				
				# Connect it to our HUD handler instead
				map_ui.connect("wave_ride_engaged", Callable(self, "_on_wave_ride_engaged_from_map").bind(map_manager))
			
			if _flight_controller_ref and is_instance_valid(_flight_controller_ref):
				# Disable normal flight controls while map is open
				_flight_controller_ref.set_process_unhandled_input(false)
				_flight_controller_ref.set_process_input(false)
				_flight_controller_ref.set_physics_process(false)
				
				# Free the mouse if it was captured for flight
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				
		if root_scene:
			var asteroid_field := root_scene.get_node_or_null("AsteroidField")
			if asteroid_field:
				asteroid_field.hide()

func _on_wave_ride_engaged_from_map(system_data: Dictionary, map_manager: Node) -> void:
	print("FlightHUDUI: Engaging HyperWave Autopilot to ", system_data.get("name", "Unknown"))
	
	# Close map and restore flight state
	_toggle_galaxy_map()
	
	# Start Autopilot
	var HyperWaveAutopilotClass := load("res://scripts/HyperWaveAutopilot.gd")
	if HyperWaveAutopilotClass and map_manager and _flight_controller_ref:
		var autopilot = HyperWaveAutopilotClass.new()
		# Add to the root so it persists
		get_tree().root.add_child(autopilot)
		
		# Try to find UniverseManager
		var universe = null
		if get_tree().root.has_node("UniverseManager"):
			universe = get_tree().root.get_node("UniverseManager")
			
		autopilot.start_jump_sequence(_flight_controller_ref, universe, map_manager.current_route_path, map_manager.current_route_names, map_manager.current_route_seeds)

func _update_ui_labels() -> void:
	if lbl_speed: lbl_speed.text = "SPEED: %d m/s" % int(current_speed_ms)
	if lbl_gforce: lbl_gforce.text = "G-FORCE: %.1f G" % current_g_force
	if lbl_altitude: lbl_altitude.text = "ALTITUDE: %d m" % int(altitude_m)
	if bar_fuel: bar_fuel.value = clampf(bio_plasma_fuel_pct, 0.0, 100.0)
	if lbl_sync: lbl_sync.text = "SYNC: %.1f%%" % neural_sync_pct

	if lbl_bpm: lbl_bpm.text = "HEART RATE: %d BPM" % int(heart_rate_bpm)
	if lbl_pressure: lbl_pressure.text = "PRESSURE: %.2f Bar" % hemolymph_pressure_bar
	if lbl_oxygen: lbl_oxygen.text = "OXYGEN: %d L/min" % int(oxygenation_yield_lpm)

	if bar_hull: bar_hull.value = clampf(hull_integrity_pct, 0.0, 100.0)
	if bar_shield: bar_shield.value = clampf(bio_shield_pct, 0.0, 100.0)
	if lbl_nanites: lbl_nanites.text = "NANITES: %.2f m³/s" % nanite_coagulation_m3s
	if lbl_radio: lbl_radio.text = "RADIOTROPHIC: %.1f Gy/hr" % radiotrophic_abs_gy_hr

	if lbl_cam_mode and _flight_controller_ref and is_instance_valid(_flight_controller_ref):
		var mode_val = _flight_controller_ref.get("camera_mode")
		if mode_val == 0:
			lbl_cam_mode.text = "[V] VIEW: COMMAND CENTER FPV"
		else:
			lbl_cam_mode.text = "[V] VIEW: EXTERIOR TACTICAL"

# ------------------------------------------------------------------------------
# UI Layout Construction
# ------------------------------------------------------------------------------

func _build_ui_layout() -> void:
	# Clear existing children if re-building in editor
	for child in get_children():
		child.queue_free()

	# Create Main Top Bar Panel
	top_bar_panel = _create_glass_panel()
	top_bar_panel.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	top_bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_bar_panel.grow_vertical = Control.GROW_DIRECTION_END
	top_bar_panel.offset_top = 10
	top_bar_panel.offset_bottom = 58
	top_bar_panel.offset_left = 20
	top_bar_panel.offset_right = -20
	top_bar_panel.custom_minimum_size.y = 48
	add_child(top_bar_panel)

	var top_hb := HBoxContainer.new()
	top_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hb.add_theme_constant_override("separation", 24)
	top_bar_panel.add_child(top_hb)

	lbl_speed = _create_hud_label("SPEED: 0 m/s", Color(0.0, 1.0, 0.8))
	top_hb.add_child(lbl_speed)

	lbl_gforce = _create_hud_label("G-FORCE: 1.0 G", Color(1.0, 0.8, 0.2))
	top_hb.add_child(lbl_gforce)

	lbl_altitude = _create_hud_label("ALTITUDE: 1000 m", Color(0.4, 0.9, 1.0))
	top_hb.add_child(lbl_altitude)

	# Fuel Container
	var fuel_vb := VBoxContainer.new()
	var lbl_fuel_header := _create_hud_label("BIO-PLASMA FUEL", Color(0.0, 1.0, 0.6), 10)
	bar_fuel = ProgressBar.new()
	bar_fuel.custom_minimum_size = Vector2(140, 14)
	bar_fuel.value = 88.0
	bar_fuel.show_percentage = true
	fuel_vb.add_child(lbl_fuel_header)
	fuel_vb.add_child(bar_fuel)
	top_hb.add_child(fuel_vb)

	lbl_sync = _create_hud_label("SYNC: 98.4%", Color(0.8, 0.4, 1.0))
	top_hb.add_child(lbl_sync)

	lbl_cam_mode = _create_hud_label("[V] VIEW: COMMAND CENTER FPV", Color(0.0, 1.0, 0.8), 11)
	top_hb.add_child(lbl_cam_mode)

	# Bottom Left Telemetry Panel (ECG + Biometrics)
	bottom_left_panel = _create_glass_panel()
	bottom_left_panel.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	bottom_left_panel.grow_horizontal = Control.GROW_DIRECTION_END
	bottom_left_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_left_panel.offset_left = 20
	bottom_left_panel.offset_right = 320
	bottom_left_panel.offset_top = -210
	bottom_left_panel.offset_bottom = -20
	bottom_left_panel.custom_minimum_size = Vector2(300, 180)
	add_child(bottom_left_panel)

	var bl_vb := VBoxContainer.new()
	bl_vb.add_theme_constant_override("separation", 6)
	bottom_left_panel.add_child(bl_vb)

	var lbl_bl_title := _create_hud_label("CARDIO-VASCULAR TELEMETRY", Color(0.0, 1.0, 0.7), 11)
	bl_vb.add_child(lbl_bl_title)

	# ECG Graph Widget
	ecg_widget = ECGGraph.new()
	ecg_widget.custom_minimum_size = Vector2(280, 80)
	bl_vb.add_child(ecg_widget)

	lbl_bpm = _create_hud_label("HEART RATE: 72 BPM", Color(0.2, 1.0, 0.5), 12)
	bl_vb.add_child(lbl_bpm)

	lbl_pressure = _create_hud_label("PRESSURE: 15.50 Bar", Color(0.0, 0.9, 0.9), 11)
	bl_vb.add_child(lbl_pressure)

	lbl_oxygen = _create_hud_label("OXYGEN: 420 L/min", Color(0.4, 1.0, 0.8), 11)
	bl_vb.add_child(lbl_oxygen)

	# Bottom Right Defense Panel (Hull, Shield, Nanites)
	bottom_right_panel = _create_glass_panel()
	bottom_right_panel.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	bottom_right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_right_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right_panel.offset_left = -310
	bottom_right_panel.offset_right = -20
	bottom_right_panel.offset_top = -210
	bottom_right_panel.offset_bottom = -20
	bottom_right_panel.custom_minimum_size = Vector2(280, 180)
	add_child(bottom_right_panel)

	var br_vb := VBoxContainer.new()
	br_vb.add_theme_constant_override("separation", 6)
	bottom_right_panel.add_child(br_vb)

	var lbl_br_title := _create_hud_label("EXOSKELETON & BIO-DEFENSE", Color(0.0, 0.8, 1.0), 11)
	br_vb.add_child(lbl_br_title)

	var lbl_hull_hdr := _create_hud_label("HULL INTEGRITY", Color(0.2, 1.0, 0.4), 10)
	bar_hull = ProgressBar.new()
	bar_hull.custom_minimum_size = Vector2(250, 14)
	bar_hull.value = 100.0
	br_vb.add_child(lbl_hull_hdr)
	br_vb.add_child(bar_hull)

	var lbl_shield_hdr := _create_hud_label("BIO-SHIELD VECTOR", Color(0.0, 0.7, 1.0), 10)
	bar_shield = ProgressBar.new()
	bar_shield.custom_minimum_size = Vector2(250, 14)
	bar_shield.value = 100.0
	br_vb.add_child(lbl_shield_hdr)
	br_vb.add_child(bar_shield)

	lbl_nanites = _create_hud_label("NANITES: 1.20 m³/s", Color(0.8, 1.0, 0.3), 11)
	br_vb.add_child(lbl_nanites)

	lbl_radio = _create_hud_label("RADIOTROPHIC: 45.0 Gy/hr", Color(1.0, 0.6, 0.2), 11)
	br_vb.add_child(lbl_radio)

	# Bottom Center Controls Keybindings Banner
	controls_banner = _create_glass_panel()
	controls_banner.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	controls_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	controls_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls_banner.offset_left = -340
	controls_banner.offset_right = 340
	controls_banner.offset_top = -46
	controls_banner.offset_bottom = -14
	controls_banner.custom_minimum_size = Vector2(680, 32)
	add_child(controls_banner)

	var lbl_controls := _create_hud_label(
		"[W/S] Throttle & Brake  |  [A/D/Mouse] Steer & Auto-Bank  |  [Q/E] Roll  |  [SHIFT] Boost  |  [RMB/F] Combat Auto-Follow  |  [LMB] Disruptors  |  [TAB] Organs  |  [M] Galaxy Map",
		Color(0.0, 1.0, 0.75, 0.9), 11
	)
	lbl_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_controls.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_controls.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	controls_banner.add_child(lbl_controls)

func _create_glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.06, 0.05, 0.75)
	style.border_color = Color(0.0, 0.8, 0.6, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_expand_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _create_hud_label(text: String, font_color: Color, size_override: int = 13) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_font_size_override("font_size", size_override)
	return lbl

# ------------------------------------------------------------------------------
# Canvas Drawing (Dynamic Crosshair, Lead Indicator, Heat Gauge)
# ------------------------------------------------------------------------------

func _draw() -> void:
	if galaxy_map_instance and is_instance_valid(galaxy_map_instance):
		return
		
	if size.x <= 10.0 or size.y <= 10.0:
		return

	var center := size * 0.5
	var ui_scale: float = clampf(size.y / 1080.0, 0.65, 2.5)
	var main_color := Color(0.0, 1.0, 0.75, 0.85)
	var lock_color := Color(1.0, 0.25, 0.2, 0.9) if target_locked else Color(0.0, 0.8, 1.0, 0.7)

	# 0a. Thin Scanline Grid Overlay across entire HUD
	var scan_spacing: float = maxf(2.0, 4.0 * ui_scale)
	var scan_lines_count: int = int(size.y / scan_spacing)
	for i in range(scan_lines_count):
		var sy: float = float(i) * scan_spacing
		draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(0.0, 0.15, 0.1, 0.03), 1.0)

	# 0b. Animated Breathing Corner Brackets
	var bracket_len: float = (28.0 + sin(_reticle_pulse_time * 2.5) * 4.0) * ui_scale
	var bracket_w: float = maxf(1.0, 2.0 * ui_scale)
	var bracket_col := Color(0.0, 1.0, 0.75, 0.5 + sin(_reticle_pulse_time * 2.5) * 0.15)
	var bracket_inset: float = 18.0 * ui_scale
	# Top-left
	draw_line(Vector2(bracket_inset, bracket_inset), Vector2(bracket_inset + bracket_len, bracket_inset), bracket_col, bracket_w)
	draw_line(Vector2(bracket_inset, bracket_inset), Vector2(bracket_inset, bracket_inset + bracket_len), bracket_col, bracket_w)
	# Top-right
	draw_line(Vector2(size.x - bracket_inset, bracket_inset), Vector2(size.x - bracket_inset - bracket_len, bracket_inset), bracket_col, bracket_w)
	draw_line(Vector2(size.x - bracket_inset, bracket_inset), Vector2(size.x - bracket_inset, bracket_inset + bracket_len), bracket_col, bracket_w)
	# Bottom-left
	draw_line(Vector2(bracket_inset, size.y - bracket_inset), Vector2(bracket_inset + bracket_len, size.y - bracket_inset), bracket_col, bracket_w)
	draw_line(Vector2(bracket_inset, size.y - bracket_inset), Vector2(bracket_inset, size.y - bracket_inset - bracket_len), bracket_col, bracket_w)
	# Bottom-right
	draw_line(Vector2(size.x - bracket_inset, size.y - bracket_inset), Vector2(size.x - bracket_inset - bracket_len, size.y - bracket_inset), bracket_col, bracket_w)
	draw_line(Vector2(size.x - bracket_inset, size.y - bracket_inset), Vector2(size.x - bracket_inset, size.y - bracket_inset - bracket_len), bracket_col, bracket_w)

	# --------------------------------------------------------------------------
	# NO MAN'S SKY TETHERED MOUSE FLIGHT HUD
	# --------------------------------------------------------------------------
	var max_r := tether_max_radius * ui_scale
	var dead_r := tether_deadzone_radius * ui_scale
	var flight_reticle_pos := center + _smoothed_cursor * max_r
	var tether_vec := flight_reticle_pos - center
	var tether_len := tether_vec.length()

	# 1. Outer Flight Steering Boundary Ring
	draw_arc(center, max_r, 0, TAU, 64, Color(0.0, 0.8, 0.6, 0.15), maxf(1.0, 1.2 * ui_scale))
	for i in range(12):
		var ang := (float(i) / 12.0) * TAU
		var p1 := center + Vector2(cos(ang), sin(ang)) * (max_r - 4.0 * ui_scale)
		var p2 := center + Vector2(cos(ang), sin(ang)) * (max_r + 4.0 * ui_scale)
		draw_line(p1, p2, Color(0.0, 1.0, 0.75, 0.3), 1.0)

	# 2. Central Deadzone Ring
	draw_arc(center, dead_r, 0, TAU, 32, Color(0.0, 1.0, 0.75, 0.25), maxf(1.0, 1.0 * ui_scale))

	# 3. Fixed Ship Boresight (Fixed Nose Crosshair)
	var boresight_r := 10.0 * ui_scale
	draw_circle(center, 2.0 * ui_scale, Color(0.0, 1.0, 0.75, 0.9))
	draw_arc(center, boresight_r, 0, TAU, 32, Color(0.0, 1.0, 0.75, 0.7), maxf(1.0, 1.2 * ui_scale))
	var bore_gap := 4.0 * ui_scale
	var bore_len := 8.0 * ui_scale
	draw_line(center + Vector2(0, -boresight_r - bore_gap), center + Vector2(0, -boresight_r - bore_gap - bore_len), Color(0.0, 1.0, 0.75, 0.6), 1.2)
	draw_line(center + Vector2(0, boresight_r + bore_gap), center + Vector2(0, boresight_r + bore_gap + bore_len), Color(0.0, 1.0, 0.75, 0.6), 1.2)
	draw_line(center + Vector2(-boresight_r - bore_gap, 0), center + Vector2(-boresight_r - bore_gap - bore_len, 0), Color(0.0, 1.0, 0.75, 0.6), 1.2)
	draw_line(center + Vector2(boresight_r + bore_gap, 0), center + Vector2(boresight_r + bore_gap + bore_len, 0), Color(0.0, 1.0, 0.75, 0.6), 1.2)

	# 4. Dynamic Holographic Flight Tether (Connects Ship Boresight to Floating Flight Reticle)
	if tether_len > dead_r:
		var tether_norm := clampf((tether_len - dead_r) / maxf(1.0, max_r - dead_r), 0.0, 1.0)
		var tether_col := Color(0.0, 1.0, 0.75, 0.4 + tether_norm * 0.45)
		draw_line(center + tether_vec.normalized() * dead_r, flight_reticle_pos, tether_col, maxf(1.5, 2.0 * ui_scale))
		# Intermediate animated pulse bead along the tether
		var bead_dist := dead_r + fmod(_reticle_pulse_time * 160.0, maxf(1.0, tether_len - dead_r))
		var bead_pos := center + tether_vec.normalized() * bead_dist
		draw_circle(bead_pos, 2.5 * ui_scale, Color(0.4, 1.0, 0.9, 0.85))

	# 5. Floating Mouse Flight Aiming Reticle (NMS Flight Pip / Chevrons)
	var reticle_r: float = 14.0 * ui_scale
	draw_circle(flight_reticle_pos, 3.0 * ui_scale, main_color)
	draw_arc(flight_reticle_pos, reticle_r, 0, TAU, 32, main_color, maxf(1.0, 1.5 * ui_scale))

	# Flight pip chevrons
	var gap: float = 5.0 * ui_scale
	var arm_len: float = 10.0 * ui_scale
	var arm_w: float = maxf(1.0, 1.5 * ui_scale)
	draw_line(flight_reticle_pos + Vector2(0, -reticle_r - gap), flight_reticle_pos + Vector2(0, -reticle_r - gap - arm_len), main_color, arm_w)
	draw_line(flight_reticle_pos + Vector2(0, reticle_r + gap), flight_reticle_pos + Vector2(0, reticle_r + gap + arm_len), main_color, arm_w)
	draw_line(flight_reticle_pos + Vector2(-reticle_r - gap, 0), flight_reticle_pos + Vector2(-reticle_r - gap - arm_len, 0), main_color, arm_w)
	draw_line(flight_reticle_pos + Vector2(reticle_r + gap, 0), flight_reticle_pos + Vector2(reticle_r + gap + arm_len, 0), main_color, arm_w)

	# 6. Animated Rotating Compass Ring around Floating Reticle
	var compass_r: float = 38.0 * ui_scale
	var compass_rot: float = _reticle_pulse_time * 0.4
	var compass_col := Color(0.0, 0.9, 0.7, 0.35)
	draw_arc(flight_reticle_pos, compass_r, 0, TAU, 48, Color(0.0, 0.8, 0.65, 0.2), maxf(1.0, 1.0 * ui_scale))
	var compass_dirs: int = 16
	for i in range(compass_dirs):
		var c_angle: float = (float(i) / float(compass_dirs)) * TAU + compass_rot
		var is_cardinal: bool = (i % 4 == 0)
		var tick_inner: float = compass_r - ((6.0 if is_cardinal else 3.0) * ui_scale)
		var tick_outer: float = compass_r + ((6.0 if is_cardinal else 3.0) * ui_scale)
		var tick_col := compass_col if not is_cardinal else Color(0.0, 1.0, 0.75, 0.6)
		var tick_w: float = maxf(1.0, (2.0 if is_cardinal else 1.0) * ui_scale)
		draw_line(flight_reticle_pos + Vector2(cos(c_angle), sin(c_angle)) * tick_inner,
			flight_reticle_pos + Vector2(cos(c_angle), sin(c_angle)) * tick_outer, tick_col, tick_w)

	# 7. Velocity Vector Indicator Line from Floating Reticle
	var speed_norm: float = clampf(current_speed_ms / maxf(1.0, max_speed_ms), 0.0, 1.0)
	var vel_line_len: float = 50.0 * ui_scale * speed_norm
	var vel_angle: float = -PI * 0.5  # Point forward by default
	var vel_end := flight_reticle_pos + Vector2(cos(vel_angle), sin(vel_angle)) * vel_line_len
	var vel_col := Color(0.0, 1.0, 0.5, 0.6) if speed_norm < 0.7 else Color(1.0, 0.6, 0.1, 0.7)
	if vel_line_len > 2.0:
		draw_line(flight_reticle_pos, vel_end, vel_col, maxf(1.0, 2.0 * ui_scale))
		draw_circle(vel_end, 3.0 * ui_scale, vel_col)

	# 8. Dynamic Heat Gauge Arc around Floating Reticle
	var heat_r: float = 24.0 * ui_scale
	var heat_angle_max: float = (exothermal_heat_pct / 100.0) * (PI * 1.5)
	var heat_col := Color(1.0, 0.3, 0.1, 0.85) if exothermal_heat_pct > 75.0 else Color(1.0, 0.8, 0.0, 0.75)
	draw_arc(flight_reticle_pos, heat_r, -PI * 0.75, -PI * 0.75 + heat_angle_max, 24, heat_col, maxf(1.5, 2.5 * ui_scale))

	# 9. 3D Target Locking Reticle / Bracket
	if target_locked:
		var lock_center := _smoothed_target_pos
		var box_s: float = (22.0 + sin(_reticle_pulse_time * 6.0) * 2.0) * ui_scale
		draw_rect(Rect2(lock_center - Vector2(box_s, box_s), Vector2(box_s * 2.0, box_s * 2.0)), lock_color, false, maxf(1.0, 1.5 * ui_scale))

		# Format Distance with realistic astronomical units (m, km, Ls, AU)
		var dist_str := ""
		if target_distance_m < 1000.0:
			dist_str = "%d m" % int(target_distance_m)
		elif target_distance_m < 1000000.0:
			dist_str = "%.1f km" % (target_distance_m / 1000.0)
		elif target_distance_m < 299792458.0:
			dist_str = "%.2f Ls" % (target_distance_m / 299792.458)
		else:
			dist_str = "%.2f AU" % (target_distance_m / 149597870.7)

		var font := get_theme_default_font()
		var txt := "%s [ %s ]" % [target_name if target_name != "" else "LOCKED", dist_str]
		var font_sz := int(maxf(9, 10 * ui_scale))
		draw_string(font, lock_center + Vector2(-45 * ui_scale, box_s + 16 * ui_scale), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, lock_color)
		
		if target_details != "":
			draw_string(font, lock_center + Vector2(-45 * ui_scale, box_s + 28 * ui_scale), target_details, HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(8, 9 * ui_scale)), Color(0.0, 1.0, 0.75, 0.8))

		# 10. Target Lead Indicator Dot & Convergence Vector
		draw_circle(_smoothed_lead_pos, 4.0 * ui_scale, Color(1.0, 0.9, 0.0, 0.9))
		draw_arc(_smoothed_lead_pos, 8.0 * ui_scale, 0, TAU, 16, Color(1.0, 0.9, 0.0, 0.7), 1.2)
		draw_line(lock_center, _smoothed_lead_pos, Color(1.0, 0.9, 0.0, 0.4), 1.0)
		# Line from floating flight reticle to lead pip
		draw_line(flight_reticle_pos, _smoothed_lead_pos, Color(1.0, 0.8, 0.0, 0.25), 1.0)

		# 10a. Enemy Health & Shield Bars above the lock bracket
		_draw_target_health_bar(lock_center, box_s, ui_scale)

	# 10b. Planet Directional Marker — edge arrow + distance readout pointing
	# toward the nearest celestial body so the player can find planets to land on.
	_draw_planet_marker(center, ui_scale)

	# 10c. Threat Assessment Display — hostile count, threat level, incoming fire
	_draw_threat_assessment(ui_scale)

	# 11. Comprehensive Wave Engine & Supercruise HUD Display
	_draw_wave_engine_hud(center, ui_scale)

	# 12. Hit markers — X shape at screen center when projectiles connect
	_draw_hit_markers(center, ui_scale)

	# 13. Damage flash overlay — red vignette when taking damage
	_draw_damage_flash(ui_scale)
	# 13b. Directional hit indicator — edge arrow toward damage source (if known)
	_draw_directional_hit_indicator(center, ui_scale)

	# 14. Overheat warning — red pulsing border when weapons overheated
	if _weapon_overheated:
		_draw_overheat_warning(ui_scale)

	# 15. Combat stats overlay — top-left corner
	_draw_combat_stats(ui_scale)

	# 16. Kill streak display — center-top when streak > 0
	_draw_kill_streak(center, ui_scale)

## Draws the planet directional marker: an on-screen reticle when the planet is
## visible, or an edge arrow pointing toward it when off-screen, plus a
## color-coded distance readout. Color: green (far), yellow (approaching),
## red (descent imminent).
func _draw_planet_marker(center: Vector2, ui_scale: float) -> void:
	if not _planet_marker_active:
		return
	var font := get_theme_default_font()
	var marker_col := _planet_marker_color
	var marker_r: float = 16.0 * ui_scale
	var marker_pos: Vector2 = _smoothed_planet_marker_pos

	if _planet_marker_offscreen:
		# Clamp the indicator to the screen edge and draw an arrow toward the
		# planet. Use a margin so the arrow sits just inside the viewport.
		var margin: float = 40.0 * ui_scale
		var half_size := size * 0.5
		# Direction from screen center to the (off-screen) projected position.
		# When the planet is behind the camera, project its world direction instead.
		var dir: Vector2 = Vector2.ZERO
		if _smoothed_planet_marker_pos != Vector2.ZERO:
			dir = (_smoothed_planet_marker_pos - center).normalized()
		else:
			dir = Vector2(0.0, -1.0) # default up when fully behind camera
		# Intersect the direction ray with the screen-edge rectangle.
		var edge_pos := _edge_intersection(center, dir, half_size, margin)
		marker_pos = edge_pos
		# Draw a triangular arrow pointing along `dir`.
		var arrow_len: float = 14.0 * ui_scale
		var arrow_w: float = 9.0 * ui_scale
		var tip := edge_pos + dir * arrow_len
		var perp := Vector2(-dir.y, dir.x)
		var base_l := edge_pos + perp * arrow_w
		var base_r := edge_pos - perp * arrow_w
		draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), marker_col)
		draw_arc(edge_pos, marker_r * 0.5, 0, TAU, 24, marker_col, maxf(1.0, 1.2 * ui_scale))
	else:
		# On-screen: draw a diamond reticle around the planet position.
		var s: float = marker_r
		draw_colored_polygon(
			PackedVector2Array([
				marker_pos + Vector2(0, -s),
				marker_pos + Vector2(s, 0),
				marker_pos + Vector2(0, s),
				marker_pos + Vector2(-s, 0),
			]),
			Color(marker_col.r, marker_col.g, marker_col.b, 0.25),
		)
		draw_line(marker_pos + Vector2(0, -s), marker_pos + Vector2(s, 0), marker_col, maxf(1.0, 1.5 * ui_scale))
		draw_line(marker_pos + Vector2(s, 0), marker_pos + Vector2(0, s), marker_col, maxf(1.0, 1.5 * ui_scale))
		draw_line(marker_pos + Vector2(0, s), marker_pos + Vector2(-s, 0), marker_col, maxf(1.0, 1.5 * ui_scale))
		draw_line(marker_pos + Vector2(-s, 0), marker_pos + Vector2(0, -s), marker_col, maxf(1.0, 1.5 * ui_scale))

	# Distance readout + planet name below the marker.
	var dist_str := ""
	if _planet_marker_distance_m < 1000.0:
		dist_str = "%d m" % int(_planet_marker_distance_m)
	elif _planet_marker_distance_m < 1000000.0:
		dist_str = "%.1f km" % (_planet_marker_distance_m / 1000.0)
	else:
		dist_str = "%.2f Mm" % (_planet_marker_distance_m / 1000000.0)
	var label_txt := "PLANET: %s [ %s ]" % [_planet_marker_name if _planet_marker_name != "" else "UNKNOWN", dist_str]
	var font_sz := int(maxf(9, 10 * ui_scale))
	draw_string(font, marker_pos + Vector2(-60 * ui_scale, marker_r + 14 * ui_scale), label_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_sz, marker_col)

## Returns the point where the ray from `center` along `dir` intersects the
## screen-edge rectangle (half-extents `half`, inset by `margin`).
func _edge_intersection(center: Vector2, dir: Vector2, half: Vector2, margin: float) -> Vector2:
	if dir == Vector2.ZERO:
		return center
	var half_inset := half - Vector2(margin, margin)
	# Scale factors to reach each edge.
	var sx: float = half_inset.x / absf(dir.x) if absf(dir.x) > 1e-6 else INF
	var sy: float = half_inset.y / absf(dir.y) if absf(dir.y) > 1e-6 else INF
	var s: float = minf(sx, sy)
	return center + dir * s

## Draws the Alcubierre-style Wave Engine Supercruise HUD overlay.
func _draw_wave_engine_hud(center: Vector2, ui_scale: float) -> void:
	var font := get_theme_default_font()

	if wave_state == 1: # CHARGING (Spool-up phase)
		var charge_r := 55.0 * ui_scale
		var charge_col := Color(0.0, 1.0, 0.85, 0.9)

		# Pulsing outer alignment ring
		draw_arc(center, charge_r, 0, TAU, 48, Color(0.0, 0.8, 1.0, 0.3), 2.0 * ui_scale)
		# Sweeping progress arc
		draw_arc(center, charge_r, -PI * 0.5, -PI * 0.5 + wave_charge_progress * TAU, 48, charge_col, 4.0 * ui_scale)

		var remain_sec := maxf(0.0, (1.0 - wave_charge_progress) * 2.0)
		var txt_charge := "WAVE JUMP SPOOL-UP [ %.1fs ]" % remain_sec
		var txt_align := "ALIGNING WARP VECTOR"
		draw_string(font, center + Vector2(-65 * ui_scale, -charge_r - 12 * ui_scale), txt_charge, HORIZONTAL_ALIGNMENT_CENTER, -1, int(12 * ui_scale), charge_col)
		draw_string(font, center + Vector2(-75 * ui_scale, charge_r + 22 * ui_scale), txt_align, HORIZONTAL_ALIGNMENT_CENTER, -1, int(9 * ui_scale), Color(1.0, 0.9, 0.2, 0.85))

	elif wave_state == 2: # ENGAGED (Alcubierre wave-ride cruise phase)
		var _warp_col := Color(0.0, 1.0, 0.9, 0.75)

		# Relativistic Warp Speed Streaks radiating from screen center
		var streak_count := 16
		for i in range(streak_count):
			var ang := (float(i) / float(streak_count)) * TAU + sin(_reticle_pulse_time * 0.5 + float(i)) * 0.2
			var streak_len := (80.0 + fmod(_reticle_pulse_time * 350.0 + float(i * 45), 220.0)) * ui_scale
			var p_start := center + Vector2(cos(ang), sin(ang)) * (streak_len * 0.4)
			var p_end := center + Vector2(cos(ang), sin(ang)) * streak_len
			var str_alpha := clampf((streak_len / (220.0 * ui_scale)), 0.1, 0.8)
			draw_line(p_start, p_end, Color(0.2, 0.9, 1.0, str_alpha * 0.4), maxf(1.0, 1.5 * ui_scale))

		# Central Supercruise HUD Bracket
		var bracket_w := 95.0 * ui_scale
		var bracket_h := 32.0 * ui_scale
		draw_rect(Rect2(center - Vector2(bracket_w, bracket_h), Vector2(bracket_w * 2.0, bracket_h * 2.0)), Color(0.0, 1.0, 0.8, 0.4), false, 1.5 * ui_scale)

		# Banner & Velocity Readout
		var cur_kms := current_speed_ms / 1000.0
		var cur_c := current_speed_ms / 299792458.0
		var txt_banner := "WAVE JUMP ACTIVE"
		var txt_speed := "SPEED: %.1f km/s (%.3f c)" % [cur_kms, cur_c]
		draw_string(font, center + Vector2(-80 * ui_scale, -bracket_h - 10 * ui_scale), txt_banner, HORIZONTAL_ALIGNMENT_CENTER, -1, int(11 * ui_scale), Color(0.0, 1.0, 0.85, 0.95))
		draw_string(font, center + Vector2(-75 * ui_scale, 0), txt_speed, HORIZONTAL_ALIGNMENT_CENTER, -1, int(10 * ui_scale), Color(1.0, 1.0, 1.0, 0.95))

		# Destination Arrival ETA
		if wave_target_name != "" and wave_eta_seconds > 0.0:
			var eta_m := int(wave_eta_seconds / 60.0)
			var eta_s := int(wave_eta_seconds) % 60
			var txt_eta := "%s | ETA: %02d:%02ds" % [wave_target_name, eta_m, eta_s]
			draw_string(font, center + Vector2(-85 * ui_scale, bracket_h + 18 * ui_scale), txt_eta, HORIZONTAL_ALIGNMENT_CENTER, -1, int(10 * ui_scale), Color(1.0, 0.85, 0.2, 0.95))

		# Disengage cue
		draw_string(font, center + Vector2(-70 * ui_scale, bracket_h + 34 * ui_scale), "[ S ] BRAKE TO DROP", HORIZONTAL_ALIGNMENT_CENTER, -1, int(8 * ui_scale), Color(0.8, 0.8, 0.8, 0.6))

	elif wave_state == 0: # READY cue
		var txt_cue := "[ SPACE ] WAVE ENGINE READY"
		draw_string(font, Vector2(center.x - 75 * ui_scale, size.y - 45 * ui_scale), txt_cue, HORIZONTAL_ALIGNMENT_CENTER, -1, int(9 * ui_scale), Color(0.0, 1.0, 0.75, 0.45))

## Draws hit markers — an X at screen center when projectiles connect.
## Color: cyan for shield hit, orange for hull hit, red+larger for kill.
func _draw_hit_markers(center: Vector2, ui_scale: float) -> void:
	if _hit_marker_timer <= 0.0:
		return
	var alpha: float = clampf(_hit_marker_timer, 0.0, 1.0)
	var marker_color: Color
	var marker_size: float = 12.0 * ui_scale
	if _hit_marker_is_kill:
		marker_color = Color(1.0, 0.2, 0.1, alpha)
		marker_size = 18.0 * ui_scale
	elif _hit_marker_is_shield:
		marker_color = Color(0.0, 0.8, 1.0, alpha)
	else:
		marker_color = Color(1.0, 0.7, 0.0, alpha)
	var w: float = maxf(1.5, 2.0 * ui_scale)
	# X shape — four diagonal lines
	draw_line(center - Vector2(marker_size, marker_size), center - Vector2(marker_size * 0.4, marker_size * 0.4), marker_color, w)
	draw_line(center + Vector2(marker_size, marker_size), center + Vector2(marker_size * 0.4, marker_size * 0.4), marker_color, w)
	draw_line(center - Vector2(marker_size, -marker_size), center - Vector2(marker_size * 0.4, -marker_size * 0.4), marker_color, w)
	draw_line(center + Vector2(marker_size, -marker_size), center + Vector2(marker_size * 0.4, -marker_size * 0.4), marker_color, w)
	# Center dot for kill confirmation
	if _hit_marker_is_kill:
		draw_circle(center, 3.0 * ui_scale, marker_color)

## Draws a red vignette overlay when the ship takes damage.
func _draw_damage_flash(ui_scale: float) -> void:
	if _damage_flash_visual <= 0.01:
		return
	var alpha: float = _damage_flash_visual * 0.5
	var edge_width: float = minf(size.x, size.y) * 0.35
	# Red border gradient — thicker at edges, transparent at center
	var col := Color(1.0, 0.05, 0.0, alpha)
	# Top edge
	draw_rect(Rect2(0, 0, size.x, edge_width), col, false, maxf(2.0, 4.0 * ui_scale))
	# Bottom edge
	draw_rect(Rect2(0, size.y - edge_width, size.x, edge_width), col, false, maxf(2.0, 4.0 * ui_scale))
	# Left edge
	draw_rect(Rect2(0, 0, edge_width, size.y), col, false, maxf(2.0, 4.0 * ui_scale))
	# Right edge
	draw_rect(Rect2(size.x - edge_width, 0, edge_width, size.y), col, false, maxf(2.0, 4.0 * ui_scale))

## Draws a pulsing red border warning when weapons are overheated.
func _draw_overheat_warning(ui_scale: float) -> void:
	var pulse: float = 0.5 + sin(_reticle_pulse_time * 8.0) * 0.3
	var col := Color(1.0, 0.2, 0.0, pulse * 0.7)
	var w: float = maxf(3.0, 5.0 * ui_scale)
	draw_rect(Rect2(0, 0, size.x, size.y), col, false, w)
	# Warning text
	var font := get_theme_default_font()
	if font:
		var txt := "WEAPONS OVERHEATED"
		draw_string(font, Vector2(center_of_screen().x - 60 * ui_scale, 50 * ui_scale), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, int(12 * ui_scale), Color(1.0, 0.3, 0.0, pulse))

func center_of_screen() -> Vector2:
	return size * 0.5

## Draws enemy health (and optional shield) bars above the target lock bracket.
## Green > 50%, yellow > 25%, red below. Shield bar (cyan) renders above health
## when the target exposes shield + max_shield with max_shield > 0.
func _draw_target_health_bar(lock_center: Vector2, box_s: float, ui_scale: float) -> void:
	if _current_target_node == null or not is_instance_valid(_current_target_node):
		return
	var t: Object = _current_target_node
	if not ("health" in t) or not ("max_health" in t):
		return
	var max_hp: float = float(t.max_health)
	if max_hp <= 0.0:
		return
	var hp: float = clampf(float(t.health), 0.0, max_hp)
	var hp_pct: float = hp / max_hp

	var bar_w: float = 60.0 * ui_scale
	var bar_h: float = 5.0 * ui_scale
	var bar_x: float = lock_center.x - bar_w * 0.5
	# Stack bars above the lock bracket.
	var shield_h: float = 0.0
	if "shield" in t and "max_shield" in t:
		var max_sh: float = float(t.max_shield)
		if max_sh > 0.0:
			shield_h = bar_h + 2.0 * ui_scale
	var health_y: float = lock_center.y - box_s - 8.0 * ui_scale - bar_h - shield_h

	# Shield bar (drawn above health)
	if shield_h > 0.0:
		var sh: float = clampf(float(t.shield), 0.0, float(t.max_shield))
		var sh_pct: float = sh / float(t.max_shield)
		var shield_y: float = health_y - bar_h - 2.0 * ui_scale
		draw_rect(Rect2(bar_x, shield_y, bar_w, bar_h), Color(0.0, 0.1, 0.15, 0.7), true)
		var shield_col := Color(0.2, 0.7, 1.0, 0.95)
		draw_rect(Rect2(bar_x, shield_y, bar_w * clampf(sh_pct, 0.0, 1.0), bar_h), shield_col, true)
		draw_rect(Rect2(bar_x, shield_y, bar_w, bar_h), Color(0.2, 0.7, 1.0, 0.5), false, maxf(0.5, 1.0 * ui_scale))

	# Health bar
	var hp_col: Color
	if hp_pct > 0.5:
		hp_col = Color(0.2, 1.0, 0.3, 0.95)
	elif hp_pct > 0.25:
		hp_col = Color(1.0, 0.85, 0.2, 0.95)
	else:
		hp_col = Color(1.0, 0.25, 0.2, 0.95)
	draw_rect(Rect2(bar_x, health_y, bar_w, bar_h), Color(0.1, 0.05, 0.05, 0.7), true)
	draw_rect(Rect2(bar_x, health_y, bar_w * clampf(hp_pct, 0.0, 1.0), bar_h), hp_col, true)
	draw_rect(Rect2(bar_x, health_y, bar_w, bar_h), Color(0.6, 0.6, 0.6, 0.4), false, maxf(0.5, 1.0 * ui_scale))

## Draws the threat assessment panel in the top-left area: hostile count,
## color-coded threat level, and a flashing INCOMING warning when an enemy
## projectile is near the player.
func _draw_threat_assessment(ui_scale: float) -> void:
	var font := get_theme_default_font()
	if not font:
		return
	var x: float = 20.0 * ui_scale
	# Place below the existing combat-stats panel (which occupies ~y 56-144).
	var y: float = 150.0 * ui_scale
	var line_h: float = 16.0 * ui_scale
	var font_size: int = int(maxf(9, 10 * ui_scale))

	var panel_w: float = 190.0 * ui_scale
	var panel_h: float = line_h * 2 + 10 * ui_scale
	if _incoming_fire_warning:
		panel_h += line_h
	draw_rect(Rect2(x - 6, y - 4, panel_w, panel_h), Color(0.0, 0.1, 0.05, 0.55), true)
	draw_rect(Rect2(x - 6, y - 4, panel_w, panel_h), Color(0.0, 0.8, 0.6, 0.3), false, maxf(0.5, 1.0 * ui_scale))

	draw_string(font, Vector2(x, y), "HOSTILES: %d" % _hostile_count, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.9, 0.9, 0.9))
	draw_string(font, Vector2(x, y + line_h), "THREAT: %s" % _threat_level, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _threat_color)

	if _incoming_fire_warning:
		# Flashing INCOMING warning — pulse alpha with the reticle timer.
		var pulse: float = 0.5 + sin(_reticle_pulse_time * 12.0) * 0.5
		var inc_col := Color(1.0, 0.15, 0.1, clampf(pulse, 0.2, 1.0))
		draw_string(font, Vector2(x, y + line_h * 2), "INCOMING", HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(10, 11 * ui_scale)), inc_col)

## Draws a directional damage indicator: a red arrow at the screen edge pointing
## toward the source of incoming damage. Only renders while the damage flash is
## active and a damage source position has been reported (via set_damage_source
## or FlightController.last_damage_source_pos).
func _draw_directional_hit_indicator(center: Vector2, ui_scale: float) -> void:
	if _damage_flash_visual <= 0.01:
		return
	if not _has_damage_source:
		return
	var cam: Camera3D = null
	if is_inside_tree() and get_viewport():
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var dir: Vector2 = Vector2.ZERO
	if cam.is_position_behind(_last_damage_source_pos):
		# Source behind the camera — point toward the back-projection of its
		# direction relative to the camera basis.
		var to_src: Vector3 = (_last_damage_source_pos - cam.global_position).normalized()
		var cam_right: Vector3 = cam.global_transform.basis.x
		var cam_up: Vector3 = cam.global_transform.basis.y
		dir = Vector2(to_src.dot(cam_right), to_src.dot(-cam_up)).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0.0, 1.0)
	else:
		var sp: Vector2 = cam.unproject_position(_last_damage_source_pos)
		dir = (sp - center).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0.0, 1.0)

	var margin: float = 36.0 * ui_scale
	var half_size := size * 0.5
	var edge_pos := _edge_intersection(center, dir, half_size, margin)

	var alpha: float = clampf(_damage_flash_visual, 0.0, 1.0)
	var col := Color(1.0, 0.1, 0.05, 0.85 * alpha)
	var arrow_len: float = 18.0 * ui_scale
	var arrow_w: float = 11.0 * ui_scale
	var tip := edge_pos + dir * arrow_len
	var perp := Vector2(-dir.y, dir.x)
	var base_l := edge_pos + perp * arrow_w
	var base_r := edge_pos - perp * arrow_w
	draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), col)
	# Outline for visibility against bright backgrounds.
	draw_line(base_l, base_r, Color(1.0, 0.4, 0.3, alpha), maxf(1.0, 1.2 * ui_scale))
	draw_line(base_l, tip, Color(1.0, 0.4, 0.3, alpha), maxf(1.0, 1.2 * ui_scale))
	draw_line(base_r, tip, Color(1.0, 0.4, 0.3, alpha), maxf(1.0, 1.2 * ui_scale))

## Draws combat statistics in the top-left corner
func _draw_combat_stats(ui_scale: float) -> void:
	var font := get_theme_default_font()
	if not font:
		return
	var x: float = 20.0 * ui_scale
	var y: float = 60.0 * ui_scale
	var line_h: float = 16.0 * ui_scale
	var font_size: int = int(10 * ui_scale)

	# Get stats from CombatStats autoload
	var stats: Dictionary = {}
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("CombatStats"):
		var cs: Object = ml.root.get_node("CombatStats")
		stats = {
			"kills": cs.kills,
			"deaths": cs.deaths,
			"accuracy": cs.get_accuracy(),
			"combat_rating": cs.get_combat_rating(),
			"kill_streak": cs.kill_streak,
			"streak_multiplier": cs.streak_multiplier,
		}

	if stats.is_empty():
		return

	# Background panel
	var panel_w: float = 180.0 * ui_scale
	var panel_h: float = line_h * 5 + 8 * ui_scale
	draw_rect(Rect2(x - 6, y - 4, panel_w, panel_h), Color(0.0, 0.1, 0.05, 0.5), true)

	# Rating color
	var rating: String = stats.get("combat_rating", "F")
	var rating_col: Color = Color(0.5, 0.5, 0.5, 0.9)
	match rating:
		"SSS": rating_col = Color(1.0, 0.2, 0.8, 1.0)
		"S": rating_col = Color(1.0, 0.8, 0.0, 1.0)
		"A": rating_col = Color(0.3, 1.0, 0.3, 1.0)
		"B": rating_col = Color(0.3, 0.8, 1.0, 0.9)
		"C": rating_col = Color(0.8, 0.8, 0.3, 0.9)
		"D": rating_col = Color(0.8, 0.5, 0.3, 0.9)
		"F": rating_col = Color(0.5, 0.5, 0.5, 0.7)

	# Draw stats lines
	draw_string(font, Vector2(x, y), "RATING: %s" % rating, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, rating_col)
	draw_string(font, Vector2(x, y + line_h), "KILLS: %d  DEATHS: %d" % [stats.get("kills", 0), stats.get("deaths", 0)], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.9, 0.7, 0.8))
	draw_string(font, Vector2(x, y + line_h * 2), "ACC: %.1f%%" % stats.get("accuracy", 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.9, 0.7, 0.8))
	if stats.get("kill_streak", 0) > 0:
		draw_string(font, Vector2(x, y + line_h * 3), "STREAK: %d (%.1fx)" % [stats.get("kill_streak", 0), stats.get("streak_multiplier", 1.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.8, 0.2, 0.9))

## Draws kill streak notification in center-top area
func _draw_kill_streak(center: Vector2, ui_scale: float) -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree and ml.root and ml.root.has_node("CombatStats")):
		return
	var cs: Object = ml.root.get_node("CombatStats")
	if cs.kill_streak < 2:
		return
	var font := get_theme_default_font()
	if not font:
		return
	var pulse: float = 0.7 + sin(_reticle_pulse_time * 6.0) * 0.3
	var col := Color(1.0, 0.8, 0.2, pulse)
	if cs.kill_streak >= 10:
		col = Color(1.0, 0.3, 0.1, pulse)
	elif cs.kill_streak >= 5:
		col = Color(1.0, 0.6, 0.0, pulse)
	var txt: String = "%d KILL STREAK (%.1fx)" % [cs.kill_streak, cs.streak_multiplier]
	var font_size: int = int(14 * ui_scale)
	draw_string(font, Vector2(center.x - 80 * ui_scale, 80 * ui_scale), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)
