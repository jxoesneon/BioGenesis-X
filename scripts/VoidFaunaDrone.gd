# res://scripts/VoidFaunaDrone.gd
# ==============================================================================
# BioGenesis-X - Void-Fauna Drone (AAA+ AI State Machine + Jolt Physics)
# ==============================================================================
@tool
class_name VoidFaunaDrone
extends CharacterBody3D

## AI behavior states — mixed scaling: passive patrols, aggressive hunters, tactical
enum AIState {
	PATROL,    ## Orbital patrol around base position, passive unless provoked
	CHASE,     ## Pursuing player after agro or hostile aggression metadata
	ATTACK,    ## In firing range, shooting at player
	FLEE,      ## Retreating when critically damaged
	DEAD,      ## Death state — explosion plays, then queue_free
}

## Drone class variants — different stats and behaviors for combat variety
enum DroneClass {
	SCOUT,     ## Fast, fragile, passive patrol, flees when hit
	HUNTER,    ## Aggressive chaser, medium health, fires bio-plasma
	SENTINEL,  ## Slow, high health, defensive, fires in bursts
	SWARMER,   ## Very fast, very fragile, swarm tactics, melee only
}

@export var drone_class: DroneClass = DroneClass.SCOUT

# Health & Shield
var health: float = 80.0
var max_health: float = 80.0
var shield: float = 0.0
var max_shield: float = 0.0
var shield_regen_rate: float = 5.0
var shield_regen_delay: float = 4.0
var _shield_regen_timer: float = 0.0

# Movement
var base_position: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var orbit_speed: float = 0.3
var move_radius: float = 25.0
var external_velocity: Vector3 = Vector3.ZERO
var chase_speed: float = 30.0
var flee_speed: float = 45.0

# AI State
var ai_state: AIState = AIState.PATROL
var _state_timer: float = 0.0
var _aggression: float = 0.0  ## From noise field metadata, 0=passive, 1=hostile

# Combat — enemy offensive capabilities
var _fire_cooldown: float = 0.0
var _fire_rate: float = 1.5
var _weapon_damage: float = 12.0
var _weapon_range: float = 120.0
var _weapon_speed: float = 80.0
var _projectile_color: Color = Color(1.0, 0.3, 0.1, 1.0)
var _burst_count: int = 0
var _burst_shots_remaining: int = 0
var _burst_cooldown: float = 0.0

# Targeting
var _player_ref: Node3D = null
var _weapon_system_ref: Node = null

# Detection ranges
var _detect_range: float = 85.0
var _attack_range: float = 70.0
var _disengage_range: float = 140.0
var _flee_health_threshold: float = 20.0

func _ready() -> void:
	base_position = global_position
	orbit_angle = randf_range(0.0, TAU)
	add_to_group("void_fauna")
	add_to_group("targets")
	_apply_class_stats()

func _apply_class_stats() -> void:
	match drone_class:
		DroneClass.SCOUT:
			max_health = 60.0
			health = max_health
			max_shield = 0.0
			shield = 0.0
			orbit_speed = 0.4
			move_radius = 30.0
			chase_speed = 35.0
			flee_speed = 50.0
			_fire_rate = 2.0
			_weapon_damage = 8.0
			_weapon_range = 80.0
			_detect_range = 70.0
			_flee_health_threshold = 25.0
			_projectile_color = Color(0.3, 1.0, 0.5, 1.0)
		DroneClass.HUNTER:
			max_health = 100.0
			health = max_health
			max_shield = 30.0
			shield = max_shield
			orbit_speed = 0.25
			move_radius = 20.0
			chase_speed = 40.0
			flee_speed = 35.0
			_fire_rate = 1.2
			_weapon_damage = 15.0
			_weapon_range = 120.0
			_detect_range = 100.0
			_attack_range = 90.0
			_flee_health_threshold = 15.0
			_projectile_color = Color(1.0, 0.3, 0.1, 1.0)
		DroneClass.SENTINEL:
			max_health = 180.0
			health = max_health
			max_shield = 80.0
			shield = max_shield
			orbit_speed = 0.15
			move_radius = 15.0
			chase_speed = 20.0
			flee_speed = 25.0
			_fire_rate = 0.8
			_weapon_damage = 20.0
			_weapon_range = 140.0
			_detect_range = 120.0
			_attack_range = 110.0
			_flee_health_threshold = 30.0
			_burst_count = 3
			_projectile_color = Color(1.0, 0.6, 0.0, 1.0)
		DroneClass.SWARMER:
			max_health = 35.0
			health = max_health
			max_shield = 0.0
			shield = 0.0
			orbit_speed = 0.6
			move_radius = 40.0
			chase_speed = 55.0
			flee_speed = 60.0
			_fire_rate = 999.0  # No ranged attack — melee only
			_weapon_damage = 10.0
			_weapon_range = 0.0
			_detect_range = 90.0
			_attack_range = 8.0  # Melee range
			_flee_health_threshold = 10.0
			_projectile_color = Color(0.8, 0.2, 1.0, 1.0)

func _physics_process(delta: float) -> void:
	if ai_state == AIState.DEAD:
		return

	# Cache player and weapon system references
	_cache_references()

	# Shield regeneration
	if shield < max_shield:
		if _shield_regen_timer > 0.0:
			_shield_regen_timer = maxf(0.0, _shield_regen_timer - delta)
		else:
			shield = minf(max_shield, shield + shield_regen_rate * delta)

	# Update AI state machine
	_update_ai_state(delta)

	# Execute behavior based on state
	match ai_state:
		AIState.PATROL:
			_patrol_behavior(delta)
		AIState.CHASE:
			_chase_behavior(delta)
		AIState.ATTACK:
			_attack_behavior(delta)
		AIState.FLEE:
			_flee_behavior(delta)

	# Dampen external recoil impulse
	external_velocity = external_velocity.lerp(Vector3.ZERO, delta * 4.0)
	velocity += external_velocity
	move_and_slide()
	# Reset velocity after move — we set it fresh each frame
	velocity = velocity.lerp(Vector3.ZERO, delta * 8.0)

func _cache_references() -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		if is_inside_tree() and get_tree():
			var ml := Engine.get_main_loop()
			if ml is SceneTree and ml.root:
				_player_ref = ml.root.find_child("FlightController", true, false) as Node3D
	if not _weapon_system_ref or not is_instance_valid(_weapon_system_ref):
		if is_inside_tree() and get_tree():
			var ml := Engine.get_main_loop()
			if ml is SceneTree and ml.root:
				_weapon_system_ref = ml.root.find_child("WeaponSystem", true, false)

func _update_ai_state(delta: float) -> void:
	_state_timer += delta

	if not _player_ref or not is_instance_valid(_player_ref):
		ai_state = AIState.PATROL
		return

	var dist: float = global_position.distance_to(_player_ref.global_position)

	# State transitions
	match ai_state:
		AIState.PATROL:
			# Aggressive drones (from noise field) detect at longer range
			var effective_detect: float = _detect_range * (0.5 + _aggression * 0.8)
			if dist < effective_detect and (_aggression > 0.3 or health < max_health):
				ai_state = AIState.CHASE
				_state_timer = 0.0
		AIState.CHASE:
			if dist < _attack_range:
				ai_state = AIState.ATTACK
				_state_timer = 0.0
			elif dist > _disengage_range:
				ai_state = AIState.PATROL
				_state_timer = 0.0
			# Flee if critically damaged
			if health < _flee_health_threshold and drone_class != DroneClass.SWARMER:
				ai_state = AIState.FLEE
				_state_timer = 0.0
		AIState.ATTACK:
			if dist > _attack_range * 1.3:
				ai_state = AIState.CHASE
				_state_timer = 0.0
			# Flee if critically damaged
			if health < _flee_health_threshold:
				ai_state = AIState.FLEE
				_state_timer = 0.0
		AIState.FLEE:
			if dist > _disengage_range * 1.5:
				ai_state = AIState.PATROL
				_state_timer = 0.0
			# Stop fleeing if shield recharged
			if shield > max_shield * 0.5 and health > _flee_health_threshold * 1.5:
				ai_state = AIState.CHASE
				_state_timer = 0.0

	# Notify WeaponSystem of targeting
	if _weapon_system_ref and is_instance_valid(_weapon_system_ref):
		var targeting: bool = ai_state == AIState.CHASE or ai_state == AIState.ATTACK
		_weapon_system_ref.set_targeted_by_enemy(self, targeting)

func _patrol_behavior(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	var target_pos: Vector3 = base_position + Vector3(
		cos(orbit_angle) * move_radius,
		sin(orbit_angle * 2.0) * 8.0,
		sin(orbit_angle) * move_radius
	)
	_move_toward(target_pos, delta, 2.0)
	_look_at_smooth(target_pos)

func _chase_behavior(delta: float) -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	var target_pos: Vector3 = _player_ref.global_position
	_move_toward(target_pos, delta, chase_speed)
	_look_at_smooth(target_pos)

func _attack_behavior(delta: float) -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	# Maintain attack distance — strafe around player
	var to_player: Vector3 = _player_ref.global_position - global_position
	var desired_dist: float = _attack_range * 0.7
	var strafe_dir: Vector3 = to_player.normalized()
	# Perpendicular strafe vector
	var strafe_perp: Vector3 = strafe_dir.cross(Vector3.UP).normalized()
	var strafe_offset: Vector3 = strafe_perp * sin(_state_timer * 1.5) * 15.0

	var target_pos: Vector3 = _player_ref.global_position - strafe_dir * desired_dist + strafe_offset
	_move_toward(target_pos, delta, chase_speed * 0.7)
	_look_at_smooth(_player_ref.global_position)

	# Fire at player
	_handle_weapon_firing(delta)

func _flee_behavior(delta: float) -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		ai_state = AIState.PATROL
		return
	# Move away from player
	var away_dir: Vector3 = (global_position - _player_ref.global_position).normalized()
	var target_pos: Vector3 = global_position + away_dir * 100.0
	_move_toward(target_pos, delta, flee_speed)
	_look_at_smooth(target_pos)

func _handle_weapon_firing(delta: float) -> void:
	# Burst fire logic for Sentinels
	if _burst_count > 0:
		if _burst_shots_remaining > 0:
			_burst_cooldown -= delta
			if _burst_cooldown <= 0.0:
				_fire_at_player()
				_burst_shots_remaining -= 1
				_burst_cooldown = 0.15
			return
		else:
			_fire_cooldown -= delta
			if _fire_cooldown <= 0.0:
				_burst_shots_remaining = _burst_count
				_burst_cooldown = 0.0
				_fire_cooldown = _fire_rate
			return

	# Standard fire
	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire_at_player()
		_fire_cooldown = _fire_rate

func _fire_at_player() -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	if not is_inside_tree() or not get_tree():
		return

	var dir: Vector3 = (_player_ref.global_position - global_position).normalized()

	# Swarmer melee — no projectile, just damage on proximity
	if drone_class == DroneClass.SWARMER:
		var dist: float = global_position.distance_to(_player_ref.global_position)
		if dist < _attack_range and _player_ref.has_method("take_damage"):
			_player_ref.call("take_damage", _weapon_damage)
		return

	# Ranged: spawn enemy projectile
	var proj := BioPlasmaProjectile.new()
	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position + dir * 2.0
	proj.setup(dir, _weapon_speed, _weapon_damage, 4.0)
	proj.setup_visuals(_projectile_color, 0.35, false)
	proj.damage_type = BioPlasmaProjectile.DamageType.ENERGY

	# Muzzle flash
	CombatVFX.spawn_muzzle_flash(global_position + dir * 2.0, dir, _projectile_color)

	# Audio
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_laser_fire(0.0)

func _move_toward(target: Vector3, delta: float, speed: float) -> void:
	var to_target: Vector3 = target - global_position
	var dist: float = to_target.length()
	if dist > 0.1:
		var desired_velocity: Vector3 = to_target.normalized() * minf(speed, dist / delta)
		velocity = desired_velocity

func _look_at_smooth(target: Vector3) -> void:
	if global_position.is_equal_approx(target):
		return
	var dir: Vector3 = (target - global_position).normalized()
	if abs(dir.dot(Vector3.UP)) < 0.99:
		look_at(target, Vector3.UP)

func apply_impulse(impulse: Vector3, _pos: Vector3 = Vector3.ZERO) -> void:
	var mass: float = 1500.0
	external_velocity += impulse / mass

func take_damage(amount: float) -> void:
	var remaining: float = amount
	# Shield absorbs first
	if shield > 0.0:
		var absorbed: float = minf(shield, remaining)
		shield = maxf(0.0, shield - absorbed)
		remaining -= absorbed
		_shield_regen_timer = shield_regen_delay
		# Shield hit ripple
		CombatVFX.spawn_shield_ripple(global_position, -global_transform.basis.z, _projectile_color)

	# Remaining damage to health
	if remaining > 0.0:
		health -= remaining
		_flash_hit()

	# Audio
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		if ml.root.has_node("BioAudioSynth"):
			ml.root.get_node("BioAudioSynth").play_creature_vocalization(1.8)
		if _weapon_system_ref and is_instance_valid(_weapon_system_ref):
			_weapon_system_ref.notify_enemy_hit(self)

	# Aggro on damage — passive drones become hostile when shot
	if ai_state == AIState.PATROL:
		_aggression = max(_aggression, 0.5)

	if health <= 0.0:
		_on_destroyed()

func apply_spore_slow(_factor: float, _duration: float) -> void:
	orbit_speed = maxf(0.05, orbit_speed * 0.5)
	chase_speed = maxf(5.0, chase_speed * 0.5)

func _flash_hit() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh and mesh.material_override:
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		mat.emission_energy_multiplier = 8.0
		if is_inside_tree() and get_tree():
			await get_tree().create_timer(0.1).timeout
			if is_instance_valid(self) and is_instance_valid(mat):
				mat.emission_energy_multiplier = 2.0

func _on_destroyed() -> void:
	if ai_state == AIState.DEAD:
		return
	ai_state = AIState.DEAD
	# Spawn explosion VFX
	CombatVFX.spawn_explosion(global_position, _projectile_color, 1.2)
	# Organic dissolve: the drone's bio-mesh disintegrates instead of just
	# popping out of existence. Null-safe — falls back to instant free if the
	# dissolve shader or mesh is unavailable.
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	var dissolved: bool = false
	if mesh and is_instance_valid(mesh):
		CombatVFX.spawn_dissolve(mesh, _projectile_color, 1.4)
		dissolved = true
	# Register kill in combat stats
	CombatStats.register_kill(drone_class_to_string())
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		if ml.root.has_node("BioAudioSynth"):
			var audio = ml.root.get_node("BioAudioSynth")
			audio.play_shield_impact()
			audio.play_creature_vocalization(0.6)
		if _weapon_system_ref and is_instance_valid(_weapon_system_ref):
			_weapon_system_ref.set_targeted_by_enemy(self, false)
	if dissolved and is_inside_tree() and get_tree():
		# Let the dissolve animation play, then free the corpse.
		await get_tree().create_timer(1.5).timeout
	queue_free()

func drone_class_to_string() -> String:
	match drone_class:
		DroneClass.SCOUT: return "SCOUT"
		DroneClass.HUNTER: return "HUNTER"
		DroneClass.SENTINEL: return "SENTINEL"
		DroneClass.SWARMER: return "SWARMER"
		_: return "UNKNOWN"

## Set aggression from noise field metadata (called by ChunkStreamManager)
func set_aggression(value: float) -> void:
	_aggression = clampf(value, 0.0, 1.0)
