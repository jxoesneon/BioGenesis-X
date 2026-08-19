# res://scripts/BioPlasmaProjectile.gd
# ==============================================================================
# BioGenesis-X - High-Velocity Bio-Plasma Projectile (AAA+ Jolt Physics Integrated)
# ==============================================================================
@tool
class_name BioPlasmaProjectile
extends Area3D

var direction: Vector3 = Vector3.FORWARD
var speed: float = 200.0
var damage: float = 25.0
var lifetime: float = 3.0

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(p_dir: Vector3, p_speed: float, p_damage: float, p_life: float) -> void:
	direction = p_dir.normalized()
	speed = p_speed
	damage = p_damage
	lifetime = p_life
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return

	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return

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

	# 3. Damage application
	if target.has_method("take_damage"):
		target.call("take_damage", damage)
	elif is_instance_valid(target.get_parent()) and target.get_parent().has_method("take_damage"):
		target.get_parent().call("take_damage", damage)

	# Audio Telemetry: Impact Detonation
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_shield_impact()

	queue_free()
