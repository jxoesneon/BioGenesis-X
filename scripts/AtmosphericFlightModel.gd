# ==============================================================================
# AtmosphericFlightModel.gd - BioGenesis-X Aerodynamic Flight Physics Extension
# Pumilio Studios & Ciel Aerospace Physics Division
# ==============================================================================
# Extends the 6-DOF Newtonian space flight model (FlightController.gd) with
# realistic aerodynamics for atmospheric entry across diverse planet archetypes.
#
# PHYSICS MODEL:
# - Exponential (ISA-style) atmosphere: rho(h) = rho0 * exp(-h / H)
# - Aerodynamic lift:  L = 0.5 * rho * v^2 * S * Cl(alpha)
# - Aerodynamic drag:  D = 0.5 * rho * v^2 * S * Cd(alpha, Mach)
# - Angle of attack:   alpha = angle(ship_forward, velocity)
# - Stall model:       Cl collapses past critical alpha (~15 deg), Cd spikes
# - Mach drag rise:    Cd *= drag_divergence_factor(Mach)  (transonic/supersonic)
# - Heating intensity: q_heat ~ rho * v^3  (convective aeroheating proxy)
#
# All functions are PURE: deterministic from inputs, no side effects, no state.
# FlightController will call these when the ship is within a planet's atmosphere.
# ==============================================================================

class_name AtmosphericFlightModel
extends RefCounted

# ------------------------------------------------------------------------------
# Atmospheric Layer Enumeration
# ------------------------------------------------------------------------------
## Atmospheric layers ordered from space edge down to the surface.
enum Layer {
	EXOSPHERE,    ## 0: Space edge, negligible air, pure space physics.
	THERMOSPHERE, ## 1: Very thin air, slight drag, heating effects begin.
	TROPOSPHERE,  ## 2: Full aerodynamic flight, significant air density, weather.
	SURFACE       ## 3: Ground effect, landing speeds, touchdown regime.
}

# ------------------------------------------------------------------------------
# Planet Archetype Enumeration (mirrors ProceduralPlanet.archetype int values)
# ------------------------------------------------------------------------------
enum Archetype {
	MOLTEN,           ## 0: Dense, hot, toxic - high drag, high heating, no oxygen.
	METALLIC_BARREN,  ## 1: Very thin atmosphere - minimal aero, mostly space physics.
	DESERT_ARID,      ## 2: Thin but present - moderate drag, dust storms.
	TERRAN_OCEANIC,   ## 3: Earth-like - full aerodynamics, weather.
	ICE_WORLD,        ## 4: Thin, cold - low drag, ice particle effects.
	GAS_GIANT_JOVIAN, ## 5: Extremely dense - massive drag, turbulent, no landing.
	GAS_GIANT_ICE,    ## 6: Dense, methane - high drag, storms.
	RADIOTROPHIC_BIO  ## 7: Moderate, spore-filled - medium drag, bio-particles.
}

# ------------------------------------------------------------------------------
# Physical Constants (SI Units)
# ------------------------------------------------------------------------------
## Earth sea-level air density (kg/m^3) — International Standard Atmosphere base.
const EARTH_SEA_LEVEL_DENSITY: float = 1.225
## Earth sea-level speed of sound (m/s) at 15 degC.
const EARTH_SPEED_OF_SOUND_SURFACE: float = 340.29
## Universal gas constant for air (J/(kg*K)).
const GAS_CONSTANT_AIR: float = 287.05
## Standard gravitational acceleration (m/s^2) for reference heating normalization.
const STANDARD_GRAVITY: float = 9.80665

# ------------------------------------------------------------------------------
# Aerodynamic Coefficients (Bio-ship hull assumptions)
# ------------------------------------------------------------------------------
## Critical angle of attack (radians) beyond which the wing stalls (~15 degrees).
const CRITICAL_AOA_RAD: float = deg_to_rad(15.0)
## Maximum lift coefficient at the critical angle of attack (pre-stall peak).
const MAX_LIFT_COEFFICIENT: float = 1.4
## Base (zero-lift) drag coefficient for the bio-ship hull form.
const BASE_DRAG_COEFFICIENT: float = 0.045
## Parasitic drag coefficient floor (form/skin friction minimum).
const MIN_DRAG_COEFFICIENT: float = 0.02
## Induced drag spike multiplier when stalled.
const STALL_DRAG_MULTIPLIER: float = 4.5
## Mach number at which drag divergence begins (transonic rise onset).
const DRAG_DIVERGENCE_MACH: float = 0.82
## Maximum supersonic drag multiplier cap (prevents runaway forces).
const MAX_SUPERSONIC_DRAG_MULT: float = 8.0
## Reference wing area (m^2) for a 28m bio-ship leviathan.
const REFERENCE_WING_AREA_M2: float = 78.0
## Reference cross-sectional area (m^2) for drag computation.
const REFERENCE_CROSS_SECTION_M2: float = 31.2
## Heating onset velocity threshold (m/s) below which aeroheating is negligible.
const HEATING_VELOCITY_THRESHOLD: float = 120.0
## Reference heating velocity for normalization (orbital-class reentry ~7800 m/s).
const HEATING_REFERENCE_VELOCITY: float = 7800.0
## Reference air density for heating normalization (kg/m^3).
const HEATING_REFERENCE_DENSITY: float = 0.0010
## Ground-effect altitude as a fraction of ship wingspan (rough approximation).
const GROUND_EFFECT_WINGSPAN_FRACTION: float = 1.0
## Landing / surface regime altitude above planet surface (m).
const SURFACE_REGIME_ALTITUDE_M: float = 50.0
## Thermosphere density fraction (1% of sea level) — boundary to troposphere.
const THERMOSPHERE_DENSITY_FRACTION: float = 0.01
## Minimum safe altitude fraction for gas giant "surface" (no solid landing).
const GAS_GIANT_SURFACE_FRACTION: float = 0.02

# ------------------------------------------------------------------------------
# Per-Archetype Atmosphere Parameters
# ------------------------------------------------------------------------------
## Returns the full atmosphere parameter dictionary for a given planet archetype.
## Keys:
##   sea_level_density_kg_m3 : float  - rho0 at the surface
##   scale_height_m          : float  - H (exponential falloff height)
##   atmosphere_thickness_m  : float  - total height of detectable atmosphere
##   speed_of_sound_surface_ms : float - c0 at the surface
##   has_oxygen              : bool   - whether bio-boost combustion is supported
##   weather_intensity       : float  - 0.0 to 1.0 storm/weather severity
##   surface_temp_k          : float  - nominal surface temperature (K)
func get_archetype_parameters(planet_archetype: int) -> Dictionary:
	var params: Dictionary = {}
	match planet_archetype:
		Archetype.MOLTEN:
			params = {
				"sea_level_density_kg_m3": 2.80,
				"scale_height_m": 6500.0,
				"atmosphere_thickness_m": 95000.0,
				"speed_of_sound_surface_ms": 410.0,
				"has_oxygen": false,
				"weather_intensity": 0.15,
				"surface_temp_k": 730.0,
			}
		Archetype.METALLIC_BARREN:
			params = {
				"sea_level_density_kg_m3": 0.0042,
				"scale_height_m": 11100.0,
				"atmosphere_thickness_m": 120000.0,
				"speed_of_sound_surface_ms": 240.0,
				"has_oxygen": false,
				"weather_intensity": 0.02,
				"surface_temp_k": 190.0,
			}
		Archetype.DESERT_ARID:
			params = {
				"sea_level_density_kg_m3": 0.020,
				"scale_height_m": 9200.0,
				"atmosphere_thickness_m": 110000.0,
				"speed_of_sound_surface_ms": 280.0,
				"has_oxygen": true,
				"weather_intensity": 0.55,
				"surface_temp_k": 310.0,
			}
		Archetype.TERRAN_OCEANIC:
			params = {
				"sea_level_density_kg_m3": EARTH_SEA_LEVEL_DENSITY,
				"scale_height_m": 8500.0,
				"atmosphere_thickness_m": 100000.0,
				"speed_of_sound_surface_ms": EARTH_SPEED_OF_SOUND_SURFACE,
				"has_oxygen": true,
				"weather_intensity": 0.70,
				"surface_temp_k": 288.0,
			}
		Archetype.ICE_WORLD:
			params = {
				"sea_level_density_kg_m3": 0.045,
				"scale_height_m": 7800.0,
				"atmosphere_thickness_m": 90000.0,
				"speed_of_sound_surface_ms": 295.0,
				"has_oxygen": false,
				"weather_intensity": 0.40,
				"surface_temp_k": 150.0,
			}
		Archetype.GAS_GIANT_JOVIAN:
			params = {
				"sea_level_density_kg_m3": 16.5,
				"scale_height_m": 27000.0,
				"atmosphere_thickness_m": 320000.0,
				"speed_of_sound_surface_ms": 880.0,
				"has_oxygen": false,
				"weather_intensity": 1.0,
				"surface_temp_k": 165.0,
			}
		Archetype.GAS_GIANT_ICE:
			params = {
				"sea_level_density_kg_m3": 9.2,
				"scale_height_m": 21000.0,
				"atmosphere_thickness_m": 260000.0,
				"speed_of_sound_surface_ms": 720.0,
				"has_oxygen": false,
				"weather_intensity": 0.92,
				"surface_temp_k": 76.0,
			}
		Archetype.RADIOTROPHIC_BIO:
			params = {
				"sea_level_density_kg_m3": 0.85,
				"scale_height_m": 8800.0,
				"atmosphere_thickness_m": 105000.0,
				"speed_of_sound_surface_ms": 330.0,
				"has_oxygen": true,
				"weather_intensity": 0.60,
				"surface_temp_k": 274.0,
			}
		_:
			# Fallback: vacuum-like (treats unknown archetypes as airless).
			params = {
				"sea_level_density_kg_m3": 0.0,
				"scale_height_m": 8500.0,
				"atmosphere_thickness_m": 100000.0,
				"speed_of_sound_surface_ms": 340.29,
				"has_oxygen": false,
				"weather_intensity": 0.0,
				"surface_temp_k": 288.0,
			}
	return params

# ------------------------------------------------------------------------------
# Air Density Model (Exponential / ISA-style)
# ------------------------------------------------------------------------------
## Returns air density (kg/m^3) at a given altitude above the planet surface.
## Uses the exponential atmosphere model: rho(h) = rho0 * exp(-h / H).
## Clamped to >= 0. Altitudes at or above the atmosphere thickness yield ~0.
func get_air_density(altitude_m: float, planet_archetype: int) -> float:
	var params: Dictionary = get_archetype_parameters(planet_archetype)
	var rho0: float = float(params["sea_level_density_kg_m3"])
	var scale_height: float = float(params["scale_height_m"])
	var atm_thickness: float = float(params["atmosphere_thickness_m"])
	if rho0 <= 0.0 or scale_height <= 0.0:
		return 0.0
	# Altitudes at/above the atmosphere top have effectively zero density.
	if altitude_m >= atm_thickness:
		return 0.0
	if altitude_m <= 0.0:
		return rho0
	var density: float = rho0 * exp(-altitude_m / scale_height)
	# Numerical floor: anything below 1e-9 kg/m^3 is treated as vacuum.
	if density < 1e-9:
		return 0.0
	return density

# ------------------------------------------------------------------------------
# Speed of Sound (altitude-dependent, simplified ISA temperature profile)
# ------------------------------------------------------------------------------
## Returns the local speed of sound (m/s) at a given altitude.
## Uses a simplified temperature profile: T(h) = T0 - L*h (lapse rate),
## capped so temperature never drops below a thermodynamic floor (~150 K for
## most archetypes; gas giants use a higher floor). c = sqrt(gamma * R * T).
func get_speed_of_sound(altitude_m: float, planet_archetype: int) -> float:
	var params: Dictionary = get_archetype_parameters(planet_archetype)
	var c0: float = float(params["speed_of_sound_surface_ms"])
	var surface_temp: float = float(params["surface_temp_k"])
	if c0 <= 0.0 or surface_temp <= 0.0:
		return 0.0
	# Standard ISA lapse rate: 6.5 K per 1000 m, scaled by archetype.
	var lapse_rate: float = 0.0065
	# Gas giants cool more slowly with altitude (high thermal inertia).
	if planet_archetype == Archetype.GAS_GIANT_JOVIAN or planet_archetype == Archetype.GAS_GIANT_ICE:
		lapse_rate = 0.0020
	# Ice worlds cool faster.
	elif planet_archetype == Archetype.ICE_WORLD:
		lapse_rate = 0.0090
	var temp_at_alt: float = surface_temp - lapse_rate * altitude_m
	# Temperature floor: atmosphere never gets colder than this (stratosphere cap).
	var temp_floor: float = 150.0
	if planet_archetype == Archetype.GAS_GIANT_JOVIAN or planet_archetype == Archetype.GAS_GIANT_ICE:
		temp_floor = 90.0
	elif planet_archetype == Archetype.MOLTEN:
		temp_floor = 400.0
	temp_at_alt = maxf(temp_at_alt, temp_floor)
	# Speed of sound scales with sqrt(T). c(h) = c0 * sqrt(T_h / T0).
	var temp_ratio: float = temp_at_alt / maxf(1.0, surface_temp)
	return c0 * sqrt(maxf(0.0, temp_ratio))

# ------------------------------------------------------------------------------
# Mach Number
# ------------------------------------------------------------------------------
## Returns the Mach number (velocity / local speed of sound).
## Returns 0.0 if the local speed of sound is zero (vacuum / airless body).
func get_mach_number(velocity_magnitude: float, altitude_m: float, planet_archetype: int) -> float:
	var c_sound: float = get_speed_of_sound(altitude_m, planet_archetype)
	if c_sound <= 0.0:
		return 0.0
	return velocity_magnitude / c_sound

# ------------------------------------------------------------------------------
# Atmospheric Layer Detection
# ------------------------------------------------------------------------------
## Returns the atmospheric layer index (Layer enum) for a given altitude.
## Boundaries scale with the planet's atmosphere thickness and radius.
##   EXOSPHERE    : above the atmosphere top (or density ~ 0)
##   THERMOSPHERE : from atmosphere top down to where density reaches ~1% of rho0
##   TROPOSPHERE  : from the 1% density altitude down to the surface regime
##   SURFACE      : within SURFACE_REGIME_ALTITUDE_M of the ground
func get_atmosphere_layer(altitude_m: float, planet_radius_m: float, planet_archetype: int) -> int:
	var params: Dictionary = get_archetype_parameters(planet_archetype)
	var rho0: float = float(params["sea_level_density_kg_m3"])
	var atm_thickness: float = float(params["atmosphere_thickness_m"])
	# Airless / negligible-atmosphere bodies are always in EXOSPHERE.
	if rho0 <= 0.0:
		return Layer.EXOSPHERE
	# Use the larger of the configured thickness or a radius-scaled envelope.
	# This keeps layer boundaries sensible for very large planets.
	var effective_thickness: float = maxf(atm_thickness, planet_radius_m * 0.15)
	# SURFACE regime: very close to the ground.
	# Gas giants have no solid surface; use a deeper "surface" band.
	var surface_band: float = SURFACE_REGIME_ALTITUDE_M
	if planet_archetype == Archetype.GAS_GIANT_JOVIAN or planet_archetype == Archetype.GAS_GIANT_ICE:
		surface_band = effective_thickness * GAS_GIANT_SURFACE_FRACTION
	if altitude_m <= surface_band:
		return Layer.SURFACE
	# EXOSPHERE: above the atmosphere top.
	if altitude_m >= effective_thickness:
		return Layer.EXOSPHERE
	# THERMOSPHERE vs TROPOSPHERE boundary: altitude where density drops to
	# THERMOSPHERE_DENSITY_FRACTION of sea level. Solve h = -H * ln(fraction).
	var scale_height: float = float(params["scale_height_m"])
	var tropo_boundary: float = -scale_height * log(THERMOSPHERE_DENSITY_FRACTION)
	# Clamp the boundary to lie within [surface_band, effective_thickness].
	tropo_boundary = clampf(tropo_boundary, surface_band + 1.0, effective_thickness - 1.0)
	if altitude_m >= tropo_boundary:
		return Layer.THERMOSPHERE
	return Layer.TROPOSPHERE

# ------------------------------------------------------------------------------
# Aerodynamic Force Computation
# ------------------------------------------------------------------------------
## Computes aerodynamic lift, drag, stall state, air density, Mach, and layer.
## All vectors are in world space. Returns a Dictionary with keys:
##   "lift"          : Vector3 - lift force vector (Newtons), perpendicular to velocity
##   "drag"          : Vector3 - drag force vector (Newtons), opposing velocity
##   "stall_factor"  : float   - 0.0 (clean) to 1.0 (fully stalled)
##   "air_density"   : float   - local air density (kg/m^3)
##   "mach_number"   : float   - local Mach number
##   "layer"         : int     - Layer enum index at this altitude
##   "angle_of_attack_rad" : float - signed angle between forward and velocity
##   "lift_coefficient"    : float - effective Cl after stall modeling
##   "drag_coefficient"    : float - effective Cd after stall + Mach modeling
func compute_aero_forces(
		velocity: Vector3,
		ship_forward: Vector3,
		ship_up: Vector3,
		altitude_m: float,
		planet_archetype: int,
		planet_radius_m: float = 100.0
		) -> Dictionary:
	var result: Dictionary = {
		"lift": Vector3.ZERO,
		"drag": Vector3.ZERO,
		"stall_factor": 0.0,
		"air_density": 0.0,
		"mach_number": 0.0,
		"layer": Layer.EXOSPHERE,
		"angle_of_attack_rad": 0.0,
		"lift_coefficient": 0.0,
		"drag_coefficient": 0.0,
	}
	var vel_mag: float = velocity.length()
	var density: float = get_air_density(altitude_m, planet_archetype)
	var layer: int = get_atmosphere_layer(altitude_m, planet_radius_m, planet_archetype)
	var mach: float = get_mach_number(vel_mag, altitude_m, planet_archetype)
	result["air_density"] = density
	result["layer"] = layer
	result["mach_number"] = mach
	# EXOSPHERE: pure space physics, zero aero forces.
	if layer == Layer.EXOSPHERE or density <= 0.0 or vel_mag < 0.01:
		return result
	# Normalize inputs (guard against degenerate vectors).
	var fwd_n: Vector3 = ship_forward.normalized() if ship_forward.length_squared() > 1e-12 else Vector3.FORWARD
	var up_n: Vector3 = ship_up.normalized() if ship_up.length_squared() > 1e-12 else Vector3.UP
	var vel_n: Vector3 = velocity / vel_mag
	# --- Angle of Attack (signed) ---
	# AoA is the angle between the ship's forward axis and the velocity vector,
	# measured in the plane spanned by forward and up. Positive AoA = nose above
	# the relative wind (producing upward lift along ship_up).
	var cos_alpha: float = clampf(fwd_n.dot(vel_n), -1.0, 1.0)
	var alpha_rad: float = acos(cos_alpha)
	# Sign the AoA using the ship's up axis projected onto the velocity-perp plane.
	# Lateral component of velocity along ship_up determines sign.
	var up_component: float = up_n.dot(vel_n)
	var signed_alpha: float = alpha_rad
	if up_component < 0.0:
		signed_alpha = -alpha_rad
	result["angle_of_attack_rad"] = signed_alpha
	# --- Stall Modeling ---
	# stall_factor ramps from 0 (at critical AoA) to 1 (well past critical).
	var stall_factor: float = 0.0
	var abs_alpha: float = absf(signed_alpha)
	if abs_alpha > CRITICAL_AOA_RAD:
		# Linear ramp to full stall at ~2x critical angle, then clamped.
		var over_stall: float = (abs_alpha - CRITICAL_AOA_RAD) / CRITICAL_AOA_RAD
		stall_factor = clampf(over_stall, 0.0, 1.0)
	result["stall_factor"] = stall_factor
	# --- Lift Coefficient (Cl) ---
	# Linear lift slope up to critical AoA, then post-stall collapse.
	var cl: float = 0.0
	if abs_alpha <= CRITICAL_AOA_RAD:
		# Cl = Cl_max * (alpha / alpha_critical)  (linear lift slope)
		cl = MAX_LIFT_COEFFICIENT * (signed_alpha / CRITICAL_AOA_RAD)
	else:
		# Post-stall: lift drops sharply. Retain ~20% of peak, decaying with stall.
		var retained_fraction: float = lerp(0.20, 0.02, stall_factor)
		var sign_val: float = 1.0 if signed_alpha >= 0.0 else -1.0
		cl = MAX_LIFT_COEFFICIENT * retained_fraction * sign_val
	# --- Drag Coefficient (Cd) ---
	# Base + induced drag, with stall spike and Mach (transonic/supersonic) rise.
	var cd_base: float = BASE_DRAG_COEFFICIENT
	# Induced drag: Cd_i = Cl^2 / (pi * AR * e). Use a moderate aspect-ratio proxy.
	# We fold AR*e into a single efficiency constant to avoid extra parameters.
	var induced_drag: float = (cl * cl) * 0.08
	var cd: float = maxf(MIN_DRAG_COEFFICIENT, cd_base + induced_drag)
	# Stall drag spike.
	if stall_factor > 0.0:
		cd += STALL_DRAG_MULTIPLIER * stall_factor * cd_base
	# Mach drag divergence: transonic rise starting near DRAG_DIVERGENCE_MACH.
	if mach > DRAG_DIVERGENCE_MACH:
		var mach_excess: float = mach - DRAG_DIVERGENCE_MACH
		# Quadratic rise through transonic, linear in supersonic regime.
		var mach_mult: float = 1.0 + minf(mach_excess * 1.6, MAX_SUPERSONIC_DRAG_MULT - 1.0)
		cd *= mach_mult
	# Hard cap to keep forces bounded for extreme reentry conditions.
	cd = minf(cd, MAX_SUPERSONIC_DRAG_MULT)
	result["lift_coefficient"] = cl
	result["drag_coefficient"] = cd
	# --- Dynamic Pressure ---
	# q = 0.5 * rho * v^2  (Pa)
	var dynamic_pressure: float = 0.5 * density * vel_mag * vel_mag
	# --- Lift Force ---
	# Lift acts perpendicular to the velocity vector, in the ship's lift plane.
	# Direction: project ship_up onto the plane perpendicular to velocity, then normalize.
	var lift_dir: Vector3 = (up_n - vel_n * up_n.dot(vel_n))
	if lift_dir.length_squared() > 1e-12:
		lift_dir = lift_dir.normalized()
	else:
		# Fallback: use world up if ship_up is parallel to velocity.
		lift_dir = (Vector3.UP - vel_n * Vector3.UP.dot(vel_n))
		if lift_dir.length_squared() > 1e-12:
			lift_dir = lift_dir.normalized()
		else:
			lift_dir = Vector3.UP
	var lift_magnitude: float = dynamic_pressure * REFERENCE_WING_AREA_M2 * cl
	var lift_force: Vector3 = lift_dir * lift_magnitude
	# --- Ground Effect (SURFACE layer) ---
	# When very close to the surface, lift is augmented and drag reduced
	# (classic ground-effect aerodynamics). Only for landable archetypes.
	if layer == Layer.SURFACE and _is_landable(planet_archetype):
		var ground_effect_strength: float = clampf(
			1.0 - (altitude_m / (GROUND_EFFECT_WINGSPAN_FRACTION * 14.0)), 0.0, 1.0)
		lift_force *= (1.0 + 0.35 * ground_effect_strength)
		cd *= (1.0 - 0.25 * ground_effect_strength)
	# --- Drag Force ---
	# Drag opposes the velocity vector.
	var drag_magnitude: float = dynamic_pressure * REFERENCE_CROSS_SECTION_M2 * cd
	var drag_force: Vector3 = -vel_n * drag_magnitude
	result["lift"] = lift_force
	result["drag"] = drag_force
	return result

# ------------------------------------------------------------------------------
# Heating Intensity
# ------------------------------------------------------------------------------
## Returns a normalized heating intensity (0.0 to 1.0) for visual/audio effects.
## Heating starts in the thermosphere and peaks at troposphere entry.
## Proportional to air_density * velocity^3 (convective aeroheating proxy),
## normalized against a reference reentry condition.
func get_heating_intensity(velocity_magnitude: float, altitude_m: float, planet_archetype: int) -> float:
	var density: float = get_air_density(altitude_m, planet_archetype)
	if density <= 0.0 or velocity_magnitude < HEATING_VELOCITY_THRESHOLD:
		return 0.0
	# Raw convective heating proxy: q ~ rho * v^3 (Sutton-Graves-style simplification).
	var raw_heat: float = density * velocity_magnitude * velocity_magnitude * velocity_magnitude
	# Normalize against a reference reentry condition.
	var reference_heat: float = HEATING_REFERENCE_DENSITY * HEATING_REFERENCE_VELOCITY * HEATING_REFERENCE_VELOCITY * HEATING_REFERENCE_VELOCITY
	var intensity: float = raw_heat / reference_heat
	# Layer weighting: thermosphere onset, peak in upper troposphere.
	var layer: int = get_atmosphere_layer(altitude_m, 100.0, planet_archetype)
	var layer_weight: float = 1.0
	match layer:
		Layer.EXOSPHERE:
			layer_weight = 0.0
		Layer.THERMOSPHERE:
			# Ramp up as we descend through the thermosphere.
			var params: Dictionary = get_archetype_parameters(planet_archetype)
			var atm_thickness: float = float(params["atmosphere_thickness_m"])
			var scale_height: float = float(params["scale_height_m"])
			var tropo_boundary: float = -scale_height * log(THERMOSPHERE_DENSITY_FRACTION)
			tropo_boundary = clampf(tropo_boundary, 1.0, atm_thickness - 1.0)
			var therm_fall: float = clampf((altitude_m - tropo_boundary) / maxf(1.0, atm_thickness - tropo_boundary), 0.0, 1.0)
			layer_weight = 1.0 - therm_fall  # 0 at top, 1 at tropo boundary
		Layer.TROPOSPHERE:
			layer_weight = 1.0
		Layer.SURFACE:
			# Near the surface, velocity is typically low; heating tapers.
			layer_weight = 0.5
	intensity *= layer_weight
	# Archetype heating multiplier (molten worlds radiate more heat back).
	var archetype_heat_mult: float = 1.0
	match planet_archetype:
		Archetype.MOLTEN:
			archetype_heat_mult = 1.6
		Archetype.GAS_GIANT_JOVIAN:
			archetype_heat_mult = 1.3
		Archetype.GAS_GIANT_ICE:
			archetype_heat_mult = 1.2
		Archetype.ICE_WORLD:
			archetype_heat_mult = 0.7
		Archetype.METALLIC_BARREN:
			archetype_heat_mult = 0.4
		_:
			archetype_heat_mult = 1.0
	intensity *= archetype_heat_mult
	return clampf(intensity, 0.0, 1.0)

# ------------------------------------------------------------------------------
# Weather Force Perturbation
# ------------------------------------------------------------------------------
## Returns a deterministic weather perturbation force vector (Newtons) based on
## the archetype's weather intensity and a per-frame phase seed. This lets
## FlightController add turbulent gusts during atmospheric flight.
## NOTE: Pure/deterministic given (altitude, phase, archetype) — no internal RNG.
func get_weather_perturbation(altitude_m: float, phase: float, planet_archetype: int) -> Vector3:
	var params: Dictionary = get_archetype_parameters(planet_archetype)
	var weather_intensity: float = float(params["weather_intensity"])
	var density: float = get_air_density(altitude_m, planet_archetype)
	if weather_intensity <= 0.0 or density <= 0.0:
		return Vector3.ZERO
	var layer: int = get_atmosphere_layer(altitude_m, 100.0, planet_archetype)
	# Weather is strongest in the troposphere, absent in exosphere.
	var layer_factor: float = 0.0
	match layer:
		Layer.TROPOSPHERE:
			layer_factor = 1.0
		Layer.SURFACE:
			layer_factor = 0.7
		Layer.THERMOSPHERE:
			layer_factor = 0.2
		Layer.EXOSPHERE:
			layer_factor = 0.0
	if layer_factor <= 0.0:
		return Vector3.ZERO
	# Deterministic pseudo-oscillation using sine functions of the phase.
	# This avoids RNG so the function stays pure/deterministic from inputs.
	var gust_x: float = sin(phase * 1.3) + 0.5 * sin(phase * 2.7 + 1.1)
	var gust_y: float = sin(phase * 0.9 + 2.0) + 0.5 * sin(phase * 3.1 + 0.4)
	var gust_z: float = sin(phase * 1.7 + 4.0) + 0.5 * sin(phase * 2.3 + 3.0)
	var gust: Vector3 = Vector3(gust_x, gust_y, gust_z)
	# Scale by density (thicker air = stronger gusts) and weather intensity.
	var force_scale: float = density * weather_intensity * layer_factor * 50000.0
	return gust * force_scale

# ------------------------------------------------------------------------------
# Bio-Boost Availability (oxygen check)
# ------------------------------------------------------------------------------
## Returns true if the planet's atmosphere contains oxygen, enabling bio-boost
## combustion augmentation. Thin atmospheres above the troposphere return false
## even for oxygen-bearing worlds (insufficient O2 density for combustion).
func can_bio_boost_in_atmosphere(altitude_m: float, planet_archetype: int) -> bool:
	var params: Dictionary = get_archetype_parameters(planet_archetype)
	var has_oxygen: bool = bool(params["has_oxygen"])
	if not has_oxygen:
		return false
	var density: float = get_air_density(altitude_m, planet_archetype)
	# Require at least 5% of sea-level density for meaningful combustion.
	var rho0: float = float(params["sea_level_density_kg_m3"])
	if rho0 <= 0.0:
		return false
	return density >= (0.05 * rho0)

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
## Returns true if the archetype has a solid surface safe for landing.
func _is_landable(planet_archetype: int) -> bool:
	return planet_archetype != Archetype.GAS_GIANT_JOVIAN and planet_archetype != Archetype.GAS_GIANT_ICE

## Returns the layer name as a human-readable string (for HUD/debug use).
func get_layer_name(layer: int) -> String:
	match layer:
		Layer.EXOSPHERE:
			return "EXOSPHERE"
		Layer.THERMOSPHERE:
			return "THERMOSPHERE"
		Layer.TROPOSPHERE:
			return "TROPOSPHERE"
		Layer.SURFACE:
			return "SURFACE"
		_:
			return "UNKNOWN"

## Returns the archetype name as a human-readable string (for HUD/debug use).
func get_archetype_name(planet_archetype: int) -> String:
	match planet_archetype:
		Archetype.MOLTEN:
			return "MOLTEN"
		Archetype.METALLIC_BARREN:
			return "METALLIC_BARREN"
		Archetype.DESERT_ARID:
			return "DESERT_ARID"
		Archetype.TERRAN_OCEANIC:
			return "TERRAN_OCEANIC"
		Archetype.ICE_WORLD:
			return "ICE_WORLD"
		Archetype.GAS_GIANT_JOVIAN:
			return "GAS_GIANT_JOVIAN"
		Archetype.GAS_GIANT_ICE:
			return "GAS_GIANT_ICE"
		Archetype.RADIOTROPHIC_BIO:
			return "RADIOTROPHIC_BIO"
		_:
			return "UNKNOWN"
