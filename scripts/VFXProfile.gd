# res://scripts/VFXProfile.gd
# ==============================================================================
# BioGenesis-X — VFX Profile Resource
# Data-driven description of a combat visual effect. Registered with the
# CombatVFX autoload's VFXRegistry so callers can spawn effects by profile id
# without hardcoding particle/light parameters at every call site.
# ==============================================================================
class_name VFXProfile extends Resource

## Unique identifier for this profile (used as the registry key).
@export var profile_id: String
## Category of effect: impact / muzzle_flash / explosion / shield_ripple / dissolve.
@export var vfx_type: String = "impact"
## Number of particles to emit.
@export var particle_count: int = 20
## Lifetime of each emitted particle, in seconds.
@export var particle_lifetime: float = 1.0
## Emission cone spread in degrees.
@export var spread: float = 0.3
## Initial outward velocity of particles.
@export var initial_speed: float = 5.0
## OmniLight3D energy/intensity for the flash.
@export var light_intensity: float = 3.0
## OmniLight3D range in meters.
@export var light_range: float = 4.0
## Total VFX duration before cleanup, in seconds.
@export var duration: float = 1.0
## Primary color tint for particles + light.
@export var color_base: Color = Color.WHITE
## Secondary/accent color for ramps and edges.
@export var color_accent: Color = Color.CYAN
