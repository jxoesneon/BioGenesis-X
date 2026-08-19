# res://scripts/PlanetHUDUI.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# PlanetHUDUI.gd - Planet Surface / Atmospheric Descent HUD (Frutiger Aero Glass)
# ==============================================================================
# CanvasLayer overlay rendered during planetary descent, surface exploration,
# and underwater submersible operations. Builds its entire UI tree
# programmatically in _ready() (no .tscn dependency).
#
# FEATURE PANELS:
#   1. Altitude display (color-coded green/yellow/red)
#   2. Atmosphere layer indicator (EXOSPHERE/THERMOSPHERE/TROPOSPHERE/SURFACE)
#   3. Descent status panel (progress 0% orbit -> 100% surface, state, velocity,
#      heating warning, stall warning)
#   4. Landing prompt (gear ready, alignment progress, descent rate, auto-land)
#   5. Surface mode HUD (ON_FOOT: planet name, time of day, temperature, gravity,
#      oxygen indicator, stamina bar, compass, enter-ship prompt)
#   6. Underwater HUD (depth, water layer, pressure bar, oxygen countdown,
#      bioluminescence indicator)
#   7. Weather indicator (type + intensity bar)
#   8. Circular top-down minimap (100m radius, ship position, north indicator)
#
# SIGNALS CONSUMED:
#   PlanetDescentController.descent_state_changed / layer_transition
#   FlightController.heating_intensity_changed / stall_warning
#   PlanetCharacterController.stamina_changed
#   OceanSystem.layer_changed
#   PlanetSurfaceManager.time_of_day_changed / weather_changed
# ==============================================================================
class_name PlanetHUDUI
extends CanvasLayer

# ------------------------------------------------------------------------------
# Constants - Frutiger Aero glass palette
# ------------------------------------------------------------------------------
const _COLOR_GLASS_BG: Color = Color(0.78, 0.94, 1.0, 0.32)
const _COLOR_GLASS_BORDER: Color = Color(1.0, 1.0, 1.0, 0.55)
const _COLOR_GLASS_HIGHLIGHT: Color = Color(1.0, 1.0, 1.0, 0.75)
const _COLOR_TEXT: Color = Color(0.04, 0.18, 0.22, 0.95)
const _COLOR_ACCENT: Color = Color(0.0, 0.62, 0.86, 1.0)
const _COLOR_SAFE: Color = Color(0.10, 0.78, 0.32, 1.0)
const _COLOR_CAUTION: Color = Color(1.0, 0.78, 0.10, 1.0)
const _COLOR_DANGER: Color = Color(1.0, 0.22, 0.16, 1.0)
const _COLOR_BIO: Color = Color(0.45, 1.0, 0.75, 1.0)

const _PANEL_CORNER_RADIUS: int = 14
const _MINIMAP_RADIUS_M: float = 100.0
const _OXYGEN_CAPACITY_S: float = 300.0
const _PRESSURE_WARN_BAR: float = 50.0
const _FADE_DURATION: float = 0.35

# Descent state names (mirrors PlanetDescentController.DescentState order)
const _STATE_NAMES: PackedStringArray = [
	"ORBITAL", "EXOSPHERE ENTRY", "THERMOSPHERE", "TROPOSPHERE",
	"SURFACE APPROACH", "LANDED", "ON FOOT", "SUBMERSIBLE",
	"ABORT ASCENT", "GAS GIANT DESCENT",
]

# Atmosphere layer names (mirrors PlanetDescentController.AtmosphereLayer order)
const _LAYER_NAMES: PackedStringArray = [
	"SPACE", "EXOSPHERE", "THERMOSPHERE", "TROPOSPHERE",
	"SURFACE", "UNDERWATER", "GAS GIANT DEEP",
]

# Ocean layer names (mirrors OceanSystem.OceanLayer order)
const _OCEAN_LAYER_NAMES: PackedStringArray = [
	"SURFACE", "SHALLOW", "MID", "DEEP", "ABYSS",
]

# Weather type names (mirrors PlanetSurfaceManager.WeatherType order)
const _WEATHER_NAMES: PackedStringArray = [
	"CLEAR", "RAIN", "SNOW", "DUST", "ASH", "SPORES",
]

# ------------------------------------------------------------------------------
# HUD mode (drives panel group visibility)
# ------------------------------------------------------------------------------
enum HUDMode {
	HIDDEN,    ## No planet target - HUD idle
	DESCENT,   ## In atmosphere / landing approach
	SURFACE,   ## On foot on the planet surface
	UNDERWATER ## Submersible / diving
}

# ------------------------------------------------------------------------------
# Controller references (resolved lazily)
# ------------------------------------------------------------------------------
var _descent_controller: Node = null
var _flight_controller: Node = null
var _character_controller: Node = null
var _ocean_system: Node = null
var _surface_manager: Node = null
var _aero_model: AtmosphericFlightModel = null

# Signal connection tracking (avoid duplicate connects on re-resolve)
var _connected_flight: bool = false
var _connected_character: bool = false
var _connected_ocean: bool = false
var _connected_surface: bool = false

# ------------------------------------------------------------------------------
# Cached telemetry state (updated from controllers / signals)
# ------------------------------------------------------------------------------
var _altitude_m: float = 0.0
var _vertical_speed_ms: float = 0.0
var _descent_progress: float = 0.0
var _current_state: int = 0
var _current_layer: int = 0
var _layer_name: String = "SPACE"
var _heating_intensity: float = 0.0
var _stall_factor: float = 0.0
var _stamina: float = 100.0
var _max_stamina: float = 100.0
var _ocean_layer: int = 0
var _pressure_bar: float = 0.0
var _time_of_day: float = 0.3
var _weather_type: int = 0
var _weather_intensity: float = 0.0
var _oxygen_seconds: float = _OXYGEN_CAPACITY_S
var _planet_name: String = "UNKNOWN"
var _gravity_g: float = 1.0
var _has_oxygen: bool = true
var _surface_temp_c: float = 15.0
var _heading_rad: float = 0.0
var _bioluminescence: bool = false

var _current_mode: int = HUDMode.HIDDEN
var _mode_tween: Tween = null

# ------------------------------------------------------------------------------
# UI node references - root
# ------------------------------------------------------------------------------
var _root_control: Control = null

# Descent group
var _descent_group: Control = null
var _lbl_altitude: Label = null
var _lbl_layer: Label = null
var _bar_descent: ProgressBar = null
var _lbl_descent_state: Label = null
var _lbl_descent_velocity: Label = null
var _lbl_heating: Label = null
var _lbl_stall: Label = null
var _bar_heating: ProgressBar = null

# Landing prompt
var _landing_panel: PanelContainer = null
var _lbl_landing_gear: Label = null
var _bar_alignment: ProgressBar = null
var _lbl_descent_rate: Label = null
var _lbl_autoland: Label = null

# Surface group
var _surface_group: Control = null
var _lbl_planet_name: Label = null
var _lbl_time_of_day: Label = null
var _lbl_temperature: Label = null
var _lbl_gravity: Label = null
var _lbl_oxygen: Label = null
var _bar_stamina: ProgressBar = null
var _lbl_compass: Label = null
var _lbl_enter_ship: Label = null

# Underwater group
var _underwater_group: Control = null
var _lbl_depth: Label = null
var _lbl_water_layer: Label = null
var _lbl_pressure: Label = null
var _bar_pressure: ProgressBar = null
var _lbl_oxygen_countdown: Label = null
var _lbl_bioluminescence: Label = null

# Weather panel (shared, always visible when target present)
var _weather_panel: PanelContainer = null
var _lbl_weather_type: Label = null
var _bar_weather_intensity: ProgressBar = null

# Minimap
var _minimap: Control = null

# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	layer = 12
	_aero_model = AtmosphericFlightModel.new()
	_build_ui_layout()
	_resolve_autoloads()
	_resolve_scene_controllers()
	set_process(true)

func _process(delta: float) -> void:
	_resolve_scene_controllers()
	_poll_telemetry()
	_update_oxygen_countdown(delta)
	_update_mode_visibility()
	_update_ui_labels()
	if _minimap:
		_minimap.queue_redraw()

func _exit_tree() -> void:
	_disconnect_all()

# ------------------------------------------------------------------------------
# Controller resolution & signal wiring
# ------------------------------------------------------------------------------

func _resolve_autoloads() -> void:
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("PlanetDescentController"):
		_descent_controller = tree.root.get_node("PlanetDescentController")
		if _descent_controller and not _descent_controller.is_connected("descent_state_changed", Callable(self, "_on_descent_state_changed")):
			_descent_controller.connect("descent_state_changed", Callable(self, "_on_descent_state_changed"))
		if _descent_controller and not _descent_controller.is_connected("layer_transition", Callable(self, "_on_layer_transition")):
			_descent_controller.connect("layer_transition", Callable(self, "_on_layer_transition"))

func _resolve_scene_controllers() -> void:
	if not _flight_controller or not is_instance_valid(_flight_controller):
		_flight_controller = _find_first_of_class("FlightController")
		if _flight_controller and not _connected_flight:
			_try_connect(_flight_controller, "heating_intensity_changed", Callable(self, "_on_heating_intensity_changed"))
			_try_connect(_flight_controller, "stall_warning", Callable(self, "_on_stall_warning"))
			_connected_flight = true

	if not _character_controller or not is_instance_valid(_character_controller):
		_character_controller = _find_first_of_class("PlanetCharacterController")
		if _character_controller and not _connected_character:
			_try_connect(_character_controller, "stamina_changed", Callable(self, "_on_stamina_changed"))
			_connected_character = true

	if not _ocean_system or not is_instance_valid(_ocean_system):
		_ocean_system = _find_first_of_class("OceanSystem")
		if _ocean_system and not _connected_ocean:
			_try_connect(_ocean_system, "layer_changed", Callable(self, "_on_ocean_layer_changed"))
			_connected_ocean = true

	if not _surface_manager or not is_instance_valid(_surface_manager):
		_surface_manager = _find_first_of_class("PlanetSurfaceManager")
		if _surface_manager and not _connected_surface:
			_try_connect(_surface_manager, "time_of_day_changed", Callable(self, "_on_time_of_day_changed"))
			_try_connect(_surface_manager, "weather_changed", Callable(self, "_on_weather_changed"))
			_connected_surface = true

func _find_first_of_class(cls_name: String) -> Node:
	var tree := get_tree()
	if not tree:
		return null
	var scene := tree.current_scene
	if scene:
		var found := scene.find_children("*", cls_name, true, false)
		if found and found.size() > 0:
			return found[0]
	# Fallback: search the root viewport children (autoloads + scene)
	if tree.root:
		for child in tree.root.get_children():
			if child.is_class(cls_name) or (child.get_script() and child.get_script().get_global_name() == cls_name):
				return child
			var found := child.find_children("*", cls_name, true, false)
			if found and found.size() > 0:
				return found[0]
	return null

func _try_connect(node: Node, sig_name: String, callable: Callable) -> void:
	if node and node.has_signal(sig_name) and not node.is_connected(sig_name, callable):
		node.connect(sig_name, callable)

func _disconnect_all() -> void:
	if _descent_controller and is_instance_valid(_descent_controller):
		_disconnect_safe(_descent_controller, "descent_state_changed", Callable(self, "_on_descent_state_changed"))
		_disconnect_safe(_descent_controller, "layer_transition", Callable(self, "_on_layer_transition"))
	if _flight_controller and is_instance_valid(_flight_controller):
		_disconnect_safe(_flight_controller, "heating_intensity_changed", Callable(self, "_on_heating_intensity_changed"))
		_disconnect_safe(_flight_controller, "stall_warning", Callable(self, "_on_stall_warning"))
	if _character_controller and is_instance_valid(_character_controller):
		_disconnect_safe(_character_controller, "stamina_changed", Callable(self, "_on_stamina_changed"))
	if _ocean_system and is_instance_valid(_ocean_system):
		_disconnect_safe(_ocean_system, "layer_changed", Callable(self, "_on_ocean_layer_changed"))
	if _surface_manager and is_instance_valid(_surface_manager):
		_disconnect_safe(_surface_manager, "time_of_day_changed", Callable(self, "_on_time_of_day_changed"))
		_disconnect_safe(_surface_manager, "weather_changed", Callable(self, "_on_weather_changed"))

func _disconnect_safe(node: Node, sig_name: String, callable: Callable) -> void:
	if node.is_connected(sig_name, callable):
		node.disconnect(sig_name, callable)

# ==============================================================================
# Signal handlers
# ==============================================================================

func _on_descent_state_changed(_old_state: int, new_state: int) -> void:
	_current_state = new_state

func _on_layer_transition(new_layer: int, layer_name: String) -> void:
	_current_layer = new_layer
	_layer_name = layer_name

func _on_heating_intensity_changed(intensity: float) -> void:
	_heating_intensity = intensity

func _on_stall_warning(stall_factor: float) -> void:
	_stall_factor = stall_factor

func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	_stamina = stamina
	_max_stamina = max_stamina

func _on_ocean_layer_changed(_old_layer: int, new_layer: int) -> void:
	_ocean_layer = new_layer

func _on_time_of_day_changed(time_normalized: float) -> void:
	_time_of_day = time_normalized

func _on_weather_changed(type: int, intensity: float) -> void:
	_weather_type = type
	_weather_intensity = intensity

# ==============================================================================
# Telemetry polling
# ==============================================================================

func _poll_telemetry() -> void:
	if _descent_controller and is_instance_valid(_descent_controller):
		_altitude_m = float(_descent_controller.get_altitude_m())
		_vertical_speed_ms = float(_descent_controller.get_vertical_speed_ms())
		_descent_progress = float(_descent_controller.get_descent_progress())
		_current_state = int(_descent_controller.get_current_state())
		_current_layer = int(_descent_controller.get_current_layer())
		if _current_layer >= 0 and _current_layer < _LAYER_NAMES.size():
			_layer_name = _LAYER_NAMES[_current_layer]
		_poll_planet_profile()
	else:
		_altitude_m = 0.0
		_vertical_speed_ms = 0.0
		_descent_progress = 0.0

	if _flight_controller and is_instance_valid(_flight_controller):
		_heating_intensity = float(_flight_controller.get_current_heating_intensity())
		_stall_factor = float(_flight_controller.get_current_stall_factor())

	if _ocean_system and is_instance_valid(_ocean_system):
		_ocean_layer = int(_ocean_system.get_current_layer())
		_pressure_bar = float(_ocean_system.get_pressure_bar())
		_bioluminescence = _ocean_layer >= 3 or _is_radiotrophic()
	else:
		_pressure_bar = 0.0

	if _surface_manager and is_instance_valid(_surface_manager):
		_time_of_day = float(_surface_manager.get_time_of_day())
		_weather_type = int(_surface_manager.get_weather_type())
		_weather_intensity = float(_surface_manager.get("weather_intensity"))

	if _character_controller and is_instance_valid(_character_controller):
		_stamina = float(_character_controller.get_stamina())
		_max_stamina = float(_character_controller.get("max_stamina"))

	_poll_heading()

func _poll_planet_profile() -> void:
	var planet: Node3D = _descent_controller.get_target_planet()
	if planet and is_instance_valid(planet) and "planet_name" in planet:
		var pname: Variant = planet.get("planet_name")
		if pname is String:
			_planet_name = pname
	elif not planet:
		_planet_name = "UNKNOWN"

	var archetype: int = int(_descent_controller.get_target_archetype())
	if _aero_model:
		var params: Dictionary = _aero_model.get_archetype_parameters(archetype)
		_has_oxygen = bool(params.get("has_oxygen", false))
		var temp_k: float = float(params.get("surface_temp_k", 288.0))
		_surface_temp_c = temp_k - 273.15

	# Gravity lives on the descent controller's internal profile.
	var profile: Object = _descent_controller.get("_profile")
	if profile and "surface_gravity_g" in profile:
		_gravity_g = float(profile.get("surface_gravity_g"))
	else:
		_gravity_g = 1.0

func _is_radiotrophic() -> bool:
	if not _descent_controller:
		return false
	return int(_descent_controller.get_target_archetype()) == 7 # RADIOTROPHIC_BIO

func _poll_heading() -> void:
	var cam: Camera3D = null
	if is_inside_tree() and get_viewport():
		cam = get_viewport().get_camera_3d()
	if not cam:
		_heading_rad = 0.0
		return
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		_heading_rad = 0.0
		return
	fwd = fwd.normalized()
	# North = -Z world; heading measured clockwise (east = +X).
	_heading_rad = atan2(fwd.x, -fwd.z)

# ------------------------------------------------------------------------------
# Oxygen countdown (underwater synthetic life-support timer)
# ------------------------------------------------------------------------------

func _update_oxygen_countdown(delta: float) -> void:
	var underwater: bool = false
	if _descent_controller and is_instance_valid(_descent_controller):
		underwater = bool(_descent_controller.is_underwater())
	if underwater:
		# Drain accelerates with pressure (1 bar => ~1x, 50 bar => ~6x).
		var drain_mult: float = 1.0 + clampf(_pressure_bar * 0.1, 0.0, 5.0)
		_oxygen_seconds = maxf(0.0, _oxygen_seconds - delta * drain_mult)
	else:
		_oxygen_seconds = _OXYGEN_CAPACITY_S

# ==============================================================================
# Mode management (smooth Frutiger Aero cross-fades)
# ==============================================================================

func _update_mode_visibility() -> void:
	var target_mode: int = _compute_mode()
	_weather_panel.visible = target_mode != HUDMode.HIDDEN
	if target_mode == _current_mode:
		return
	_current_mode = target_mode
	if _mode_tween and _mode_tween.is_valid():
		_mode_tween.kill()
	_mode_tween = create_tween()
	_fade_group(_descent_group, target_mode == HUDMode.DESCENT, _mode_tween)
	_fade_group(_surface_group, target_mode == HUDMode.SURFACE, _mode_tween)
	_fade_group(_underwater_group, target_mode == HUDMode.UNDERWATER, _mode_tween)
	_fade_group(_landing_panel, _is_landing_prompt_visible(target_mode), _mode_tween)

func _compute_mode() -> int:
	if not _descent_controller or not is_instance_valid(_descent_controller):
		return HUDMode.HIDDEN
	if not bool(_descent_controller.has_target_planet()):
		return HUDMode.HIDDEN
	var state: int = int(_descent_controller.get_current_state())
	# PlanetDescentController.DescentState.ON_FOOT = 6, SUBMERSIBLE = 7
	if state == 6:
		return HUDMode.SURFACE
	if state == 7:
		return HUDMode.UNDERWATER
	# LANDED (5) shows the descent/landing panels so the player can take off.
	return HUDMode.DESCENT

func _is_landing_prompt_visible(mode: int) -> bool:
	if mode != HUDMode.DESCENT:
		return false
	if not _descent_controller:
		return false
	var state: int = int(_descent_controller.get_current_state())
	# SURFACE_APPROACH = 4, LANDED = 5
	return state == 4 or state == 5

func _fade_group(group: Control, visible_target: bool, tween: Tween) -> void:
	if not group:
		return
	var target_alpha: float = 1.0 if visible_target else 0.0
	if visible_target:
		group.visible = true
		group.modulate.a = 0.0
	tween.parallel().tween_property(group, "modulate:a", target_alpha, _FADE_DURATION)
	if not visible_target:
		# Hide after fade completes.
		tween.chain().tween_callback(Callable(group, "set_visible").bind(false))
	else:
		tween.chain().tween_callback(Callable(group, "set_visible").bind(true))

# ==============================================================================
# UI label / bar updates
# ==============================================================================

func _update_ui_labels() -> void:
	# Altitude (color-coded)
	if _lbl_altitude:
		_lbl_altitude.text = "ALTITUDE: %d m" % int(_altitude_m)
		_lbl_altitude.add_theme_color_override("font_color", _altitude_color(_altitude_m))

	# Atmosphere layer
	if _lbl_layer:
		_lbl_layer.text = "LAYER: %s" % _layer_name

	# Descent status
	if _bar_descent:
		_bar_descent.value = clampf(_descent_progress * 100.0, 0.0, 100.0)
	if _lbl_descent_state:
		var sname: String = "—"
		if _current_state >= 0 and _current_state < _STATE_NAMES.size():
			sname = _STATE_NAMES[_current_state]
		_lbl_descent_state.text = "STATE: %s" % sname
	if _lbl_descent_velocity:
		var total_speed: float = 0.0
		if _flight_controller and is_instance_valid(_flight_controller):
			total_speed = float((_flight_controller.get("linear_velocity_vector") as Vector3).length())
		_lbl_descent_velocity.text = "V: %d m/s  |  V/S: %.1f m/s" % [int(total_speed), _vertical_speed_ms]

	# Heating
	if _lbl_heating and _bar_heating:
		var pct: float = clampf(_heating_intensity * 100.0, 0.0, 100.0)
		_lbl_heating.text = "HEATING: %d%%" % int(pct)
		var hcol: Color = _COLOR_DANGER if _heating_intensity > 0.6 else (_COLOR_CAUTION if _heating_intensity > 0.3 else _COLOR_SAFE)
		_lbl_heating.add_theme_color_override("font_color", hcol)
		_bar_heating.value = pct

	# Stall
	if _lbl_stall:
		if _stall_factor > 0.1:
			_lbl_stall.text = "⚠ STALL WARNING"
			_lbl_stall.add_theme_color_override("font_color", _COLOR_DANGER)
			_lbl_stall.visible = true
		else:
			_lbl_stall.visible = false

	# Landing prompt
	if _lbl_landing_gear and _bar_alignment and _lbl_descent_rate and _lbl_autoland:
		var gear_ready: bool = false
		var align_progress: float = 0.0
		if _descent_controller and is_instance_valid(_descent_controller):
			gear_ready = bool(_descent_controller.is_landing_assist_active()) or _altitude_m < 120.0
			var surface_normal: Vector3 = Vector3.UP
			var sn: Variant = _descent_controller.get_surface_normal()
			if sn is Vector3:
				surface_normal = sn
			var ship_up: Vector3 = Vector3.UP
			if _flight_controller and is_instance_valid(_flight_controller) and _flight_controller is Node3D:
				ship_up = (_flight_controller as Node3D).global_transform.basis.y
			var dot: float = clampf(ship_up.dot(surface_normal), -1.0, 1.0)
			align_progress = clampf((dot + 1.0) * 0.5, 0.0, 1.0)
		_lbl_landing_gear.text = "LANDING GEAR %s" % ("READY" if gear_ready else "STOWED")
		_lbl_landing_gear.add_theme_color_override("font_color", _COLOR_SAFE if gear_ready else _COLOR_CAUTION)
		_bar_alignment.value = align_progress * 100.0
		_lbl_descent_rate.text = "DESCENT RATE: %.1f m/s" % _vertical_speed_ms
		_lbl_descent_rate.add_theme_color_override("font_color", _COLOR_DANGER if _vertical_speed_ms < -8.0 else _COLOR_TEXT)
		_lbl_autoland.text = "Press F to auto-land"

	# Surface HUD
	if _lbl_planet_name:
		_lbl_planet_name.text = "PLANET: %s" % _planet_name
	if _lbl_time_of_day:
		_lbl_time_of_day.text = "TIME: %s" % _format_time_of_day(_time_of_day)
	if _lbl_temperature:
		_lbl_temperature.text = "TEMP: %d°C" % int(_surface_temp_c)
	if _lbl_gravity:
		_lbl_gravity.text = "GRAVITY: %.2f G" % _gravity_g
	if _lbl_oxygen:
		if _has_oxygen:
			_lbl_oxygen.text = "OXYGEN: BREATHABLE"
			_lbl_oxygen.add_theme_color_override("font_color", _COLOR_SAFE)
		else:
			_lbl_oxygen.text = "OXYGEN: NONE — SUIT REQUIRED"
			_lbl_oxygen.add_theme_color_override("font_color", _COLOR_DANGER)
	if _bar_stamina:
		var max_s: float = maxf(1.0, _max_stamina)
		_bar_stamina.value = clampf((_stamina / max_s) * 100.0, 0.0, 100.0)
	if _lbl_compass:
		_lbl_compass.text = "HEADING: %s (%d°)" % [_compass_cardinal(_heading_rad), int(rad_to_deg(_heading_rad)) % 360]
	if _lbl_enter_ship:
		_lbl_enter_ship.text = "Press F to enter ship"

	# Underwater HUD
	if _lbl_depth:
		var depth: float = 0.0
		if _descent_controller and is_instance_valid(_descent_controller):
			depth = float(_descent_controller.get_underwater_depth_m())
		_lbl_depth.text = "DEPTH: %d m" % int(depth)
	if _lbl_water_layer:
		var lname: String = "—"
		if _ocean_layer >= 0 and _ocean_layer < _OCEAN_LAYER_NAMES.size():
			lname = _OCEAN_LAYER_NAMES[_ocean_layer]
		_lbl_water_layer.text = "WATER LAYER: %s" % lname
	if _lbl_pressure and _bar_pressure:
		_lbl_pressure.text = "PRESSURE: %.1f bar" % _pressure_bar
		var pcol: Color = _COLOR_DANGER if _pressure_bar > _PRESSURE_WARN_BAR else _COLOR_SAFE
		_lbl_pressure.add_theme_color_override("font_color", pcol)
		_bar_pressure.value = clampf(_pressure_bar, 0.0, 100.0)
	if _lbl_oxygen_countdown:
		_lbl_oxygen_countdown.text = "OXYGEN: %s" % _format_oxygen_countdown(_oxygen_seconds)
		var ocol: Color = _COLOR_DANGER if _oxygen_seconds < 60.0 else (_COLOR_CAUTION if _oxygen_seconds < 120.0 else _COLOR_SAFE)
		_lbl_oxygen_countdown.add_theme_color_override("font_color", ocol)
	if _lbl_bioluminescence:
		if _bioluminescence:
			_lbl_bioluminescence.text = "✦ BIOLUMINESCENCE DETECTED"
			_lbl_bioluminescence.add_theme_color_override("font_color", _COLOR_BIO)
			_lbl_bioluminescence.visible = true
		else:
			_lbl_bioluminescence.visible = false

	# Weather
	if _lbl_weather_type and _bar_weather_intensity:
		var wname: String = "CLEAR"
		if _weather_type >= 0 and _weather_type < _WEATHER_NAMES.size():
			wname = _WEATHER_NAMES[_weather_type]
		_lbl_weather_type.text = "WEATHER: %s" % wname
		_bar_weather_intensity.value = clampf(_weather_intensity * 100.0, 0.0, 100.0)

	# Minimap data feed
	if _minimap:
		_minimap.set("heading_rad", _heading_rad)
		_minimap.set("mode", _current_mode)

# ------------------------------------------------------------------------------
# Formatting helpers
# ------------------------------------------------------------------------------

func _altitude_color(alt: float) -> Color:
	if alt > 1000.0:
		return _COLOR_SAFE
	if alt > 200.0:
		return _COLOR_CAUTION
	return _COLOR_DANGER

func _format_time_of_day(t_norm: float) -> String:
	var total_min: int = int(t_norm * 24.0 * 60.0)
	var hh: int = int(total_min / 60.0)
	var mm: int = total_min % 60
	return "%02d:%02d" % [hh, mm]

func _format_oxygen_countdown(seconds: float) -> String:
	var s: int = int(seconds)
	return "%02d:%02d" % [int(s / 60.0), s % 60]

func _compass_cardinal(rad: float) -> String:
	var deg: int = int(round(rad_to_deg(rad))) % 360
	if deg < 0:
		deg += 360
	var cards: PackedStringArray = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx: int = int(round(float(deg) / 45.0)) % 8
	return cards[idx]

# ==============================================================================
# UI Layout Construction (Frutiger Aero glass panels)
# ==============================================================================

func _build_ui_layout() -> void:
	_root_control = Control.new()
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root_control)

	# --- Descent group (top-left: altitude + layer; top-center: status) ---
	_descent_group = Control.new()
	_descent_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_descent_group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_descent_group.modulate.a = 0.0
	_descent_group.visible = false
	_root_control.add_child(_descent_group)

	# Altitude + layer panel (top-left)
	var alt_panel: PanelContainer = _create_glass_panel()
	alt_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	alt_panel.offset_left = 20
	alt_panel.offset_top = 20
	alt_panel.offset_right = 280
	alt_panel.offset_bottom = 96
	alt_panel.custom_minimum_size = Vector2(260, 70)
	_descent_group.add_child(alt_panel)
	var alt_vb := VBoxContainer.new()
	alt_vb.add_theme_constant_override("separation", 4)
	alt_panel.add_child(alt_vb)
	_lbl_altitude = _create_glass_label("ALTITUDE: 0 m", _COLOR_TEXT, 18)
	alt_vb.add_child(_lbl_altitude)
	_lbl_layer = _create_glass_label("LAYER: SPACE", _COLOR_ACCENT, 13)
	alt_vb.add_child(_lbl_layer)

	# Descent status panel (top-center)
	var status_panel: PanelContainer = _create_glass_panel()
	status_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_panel.offset_left = -200
	status_panel.offset_top = 20
	status_panel.offset_right = 200
	status_panel.offset_bottom = 178
	status_panel.custom_minimum_size = Vector2(400, 150)
	_descent_group.add_child(status_panel)
	var status_vb := VBoxContainer.new()
	status_vb.add_theme_constant_override("separation", 5)
	status_panel.add_child(status_vb)
	var lbl_status_title := _create_glass_label("DESCENT STATUS", _COLOR_ACCENT, 12)
	status_vb.add_child(lbl_status_title)
	_bar_descent = ProgressBar.new()
	_bar_descent.custom_minimum_size = Vector2(380, 16)
	_bar_descent.value = 0.0
	_bar_descent.show_percentage = true
	status_vb.add_child(_bar_descent)
	_lbl_descent_state = _create_glass_label("STATE: ORBITAL", _COLOR_TEXT, 13)
	status_vb.add_child(_lbl_descent_state)
	_lbl_descent_velocity = _create_glass_label("V: 0 m/s  |  V/S: 0.0 m/s", _COLOR_TEXT, 13)
	status_vb.add_child(_lbl_descent_velocity)
	var heat_hb := HBoxContainer.new()
	heat_hb.add_theme_constant_override("separation", 8)
	status_vb.add_child(heat_hb)
	_lbl_heating = _create_glass_label("HEATING: 0%", _COLOR_SAFE, 13)
	heat_hb.add_child(_lbl_heating)
	_bar_heating = ProgressBar.new()
	_bar_heating.custom_minimum_size = Vector2(140, 14)
	_bar_heating.value = 0.0
	_bar_heating.show_percentage = false
	heat_hb.add_child(_bar_heating)
	_lbl_stall = _create_glass_label("⚠ STALL WARNING", _COLOR_DANGER, 13)
	_lbl_stall.visible = false
	status_vb.add_child(_lbl_stall)

	# Landing prompt (bottom-center, within descent group)
	_landing_panel = _create_glass_panel()
	_landing_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_landing_panel.offset_left = -180
	_landing_panel.offset_top = -150
	_landing_panel.offset_right = 180
	_landing_panel.offset_bottom = -24
	_landing_panel.custom_minimum_size = Vector2(360, 120)
	_landing_panel.modulate.a = 0.0
	_landing_panel.visible = false
	_descent_group.add_child(_landing_panel)
	var land_vb := VBoxContainer.new()
	land_vb.add_theme_constant_override("separation", 5)
	_landing_panel.add_child(land_vb)
	_lbl_landing_gear = _create_glass_label("LANDING GEAR STOWED", _COLOR_CAUTION, 15)
	land_vb.add_child(_lbl_landing_gear)
	var align_hdr := _create_glass_label("ALIGNMENT", _COLOR_ACCENT, 11)
	land_vb.add_child(align_hdr)
	_bar_alignment = ProgressBar.new()
	_bar_alignment.custom_minimum_size = Vector2(340, 14)
	_bar_alignment.value = 0.0
	_bar_alignment.show_percentage = true
	land_vb.add_child(_bar_alignment)
	_lbl_descent_rate = _create_glass_label("DESCENT RATE: 0.0 m/s", _COLOR_TEXT, 13)
	land_vb.add_child(_lbl_descent_rate)
	_lbl_autoland = _create_glass_label("Press F to auto-land", _COLOR_ACCENT, 13)
	land_vb.add_child(_lbl_autoland)

	# --- Surface group (left side) ---
	_surface_group = Control.new()
	_surface_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface_group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface_group.modulate.a = 0.0
	_surface_group.visible = false
	_root_control.add_child(_surface_group)

	var surface_panel: PanelContainer = _create_glass_panel()
	surface_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	surface_panel.offset_left = 20
	surface_panel.offset_top = 20
	surface_panel.offset_right = 300
	surface_panel.offset_bottom = 320
	surface_panel.custom_minimum_size = Vector2(280, 290)
	_surface_group.add_child(surface_panel)
	var surf_vb := VBoxContainer.new()
	surf_vb.add_theme_constant_override("separation", 6)
	surface_panel.add_child(surf_vb)
	var surf_title := _create_glass_label("SURFACE EXPLORATION", _COLOR_ACCENT, 12)
	surf_vb.add_child(surf_title)
	_lbl_planet_name = _create_glass_label("PLANET: UNKNOWN", _COLOR_TEXT, 15)
	surf_vb.add_child(_lbl_planet_name)
	_lbl_time_of_day = _create_glass_label("TIME: 00:00", _COLOR_TEXT, 13)
	surf_vb.add_child(_lbl_time_of_day)
	_lbl_temperature = _create_glass_label("TEMP: 15°C", _COLOR_TEXT, 13)
	surf_vb.add_child(_lbl_temperature)
	_lbl_gravity = _create_glass_label("GRAVITY: 1.00 G", _COLOR_TEXT, 13)
	surf_vb.add_child(_lbl_gravity)
	_lbl_oxygen = _create_glass_label("OXYGEN: BREATHABLE", _COLOR_SAFE, 13)
	surf_vb.add_child(_lbl_oxygen)
	var stam_hdr := _create_glass_label("STAMINA", _COLOR_ACCENT, 11)
	surf_vb.add_child(stam_hdr)
	_bar_stamina = ProgressBar.new()
	_bar_stamina.custom_minimum_size = Vector2(260, 14)
	_bar_stamina.value = 100.0
	_bar_stamina.show_percentage = true
	surf_vb.add_child(_bar_stamina)
	_lbl_compass = _create_glass_label("HEADING: N (0°)", _COLOR_TEXT, 13)
	surf_vb.add_child(_lbl_compass)
	_lbl_enter_ship = _create_glass_label("Press F to enter ship", _COLOR_ACCENT, 13)
	surf_vb.add_child(_lbl_enter_ship)

	# --- Underwater group (left side) ---
	_underwater_group = Control.new()
	_underwater_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underwater_group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_underwater_group.modulate.a = 0.0
	_underwater_group.visible = false
	_root_control.add_child(_underwater_group)

	var under_panel: PanelContainer = _create_glass_panel()
	under_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	under_panel.offset_left = 20
	under_panel.offset_top = 20
	under_panel.offset_right = 300
	under_panel.offset_bottom = 300
	under_panel.custom_minimum_size = Vector2(280, 270)
	_underwater_group.add_child(under_panel)
	var under_vb := VBoxContainer.new()
	under_vb.add_theme_constant_override("separation", 6)
	under_panel.add_child(under_vb)
	var under_title := _create_glass_label("SUBMERSIBLE DIVE", _COLOR_ACCENT, 12)
	under_vb.add_child(under_title)
	_lbl_depth = _create_glass_label("DEPTH: 0 m", _COLOR_TEXT, 15)
	under_vb.add_child(_lbl_depth)
	_lbl_water_layer = _create_glass_label("WATER LAYER: SURFACE", _COLOR_TEXT, 13)
	under_vb.add_child(_lbl_water_layer)
	_lbl_pressure = _create_glass_label("PRESSURE: 0.0 bar", _COLOR_SAFE, 13)
	under_vb.add_child(_lbl_pressure)
	_bar_pressure = ProgressBar.new()
	_bar_pressure.custom_minimum_size = Vector2(260, 14)
	_bar_pressure.value = 0.0
	_bar_pressure.show_percentage = false
	under_vb.add_child(_bar_pressure)
	_lbl_oxygen_countdown = _create_glass_label("OXYGEN: 05:00", _COLOR_SAFE, 14)
	under_vb.add_child(_lbl_oxygen_countdown)
	_lbl_bioluminescence = _create_glass_label("✦ BIOLUMINESCENCE DETECTED", _COLOR_BIO, 13)
	_lbl_bioluminescence.visible = false
	under_vb.add_child(_lbl_bioluminescence)

	# --- Weather panel (top-right, below minimap) ---
	_weather_panel = _create_glass_panel()
	_weather_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_weather_panel.offset_left = -200
	_weather_panel.offset_top = 200
	_weather_panel.offset_right = -20
	_weather_panel.offset_bottom = 270
	_weather_panel.custom_minimum_size = Vector2(180, 64)
	_weather_panel.visible = false
	_root_control.add_child(_weather_panel)
	var weather_vb := VBoxContainer.new()
	weather_vb.add_theme_constant_override("separation", 4)
	_weather_panel.add_child(weather_vb)
	_lbl_weather_type = _create_glass_label("WEATHER: CLEAR", _COLOR_TEXT, 13)
	weather_vb.add_child(_lbl_weather_type)
	_bar_weather_intensity = ProgressBar.new()
	_bar_weather_intensity.custom_minimum_size = Vector2(160, 12)
	_bar_weather_intensity.value = 0.0
	_bar_weather_intensity.show_percentage = false
	weather_vb.add_child(_bar_weather_intensity)

	# --- Minimap (top-right) ---
	_minimap = MinimapView.new()
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.offset_left = -180
	_minimap.offset_top = 20
	_minimap.offset_right = -20
	_minimap.offset_bottom = 180
	_minimap.custom_minimum_size = Vector2(160, 160)
	_root_control.add_child(_minimap)

# ------------------------------------------------------------------------------
# Glass panel / label factories
# ------------------------------------------------------------------------------

func _create_glass_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = _COLOR_GLASS_BG
	style.border_color = _COLOR_GLASS_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(_PANEL_CORNER_RADIUS)
	style.set_expand_margin_all(6)
	# Frutiger Aero top highlight (thicker bright top border)
	style.border_width_top = 2
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _create_glass_label(text: String, font_color: Color, size_override: int = 13) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_font_size_override("font_size", size_override)
	return lbl

# ==============================================================================
# Inner class: circular top-down minimap (100m radius, north-up)
# ==============================================================================

class MinimapView extends Control:
	var heading_rad: float = 0.0
	var mode: int = 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sz: Vector2 = size
		if sz.x < 10.0 or sz.y < 10.0:
			return
		var center: Vector2 = sz * 0.5
		var radius: float = minf(sz.x, sz.y) * 0.46
		# Glass backdrop disc
		draw_circle(center, radius + 2.0, Color(0.78, 0.94, 1.0, 0.18))
		# Outer ring
		draw_arc(center, radius, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.7), 2.0)
		# Range rings (25/50/75/100 m)
		for i in range(1, 4):
			var rr: float = radius * (float(i) / 4.0)
			draw_arc(center, rr, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.18), 1.0)
		# Cardinal ticks + labels (north-up)
		var cardinals: PackedStringArray = ["N", "E", "S", "W"]
		var font := get_theme_default_font()
		for i in range(4):
			var ang: float = float(i) * (TAU * 0.25) - (TAU * 0.25) # N at top
			var dir := Vector2(sin(ang), -cos(ang))
			var tick_in := center + dir * (radius - 6.0)
			var tick_out := center + dir * (radius + 6.0)
			draw_line(tick_in, tick_out, Color(0.0, 0.62, 0.86, 0.9), 2.0)
			var lbl_pos := center + dir * (radius + 16.0) - Vector2(5, 6)
			var col := Color(1.0, 0.22, 0.16, 1.0) if i == 0 else Color(0.04, 0.18, 0.22, 0.95)
			draw_string(font, lbl_pos, cardinals[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 11, col)
		# Crosshair
		draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(1, 1, 1, 0.08), 1.0)
		draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(1, 1, 1, 0.08), 1.0)
		# Player / ship marker at center pointing in heading direction
		var hdir := Vector2(sin(heading_rad), -cos(heading_rad))
		var tip := center + hdir * 12.0
		var left := center + Vector2(sin(heading_rad + 2.5), -cos(heading_rad + 2.5)) * 8.0
		var right := center + Vector2(sin(heading_rad - 2.5), -cos(heading_rad - 2.5)) * 8.0
		var pts: PackedVector2Array = PackedVector2Array([tip, left, right])
		draw_colored_polygon(pts, Color(0.0, 0.62, 0.86, 1.0))
		draw_circle(center, 3.0, Color(1.0, 1.0, 1.0, 0.95))
		# Radius label
		draw_string(font, center + Vector2(-radius + 4, radius - 4), "100m", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.04, 0.18, 0.22, 0.7))
