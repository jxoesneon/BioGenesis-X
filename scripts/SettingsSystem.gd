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
##   - localization: language (ISO 639-1 code, e.g. "en", "es")
##
## Localization is wired through LocGuard Lite (in-editor checker) at authoring
## time and the standard Godot TranslationServer at runtime. Translation files
## live in res://translations/ and are registered in project.godot.
##
## Usage:
##   SettingsSystem.get_setting("audio", "master_volume", 0.8)
##   SettingsSystem.set_setting("audio", "master_volume", 0.5)
##   SettingsSystem.save_settings()
##   SettingsSystem.set_language("es")  # switches TranslationServer locale

const SETTINGS_FILE_PATH = "user://settings.json"
const TRANSLATIONS_DIR := "res://translations"
## Supported language codes mapped to human-readable display names.
const SUPPORTED_LANGUAGES: Dictionary = {
	"en": "English",
	"es": "Español",
}

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
		# POI scan radius: 80 LY covers ~2 sectors (40 LY each). This is the
		# Void-Fauna's multispectral eye pod detection range (LORE.md) — the
		# ganglion core can detect stellar radiation signatures from nearby
		# star systems. 80 LY balances usefulness (enough POIs to plan routes)
		# with performance (scanning more systems is expensive).
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
		# These settings control the ship's sensor display — the Void-Fauna's
		# Multispectral Eye Pods (LORE.md) detect infrared, polarized starlight,
		# and planetary EM fluctuations. The noise overlay renders this sensor
		# data as a holographic projection around the ship.
		"noise_overlay_opacity": 0.6,     # 0.1 - 1.0 (debug overlay plane opacity)
		"noise_show_resources": true,     # bool (debug overlay channel visibility)
		"noise_show_enemies": true,       # bool
		"noise_show_anomalies": true,     # bool
		"noise_show_hazards": true,       # bool
		# Scanner range: 5 km is the tactical engagement range — far enough to
		# detect asteroids and enemies before collision, close enough that the
		# scanner feels like a short-range tactical tool, not an omniscient map.
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
	"localization": {
		"language": "en",            # ISO 639-1 code (en, es, ...). Default resolved at boot.
	},
}

var _settings: Dictionary = {}
var _loaded: bool = false
# Resolved at boot from OS.get_locale(); used as the default for the
# "localization/language" setting since DEFAULTS is a const and cannot be
# mutated at runtime.
var _language_default: String = "en"

# --- Signals ---
signal setting_changed(section: String, key: String, value: Variant)
signal settings_loaded()
signal language_changed(code: String)

func _ready() -> void:
	_resolve_default_language()
	load_settings()
	_load_translations()
	_apply_all_settings()

## Resolve the default language from the OS locale on first boot. The stored
## value in DEFAULTS is a placeholder; we replace it with the OS language if it
## is one of our supported languages, otherwise fall back to "en".
func _resolve_default_language() -> void:
	var os_locale := OS.get_locale()
	var os_lang := os_locale.split("_")[0]
	if SUPPORTED_LANGUAGES.has(os_lang):
		_language_default = os_lang
	else:
		_language_default = "en"

## Load all .translation resources from res://translations/ into the
## TranslationServer. This is a runtime fallback that guarantees translations
## are available even when the project.godot registration hasn't been processed
## (e.g. fresh clones before the first editor import). project.godot also
## registers them, and duplicate adds are harmless.
func _load_translations() -> void:
	var dir := DirAccess.open(TRANSLATIONS_DIR)
	if dir == null:
		print("[SettingsSystem] No translations directory found at ", TRANSLATIONS_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "translation":
			var res_path := TRANSLATIONS_DIR + "/" + file_name
			var translation: Translation = load(res_path) as Translation
			if translation:
				TranslationServer.add_translation(translation)
				print("[SettingsSystem] Loaded translation: ", res_path)
			else:
				push_warning("[SettingsSystem] Failed to load translation: " + res_path)
		file_name = dir.get_next()

func load_settings() -> void:
	_settings = DEFAULTS.duplicate(true)
	# Apply the boot-resolved default language (OS locale) before merging saved
	# values so a first-boot user gets their OS language instead of the const "en".
	_settings["localization"]["language"] = _language_default
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
		# localization/language default is resolved at boot from the OS locale
		if section == "localization" and key == "language":
			return _language_default
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
		"localization":
			_apply_localization_setting(key, value)

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
			_apply_anisotropic_filter(int(value))
		"volumetric_fog":
			_apply_volumetric_fog(int(value))
		"reflection_quality":
			_apply_reflection_quality(int(value))
		"occlusion_culling":
			var viewport := get_viewport()
			if viewport:
				viewport.use_occlusion_culling = bool(value)
		"lod_bias":
			_apply_lod_bias(float(value))
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

func _apply_controls_setting(key: String, value: Variant) -> void:
	# Controls settings are applied live to FlightController when present.
	var tree := get_tree()
	if not tree or not tree.root:
		return
	var fc := tree.root.find_child("FlightController", true, false) as Node
	if not fc or not is_instance_valid(fc):
		return  # FlightController not in scene — value stored for later query
	match key:
		"invert_y":
			if "invert_y" in fc:
				fc.set("invert_y", bool(value))
		"mouse_sensitivity":
			if "mouse_sensitivity" in fc:
				fc.set("mouse_sensitivity", clampf(float(value), 0.0005, 0.02))
		"flight_damping":
			if "linear_dampening_rate" in fc:
				fc.set("linear_dampening_rate", clampf(float(value), 0.0, 1.0))
			if "angular_dampening_rate" in fc:
				fc.set("angular_dampening_rate", clampf(float(value), 0.0, 1.0))
		"controller_deadzone":
			if "controller_deadzone" in fc:
				fc.set("controller_deadzone", clampf(float(value), 0.0, 0.5))
		_:
			pass  # controller_enabled, vibration_* handled by input system at runtime

func _apply_accessibility_setting(key: String, value: Variant) -> void:
	# Accessibility settings are applied to UI themes and the scene tree.
	var tree := get_tree()
	if not tree or not tree.root:
		return
	match key:
		"color_blind_mode":
			_apply_color_blind_mode(int(value))
		"ui_scale":
			_apply_ui_scale(float(value))
		"text_size":
			_apply_text_size(float(value))
		"high_contrast":
			_apply_high_contrast(bool(value))
		"reduce_motion":
			_apply_reduce_motion(bool(value))
		"screen_shake_intensity":
			_apply_screen_shake_intensity(float(value))

# --- Localization ---

func _apply_localization_setting(key: String, value: Variant) -> void:
	match key:
		"language":
			_apply_language(String(value))

func _apply_language(code: String) -> void:
	var lang := code.strip_edges()
	if lang.is_empty():
		lang = _language_default
	if not SUPPORTED_LANGUAGES.has(lang):
		push_warning("[SettingsSystem] Unsupported language code '%s', falling back to 'en'" % lang)
		lang = "en"
	TranslationServer.set_locale(lang)
	print("[SettingsSystem] Locale set to: ", lang)
	language_changed.emit(lang)

## Set the active language. Persists immediately and applies to TranslationServer.
func set_language(code: String) -> void:
	set_setting("localization", "language", code)

## Get the active language code (e.g. "en", "es").
func get_language() -> String:
	return String(get_setting("localization", "language", "en"))

## Get the list of supported language codes in stable order.
func get_supported_languages() -> Array:
	return SUPPORTED_LANGUAGES.keys()

## Get a human-readable display name for a language code.
func get_language_display_name(code: String) -> String:
	return String(SUPPORTED_LANGUAGES.get(code, code))

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

func _apply_texture_quality(quality: int) -> void:
	# 0=Low (256 max), 1=Medium (512), 2=High (1024), 3=Ultra (2048)
	# Apply LOD bias as a proxy for texture quality — higher tiers keep
	# detailed LODs (which use higher-res textures) visible at greater distance.
	var max_res: int = 256
	match quality:
		0: max_res = 256
		1: max_res = 512
		2: max_res = 1024
		3: max_res = 2048
	# Apply to all MeshInstance3D nodes — adjust LOD bias based on quality tier
	var tree := get_tree()
	if tree and tree.root:
		_apply_texture_quality_recursive(tree.root, max_res)

func _apply_texture_quality_recursive(node: Node, max_res: int) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# Adjust mesh LOD bias based on texture quality tier
		# Higher quality = more detailed LODs visible at distance
		var lod_bias: float = 0.5 + float(max_res) / 2048.0 * 1.0
		mi.lod_bias = clampf(lod_bias, 0.5, 2.0)
	for child in node.get_children():
		_apply_texture_quality_recursive(child, max_res)

func _apply_anisotropic_filter(level: int) -> void:
	# 0=None, 1=2x, 2=4x, 3=8x, 4=16x
	# Apply via RenderingServer global anisotropic filter level
	var aniso_level: int = 0
	match level:
		0: aniso_level = 0
		1: aniso_level = 2
		2: aniso_level = 4
		3: aniso_level = 8
		4: aniso_level = 16
	# Apply to all StandardMaterial3D instances in the scene
	var tree := get_tree()
	if tree and tree.root:
		_apply_anisotropic_recursive(tree.root, aniso_level)

func _apply_anisotropic_recursive(node: Node, aniso_level: int) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for mat_idx in range(mi.get_surface_override_material_count()):
			var mat := mi.get_surface_override_material(mat_idx)
			if mat and mat is StandardMaterial3D:
				(mat as StandardMaterial3D).texture_filter = \
					BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if aniso_level > 0 \
					else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in node.get_children():
		_apply_anisotropic_recursive(child, aniso_level)

func _apply_lod_bias(bias: float) -> void:
	# Apply LOD bias multiplier to all MeshInstance3D nodes in the scene.
	# Higher bias = more detailed LODs at distance (sharper but heavier).
	var clamped := clampf(bias, 0.5, 2.0)
	var tree := get_tree()
	if tree and tree.root:
		_apply_lod_bias_recursive(tree.root, clamped)

func _apply_lod_bias_recursive(node: Node, bias: float) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).lod_bias = bias
	for child in node.get_children():
		_apply_lod_bias_recursive(child, bias)

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

# --- Accessibility helper functions ---

func _apply_color_blind_mode(mode: int) -> void:
	# 0=None, 1=Protanopia, 2=Deuteranopia, 3=Tritanopia
	# Apply a color correction via the WorldEnvironment if present.
	var env := _get_world_environment()
	if env:
		env.adjustment_enabled = mode != 0
		match mode:
			1: # Protanopia — shift reds toward yellow
				env.adjustment_saturation = 1.15
				env.adjustment_color_correction = _make_correction_texture(Color(1.0, 0.9, 0.8, 1.0))
			2: # Deuteranopia — shift greens toward red
				env.adjustment_saturation = 1.15
				env.adjustment_color_correction = _make_correction_texture(Color(0.9, 0.95, 1.0, 1.0))
			3: # Tritanopia — shift blues toward green
				env.adjustment_saturation = 1.15
				env.adjustment_color_correction = _make_correction_texture(Color(1.0, 1.0, 0.85, 1.0))
			_:
				env.adjustment_saturation = 1.0
				env.adjustment_color_correction = null

func _make_correction_texture(tint: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0, tint)
	grad.set_color(1, Color.WHITE)
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

func _apply_ui_scale(scale: float) -> void:
	# Apply UI scale via the window's content scale factor
	var clamped := clampf(scale, 0.75, 1.5)
	get_tree().root.content_scale_factor = clamped

func _apply_text_size(scale: float) -> void:
	# Apply text size override to all Control nodes with theme font overrides
	var clamped := clampf(scale, 0.8, 1.4)
	var tree := get_tree()
	if not tree or not tree.root:
		return
	_apply_text_size_recursive(tree.root, clamped)

func _apply_text_size_recursive(node: Node, scale: float) -> void:
	if node is Control:
		var ctrl := node as Control
		# Add a theme font size override multiplier
		# The default font size in Godot 4 is 16; scale it
		var base_size: int = int(16 * scale)
		ctrl.add_theme_font_size_override("font_size", base_size)
	for child in node.get_children():
		_apply_text_size_recursive(child, scale)

func _apply_high_contrast(enabled: bool) -> void:
	# Increase contrast by adjusting environment and UI theme colors
	var env := _get_world_environment()
	if env:
		env.adjustment_enabled = enabled or env.adjustment_enabled
		if enabled:
			env.adjustment_brightness = 1.05
			env.adjustment_contrast = 1.15
		else:
			env.adjustment_brightness = 1.0
			env.adjustment_contrast = 1.0

func _apply_reduce_motion(enabled: bool) -> void:
	# Disable camera shake and screen shake when reduce_motion is on
	# FlightController reads this via get_setting() at runtime
	var tree := get_tree()
	if tree and tree.root:
		var fc := tree.root.find_child("FlightController", true, false) as Node
		if fc and is_instance_valid(fc) and "camera_shake_intensity" in fc:
			if enabled:
				fc.set("camera_shake_intensity", 0.0)

func _apply_screen_shake_intensity(intensity: float) -> void:
	# Scale camera shake intensity — FlightController reads this at runtime
	# Store in settings for FlightController to query via get_setting()
	var clamped := clampf(intensity, 0.0, 1.0)
	# Also apply immediately if FlightController is present
	var tree := get_tree()
	if tree and tree.root:
		var fc := tree.root.find_child("FlightController", true, false) as Node
		if fc and is_instance_valid(fc) and "camera_shake_multiplier" in fc:
			fc.set("camera_shake_multiplier", clamped)
