extends Node
## SettingsSystem — Persistent game settings autoload (AAA+ pattern).
##
## Stores user preferences in user://settings.json, separate from save_game.json.
## All settings have defaults that are applied on first boot and merged with
## any saved values on subsequent boots. Settings are organized into sections:
##   - audio: master_volume, music_volume, sfx_volume, ui_volume, reverb_send
##   - graphics: fullscreen, vsync, msaa, shadow_quality, render_scale
##   - gameplay: poi_scan_radius_ly, hud_opacity, auto_aim_assist, camera_sensitivity
##   - controls: invert_y, mouse_sensitivity, flight_damping
##
## Usage:
##   SettingsSystem.get_setting("audio", "master_volume", 0.8)
##   SettingsSystem.set_setting("audio", "master_volume", 0.5)
##   SettingsSystem.save_settings()

const SETTINGS_FILE_PATH = "user://settings.json"

# --- Default settings schema ---
const DEFAULTS: Dictionary = {
	"audio": {
		"master_volume": 0.8,        # 0.0 - 1.0
		"music_volume": 0.6,         # 0.0 - 1.0
		"sfx_volume": 0.85,          # 0.0 - 1.0
		"ui_volume": 0.7,            # 0.0 - 1.0
		"reverb_send": 0.3,          # 0.0 - 1.0 (global reverb amount)
		"subtitles_enabled": true,   # bool (caption toggle for voice/comms)
		"subtitle_bg_opacity": 0.7,  # 0.0 - 1.0
		"audio_device": "default",   # String (audio output device name)
	},
	"graphics": {
		"fullscreen": true,          # bool
		"vsync": true,               # bool (DisplayServer.VSyncMode)
		"msaa": 2,                   # 0=Disabled, 2=2x, 4=4x, 8=8x (Viewport.MSAA enum)
		"fxaa": true,                # bool (screen-space AA)
		"shadow_quality": 2,         # 0=Off, 1=Low, 2=Medium, 3=High, 4=Ultra
		"render_scale": 1.0,         # 0.5 - 1.5 (resolution scale multiplier)
		"max_fps": 0,                # 0=unlimited, else target FPS
		"quality_preset": 4,         # 0=Custom, 1=Low, 2=Medium, 3=High, 4=Ultra
		"texture_quality": 3,        # 0=Low, 1=Medium, 2=High, 3=Ultra
		"anisotropic_filter": 8,     # 0, 1, 2, 4, 8, 16
		"volumetric_fog": 2,         # 0=Off, 1=Low, 2=Medium, 3=High
		"reflection_quality": 2,     # 0=Off, 1=Low, 2=Medium, 3=High
		"occlusion_culling": true,   # bool
		"lod_bias": 1.0,             # 0.5 - 2.0 (multiplier for LOD distances)
		"motion_blur": false,        # bool
		"depth_of_field": false,     # bool
		"bloom_intensity": 0.6,      # 0.0 - 2.0
		"chromatic_aberration": 0.0, # 0.0 - 1.0
		"film_grain": 0.0,           # 0.0 - 1.0
		"vignette": 0.3,             # 0.0 - 1.0
		"fov": 75.0,                 # 60.0 - 110.0 (degrees)
	},
	"gameplay": {
		"poi_scan_radius_ly": 80.0,  # 10.0 - 500.0 (light-years for nearby system POI scan)
		"poi_max_indicators": 50,    # 0 - 200 (max POI markers to show, 0=unlimited)
		"hud_opacity": 1.0,          # 0.3 - 1.0
		"auto_aim_assist": 0.3,      # 0.0 - 1.0 (0=off, 1=full lock-on)
		"camera_sensitivity": 1.0,   # 0.1 - 3.0 (multiplier)
		"flight_damping": 0.15,      # 0.0 - 1.0 (inertia damping for controls)
		"show_debug_overlay": false, # bool (F3 collision debug default)
		"difficulty": 1,             # 0=Casual, 1=Normal, 2=Veteran, 3=Hardcore
		"minimap_enabled": true,     # bool
		"damage_numbers": true,      # bool
		"crosshair_style": 0,        # 0=Default, 1=Minimal, 2=Cross, 3=Circle
		# --- Noise Map / Scanner Settings ---
		"noise_overlay_opacity": 0.6,     # 0.1 - 1.0 (debug overlay plane opacity)
		"noise_show_resources": true,     # bool (debug overlay channel visibility)
		"noise_show_enemies": true,       # bool
		"noise_show_anomalies": true,     # bool
		"noise_show_hazards": true,       # bool
		"scanner_range_km": 5.0,          # 1.0 - 50.0 (in-game scanner radius in km)
		"scanner_opacity": 0.7,           # 0.1 - 1.0 (scanner hologram opacity)
	},
	"controls": {
		"invert_y": false,           # bool
		"mouse_sensitivity": 0.003,  # 0.001 - 0.01
		"flight_damping": 0.15,      # 0.0 - 1.0 (same as gameplay, kept for controls panel)
		"controller_enabled": true,  # bool
		"controller_deadzone": 0.2,  # 0.0 - 1.0
		"vibration_enabled": true,   # bool
		"vibration_intensity": 0.7,  # 0.0 - 1.0
	},
	"accessibility": {
		"color_blind_mode": 0,       # 0=None, 1=Protanopia, 2=Deuteranopia, 3=Tritanopia
		"ui_scale": 1.0,             # 0.75 - 1.5
		"text_size": 1.0,            # 0.8 - 1.4
		"high_contrast": false,      # bool
		"reduce_motion": false,      # bool (disables screen shake, camera shake)
		"screen_shake_intensity": 1.0, # 0.0 - 1.0
	},
}

var _settings: Dictionary = {}
var _loaded: bool = false

# --- Signals ---
signal setting_changed(section: String, key: String, value: Variant)
signal settings_loaded()

func _ready() -> void:
	load_settings()
	_apply_all_settings()

func load_settings() -> void:
	_settings = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(SETTINGS_FILE_PATH):
		var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
		if file:
			var content := file.get_as_text()
			var json := JSON.new()
			var err := json.parse(content)
			if err == OK and json.data is Dictionary:
				_merge_settings(_settings, json.data)
				print("[SettingsSystem] Loaded settings from ", SETTINGS_FILE_PATH)
			else:
				print("[SettingsSystem] Failed to parse settings file, using defaults")
			file.close()
	else:
		print("[SettingsSystem] No settings file found, using defaults")
	_loaded = true
	settings_loaded.emit()

func _merge_settings(target: Dictionary, source: Dictionary) -> void:
	for section in source:
		if target.has(section) and target[section] is Dictionary and source[section] is Dictionary:
			for key in source[section]:
				target[section][key] = source[section][key]
		else:
			target[section] = source[section]

func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_settings, "\t"))
		file.close()
		print("[SettingsSystem] Settings saved to ", SETTINGS_FILE_PATH)
	else:
		push_error("[SettingsSystem] Failed to save settings to " + SETTINGS_FILE_PATH)

func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	if _settings.has(section) and _settings[section].is_empty() == false and _settings[section].has(key):
		return _settings[section][key]
	if default != null:
		return default
	# Fall back to DEFAULTS
	if DEFAULTS.has(section) and DEFAULTS[section].has(key):
		return DEFAULTS[section][key]
	return null

func set_setting(section: String, key: String, value: Variant) -> void:
	if not _settings.has(section):
		_settings[section] = {}
	_settings[section][key] = value
	setting_changed.emit(section, key, value)
	_apply_setting(section, key, value)
	save_settings()

func reset_to_defaults() -> void:
	_settings = DEFAULTS.duplicate(true)
	save_settings()
	_apply_all_settings()
	print("[SettingsSystem] Settings reset to defaults")

func reset_section(section: String) -> void:
	if DEFAULTS.has(section):
		_settings[section] = DEFAULTS[section].duplicate(true)
		save_settings()
		_apply_section(section)
		print("[SettingsSystem] Reset section: ", section)

func get_all_settings() -> Dictionary:
	return _settings.duplicate(true)

func is_loaded() -> bool:
	return _loaded

# --- Apply settings to engine systems ---
func _apply_all_settings() -> void:
	for section in _settings:
		_apply_section(section)

func _apply_section(section: String) -> void:
	if not _settings.has(section):
		return
	for key in _settings[section]:
		_apply_setting(section, key, _settings[section][key])

func _apply_setting(section: String, key: String, value: Variant) -> void:
	match section:
		"audio":
			_apply_audio_setting(key, value)
		"graphics":
			_apply_graphics_setting(key, value)
		"gameplay":
			_apply_gameplay_setting(key, value)
		"controls":
			_apply_controls_setting(key, value)
		"accessibility":
			_apply_accessibility_setting(key, value)

func _apply_audio_setting(key: String, value: Variant) -> void:
	match key:
		"master_volume":
			_set_bus_volume("Master", float(value))
		"music_volume":
			_set_bus_volume("Music", float(value))
		"sfx_volume":
			# SFX_Player and SFX_World both controlled by this setting
			_set_bus_volume("SFX_Player", float(value))
			_set_bus_volume("SFX_World", float(value))
		"ui_volume":
			# UI sounds route through Telemetry_Voice bus
			_set_bus_volume("Telemetry_Voice", float(value))
		"reverb_send":
			# Global reverb send amount — applied to Reverb_Space and Reverb_Cockpit
			var reverb_db := linear_to_db(clampf(float(value), 0.0, 1.0)) if float(value) > 0.001 else -80.0
			_set_bus_volume_raw("Reverb_Space", reverb_db)
			_set_bus_volume_raw("Reverb_Cockpit", reverb_db)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clampf(linear, 0.0, 1.0)))

func _set_bus_volume_raw(bus_name: String, db: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db)

func _apply_graphics_setting(key: String, value: Variant) -> void:
	match key:
		"fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value) else DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(mode)
		"vsync":
			var vsync_mode := DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(vsync_mode)
		"msaa":
			var msaa_val := int(value)
			var viewport := get_viewport()
			if viewport:
				match msaa_val:
					0: viewport.msaa_3d = Viewport.MSAA_DISABLED
					2: viewport.msaa_3d = Viewport.MSAA_2X
					4: viewport.msaa_3d = Viewport.MSAA_4X
					8: viewport.msaa_3d = Viewport.MSAA_8X
					_: viewport.msaa_3d = Viewport.MSAA_DISABLED
		"fxaa":
			var viewport := get_viewport()
			if viewport:
				viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(value) else Viewport.SCREEN_SPACE_AA_DISABLED
		"shadow_quality":
			var sq := int(value)
			var shadow_atlas_size := 2048
			match sq:
				0: shadow_atlas_size = 0
				1: shadow_atlas_size = 512
				2: shadow_atlas_size = 1024
				3: shadow_atlas_size = 2048
				4: shadow_atlas_size = 4096
			RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size, sq >= 3)
			RenderingServer.viewport_set_positional_shadow_atlas_size(get_viewport().get_viewport_rid(), shadow_atlas_size)
		"render_scale":
			var rs := clampf(float(value), 0.5, 1.5)
			var viewport := get_viewport()
			if viewport:
				viewport.scaling_3d_scale = rs
		"max_fps":
			var fps := int(value)
			Engine.max_fps = fps if fps > 0 else 0
		"texture_quality":
			_apply_texture_quality(int(value))
		"anisotropic_filter":
			# Anisotropic filter level is read by material systems at runtime
			pass
		"volumetric_fog":
			_apply_volumetric_fog(int(value))
		"reflection_quality":
			_apply_reflection_quality(int(value))
		"occlusion_culling":
			var viewport := get_viewport()
			if viewport:
				viewport.use_occlusion_culling = bool(value)
		"lod_bias":
			# LOD bias is read by mesh instances at runtime; store for systems to query
			pass
		"motion_blur":
			_apply_world_environment("motion_blur_enabled", bool(value))
		"depth_of_field":
			_apply_world_environment("dof_blur_far_enabled", bool(value))
		"bloom_intensity":
			_apply_world_environment("glow_intensity", float(value))
		"chromatic_aberration":
			_apply_world_environment("chromatic_aberration", float(value))
		"film_grain":
			_apply_world_environment("film_grain", float(value))
		"vignette":
			_apply_world_environment("vignette_intensity", float(value))
		"fov":
			_apply_fov(float(value))
		"quality_preset":
			_apply_quality_preset(int(value))

func _apply_gameplay_setting(key: String, value: Variant) -> void:
	# Most gameplay settings are read by game systems at runtime via get_setting().
	# Noise map settings are applied live to the debug overlay and scanner HUD.
	match key:
		"noise_overlay_opacity":
			_apply_noise_overlay_opacity(float(value))
		"noise_show_resources", "noise_show_enemies", "noise_show_anomalies", "noise_show_hazards":
			_apply_noise_channel_visibility()
		"scanner_range_km":
			_apply_scanner_range(float(value))
		"scanner_opacity":
			_apply_scanner_opacity(float(value))

func _get_noise_overlay() -> Node:
	var tree := get_tree()
	if tree and tree.root:
		return tree.root.get_node_or_null("SpaceFlight/NoiseMapDebugOverlay")
	return null

func _get_scanner_hud() -> Node:
	var tree := get_tree()
	if tree and tree.root:
		return tree.root.get_node_or_null("SpaceFlight/ScannerHUD")
	return null

func _apply_noise_overlay_opacity(opacity: float) -> void:
	var overlay := _get_noise_overlay()
	if overlay and overlay.has_method("set_overlay_opacity"):
		overlay.set_overlay_opacity(opacity)

func _apply_noise_channel_visibility() -> void:
	var overlay := _get_noise_overlay()
	if overlay and overlay.has_method("set_channel_visible"):
		overlay.set_channel_visible(0, bool(get_setting("gameplay", "noise_show_resources", true)))
		overlay.set_channel_visible(1, bool(get_setting("gameplay", "noise_show_enemies", true)))
		overlay.set_channel_visible(2, bool(get_setting("gameplay", "noise_show_anomalies", true)))
		overlay.set_channel_visible(3, bool(get_setting("gameplay", "noise_show_hazards", true)))

func _apply_scanner_range(range_km: float) -> void:
	var scanner := _get_scanner_hud()
	if scanner and scanner.has_method("set_scan_range"):
		scanner.set_scan_range(range_km * 1000.0)  # Convert km to meters

func _apply_scanner_opacity(opacity: float) -> void:
	var scanner := _get_scanner_hud()
	if scanner and scanner.has_method("set_opacity"):
		scanner.set_opacity(opacity)

func _apply_controls_setting(_key: String, _value: Variant) -> void:
	# Controls settings are read by FlightController at runtime
	pass

func _apply_accessibility_setting(_key: String, _value: Variant) -> void:
	# Accessibility settings are read by UI/HUD systems at runtime via get_setting().
	# Color-blind mode and high-contrast are applied to UI themes on next rebuild.
	pass

# --- Graphics helper functions ---

func _get_world_environment() -> Environment:
	var tree := get_tree()
	if tree and tree.root:
		var env_node := tree.root.get_node_or_null("SpaceFlight/WorldEnvironment")
		if env_node and env_node is WorldEnvironment:
			return env_node.environment
	return null

func _apply_world_environment(property: String, value: Variant) -> void:
	var env := _get_world_environment()
	if env and property in env:
		env.set(property, value)

func _apply_fov(fov: float) -> void:
	var tree := get_tree()
	if tree and tree.root:
		var cam := tree.root.get_node_or_null("SpaceFlight/FlightCamera3D")
		if cam and cam is Camera3D:
			cam.fov = clampf(fov, 60.0, 110.0)

func _apply_texture_quality(_quality: int) -> void:
	# 0=Low (256 max), 1=Medium (512), 2=High (1024), 3=Ultra (2048)
	# Texture quality is read by streaming systems at runtime via get_setting()
	pass

func _apply_volumetric_fog(quality: int) -> void:
	# 0=Off, 1=Low, 2=Medium, 3=High
	var env := _get_world_environment()
	if not env:
		return
	match quality:
		0:
			env.volumetric_fog_enabled = false
		_:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_length = 32.0 + float(quality) * 16.0
			env.volumetric_fog_density = 0.05 + float(quality) * 0.02

func _apply_reflection_quality(quality: int) -> void:
	# 0=Off, 1=Low, 2=Medium, 3=High
	var env := _get_world_environment()
	if not env:
		return
	match quality:
		0:
			env.ssr_enabled = false
		_:
			env.ssr_enabled = true
			env.ssr_max_steps = 64 * quality

# --- Quality Presets ---

const QUALITY_PRESETS: Dictionary = {
	1: {  # Low
		"msaa": 0, "fxaa": false, "shadow_quality": 1, "render_scale": 0.75,
		"texture_quality": 0, "anisotropic_filter": 1, "volumetric_fog": 0,
		"reflection_quality": 0, "occlusion_culling": true, "bloom_intensity": 0.3,
		"motion_blur": false, "depth_of_field": false,
	},
	2: {  # Medium
		"msaa": 0, "fxaa": true, "shadow_quality": 2, "render_scale": 0.85,
		"texture_quality": 1, "anisotropic_filter": 2, "volumetric_fog": 1,
		"reflection_quality": 1, "occlusion_culling": true, "bloom_intensity": 0.5,
		"motion_blur": false, "depth_of_field": false,
	},
	3: {  # High
		"msaa": 2, "fxaa": true, "shadow_quality": 3, "render_scale": 1.0,
		"texture_quality": 2, "anisotropic_filter": 4, "volumetric_fog": 2,
		"reflection_quality": 2, "occlusion_culling": true, "bloom_intensity": 0.6,
		"motion_blur": false, "depth_of_field": false,
	},
	4: {  # Ultra
		"msaa": 4, "fxaa": true, "shadow_quality": 4, "render_scale": 1.0,
		"texture_quality": 3, "anisotropic_filter": 8, "volumetric_fog": 3,
		"reflection_quality": 3, "occlusion_culling": true, "bloom_intensity": 0.8,
		"motion_blur": true, "depth_of_field": false,
	},
}

func _apply_quality_preset(preset: int) -> void:
	if preset == 0:  # Custom — don't change anything
		return
	if not QUALITY_PRESETS.has(preset):
		return
	var settings: Dictionary = QUALITY_PRESETS[preset]
	for key in settings:
		var value: Variant = settings[key]
		_settings["graphics"][key] = value
		_apply_graphics_setting(key, value)
	setting_changed.emit("graphics", "quality_preset", preset)
	save_settings()

func apply_hardware_recommended_preset() -> void:
	# Called by HardwareDetector on boot to set the recommended preset
	var hw: Node = get_node_or_null("/root/HardwareDetector")
	if hw and "quality_tier" in hw:
		var tier: int = int(hw.quality_tier)  # 0=LOW, 1=MEDIUM, 2=HIGH, 3=ULTRA
		# Map hardware tier to preset: LOW→1, MEDIUM→2, HIGH→3, ULTRA→4
		var preset := tier + 1
		_apply_quality_preset(preset)
		print("[SettingsSystem] Applied hardware-recommended preset: %d" % preset)
