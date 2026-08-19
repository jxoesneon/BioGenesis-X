# res://scripts/ProceduralGalaxy.gd
# ==============================================================================
# BioGenesis-X: Elite Dangerous-Scale Procedural Galaxy & Astrophysics Engine
# ==============================================================================
# Implements Lin-Shu Logarithmic Spiral Density Wave Galaxy Model,
# Deterministic Sector Octrees, Harvard Stellar Classification (O/B/A/F/G/K/M),
# and Titius-Bode Planetary Orbital Resonance Simulation.
# ==============================================================================

@tool
class_name ProceduralGalaxy
extends RefCounted

# ------------------------------------------------------------------------------
# Stellar Spectral Class Definitions
# ------------------------------------------------------------------------------
enum SpectralClass {
	CLASS_O,       ## Blue Hypergiant (>30,000 K) - Ultra Rare
	CLASS_B,       ## Blue-White Giant (10,000 - 30,000 K)
	CLASS_A,       ## White Main Sequence (7,500 - 10,000 K)
	CLASS_F,       ## Yellow-White (6,000 - 7,500 K)
	CLASS_G,       ## Yellow Dwarf / Sol-Type (5,200 - 6,000 K)
	CLASS_K,       ## Orange Dwarf (3,700 - 5,200 K)
	CLASS_M,       ## Red Dwarf (2,400 - 3,700 K) - Most Common (~76%)
	NEUTRON_STAR,  ## Ultra-Dense Pulsar with Relativistic Beams
	BLACK_HOLE,    ## Singularity with Gravitational Lensing Accretion
	WOLF_RAYET     ## Mass-Losing Supermassive Variable
}

# ------------------------------------------------------------------------------
# Planet Archetype Classifications
# ------------------------------------------------------------------------------
enum PlanetArchetype {
	MOLTEN,            ## Volcanic / Magma Surface
	METALLIC_BARREN,   ## Cratered Heavy Ore World
	DESERT_ARID,       ## Sandy Dunes & Iron Oxide
	TERRAN_OCEANIC,    ## Liquid Water & Photosynthetic Biosphere
	ICE_WORLD,         ## Cryo-Glacial Frozen Crust
	GAS_GIANT_JOVIAN,  ## Banded Hydrogen/Helium with Rings & Great Red Spot
	GAS_GIANT_ICE,     ## Turquoise Methane Giant (Neptune Analogue)
	RADIOTROPHIC_BIO   ## Alien Bioluminescent Spore World
}

# ------------------------------------------------------------------------------
# Galaxy Parameters (Milky Way Scale Analogue)
# ------------------------------------------------------------------------------
const GALAXY_RADIUS_LY: float = 50000.0        ## 50,000 Light Years radius (100k LY diameter)
const GALAXY_THICKNESS_LY: float = 1200.0      ## 1,200 Light Years disc scale height
const CORE_RADIUS_LY: float = 8000.0           ## Dense Central Bulge radius
const SECTOR_SIZE_LY: float = 40.0             ## Cubic spatial sector dimension
const SPIRAL_ARM_COUNT: int = 4                ## 4 Primary Logarithmic Spiral Arms
const SPIRAL_ARM_PITCH: float = 0.22           ## Pitch angle constant (b) = tan(12°)
const GALAXY_SEED: int = 0x50756D69            ## "Pumi" Master Galaxy Seed

## Supermassive Black Hole — Sagittarius A* (real values)
## Mass from Gillessen et al. (2009) / Gravity Collaboration (2018): 4.15 × 10⁶ M_sun
const SMBH_MASS_SOL: float = 4.15e6
## Schwarzschild radius: R_s = 2GM/c² = 2.95 km × (M/M_sun)
## For Sgr A*: 2.95 × 4.15e6 ≈ 12.2 million km ≈ 0.082 AU ≈ 1.3e-9 LY
const SMBH_SCHWARZSCHILD_RADIUS_LY: float = 1.3e-9

## Sphere of influence: r_inf = G × M_BH / σ²
## where σ is the stellar velocity dispersion near the galactic center.
## Milky Way σ ≈ 75 km/s (Kormendy & Ho 2013, Genzel et al. 2010).
## r_inf ≈ 3 pc ≈ 10 LY — region where SMBH gravity dominates stellar dynamics.
## Stars within this zone are on SMBH-dominated orbits (nuclear star cluster).
const SMBH_EXCLUSION_RADIUS_LY: float = 10.0

# Sol Reference Coordinate in Galaxy (Orion Spur, ~26,000 LY from Sag A*)
const SOL_SYSTEM_COORDINATE: Vector3 = Vector3(0.0, 15.0, 26000.0)

# ------------------------------------------------------------------------------
# Real Astrophysical Constants (SI / Solar Units)
# ------------------------------------------------------------------------------
const SOLAR_MASS_KG: float = 1.9885e30         ## M_sun (IAU 2015 nominal)
const SOLAR_RADIUS_KM: float = 696340.0        ## R_sun (IAU 2015 nominal)
const SOLAR_LUMINOSITY_W: float = 3.828e26     ## L_sun (IAU 2015 nominal)
const SOLAR_TEMPERATURE_K: float = 5772.0      ## T_eff,sun (IAU 2015 nominal)
const STEFAN_BOLTZMANN: float = 5.670374419e-8 ## σ (W m⁻² K⁻⁴)
const GRAVITATIONAL_CONSTANT: float = 6.6743e-11  ## G (m³ kg⁻¹ s⁻²)
const AU_KM: float = 149597870.7               ## 1 AU in km
const LIGHT_SPEED_KMS: float = 299792.458      ## c in km/s
const EARTH_MASS_KG: float = 5.9722e24         ## M_earth
const EARTH_RADIUS_KM: float = 6371.0          ## R_earth (mean)
const PARSEC_LY: float = 3.26156               ## 1 pc in light-years

## Real local stellar number density in the solar neighborhood.
## Value: ~0.004 stars/ly³ (0.14 stars/pc³, from RECONS / GAIA DR2).
## This is the REAL density — we use it for physics calculations, then cull
## the generated star list down to the performance budget (max_stars_per_sector).
const REAL_LOCAL_STELLAR_DENSITY_PER_LY3: float = 0.004

## Performance density cap — the ONLY fake number in the system.
## We generate stars at real density, then probabilistically cull to this
## fraction so the galaxy map renders at interactive framerates.
const DENSITY_CULL_FACTOR: float = 0.01        ## 1% of real density for performance

# ------------------------------------------------------------------------------
# Deterministic Mathematical Hashing (SplitMix64 / Murmur3 Bit-Mixing)
# ------------------------------------------------------------------------------

static func hash_coords(x: int, y: int, z: int, seed_val: int = GALAXY_SEED) -> int:
	var h: int = seed_val ^ (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h ^ (h >> 16)
	return abs(h)

static func hash_to_float(hash_val: int) -> float:
	return float(hash_val % 1000000) / 1000000.0

# ------------------------------------------------------------------------------
# Real Astrophysical Formulae
# ------------------------------------------------------------------------------

## Kroupa Initial Mass Function (2001) — broken power law.
## Samples a stellar mass in solar units from the real IMF:
##   α = 0.3  for 0.01 ≤ M < 0.08  (brown dwarfs)
##   α = 1.3  for 0.08 ≤ M < 0.5   (M dwarfs)
##   α = 2.3  for 0.5 ≤ M < 150    (main sequence + giants)
## Uses inverse-transform sampling on the normalized CDF.
static func sample_imf_mass(u: float) -> float:
	# Mass range bounds
	var m_min: float = 0.01
	var m_bd: float = 0.08   # Brown dwarf / M-dwarf boundary
	var m_low: float = 0.5   # M-dwarf / upper main sequence boundary
	var m_max: float = 150.0

	# Power-law exponents per Kroupa (2001)
	var a1: float = 0.3   # brown dwarf regime
	var a2: float = 1.3   # low-mass regime
	var a3: float = 2.3   # main sequence + massive

	# Compute relative number of stars in each segment
	# N = integral of M^-a dM = [M^(1-a) / (1-a)]
	var n1: float = (m_bd ** (1.0 - a1) - m_min ** (1.0 - a1)) / (1.0 - a1)
	var n2: float = (m_low ** (1.0 - a2) - m_bd ** (1.0 - a2)) / (1.0 - a2)
	var n3: float = (m_max ** (1.0 - a3) - m_low ** (1.0 - a3)) / (1.0 - a3)
	var n_total: float = n1 + n2 + n3

	# Determine which segment this sample falls in
	var p1: float = n1 / n_total
	var p2: float = (n1 + n2) / n_total

	if u < p1:
		# Brown dwarf segment: inverse CDF of M^-0.3
		var u_local: float = u / p1
		return (m_min ** (1.0 - a1) + u_local * (m_bd ** (1.0 - a1) - m_min ** (1.0 - a1))) ** (1.0 / (1.0 - a1))
	elif u < p2:
		# Low-mass segment: inverse CDF of M^-1.3
		var u_local: float = (u - p1) / (p2 - p1)
		return (m_bd ** (1.0 - a2) + u_local * (m_low ** (1.0 - a2) - m_bd ** (1.0 - a2))) ** (1.0 / (1.0 - a2))
	else:
		# Upper main sequence: inverse CDF of M^-2.3
		var u_local: float = (u - p2) / (1.0 - p2)
		return (m_low ** (1.0 - a3) + u_local * (m_max ** (1.0 - a3) - m_low ** (1.0 - a3))) ** (1.0 / (1.0 - a3))

## Mass-Luminosity relation for main-sequence stars (piecewise, solar units).
## Based on empirical fits from Eker et al. (2018):
##   M < 0.43:  L = 0.23 * M^2.3   (fully convective)
##   0.43-2.0:  L = M^4.0           (Sun-like)
##   2.0-20:    L = 1.4 * M^3.5     (intermediate mass)
##   M ≥ 20:    L = 320 * M         (very massive, Eddington-limited)
static func mass_to_luminosity(m_sol: float) -> float:
	if m_sol < 0.43:
		return 0.23 * (m_sol ** 2.3)
	elif m_sol < 2.0:
		return m_sol ** 4.0
	elif m_sol < 20.0:
		return 1.4 * (m_sol ** 3.5)
	else:
		return 320.0 * m_sol

## Mass-Radius relation for main-sequence stars (solar units).
## Based on empirical fits from Eker et al. (2018):
##   M < 1.0:   R = M^0.8    (low mass, convective)
##   M ≥ 1.0:   R = M^0.57   (higher mass, radiative)
static func mass_to_radius(m_sol: float) -> float:
	if m_sol < 1.0:
		return m_sol ** 0.8
	else:
		return m_sol ** 0.57

## Effective temperature from Stefan-Boltzmann law: L = 4πR²σT⁴
## In solar units: T = T_sun * (L/L_sun)^0.25 * (R/R_sun)^-0.5
static func luminosity_radius_to_temperature(l_sol: float, r_sol: float) -> float:
	return SOLAR_TEMPERATURE_K * (l_sol ** 0.25) / (r_sol ** 0.5)

## Main-sequence lifetime: τ = τ_sun * M / L (nuclear timescale)
## τ_sun ≈ 10^10 years. Returns lifetime in years.
static func stellar_lifetime_years(m_sol: float, l_sol: float) -> float:
	return 1.0e10 * m_sol / maxf(l_sol, 1e-6)

## Classify spectral type from effective temperature (Harvard OBAFGKM).
## Thresholds from Morgan-Keenan classification boundaries.
static func temperature_to_spectral_class(temp_k: float) -> int:
	if temp_k >= 30000.0:
		return SpectralClass.CLASS_O
	elif temp_k >= 10000.0:
		return SpectralClass.CLASS_B
	elif temp_k >= 7500.0:
		return SpectralClass.CLASS_A
	elif temp_k >= 6000.0:
		return SpectralClass.CLASS_F
	elif temp_k >= 5200.0:
		return SpectralClass.CLASS_G
	elif temp_k >= 3700.0:
		return SpectralClass.CLASS_K
	else:
		return SpectralClass.CLASS_M

## Blackbody color from temperature (Planckian locus approximation).
## Uses the Tanner Helland approximation for color temperature to sRGB.
## Returns a linear-space Color suitable for Godot emission/albedo.
static func blackbody_color(temp_k: float) -> Color:
	var t: float = temp_k / 100.0
	var r: float
	var g: float
	var b: float

	# Red channel
	if t <= 66.0:
		r = 255.0
	else:
		r = 329.698727446 * ((t - 60.0) ** -0.1332047592)

	# Green channel
	if t <= 66.0:
		g = 99.4708025861 * log(t) - 161.1195681661
	else:
		g = 288.1221695283 * ((t - 60.0) ** -0.0755148492)

	# Blue channel
	if t >= 66.0:
		b = 255.0
	elif t <= 19.0:
		b = 0.0
	else:
		b = 138.5177312231 * log(t - 10.0) - 305.0447927307

	# Clamp and normalize to 0-1
	r = clampf(r / 255.0, 0.0, 1.0)
	g = clampf(g / 255.0, 0.0, 1.0)
	b = clampf(b / 255.0, 0.0, 1.0)
	return Color(r, g, b)

## Kopparapu et al. (2013) habitable zone bounds.
## Computes the inner (runaway greenhouse) and outer (maximum greenhouse)
## edges in AU, accounting for the star's effective temperature.
## seff = seff_sun + a*T_eff' + b*T_eff'² + c*T_eff'³ + d*T_eff'⁴
## where T_eff' = T_star - 5780 K, and r = sqrt(L_star / seff) AU.
static func habitable_zone(l_sol: float, t_star_k: float) -> Vector2:
	var t_eff_prime: float = t_star_k - 5780.0

	# Coefficients for runaway greenhouse (inner edge)
	var seff_sun_inner: float = 1.107
	var a_in: float = 1.332e-4
	var b_in: float = -1.580e-8
	var c_in: float = -1.952e-12
	var d_in: float = 5.007e-16
	var seff_inner: float = seff_sun_inner + a_in * t_eff_prime + b_in * t_eff_prime ** 2 + c_in * t_eff_prime ** 3 + d_in * t_eff_prime ** 4

	# Coefficients for maximum greenhouse (outer edge)
	var seff_sun_outer: float = 0.356
	var a_out: float = 5.894e-5
	var b_out: float = -1.268e-8
	var c_out: float = -1.952e-12
	var d_out: float = 5.007e-16
	var seff_outer: float = seff_sun_outer + a_out * t_eff_prime + b_out * t_eff_prime ** 2 + c_out * t_eff_prime ** 3 + d_out * t_eff_prime ** 4

	var r_inner: float = sqrt(l_sol / maxf(seff_inner, 0.01))
	var r_outer: float = sqrt(l_sol / maxf(seff_outer, 0.01))
	return Vector2(r_inner, r_outer)

## Frost line distance: where volatile ices (H₂O, CO₂, CH₄) condense.
## Empirically ~2.7 AU for the Sun (beyond the asteroid belt, at Jupiter).
## Scales as sqrt(L) from the star's luminosity.
static func frost_line(l_sol: float) -> float:
	return 2.7 * sqrt(l_sol)

## Planet mass-radius relation for solid planets (Sotin et al. 2007, Valencia et al. 2006).
## For rocky/iron planets: R/R_earth = (M/M_earth)^0.274 (compressed mass-radius)
## For ice-rich planets: R/R_earth = (M/M_earth)^0.274 * 1.26 (ice is less dense)
## For gas giants: radius is largely independent of mass (degenerate).
static func planet_mass_to_radius(m_earth: float, is_gas_giant: bool, is_ice_giant: bool) -> float:
	if is_gas_giant:
		# Gas giants: R ≈ 1.0-1.2 R_jup for 0.3-13 M_jup, slight inflation above
		var r_jup: float = 1.0 + 0.07 * log(maxf(m_earth / 318.0, 0.01))
		return r_jup * 69911.0  # R_jup in km
	elif is_ice_giant:
		# Ice giants (Neptune-like): R ≈ 3.9 R_earth, weakly dependent on mass
		return 3.9 * (m_earth / 14.5) ** 0.274 * EARTH_RADIUS_KM
	else:
		# Rocky planets: M-R relation from Sotin et al. (2007)
		return (m_earth ** 0.274) * EARTH_RADIUS_KM

## Exoplanet eccentricity distribution.
## Observed exoplanets (from Kepler + radial velocity) show a Rayleigh-like
## distribution with σ ≈ 0.17 for single-planet systems, lower for multi-planet.
## Uses inverse CDF of Rayleigh: e = σ * sqrt(-2 * ln(1 - u))
static func sample_eccentricity(u: float, is_multi_planet: bool) -> float:
	var sigma: float = 0.17 if not is_multi_planet else 0.08
	var e: float = sigma * sqrt(-2.0 * log(maxf(1.0 - u, 0.0001)))
	return clampf(e, 0.0, 0.9)  # Hard upper bound for stability

## Surface pressure from atmospheric mass and gravity.
## Uses the barometric approximation: P ∝ (atmosphere_mass * g) / (surface_area)
## Simplified to: P_bar = k * atmosphere_mass_fraction * g / g_earth
static func compute_surface_pressure_bar(atmosphere_mass_fraction: float, gravity_g: float) -> float:
	return atmosphere_mass_fraction * gravity_g * 1.0  # Normalized to Earth = 1 bar

## Jeans escape parameter: Λ = G * M * m_atm / (k_B * R * T)
## If Λ < 15 (roughly), the atmosphere escapes over geological timescales.
## Simplified: atmosphere survives if escape_velocity > thermal_velocity * 6
static func atmosphere_retention(escape_vel_kms: float, temp_k: float, molecular_weight: float = 28.97) -> bool:
	# Thermal velocity of gas molecules: v_thermal = sqrt(3*k_B*T/m)
	# For N₂ (MW=28): v_thermal ≈ 0.5 km/s at 300K
	var v_thermal: float = 0.157 * sqrt(temp_k / molecular_weight)  # km/s
	return escape_vel_kms > v_thermal * 6.0  # Factor of 6 for geological retention

# ------------------------------------------------------------------------------
# Galactic Structural Parameters (Real Milky Way Values)
# ------------------------------------------------------------------------------
# Galactic Bar — the Milky Way is a barred spiral (SBbc).
# Bar half-length: 5.0 ± 0.2 kpc (Wegg et al. 2015)
# Bar angle: 27°-30° from Sun-GC line (we use 28°)
# Boxy/peanut bulge: X-shape in cross-section
const BAR_HALF_LENGTH_LY: float = 16300.0       # 5.0 kpc
const BAR_HALF_WIDTH_LY: float = 3600.0         # ~1.1 kpc (minor axis)
const BAR_HALF_HEIGHT_LY: float = 1800.0        # ~0.55 kpc (vertical)
const BAR_ANGLE_RAD: float = deg_to_rad(28.0)   # 28° from Sun-GC line
const BAR_AXIS_RATIO_X: float = 1.67            # X/P instability (Ciambur & Graham 2016)

# Thick Disk — older Population II stars
# Scale height: ~3000 LY (vs thin disk ~700 LY)
# Stellar density: ~10-15% of thin disk at same radius
const THICK_DISK_SCALE_HEIGHT_LY: float = 3000.0
const THICK_DISK_DENSITY_RATIO: float = 0.12    # 12% of thin disk

# Stellar Halo — ancient metal-poor stars, ~1% of total
# Power-law profile: ρ ∝ r^-3.5 (Bland-Hawthorn & Gerhard 2016)
# Extends to ~100,000 LY (some stars to 300,000 LY)
const STELLAR_HALO_RADIUS_LY: float = 100000.0
const STELLAR_HALO_POWER_LAW: float = 3.5
const STELLAR_HALO_DENSITY_RATIO: float = 0.01   # 1% of disk at same r

# Disk Warp — outer disk bends above/below the plane
# Warp amplitude: ~5000 LY at R = 50,000 LY
# Warp starts at R ~ 40,000 LY (Galactic anticenter side up, center side down)
const WARP_START_RADIUS_LY: float = 40000.0
const WARP_AMPLITUDE_LY: float = 5000.0
const WARP_ANGLE_RAD: float = deg_to_rad(90.0)   # Node line perpendicular to Sun-GC

# Disk Flare — scale height increases with radius
# h(R) = h0 * (1 + R/R_flare)^1.5 (López-Corredoira et al. 2002)
const FLARE_SCALE_RADIUS_LY: float = 40000.0

# Spiral Arm Spurs/Feathers — sub-structure branching off arms
# Orion Spur is a prominent feather (~3000 LY long)
const SPUR_DENSITY_BOOST: float = 0.3
const SPUR_SPACING_LY: float = 8000.0            # Spurs every ~8 kLY along arms

# Globular Clusters — ~150-170 known (Harris catalog 2010 edition)
const GLOBULAR_CLUSTER_COUNT: int = 157
const GLOBULAR_CLUSTER_MAX_RADIUS_LY: float = 33.0   # Half-light radius (Omega Cen ~33 LY)
const GLOBULAR_CLUSTER_MIN_STARS: int = 10000
const GLOBULAR_CLUSTER_MAX_STARS: int = 1000000

# HII Regions — ionized nebulae around hot O/B stars
# ~10,000+ estimated in Milky Way (Anderson et al. 2014, WISE catalog)
# Size: 1-100 pc (3-330 LY), pink/red from Hα emission
const HII_REGION_COUNT: int = 10000
const HII_REGION_MIN_RADIUS_LY: float = 3.0
const HII_REGION_MAX_RADIUS_LY: float = 330.0
const HII_REGION_TEMP_K: float = 10000.0         # Ionized hydrogen temperature

# Molecular Clouds (GMCs) — cold CO/H₂, star formation sites
# ~10,000+ estimated (Dame et al. 2001 CO survey extrapolated)
# Mass: 10^4-10^6 M_sun, Size: 10-100 pc (33-330 LY)
const MOLECULAR_CLOUD_COUNT: int = 10000
const MOLECULAR_CLOUD_MIN_RADIUS_LY: float = 33.0
const MOLECULAR_CLOUD_MAX_RADIUS_LY: float = 330.0
const MOLECULAR_CLOUD_TEMP_K: float = 15.0       # Cold molecular gas

# Satellite Galaxies — ~60 known (McConnachie 2012)
# LMC: 163,000 LY, SMC: 200,000 LY, Sagittarius Dwarf: 70,000 LY
const SATELLITE_GALAXY_COUNT: int = 60

# Stellar Streams — ~40+ known (Malhan et al. 2018, Ibata et al. 2021)
const STELLAR_STREAM_COUNT: int = 40

# Supernova Remnants — ~1,000+ estimated (Green 2019 catalog extrapolated)
# Most are old/faint and below survey detection limits
const SNR_COUNT: int = 1000
const SNR_MIN_RADIUS_LY: float = 3.0             # ~1 pc (young SNR)
const SNR_MAX_RADIUS_LY: float = 163.0           # ~50 pc (old SNR)

# Planetary Nebulae — ~10,000+ estimated (HASH catalog extrapolated)
# Most are faint/below detection limits in disk extinction
const PN_COUNT: int = 10000
const PN_MIN_RADIUS_LY: float = 0.3              # ~0.1 pc
const PN_MAX_RADIUS_LY: float = 3.3              # ~1 pc

# Open Clusters — ~5,000+ estimated (Dias catalog extrapolated)
# Many are dissolved or below detection in dense disk fields
const OPEN_CLUSTER_COUNT: int = 5000
const OPEN_CLUSTER_MIN_RADIUS_LY: float = 3.0    # ~1 pc
const OPEN_CLUSTER_MAX_RADIUS_LY: float = 33.0   # ~10 pc

# ------------------------------------------------------------------------------
# Lin-Shu Spiral Density Wave Galactic Mass Model
# ------------------------------------------------------------------------------

## Computes the disk warp offset (Y displacement) at a given galactic position.
## The warp starts beyond WARP_START_RADIUS_LY and bends the disk plane.
## Real warp: amplitude ~5 kLY at R=50 kLY, node line at ~90° from Sun-GC.
static func get_warp_offset(pos_ly: Vector3) -> float:
	var r: float = Vector2(pos_ly.x, pos_ly.z).length()
	if r < WARP_START_RADIUS_LY:
		return 0.0
	var r_excess: float = (r - WARP_START_RADIUS_LY) / (GALAXY_RADIUS_LY - WARP_START_RADIUS_LY)
	var theta: float = atan2(pos_ly.z, pos_ly.x)
	# Sine warp: node line at WARP_ANGLE_RAD, amplitude grows with radius
	return WARP_AMPLITUDE_LY * r_excess * sin(theta - WARP_ANGLE_RAD)

## Computes the flared disk scale height at a given radius.
## h(R) = h0 * (1 + R/R_flare)^1.5 (López-Corredoira et al. 2002)
static func get_flared_scale_height(r_ly: float) -> float:
	return GALAXY_THICKNESS_LY * pow(1.0 + r_ly / FLARE_SCALE_RADIUS_LY, 1.5)

## Computes the galactic bar density at a position.
## Uses a triaxial ellipsoid with boxy/peanut (X-shape) cross-section.
## Bar is oriented at BAR_ANGLE_RAD from the Sun-GC line (X axis).
static func get_bar_density(pos_ly: Vector3) -> float:
	# Rotate position into bar frame
	var cos_a: float = cos(BAR_ANGLE_RAD)
	var sin_a: float = sin(BAR_ANGLE_RAD)
	# Bar long axis is along (cos_a, 0, sin_a) in galactic coords
	var x_bar: float = pos_ly.x * cos_a + pos_ly.z * sin_a
	var z_bar: float = -pos_ly.x * sin_a + pos_ly.z * cos_a
	var y_bar: float = pos_ly.y

	# Normalized ellipsoidal radius
	var ellip_r: float = sqrt(
		(x_bar / BAR_HALF_LENGTH_LY) ** 2 +
		(z_bar / BAR_HALF_WIDTH_LY) ** 2 +
		(y_bar / BAR_HALF_HEIGHT_LY) ** 2
	)
	if ellip_r > 1.0:
		return 0.0

	# Boxy/peanut profile: sech² vertical, exponential radial
	var radial_profile: float = exp(-ellip_r * 3.0)
	# X-shape: density enhanced along diagonals in the X-Z plane
	var x_shape: float = 1.0 + BAR_AXIS_RATIO_X * exp(-abs(abs(x_bar) - abs(y_bar)) / BAR_HALF_HEIGHT_LY) * 0.3
	return radial_profile * x_shape * 3.0

## Computes normalized stellar density [0.0, 1.0] at any 3D galactic coordinate.
## Combines: thin disk + thick disk + galactic bar + stellar halo + spiral arms
## with disk warp and flare applied to the vertical structure.
static func get_stellar_density(pos_ly: Vector3) -> float:
	var r: float = Vector2(pos_ly.x, pos_ly.z).length()
	var theta: float = atan2(pos_ly.z, pos_ly.x)

	# Apply disk warp — shift the effective z by the warp offset
	var warp_y: float = get_warp_offset(pos_ly)
	var z_eff: float = abs(pos_ly.y - warp_y)

	# SMBH gravitational exclusion zone
	if pos_ly.length() < SMBH_EXCLUSION_RADIUS_LY:
		return 0.0

	# Stellar halo extends beyond the disk
	if r > STELLAR_HALO_RADIUS_LY:
		return 0.0

	# Flared scale height at this radius
	var scale_h: float = get_flared_scale_height(r)

	# 1. Thin Disk — exponential vertical decay with flared scale height
	var thin_vertical: float = exp(-z_eff / (scale_h * 0.5))

	# 2. Thick Disk — larger scale height, lower density
	var thick_vertical: float = exp(-z_eff / (THICK_DISK_SCALE_HEIGHT_LY * 0.5))
	var thick_disk: float = thick_vertical * exp(-r / (GALAXY_RADIUS_LY * 0.4)) * THICK_DISK_DENSITY_RATIO

	# 3. Central Bulge + Galactic Bar
	var bulge_density: float = exp(-r / (CORE_RADIUS_LY * 0.45)) * 4.5
	var bar_density: float = get_bar_density(pos_ly)

	# 4. Radial Disc Falloff
	var disc_density: float = exp(-r / (GALAXY_RADIUS_LY * 0.35))

	# 5. Logarithmic Spiral Arms (Lin-Shu Density Wave)
	var arm_modulation: float = 0.0
	if r > 1000.0:
		var log_r: float = log(r / 1000.0) / SPIRAL_ARM_PITCH
		for arm in range(SPIRAL_ARM_COUNT):
			var arm_phase: float = (float(arm) / float(SPIRAL_ARM_COUNT)) * TAU
			var phase_diff: float = fmod(theta - log_r - arm_phase + TAU * 10.0, TAU)
			if phase_diff > PI:
				phase_diff -= TAU
			arm_modulation += exp(-abs(phase_diff) * 4.5)

			# Spiral arm spurs/feathers — sub-structure branching off arms
			# Spurs appear at regular intervals along the arm
			var spur_phase: float = fmod(log_r * SPUR_SPACING_LY / 1000.0 + arm_phase, PI * 0.5)
			if abs(spur_phase) < 0.3:
				arm_modulation += SPUR_DENSITY_BOOST * exp(-abs(phase_diff) * 8.0) * exp(-abs(spur_phase - 0.15) * 10.0)

	# 6. Stellar Halo — power-law profile, very diffuse
	var halo_density: float = 0.0
	if r > CORE_RADIUS_LY:
		halo_density = pow(CORE_RADIUS_LY / r, STELLAR_HALO_POWER_LAW) * STELLAR_HALO_DENSITY_RATIO

	# Combine all components
	var thin_disk: float = disc_density * (0.05 + arm_modulation * 3.5) * thin_vertical
	var total_density: float = (bulge_density + bar_density) * thin_vertical + thin_disk + thick_disk + halo_density
	return clampf(total_density * 0.45, 0.0, 1.0)

# ------------------------------------------------------------------------------
# Streaming Galaxy Map: Fast Sector Star Generation (Thread-Safe)
# ------------------------------------------------------------------------------

## Generates visual star points for a streaming sector using stratified
## jittered rejection sampling. Fully deterministic and thread-safe.
## Called from WorkerThreadPool background threads.
static func generate_sector_stars(
	sec_x: int, sec_y: int, sec_z: int,
	sector_size: float = 2500.0,
	max_stars_per_sector: int = 600
) -> Array[Dictionary]:
	var stars: Array[Dictionary] = []
	
	var origin := Vector3(sec_x, sec_y, sec_z) * sector_size
	
	# Quick density check at sector center - skip empty space entirely
	var center := origin + Vector3.ONE * (sector_size * 0.5)
	var center_density := get_stellar_density(center)
	if center_density < 0.001:
		return stars
	
	# Deterministic seed from sector coordinates
	var sec_seed := hash_coords(sec_x, sec_y, sec_z, GALAXY_SEED + 0xAABB)
	
	# Stratified jittered sampling: 8x2x8 sub-grid (128 candidate cells)
	var subdiv_x := 8
	var subdiv_y := 2 # Galaxy is thin
	var subdiv_z := 8
	var cell_x := sector_size / float(subdiv_x)
	var cell_y := sector_size / float(subdiv_y)
	var cell_z := sector_size / float(subdiv_z)
	
	var star_count := 0
	
	for cx in range(subdiv_x):
		for cy in range(subdiv_y):
			for cz in range(subdiv_z):
				if star_count >= max_stars_per_sector:
					break
				
				# Deterministic jitter per sub-cell
				var cell_seed := hash_coords(cx + sec_x * 31, cy + sec_y * 17, cz + sec_z * 7, sec_seed)
				var jx := hash_to_float(hash_coords(cell_seed, 1, 2))
				var jy := hash_to_float(hash_coords(cell_seed, 3, 4))
				var jz := hash_to_float(hash_coords(cell_seed, 5, 6))
				
				var pos_ly := Vector3(
					origin.x + (float(cx) + jx) * cell_x,
					origin.y + (float(cy) + jy) * cell_y,
					origin.z + (float(cz) + jz) * cell_z
				)
				
				# Evaluate density at candidate position
				var density := get_stellar_density(pos_ly)
				
				# Rejection test (deterministic)
				var reject_roll := hash_to_float(hash_coords(cell_seed, 7, 8))
				if reject_roll < density:
					# Additional sub-sampling: generate 1-4 extra stars if density is high
					var extra := 1 + int(density * 3.0)
					for ei in range(extra):
						if star_count >= max_stars_per_sector:
							break
						var star_seed := hash_coords(cell_seed, ei * 13, ei * 29)
						var offset_x := hash_to_float(hash_coords(star_seed, 10, 20)) * cell_x * 0.8
						var offset_y := hash_to_float(hash_coords(star_seed, 30, 40)) * cell_y * 0.8
						var offset_z := hash_to_float(hash_coords(star_seed, 50, 60)) * cell_z * 0.8
						var final_pos := pos_ly + Vector3(offset_x, offset_y, offset_z)

						# Derive luminosity from IMF-sampled mass (real physics)
						var imf_roll := hash_to_float(hash_coords(star_seed, 77, 88))
						var m_sol := sample_imf_mass(imf_roll)
						var l_sol := mass_to_luminosity(m_sol)
						var r_sol := mass_to_radius(m_sol)
						var t_k := luminosity_radius_to_temperature(l_sol, r_sol)
						var spec_idx := float(temperature_to_spectral_class(t_k)) / 7.0

						stars.append({
							"position": final_pos,
							"galactic_pos": final_pos,
							"spectral_idx": spec_idx,
							"luminosity": clampf(log(l_sol + 1.0) / log(100.0), 0.05, 1.0),
							"name": "BIO-%04d" % (star_seed % 9999),
							"seed": star_seed
						})
						star_count += 1

	return stars

# ------------------------------------------------------------------------------
# Galactic Feature Generation (Globular Clusters, HII Regions, GMCs, etc.)
# ------------------------------------------------------------------------------

## Generates all globular clusters in the galaxy. ~157 known (Harris catalog).
## Distributed in the stellar halo with a power-law radial profile.
## Each cluster: 10^4 to 10^6 stars, half-light radius 3-33 LY.
static func generate_globular_clusters() -> Array[Dictionary]:
	var clusters: Array[Dictionary] = []
	for i in range(GLOBULAR_CLUSTER_COUNT):
		var seed_val := hash_coords(i, 0x6C, 0, GALAXY_SEED)
		var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
		var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
		var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
		var u4 := hash_to_float(hash_coords(seed_val, 7, 8))

		# Radial distribution: power-law biased toward inner halo
		# r = R_core * (1/(1-u))^(1/2.5) for r > R_core
		var r: float = CORE_RADIUS_LY * pow(1.0 / maxf(1.0 - u1, 0.01), 1.0 / 2.5)
		r = clampf(r, CORE_RADIUS_LY * 0.5, STELLAR_HALO_RADIUS_LY * 0.9)

		# Spherical distribution
		var phi: float = u2 * TAU
		var cos_theta: float = 1.0 - 2.0 * u3
		var sin_theta: float = sqrt(1.0 - cos_theta * cos_theta)
		var pos := Vector3(
			r * sin_theta * cos(phi),
			r * cos_theta,
			r * sin_theta * sin(phi)
		)

		# Cluster properties
		var half_light_radius: float = GLOBULAR_CLUSTER_MAX_RADIUS_LY * (0.1 + u4 * 0.9)
		var star_count: int = int(GLOBULAR_CLUSTER_MIN_STARS + u4 * (GLOBULAR_CLUSTER_MAX_STARS - GLOBULAR_CLUSTER_MIN_STARS))
		# Metallicity: halo clusters are metal-poor [Fe/H] ~ -1.5 to -2.5
		var metallicity: float = -2.5 + u1 * 1.0

		# Real named clusters for known ones (first ~15)
		var name: String = "NGC-%04d" % (seed_val % 9999)
		if i == 0: name = "Omega Centauri"
		elif i == 1: name = "47 Tucanae"
		elif i == 2: name = "M13 (Hercules)"
		elif i == 3: name = "M3"
		elif i == 4: name = "M5"
		elif i == 5: name = "M15"
		elif i == 6: name = "M2"
		elif i == 7: name = "M92"
		elif i == 8: name = "NGC 2808"
		elif i == 9: name = "NGC 7078"
		elif i == 10: name = "M22 (Sagittarius)"
		elif i == 11: name = "M10"
		elif i == 12: name = "M12"
		elif i == 13: name = "M71"
		elif i == 14: name = "M55"

		clusters.append({
			"index": i,
			"name": name,
			"position": pos,
			"galactic_pos": pos,
			"half_light_radius_ly": half_light_radius,
			"star_count": star_count,
			"metallicity_fe_h": metallicity,
			"age_gyr": 12.0 + u4 * 1.5,  # 12-13.5 Gyr (ancient)
			"seed": seed_val
		})
	return clusters

## Generates HII regions — ionized nebulae around hot O/B stars in spiral arms.
## Pink/red color from Hα recombination emission at 656.3 nm.
## Size: 1-100 pc (3-330 LY). Found in spiral arms where massive stars form.
static func generate_hii_regions() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	for i in range(HII_REGION_COUNT):
		var seed_val := hash_coords(i, 0x12, 0, GALAXY_SEED)
		var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
		var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
		var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
		var u4 := hash_to_float(hash_coords(seed_val, 7, 8))

		# Place in spiral arms — sample along arm paths
		var r: float = 5000.0 + u1 * (GALAXY_RADIUS_LY - 5000.0)
		var arm_idx: int = int(u2 * SPIRAL_ARM_COUNT)
		var log_r: float = log(r / 1000.0) / SPIRAL_ARM_PITCH
		var arm_phase: float = (float(arm_idx) / float(SPIRAL_ARM_COUNT)) * TAU
		var theta: float = log_r + arm_phase + (u3 - 0.5) * 0.3  # Small scatter from arm center

		# Vertical scatter (thin disk — HII regions are young)
		var z: float = (u4 - 0.5) * GALAXY_THICKNESS_LY * 0.3

		var pos := Vector3(r * cos(theta), z, r * sin(theta))

		# Size: log-uniform from 3 to 330 LY
		var log_size: float = log(HII_REGION_MIN_RADIUS_LY) + u4 * (log(HII_REGION_MAX_RADIUS_LY) - log(HII_REGION_MIN_RADIUS_LY))
		var radius: float = exp(log_size)

		# Hα emission: 656.3 nm → pink/red color
		# Temperature ~10,000 K (ionized hydrogen)
		var color := blackbody_color(HII_REGION_TEMP_K)
		# Boost red for Hα dominance
		color = Color(color.r * 1.2, color.g * 0.6, color.b * 0.7)

		regions.append({
			"index": i,
			"position": pos,
			"galactic_pos": pos,
			"radius_ly": radius,
			"temperature_k": HII_REGION_TEMP_K,
			"color": color,
			"emission_line_nm": 656.3,  # Hα
			"seed": seed_val
		})
	return regions

## Generates Giant Molecular Clouds (GMCs) — cold CO/H₂ in spiral arms.
## Dark absorption patches. Mass: 10^4-10^6 M_sun. Size: 10-100 pc (33-330 LY).
static func generate_molecular_clouds() -> Array[Dictionary]:
	var clouds: Array[Dictionary] = []
	for i in range(MOLECULAR_CLOUD_COUNT):
		var seed_val := hash_coords(i, 0xAC0, 0, GALAXY_SEED)
		var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
		var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
		var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
		var u4 := hash_to_float(hash_coords(seed_val, 7, 8))

		# Place in spiral arms
		var r: float = 3000.0 + u1 * (GALAXY_RADIUS_LY - 3000.0)
		var arm_idx: int = int(u2 * SPIRAL_ARM_COUNT)
		var log_r: float = log(r / 1000.0) / SPIRAL_ARM_PITCH
		var arm_phase: float = (float(arm_idx) / float(SPIRAL_ARM_COUNT)) * TAU
		var theta: float = log_r + arm_phase + (u3 - 0.5) * 0.4

		var z: float = (u4 - 0.5) * GALAXY_THICKNESS_LY * 0.2

		var pos := Vector3(r * cos(theta), z, r * sin(theta))

		var log_size: float = log(MOLECULAR_CLOUD_MIN_RADIUS_LY) + u4 * (log(MOLECULAR_CLOUD_MAX_RADIUS_LY) - log(MOLECULAR_CLOUD_MIN_RADIUS_LY))
		var radius: float = exp(log_size)
		var mass_sol: float = 1e4 + u1 * 9.9e5  # 10^4 to 10^6 M_sun

		clouds.append({
			"index": i,
			"position": pos,
			"galactic_pos": pos,
			"radius_ly": radius,
			"mass_sol": mass_sol,
			"temperature_k": MOLECULAR_CLOUD_TEMP_K,
			"color": Color(0.15, 0.1, 0.08),  # Dark brownish-red (extinction)
			"seed": seed_val
		})
	return clouds

## Generates satellite galaxies of the Milky Way.
## Real positions for known satellites; procedural for the rest.
static func generate_satellite_galaxies() -> Array[Dictionary]:
	var galaxies: Array[Dictionary] = []

	# Known satellites with real data (McConnachie 2012)
	var known := [
		# name, distance_ly, diameter_ly, ra_deg, dec_deg, type
		["Large Magellanic Cloud", 163000.0, 14000.0, 80.89, -69.76, "Irregular"],
		["Small Magellanic Cloud", 200000.0, 7000.0, 13.16, -72.80, "Irregular"],
		["Sagittarius Dwarf", 70000.0, 10000.0, 283.83, -30.48, "Elliptical (tidal)"],
		["Canis Major Dwarf", 28000.0, 5000.0, 105.0, -28.0, "Irregular"],
		["Ursa Minor Dwarf", 200000.0, 2000.0, 224.28, 67.21, "Elliptical"],
		["Draco Dwarf", 260000.0, 1500.0, 260.05, 57.92, "Elliptical"],
		["Carina Dwarf", 330000.0, 1000.0, 100.41, -50.68, "Elliptical"],
		["Fornax Dwarf", 460000.0, 6000.0, 39.99, -34.45, "Elliptical"],
		["Leo I", 820000.0, 900.0, 152.12, 12.31, "Elliptical"],
		["Leo II", 690000.0, 700.0, 168.37, 22.15, "Elliptical"],
		["Sculptor Dwarf", 280000.0, 1500.0, 15.04, -33.71, "Elliptical"],
		["Sextans Dwarf", 290000.0, 1500.0, 153.26, -1.61, "Elliptical"],
	]

	for i in range(SATELLITE_GALAXY_COUNT):
		var name: String
		var pos: Vector3
		var diameter: float
		var galaxy_type: String

		if i < known.size():
			var data = known[i]
			name = data[0]
			var dist: float = data[1]
			diameter = data[2]
			var ra_rad: float = deg_to_rad(float(data[3]))
			var dec_rad: float = deg_to_rad(float(data[4]))
			galaxy_type = data[5]
			# Convert RA/Dec/distance to galactic XYZ (simplified)
			# Galactic center is at origin, Sun at (0, 15, 26000)
			pos = Vector3(
				dist * cos(dec_rad) * cos(ra_rad - PI),
				dist * sin(dec_rad),
				dist * cos(dec_rad) * sin(ra_rad - PI)
			)
		else:
			var seed_val := hash_coords(i, 0x56, 0, GALAXY_SEED)
			var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
			var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
			var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
			var u4 := hash_to_float(hash_coords(seed_val, 7, 8))

			# Ultra-faint dwarfs: 100k-1M LY, 100-1000 LY diameter
			var dist: float = 50000.0 + u1 * 950000.0
			var phi: float = u2 * TAU
			var cos_theta: float = 1.0 - 2.0 * u3
			var sin_theta: float = sqrt(1.0 - cos_theta * cos_theta)
			pos = Vector3(dist * sin_theta * cos(phi), dist * cos_theta, dist * sin_theta * sin(phi))
			diameter = 100.0 + u4 * 900.0
			name = "Dwarf-%04d" % (seed_val % 9999)
			galaxy_type = "Ultra-faint dwarf"

		galaxies.append({
			"index": i,
			"name": name,
			"position": pos,
			"galactic_pos": pos,
			"diameter_ly": diameter,
			"type": galaxy_type,
			"seed": hash_coords(i, 0x56, 0, GALAXY_SEED)
		})
	return galaxies

## Generates stellar streams — tidal debris from disrupted dwarf galaxies.
## Sagittarius stream is the most prominent, wrapping around the galaxy.
static func generate_stellar_streams() -> Array[Dictionary]:
	var streams: Array[Dictionary] = []

	# Known streams with real orbital parameters
	var known_streams := [
		# name, mean_radius_ly, inclination_deg, phase_offset_deg, length_deg, star_count
		["Sagittarius Stream", 45000.0, 75.0, 0.0, 360.0, 10000],
		["GD-1", 28000.0, 60.0, 45.0, 120.0, 3000],
		["Orphan Stream", 35000.0, 50.0, 90.0, 100.0, 2000],
		["Cetus Stream", 60000.0, 80.0, 180.0, 90.0, 1500],
		["Phoenix Stream", 55000.0, 70.0, 270.0, 80.0, 1000],
	]

	for i in range(STELLAR_STREAM_COUNT):
		var name: String
		var mean_r: float
		var incl: float
		var phase: float
		var length_deg: float
		var star_count: int

		if i < known_streams.size():
			var data = known_streams[i]
			name = data[0]
			mean_r = data[1]
			incl = deg_to_rad(data[2])
			phase = deg_to_rad(data[3])
			length_deg = data[4]
			star_count = data[5]
		else:
			var seed_val := hash_coords(i, 0x57, 0, GALAXY_SEED)
			var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
			var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
			var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
			mean_r = 20000.0 + u1 * 80000.0
			incl = u2 * PI
			phase = u3 * TAU
			length_deg = 30.0 + u1 * 150.0
			star_count = 500 + int(u2 * 3000)
			name = "Stream-%04d" % (seed_val % 9999)

		# Generate stream points along a great circle
		var points: Array[Vector3] = []
		var n_points: int = int(float(star_count) / 100.0)
		for j in range(n_points):
			var t: float = float(j) / float(n_points)
			var angle: float = phase + t * deg_to_rad(length_deg)
			# Great circle in the inclined plane
			var x: float = mean_r * cos(angle)
			var z: float = mean_r * sin(angle) * cos(incl)
			var y: float = mean_r * sin(angle) * sin(incl)
			# Add small scatter
			var seed_val := hash_coords(i * 100 + j, 0x57, 0, GALAXY_SEED)
			var scatter: float = 500.0
			x += (hash_to_float(hash_coords(seed_val, 1, 2)) - 0.5) * scatter
			y += (hash_to_float(hash_coords(seed_val, 3, 4)) - 0.5) * scatter
			z += (hash_to_float(hash_coords(seed_val, 5, 6)) - 0.5) * scatter
			points.append(Vector3(x, y, z))

		streams.append({
			"index": i,
			"name": name,
			"mean_radius_ly": mean_r,
			"points": points,
			"star_count": star_count,
			"length_deg": length_deg,
			"seed": hash_coords(i, 0x57, 0, GALAXY_SEED)
		})
	return streams

## Generates supernova remnants — expanding shells from supernova explosions.
## ~300 known (Green 2019). Size: 1-50 pc (3-163 LY). Short-lived.
static func generate_supernova_remnants() -> Array[Dictionary]:
	var remnants: Array[Dictionary] = []
	for i in range(SNR_COUNT):
		var seed_val := hash_coords(i, 0x5E, 0, GALAXY_SEED)
		var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
		var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
		var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
		var u4 := hash_to_float(hash_coords(seed_val, 7, 8))

		# Distribute in disk (supernovae come from short-lived massive stars)
		var r: float = 2000.0 + u1 * (GALAXY_RADIUS_LY - 2000.0)
		var theta: float = u2 * TAU
		var z: float = (u3 - 0.5) * GALAXY_THICKNESS_LY * 0.2
		var pos := Vector3(r * cos(theta), z, r * sin(theta))

		var log_size: float = log(SNR_MIN_RADIUS_LY) + u4 * (log(SNR_MAX_RADIUS_LY) - log(SNR_MIN_RADIUS_LY))
		var radius: float = exp(log_size)

		# Age: 100 to 100,000 years
		var age_years: float = 100.0 + u4 * 99900.0

		# Color: greenish-blue from [O III] emission in young SNRs, reddish in old
		var color: Color
		if age_years < 1000.0:
			color = Color(0.3, 0.8, 0.6)  # Young: greenish (Crab-like)
		else:
			color = Color(0.6, 0.4, 0.3)  # Old: reddish

		remnants.append({
			"index": i,
			"position": pos,
			"galactic_pos": pos,
			"radius_ly": radius,
			"age_years": age_years,
			"color": color,
			"seed": seed_val
		})
	return remnants

## Generates planetary nebulae — shells from dying low-mass stars.
## ~3000+ known. Size: 0.1-1 pc (0.3-3.3 LY). Short-lived (~10^4 years).
static func generate_planetary_nebulae() -> Array[Dictionary]:
	var nebulae: Array[Dictionary] = []
	for i in range(PN_COUNT):
		var seed_val := hash_coords(i, 0x9E, 0, GALAXY_SEED)
		var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
		var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
		var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
		var u4 := hash_to_float(hash_coords(seed_val, 7, 8))

		# Distribute throughout disk and bulge (old low-mass stars everywhere)
		var r: float = u1 * GALAXY_RADIUS_LY
		var theta: float = u2 * TAU
		var z: float = (u3 - 0.5) * GALAXY_THICKNESS_LY
		var pos := Vector3(r * cos(theta), z, r * sin(theta))

		var log_size: float = log(PN_MIN_RADIUS_LY) + u4 * (log(PN_MAX_RADIUS_LY) - log(PN_MIN_RADIUS_LY))
		var radius: float = exp(log_size)

		# Color: greenish from [O III] 500.7nm, or bluish from central star
		var color: Color
		if u4 < 0.5:
			color = Color(0.3, 0.7, 0.5)  # [O III] green
		else:
			color = Color(0.5, 0.6, 0.9)  # Central star blue

		nebulae.append({
			"index": i,
			"position": pos,
			"galactic_pos": pos,
			"radius_ly": radius,
			"color": color,
			"seed": seed_val
		})
	return nebulae

## Generates open clusters — young stellar associations in spiral arms.
## ~2000+ known (Dias catalog). 10-1000 stars. Size: 1-10 pc (3-33 LY).
static func generate_open_clusters() -> Array[Dictionary]:
	var clusters: Array[Dictionary] = []
	for i in range(OPEN_CLUSTER_COUNT):
		var seed_val := hash_coords(i, 0x0C, 0, GALAXY_SEED)
		var u1 := hash_to_float(hash_coords(seed_val, 1, 2))
		var u2 := hash_to_float(hash_coords(seed_val, 3, 4))
		var u3 := hash_to_float(hash_coords(seed_val, 5, 6))
		var u4 := hash_to_float(hash_coords(seed_val, 7, 8))

		# Place in spiral arms (young stars)
		var r: float = 3000.0 + u1 * (GALAXY_RADIUS_LY - 3000.0)
		var arm_idx: int = int(u2 * SPIRAL_ARM_COUNT)
		var log_r: float = log(r / 1000.0) / SPIRAL_ARM_PITCH
		var arm_phase: float = (float(arm_idx) / float(SPIRAL_ARM_COUNT)) * TAU
		var theta: float = log_r + arm_phase + (u3 - 0.5) * 0.2
		var z: float = (u4 - 0.5) * GALAXY_THICKNESS_LY * 0.2

		var pos := Vector3(r * cos(theta), z, r * sin(theta))

		var radius: float = OPEN_CLUSTER_MIN_RADIUS_LY + u4 * (OPEN_CLUSTER_MAX_RADIUS_LY - OPEN_CLUSTER_MIN_RADIUS_LY)
		var star_count: int = 10 + int(u4 * 990)
		var age_myr: float = u1 * 500.0  # 0-500 Myr (young)

		# Named clusters for first ~20
		var name: String = "OC-%04d" % (seed_val % 9999)
		if i == 0: name = "Pleiades (M45)"
		elif i == 1: name = "Hyades"
		elif i == 2: name = "Praesepe (M44)"
		elif i == 3: name = "M6 (Butterfly)"
		elif i == 4: name = "M7 (Ptolemy)"
		elif i == 5: name = "M11 (Wild Duck)"
		elif i == 6: name = "M41"
		elif i == 7: name = "M47"
		elif i == 8: name = "M67"
		elif i == 9: name = "M39"
		elif i == 10: name = "M34"
		elif i == 11: name = "M35"
		elif i == 12: name = "M36"
		elif i == 13: name = "M37"
		elif i == 14: name = "M38"
		elif i == 15: name = "M48"
		elif i == 16: name = "M50"
		elif i == 17: name = "M52"
		elif i == 18: name = "M103"
		elif i == 19: name = "NGC 869 (Double Cluster)"

		clusters.append({
			"index": i,
			"name": name,
			"position": pos,
			"galactic_pos": pos,
			"radius_ly": radius,
			"star_count": star_count,
			"age_myr": age_myr,
			"seed": seed_val
		})
	return clusters

# ------------------------------------------------------------------------------
# Sector Query & Deterministic Star System Generation
# ------------------------------------------------------------------------------

## Retrieves all deterministic star systems generated in a given galactic sector.
static func get_systems_in_sector(sec_x: int, sec_y: int, sec_z: int) -> Array[Dictionary]:
	var systems: Array[Dictionary] = []
	var sec_origin_ly := Vector3(sec_x, sec_y, sec_z) * SECTOR_SIZE_LY
	var sec_center := sec_origin_ly + Vector3.ONE * (SECTOR_SIZE_LY * 0.5)

	var density := get_stellar_density(sec_center)
	if density < 0.005:
		return systems

	var sec_seed := hash_coords(sec_x, sec_y, sec_z, GALAXY_SEED)

	# Real star count: compute from actual stellar density, then cull for performance.
	# The density model returns a normalized [0,1] value that encodes the relative
	# spatial density profile (bulge, disc, arms). We scale it by the real local
	# stellar number density (0.004 stars/ly³ in the solar neighborhood) to get
	# the true star count, then multiply by DENSITY_CULL_FACTOR (1%) for performance.
	var sector_volume_ly3: float = SECTOR_SIZE_LY ** 3
	var real_star_count: float = density * REAL_LOCAL_STELLAR_DENSITY_PER_LY3 * sector_volume_ly3
	var culled_star_count: int = max(1, int(real_star_count * DENSITY_CULL_FACTOR))
	# Cap to a reasonable per-sector maximum for the detailed system generator
	const MAX_DETAILED_STARS_PER_SECTOR := 20
	var max_stars_in_sector := mini(culled_star_count, MAX_DETAILED_STARS_PER_SECTOR)

	for i in range(max_stars_in_sector):
		var star_seed := hash_coords(sec_x * 31 + i, sec_y * 17 + i, sec_z * 7 + i, sec_seed)
		var star_data := generate_star_system(star_seed, sec_origin_ly)
		systems.append(star_data)

	return systems

## Generates a complete, deterministic star system with host star, planets, orbits, and resources.
static func generate_star_system(system_seed: int, sector_offset_ly: Vector3 = Vector3.ZERO) -> Dictionary:
	var h1 := hash_coords(system_seed, 101, 202)
	var h2 := hash_coords(system_seed, 303, 404)
	var h3 := hash_coords(system_seed, 505, 606)

	# 1. 3D Coordinates within Galactic Sector
	var local_pos := Vector3(
		hash_to_float(h1) * SECTOR_SIZE_LY,
		hash_to_float(h2) * (SECTOR_SIZE_LY * 0.6) - (SECTOR_SIZE_LY * 0.3),
		hash_to_float(h3) * SECTOR_SIZE_LY
	)
	var galactic_pos := sector_offset_ly + local_pos

	# 2. Stellar Classification — Kroupa IMF + Mass-Derived Properties
	# Sample a stellar mass from the real Kroupa (2001) Initial Mass Function,
	# then derive ALL physical properties (L, R, T, color) from that mass
	# using standard main-sequence relations.
	var imf_roll := hash_to_float(hash_coords(system_seed, 777, 888))
	var stellar_evolution_roll := hash_to_float(hash_coords(system_seed, 888, 999))

	var spectral_type: int = SpectralClass.CLASS_M
	var star_temp_k: float = 3200.0
	var star_lum_sol: float = 0.02
	var star_mass_sol: float = 0.25
	var star_radius_km: float = 280000.0
	var star_color: Color = Color(1.0, 0.45, 0.25)
	var star_name_prefix: String = "BIO"

	# Rare stellar remnants (not on the main sequence, so not sampled by IMF)
	# Rates from observational statistics: ~0.01% black holes, ~0.07% neutron stars
	if stellar_evolution_roll < 0.0001:
		# Stellar-mass black hole: forms from stars >25 M_sun
		# Mass distribution from gravitational wave observations (LIGO/Virgo O3):
		# 5-40 M_sun, with a mass gap at 45-120 M_sun (pair-instability)
		var bh_mass_roll := hash_to_float(hash_coords(system_seed, 111, 222))
		star_mass_sol = 5.0 + bh_mass_roll * 35.0  # 5-40 M_sun
		star_temp_k = 0.0  # No thermal emission
		star_lum_sol = 0.0
		# Schwarzschild radius: R_s = 2GM/c² = 2.95 km * (M/M_sun)
		star_radius_km = 2.95 * star_mass_sol
		star_color = Color(0.0, 0.0, 0.0)
		spectral_type = SpectralClass.BLACK_HOLE
		star_name_prefix = "SINGULARITY"
	elif stellar_evolution_roll < 0.0008:
		# Neutron star: forms from stars 8-25 M_sun
		# Tolman-Oppenheimer-Volkoff limit: 1.4-2.16 M_sun
		var ns_mass_roll := hash_to_float(hash_coords(system_seed, 111, 222))
		star_mass_sol = 1.4 + ns_mass_roll * 0.8  # 1.4-2.2 M_sun
		star_temp_k = 1000000.0  # Surface T ~10^6 K (cooling NS)
		# L = 4πR²σT⁴ for R=12km, T=10^6K → very low bolometric luminosity
		star_lum_sol = 0.001
		star_radius_km = 12.0  # Typical NS radius (Lattimer & Prakash 2001)
		star_color = Color(0.7, 0.9, 1.0)
		spectral_type = SpectralClass.NEUTRON_STAR
		star_name_prefix = "PULSAR"
	else:
		# Main-sequence star: sample mass from Kroupa IMF
		star_mass_sol = sample_imf_mass(imf_roll)

		# Derive luminosity from mass-luminosity relation (Eker et al. 2018)
		star_lum_sol = mass_to_luminosity(star_mass_sol)

		# Derive radius from mass-radius relation (Eker et al. 2018)
		var star_radius_sol: float = mass_to_radius(star_mass_sol)
		star_radius_km = star_radius_sol * SOLAR_RADIUS_KM

		# Derive effective temperature from Stefan-Boltzmann: L = 4πR²σT⁴
		star_temp_k = luminosity_radius_to_temperature(star_lum_sol, star_radius_sol)

		# Derive color from blackbody temperature (Planckian locus)
		star_color = blackbody_color(star_temp_k)

		# Classify spectral type from temperature (Morgan-Keenan boundaries)
		spectral_type = temperature_to_spectral_class(star_temp_k)

		# Name prefix by spectral class
		match spectral_type:
			SpectralClass.CLASS_O: star_name_prefix = "HYPERION"
			SpectralClass.CLASS_B: star_name_prefix = "RIGEL"
			SpectralClass.CLASS_A: star_name_prefix = "SIRIUS"
			SpectralClass.CLASS_F: star_name_prefix = "PROCYON"
			SpectralClass.CLASS_G: star_name_prefix = "SOLARIS"
			SpectralClass.CLASS_K: star_name_prefix = "ALDER"
			SpectralClass.CLASS_M: star_name_prefix = "PROXIMA"
			_: star_name_prefix = "BIO"

	# Generate Distinct System Designation Name
	var sys_id_num := system_seed % 9999
	var system_name := "%s-%04d" % [star_name_prefix, sys_id_num]

	# 3. Habitable Zone (Kopparapu et al. 2013) & Frost Line
	var hz := habitable_zone(star_lum_sol, star_temp_k)
	var hab_zone_inner_au: float = hz.x
	var hab_zone_outer_au: float = hz.y
	var frost_line_au: float = frost_line(star_lum_sol)

	# 4. Deterministic Planetary Generation (Titius-Bode Law)
	var planet_count_roll := hash_to_float(hash_coords(system_seed, 919, 929))
	var planet_count := 2 + int(planet_count_roll * 8.0) # 2 to 10 planets
	var planets: Array[Dictionary] = []

	var current_orbit_au: float = maxf(0.15, sqrt(star_lum_sol) * 0.25)

	for p_idx in range(planet_count):
		var p_seed := hash_coords(system_seed, p_idx * 53, p_idx * 97)
		var p_roll1 := hash_to_float(hash_coords(p_seed, 11, 22))
		var p_roll2 := hash_to_float(hash_coords(p_seed, 33, 44))
		var p_roll3 := hash_to_float(hash_coords(p_seed, 55, 66))

		# Titius-Bode geometric spacing progression
		# Real solar system ratios: Mercury→Venus=1.87, Venus→Earth=1.36, Earth→Mars=1.52,
		# Mars→Ceres=1.78, Ceres→Jupiter=2.82, Jupiter→Saturn=1.83, Saturn→Uranus=2.02
		# Use 1.5 to 2.2 for realistic spacing that prevents visual overlap
		var spacing_factor := 1.5 + p_roll1 * 0.7
		current_orbit_au *= spacing_factor

		# Determine Planet Archetype based on Orbit Distance relative to Habitable Zone & Frost Line
		# Mass is sampled first, then radius is derived from the mass-radius relation.
		var archetype: int = PlanetArchetype.METALLIC_BARREN
		var mass_earth: float = 1.0
		var radius_km: float = 6371.0
		var atmosphere_density: float = 1.0
		var has_rings: bool = false
		var planet_color: Color = Color(0.5, 0.5, 0.5)

		if current_orbit_au < hab_zone_inner_au:
			# Inner Scorched Zone — close to star, high temperature
			if p_roll2 < 0.45:
				archetype = PlanetArchetype.MOLTEN
				# Magma worlds: 0.3-1.5 M_earth (Kepler observations)
				mass_earth = 0.3 + p_roll3 * 1.2
				radius_km = planet_mass_to_radius(mass_earth, false, false)
				# Thick atmosphere from outgassing (Venus-like)
				atmosphere_density = 3.5 + p_roll2 * 8.0
				planet_color = Color(1.0, 0.35, 0.1)
			elif p_roll2 < 0.85:
				archetype = PlanetArchetype.METALLIC_BARREN
				# Barren rocky: 0.1-1.0 M_earth (Mercury-like)
				mass_earth = 0.1 + p_roll3 * 0.9
				radius_km = planet_mass_to_radius(mass_earth, false, false)
				atmosphere_density = 0.05
				planet_color = Color(0.65, 0.58, 0.52)
			else:
				archetype = PlanetArchetype.DESERT_ARID
				# Desert: 0.3-2.0 M_earth (Mars-like to super-Earth)
				mass_earth = 0.3 + p_roll3 * 1.7
				radius_km = planet_mass_to_radius(mass_earth, false, false)
				atmosphere_density = 0.6
				planet_color = Color(0.85, 0.65, 0.35)
		elif current_orbit_au <= hab_zone_outer_au:
			# Goldilocks Habitable Zone
			if p_roll2 < 0.55:
				archetype = PlanetArchetype.TERRAN_OCEANIC
				# Terran: 0.5-2.0 M_earth (Earth to super-Earth)
				mass_earth = 0.5 + p_roll3 * 1.5
				radius_km = planet_mass_to_radius(mass_earth, false, false)
				atmosphere_density = 1.0
				planet_color = Color(0.15, 0.55, 0.85)
			elif p_roll2 < 0.80:
				archetype = PlanetArchetype.RADIOTROPHIC_BIO
				# Exotic bio-world: 0.8-3.0 M_earth
				mass_earth = 0.8 + p_roll3 * 2.2
				radius_km = planet_mass_to_radius(mass_earth, false, false)
				atmosphere_density = 1.8
				planet_color = Color(0.2, 0.9, 0.6)
			else:
				archetype = PlanetArchetype.DESERT_ARID
				mass_earth = 0.3 + p_roll3 * 1.7
				radius_km = planet_mass_to_radius(mass_earth, false, false)
				atmosphere_density = 0.8
				planet_color = Color(0.9, 0.6, 0.3)
		else:
			# Outer Cold Zone Beyond Frost Line
			if p_roll2 < 0.45:
				archetype = PlanetArchetype.GAS_GIANT_JOVIAN
				# Jovian: 50-320 M_earth (Jupiter = 318 M_earth)
				mass_earth = 50.0 + p_roll3 * 270.0
				radius_km = planet_mass_to_radius(mass_earth, true, false)
				atmosphere_density = 45.0
				has_rings = (p_roll1 > 0.4)
				planet_color = Color(0.88, 0.72, 0.52)
			elif p_roll2 < 0.75:
				archetype = PlanetArchetype.GAS_GIANT_ICE
				# Ice giant: 10-30 M_earth (Neptune = 17 M_earth)
				mass_earth = 10.0 + p_roll3 * 20.0
				radius_km = planet_mass_to_radius(mass_earth, false, true)
				atmosphere_density = 25.0
				has_rings = (p_roll1 > 0.6)
				planet_color = Color(0.25, 0.75, 0.85)
			else:
				archetype = PlanetArchetype.ICE_WORLD
				# Ice world: 0.1-1.0 M_earth (Europa/Enceladus-like)
				mass_earth = 0.1 + p_roll3 * 0.9
				radius_km = planet_mass_to_radius(mass_earth, false, false)
				atmosphere_density = 0.2
				planet_color = Color(0.85, 0.92, 1.0)

		var planet_name := "%s %c" % [system_name, 65 + p_idx] # e.g. "SOLARIS-4912 B"

		# ----------------------------------------------------------------------
		# Full Keplerian Orbital Mechanics & Dynamics
		# ----------------------------------------------------------------------
		# Eccentricity from Rayleigh distribution (exoplanet statistics)
		# Multi-planet systems have lower mean eccentricity due to dynamical relaxation
		var is_multi_planet: bool = planet_count > 1
		var eccentricity := sample_eccentricity(p_roll1, is_multi_planet)
		var semi_major_axis_au := current_orbit_au
		var semi_minor_axis_au := semi_major_axis_au * sqrt(maxf(0.01, 1.0 - eccentricity * eccentricity))
		var periapsis_au := semi_major_axis_au * (1.0 - eccentricity)
		var apoapsis_au := semi_major_axis_au * (1.0 + eccentricity)
		
		# 3D Orbital Plane Orientation (Euler Angles)
		var inclination_deg := (p_roll2 - 0.5) * 12.0 # -6° to +6° orbital inclination
		var longitude_ascending_node_deg := p_roll3 * 360.0 # Ω
		var argument_periapsis_deg := p_roll1 * 360.0 # ω
		var mean_anomaly_epoch_rad := p_roll2 * TAU # M0

		# Planetary Axial Tilt & Sidereal Rotation (Day/Night Dynamics)
		var axial_tilt_deg := p_roll3 * 28.5 # e.g. Earth = 23.44°, Mars = 25.19°
		var is_tidally_locked := (semi_major_axis_au < 0.08 or (spectral_type == SpectralClass.CLASS_M and semi_major_axis_au < 0.18))
		var sidereal_rotation_period_hours := 24.0
		if is_tidally_locked:
			# Rotation period equals orbital period
			sidereal_rotation_period_hours = sqrt(semi_major_axis_au ** 3 / maxf(0.1, star_mass_sol)) * 365.25 * 24.0
		else:
			sidereal_rotation_period_hours = 8.0 + p_roll2 * 36.0 # 8h to 44h day length

		var orbit_km := semi_major_axis_au * 149597870.7
		var orbit_light_seconds := orbit_km / 299792.458
		var mass_kg := mass_earth * 5.9722e24
		
		# Surface Gravity: g = G * M / R^2
		var radius_ratio := radius_km / 6371.0
		var surface_gravity_g := mass_earth / maxf(0.01, radius_ratio * radius_ratio)
		var surface_gravity_ms2 := surface_gravity_g * 9.80665

		# Bond Albedo by archetype
		var bond_albedo := 0.30
		if archetype == PlanetArchetype.MOLTEN: bond_albedo = 0.12
		elif archetype == PlanetArchetype.METALLIC_BARREN: bond_albedo = 0.15
		elif archetype == PlanetArchetype.DESERT_ARID: bond_albedo = 0.28
		elif archetype == PlanetArchetype.TERRAN_OCEANIC: bond_albedo = 0.33
		elif archetype == PlanetArchetype.ICE_WORLD: bond_albedo = 0.62
		elif archetype == PlanetArchetype.GAS_GIANT_JOVIAN: bond_albedo = 0.44
		elif archetype == PlanetArchetype.GAS_GIANT_ICE: bond_albedo = 0.48
		elif archetype == PlanetArchetype.RADIOTROPHIC_BIO: bond_albedo = 0.25

		# Stefan-Boltzmann Equilibrium Surface Temperature: T_eq = T_star * sqrt(R_star / (2 * d)) * (1 - A)^0.25
		var star_rad_m := star_radius_km * 1000.0
		var dist_m := orbit_km * 1000.0
		var temp_k := star_temp_k * sqrt(star_rad_m / (2.0 * dist_m)) * ( (1.0 - bond_albedo) ** 0.25 )
		if atmosphere_density > 0.5:
			temp_k += atmosphere_density * 22.0

		var surface_pressure_bar := compute_surface_pressure_bar(atmosphere_density, surface_gravity_g)
		var escape_velocity_kms := 11.186 * sqrt(mass_earth / maxf(0.01, radius_ratio))
		var orbital_velocity_kms := 29.784 * sqrt(star_mass_sol / maxf(0.01, semi_major_axis_au))
		var orbital_period_days := sqrt(semi_major_axis_au ** 3 / maxf(0.1, star_mass_sol)) * 365.25

		# Hill Sphere Radius: r_H = a * cbrt(m / (3 * M_star))
		var mass_ratio_to_star := (mass_earth * 3.003e-6) / maxf(0.01, star_mass_sol)
		var hill_sphere_km := orbit_km * (mass_ratio_to_star / 3.0) ** (1.0 / 3.0)

		# Generate Hierarchical Moons inside Hill Sphere
		var is_gas_giant: bool = (archetype == PlanetArchetype.GAS_GIANT_JOVIAN or archetype == PlanetArchetype.GAS_GIANT_ICE)
		var moon_count: int = int(p_roll3 * (5.0 if is_gas_giant else 2.0))
		var moons: Array[Dictionary] = []
		var cur_moon_dist_km := radius_km * 3.5

		for m_idx in range(moon_count):
			var m_seed := hash_coords(p_seed, m_idx * 71, m_idx * 113)
			var m_roll1 := hash_to_float(hash_coords(m_seed, 10, 20))
			var m_roll2 := hash_to_float(hash_coords(m_seed, 30, 40))
			
			cur_moon_dist_km += (radius_km * 4.0) + m_roll1 * (hill_sphere_km * 0.15)
			if cur_moon_dist_km > hill_sphere_km * 0.4:
				break # Stable orbit boundary
				
			var moon_rad_km := 450.0 + m_roll2 * 2100.0 # 450km to 2550km (Europa/Titan scale)
			var moon_period_days := 2.0 * PI * sqrt((cur_moon_dist_km * 1000.0) ** 3 / maxf(1.0, 6.6743e-11 * mass_kg)) / 86400.0
			
			moons.append({
				"index": m_idx,
				"name": "%s %c" % [planet_name, 73 + m_idx], # e.g. "ALDER-7149 C I"
				"orbit_km": cur_moon_dist_km,
				"radius_km": moon_rad_km,
				"eccentricity": 0.002 + m_roll1 * 0.04,
				"inclination_deg": (m_roll2 - 0.5) * 6.0,
				"orbital_period_days": moon_period_days,
				"mean_anomaly_epoch_rad": m_roll1 * TAU
			})

		planets.append({
			"index": p_idx,
			"name": planet_name,
			"archetype": archetype,
			"semi_major_axis_au": semi_major_axis_au,
			"semi_minor_axis_au": semi_minor_axis_au,
			"eccentricity": eccentricity,
			"periapsis_au": periapsis_au,
			"apoapsis_au": apoapsis_au,
			"inclination_deg": inclination_deg,
			"longitude_ascending_node_deg": longitude_ascending_node_deg,
			"argument_periapsis_deg": argument_periapsis_deg,
			"mean_anomaly_epoch_rad": mean_anomaly_epoch_rad,
			"axial_tilt_deg": axial_tilt_deg,
			"sidereal_rotation_period_hours": sidereal_rotation_period_hours,
			"is_tidally_locked": is_tidally_locked,
			"orbit_au": semi_major_axis_au,
			"orbit_km": orbit_km,
			"orbit_light_seconds": orbit_light_seconds,
			"radius_km": radius_km,
			"radius_earth_ratio": radius_ratio,
			"mass_earth": mass_earth,
			"mass_kg": mass_kg,
			"surface_gravity_g": surface_gravity_g,
			"surface_gravity_ms2": surface_gravity_ms2,
			"surface_temp_k": temp_k,
			"surface_temp_c": temp_k - 273.15,
			"atmosphere_density": atmosphere_density,
			"surface_pressure_bar": surface_pressure_bar,
			"escape_velocity_kms": escape_velocity_kms,
			"orbital_velocity_kms": orbital_velocity_kms,
			"orbital_period_days": orbital_period_days,
			"hill_sphere_km": hill_sphere_km,
			"has_rings": has_rings,
			"surface_color": planet_color,
			"moon_count": moons.size(),
			"moons": moons
		})

	return {
		"seed": system_seed,
		"name": system_name,
		"galactic_position_ly": galactic_pos,
		"spectral_class": spectral_type,
		"temperature_k": star_temp_k,
		"luminosity_sol": star_lum_sol,
		"mass_sol": star_mass_sol,
		"mass_kg": star_mass_sol * 1.9885e30,
		"radius_km": star_radius_km,
		"radius_solar_ratio": star_radius_km / 696340.0,
		"star_color": star_color,
		"habitable_zone_au": Vector2(hab_zone_inner_au, hab_zone_outer_au),
		"frost_line_au": frost_line_au,
		"planet_count": planets.size(),
		"planets": planets
	}
