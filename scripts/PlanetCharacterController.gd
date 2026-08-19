# ==============================================================================
# PlanetCharacterController.gd
# BioGenesis-X: Third-Person Planet Surface Character Controller
# ==============================================================================
# Walks, runs, jumps, crouches and swims on the OUTER SURFACE of spherical
# planets. Gravity always points toward the planet center (radial gravity),
# not the engine's global -Y axis. The character's up vector is smoothly
# slerped to the local surface normal so the avatar stands "upright" anywhere
# on the sphere.
#
# Movement is camera-relative: WASD is projected onto the local tangent plane
# (perpendicular to the surface normal) so the player walks along the curve of
# the world. Swimming switches to full 3D buoyant movement when submerged.
#
# Designed to be instantiated by PlanetSurfaceManager / PlanetDescentController
# when the player exits their ship onto a planet surface.
# ==============================================================================
class_name PlanetCharacterController
extends CharacterBody3D

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal started_walking()
signal started_running()
signal stopped_moving()
signal jumped()
signal landed(impact_force: float)
signal entered_water(depth: float)
signal exited_water()
signal footstep()
signal stamina_changed(stamina: float, max_stamina: float)

# ------------------------------------------------------------------------------
# Movement Exports
# ------------------------------------------------------------------------------
@export_group("Locomotion")
@export var walk_speed: float = 3.0
@export var run_speed: float = 7.0
@export var jump_force: float = 5.0
@export var crouch_height: float = 0.9
@export var stand_height: float = 1.8
@export var gravity_scale: float = 1.0
@export var rotation_speed: float = 10.0

@export_group("Swimming")
@export var swim_speed: float = 4.0
@export var buoyancy_strength: float = 6.0
@export var water_drag: float = 3.0

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 18.0
@export var stamina_regen_rate: float = 12.0
@export var stamina_regain_delay: float = 1.2

@export_group("Input & Feel")
@export var acceleration: float = 18.0
@export var air_acceleration: float = 4.0
@export var ground_friction: float = 12.0
@export var footstep_interval: float = 0.45

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _planet_center: Vector3 = Vector3.ZERO
var _planet_radius: float = 100.0
var _surface_gravity: float = 9.81
var _surface_normal: Vector3 = Vector3.UP
var _gravity_vector: Vector3 = Vector3.DOWN * 9.81

var _is_running: bool = false
var _is_crouching: bool = false
var _is_swimming: bool = false
var _is_moving: bool = false
var _water_depth: float = 0.0
var _was_on_floor: bool = false

var _stamina: float = 100.0
var _stamina_regen_timer: float = 0.0

var _footstep_timer: float = 0.0
var _current_height: float = 1.8
var _jump_requested: bool = false

# Reference to the orbit camera (set externally or auto-detected).
# Typed as Camera3D (PlanetCamera extends Camera3D) to avoid a hard
# class_name forward-reference; the orbit camera provides its transform.
var _camera: Camera3D = null

# Collision shape reference for crouch height changes.
var _collision_shape: CollisionShape3D = null

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	_current_height = stand_height
	_collision_shape = _find_collision_shape()
	_apply_collision_height(stand_height)
	# CharacterBody3D floor detection uses up_direction.
	up_direction = _surface_normal
	# Capture mouse for orbit look; the camera handles actual capture.
	if _camera == null:
		_camera = _find_planet_camera()

func _find_collision_shape() -> CollisionShape3D:
	for child: Node in get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape"
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = stand_height
	capsule.radius = 0.35
	shape.shape = capsule
	add_child(shape)
	return shape

func _find_planet_camera() -> Camera3D:
	var parent: Node = get_parent()
	while parent != null:
		for child: Node in parent.get_children():
			if child is Camera3D:
				return child as Camera3D
		parent = parent.get_parent()
	return null

func _physics_process(delta: float) -> void:
	_update_surface_normal()
	_update_gravity_vector()
	up_direction = _surface_normal

	_align_to_surface(delta)
	_update_stamina(delta)

	if _is_swimming:
		_process_swimming(delta)
	else:
		_process_ground_movement(delta)

	_handle_footsteps(delta)
	_check_landing()
	_was_on_floor = is_on_floor()

# Edge detection for jump (Space) and swim-up/swim-down keys.
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if not k.echo and k.pressed and k.keycode == KEY_SPACE:
			_jump_requested = true
			get_viewport().set_input_as_handled()

# ------------------------------------------------------------------------------
# Planet Configuration
# ------------------------------------------------------------------------------
## Configures radial gravity for a spherical planet.
## center: world-space center of the planet.
## radius: planet radius in meters.
## surface_gravity: gravity magnitude at the surface in m/s^2.
func set_planet(center: Vector3, radius: float, surface_gravity: float) -> void:
	_planet_center = center
	_planet_radius = maxf(1.0, radius)
	_surface_gravity = surface_gravity
	_update_surface_normal()
	_update_gravity_vector()
	up_direction = _surface_normal

# ------------------------------------------------------------------------------
# Surface Normal & Gravity
# ------------------------------------------------------------------------------
func _update_surface_normal() -> void:
	var to_center: Vector3 = _planet_center - global_position
	var dist: float = to_center.length()
	if dist < 0.001:
		_surface_normal = Vector3.UP
		return
	# Surface normal points AWAY from planet center (outward = up).
	_surface_normal = (-to_center / dist).normalized()

func _update_gravity_vector() -> void:
	# Gravity points TOWARD planet center.
	_gravity_vector = (_planet_center - global_position).normalized() * _surface_gravity

# ------------------------------------------------------------------------------
# Alignment (smooth slerp of up vector to surface normal)
# ------------------------------------------------------------------------------
func _align_to_surface(delta: float) -> void:
	var current_up: Vector3 = global_transform.basis.y
	var target_up: Vector3 = _surface_normal
	var dot: float = clampf(current_up.dot(target_up), -1.0, 1.0)
	if dot > 0.9999:
		return
	var axis: Vector3 = current_up.cross(target_up)
	if axis.length_squared() < 1e-9:
		# Parallel/opposite; pick a fallback rotation axis.
		axis = current_up.cross(Vector3.FORWARD)
		if axis.length_squared() < 1e-9:
			axis = current_up.cross(Vector3.RIGHT)
	var angle: float = acos(dot)
	var max_angle: float = rotation_speed * delta
	var step: float = minf(angle, max_angle)
	var q_current: Quaternion = Quaternion(global_transform.basis.orthonormalized())
	var q_rot: Quaternion = Quaternion(axis.normalized(), step)
	var q_new: Quaternion = q_rot * q_current
	global_transform.basis = Basis(q_new).orthonormalized()

# ------------------------------------------------------------------------------
# Ground Movement (walk / run / jump / crouch)
# ------------------------------------------------------------------------------
func _process_ground_movement(delta: float) -> void:
	# Apply radial gravity.
	velocity += _gravity_vector * gravity_scale * delta

	var input_dir: Vector2 = _get_move_input()
	var is_moving: bool = input_dir.length_squared() > 0.01

	# Determine run state: Shift + moving + has stamina.
	var wants_run: bool = is_moving and Input.is_key_pressed(KEY_SHIFT) and _stamina > 0.1 and not _is_crouching
	if wants_run and not _is_running:
		_is_running = true
		started_running.emit()
	elif not wants_run and _is_running:
		_is_running = false

	# Crouch handling (Ctrl).
	_is_crouching = Input.is_key_pressed(KEY_CTRL) and is_on_floor()
	var target_height: float = crouch_height if _is_crouching else stand_height
	_apply_collision_height(target_height)

	# Build camera-relative horizontal direction on the tangent plane.
	var move_speed: float = _current_move_speed()
	var wish_dir: Vector3 = _compute_wish_direction(input_dir)

	var accel: float = acceleration if is_on_floor() else air_acceleration
	if is_moving:
		velocity = velocity.move_toward(wish_dir * move_speed, accel * delta)
		if not _is_running and is_on_floor() and not _is_moving:
			started_walking.emit()
		_is_moving = true
	else:
		if is_on_floor():
			# Apply ground friction to the tangent-plane component.
			var hori: Vector3 = _project_to_tangent(velocity)
			var vert: Vector3 = velocity - hori
			hori = hori.move_toward(Vector3.ZERO, ground_friction * delta)
			velocity = hori + vert
			if _is_moving and hori.length_squared() < 0.25:
				_is_moving = false
				stopped_moving.emit()

	# Jump (only when grounded, not crouching, has stamina).
	if _jump_requested and is_on_floor() and not _is_crouching and _stamina > 5.0:
		# Jump along the surface normal (away from planet).
		velocity += _surface_normal * jump_force
		_stamina -= 5.0
		_stamina_regen_timer = stamina_regain_delay
		stamina_changed.emit(_stamina, max_stamina)
		jumped.emit()
	_jump_requested = false

	move_and_slide()

func _current_move_speed() -> float:
	if _is_crouching:
		return walk_speed * 0.5
	return run_speed if _is_running else walk_speed

## Projects WASD input into a world-space direction on the local tangent plane,
## relative to the orbit camera's yaw.
func _compute_wish_direction(input_dir: Vector2) -> Vector3:
	if _camera == null:
		# Fallback: use global basis.
		var fwd: Vector3 = -global_transform.basis.z
		var right: Vector3 = global_transform.basis.x
		var wish_dir: Vector3 = (fwd * input_dir.y + right * input_dir.x)
		return _project_to_tangent(wish_dir).normalized()
	var cam_basis: Basis = _camera.global_transform.basis
	var cam_fwd: Vector3 = -cam_basis.z
	var cam_right: Vector3 = cam_basis.x
	var wish: Vector3 = cam_fwd * input_dir.y + cam_right * input_dir.x
	return _project_to_tangent(wish).normalized()

func _project_to_tangent(vec: Vector3) -> Vector3:
	return vec - _surface_normal * vec.dot(_surface_normal)

func _get_move_input() -> Vector2:
	var v: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	return v.normalized()

# ------------------------------------------------------------------------------
# Swimming
# ------------------------------------------------------------------------------
func _process_swimming(delta: float) -> void:
	# Reduced gravity + buoyancy toward surface.
	velocity += _gravity_vector * gravity_scale * 0.25 * delta
	# Buoyancy pushes up (along surface normal) proportional to depth.
	var buoy: Vector3 = _surface_normal * buoyancy_strength * clampf(_water_depth * 0.1, 0.0, 1.0)
	velocity += buoy * delta
	# Water drag.
	velocity = velocity.move_toward(Vector3.ZERO, water_drag * delta)

	var input_dir: Vector2 = _get_move_input()
	var cam_basis: Basis = _camera.global_transform.basis if _camera != null else global_transform.basis
	var wish: Vector3 = (-cam_basis.z * input_dir.y + cam_basis.x * input_dir.x)
	if Input.is_key_pressed(KEY_SPACE):
		wish += _surface_normal
	if Input.is_key_pressed(KEY_CTRL):
		wish -= _surface_normal
	wish = wish.normalized()
	velocity = velocity.move_toward(wish * swim_speed, acceleration * delta)
	_jump_requested = false
	move_and_slide()

# ------------------------------------------------------------------------------
# Collision Height (crouch)
# ------------------------------------------------------------------------------
func _apply_collision_height(target_height: float) -> void:
	_current_height = target_height
	if _collision_shape == null:
		return
	var shape: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
	if shape == null:
		return
	shape.height = target_height
	# Keep the capsule base at the feet.
	_collision_shape.position.y = target_height * 0.5

# ------------------------------------------------------------------------------
# Stamina
# ------------------------------------------------------------------------------
func _update_stamina(delta: float) -> void:
	if _is_running and not _is_swimming:
		_stamina = maxf(0.0, _stamina - stamina_drain_rate * delta)
		_stamina_regen_timer = stamina_regain_delay
	elif not _is_running:
		_stamina_regen_timer = maxf(0.0, _stamina_regen_timer - delta)
		if _stamina_regen_timer <= 0.0:
			_stamina = minf(max_stamina, _stamina + stamina_regen_rate * delta)
	stamina_changed.emit(_stamina, max_stamina)

# ------------------------------------------------------------------------------
# Footsteps
# ------------------------------------------------------------------------------
func _handle_footsteps(delta: float) -> void:
	if not is_on_floor() or _is_swimming:
		_footstep_timer = 0.0
		return
	var speed: float = _project_to_tangent(velocity).length()
	if speed < 0.5:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	var interval: float = footstep_interval * (walk_speed / maxf(0.1, speed))
	if _footstep_timer <= 0.0:
		_footstep_timer = interval
		footstep.emit()

# ------------------------------------------------------------------------------
# Landing Detection
# ------------------------------------------------------------------------------
func _check_landing() -> void:
	if not _was_on_floor and is_on_floor() and not _is_swimming:
		var impact: float = _project_to_tangent(velocity).length()
		var fall_speed: float = absf(velocity.dot(-_surface_normal))
		var force: float = fall_speed + impact
		landed.emit(force)

# ------------------------------------------------------------------------------
# Water / Swimming Control
# ------------------------------------------------------------------------------
## Toggles swimming mode and reports the current water depth in meters.
func set_swimming(swimming: bool, depth: float) -> void:
	var was_swimming: bool = _is_swimming
	_is_swimming = swimming
	_water_depth = depth
	if swimming and not was_swimming:
		entered_water.emit(depth)
	elif not swimming and was_swimming:
		exited_water.emit()

# ------------------------------------------------------------------------------
# Ship Entry / Exit Transitions
# ------------------------------------------------------------------------------
## Places the character on the planet surface just outside the ship.
func enter_from_ship(ship_pos: Vector3, ship_rot: Basis) -> void:
	global_position = ship_pos + (ship_rot.y * 2.0)
	_update_surface_normal()
	_update_gravity_vector()
	up_direction = _surface_normal
	# Snap alignment to surface normal immediately.
	var fwd: Vector3 = -ship_rot.z
	var projected_fwd: Vector3 = _project_to_tangent(fwd).normalized()
	if projected_fwd.length_squared() < 0.01:
		projected_fwd = _surface_normal.cross(Vector3.RIGHT).normalized()
	var new_basis: Basis = Basis.looking_at(projected_fwd, _surface_normal)
	global_transform.basis = new_basis
	velocity = Vector3.ZERO

## Returns the character to the ship (caller re-enables ship controller).
func return_to_ship() -> void:
	velocity = Vector3.ZERO
	_is_swimming = false
	_is_running = false
	_is_crouching = false
	stopped_moving.emit()

# ------------------------------------------------------------------------------
# Accessors
# ------------------------------------------------------------------------------
func get_stamina() -> float:
	return _stamina

func is_swimming() -> bool:
	return _is_swimming

func is_running() -> bool:
	return _is_running

func is_crouching() -> bool:
	return _is_crouching

func get_surface_normal() -> Vector3:
	return _surface_normal

func get_water_depth() -> float:
	return _water_depth

func set_camera(cam: Camera3D) -> void:
	_camera = cam
