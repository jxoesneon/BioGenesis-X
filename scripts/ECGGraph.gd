# res://scripts/ECGGraph.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# ECGGraph.gd - Real-time Oscilloscope & ECG Heartbeat Line Graph Render Control
# ==============================================================================
# Extends Control to render a high-fidelity biopunk oscilloscope. Subscribes to
# OrganTelemetry.gd for live pulse data or generates autonomous P-QRS-T samples.
# Renders grid lines, glowing cyan/green traces, scanning sweep line, and fading trail.
# ==============================================================================

@tool
class_name ECGGraph
extends Control

## Signal emitted when ECG heart pulse reaches R-wave peak
signal heart_beat_peak(bpm: float)

@export_group("Biopunk Aesthetic & Styling")
## Primary trace signal color (glowing cyan-green)
@export var trace_color: Color = Color(0.0, 1.0, 0.75, 1.0)
## Secondary glow color around active trace head
@export var glow_color: Color = Color(0.0, 1.0, 0.5, 0.6)
## Oscilloscope background grid color
@export var grid_color: Color = Color(0.0, 0.35, 0.25, 0.25)
## Accent grid line color (major grid markers)
@export var major_grid_color: Color = Color(0.0, 0.6, 0.4, 0.45)
## Scanning sweep vertical cursor line color
@export var sweep_line_color: Color = Color(0.2, 1.0, 0.8, 0.8)
## Baseline center reference line color
@export var baseline_color: Color = Color(0.0, 0.5, 0.3, 0.3)

@export_group("Graph Dimensions & Performance")
## Line width of the ECG trace
@export var line_thickness: float = 2.2
## Number of sample points stored across the horizontal display width
@export var max_samples: int = 250
## Horizontal sweep speed (pixels per second)
@export var sweep_speed: float = 120.0
## Vertical amplitude scaling factor
@export var amplitude_gain: float = 0.40
## Display grid division size in pixels
@export var grid_step_px: float = 24.0
## Enable fading trail effect behind scanning sweep line
@export var enable_fading_trail: bool = true
## Show biometric HUD overlay text (BPM, Sync status)
@export var show_hud_text: bool = true

# Internal State & Buffer Management
var _sample_buffer: PackedFloat32Array = PackedFloat32Array()
var _write_index: int = 0
var _sweep_x: float = 0.0
var _telemetry_ref: Node = null
var _current_bpm: float = 68.0
var _internal_time: float = 0.0
var _last_peak_time: float = 0.0

func _ready() -> void:
	_init_buffer()
	_locate_telemetry_source()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _exit_tree() -> void:
	if resized.is_connected(_on_resized):
		resized.disconnect(_on_resized)
	if _telemetry_ref and is_instance_valid(_telemetry_ref):
		if _telemetry_ref.is_connected("ecg_pulse", Callable(self, "push_sample")):
			_telemetry_ref.disconnect("ecg_pulse", Callable(self, "push_sample"))
		if _telemetry_ref.is_connected("telemetry_updated", Callable(self, "_on_telemetry_updated")):
			_telemetry_ref.disconnect("telemetry_updated", Callable(self, "_on_telemetry_updated"))

func _on_resized() -> void:
	queue_redraw()

func _init_buffer() -> void:
	_sample_buffer.resize(max_samples)
	_sample_buffer.fill(0.0)

func _locate_telemetry_source() -> void:
	if get_node_or_null("/root/OrganTelemetry"):
		_telemetry_ref = get_node("/root/OrganTelemetry")
		if _telemetry_ref.has_signal("ecg_pulse"):
			if not _telemetry_ref.is_connected("ecg_pulse", Callable(self, "push_sample")):
				_telemetry_ref.connect("ecg_pulse", Callable(self, "push_sample"))
		if _telemetry_ref.has_signal("telemetry_updated"):
			if not _telemetry_ref.is_connected("telemetry_updated", Callable(self, "_on_telemetry_updated")):
				_telemetry_ref.connect("telemetry_updated", Callable(self, "_on_telemetry_updated"))

func _on_telemetry_updated(data: Dictionary) -> void:
	if data.has("heart_rate_bpm"):
		_current_bpm = data["heart_rate_bpm"]

func push_sample(value: float) -> void:
	if _sample_buffer.size() != max_samples:
		_init_buffer()
	
	_sample_buffer[_write_index] = value
	
	# Detect R-wave peak for pulse signal emission
	if value > 0.8:
		var current_ticks := Time.get_ticks_msec() / 1000.0
		if current_ticks - _last_peak_time > (60.0 / clamp(_current_bpm, 40.0, 200.0)) * 0.7:
			_last_peak_time = current_ticks
			heart_beat_peak.emit(_current_bpm)
			
	_write_index = (_write_index + 1) % max(1, max_samples)
	queue_redraw()

func set_heart_rate(bpm: float) -> void:
	_current_bpm = max(30.0, bpm)

func _process(delta: float) -> void:
	_internal_time += delta
	if size.x > 0.0:
		_sweep_x = fmod(_sweep_x + sweep_speed * delta, size.x)
	
	# If no external OrganTelemetry is connected, generate self-contained heartbeat signal
	if _telemetry_ref == null or not is_instance_valid(_telemetry_ref):
		var sample := _synthesize_ecg_waveform(_internal_time)
		push_sample(sample)
	else:
		queue_redraw()

## Autonomous fallback P-QRS-T waveform generator when OrganTelemetry autoload is absent
func _synthesize_ecg_waveform(t: float) -> float:
	var period: float = 60.0 / clamp(_current_bpm, 40.0, 200.0)
	var phase: float = fmod(t, period) / period
	var sample: float = 0.0

	# P-wave (Atrial depolarization)
	if phase >= 0.10 and phase <= 0.20:
		var p_p := (phase - 0.15) / 0.05
		sample += 0.15 * exp(-p_p * p_p * 4.0)
	# QRS complex (Ventricular depolarization)
	elif phase >= 0.30 and phase <= 0.44:
		if phase <= 0.34: # Q dip
			var q_p := (phase - 0.32) / 0.02
			sample -= 0.20 * exp(-q_p * q_p * 6.0)
		elif phase <= 0.40: # R peak
			var r_p := (phase - 0.37) / 0.03
			sample += 1.20 * exp(-r_p * r_p * 8.0)
		else: # S dip
			var s_p := (phase - 0.42) / 0.02
			sample -= 0.35 * exp(-s_p * s_p * 6.0)
	# T-wave (Ventricular repolarization)
	elif phase >= 0.58 and phase <= 0.74:
		var t_p := (phase - 0.66) / 0.08
		sample += 0.30 * exp(-t_p * t_p * 3.5)

	# Micro bio-noise
	sample += (randf() * 0.015 - 0.0075)
	return sample

func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return

	# Draw solid background frame
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.04, 0.85), true)

	# Phosphor glow afterimage - subtle green CRT ambient wash behind sweep
	var phosphor_width: float = size.x * 0.25
	var phosphor_start_x: float = _sweep_x - phosphor_width
	if phosphor_start_x < 0:
		# Wrap-around glow from right edge
		draw_rect(Rect2(Vector2(maxf(0.0, size.x + phosphor_start_x), 0), Vector2(-phosphor_start_x, size.y)), Color(0.0, 0.25, 0.15, 0.08), true)
		draw_rect(Rect2(Vector2(0, 0), Vector2(_sweep_x, size.y)), Color(0.0, 0.25, 0.15, 0.06), true)
	else:
		draw_rect(Rect2(Vector2(phosphor_start_x, 0), Vector2(phosphor_width, size.y)), Color(0.0, 0.25, 0.15, 0.08), true)
	# Bright phosphor band right at sweep position
	var bright_w: float = 8.0
	draw_rect(Rect2(Vector2(maxf(0.0, _sweep_x - bright_w), 0), Vector2(bright_w, size.y)), Color(0.0, 0.4, 0.25, 0.1), true)

	# 1. Draw Oscilloscope Grid Lines
	_draw_oscilloscope_grid()

	# 2. Draw Baseline Center Line
	var center_y: float = size.y * 0.5
	draw_line(Vector2(0, center_y), Vector2(size.x, center_y), baseline_color, 1.0)

	# 3. Draw ECG Line Trace
	if _sample_buffer.size() < 2:
		return

	var num_pts: int = _sample_buffer.size()
	var step_x: float = size.x / float(num_pts - 1)
	var sweep_idx: int = int((_sweep_x / size.x) * float(num_pts))

	var points: PackedVector2Array = PackedVector2Array()
	points.resize(num_pts)

	for i in range(num_pts):
		var val: float = _sample_buffer[i]
		var px: float = float(i) * step_x
		var py: float = center_y - (val * (size.y * amplitude_gain))
		points[i] = Vector2(px, py)

	# Draw segments with fading opacity behind sweep head
	for i in range(num_pts - 1):
		var dist_to_sweep: float = float(i - sweep_idx)
		if dist_to_sweep < 0:
			dist_to_sweep += num_pts
		
		var alpha: float = 1.0
		if enable_fading_trail:
			var norm_dist: float = dist_to_sweep / float(num_pts)
			alpha = clamp(1.0 - norm_dist, 0.08, 1.0)
		
		# Draw outer glow segment
		var col_glow := glow_color
		col_glow.a *= alpha * 0.5
		draw_line(points[i], points[i + 1], col_glow, line_thickness * 2.5)

		# Draw primary trace segment
		var col_trace := trace_color
		col_trace.a *= alpha
		draw_line(points[i], points[i + 1], col_trace, line_thickness)

	# 4. Draw Scanning Sweep Vertical Cursor Line & Lead Glow Head
	draw_line(Vector2(_sweep_x, 0), Vector2(_sweep_x, size.y), sweep_line_color, 1.5)
	
	if sweep_idx >= 0 and sweep_idx < points.size():
		var head_pt: Vector2 = points[sweep_idx]
		draw_circle(head_pt, 4.5, trace_color)
		draw_circle(head_pt, 7.5, glow_color)

	# 5. Draw Outer Biopunk Border Frame
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.8, 0.6, 0.6), false, 1.5)

	# Corner tick marks
	var corner_len: float = min(12.0, min(size.x, size.y) * 0.1)
	draw_line(Vector2(0, 0), Vector2(corner_len, 0), trace_color, 2.0)
	draw_line(Vector2(0, 0), Vector2(0, corner_len), trace_color, 2.0)
	draw_line(Vector2(size.x, 0), Vector2(size.x - corner_len, 0), trace_color, 2.0)
	draw_line(Vector2(size.x, 0), Vector2(size.x, corner_len), trace_color, 2.0)
	draw_line(Vector2(0, size.y), Vector2(corner_len, size.y), trace_color, 2.0)
	draw_line(Vector2(0, size.y), Vector2(0, size.y - corner_len), trace_color, 2.0)
	draw_line(Vector2(size.x, size.y), Vector2(size.x - corner_len, size.y), trace_color, 2.0)
	draw_line(Vector2(size.x, size.y), Vector2(size.x, size.y - corner_len), trace_color, 2.0)


	# 6. Draw Biometric Telemetry Overlay Text
	if show_hud_text:
		var font: Font = get_theme_default_font()
		var font_size: int = clamp(int(size.y * 0.12), 10, 16)
		var label_str: String = "ECG LEAD-I | %d BPM" % int(_current_bpm)
		draw_string(font, Vector2(10, font_size + 6), label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, trace_color)
		
		var status_str: String = "HEMOLYMPH OSC"
		draw_string(font, Vector2(size.x - 100, font_size + 6), status_str, HORIZONTAL_ALIGNMENT_RIGHT, 90, font_size, Color(0.0, 0.8, 0.5, 0.7))

func _draw_oscilloscope_grid() -> void:
	if grid_step_px <= 4.0:
		return

	var x_steps := int(size.x / grid_step_px)
	var y_steps := int(size.y / grid_step_px)

	for x in range(1, x_steps):
		var px := float(x) * grid_step_px
		var is_major := (x % 4 == 0)
		var col := major_grid_color if is_major else grid_color
		draw_line(Vector2(px, 0), Vector2(px, size.y), col, 1.0 if not is_major else 1.2)

	for y in range(1, y_steps):
		var py := float(y) * grid_step_px
		var is_major := (y % 4 == 0)
		var col := major_grid_color if is_major else grid_color
		draw_line(Vector2(0, py), Vector2(size.x, py), col, 1.0 if not is_major else 1.2)

	# Grid dot markers at intersections
	var dot_col := Color(0.0, 0.6, 0.45, 0.4)
	for x in range(1, x_steps):
		for y in range(1, y_steps):
			var px := float(x) * grid_step_px
			var py := float(y) * grid_step_px
			var is_major_x := (x % 4 == 0)
			var is_major_y := (y % 4 == 0)
			if is_major_x and is_major_y:
				draw_circle(Vector2(px, py), 2.0, Color(0.0, 0.8, 0.55, 0.5))
			else:
				draw_circle(Vector2(px, py), 1.0, dot_col)
