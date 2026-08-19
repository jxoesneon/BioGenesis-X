# ==============================================================================
# PlanetCamera.gd
# BioGenesis-X: Third-Person Orbit Camera for Planet Surface Exploration
# ==============================================================================
# Orbit camera that follows a PlanetCharacterController on a spherical planet.
# Mouse look orbits yaw/pitch around the target; scroll wheel zooms in/out.
# The camera's up vector is kept aligned with the character's up (the local
# surface normal) so the view stays level as the player walks around the curve
# of the world. Collision avoidance pulls the camera in when terrain occludes
# the line of sight to the target.
# ==============================================================================
class_name PlanetCamera
extends Camera3D

# ------------------------------------------------------------------------------
# Exports
# ------------------------------------------------------------------------------
@export_group("Orbit")
@export var yaw_sensitivity: float = 0.003
@export var pitch_sensitivity: float = 0.003
@export var min_pitch_deg: float = -75.0
@export var max_pitch_deg: float = 75.0
@export var min_distance: float = 2.0
@export var max_distance: float = 12.0
@export var zoom_step: float = 1.0

@export_group("Follow")
@export var follow_lerp: float = 12.0
@export var up_align_lerp: float = 8.0
@export var target_offset: Vector3 = Vector3(0.0, 1.5, 0.0)

@export_group("Collision Avoidance")
@export var collision_mask: int = 1
@export var collision_recover_lerp: float = 6.0
@export var collision_shape_radius: float = 0.3

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _target: Node3D = null
var _planet_up: Vector3 = Vector3.UP
var _yaw: float = 0.0
var _pitch: float = -0.35
var _distance: float = 7.0
var _current_up: Vector3 = Vector3.UP
var _mouse_captured: bool = false

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	# Independent of parent transform so physics interpolation of the target
	# does not double-apply to the camera.
	top_level = true
	reset_physics_interpolation()
	_current_up = _planet_up

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= motion.relative.x * yaw_sensitivity
		_pitch -= motion.relative.y * pitch_sensitivity
		_pitch = clamp(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_mouse_captured = true
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_mouse_captured = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(min_distance, _distance - zoom_step)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(max_distance, _distance + zoom_step)

func _process(delta: float) -> void:
	# Camera moves in _process with top_level=true + physics_interpolation off
	# for smooth orbit. Disable interpolation on this node to avoid warnings.
	if _target == null:
		return

	# Smoothly align the camera up to the planet/character up.
	_current_up = _current_up.slerp(_planet_up, up_align_lerp * delta).normalized()

	# Desired orbit position around the target.
	var target_pos: Vector3 = _target.global_position + _target.global_transform.basis * target_offset
	var offset: Vector3 = _compute_orbit_offset()
	var desired_pos: Vector3 = target_pos + offset

	# Collision avoidance: raycast from target to desired camera position.
	var safe_pos: Vector3 = _avoid_collision(target_pos, desired_pos)

	# Smoothly move to the safe position.
	global_position = global_position.slerp(safe_pos, follow_lerp * delta)
	if global_position.distance_to(safe_pos) < 0.001:
		global_position = safe_pos

	# Look at the target using the aligned up vector.
	var look_target: Vector3 = target_pos
	var cam_basis: Basis = Basis.looking_at((look_target - global_position).normalized(), _current_up)
	global_transform.basis = cam_basis

func _compute_orbit_offset() -> Vector3:
	# Build offset from yaw/pitch/distance using the aligned up as the reference up.
	var right: Vector3 = _current_up.cross(Vector3.FORWARD)
	if right.length_squared() < 1e-6:
		right = _current_up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward_h: Vector3 = right.cross(_current_up).normalized()
	# Rotate forward_h by yaw around up, then pitch around right.
	var dir: Vector3 = forward_h.rotated(_current_up, _yaw)
	dir = dir.rotated(right, _pitch)
	return dir * _distance

func _avoid_collision(from: Vector3, to: Vector3) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return to
	var state: PhysicsDirectSpaceState3D = world.direct_space_state
	if state == null:
		return to
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = to
	params.collision_mask = collision_mask
	var dict: Dictionary = state.intersect_ray(params)
	if dict.is_empty():
		return to
	var hit_pos: Vector3 = dict["position"]
	var normal: Vector3 = dict["normal"]
	# Pull the camera in to just before the hit, offset along the normal.
	var safe: Vector3 = hit_pos + normal * collision_shape_radius
	return safe

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------
## Sets the node this camera orbits around (typically the PlanetCharacterController).
func set_target(node: Node3D) -> void:
	_target = node

## Sets the reference up vector (surface normal / planet up) for level framing.
func set_planet_up(up: Vector3) -> void:
	_planet_up = up.normalized()

## Returns the current yaw (radians) so the character can read camera facing.
func get_yaw() -> float:
	return _yaw

## Returns the current orbit distance.
func get_distance() -> float:
	return _distance

## Sets the orbit distance directly (clamped to export limits).
func set_distance(d: float) -> void:
	_distance = clampf(d, min_distance, max_distance)

## Returns whether the right mouse button is currently capturing look input.
func is_mouse_captured() -> bool:
	return _mouse_captured
