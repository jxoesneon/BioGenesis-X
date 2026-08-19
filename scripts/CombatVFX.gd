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

## Spawn an impact effect at the given world position.
## Returns the spawned Node3D (or null if budget exceeded).
func spawn_impact(pos: Vector3, color: Color, hit_shield: bool, damage: float) -> Node3D:
	var root := Engine.get_main_loop() as SceneTree
	if not root or not root.current_scene:
		return null
	var vfx: Node3D = _create_impact_node(color, hit_shield, damage)
	vfx.global_position = pos
	root.current_scene.add_child(vfx)
	# Juicee impact juice: 3D camera shake + hit-stop + FOV punch, scaled by damage.
	_trigger_combat_juice(damage, hit_shield)
	return vfx

## Spawn a muzzle flash at the given world position and direction.
func spawn_muzzle_flash(pos: Vector3, direction: Vector3, color: Color) -> Node3D:
	var root := Engine.get_main_loop() as SceneTree
	if not root or not root.current_scene:
		return null
	var flash := _create_muzzle_flash(color)
	flash.global_position = pos
	flash.look_at(pos + direction, Vector3.UP)
	root.current_scene.add_child(flash)
	return flash

## Spawn an explosion at the given world position. Used for enemy death,
## asteroid destruction, and large impacts.
func spawn_explosion(pos: Vector3, color: Color, scale: float = 1.0) -> Node3D:
	var root := Engine.get_main_loop() as SceneTree
	if not root or not root.current_scene:
		return null
	var explosion := _create_explosion(color, scale)
	explosion.global_position = pos
	root.current_scene.add_child(explosion)
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
	var ripple := _create_shield_ripple(color)
	ripple.global_position = pos
	ripple.look_at(pos + normal, Vector3.UP)
	root.current_scene.add_child(ripple)
	return ripple

# ==============================================================================
# Internal: Particle node factories
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
