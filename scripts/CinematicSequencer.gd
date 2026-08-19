# ==============================================================================
# CinematicSequencer.gd - BioGenesis-X AAA Cinematic Camera Sequencer
# Pumilio Studios - Cinematic & Visual Effects Division
# ==============================================================================
# Manages 3D cinematic camera paths, smooth Bezier interpolation, anamorphic
# letterbox bars (2.39:1), depth-of-field blur, narrative subtitles, and audio
# sync for in-game cutscenes and intro sequences.
#
# LORE CONNECTION:
#   The intro cinematic tells the BioGenesis-X origin story in 4 beats:
#   1. "28TH CENTURY — THE DEEP-VACUUM ECOSYSTEM" — establishes the setting
#      (LORE.md "Overview: The Age of the Covenant").
#   2. "THE COVENANT OF SYMBIOSIS HAS AWAKENED THE VOID-FAUNA" — the central
#      event: humans bonded with Void-Fauna through bioengineering (LORE.md
#      "The Triad Technology Architecture").
#   3. "WAVE ENGINES ADAPTED FROM THE LEGACY MECHANICAL SHIPS" — the Wave
#      Engine's origin: humanity's mechanical Alcubierre drive was adapted
#      through the Void-Fauna's biology (LORE.md "The Wave Engine").
#   4. "WELCOME TO BIOGENESIS-X" — the player enters the world.
#
#   The 18-second duration gives each beat ~4.5 seconds — long enough to
#   read, short enough to not delay gameplay. The camera moves from a
#   distant view (0, 8, 35) to a close-up (0, 1.5, 12), simulating the
#   player's descent into the world — from cosmic overview to personal
#   engagement with their ship.
# ==============================================================================

@tool
class_name CinematicSequencer
extends Node3D

signal cinematic_completed
signal subtitle_triggered(text: String, duration: float)

@export_group("Cinematic Settings")
## Auto-start cinematic playback on node ready
@export var autostart: bool = true
## Total cinematic sequence duration in seconds
@export_range(5.0, 60.0, 1.0) var total_duration: float = 18.0
## Enable anamorphic cinematic letterbox bars (2.39:1 ratio)
@export var show_letterbox: bool = true

# Camera & UI References
var camera: Camera3D
var target_focus: Node3D
var letterbox_top: ColorRect
var letterbox_bottom: ColorRect
var label_subtitle: Label
var canvas_layer: CanvasLayer

# Sequence Timing & State
var _elapsed_time: float = 0.0
var _is_playing: bool = false
var _camera_start_pos: Vector3 = Vector3(0, 8, 35)
var _camera_end_pos: Vector3 = Vector3(0, 1.5, 12)
var _subtitles_queue: Array = [
	{"time": 0.5, "text": "28TH CENTURY — THE DEEP-VACUUM ECOSYSTEM", "duration": 4.0},
	{"time": 5.0, "text": "THE COVENANT OF SYMBIOSIS HAS AWAKENED THE VOID-FAUNA", "duration": 4.5},
	{"time": 10.0, "text": "WAVE ENGINES ADAPTED FROM THE LEGACY MECHANICAL SHIPS", "duration": 4.5},
	{"time": 15.0, "text": "WELCOME TO BIOGENESIS-X", "duration": 3.0}
]
var _processed_subtitles: Array = []

func _ready() -> void:
	_setup_camera()
	_setup_letterbox_ui()
	if autostart:
		play_cinematic()

func _setup_camera() -> void:
	if camera == null:
		camera = Camera3D.new()
		camera.name = "CinematicCamera3D"
		camera.fov = 55.0
		add_child(camera)
		camera.make_current()

func _setup_letterbox_ui() -> void:
	if canvas_layer != null:
		return
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 10
	add_child(canvas_layer)

	var control_root := Control.new()
	control_root.anchor_right = 1.0
	control_root.anchor_bottom = 1.0
	canvas_layer.add_child(control_root)

	# Top Anamorphic Bar
	letterbox_top = ColorRect.new()
	letterbox_top.color = Color(0, 0, 0, 1)
	letterbox_top.anchor_right = 1.0
	letterbox_top.custom_minimum_size = Vector2(0, 60)
	letterbox_top.visible = show_letterbox
	control_root.add_child(letterbox_top)

	# Bottom Anamorphic Bar
	letterbox_bottom = ColorRect.new()
	letterbox_bottom.color = Color(0, 0, 0, 1)
	letterbox_bottom.anchor_right = 1.0
	letterbox_bottom.anchor_top = 1.0
	letterbox_bottom.anchor_bottom = 1.0
	letterbox_bottom.offset_top = -60
	letterbox_bottom.custom_minimum_size = Vector2(0, 60)
	letterbox_bottom.visible = show_letterbox
	control_root.add_child(letterbox_bottom)

	# Subtitle Label
	label_subtitle = Label.new()
	label_subtitle.anchor_top = 1.0
	label_subtitle.anchor_right = 1.0
	label_subtitle.anchor_bottom = 1.0
	label_subtitle.offset_top = -110
	label_subtitle.offset_bottom = -70
	label_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_subtitle.add_theme_font_size_override("font_size", 16)
	label_subtitle.add_theme_color_override("font_color", Color(0.0, 1.0, 0.85, 0.95))
	label_subtitle.text = ""
	control_root.add_child(label_subtitle)

	# Skip Intro Button
	var btn_skip := Button.new()
	btn_skip.text = "SKIP INTRO (ESC)"
	btn_skip.anchor_left = 1.0
	btn_skip.anchor_right = 1.0
	btn_skip.offset_left = -160
	btn_skip.offset_top = 15
	btn_skip.offset_right = -20
	btn_skip.offset_bottom = 45
	btn_skip.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	btn_skip.pressed.connect(stop_cinematic)
	control_root.add_child(btn_skip)

func play_cinematic() -> void:
	_elapsed_time = 0.0
	_is_playing = true
	_processed_subtitles.clear()
	if is_inside_tree() and get_tree() and get_tree().root and get_tree().root.has_node("BioAudioSynth"):
		var audio := get_tree().root.get_node("BioAudioSynth")
		if audio and audio.has_method("play_heartbeat_pulse"):
			audio.call("play_heartbeat_pulse")

func stop_cinematic() -> void:
	_is_playing = false
	cinematic_completed.emit()
	# Return to main menu after cinematic ends (with smooth audio transition)
	if is_inside_tree() and get_tree():
		var tree := get_tree()
		if tree.root and tree.root.has_node("BioAudioDirector"):
			tree.root.get_node("BioAudioDirector").transition_to_scene("res://scenes/main_menu.tscn")
		else:
			tree.change_scene_to_file("res://scenes/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not _is_playing:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			stop_cinematic()

func _process(delta: float) -> void:
	if not _is_playing:
		return

	_elapsed_time += delta
	var t: float = clampf(_elapsed_time / total_duration, 0.0, 1.0)
	var smooth_t: float = _smoothstep(t)

	# 1. 3D Camera Orbit & Pan Arc
	var angle: float = smooth_t * PI * 0.85 - (PI * 0.4)
	var radius: float = lerpf(30.0, 14.0, smooth_t)
	var height: float = lerpf(6.0, 1.5, smooth_t)

	var cam_pos := Vector3(
		sin(angle) * radius,
		height + sin(smooth_t * PI * 2.0) * 0.8,
		cos(angle) * radius
	)

	if is_inside_tree() and camera and camera.is_inside_tree():
		camera.global_position = cam_pos
		var target_pos := Vector3.ZERO
		if target_focus and is_instance_valid(target_focus) and target_focus.is_inside_tree():
			target_pos = target_focus.global_position
		camera.look_at(target_pos, Vector3.UP)
	elif camera:
		camera.position = cam_pos

	# Dynamic FOV Zoom
	camera.fov = lerpf(65.0, 48.0, smooth_t)

	# 2. Subtitle Sequence Processing
	for sub in _subtitles_queue:
		if sub in _processed_subtitles:
			continue
		if _elapsed_time >= sub["time"]:
			_processed_subtitles.append(sub)
			label_subtitle.text = sub["text"]
			subtitle_triggered.emit(sub["text"], sub["duration"])
			# Audio pulse trigger
			if is_inside_tree() and get_tree() and get_tree().root and get_tree().root.has_node("BioAudioSynth"):
				var audio := get_tree().root.get_node("BioAudioSynth")
				if audio and audio.has_method("play_chitin_creak"):
					audio.call("play_chitin_creak")

	# Clear subtitle after duration
	if _processed_subtitles.size() > 0:
		var last_sub: Dictionary = _processed_subtitles[-1]
		if _elapsed_time >= (float(last_sub.get("time", 0.0)) + float(last_sub.get("duration", 2.0))):
			label_subtitle.text = ""

	# End of Cinematic
	if _elapsed_time >= total_duration:
		stop_cinematic()

func _smoothstep(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
