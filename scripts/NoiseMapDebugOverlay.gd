# res://scripts/NoiseMapDebugOverlay.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# NoiseMapDebugOverlay.gd — Debug Visualization for Gameplay Noise Maps
# ==============================================================================
# Renders the SystemNoiseField's 4 channels as semi-transparent colored
# planes on the system's orbital plane (ecliptic). Toggled with F4.
#
# Each channel gets its own colored plane:
#   - RESOURCES: Green plane (mineral/bio-matter density)
#   - ENEMIES:   Red plane (hostile Void-Fauna density)
#   - ANOMALIES: Purple plane (special event density)
#   - HAZARDS:   Yellow plane (environmental danger density)
#
# The planes are stacked slightly above the ecliptic to avoid z-fighting.
# Channel visibility can be toggled individually with F5-F8.
#
# This is a DEVELOPMENT TOOL for visualizing noise distribution.
# For the in-game player experience, see ScannerHUD.gd.
# ==============================================================================

extends Node3D

const SystemNoiseFieldClass: GDScript = preload("res://scripts/SystemNoiseField.gd")

var _planes: Dictionary = {}  # Channel -> MeshInstance3D
var _is_visible: bool = false
var _channel_visible: Dictionary = {}
var _noise_field: Node = null
var _overlay_opacity: float = 0.6

# Channel key bindings for individual toggles
const KEY_TOGGLE_ALL = KEY_F4
const KEY_TOGGLE_RESOURCES = KEY_F5
const KEY_TOGGLE_ENEMIES = KEY_F6
const KEY_TOGGLE_ANOMALIES = KEY_F7
const KEY_TOGGLE_HAZARDS = KEY_F8

func _ready() -> void:
	# Find the SystemNoiseField (sibling node under SpaceFlight)
	_noise_field = get_node_or_null("../SystemNoiseField")

	# Initialize all channels as visible
	for channel in [0, 1, 2, 3]:
		_channel_visible[channel] = true

	# Create the planes but keep them hidden initially
	_create_planes()
	_set_overlay_visible(false)

	# Connect to noise field generation signal
	if _noise_field and _noise_field.has_signal("grids_generated"):
		_noise_field.grids_generated.connect(_on_grids_generated)

func _create_planes() -> void:
	# Remove existing planes
	for channel in _planes.keys():
		var plane: MeshInstance3D = _planes[channel]
		if plane and is_instance_valid(plane):
			plane.queue_free()
	_planes.clear()

	if not _noise_field:
		return

	var extent_m: float = _noise_field.get_system_extent_m()
	# Each plane is a large flat quad covering the system
	# Stack them at slightly different Y offsets to avoid z-fighting
	var y_offsets: Dictionary = {0: 0.0, 1: 100.0, 2: 200.0, 3: 300.0}

	for channel in [0, 1, 2, 3]:
		var plane := MeshInstance3D.new()
		plane.name = "NoisePlane_" + SystemNoiseFieldClass.CHANNEL_NAMES[channel]

		# Create a plane mesh
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(extent_m * 2.0, extent_m * 2.0)
		mesh.orientation = PlaneMesh.FACE_Y  # Flat on XZ plane
		plane.mesh = mesh

		# Position at system center (star), slightly above ecliptic
		plane.position = Vector3(0.0, y_offsets[channel], 0.0)

		# Create material with the channel color
		var mat := StandardMaterial3D.new()
		var base_color: Color = SystemNoiseFieldClass.CHANNEL_COLORS[channel]
		mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, _overlay_opacity)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true  # Always visible regardless of depth
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		plane.material_override = mat

		add_child(plane)
		_planes[channel] = plane

	# Update textures from noise field
	_update_plane_textures()

func _update_plane_textures() -> void:
	if not _noise_field or not _noise_field.is_generated():
		return

	for channel in [0, 1, 2, 3]:
		if not _planes.has(channel):
			continue
		var plane: MeshInstance3D = _planes[channel]
		if not plane or not is_instance_valid(plane):
			continue

		# Get colored image from noise field
		var img: Image = _noise_field.get_channel_colored_image(channel)
		if img.is_empty():
			continue

		var tex := ImageTexture.create_from_image(img)
		var mat := plane.material_override as StandardMaterial3D
		if mat:
			mat.albedo_texture = tex

func _on_grids_generated() -> void:
	_update_plane_textures()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		match key:
			KEY_TOGGLE_ALL:
				_is_visible = not _is_visible
				_set_overlay_visible(_is_visible)
				print("[NoiseMapDebug] Overlay %s" % ("ON" if _is_visible else "OFF"))
			KEY_TOGGLE_RESOURCES:
				_toggle_channel(0)
			KEY_TOGGLE_ENEMIES:
				_toggle_channel(1)
			KEY_TOGGLE_ANOMALIES:
				_toggle_channel(2)
			KEY_TOGGLE_HAZARDS:
				_toggle_channel(3)

func _toggle_channel(channel: int) -> void:
	_channel_visible[channel] = not _channel_visible[channel]
	if _planes.has(channel):
		var plane: MeshInstance3D = _planes[channel]
		if plane and is_instance_valid(plane):
			plane.visible = _is_visible and _channel_visible[channel]
	print("[NoiseMapDebug] Channel %s: %s" % [
		SystemNoiseFieldClass.CHANNEL_NAMES[channel],
		"ON" if _channel_visible[channel] else "OFF"
	])

func _set_overlay_visible(vis: bool) -> void:
	for channel in _planes.keys():
		var plane: MeshInstance3D = _planes[channel]
		if plane and is_instance_valid(plane):
			plane.visible = vis and _channel_visible.get(channel, true)

func set_channel_visible(channel: int, is_visible: bool) -> void:
	_channel_visible[channel] = is_visible
	if _planes.has(channel):
		var plane: MeshInstance3D = _planes[channel]
		if plane and is_instance_valid(plane):
			plane.visible = _is_visible and _channel_visible[channel]

func set_overlay_opacity(opacity: float) -> void:
	_overlay_opacity = clampf(opacity, 0.1, 1.0)
	for channel in _planes.keys():
		var plane: MeshInstance3D = _planes[channel]
		if plane and is_instance_valid(plane):
			var mat := plane.material_override as StandardMaterial3D
			if mat:
				var base_color: Color = SystemNoiseFieldClass.CHANNEL_COLORS[channel]
				mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, _overlay_opacity)

func is_overlay_visible() -> bool:
	return _is_visible

func get_channel_visible(channel: int) -> bool:
	return _channel_visible.get(channel, false)
