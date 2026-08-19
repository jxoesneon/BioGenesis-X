# ==============================================================================
# WeaponSystem.gd - BioGenesis-X Tactical Weapons & Combat Director
# Pumilio Studios & Ciel Audio Architecture Division
# ==============================================================================
# Controls Bio-Plasma Disruptors, Homing Plasma Missiles, Bio-Spore Dispensers,
# Venting Spiracles, and Combat State Tracking.
#
# TARGETING AUDIO RULE SPECIFICATION:
# - Targeting sound ONLY activates when BOTH:
#   A) Plasma Missiles are the selected weapon, AND
#   B) Active Combat is engaged (AI fauna targeting player OR player hits enemy).
# ==============================================================================

@tool
class_name WeaponSystem
extends Node3D

const BioPlasmaProjectileClass = preload("res://scripts/BioPlasmaProjectile.gd")
const BioSporeCloudClass = preload("res://scripts/BioSporeCloud.gd")

signal weapon_fired(weapon_type: String, heat_generated: float)
signal heat_updated(current_heat: float, max_heat: float)
signal overheat_triggered(is_overheated: bool)
signal lock_on_state_changed(state: String, target: Node3D)
signal weapon_selected(new_weapon_type: int)
signal combat_state_changed(is_in_combat: bool)

enum LockState { NONE, ACQUIRING, LOCKED }
enum WeaponType {
	DISRUPTOR,       ## Rapid bio-plasma lasers (Straight fire)
	PLASMA_MISSILES, ## Homing bio-plasma lock-on missiles
	SPORE_CLOUD,     ## Defensive bio-spore cloud dispenser
	EMP_BURST,       ## Area-of-effect energy pulse that strips enemy shields
	BEAM_EMITTER,    ## Continuous hitscan beam weapon
	MINE_DEPLOYER    ## Proximity mine deployed behind the ship
}

@export_group("Active Weapon Selection")
## Currently active weapon system
@export var selected_weapon: WeaponType = WeaponType.DISRUPTOR

@export_group("Primary Fire - Bio-Plasma Disruptor")
@export var primary_fire_rate: float = 0.15 # seconds between shots
@export var primary_damage: float = 25.0
@export var primary_speed: float = 220.0
@export var primary_lifetime: float = 3.0
@export var primary_heat_cost: float = 7.0

@export_group("Plasma Missiles - Heavy Homing Bio-Warheads")
@export var missile_fire_rate: float = 0.45
@export var missile_damage: float = 75.0
@export var missile_speed: float = 180.0
@export var missile_lifetime: float = 4.5
@export var missile_heat_cost: float = 22.0

@export_group("Secondary Fire - Bio-Spore Cloud")
@export var secondary_fire_cooldown: float = 2.0
@export var spore_cloud_duration: float = 6.0
@export var spore_cloud_radius: float = 12.0
@export var spore_cloud_dps: float = 15.0
@export var secondary_heat_cost: float = 30.0

@export_group("EMP Burst - Shield-Stripping Area Pulse")
@export var emp_fire_cooldown: float = 3.0
@export var emp_damage: float = 10.0
@export var emp_shield_bonus_damage: float = 40.0
@export var emp_heat_cost: float = 40.0
@export var emp_max_radius: float = 30.0
@export var emp_expand_speed: float = 60.0

@export_group("Beam Emitter - Continuous Hitscan Lance")
@export var beam_tick_interval: float = 0.02
@export var beam_damage_per_tick: float = 8.0
@export var beam_heat_cost: float = 3.0
@export var beam_range: float = 500.0

@export_group("Mine Deployer - Proximity Explosive Ordnance")
@export var mine_fire_cooldown: float = 1.5
@export var mine_damage: float = 60.0
@export var mine_heat_cost: float = 25.0
@export var mine_trigger_radius: float = 15.0

@export_group("Heat & Spiracle Venting")
@export var max_heat: float = 100.0
@export var heat_dissipation_rate: float = 25.0 # heat units per second
@export var overheat_cooldown_threshold: float = 20.0
@export var spiracle_vent_particles: GPUParticles3D

@export_group("Targeting & Lock-On")
@export var lock_on_range: float = 350.0
@export var lock_on_acquire_time: float = 0.9 # seconds required to complete lock
@export var lock_on_fov_angle: float = 28.0 # degrees

# Node References & Muzzle Points
@export var save_system: Node
@export var muzzle_left: Node3D
@export var muzzle_right: Node3D

# Internal Weapon State
var current_heat: float = 0.0
var is_overheated: bool = false
var primary_cooldown_timer: float = 0.0
var secondary_cooldown_timer: float = 0.0
var emp_cooldown_timer: float = 0.0
var mine_cooldown_timer: float = 0.0
var beam_tick_timer: float = 0.0
var current_muzzle_toggle: bool = false

# Beam visual node (lazily created, reused across ticks)
var _beam_visual: MeshInstance3D

var lock_state: LockState = LockState.NONE
var current_target: Node3D = null
var lock_timer: float = 0.0

# Active Combat State Tracking
var is_in_combat: bool = false
var combat_timer: float = 0.0
const COMBAT_DURATION: float = 9.0
var targeting_enemies: Array[Node3D] = []

# Input debounce timers
var _key_switch_debounce: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	if is_instance_valid(save_system):
		var save_sys := save_system
		if save_sys.has_method("get_upgrade"):
			primary_damage = save_sys.get_upgrade("primary_damage", primary_damage)
			max_heat = save_sys.get_upgrade("max_heat", max_heat)
			heat_dissipation_rate = save_sys.get_upgrade("heat_dissipation_rate", heat_dissipation_rate)
			
	if not muzzle_left:
		muzzle_left = get_node_or_null("MuzzleLeft")
	if not muzzle_right:
		muzzle_right = get_node_or_null("MuzzleRight")


func _process(delta: float) -> void:
	if _key_switch_debounce > 0.0:
		_key_switch_debounce -= delta

	_update_cooldowns_and_heat(delta)
	_update_combat_state(delta)
	_update_targeting(delta)
	_update_beam(delta)
	_handle_input()


# ==============================================================================
# Combat State Management
# ==============================================================================

## Called when an AI void fauna / hostile drone targets or loses the player
func set_targeted_by_enemy(enemy: Node3D, targeted: bool) -> void:
	# Purge invalid references
	var valid_enemies: Array[Node3D] = []
	for e in targeting_enemies:
		if is_instance_valid(e):
			valid_enemies.append(e)
	targeting_enemies = valid_enemies

	if targeted and is_instance_valid(enemy):
		if not targeting_enemies.has(enemy):
			targeting_enemies.append(enemy)
	elif not targeted:
		targeting_enemies.erase(enemy)

	_evaluate_combat_state()

## Called when the player shoots and hits an enemy
func notify_enemy_hit(_enemy: Node3D = null) -> void:
	combat_timer = COMBAT_DURATION
	_evaluate_combat_state()

func _update_combat_state(delta: float) -> void:
	if combat_timer > 0.0:
		combat_timer -= delta
		if combat_timer <= 0.0:
			combat_timer = 0.0
			_evaluate_combat_state()

func _evaluate_combat_state() -> void:
	var prev_combat := is_in_combat
	# Purge dead enemies
	var count := 0
	for e in targeting_enemies:
		if is_instance_valid(e): count += 1
	
	is_in_combat = (combat_timer > 0.0) or (count > 0)
	if is_in_combat != prev_combat:
		combat_state_changed.emit(is_in_combat)
		# Re-evaluate audio lock state upon entering/exiting combat
		_sync_audio_lock_state(_get_current_lock_stage())
		# Notify BioAudioDirector for smooth combat tension transitions
		var ml := Engine.get_main_loop()
		if ml is SceneTree and ml.root and ml.root.has_node("BioAudioDirector"):
			var director = ml.root.get_node("BioAudioDirector")
			if is_in_combat:
				director.transition_to_event("combat_start")
			else:
				director.transition_to_event("combat_end")


# ==============================================================================
# Weapon Switching
# ==============================================================================

func select_weapon(type: WeaponType) -> void:
	if selected_weapon == type:
		return
	selected_weapon = type
	weapon_selected.emit(int(type))
	_play_ui_click()
	_sync_audio_lock_state(_get_current_lock_stage())

func cycle_weapon_next() -> void:
	var next_idx := (int(selected_weapon) + 1) % WeaponType.size()
	select_weapon(next_idx as WeaponType)


func _handle_input() -> void:
	# Weapon Switching Hotkeys (1-6 select weapons directly)
	if _key_switch_debounce <= 0.0:
		if Input.is_key_pressed(KEY_1):
			select_weapon(WeaponType.DISRUPTOR)
			_key_switch_debounce = 0.25
		elif Input.is_key_pressed(KEY_2):
			select_weapon(WeaponType.PLASMA_MISSILES)
			_key_switch_debounce = 0.25
		elif Input.is_key_pressed(KEY_3):
			select_weapon(WeaponType.SPORE_CLOUD)
			_key_switch_debounce = 0.25
		elif Input.is_key_pressed(KEY_4) or Input.is_key_pressed(KEY_X):
			select_weapon(WeaponType.EMP_BURST)
			_key_switch_debounce = 0.25
		elif Input.is_key_pressed(KEY_5) or Input.is_key_pressed(KEY_B):
			select_weapon(WeaponType.BEAM_EMITTER)
			_key_switch_debounce = 0.25
		elif Input.is_key_pressed(KEY_6) or Input.is_key_pressed(KEY_M):
			select_weapon(WeaponType.MINE_DEPLOYER)
			_key_switch_debounce = 0.25
		elif Input.is_key_pressed(KEY_G):
			cycle_weapon_next()
			_key_switch_debounce = 0.25

	# Primary Fire (Fires selected weapon). Beam is handled in _update_beam.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE):
		match selected_weapon:
			WeaponType.DISRUPTOR:
				fire_primary()
			WeaponType.PLASMA_MISSILES:
				fire_plasma_missiles()
			WeaponType.SPORE_CLOUD:
				fire_secondary()
			WeaponType.EMP_BURST:
				fire_emp_burst()
			WeaponType.BEAM_EMITTER:
				pass # Continuous beam handled by _update_beam tick logic
			WeaponType.MINE_DEPLOYER:
				fire_mine()

	# Secondary Fire (Always available shortcut for Spore Cloud)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_C):
		fire_secondary()


# ==============================================================================
# Weapon Firing Implementations
# ==============================================================================

## Primary Fire: Fast Bio-Plasma Disruptors
func fire_primary() -> bool:
	if is_overheated or primary_cooldown_timer > 0.0:
		return false

	primary_cooldown_timer = primary_fire_rate
	_add_heat(primary_heat_cost)
	
	var muzzle := muzzle_left if (current_muzzle_toggle and muzzle_left) else (muzzle_right if muzzle_right else self)
	current_muzzle_toggle = not current_muzzle_toggle

	var proj := _create_bio_plasma_projectile()
	if is_inside_tree() and get_tree() and get_tree().root:
		get_tree().root.add_child(proj)

	var fire_transform := muzzle.global_transform
	proj.global_transform = fire_transform
	var dir := -fire_transform.basis.z.normalized()

	proj.setup(dir, primary_speed, primary_damage, primary_lifetime)
	# Visual: cyan-green glowing bolt for disruptor
	proj.setup_visuals(Color(0.0, 1.0, 0.75, 1.0), 0.3, false)
	proj.damage_type = BioPlasmaProjectile.DamageType.ENERGY

	# Muzzle flash VFX
	CombatVFX.spawn_muzzle_flash(muzzle.global_position, dir, Color(0.0, 1.0, 0.75, 1.0))

	# Audio Telemetry: Bio-Plasma Disruptor Fire
	var pan := -0.6 if muzzle == muzzle_left else 0.6
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_laser_fire(pan)

	weapon_fired.emit("disruptor", primary_heat_cost)
	CombatStats.register_shot_fired()
	return true


## Heavy Homing Bio-Plasma Missiles
func fire_plasma_missiles() -> bool:
	if is_overheated or primary_cooldown_timer > 0.0:
		return false

	primary_cooldown_timer = missile_fire_rate
	_add_heat(missile_heat_cost)

	var muzzle := muzzle_left if (current_muzzle_toggle and muzzle_left) else (muzzle_right if muzzle_right else self)
	current_muzzle_toggle = not current_muzzle_toggle

	var proj := _create_bio_plasma_projectile()
	if is_inside_tree() and get_tree() and get_tree().root:
		get_tree().root.add_child(proj)

	var fire_transform := muzzle.global_transform
	proj.global_transform = fire_transform

	# Homing Vector towards locked target if locked
	var dir := -fire_transform.basis.z.normalized()
	if lock_state == LockState.LOCKED and is_instance_valid(current_target):
		var target_dir := (current_target.global_position - muzzle.global_position).normalized()
		dir = dir.lerp(target_dir, 0.75).normalized()
	elif lock_state == LockState.ACQUIRING and is_instance_valid(current_target):
		var target_dir := (current_target.global_position - muzzle.global_position).normalized()
		dir = dir.lerp(target_dir, 0.35).normalized()

	proj.setup(dir, missile_speed, missile_damage, missile_lifetime)
	# Visual: orange-red glowing missile, larger than disruptor bolt
	proj.setup_visuals(Color(1.0, 0.4, 0.1, 1.0), 0.5, true)
	proj.damage_type = BioPlasmaProjectile.DamageType.THERMAL

	# Muzzle flash VFX — bigger for missiles
	CombatVFX.spawn_muzzle_flash(muzzle.global_position, dir, Color(1.0, 0.4, 0.1, 1.0))

	# Audio Telemetry: Heavier Disruptor Fire Transient
	var pan := -0.6 if muzzle == muzzle_left else 0.6
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		var synth = ml.root.get_node("BioAudioSynth")
		synth.play_laser_fire(pan)
		synth.play_chitin_creak()

	weapon_fired.emit("plasma_missiles", missile_heat_cost)
	CombatStats.register_shot_fired()
	return true


## Secondary Fire: Defensive Bio-Spore Cloud
func fire_secondary() -> bool:
	if is_overheated or secondary_cooldown_timer > 0.0:
		return false

	secondary_cooldown_timer = secondary_fire_cooldown
	_add_heat(secondary_heat_cost)

	var spore_cloud := _create_spore_cloud_area()
	if is_inside_tree() and get_tree() and get_tree().root:
		get_tree().root.add_child(spore_cloud)
	
	spore_cloud.setup(spore_cloud_radius, spore_cloud_dps, spore_cloud_duration)
	spore_cloud.global_position = global_position - global_transform.basis.z * 3.0

	# Audio Telemetry: Spore Cloud Release
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_spore_cloud_release()

	weapon_fired.emit("spore_cloud", secondary_heat_cost)
	return true


## EMP Burst: Area-of-effect energy pulse that strips enemy shields.
## Spawns an expanding Area3D that sets shield=0 and deals bonus damage to shielded targets.
func fire_emp_burst() -> bool:
	if is_overheated or emp_cooldown_timer > 0.0:
		return false

	emp_cooldown_timer = emp_fire_cooldown
	_add_heat(emp_heat_cost)

	var pulse := EmpPulseArea.new()
	pulse.base_damage = emp_damage
	pulse.shield_bonus = emp_shield_bonus_damage
	pulse.max_radius = emp_max_radius
	pulse.expand_speed = emp_expand_speed
	if is_inside_tree() and get_tree() and get_tree().root:
		get_tree().root.add_child(pulse)
	pulse.global_position = global_position

	# Visual: blue-white expanding ring via CombatVFX
	CombatVFX.spawn_explosion(global_position, Color(0.45, 0.75, 1.0, 1.0), 1.5)

	# Audio Telemetry: EMP discharge reuses shield impact transient
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_shield_impact()

	weapon_fired.emit("emp_burst", emp_heat_cost)
	return true


## Beam Emitter: Continuous hitscan beam weapon. Called on a fixed tick interval
## by _update_beam while the player holds the fire input with BEAM_EMITTER selected.
func fire_beam_tick() -> bool:
	if is_overheated:
		return false

	_add_heat(beam_heat_cost)

	var muzzle := muzzle_left if muzzle_left else (muzzle_right if muzzle_right else self)
	var origin := muzzle.global_position
	var dir := -muzzle.global_transform.basis.z.normalized()
	var end_pos := origin + dir * beam_range

	# Hitscan raycast along the beam
	if is_inside_tree() and get_world_3d():
		var space_state := get_world_3d().direct_space_state
		if space_state:
			var query := PhysicsRayQueryParameters3D.create(origin, end_pos)
			query.collide_with_areas = true
			query.collide_with_bodies = true
			query.exclude = [get_rid()]
			var hit_dict := space_state.intersect_ray(query)
			if not hit_dict.is_empty():
				end_pos = hit_dict.get("position", end_pos)
				var collider = hit_dict.get("collider")
				if collider is Node:
					_apply_beam_damage(collider as Node, end_pos)

	# Draw thin green beam from muzzle to hit point
	_draw_beam(origin, end_pos)

	weapon_fired.emit("beam", beam_heat_cost)
	return true


## Mine Deployer: Deploys a stationary proximity mine behind the ship.
## The mine detonates when an enemy comes within mine_trigger_radius meters.
func fire_mine() -> bool:
	if is_overheated or mine_cooldown_timer > 0.0:
		return false

	mine_cooldown_timer = mine_fire_cooldown
	_add_heat(mine_heat_cost)

	var mine := ProximityMine.new()
	mine.trigger_radius = mine_trigger_radius
	mine.damage = mine_damage
	if is_inside_tree() and get_tree() and get_tree().root:
		get_tree().root.add_child(mine)
	# Deploy behind the ship
	mine.global_position = global_position - global_transform.basis.z * 4.0

	weapon_fired.emit("mine", mine_heat_cost)
	return true


# ==============================================================================
# Beam Rendering & Tick Control
# ==============================================================================

## Per-frame beam control: ticks damage/heat on beam_tick_interval while fire is held.
func _update_beam(delta: float) -> void:
	var want_fire: bool = (selected_weapon == WeaponType.BEAM_EMITTER) and \
		(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)) and \
		not is_overheated

	if not want_fire:
		beam_tick_timer = 0.0
		if _beam_visual and is_instance_valid(_beam_visual):
			_beam_visual.visible = false
		return

	beam_tick_timer -= delta
	if beam_tick_timer <= 0.0:
		beam_tick_timer = beam_tick_interval
		fire_beam_tick()
	else:
		# Keep the beam visual refreshed each frame between damage ticks
		_refresh_beam_visual()

## Applies beam tick damage to the raycast hit target.
func _apply_beam_damage(target: Node, hit_point: Vector3) -> void:
	if not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.call("take_damage", beam_damage_per_tick)
	elif is_instance_valid(target.get_parent()) and target.get_parent().has_method("take_damage"):
		target.get_parent().call("take_damage", beam_damage_per_tick)
	CombatVFX.spawn_impact(hit_point, Color(0.2, 1.0, 0.3, 1.0), false, beam_damage_per_tick)

## Lazily creates the beam visual node and draws a line from start to end.
func _draw_beam(start: Vector3, end: Vector3) -> void:
	_ensure_beam_visual()
	if not _beam_visual or not is_instance_valid(_beam_visual):
		return
	_beam_visual.visible = true
	var im := _beam_visual.mesh as ImmediateMesh
	if im:
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES, _beam_visual.material_override)
		im.surface_add_vertex(start)
		im.surface_add_vertex(end)
		im.surface_end()

## Redraws the beam using the current muzzle position and a fresh raycast,
## so the visual stays smooth between damage ticks.
func _refresh_beam_visual() -> void:
	if not _beam_visual or not is_instance_valid(_beam_visual):
		return
	var muzzle := muzzle_left if muzzle_left else (muzzle_right if muzzle_right else self)
	var origin := muzzle.global_position
	var dir := -muzzle.global_transform.basis.z.normalized()
	var end_pos := origin + dir * beam_range
	if is_inside_tree() and get_world_3d():
		var space_state := get_world_3d().direct_space_state
		if space_state:
			var query := PhysicsRayQueryParameters3D.create(origin, end_pos)
			query.collide_with_areas = true
			query.collide_with_bodies = true
			query.exclude = [get_rid()]
			var hit_dict := space_state.intersect_ray(query)
			if not hit_dict.is_empty():
				end_pos = hit_dict.get("position", end_pos)
	_draw_beam(origin, end_pos)

func _ensure_beam_visual() -> void:
	if _beam_visual and is_instance_valid(_beam_visual):
		return
	_beam_visual = MeshInstance3D.new()
	_beam_visual.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.3, 0.85)
	mat.emission = Color(0.2, 1.0, 0.3)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_beam_visual.material_override = mat
	if is_inside_tree() and get_tree() and get_tree().root:
		get_tree().root.add_child(_beam_visual)


# ==============================================================================
# Heat & Targeting Mechanics
# ==============================================================================

func _add_heat(amount: float) -> void:
	if is_overheated:
		return
	current_heat = min(max_heat, current_heat + amount)
	heat_updated.emit(current_heat, max_heat)

	if current_heat >= max_heat:
		is_overheated = true
		overheat_triggered.emit(true)
		_vent_emergency_steam()

func _update_cooldowns_and_heat(delta: float) -> void:
	if primary_cooldown_timer > 0.0:
		primary_cooldown_timer -= delta
	if secondary_cooldown_timer > 0.0:
		secondary_cooldown_timer -= delta
	if emp_cooldown_timer > 0.0:
		emp_cooldown_timer -= delta
	if mine_cooldown_timer > 0.0:
		mine_cooldown_timer -= delta

	if current_heat > 0.0:
		current_heat = max(0.0, current_heat - heat_dissipation_rate * delta)
		heat_updated.emit(current_heat, max_heat)

	if is_overheated and current_heat <= overheat_cooldown_threshold:
		is_overheated = false
		overheat_triggered.emit(false)
		if spiracle_vent_particles:
			spiracle_vent_particles.emitting = false

func _vent_emergency_steam() -> void:
	if spiracle_vent_particles:
		spiracle_vent_particles.emitting = true

func _update_targeting(delta: float) -> void:
	if not is_inside_tree() or not get_tree():
		return

	if current_target and not is_instance_valid(current_target):
		current_target = null
		if lock_state != LockState.NONE:
			lock_state = LockState.NONE
			lock_on_state_changed.emit("NONE", null)
			_sync_audio_lock_state(0)

	var potential_target := _find_best_target_in_cone()

	if potential_target != current_target:
		current_target = potential_target
		lock_timer = 0.0
		if lock_state != LockState.NONE:
			lock_state = LockState.NONE
			lock_on_state_changed.emit("NONE", null)
			_sync_audio_lock_state(0)

	if current_target and is_instance_valid(current_target):
		if lock_state == LockState.NONE:
			lock_state = LockState.ACQUIRING
			lock_on_state_changed.emit("ACQUIRING", current_target)
			_sync_audio_lock_state(1)

		if lock_state == LockState.ACQUIRING:
			lock_timer += delta
			_sync_audio_lock_state(2)
			if lock_timer >= lock_on_acquire_time:
				lock_state = LockState.LOCKED
				lock_on_state_changed.emit("LOCKED", current_target)
				_sync_audio_lock_state(3)
	else:
		current_target = null
		if lock_state != LockState.NONE:
			lock_state = LockState.NONE
			lock_on_state_changed.emit("NONE", null)
			_sync_audio_lock_state(0)

func _get_current_lock_stage() -> int:
	match lock_state:
		LockState.NONE: return 0
		LockState.ACQUIRING: return 2 if lock_timer > 0.1 else 1
		LockState.LOCKED: return 3
	return 0

## Synchronizes lock-on audio with strict rules:
## ONLY audible when (selected_weapon == PLASMA_MISSILES) AND (is_in_combat)
func _sync_audio_lock_state(stage: int) -> void:
	var should_play_lock_audio: bool = (selected_weapon == WeaponType.PLASMA_MISSILES) and is_in_combat
	var audio_stage: int = stage if should_play_lock_audio else 0

	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").set_lock_on_stage(audio_stage)


func _find_best_target_in_cone() -> Node3D:
	if not is_inside_tree() or not get_tree():
		return null

	var best_node: Node3D = null
	var best_angle: float = lock_on_fov_angle

	var candidates: Array[Node] = []
	if get_tree().has_group("targets"):
		candidates.append_array(get_tree().get_nodes_in_group("targets"))
	if get_tree().has_group("void_fauna"):
		candidates.append_array(get_tree().get_nodes_in_group("void_fauna"))

	var forward := -global_transform.basis.z.normalized()

	for node in candidates:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var n3d := node as Node3D
		if n3d == self or is_ancestor_of(n3d):
			continue

		var to_target := (n3d.global_position - global_position)
		var dist := to_target.length()

		if dist > lock_on_range or dist < 0.1:
			continue

		var angle_deg := rad_to_deg(forward.angle_to(to_target.normalized()))
		if angle_deg < best_angle:
			best_angle = angle_deg
			best_node = n3d

	return best_node


func _play_ui_click() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		ml.root.get_node("BioAudioSynth").play_ui_click(true)

func _create_bio_plasma_projectile() -> Area3D:
	return BioPlasmaProjectileClass.new()

func _create_spore_cloud_area() -> Area3D:
	return BioSporeCloudClass.new()


# ==============================================================================
# Inner Classes: EMP Pulse & Proximity Mine (self-contained Area3D payloads)
# ==============================================================================

## Expanding Area3D energy pulse that strips enemy shields and deals bonus
## damage to shielded targets. Grows from a small radius to max_radius, then
## frees itself. Each target is only affected once per pulse.
class EmpPulseArea extends Area3D:
	var max_radius: float = 30.0
	var expand_speed: float = 60.0
	var base_damage: float = 10.0
	var shield_bonus: float = 40.0

	var _radius: float = 1.0
	var _shape: SphereShape3D
	var _mesh: MeshInstance3D
	var _hit_targets: Dictionary = {} # Node -> bool (already affected)

	func _ready() -> void:
		_shape = SphereShape3D.new()
		_shape.radius = _radius
		var cs := CollisionShape3D.new()
		cs.shape = _shape
		add_child(cs)

		_mesh = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		var mat := StandardMaterial3D.new()
		var c := Color(0.45, 0.75, 1.0, 0.55)
		mat.albedo_color = c
		mat.emission = c
		mat.emission_energy_multiplier = 2.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = mat
		_mesh.mesh = sphere
		add_child(_mesh)

		# Disable monitoring self
		monitorable = true
		monitoring = true

	func _physics_process(delta: float) -> void:
		if is_queued_for_deletion():
			return

		_radius += expand_speed * delta
		if _radius >= max_radius:
			queue_free()
			return

		_shape.radius = _radius
		if _mesh and is_instance_valid(_mesh):
			_mesh.scale = Vector3.ONE * _radius

		# Affect every overlapping target once
		for body in get_overlapping_bodies():
			_try_apply(body)
		for area in get_overlapping_areas():
			_try_apply(area)

	func _try_apply(target: Node) -> void:
		if not is_instance_valid(target) or target == self:
			return
		if _hit_targets.has(target):
			return
		_hit_targets[target] = true

		# Resolve the damageable node (target or its parent)
		var node: Node = target
		var had_shield: bool = false
		if "bio_shield" in node and float(node.get("bio_shield")) > 0.0:
			had_shield = true
		elif is_instance_valid(node.get_parent()) and "bio_shield" in node.get_parent() \
				and float(node.get_parent().get("bio_shield")) > 0.0:
			had_shield = true
			node = node.get_parent()

		var dmg: float = base_damage + (shield_bonus if had_shield else 0.0)
		if node.has_method("take_damage"):
			node.call("take_damage", dmg)
		elif is_instance_valid(node.get_parent()) and node.get_parent().has_method("take_damage"):
			node.get_parent().call("take_damage", dmg)

		# Strip shields (set shield=0)
		if "bio_shield" in node:
			node.set("bio_shield", 0.0)
		elif is_instance_valid(node.get_parent()) and "bio_shield" in node.get_parent():
			node.get_parent().set("bio_shield", 0.0)

		# Shield ripple feedback if a shield was present
		if had_shield:
			CombatVFX.spawn_shield_ripple(
				(target as Node3D).global_position if target is Node3D else global_position,
				Vector3.UP, Color(0.45, 0.75, 1.0, 1.0))


## Stationary proximity mine. Arms after a short delay, then detonates when an
## enemy enters its trigger radius, dealing explosion damage and spawning VFX.
class ProximityMine extends Area3D:
	var trigger_radius: float = 15.0
	var damage: float = 60.0
	var arm_delay: float = 0.5

	var _armed: bool = false
	var _arm_timer: float = 0.0
	var _shape: SphereShape3D
	var _mesh: MeshInstance3D

	func _ready() -> void:
		_shape = SphereShape3D.new()
		_shape.radius = trigger_radius
		var cs := CollisionShape3D.new()
		cs.shape = _shape
		add_child(cs)

		_mesh = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		var mat := StandardMaterial3D.new()
		var c := Color(1.0, 0.1, 0.1, 1.0)
		mat.albedo_color = c
		mat.emission = c
		mat.emission_energy_multiplier = 2.0
		mat.no_depth_test = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = mat
		_mesh.mesh = sphere
		add_child(_mesh)

		monitorable = true
		monitoring = true

	func _physics_process(delta: float) -> void:
		if is_queued_for_deletion():
			return

		if not _armed:
			_arm_timer += delta
			if _arm_timer >= arm_delay:
				_armed = true
			return

		# Pulse the red sphere visual once armed
		if _mesh and is_instance_valid(_mesh):
			_mesh.scale = Vector3.ONE * (1.0 + sin(_arm_timer * 8.0) * 0.2)
		_arm_timer += delta

		# Detonate if any enemy is within the trigger radius
		for body in get_overlapping_bodies():
			if _is_enemy(body):
				_detonate()
				return
		for area in get_overlapping_areas():
			if _is_enemy(area):
				_detonate()
				return

	func _is_enemy(node: Node) -> bool:
		if not is_instance_valid(node) or node == self:
			return false
		if node.is_in_group("targets") or node.is_in_group("void_fauna"):
			return true
		if is_instance_valid(node.get_parent()):
			var p: Node = node.get_parent()
			if p.is_in_group("targets") or p.is_in_group("void_fauna"):
				return true
		return false

	func _detonate() -> void:
		if is_queued_for_deletion():
			return
		# Explosion VFX via CombatVFX
		CombatVFX.spawn_explosion(global_position, Color(1.0, 0.3, 0.1, 1.0), 2.0)

		# Apply explosion damage to everything in the trigger radius
		for body in get_overlapping_bodies():
			_apply_damage(body)
		for area in get_overlapping_areas():
			_apply_damage(area)

		# Audio Telemetry: detonation reuses shield impact transient
		var ml := Engine.get_main_loop()
		if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
			ml.root.get_node("BioAudioSynth").play_shield_impact()

		queue_free()

	func _apply_damage(node: Node) -> void:
		if not is_instance_valid(node) or node == self:
			return
		if node.has_method("take_damage"):
			node.call("take_damage", damage)
		elif is_instance_valid(node.get_parent()) and node.get_parent().has_method("take_damage"):
			node.get_parent().call("take_damage", damage)
