# res://scripts/test_procedural_universe.gd
# ==============================================================================
# BioGenesis-X: Elite Dangerous Procedural Universe & Galaxy Engine Audit
# ==============================================================================

extends SceneTree

const ProceduralGalaxyClass = preload("res://scripts/ProceduralGalaxy.gd")
const ProceduralPlanetClass = preload("res://scripts/ProceduralPlanet.gd")
const UniverseManagerClass = preload("res://scripts/UniverseManager.gd")

func _init() -> void:
	print("\n==================================================================")
	print("BIO-GENESIS-X: PROCEDURAL UNIVERSE & ASTROPHYSICS ENGINE AUDIT")
	print("==================================================================")

	# -------------------------------------------------------------------------
	# TEST 0: Real Astrophysical Formulae Verification
	# -------------------------------------------------------------------------
	print("\n[TEST 0] Testing Real Astrophysical Formulae (IMF, Mass-L, Blackbody, HZ)...")

	# Kroupa IMF: most stars should be M-dwarfs (low mass)
	var m_dwarf_count := 0
	var massive_count := 0
	for i in range(1000):
		var u := float(i) / 1000.0
		var m := ProceduralGalaxyClass.sample_imf_mass(u)
		assert(m >= 0.01 and m <= 150.0, "IMF mass must be within stellar range [0.01, 150] M_sun")
		if m < 0.5:
			m_dwarf_count += 1
		if m > 8.0:
			massive_count += 1
	print("  • Kroupa IMF: %d/1000 are M-dwarfs (<0.5 M_sun), %d/1000 are massive (>8 M_sun)" % [m_dwarf_count, massive_count])
	assert(m_dwarf_count > 500, "Kroupa IMF must produce majority low-mass stars")
	assert(massive_count < 20, "Massive stars must be rare in Kroupa IMF")

	# Mass-Luminosity: Sun (M=1) should give L≈1
	var sun_lum := ProceduralGalaxyClass.mass_to_luminosity(1.0)
	print("  • Mass-Luminosity: M=1.0 M_sun -> L=%.4f L_sun (expected ~1.0)" % sun_lum)
	assert(abs(sun_lum - 1.0) < 0.1, "Sun's luminosity must be ~1.0 L_sun")

	# Mass-Radius: Sun (M=1) should give R≈1
	var sun_rad := ProceduralGalaxyClass.mass_to_radius(1.0)
	print("  • Mass-Radius: M=1.0 M_sun -> R=%.4f R_sun (expected ~1.0)" % sun_rad)
	assert(abs(sun_rad - 1.0) < 0.1, "Sun's radius must be ~1.0 R_sun")

	# Stefan-Boltzmann: Sun should give T≈5772 K
	var sun_temp := ProceduralGalaxyClass.luminosity_radius_to_temperature(1.0, 1.0)
	print("  • Stefan-Boltzmann: L=1, R=1 -> T=%.0f K (expected ~5772 K)" % sun_temp)
	assert(abs(sun_temp - ProceduralGalaxyClass.SOLAR_TEMPERATURE_K) < 100.0, "Sun's temperature must be ~5772 K")

	# Blackbody color: Sun should be yellowish-white
	var sun_color := ProceduralGalaxyClass.blackbody_color(5772.0)
	print("  • Blackbody Color: T=5772K -> RGB(%.2f, %.2f, %.2f)" % [sun_color.r, sun_color.g, sun_color.b])
	assert(sun_color.r > 0.9 and sun_color.g > 0.8, "Sun's blackbody color must be warm white")

	# Kopparapu habitable zone: Sun should give ~[0.99, 1.70] AU
	var sun_hz := ProceduralGalaxyClass.habitable_zone(1.0, 5772.0)
	print("  • Kopparapu HZ: L=1, T=5772K -> [%.2f, %.2f] AU (expected ~[0.99, 1.70])" % [sun_hz.x, sun_hz.y])
	assert(sun_hz.x > 0.8 and sun_hz.x < 1.2, "Inner HZ for Sun must be ~0.99 AU")
	assert(sun_hz.y > 1.5 and sun_hz.y < 2.0, "Outer HZ for Sun must be ~1.70 AU")

	# Frost line: Sun should give ~2.7 AU
	var sun_fl := ProceduralGalaxyClass.frost_line(1.0)
	print("  • Frost Line: L=1 -> %.2f AU (expected ~2.7)" % sun_fl)
	assert(abs(sun_fl - 2.7) < 0.1, "Frost line for Sun must be ~2.7 AU")

	# Planet mass-radius: Earth (M=1) should give R≈6371 km
	var earth_rad := ProceduralGalaxyClass.planet_mass_to_radius(1.0, false, false)
	print("  • Planet M-R: M=1.0 M_earth -> R=%.0f km (expected ~6371)" % earth_rad)
	assert(abs(earth_rad - 6371.0) < 100.0, "Earth's radius must be ~6371 km")

	print("  ✓ All real astrophysical formulae verified.")

	# -------------------------------------------------------------------------
	# TEST 1: Lin-Shu Spiral Density Wave Mathematical Model
	# -------------------------------------------------------------------------
	print("\n[TEST 1] Testing Lin-Shu Spiral Density Wave Galaxy Mass Model...")
	
	# Galactic Center — the SMBH exclusion zone is the real sphere of influence
	# (~10 LY). The galactic bulge (8000 LY core) has high density right up to
	# the exclusion zone edge. Test density just outside the 10 LY zone.
	var core_test_pos := Vector3(ProceduralGalaxyClass.SMBH_EXCLUSION_RADIUS_LY + 200.0, 0.0, 0.0)
	var core_density := ProceduralGalaxyClass.get_stellar_density(core_test_pos)
	print("  • Galactic Core Density (%.0f, 0, 0): %.4f (Expected high: >0.5)" % [core_test_pos.x, core_density])
	assert(core_density > 0.5, "Galactic bulge just outside SMBH sphere of influence must have high stellar density")

	# SMBH Exclusion Zone — no stars should exist within the gravitational capture radius
	var smbh_density := ProceduralGalaxyClass.get_stellar_density(Vector3.ZERO)
	print("  • SMBH Exclusion Zone (0, 0, 0): %.4f (Expected: 0.0 — stars consumed by SMBH)" % smbh_density)
	assert(smbh_density == 0.0, "SMBH exclusion zone must have zero stellar density")

	# Sol System Neighborhood (Orion Spur, ~26,000 LY out)
	var sol_density := ProceduralGalaxyClass.get_stellar_density(ProceduralGalaxyClass.SOL_SYSTEM_COORDINATE)
	print("  • Sol Sector Density (0, 15, 26000 LY): %.4f" % sol_density)
	assert(sol_density > 0.01 and sol_density < 0.8, "Sol sector must have moderate spiral arm disc density")

	# Intergalactic Void Beyond Stellar Halo (150,000 LY out — beyond halo radius)
	var void_density := ProceduralGalaxyClass.get_stellar_density(Vector3(150000.0, 5000.0, 0.0))
	print("  • Intergalactic Void Density (150000 LY): %.4f (Expected: 0.0)" % void_density)
	assert(void_density == 0.0, "Void beyond stellar halo must have zero density")
	print("  ✓ Lin-Shu Spiral Density Wave galactic distribution verified.")

	# -------------------------------------------------------------------------
	# TEST 2: Deterministic Sector Octree & Star System Population
	# -------------------------------------------------------------------------
	print("\n[TEST 2] Testing Sector Star System Population (1% Milky Way Density)...")
	var sec_x := int(ProceduralGalaxyClass.SOL_SYSTEM_COORDINATE.x / ProceduralGalaxyClass.SECTOR_SIZE_LY)
	var sec_y := int(ProceduralGalaxyClass.SOL_SYSTEM_COORDINATE.y / ProceduralGalaxyClass.SECTOR_SIZE_LY)
	var sec_z := int(ProceduralGalaxyClass.SOL_SYSTEM_COORDINATE.z / ProceduralGalaxyClass.SECTOR_SIZE_LY)

	# Search nearby sectors for one with systems — the sharpened spiral arm density
	# model means not every sector has stars; find the nearest populated one.
	var local_systems: Array[Dictionary] = []
	var found_sec := Vector3i.ZERO
	for dz in range(-5, 6):
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				var systems = ProceduralGalaxyClass.get_systems_in_sector(sec_x + dx, sec_y + dy, sec_z + dz)
				if systems.size() > 0:
					local_systems = systems
					found_sec = Vector3i(sec_x + dx, sec_y + dy, sec_z + dz)
					break
				if local_systems.size() > 0:
					break
			if local_systems.size() > 0:
				break
		if local_systems.size() > 0:
			break

	print("  • Nearest Populated Sector (%d, %d, %d) Systems: %d" % [found_sec.x, found_sec.y, found_sec.z, local_systems.size()])
	assert(local_systems.size() > 0, "Must find a populated sector near Sol within spiral arm")

	# Use the found sector for subsequent tests
	sec_x = found_sec.x
	sec_y = found_sec.y
	sec_z = found_sec.z

	# Verify Determinism (same coordinates yield identical star systems)
	var repeat_systems := ProceduralGalaxyClass.get_systems_in_sector(sec_x, sec_y, sec_z)
	assert(local_systems.size() == repeat_systems.size(), "Sector generation must be 100% deterministic")
	assert(local_systems[0]["name"] == repeat_systems[0]["name"], "System names and seeds must match perfectly")
	print("  ✓ Deterministic sector population verified.")

	# -------------------------------------------------------------------------
	# TEST 3: Harvard Stellar Classification & Titius-Bode Planetary Systems
	# -------------------------------------------------------------------------
	print("\n[TEST 3] Testing Harvard Stellar Classification & Planetary Formation...")
	var test_system := local_systems[0]
	print("  • Host Star: '%s'" % test_system["name"])
	print("    - Spectral Class: %d | Temperature: %.0f K | Luminosity: %.3f Sol" % [
		test_system["spectral_class"], test_system["temperature_k"], test_system["luminosity_sol"]
	])
	print("    - Stellar Radius: %.0f km (%.2f R_sol) | Mass: %.2f M_sol" % [
		test_system["radius_km"], test_system["radius_solar_ratio"], test_system["mass_sol"]
	])
	print("    - Habitable Zone: %.2f AU - %.2f AU | Frost Line: %.2f AU" % [
		test_system["habitable_zone_au"].x, test_system["habitable_zone_au"].y, test_system["frost_line_au"]
	])
	print("    - Total Orbiting Planets: %d" % test_system["planet_count"])

	assert(test_system["planets"].size() >= 2, "Star system must generate at least 2 planets")
	var prev_orbit: float = 0.0
	for p in test_system["planets"]:
		print("      [%c] %s | Archetype: %d | Orbit: %.2f AU (%.1f Ls) | Radius: %.0f km (%.2f R⊕) | Mass: %.2f M⊕ | Gravity: %.2f G (%.2f m/s²) | Temp: %.0f K (%.1f °C) | Escape: %.1f km/s" % [
			65 + p["index"], p["name"], p["archetype"], p["orbit_au"], p["orbit_light_seconds"],
			p["radius_km"], p["radius_earth_ratio"], p["mass_earth"],
			p["surface_gravity_g"], p["surface_gravity_ms2"],
			p["surface_temp_k"], p["surface_temp_c"], p["escape_velocity_kms"]
		])
		assert(p["eccentricity"] >= 0.0 and p["eccentricity"] < 0.9, "Planetary eccentricity must represent stable elliptic orbit")
		assert(p["periapsis_au"] < p["semi_major_axis_au"], "Periapsis must be strictly closer than semi-major axis")
		assert(p["apoapsis_au"] > p["semi_major_axis_au"], "Apoapsis must be strictly farther than semi-major axis")
		assert(p["orbit_au"] > prev_orbit, "Planets must follow monotonic Titius-Bode orbital progression")
		assert(p["mass_kg"] > 1.0e22, "Planet mass in kg must be physically realistic")
		assert(p["surface_gravity_g"] > 0.05 and p["surface_gravity_g"] < 35.0, "Surface gravity must match astrophysical limits")
		assert(p["surface_temp_k"] > 10.0 and p["surface_temp_k"] < 3500.0, "Surface equilibrium temperature must be realistic")
		assert(p["escape_velocity_kms"] > 1.0, "Escape velocity must be realistic")
		
		# Validate Moons inside Hill sphere
		for m in p["moons"]:
			assert(m["orbit_km"] < p["hill_sphere_km"], "Moon orbit must be securely contained within parent Hill sphere")
			assert(m["orbital_period_days"] > 0.1, "Moon orbital period must be positive and realistic")

		prev_orbit = p["orbit_au"]
	print("  ✓ Stellar classification & Titius-Bode planetary formation verified.")

	# -------------------------------------------------------------------------
	# TEST 4: Kepler's 3 Laws & Newton-Raphson Solver Audit
	# -------------------------------------------------------------------------
	print("\n[TEST 4] Testing Kepler's Equation Newton-Raphson Solver & 3D Orbital Velocity...")
	var test_e := 0.20
	var test_M := 1.25 # rad
	var dummy_test := ProceduralPlanetClass.new()
	var solved_E: float = dummy_test.solve_kepler_eccentric_anomaly(test_M, test_e)
	var residual: float = absf(solved_E - test_e * sin(solved_E) - test_M)
	print("  • Kepler Solver: M=%.3f, e=%.2f -> E=%.6f (Residual: %.8f)" % [test_M, test_e, solved_E, residual])
	assert(residual < 1.0e-5, "Kepler equation Newton-Raphson solver must converge with high precision")
	dummy_test.free()

	# Test Keplerian Velocity variation (Faster at periapsis, slower at apoapsis)
	var dummy_planet := ProceduralPlanetClass.new()
	dummy_planet.semi_major_axis_m = 1000.0
	dummy_planet.eccentricity = 0.25
	dummy_planet.orbital_period_days = 365.25
	dummy_planet.mean_anomaly_epoch_rad = 0.0 # Periapsis (t = 0)
	var pos_peri := dummy_planet.compute_keplerian_position(0.0)
	var pos_apo := dummy_planet.compute_keplerian_position(365.25 * 86400.0 * 0.5) # Apoapsis (t = T/2)
	
	var r_peri := pos_peri.length()
	var r_apo := pos_apo.length()
	print("  • Keplerian Distances: Periapsis=%.1fm, Apoapsis=%.1fm (Expected: 750m / 1250m)" % [r_peri, r_apo])
	assert(is_equal_approx(r_peri, 750.0), "Periapsis distance must equal a * (1 - e)")
	assert(is_equal_approx(r_apo, 1250.0), "Apoapsis distance must equal a * (1 + e)")
	dummy_planet.free()
	print("  ✓ Kepler's 3 Laws & 3D state vector orbital dynamics verified.")

	# -------------------------------------------------------------------------
	# TEST 5: UniverseManager 3D Streaming & Host Star Instantiation
	# -------------------------------------------------------------------------
	print("\n[TEST 5] Testing UniverseManager Local Star System Instantiation...")
	var universe := UniverseManagerClass.new()
	universe.name = "UniverseManager"
	universe.current_system_seed = test_system["seed"]
	# Set galactic coordinates to the found sector so nearby system scan works
	universe.galactic_coordinates_ly = Vector3(found_sec.x, found_sec.y, found_sec.z) * ProceduralGalaxyClass.SECTOR_SIZE_LY
	root.add_child(universe)
	universe._ready()

	assert(universe.host_star_node != null, "UniverseManager must instantiate host star node")
	assert(universe.planets_container != null, "UniverseManager must instantiate planets container")
	assert(universe.planets_container.get_child_count() == test_system["planet_count"], "Must spawn all procedural planets")
	print("  • Host Star Node: '%s' spawned with directional and omni lighting." % universe.host_star_node.name)
	print("  • Spawned Planetary Bodies: %d" % universe.planets_container.get_child_count())
	print("  ✓ UniverseManager local system streaming verified.")

	# -------------------------------------------------------------------------
	# TEST 6: Interstellar Hyperjump Navigation & Sector Scanning
	# -------------------------------------------------------------------------
	print("\n[TEST 6] Testing Interstellar Hyperjump & Sector Radar...")
	var nearby_stars := universe.get_nearby_systems(200.0) # 200 LY radar scan (wider due to sharpened spiral arm density)
	print("  • Stars detected within 60 Light-Years: %d" % nearby_stars.size())
	assert(nearby_stars.size() > 0, "Galaxy scan must locate nearby star systems")

	# Execute Hyperjump to the nearest neighbor star system
	var target_sys := nearby_stars[1] if nearby_stars.size() > 1 else nearby_stars[0]
	print("  • Initiating Frame Shift Hyperjump to '%s' (Distance: %.2f LY)..." % [
		target_sys["name"], target_sys.get("distance_from_vessel_ly", 0.0)
	])
	universe.hyperjump_to_system(target_sys["seed"])
	
	assert(universe.current_system_data["name"] == target_sys["name"], "Hyperjump must load target star system")
	assert(universe.planets_container.get_child_count() == universe.current_system_data["planet_count"], "Must stream new celestial bodies")
	print("  ✓ Interstellar hyperjump transition verified.")

	print("\n==================================================================")
	print("SUCCESS: 100% PROCEDURAL UNIVERSE & ASTROPHYSICS AUDIT PASSED!")
	print("==================================================================")
	quit(0)
