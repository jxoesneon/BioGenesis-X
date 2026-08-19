# res://scripts/LoadingScreenManager.gd
# ==============================================================================
# BioGenesis-X — Loading Screen Manager
# ==============================================================================
# Provides a themed loading screen between scene transitions (main menu → flight,
# flight → galaxy map, etc.) that:
#
# 1. Shows a biopunk-themed overlay with progress bar and status text
# 2. Loads the target scene asynchronously via ResourceLoader.load_threaded_request
# 3. Tracks procedural generation signals after scene swap:
#    - UniverseManager.system_loaded
#    - SystemNoiseField.grids_generated
#    - ChunkStreamManager first chunk loaded
#    - AsteroidField asteroids generated
# 4. Fades out only when all systems report ready
#
# This prevents the player from seeing a half-loaded scene with popping content.
# ==============================================================================

extends Node

# --- Loading stages ---
enum Stage {
	IDLE,
	LOADING_RESOURCE,
	SCENE_SWAP,
	WAITING_FOR_SYSTEM,
	WAITING_FOR_NOISE,
	WAITING_FOR_CHUNKS,
	WAITING_FOR_ASTEROIDS,
	FADE_OUT,
	COMPLETE,
}

var _stage: Stage = Stage.IDLE

# --- Target scene ---
var _target_scene_path: String = ""
var _target_scene_name: String = ""
var _resource_loading_path: String = ""

# --- Progress tracking ---
var _resource_progress: float = 0.0  # 0-1 from ResourceLoader
var _init_progress: float = 0.0      # 0-1 from signal chain
var _total_progress: float = 0.0     # combined 0-1

# --- Signal tracking flags ---
var _system_loaded: bool = false
var _noise_generated: bool = false
var _chunks_loaded: bool = false
var _asteroids_generated: bool = false

# --- Timeout (safety so we don't hang forever) ---
const MAX_LOAD_TIME_SEC: float = 30.0
var _elapsed: float = 0.0

# --- UI elements ---
var _overlay: CanvasLayer = null
var _bg_rect: ColorRect = null
var _progress_bar: ProgressBar = null
var _status_label: Label = null
var _lore_label: Label = null
var _title_label: Label = null
var _fade_tween: Tween = null

# --- Lore snippets shown during loading ---
const LORE_SNIPPETS: Array[String] = [
	"In the void between stars, life found a way...",
	"The Covenant of Symbiosis binds pilot and Void-Fauna as one.",
	"Wave Engine engaging — folding space around the vessel.",
	"Biological systems initializing — organs pulsing with bioluminescent energy.",
	"Neural pathways calibrating — the ship dreams of open space.",
	"Radiation shielding membranes flexing — void-fauna adapting to stellar wind.",
	"Propulsion cysts swelling with charged plasma — ready for the void.",
	"The void is not empty. It teems with life we have yet to name.",
	"Your ship is alive. It breathes. It thinks. It flies.",
	"From the depths of the Void-Fauna, a new form of travel emerges.",
]

signal loading_started(scene_path: String)
signal loading_complete(scene_path: String)

## Returns true if the loading screen has completed (not idle, not in progress).
func is_complete() -> bool:
	return _stage == Stage.COMPLETE

## Returns true if loading is actively in progress.
func is_loading() -> bool:
	return _stage != Stage.IDLE and _stage != Stage.COMPLETE

## Returns the current loading stage as an integer (for external polling).
func get_stage() -> int:
	return int(_stage)

## Returns total progress as 0.0 to 1.0.
func get_total_progress() -> float:
	return _total_progress

func _ready() -> void:
	_create_overlay()

# ==============================================================================
# Overlay UI Construction
# ==============================================================================
func _create_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "LoadingScreenOverlay"
	_overlay.layer = 200  # Above BioAudioDirector's layer 100
	add_child(_overlay)

	# Full-screen black background
	_bg_rect = ColorRect.new()
	_bg_rect.color = Color(0.02, 0.05, 0.03, 0.0)  # Near-black with green tint, start transparent
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input during loading
	_overlay.add_child(_bg_rect)

	# Main container
	var container := VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 20)
	_bg_rect.add_child(container)

	# Title
	_title_label = Label.new()
	_title_label.text = "BIOGENESIS-X"
	_title_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5, 0.0))
	_title_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.5, 0.2, 0.0))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	container.add_child(_title_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	container.add_child(spacer)

	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.custom_minimum_size = Vector2(500, 24)
	_progress_bar.modulate.a = 0.0
	# Theme the progress bar
	var pb_style_bg := StyleBoxFlat.new()
	pb_style_bg.bg_color = Color(0.05, 0.15, 0.08, 0.8)
	pb_style_bg.border_color = Color(0.2, 0.6, 0.3, 0.6)
	pb_style_bg.border_width_left = 1
	pb_style_bg.border_width_right = 1
	pb_style_bg.border_width_top = 1
	pb_style_bg.border_width_bottom = 1
	pb_style_bg.corner_radius_top_left = 4
	pb_style_bg.corner_radius_top_right = 4
	pb_style_bg.corner_radius_bottom_left = 4
	pb_style_bg.corner_radius_bottom_right = 4
	_progress_bar.add_theme_stylebox_override("background", pb_style_bg)

	var pb_style_fill := StyleBoxFlat.new()
	pb_style_fill.bg_color = Color(0.2, 0.8, 0.4, 0.9)
	pb_style_fill.corner_radius_top_left = 4
	pb_style_fill.corner_radius_top_right = 4
	pb_style_fill.corner_radius_bottom_left = 4
	pb_style_fill.corner_radius_bottom_right = 4
	_progress_bar.add_theme_stylebox_override("fill", pb_style_fill)
	container.add_child(_progress_bar)

	# Status label
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.5, 0.0))
	container.add_child(_status_label)

	# Lore label
	_lore_label = Label.new()
	_lore_label.text = ""
	_lore_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	_lore_label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_BOTTOM
	_lore_label.add_theme_font_size_override("font_size", 13)
	_lore_label.add_theme_color_override("font_color", Color(0.3, 0.6, 0.4, 0.0))
	_lore_label.custom_minimum_size = Vector2(600, 40)
	container.add_child(_lore_label)

	# Start hidden
	_overlay.visible = false

# ==============================================================================
# Public API
# ==============================================================================

## Start a loading-screen transition to the given scene.
## This replaces direct change_scene_to_file calls for scenes that need
## procedural generation time (space_flight, galaxy_map, etc.).
func transition_to_scene(scene_path: String) -> void:
	if _stage != Stage.IDLE and _stage != Stage.COMPLETE:
		push_warning("[LoadingScreen] Transition already in progress, ignoring new request")
		return

	_target_scene_path = scene_path
	_target_scene_name = scene_path.get_file().get_basename()
	_resource_progress = 0.0
	_init_progress = 0.0
	_total_progress = 0.0
	_system_loaded = false
	_noise_generated = false
	_chunks_loaded = false
	_asteroids_generated = false
	_elapsed = 0.0

	# Pick a random lore snippet
	_lore_label.text = LORE_SNIPPETS[randi() % LORE_SNIPPETS.size()]

	# Show and fade in overlay
	_overlay.visible = true
	_fade_overlay_in()

	# Start threaded resource loading
	_resource_loading_path = scene_path
	ResourceLoader.load_threaded_request(scene_path)
	_stage = Stage.LOADING_RESOURCE
	_status_label.text = "Loading scene resources..."

	# Trigger BioAudioDirector audio crossfade (without scene change)
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioDirector"):
		var director: Node = ml.root.get_node("BioAudioDirector")
		if director.has_method("prepare_audio_for_scene"):
			director.prepare_audio_for_scene(scene_path)

	loading_started.emit(scene_path)
	print("[LoadingScreen] Starting transition to: %s" % scene_path)

## Instant transition (no loading screen) for simple scene changes
func quick_transition(scene_path: String) -> void:
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file(scene_path)

# ==============================================================================
# Main Processing Loop
# ==============================================================================
func _process(delta: float) -> void:
	if _stage == Stage.IDLE or _stage == Stage.COMPLETE:
		return

	_elapsed += delta

	# Safety timeout
	if _elapsed > MAX_LOAD_TIME_SEC:
		push_warning("[LoadingScreen] Timeout reached, forcing completion")
		_force_complete()
		return

	match _stage:
		Stage.LOADING_RESOURCE:
			_poll_resource_loading()
		Stage.SCENE_SWAP:
			_do_scene_swap()
		Stage.WAITING_FOR_SYSTEM:
			_update_status("Generating star system...", 0.1)
		Stage.WAITING_FOR_NOISE:
			_update_status("Computing noise fields...", 0.3)
		Stage.WAITING_FOR_CHUNKS:
			_update_status("Streaming gameplay chunks...", 0.5)
		Stage.WAITING_FOR_ASTEROIDS:
			_update_status("Seeding asteroid field...", 0.7)
		Stage.FADE_OUT:
			pass  # Handled by tween

	_update_progress_bar()

# ==============================================================================
# Stage: Resource Loading
# ==============================================================================
func _poll_resource_loading() -> void:
	if _resource_loading_path.is_empty():
		_stage = Stage.SCENE_SWAP
		return

	var status: int = ResourceLoader.load_threaded_get_status(_resource_loading_path)
	match status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("[LoadingScreen] Invalid resource path: %s" % _resource_loading_path)
			# Fallback to direct scene change
			_resource_loading_path = ""
			_stage = Stage.SCENE_SWAP
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# ResourceLoader doesn't expose progress directly in Godot 4
			# We simulate progress based on time elapsed (resource loading is fast)
			_resource_progress = minf(_elapsed / 2.0, 0.95)
		ResourceLoader.THREAD_LOAD_LOADED:
			_resource_progress = 1.0
			_stage = Stage.SCENE_SWAP
		_:
			push_warning("[LoadingScreenManager] Unknown ResourceLoader status: %d" % status)

# ==============================================================================
# Stage: Scene Swap
# ==============================================================================
func _do_scene_swap() -> void:
	var tree := get_tree()
	if not tree:
		print("[LoadingScreen] ERROR: No scene tree during swap")
		_force_complete()
		return

	# Get the loaded resource
	var packed_scene: PackedScene = null
	if not _resource_loading_path.is_empty():
		packed_scene = ResourceLoader.load_threaded_get(_resource_loading_path)
		_resource_loading_path = ""

	if packed_scene:
		print("[LoadingScreen] Scene loaded, swapping to packed scene...")
		tree.change_scene_to_packed(packed_scene)
	else:
		print("[LoadingScreen] Packed scene null, falling back to change_scene_to_file...")
		tree.change_scene_to_file(_target_scene_path)

	# Use a timer to retry connection — the new scene's _ready() may not have
	# fired yet when call_deferred runs. A 0.1s timer gives the scene tree
	# time to process the new scene.
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.one_shot = true
	timer.timeout.connect(_connect_to_new_scene)
	add_child(timer)
	timer.start()

	_stage = Stage.WAITING_FOR_SYSTEM
	_status_label.text = "Initializing star system..."

# ==============================================================================
# Connect to the newly loaded scene's initialization signals
# ==============================================================================
func _connect_to_new_scene() -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene:
		print("[LoadingScreen] Scene not ready yet, retrying...")
		# Retry with another timer
		var timer := Timer.new()
		timer.wait_time = 0.1
		timer.one_shot = true
		timer.timeout.connect(_connect_to_new_scene)
		add_child(timer)
		timer.start()
		return

	var scene_root: Node = tree.current_scene
	print("[LoadingScreen] Connecting to new scene: %s" % scene_root.name)

	# Find UniverseManager and connect to system_loaded
	var universe_mgr := scene_root.get_node_or_null("UniverseManager")
	if universe_mgr:
		print("[LoadingScreen] Found UniverseManager, connecting to system_loaded signal")
		if universe_mgr.has_signal("system_loaded"):
			if not universe_mgr.system_loaded.is_connected(_on_system_loaded):
				universe_mgr.system_loaded.connect(_on_system_loaded)
		# Check if already loaded
		if universe_mgr.has_method("is_system_loaded") and universe_mgr.is_system_loaded():
			print("[LoadingScreen] System already loaded, proceeding")
			_on_system_loaded()
	else:
		print("[LoadingScreen] No UniverseManager found, skipping system stage")
		_on_system_loaded()

	# Find AsteroidField and connect to its generated signal
	var asteroid_field := scene_root.get_node_or_null("AsteroidField")
	if asteroid_field:
		print("[LoadingScreen] Found AsteroidField, connecting to asteroids_generated signal")
		if asteroid_field.has_signal("asteroids_generated"):
			if not asteroid_field.asteroids_generated.is_connected(_on_asteroids_generated):
				asteroid_field.asteroids_generated.connect(_on_asteroids_generated)
		# Check if already fully generated (flag-based, not child count)
		if asteroid_field.get("_asteroid_gen_done") == true:
			print("[LoadingScreen] AsteroidField already generated, proceeding")
			_on_asteroids_generated()
		# Otherwise wait for the signal — don't fire prematurely
	else:
		print("[LoadingScreen] No AsteroidField found, skipping asteroid stage")
		_on_asteroids_generated()

# ==============================================================================
# Signal callbacks from the new scene
# ==============================================================================
func _on_system_loaded() -> void:
	if _system_loaded:
		return
	_system_loaded = true
	_status_label.text = "Star system generated. Computing noise fields..."
	print("[LoadingScreen] ✓ System loaded")

	# Now connect to SystemNoiseField
	var tree := get_tree()
	if tree and tree.current_scene:
		var noise_field := tree.current_scene.get_node_or_null("SystemNoiseField")
		if noise_field:
			print("[LoadingScreen] Found SystemNoiseField, connecting to grids_generated")
			if noise_field.has_signal("grids_generated"):
				if not noise_field.grids_generated.is_connected(_on_noise_generated):
					noise_field.grids_generated.connect(_on_noise_generated)
			# Check if already generated
			if noise_field.has_method("is_generated") and noise_field.is_generated():
				print("[LoadingScreen] Noise already generated, proceeding")
				_on_noise_generated()
		else:
			print("[LoadingScreen] No SystemNoiseField found, skipping noise stage")
			_on_noise_generated()
	else:
		_on_noise_generated()

func _on_noise_generated() -> void:
	if _noise_generated:
		return
	_noise_generated = true
	_status_label.text = "Noise fields ready. Streaming gameplay chunks..."
	print("[LoadingScreen] ✓ Noise grids generated")

	# Now connect to ChunkStreamManager
	var tree := get_tree()
	if tree and tree.current_scene:
		var chunk_mgr := tree.current_scene.get_node_or_null("ChunkStreamManager")
		if chunk_mgr:
			print("[LoadingScreen] Found ChunkStreamManager, connecting to chunk_loaded")
			if chunk_mgr.has_signal("chunk_loaded"):
				if not chunk_mgr.chunk_loaded.is_connected(_on_chunk_loaded):
					chunk_mgr.chunk_loaded.connect(_on_chunk_loaded)
			# Check if already has active chunks
			if chunk_mgr.has_method("get_active_chunk_count"):
				var counts: Dictionary = chunk_mgr.get_active_chunk_count()
				if int(counts.get("far", 0)) > 0 or int(counts.get("near", 0)) > 0:
					print("[LoadingScreen] Chunks already active, proceeding")
					_on_chunk_loaded("", 0)
		else:
			print("[LoadingScreen] No ChunkStreamManager found, skipping chunk stage")
			_on_chunk_loaded("", 0)
	else:
		_on_chunk_loaded("", 0)

func _on_chunk_loaded(_chunk_key: String, _lod: int) -> void:
	if _chunks_loaded:
		return
	_chunks_loaded = true
	_status_label.text = "Chunks streaming. Finalizing..."
	print("[LoadingScreen] ✓ First chunk loaded")

	_check_all_ready()

func _on_asteroids_generated() -> void:
	if _asteroids_generated:
		return
	_asteroids_generated = true
	print("[LoadingScreen] ✓ Asteroid field generated")
	_check_all_ready()

func _check_all_ready() -> void:
	print("[LoadingScreen] Readiness check: system=%s noise=%s chunks=%s asteroids=%s" % [
		_system_loaded, _noise_generated, _chunks_loaded, _asteroids_generated
	])
	if _system_loaded and _noise_generated and _chunks_loaded and _asteroids_generated:
		_begin_fade_out()

# ==============================================================================
# Fade out and complete
# ==============================================================================
func _begin_fade_out() -> void:
	_stage = Stage.FADE_OUT
	_status_label.text = "Entering system..."

	# Fade overlay out
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_parallel(true)

	# Fade all UI elements
	_fade_tween.tween_property(_bg_rect, "color:a", 0.0, 0.8)
	_fade_tween.tween_property(_progress_bar, "modulate:a", 0.0, 0.5)
	_fade_tween.tween_property(_status_label, "modulate:a", 0.0, 0.5)
	_fade_tween.tween_property(_lore_label, "modulate:a", 0.0, 0.5)
	_fade_tween.tween_property(_title_label, "modulate:a", 0.0, 0.5)

	_fade_tween.chain().tween_callback(_on_fade_complete)

	print("[LoadingScreen] All systems ready, fading out")

func _on_fade_complete() -> void:
	_overlay.visible = false
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage = Stage.COMPLETE
	_status_label.text = ""
	_progress_bar.value = 100.0
	loading_complete.emit(_target_scene_path)
	print("[LoadingScreen] Transition complete: %s" % _target_scene_path)

	# Reset to idle for next transition
	call_deferred("_reset_to_idle")

func _reset_to_idle() -> void:
	_stage = Stage.IDLE
	_resource_progress = 0.0
	_init_progress = 0.0
	_total_progress = 0.0

# ==============================================================================
# Fallback / force complete
# ==============================================================================
func _force_complete() -> void:
	print("[LoadingScreen] Force completing after timeout")
	_system_loaded = true
	_noise_generated = true
	_chunks_loaded = true
	_asteroids_generated = true
	_begin_fade_out()

# ==============================================================================
# UI helpers
# ==============================================================================
func _fade_overlay_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_parallel(true)

	_fade_tween.tween_property(_bg_rect, "color:a", 1.0, 0.4)
	_fade_tween.tween_property(_progress_bar, "modulate:a", 1.0, 0.6)
	_fade_tween.tween_property(_status_label, "modulate:a", 1.0, 0.6)
	_fade_tween.tween_property(_lore_label, "modulate:a", 1.0, 0.8)
	_fade_tween.tween_property(_title_label, "modulate:a", 1.0, 0.5)

func _update_status(text: String, init_fraction: float) -> void:
	_status_label.text = text
	_init_progress = init_fraction

func _update_progress_bar() -> void:
	# Combine resource loading progress with init progress
	var resource_weight: float = 0.3
	var init_weight: float = 0.7

	# Compute init progress from signal flags
	var init_frac: float = 0.0
	if _system_loaded:
		init_frac += 0.25
	if _noise_generated:
		init_frac += 0.25
	if _chunks_loaded:
		init_frac += 0.25
	if _asteroids_generated:
		init_frac += 0.25

	_total_progress = _resource_progress * resource_weight + init_frac * init_weight
	_progress_bar.value = _total_progress * 100.0
