# res://scripts/BioPlasmaProjectile.gd
# ==============================================================================
# BioGenesis-X - High-Velocity Bio-Plasma Projectile (AAA+ Jolt Physics Integrated)
# ==============================================================================
@tool
class_name BioPlasmaProjectile
extends Area3D

## Damage types — different resistances and visual feedback per type
enum DamageType { KINETIC, ENERGY, BIOLOGICAL, THERMAL }

var direction: Vector3 = Vector3.FORWARD
var speed: float = 200.0
var damage: float = 25.0
var lifetime: float = 3.0
var damage_type: DamageType = DamageType.ENERGY

## Visual properties — set by weapon type
var projectile_color: Color = Color(0.0, 1.0, 0.75, 1.0)
var projectile_radius: float = 0.35
var is_missile: bool = false

## Hit marker signal — emitted on impact, consumed by FlightHUDUI
signal projectile_hit(hit_point: Vector3, hit_shield: bool, target_killed: bool)

var _mesh_instance: MeshInstance3D
var _light: OmniLight3D
var _trail_max_points: int = 12
var _age: float = 0.0

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_create_visuals()

func _create_visuals() -> void:
	# Glowing core mesh
	if not _mesh_instance:
		_mesh_instance = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = projectile_radius
		sphere.height = projectile_radius * 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = projectile_color
		mat.emission_energy_multiplier = 3.0
		mat.emission = projectile_color
		mat.glow_on = true
		mat.glow_blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = mat
		_mesh_instance.mesh = sphere
		add_child(_mesh_instance)

	# Point light for local illumination
	if not _light:
		_light = OmniLight3D.new()
		_light.light_color = projectile_color
		_light.light_energy = 2.5
		_light.omni_range = 8.0
		_light.omni_attenuation = 1.5
		add_child(_light)

func setup(p_dir: Vector3, p_speed: float, p_damage: float, p_life: float) -> void:
	direction = p_dir.normalized()
	speed = p_speed
	damage = p_damage
	lifetime = p_life
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup_visuals(p_color: Color, p_radius: float, p_is_missile: bool) -> void:
	projectile_color = p_color
	projectile_radius = p_radius
	is_missile = p_is_missile
	if is_missile:
		_trail_max_points = 20
	else:
		_trail_max_points = 10

func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return

	_age += delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return

	# Animate glow pulse
	if _mesh_instance and is_instance_valid(_mesh_instance):
		var pulse: float = 1.0 + sin(_age * 30.0) * 0.15
		_mesh_instance.scale = Vector3.ONE * pulse
	if _light and is_instance_valid(_light):
		_light.light_energy = 2.0 + sin(_age * 25.0) * 0.5

	var prev_pos: Vector3 = global_position
	var move_vec: Vector3 = direction * speed * delta
	var next_pos: Vector3 = prev_pos + move_vec

	# Swept continuous raycasting to prevent tunneling at 200+ m/s in JoltPhysics3D
	if is_inside_tree() and get_world_3d():
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		if space_state:
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(prev_pos, next_pos)
			query.collide_with_areas = true
			query.collide_with_bodies = true
			query.exclude = [get_rid()]

			var hit_dict: Dictionary = space_state.intersect_ray(query)
			if not hit_dict.is_empty():
				var hit_pos: Vector3 = hit_dict.get("position", next_pos)
				global_position = hit_pos
				var collider: Object = hit_dict.get("collider")
				if collider is Node:
					_apply_impact(collider as Node, hit_pos)
				else:
					_spawn_impact_particles(hit_pos, false)
					queue_free()
				return

	# Overlapping bodies & areas fallback check
	for b: Node3D in get_overlapping_bodies():
		if is_instance_valid(b) and b != self:
			_apply_impact(b, global_position)
			return

	for a: Area3D in get_overlapping_areas():
		if is_instance_valid(a) and a != self:
			_apply_impact(a, global_position)
			return

	# Distance proximity check fallback for high-speed bio-plasma bolts
	if is_inside_tree() and get_tree():
		for target: Node in get_tree().get_nodes_in_group("targets"):
			if is_instance_valid(target) and target is Node3D and target != self:
				var t3d: Node3D = target as Node3D
				if global_position.distance_to(t3d.global_position) < 3.5:
					_apply_impact(t3d, global_position)
					return

	global_position = next_pos

func _on_body_entered(body: Node) -> void:
	_apply_impact(body, global_position)

func _on_area_entered(area: Area3D) -> void:
	_apply_impact(area, global_position)

func _apply_impact(target: Node, hit_point: Vector3 = Vector3.ZERO) -> void:
	if is_queued_for_deletion():
		return

	if not is_instance_valid(target):
		_spawn_impact_particles(hit_point, false)
		queue_free()
		return

	var impulse: Vector3 = direction * (damage * 2000.0)
	var impulse_applied: bool = false

	# 1. Direct target impulse handling
	if target.has_method("apply_impulse"):
		var contact_offset: Vector3 = Vector3.ZERO
		if target is Node3D and hit_point != Vector3.ZERO:
			contact_offset = (target as Node3D).global_transform.affine_inverse() * hit_point
		target.call("apply_impulse", impulse, contact_offset)
		impulse_applied = true
	elif target is RigidBody3D:
		var rb: RigidBody3D = target as RigidBody3D
		if not rb.freeze:
			rb.apply_central_impulse(impulse)
			impulse_applied = true
	elif target is CharacterBody3D:
		var cb: CharacterBody3D = target as CharacterBody3D
		var mass: float = 100.0
		if cb.get("vessel_mass_kg") != null and float(cb.get("vessel_mass_kg")) > 0.0:
			mass = float(cb.get("vessel_mass_kg"))
		cb.velocity += impulse / mass
		impulse_applied = true

	# 2. Parent target fallback impulse handling
	if not impulse_applied and is_instance_valid(target.get_parent()):
		var parent: Node = target.get_parent()
		if parent.has_method("apply_impulse"):
			parent.call("apply_impulse", impulse, global_position)
		elif parent is RigidBody3D:
			var prb: RigidBody3D = parent as RigidBody3D
			if not prb.freeze:
				prb.apply_central_impulse(impulse)
		elif parent is CharacterBody3D:
			var pcb: CharacterBody3D = parent as CharacterBody3D
			var pmass: float = 100.0
			if pcb.get("vessel_mass_kg") != null and float(pcb.get("vessel_mass_kg")) > 0.0:
				pmass = float(pcb.get("vessel_mass_kg"))
			pcb.velocity += impulse / pmass

	# 3. Determine if target has shield (for hit marker color)
	var hit_shield: bool = false
	var target_killed: bool = false

	# 4. Damage application
	if target.has_method("take_damage"):
		# Check if target has shield before calling take_damage
		if "bio_shield" in target and target.get("bio_shield") > 0.0:
			hit_shield = true
		target.call("take_damage", damage)
		# Check if killed
		if "health" in target and float(target.get("health")) <= 0.0:
			target_killed = true
		elif "hull_integrity" in target and float(target.get("hull_integrity")) <= 0.0:
			target_killed = true
	elif is_instance_valid(target.get_parent()) and target.get_parent().has_method("take_damage"):
		var parent: Node = target.get_parent()
		if "bio_shield" in parent and parent.get("bio_shield") > 0.0:
			hit_shield = true
		parent.call("take_damage", damage)
		if "hull_integrity" in parent and float(parent.get("hull_integrity")) <= 0.0:
			target_killed = true

	# 5. Visual impact particles
	_spawn_impact_particles(hit_point, hit_shield)

	# 6. Hit marker signal for HUD
	projectile_hit.emit(hit_point, hit_shield, target_killed)

	# 7. Notify HUD for hit markers
	_notify_hit_marker(hit_shield, target_killed)

	# 8. Register hit in combat stats
	CombatStats.register_projectile_hit()
	CombatStats.register_damage_dealt(damage)

	# Audio Telemetry: Impact Detonation
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_shield_impact()

	queue_free()

func _notify_hit_marker(hit_shield: bool, target_killed: bool) -> void:
	if not is_inside_tree() or not get_tree():
		return
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		# Find the FlightHUDUI and trigger hit marker
		for hud in get_tree().get_nodes_in_group("flight_hud"):
			if is_instance_valid(hud) and hud.has_method("_on_projectile_hit"):
				hud.call("_on_projectile_hit", hit_shield, target_killed)
				break

func _spawn_impact_particles(pos: Vector3, hit_shield: bool) -> void:
	if not is_inside_tree() or not get_tree():
		return
	var fx := CombatVFX.spawn_impact(pos, projectile_color, hit_shield, damage)
	if fx and get_tree().current_scene:
		get_tree().current_scene.add_child(fx)
