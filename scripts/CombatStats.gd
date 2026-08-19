# res://scripts/CombatStats.gd
# ==============================================================================
# BioGenesis-X — Combat Statistics & Scoring Manager (Autoload)
# Tracks kills, damage, accuracy, and combat rating across the session.
# ==============================================================================
extends Node

## Signals for UI integration
signal stats_updated(stats: Dictionary)
signal kill_streak_changed(streak: int, multiplier: float)
signal combat_rating_changed(rating: String)

## Session statistics
var kills: int = 0
var kills_by_class: Dictionary = {}  # drone_class -> count
var damage_dealt: float = 0.0
var damage_received: float = 0.0
var shots_fired: int = 0
var shots_hit: int = 0
var projectiles_fired: int = 0
var projectiles_hit: int = 0

## Kill streak system
var kill_streak: int = 0
var kill_streak_timer: float = 0.0
const KILL_STREAK_TIMEOUT: float = 8.0  # Seconds before streak resets
var streak_multiplier: float = 1.0

## Combat rating thresholds
const RATING_F = 0    # 0-4 kills
const RATING_D = 5    # 5-9
const RATING_C = 10   # 10-19
const RATING_B = 20   # 20-39
const RATING_A = 40   # 40-79
const RATING_S = 80   # 80+
const RATING_SSS = 150 # 150+

func _process(delta: float) -> void:
	# Decay kill streak
	if kill_streak > 0:
		kill_streak_timer -= delta
		if kill_streak_timer <= 0.0:
			_reset_streak()

## Register a kill — called when an enemy is destroyed
func register_kill(drone_class: String = "unknown") -> void:
	kills += 1
	kills_by_class[drone_class] = kills_by_class.get(drone_class, 0) + 1

	# Kill streak
	kill_streak += 1
	kill_streak_timer = KILL_STREAK_TIMEOUT
	streak_multiplier = 1.0 + minf(kill_streak * 0.1, 2.0)  # Cap at 3x
	kill_streak_changed.emit(kill_streak, streak_multiplier)

	# Update combat rating
	_update_rating()

	_emit_stats()

## Register damage dealt by player
func register_damage_dealt(amount: float) -> void:
	damage_dealt += amount
	_emit_stats()

## Register damage received by player
func register_damage_received(amount: float) -> void:
	damage_received += amount
	_emit_stats()

## Register a shot fired
func register_shot_fired() -> void:
	shots_fired += 1
	projectiles_fired += 1
	_emit_stats()

## Register a projectile hit
func register_projectile_hit() -> void:
	shots_hit += 1
	projectiles_hit += 1
	_emit_stats()

## Get accuracy as a percentage (0-100)
func get_accuracy() -> float:
	if projectiles_fired == 0:
		return 0.0
	return (float(projectiles_hit) / float(projectiles_fired)) * 100.0

## Get combat rating string
func get_combat_rating() -> String:
	if kills >= RATING_SSS:
		return "SSS"
	elif kills >= RATING_S:
		return "S"
	elif kills >= RATING_A:
		return "A"
	elif kills >= RATING_B:
		return "B"
	elif kills >= RATING_C:
		return "C"
	elif kills >= RATING_D:
		return "D"
	else:
		return "F"

## Get kill/death ratio (deaths tracked by ship_destroyed signal count)
var deaths: int = 0
func get_kd_ratio() -> float:
	if deaths == 0:
		return float(kills)
	return float(kills) / float(deaths)

## Register a player death
func register_death() -> void:
	deaths += 1
	_reset_streak()
	_emit_stats()

## Reset all statistics (new session)
func reset_stats() -> void:
	kills = 0
	kills_by_class.clear()
	damage_dealt = 0.0
	damage_received = 0.0
	shots_fired = 0
	shots_hit = 0
	projectiles_fired = 0
	projectiles_hit = 0
	deaths = 0
	_reset_streak()
	_emit_stats()

func _reset_streak() -> void:
	kill_streak = 0
	streak_multiplier = 1.0
	kill_streak_timer = 0.0
	kill_streak_changed.emit(0, 1.0)

func _update_rating() -> void:
	combat_rating_changed.emit(get_combat_rating())

func _emit_stats() -> void:
	var stats := {
		"kills": kills,
		"deaths": deaths,
		"damage_dealt": damage_dealt,
		"damage_received": damage_received,
		"accuracy": get_accuracy(),
		"kill_streak": kill_streak,
		"streak_multiplier": streak_multiplier,
		"combat_rating": get_combat_rating(),
		"kd_ratio": get_kd_ratio(),
		"projectiles_fired": projectiles_fired,
		"projectiles_hit": projectiles_hit,
	}
	stats_updated.emit(stats)

## Get a summary string for display
func get_summary_string() -> String:
	return "K: %d | D: %d | ACC: %.1f%% | STREAK: %d (%.1fx) | RATING: %s" % [
		kills, deaths, get_accuracy(), kill_streak, streak_multiplier, get_combat_rating()
	]
