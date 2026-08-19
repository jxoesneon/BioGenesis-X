# res://scripts/CombatVFX.gd
# ==============================================================================
# BioGenesis-X — Combat Visual Effects Manager (Autoload)
# Procedural particle-based VFX for all combat events. No external assets.
# ==============================================================================
extends Node
## CombatVFX — Autoload singleton for combat visual effects

## Active VFX budget — prevents particle explosion spam from tanking FPS
const MAX_ACTIVE_VFX: int = 64

# Cached Juicee autoload reference (dynamic lookup so this autoload parses cleanly
# even when the Juicee singleton isn't registered, e.g. headless test runs).
var _juicee_node: Node = null
# Active tween tracking — maps node RID to Tween for explicit cleanup.
var _active_tweens: Dictionary = {}

# --- Object pooling ---
# Pre-allocated pools of reusable VFX containers. Each pool stores Node3D
# containers carrying GPUParticles3D + OmniLight3D children, kept invisible
# and parented to this autoload until acquired by a spawn_* call.
const _POOL_SIZE: int = 32
var _impact_pool: Array[Node3D] = []
var _muzzle_pool: Array[Node3D] = []
var _explosion_pool: Array[Node3D] = []
var _shield_ripple_pool: Array[Node3D] = []
# Count of VFX currently active (acquired from a pool and live in the scene).
var _active_vfx_count: int = 0

# --- VFX profile registry ---
# Static registry mapping profile_id -> VFXProfile, populated at load time by
# game systems so any caller can spawn a data-driven effect by id.
static var _vfx_profiles: Dictionary = {}

## Spawn an impact effect at the given world position.
## [param normal] is the surface normal at the hit point (used to orient the
## bio-impact burn decal flat against the hull). Defaults to UP when unknown.
## Returns the spawned Node3D (or null if budget exceeded).
func spawn_impact(pos: Vector3, color: Color, hit_shield: bool, damage: float, normal: Vector3 = Vector3.UP) -> Node3D:
	var root := Engine.get_main_loop() as SceneTree
	if not root or not root.current_scene:
		return null
	if _active_vfx_count >= MAX_ACTIVE_VFX:
		return null
	var vfx: Node3D = _acquire_from_pool(_impact_pool, func() -> Node3D: return _make_bare_container("ImpactVFX", 1))
	_apply_impact_config(vfx, color, hit_shield, damage)
	vfx.visible = true
	vfx.global_position = pos
	vfx.reparent(root.current_scene)
	# Bio-impact burn decal — organic scorch + energy discharge that fades over
	# time. Null-safe: skipped if the shader isn't registered.
	_attach_impact_burn_decal(vfx, normal, damage, color)
	_add_pool_cleanup_timer(vfx, 1.0, _impact_pool)
	_active_vfx_count += 1
	# Juicee impact juice: 3D camera shake + hit-stop + FOV punch, scaled by damage.
	_trigger_combat_juice(damage, hit_shield)
	return vfx

## Spawn a muzzle flash at the given world position and direction.
func spawn_muzzle_flash(pos: Vector3, direction: Vector3, color: Color) -> Node3D:
	var root := Engine.get_main_loop() as SceneTree
	if not root or not root.current_scene:
		return null
	if _active_vfx_count >= MAX_ACTIVE_VFX:
		return null
	var flash := _acquire_from_pool(_muzzle_pool, func() -> Node3D: return _make_bare_container("MuzzleFlash", 1))
	_apply_muzzle_flash_config(flash, color)
	flash.visible = true
	flash.global_position = pos
	flash.look_at(pos + direction, Vector3.UP)
	flash.reparent(root.current_scene)
	_add_pool_cleanup_timer(flash, 0.2, _muzzle_pool)
	_active_vfx_count += 1
	return flash

## Spawn an explosion at the given world position. Used for enemy death,
## asteroid destruction, and large impacts.
func spawn_explosion(pos: Vector3, color: Color, scale: float = 1.0) -> Node3D:
	var root := Engine.get_main_loop() as SceneTree
	if not root or not root.current_scene:
		return null
	if _active_vfx_count >= MAX_ACTIVE_VFX:
		return null
	var explosion := _acquire_from_pool(_explosion_pool, func() -> Node3D: return _make_bare_container("Explosion", 2))
	_apply_explosion_config(explosion, color, scale)
	explosion.visible = true
	explosion.global_position = pos
	explosion.reparent(root.current_scene)
	_add_pool_cleanup_timer(explosion, 2.0, _explosion_pool)
	_active_vfx_count += 1
	# Juicee explosion juice: big shake + hit-stop + FOV kick, scaled by blast size.
	var juicee: Node = _get_juicee()
	if juicee:
		var intensity: float = clampf(scale, 0.3, 1.5)
		juicee.call("shake_camera_3d", self, 0.1 + intensity * 0.2, 0.3 + intensity * 0.2)
		juicee.call("hit_stop", self, 0.05 + intensity * 0.04, 0.0)
		juicee.call("fov_3d", self, -4.0 - intensity * 6.0, 0.3 + intensity * 0.2)
	return explosion

## Spawn a shield ripple effect at the given position, oriented to the hit normal.
func spawn_shield_ripple(pos: Vector3, normal: Vector3, color: Color) -> Node3D:
	var root := Engine.get_main_loop() as SceneTree
	if not root or not root.current_scene:
		return null
	if _active_vfx_count >= MAX_ACTIVE_VFX:
		return null
	var ripple := _acquire_from_pool(_shield_ripple_pool, func() -> Node3D: return _make_bare_container("ShieldRipple", 1))
	_apply_shield_ripple_config(ripple, color)
	ripple.visible = true
	ripple.global_position = pos
	ripple.look_at(pos + normal, Vector3.UP)
	ripple.reparent(root.current_scene)
	_add_pool_cleanup_timer(ripple, 0.8, _shield_ripple_pool)
	_active_vfx_count += 1
	return ripple

# ==============================================================================
# Internal: Object pooling infrastructure
# ==============================================================================

## Called when the autoload enters the tree. Pre-allocates the VFX pools so the
## first burst of combat effects doesn't stall on Node3D/GPUParticles3D alloc.
func _ready() -> void:
	_init_pools()

## Pre-creates [_POOL_SIZE] reusable containers per VFX type, each carrying the
## appropriate number of GPUParticles3D children plus an OmniLight3D. Containers
## start invisible and parented to this autoload until acquired by a spawn.
func _init_pools() -> void:
	for i in _POOL_SIZE:
		_impact_pool.append(_make_bare_container("ImpactVFX", 1))
		_muzzle_pool.append(_make_bare_container("MuzzleFlash", 1))
		_explosion_pool.append(_make_bare_container("Explosion", 2))
		_shield_ripple_pool.append(_make_bare_container("ShieldRipple", 1))

## Builds an invisible Node3D container with [param particle_count] named
## GPUParticles3D children ("Particles0", "Particles1", ...) and one OmniLight3D
## ("Light"). Parented to this autoload so it is processed but never rendered
## until acquired and re-parented into the active scene.
func _make_bare_container(node_name: String, particle_count: int) -> Node3D:
	var container := Node3D.new()
	container.name = node_name
	container.visible = false
	for i in particle_count:
		var particles := GPUParticles3D.new()
		particles.name = "Particles%d" % i
		particles.emitting = false
		container.add_child(particles)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.visible = true
	container.add_child(light)
	add_child(container)
	return container

## Returns a node from [param pool] if one is available, otherwise invokes
## [param factory] to create a fresh one. The returned node is hidden and owned
## by this autoload; the caller is responsible for configuring, showing, and
## re-parenting it into the scene.
func _acquire_from_pool(pool: Array[Node3D], factory: Callable) -> Node3D:
	if not pool.is_empty():
		return pool.pop_back()
	return factory.call()

## Recycles a VFX container back into [param pool]: stops all particle systems,
## frees transient children (decals / cleanup timers), kills tracked tweens,
## hides the node, and re-parents it to this autoload. Called automatically when
## a pool cleanup timer expires instead of queue_free-ing the node.
func _release_to_pool(pool: Array[Node3D], node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	_active_vfx_count = max(0, _active_vfx_count - 1)
	for child in node.get_children():
		if child is GPUParticles3D:
			child.emitting = false
		elif child is Timer or child is MeshInstance3D:
			child.queue_free()
	cleanup_tweens_for_node(node)
	node.visible = false
	var root := Engine.get_main_loop() as SceneTree
	if root and root.current_scene and node.get_parent() == root.current_scene:
		node.reparent(self)
	elif node.get_parent() != self:
		node.reparent(self)
	pool.append(node)

## Attaches a one-shot Timer that returns [param node] to [param pool] after
## [param delay] seconds, replacing the legacy queue_free cleanup so pooled
## nodes are recycled instead of freed.
func _add_pool_cleanup_timer(node: Node3D, delay: float, pool: Array[Node3D]) -> void:
	var timer := Timer.new()
	timer.name = "CleanupTimer"
	timer.wait_time = delay
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if is_instance_valid(node):
			_release_to_pool(pool, node)
	)
	node.add_child(timer)

# ==============================================================================
# Internal: Pooled VFX configuration (applied on acquire)
# ==============================================================================

## (Re)configures an impact container's Particles0 + Light using the same
## parameters as the legacy _create_impact_node factory. Children are created if
## missing so this works on both bare pooled containers and fresh nodes.
func _apply_impact_config(container: Node3D, color: Color, hit_shield: bool, damage: float) -> void:
	# Scale based on damage
	var intensity: float = clampf(damage / 50.0, 0.3, 2.0)
	var particles := container.get_node_or_null("Particles0") as GPUParticles3D
	if particles == null:
		particles = GPUParticles3D.new()
		particles.name = "Particles0"
		container.add_child(particles)
	# Spark/burst particles
	particles.amount = hit_shield and 24 or 16
	particles.lifetime = 0.4
	particles.explosiveness = 1.0
	particles.randomness = 0.8
	particles.one_shot = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.ZERO
	mat.spread = 35.0 if hit_shield else 25.0
	mat.initial_velocity_min = 3.0 * intensity
	mat.initial_velocity_max = 12.0 * intensity
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_fade_ramp_texture(color)
	mat.scale_min = 0.02
	mat.scale_max = 0.08 * intensity
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	particles.draw_pass_1 = mesh
	particles.emitting = true
	particles.restart()
	# Brief flash light
	var light := container.get_node_or_null("Light") as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = "Light"
		container.add_child(light)
	light.light_color = color
	light.light_energy = 5.0 * intensity
	light.omni_range = 4.0 * intensity
	light.omni_attenuation = 1.2

## (Re)configures a muzzle-flash container's Particles0 + Light.
func _apply_muzzle_flash_config(container: Node3D, color: Color) -> void:
	var particles := container.get_node_or_null("Particles0") as GPUParticles3D
	if particles == null:
		particles = GPUParticles3D.new()
		particles.name = "Particles0"
		container.add_child(particles)
	# Flash particles — brief outward burst
	particles.amount = 8
	particles.lifetime = 0.08
	particles.explosiveness = 1.0
	particles.one_shot = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.FORWARD
	mat.spread = 15.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_fade_ramp_texture(color)
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	particles.draw_pass_1 = mesh
	particles.emitting = true
	particles.restart()
	# Bright flash light
	var light := container.get_node_or_null("Light") as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = "Light"
		container.add_child(light)
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = 6.0
	light.omni_attenuation = 1.0

## (Re)configures an explosion container's Particles0 (blast) + Particles1
## (debris) + Light.
func _apply_explosion_config(container: Node3D, color: Color, scale: float) -> void:
	var particles := container.get_node_or_null("Particles0") as GPUParticles3D
	if particles == null:
		particles = GPUParticles3D.new()
		particles.name = "Particles0"
		container.add_child(particles)
	# Main blast particles
	particles.amount = int(60 * scale)
	particles.lifetime = 0.8
	particles.explosiveness = 1.0
	particles.randomness = 0.9
	particles.one_shot = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.ZERO
	mat.spread = 45.0
	mat.initial_velocity_min = 5.0 * scale
	mat.initial_velocity_max = 25.0 * scale
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_explosion_ramp_texture(color)
	mat.scale_min = 0.05 * scale
	mat.scale_max = 0.3 * scale
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 2.0
	mat.turbulence_influence_min = 0.2
	mat.turbulence_influence_max = 0.5
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	particles.draw_pass_1 = mesh
	particles.emitting = true
	particles.restart()
	# Secondary debris chunks
	var debris := container.get_node_or_null("Particles1") as GPUParticles3D
	if debris == null:
		debris = GPUParticles3D.new()
		debris.name = "Particles1"
		container.add_child(debris)
	debris.amount = int(12 * scale)
	debris.lifetime = 1.5
	debris.explosiveness = 1.0
	debris.randomness = 0.7
	debris.one_shot = true
	var debris_mat := ParticleProcessMaterial.new()
	debris_mat.direction = Vector3.ZERO
	debris_mat.spread = 30.0
	debris_mat.initial_velocity_min = 3.0 * scale
	debris_mat.initial_velocity_max = 10.0 * scale
	debris_mat.gravity = Vector3.ZERO
	debris_mat.color = Color(0.4, 0.3, 0.2, 1.0)
	debris_mat.color_ramp = _create_fade_ramp_texture(Color(0.4, 0.3, 0.2, 1.0))
	debris_mat.scale_min = 0.1 * scale
	debris_mat.scale_max = 0.25 * scale
	debris_mat.angular_velocity_min = 5.0
	debris_mat.angular_velocity_max = 15.0
	debris.process_material = debris_mat
	var debris_mesh := BoxMesh.new()
	debris_mesh.size = Vector3(0.15, 0.15, 0.15)
	debris.draw_pass_1 = debris_mesh
	debris.emitting = true
	debris.restart()
	# Bright explosion light
	var light := container.get_node_or_null("Light") as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = "Light"
		container.add_child(light)
	light.light_color = color
	light.light_energy = 15.0 * scale
	light.omni_range = 15.0 * scale
	light.omni_attenuation = 1.5

## (Re)configures a shield-ripple container's Particles0 + Light.
func _apply_shield_ripple_config(container: Node3D, color: Color) -> void:
	var particles := container.get_node_or_null("Particles0") as GPUParticles3D
	if particles == null:
		particles = GPUParticles3D.new()
		particles.name = "Particles0"
		container.add_child(particles)
	# Expanding ring particles
	particles.amount = 32
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.one_shot = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.BACK
	mat.spread = 5.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_fade_ramp_texture(color)
	mat.scale_min = 0.03
	mat.scale_max = 0.1
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh
	particles.emitting = true
	particles.restart()
	# Shield flash light
	var light := container.get_node_or_null("Light") as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = "Light"
		container.add_child(light)
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = 5.0
	light.omni_attenuation = 1.0

# ==============================================================================
# Internal: VFX profile registry
# ==============================================================================

## Registers a VFXProfile under its profile_id so it can be spawned by id.
static func register_vfx_profile(profile: VFXProfile) -> void:
	if profile == null:
		return
	_vfx_profiles[profile.profile_id] = profile

## Returns the VFXProfile registered under [param id], or null if not found.
static func get_vfx_profile(id: String) -> VFXProfile:
	return _vfx_profiles.get(id) as VFXProfile

## Spawns a VFX described by a registered VFXProfile at [param pos], oriented to
## [param normal]. Delegates to the matching spawn_* method using profile-derived
## parameters. Returns the spawned Node3D (or null if the profile is unknown or
## the active-VFX budget is exhausted).
func spawn_from_profile(profile_id: String, pos: Vector3, normal: Vector3 = Vector3.UP) -> Node3D:
	var profile := get_vfx_profile(profile_id)
	if profile == null:
		return null
	match profile.vfx_type:
		"impact":
			return spawn_impact(pos, profile.color_base, false, float(profile.particle_count) * 2.0, normal)
		"muzzle_flash":
			return spawn_muzzle_flash(pos, normal, profile.color_base)
		"explosion":
			return spawn_explosion(pos, profile.color_base, clampf(float(profile.particle_count) / 60.0, 0.1, 3.0))
		"shield_ripple":
			return spawn_shield_ripple(pos, normal, profile.color_base)
		"dissolve":
			return null
		_:
			return null

# ==============================================================================
# Internal: Particle node factories (legacy, non-pooled)
# ==============================================================================

func _create_impact_node(color: Color, hit_shield: bool, damage: float) -> Node3D:
	var container := Node3D.new()
	container.name = "ImpactVFX"

	# Scale based on damage
	var intensity: float = clampf(damage / 50.0, 0.3, 2.0)

	# Spark/burst particles
	var particles := GPUParticles3D.new()
	particles.name = "Sparks"
	particles.amount = hit_shield and 24 or 16
	particles.lifetime = 0.4
	particles.explosiveness = 1.0
	particles.randomness = 0.8
	particles.emitting = true
	particles.one_shot = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.ZERO
	mat.spread = 35.0 if hit_shield else 25.0
	mat.initial_velocity_min = 3.0 * intensity
	mat.initial_velocity_max = 12.0 * intensity
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_fade_ramp_texture(color)
	mat.scale_min = 0.02
	mat.scale_max = 0.08 * intensity
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	particles.draw_pass_1 = mesh

	container.add_child(particles)

	# Brief flash light
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0 * intensity
	light.omni_range = 4.0 * intensity
	light.omni_attenuation = 1.2
	container.add_child(light)

	# Auto-cleanup timer
	_add_cleanup_timer(container, 1.0)

	return container

func _create_muzzle_flash(color: Color) -> Node3D:
	var container := Node3D.new()
	container.name = "MuzzleFlash"

	# Flash particles — brief outward burst
	var particles := GPUParticles3D.new()
	particles.name = "Flash"
	particles.amount = 8
	particles.lifetime = 0.08
	particles.explosiveness = 1.0
	particles.emitting = true
	particles.one_shot = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.FORWARD
	mat.spread = 15.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_fade_ramp_texture(color)
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	particles.draw_pass_1 = mesh

	container.add_child(particles)

	# Bright flash light
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = 6.0
	light.omni_attenuation = 1.0
	container.add_child(light)

	_add_cleanup_timer(container, 0.2)

	return container

func _create_explosion(color: Color, scale: float) -> Node3D:
	var container := Node3D.new()
	container.name = "Explosion"

	# Main blast particles
	var particles := GPUParticles3D.new()
	particles.name = "Blast"
	particles.amount = int(60 * scale)
	particles.lifetime = 0.8
	particles.explosiveness = 1.0
	particles.randomness = 0.9
	particles.emitting = true
	particles.one_shot = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.ZERO
	mat.spread = 45.0
	mat.initial_velocity_min = 5.0 * scale
	mat.initial_velocity_max = 25.0 * scale
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_explosion_ramp_texture(color)
	mat.scale_min = 0.05 * scale
	mat.scale_max = 0.3 * scale
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 2.0
	mat.turbulence_influence_min = 0.2
	mat.turbulence_influence_max = 0.5
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	particles.draw_pass_1 = mesh

	container.add_child(particles)

	# Secondary debris chunks
	var debris := GPUParticles3D.new()
	debris.name = "Debris"
	debris.amount = int(12 * scale)
	debris.lifetime = 1.5
	debris.explosiveness = 1.0
	debris.randomness = 0.7
	debris.emitting = true
	debris.one_shot = true

	var debris_mat := ParticleProcessMaterial.new()
	debris_mat.direction = Vector3.ZERO
	debris_mat.spread = 30.0
	debris_mat.initial_velocity_min = 3.0 * scale
	debris_mat.initial_velocity_max = 10.0 * scale
	debris_mat.gravity = Vector3.ZERO
	debris_mat.color = Color(0.4, 0.3, 0.2, 1.0)
	debris_mat.color_ramp = _create_fade_ramp_texture(Color(0.4, 0.3, 0.2, 1.0))
	debris_mat.scale_min = 0.1 * scale
	debris_mat.scale_max = 0.25 * scale
	debris_mat.angular_velocity_min = 5.0
	debris_mat.angular_velocity_max = 15.0
	debris.process_material = debris_mat

	var debris_mesh := BoxMesh.new()
	debris_mesh.size = Vector3(0.15, 0.15, 0.15)
	debris.draw_pass_1 = debris_mesh

	container.add_child(debris)

	# Bright explosion light
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 15.0 * scale
	light.omni_range = 15.0 * scale
	light.omni_attenuation = 1.5
	container.add_child(light)

	_add_cleanup_timer(container, 2.0)

	return container

func _create_shield_ripple(color: Color) -> Node3D:
	var container := Node3D.new()
	container.name = "ShieldRipple"

	# Expanding ring particles
	var particles := GPUParticles3D.new()
	particles.name = "Ripple"
	particles.amount = 32
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.emitting = true
	particles.one_shot = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.BACK
	mat.spread = 5.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3.ZERO
	mat.color = color
	mat.color_ramp = _create_fade_ramp_texture(color)
	mat.scale_min = 0.03
	mat.scale_max = 0.1
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh

	container.add_child(particles)

	# Shield flash light
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = 5.0
	light.omni_attenuation = 1.0
	container.add_child(light)

	_add_cleanup_timer(container, 0.8)

	return container

# ==============================================================================
# Internal: Bio-shader decal / dissolve factories
# ==============================================================================

## Spawns a flat bio-impact burn decal as a child of the impact VFX container,
## oriented to the surface normal. The decal uses bio_impact_burn.gdshader and
## animates impact_age so the energy discharge ripple fades over time. Null-safe:
## no-ops if the shader isn't registered (headless / missing asset).
func _attach_impact_burn_decal(parent: Node3D, normal: Vector3, damage: float, energy_color: Color) -> void:
	var shader: Shader = ShaderRegistry.get_shader(ShaderRegistry.ID_IMPACT_BURN)
	if shader == null:
		return
	var n: Vector3 = normal
	if n.length_squared() < 0.001:
		n = Vector3.UP
	n = n.normalized()

	var decal := MeshInstance3D.new()
	decal.name = "BioImpactBurnDecal"
	# Small flat quad lying in the XY plane (PlaneMesh default faces +Y); we
	# orient it so its +Y axis aligns with the surface normal.
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.6, 1.6)
	quad.material = null
	decal.mesh = quad
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = shader
	# impact_point is object-space; the decal is centered on the hit so use origin.
	mat.set_shader_parameter("impact_point", Vector3.ZERO)
	mat.set_shader_parameter("impact_age", 0.0)
	mat.set_shader_parameter("impact_strength", clampf(damage / 25.0, 0.3, 3.0))
	mat.set_shader_parameter("impact_radius", 1.4)
	# Tint the discharge to the weapon/impact energy color for visual cohesion.
	mat.set_shader_parameter("discharge_color", energy_color)

	decal.material_override = mat
	parent.add_child(decal)

	# Orient the decal flat against the surface (PlaneMesh +Y → normal).
	if n != Vector3.UP:
		decal.look_at(decal.global_position + n, Vector3.UP)
	else:
		decal.rotation = Vector3.ZERO

	# Animate impact_age so the ripple expands and the scorch fades. The shader's
	# discharge_decay uniform drives the fade; we just advance time.
	var tween := parent.create_tween()
	_track_tween(decal, tween)
	tween.tween_method(
		func(age: float) -> void:
			if is_instance_valid(mat):
				mat.set_shader_parameter("impact_age", age),
		0.0, 3.0, 1.0).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(func() -> void: _untrack_tween(decal))

## Tracks a tween keyed by its associated node for explicit cleanup.
func _track_tween(node: Node, tween: Tween) -> void:
	_active_tweens[node.get_instance_id()] = tween

## Removes a tween from tracking (called on tween.finished).
func _untrack_tween(node: Node) -> void:
	_active_tweens.erase(node.get_instance_id())

## Kills and clears all tweens associated with the given node. Call before queue_free.
func cleanup_tweens_for_node(node: Node) -> void:
	var id := node.get_instance_id()
	if _active_tweens.has(id):
		var tween: Tween = _active_tweens[id]
		if is_instance_valid(tween):
			tween.kill()
		_active_tweens.erase(id)

## Applies the bio_dissolve shader to [param target_mesh] and animates an organic
## disintegration from solid → gone over [param duration] seconds. The mesh's
## material_override is replaced with the dissolve material; the caller is
## responsible for freeing the owning node after the animation completes.
## Null-safe: no-ops if the shader isn't registered.
func spawn_dissolve(target_mesh: MeshInstance3D, color: Color, duration: float = 1.5) -> void:
	if target_mesh == null or not is_instance_valid(target_mesh):
		return
	var shader: Shader = ShaderRegistry.get_shader(ShaderRegistry.ID_DISSOLVE)
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("dissolve_amount", 0.0)
	mat.set_shader_parameter("base_color", Color(
		color.r * 0.25, color.g * 0.4, color.b * 0.35, 1.0))
	mat.set_shader_parameter("edge_color_inner", color)
	mat.set_shader_parameter("edge_color_outer", Color(1.0, 0.05, 0.45, 1.0))
	target_mesh.material_override = mat
	# Disable shadow casting during dissolve so the fading hull doesn't leave
	# hard shadow pops as it disintegrates.
	target_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := target_mesh.create_tween()
	_track_tween(target_mesh, tween)
	tween.tween_property(mat, "shader_parameter/dissolve_amount", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(func() -> void: _untrack_tween(target_mesh))

# ==============================================================================
# Internal: Helpers
# ==============================================================================

## Returns the Juicee autoload node if present (dynamic lookup so this script
## parses without the singleton registered). Returns null in headless/test runs.
func _get_juicee() -> Node:
	if _juicee_node and is_instance_valid(_juicee_node):
		return _juicee_node
	var root := Engine.get_main_loop() as SceneTree
	if root and root.root and root.root.has_node("Juicee"):
		_juicee_node = root.root.get_node("Juicee")
		return _juicee_node
	return null

## Fire Juicee combat-impact juice (3D shake + hit-stop + FOV punch) scaled by
## the hit's damage. Heavy hits and hull breaches get a brief hit-stop for weight.
## No-ops when Juicee is unavailable.
func _trigger_combat_juice(damage: float, hit_shield: bool) -> void:
	var juicee: Node = _get_juicee()
	if juicee == null:
		return
	var intensity: float = clampf(damage / 50.0, 0.1, 1.0)
	juicee.call("shake_camera_3d", self, 0.04 + intensity * 0.18, 0.15 + intensity * 0.15)
	# Hit-stop only on weighty impacts (big damage or hull breach) to avoid
	# constant time freezes during rapid-fire combat.
	if intensity >= 0.6 and not hit_shield:
		juicee.call("hit_stop", self, 0.03 + intensity * 0.04, 0.0)
	juicee.call("fov_3d", self, -2.0 - intensity * 5.0, 0.2 + intensity * 0.15)

func _create_fade_ramp_texture(color: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

func _create_explosion_ramp_texture(color: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 0.8, 1.0))  # White-hot core
	grad.set_color(1, Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.0))  # Faded smoke
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

func _add_cleanup_timer(node: Node, delay: float) -> void:
	var timer := Timer.new()
	timer.name = "CleanupTimer"
	timer.wait_time = delay
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free()
	)
	node.add_child(timer)
