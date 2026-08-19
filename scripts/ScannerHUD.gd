# res://scripts/ScannerHUD.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# ScannerHUD.gd — In-Game Holographic Noise Map Scanner (AAA Immersion)
# ==============================================================================
# A ship system that renders the SystemNoiseField as a holographic scanning
# plane when activated by the player. Unlike the debug overlay, this is an
# immersive in-game tool with:
#   - Scan animation (radial sweep from ship position)
#   - Holographic shader effect (scanlines, edge glow, pulsing)
#   - Channel selection (player chooses which channel to scan)
#   - Range limitation (scanner has a finite radius around the ship)
#   - Audio feedback (scanning hum, detection pings)
#
# Activation: Press SCAN key (default: Tab) to toggle the scanner.
# Channel switch: Press 1-4 to select channel while scanner is active.
# ==============================================================================

extends Node3D

const SystemNoiseFieldClass: GDScript = preload("res://scripts/SystemNoiseField.gd")

var _noise_field: Node = null
var _scanner_plane: MeshInstance3D = null
var _scanner_material: ShaderMaterial = null
var _is_active: bool = false
var _current_channel: int = 0  # Default: RESOURCES
var _scan_progress: float = 0.0
var _scan_range_m: float = 5000.0  # 5km scan radius around ship
var _ship_node: Node3D = null

# --- Scanner shader (inline to avoid external file dependency) ---
const SCANNER_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D noise_tex;
uniform vec4 channel_color : source_color = vec4(0.0, 1.0, 0.4, 1.0);
uniform float scan_progress : hint_range(0.0, 1.0) = 0.0;
uniform float scan_range = 5000.0;
uniform float time_sec = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.7;
uniform vec3 ship_pos = vec3(0.0);

varying vec2 v_uv;
varying vec3 v_world_pos;

void vertex() {
	v_uv = UV;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 noise_val = texture(noise_tex, v_uv);
	float intensity = noise_val.a;

	// Distance from ship in world space
	float dist_from_ship = length(v_world_pos.xz - ship_pos.xz);
	float normalized_dist = dist_from_ship / scan_range;

	// Scan sweep effect — radial wave from ship position
	float scan_wave = smoothstep(scan_progress - 0.05, scan_progress, normalized_dist)
		- smoothstep(scan_progress, scan_progress + 0.05, normalized_dist);

	// Scanline effect
	float scanlines = sin(v_uv.y * 200.0 + time_sec * 5.0) * 0.5 + 0.5;
	scanlines = mix(0.7, 1.0, scanlines);

	// Edge fade — fade out at scan range boundary
	float edge_fade = 1.0 - smoothstep(0.85, 1.0, normalized_dist);

	// Combine effects
	float alpha = intensity * opacity * edge_fade * scanlines;
	alpha += scan_wave * 0.3 * opacity;  // Add scan wave glow

	ALBEDO = channel_color.rgb * intensity * scanlines;
	ALPHA = clamp(alpha, 0.0, 1.0);
	EMISSION = channel_color.rgb * scan_wave * 0.5;
}
"""

func _ready() -> void:
	# Find SystemNoiseField (sibling node under SpaceFlight)
	_noise_field = get_node_or_null("../SystemNoiseField")

	# Find ship
	call_deferred("_find_ship")

	# Create scanner plane (hidden initially)
	_create_scanner_plane()

	# Connect to noise field
	if _noise_field and _noise_field.has_signal("grids_generated"):
		_noise_field.grids_generated.connect(_on_grids_generated)

func _find_ship() -> void:
	_ship_node = get_node_or_null("../PlayerShip")

func _create_scanner_plane() -> void:
	_scanner_plane = MeshInstance3D.new()
	_scanner_plane.name = "ScannerHUDPlane"

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(_scan_range_m * 2.0, _scan_range_m * 2.0)
	mesh.orientation = PlaneMesh.FACE_Y
	_scanner_plane.mesh = mesh

	# Create shader material
	_scanner_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SCANNER_SHADER_CODE
	_scanner_material.shader = shader

	var base_color: Color = SystemNoiseFieldClass.CHANNEL_COLORS[_current_channel]
	_scanner_material.set_shader_parameter("channel_color", base_color)
	_scanner_material.set_shader_parameter("scan_progress", 0.0)
	_scanner_material.set_shader_parameter("scan_range", _scan_range_m)
	_scanner_material.set_shader_parameter("opacity", 0.7)
	_scanner_material.set_shader_parameter("ship_pos", Vector3.ZERO)

	_scanner_plane.material_override = _scanner_material
	_scanner_plane.visible = false
	add_child(_scanner_plane)

func _on_grids_generated() -> void:
	_update_scanner_texture()

func _update_scanner_texture() -> void:
	if not _noise_field or not _noise_field.is_generated():
		return
	if not _scanner_material:
		return

	var img: Image = _noise_field.get_channel_colored_image(_current_channel)
	if img.is_empty():
		return
	var tex := ImageTexture.create_from_image(img)
	_scanner_material.set_shader_parameter("noise_tex", tex)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		match key:
			KEY_TAB:
				toggle_scanner()
			KEY_1:
				_switch_channel(0)  # RESOURCES
			KEY_2:
				_switch_channel(1)  # ENEMIES
			KEY_3:
				_switch_channel(2)  # ANOMALIES
			KEY_4:
				_switch_channel(3)  # HAZARDS

func toggle_scanner() -> void:
	_is_active = not _is_active
	if _scanner_plane:
		_scanner_plane.visible = _is_active
	_scan_progress = 0.0
	print("[ScannerHUD] Scanner %s — Channel: %s" % [
		"ACTIVE" if _is_active else "INACTIVE",
		SystemNoiseFieldClass.CHANNEL_NAMES[_current_channel]
	])
	_play_scan_sound(_is_active)

func _switch_channel(channel: int) -> void:
	if not _is_active:
		return
	_current_channel = channel
	_update_scanner_texture()
	if _scanner_material:
		_scanner_material.set_shader_parameter("channel_color",
			SystemNoiseFieldClass.CHANNEL_COLORS[channel])
	print("[ScannerHUD] Channel: %s" % SystemNoiseFieldClass.CHANNEL_NAMES[channel])
	_play_ui_click()

func _process(delta: float) -> void:
	if not _is_active:
		return

	# Animate scan sweep
	_scan_progress += delta * 0.3  # 3.3 seconds per full sweep
	if _scan_progress > 1.0:
		_scan_progress = 0.0

	# Update shader parameters
	if _scanner_material:
		_scanner_material.set_shader_parameter("scan_progress", _scan_progress)
		_scanner_material.set_shader_parameter("time_sec", Time.get_ticks_msec() / 1000.0)

	# Follow ship position
	if _ship_node and is_instance_valid(_ship_node):
		var ship_pos: Vector3 = _ship_node.global_position
		# Position scanner plane at ship location, slightly above ecliptic
		_scanner_plane.global_position = Vector3(ship_pos.x, 50.0, ship_pos.z)
		if _scanner_material:
			_scanner_material.set_shader_parameter("ship_pos", ship_pos)

func set_scan_range(range_m: float) -> void:
	_scan_range_m = maxf(range_m, 100.0)
	if _scanner_plane and _scanner_plane.mesh is PlaneMesh:
		(_scanner_plane.mesh as PlaneMesh).size = Vector2(_scan_range_m * 2.0, _scan_range_m * 2.0)
	if _scanner_material:
		_scanner_material.set_shader_parameter("scan_range", _scan_range_m)

func set_opacity(opacity: float) -> void:
	if _scanner_material:
		_scanner_material.set_shader_parameter("opacity", clampf(opacity, 0.1, 1.0))

func is_active() -> bool:
	return _is_active

func get_current_channel() -> int:
	return _current_channel

func _play_scan_sound(activating: bool) -> void:
	var tree := get_tree()
	if tree and tree.root:
		var synth := tree.root.get_node_or_null("BioAudioSynth")
		if synth and synth.has_method("play_ui_click"):
			synth.play_ui_click(activating)

func _play_ui_click() -> void:
	var tree := get_tree()
	if tree and tree.root:
		var synth := tree.root.get_node_or_null("BioAudioSynth")
		if synth and synth.has_method("play_ui_click"):
			synth.play_ui_click(false)
