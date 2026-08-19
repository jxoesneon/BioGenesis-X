# Propulsion Scaling & Dynamic Engine Sizing Research

*Generated: 2026-08-11 | Sources: 40+ | Confidence: High*

## Executive Summary

Research across astrophysics, propulsion engineering, and biological allometric scaling
provides the quantitative foundation for a dynamic engine sizing system in BioGenesis.
The key finding: **engine cowl diameter should scale as M^0.67 (cross-sectional area
scaling), engine mass as M^1.0 (isometric), and power output as M^0.75 (Kleiber's law)**,
where M is ship mass. The current implementation uses a hardcoded formula
(`1.2 + thrusterCount * 0.15`) that does not scale with ship size, producing identical
engine cowls for a 22m Leviathan and an 8m Interceptor.

## 1. Cosmic Distances & Travel Times

### Interstellar Distances
- Proxima Centauri: 4.2465 ly (40.2 trillion km)
- Sirius: 8.60 ly
- Milky Way diameter: 100,000 ly
- Andromeda Galaxy: 2.54 million ly

### Travel Times to Proxima Centauri (4.24 ly)
| Speed | Earth time | Ship time (dilated) | γ |
|---|---|---|---|
| 0.1c | 42.4 years | 42.1 years | 1.005 |
| 0.5c | 8.48 years | 7.35 years | 1.15 |
| 0.9c | 4.71 years | 2.06 years | 2.29 |
| 0.99c | 4.28 years | 0.60 years | 7.09 |

### Voyager 1 Speed (17.3 km/s)
- Time to Proxima Centauri: ~73,000-77,000 years

### Solar System Distances (AU)
- Earth→Mars: 0.52 AU (78M km)
- Earth→Jupiter: 4.2 AU (629M km)
- Earth→Saturn: 8.52 AU (1.28B km)
- Earth→Neptune: 30.05 AU (4.5B km)

## 2. Energy Requirements

### Relativistic Kinetic Energy
```
KE = (γ - 1) × m × c²
```
Example: 17,000 kg spacecraft at 0.22c → KE = 3.83×10¹⁶ J

### Tsiolkovsky Rocket Equation
```
Δv = Isp × g₀ × ln(m₀/m_f)
```
Mass ratio: m₀/m_f = e^(Δv/v_e)
For Δv = 2.5×v_e: mass ratio = e²·⁵ ≈ 12.2

### Propulsion Energy Densities
| Type | Energy Density (MJ/kg) | Isp (s) | Exhaust Velocity (m/s) | TWR |
|---|---|---|---|---|
| Chemical (LOX/LH2) | 13.4 | 450-470 | 4,400-4,600 | 20-100 |
| Nuclear Thermal | 3,456,000 | 825-1000 | 8,100-9,800 | 3-20 |
| Nuclear Electric | 3,456,000 | 1,000-50,000 | 10,000-500,000 | ~0.001 |
| Fusion (D-T) | 576,000,000 | 10,000-100,000 | 100,000-1,000,000 | 5-20 |
| Antimatter | 89,875,517,874 | 2,490,000 | 207,000,000 (0.69c) | Unknown |
| Plasma | Variable | 1,000-5,000 | 10,000-50,000 | ~0.01 |

### Thrust Equation
```
F = ṁ × v_e + (p_e - p₀) × A_e
```
Thrust scales with throat area (A*) for choked flow → **thrust ∝ diameter²**

## 3. Biological Allometric Scaling Laws

### Key Scaling Exponents
| Parameter | Exponent | Formula | Application |
|---|---|---|---|
| Metabolic rate / Engine power | 0.75 | P ∝ M^0.75 | Power output |
| Heart rate / Engine frequency | -0.25 | f ∝ M^-0.25 | Cycle frequency |
| Muscle cross-sectional area | 0.67 | A ∝ M^0.67 | Thrust surface |
| Heart mass / Engine mass | 1.0 | M_engine ∝ M^1.0 | Engine mass |
| Gill area / Heat exchanger | 0.8-0.9 | A_hx ∝ M^0.8 | Thermal management |
| Tail beat frequency | -0.29 | f ∝ M^-0.29 | Propulsion frequency |
| Cost of transport | -0.29 | COT ∝ M^-0.29 | Energy efficiency |
| Drag force | 0.67 | F_d ∝ U² × M^0.67 | Drag calculation |

### Kleiber's Law
```
BMR = 3.4 × M^0.75 watts
```
A 1000-ton ship needs 5.6× the power of a 100-ton ship (not 10×).

### Squid Jet Propulsion Scaling
- Thrust per unit muscle area: 0.25 mN/mm² (hatchlings) → 1.4 mN/mm² (adults)
- Funnel orifice area scales isometrically: A ∝ M^0.67
- Orifice ratio (aperture/body diameter): 0.24 (larvae) → 0.10 (adults)
- Weight-specific thrust increases with size: 0.36 (hatchlings) → 1.5 (adults)

### Optimal Biological Proportions
- Optimal fineness ratio (L/D): 4.5-5.0
- Tail beat amplitude: 10-30% of body length (optimal ~20%)
- Strouhal number for efficient locomotion: 0.2-0.4
- Locomotor muscle: ~50% of body mass in fast swimmers
- Energy to locomotion: ~50-70% of metabolic energy at cruise

### Murray's Law (Duct Scaling)
```
r_parent³ = r_daughter1³ + r_daughter2³
```
Flow rate Q ∝ r³ (laminar) or Q ∝ r^2.33 (coronary)

## 4. Plasma/Bio-Plasma Propulsion

### Plasma Energy Density
```
W = (3/2) × n × k_B × T
```
- 1 eV plasma (11,609 K): ~24 kJ/m³ at n=10²⁰ m⁻³
- 10 eV plasma: ~240 kJ/m³
- 100 eV plasma: ~2.4 MJ/m³

### Plasma Thrust Scaling
- Thrust-to-power ratio: 0.01-0.1 N/kW
- Thrust increases quadratically with anode radius
- Thrust increases linearly with discharge current

### Biological Energy Production
- Electric eel: Up to 860V, 1A, 63W peak, 6000 electrocytes in series
- Muscle power output: 10-400 W/kg (burst), 1-10 W/kg (sustained)
- Resting metabolic rate: 0.3-9 W/kg across all life
- Organ-specific: Heart 440 kcal/kg/day, Brain 240, Muscle 13

## 5. Current Codebase Analysis

### What's Hardcoded
- Cowl height: fixed 1.4m regardless of ship size
- Cowl minimum radius: fixed 1.2m even with 0 thrusters
- Caudal manifold: fixed TorusKnot(0.45, 0.12) — no scaling
- Thruster component ratios: fixed proportions
- Plume base height: fixed 3.8 × thrusterScale

### What's Dynamic
- Cowl base radius: `max(1.2 + thrusterCount * 0.15, caudalNode.radius * 1.5)`
- Thruster positions: scale with engineBaseRadius
- Individual thruster size: inversely with √(thrusterCount)
- Pipeline node positions: scale with hull radius

### What's Missing
- Ship mass/displacement tracking (not in AppState)
- Thrust-to-weight ratio calculation
- Energy-to-thrust coupling
- Cowl height scaling with ship size
- Caudal manifold scaling with engine size

## 6. Design Model: Dynamic Engine Sizing

### Ship Mass Estimation
```
mass ≈ hullVolume × tissueDensity + organMass
hullVolume ≈ π × (thoraxWidth × 0.5)² × length × 0.6  (0.6 = avg fill factor)
tissueDensity ≈ 1050 kg/m³ (biological tissue)
```

### Required Thrust (for 0.01g cruise acceleration)
```
F_thrust = mass × a_cruise
a_cruise = 0.098 m/s² (0.01g)
```

### Engine Cowl Sizing (Allometric)
```
cowlRadius ∝ M^0.33  (isometric diameter scaling, from squid mantle)
cowlHeight ∝ M^0.33  (proportional length scaling)
cowlRadius = max(tailRadius × 1.4, (mass^0.33) × 0.15)
cowlHeight = cowlRadius × 0.8  (aspect ratio from squid mantle)
```

### Thruster Sizing
```
thrusterRadius ∝ √(F_thrust / thrusterCount)  (thrust ∝ area)
thrusterScale = √(engineBaseRadius² / (thrusterCount × 0.8))
```

### Caudal Manifold Scaling
```
manifoldRadius = engineBaseRadius × 0.35  (proportional to engine)
manifoldTube = engineBaseRadius × 0.08
```

### Plume Scaling (Energy-Coupled)
```
plumeLength ∝ √(energyGeneration / thrusterCount)
plumeLength = base × (energyGen / energyLoad)^0.5 × thrusterScale
```

### Energy-Thrust Coupling
```
effectiveThrust = baseThrust × (energyGen / energyLoad)
plumeIntensity ∝ energyStatus (OPTIMAL=1.0, SUB_OPTIMAL=0.6, FAILING=0.2, OFFLINE=0.05)
```

## Sources

### Astrophysics
1. NASA Voyager 1 — https://science.nasa.gov/mission/voyager/voyager-1/
2. NASA Imagine — https://imagine.gsfc.nasa.gov/features/cosmic/nearest_star_info.html
3. OpenStax Physics — https://openstax.org/books/physics/pages/10-2-consequences-of-special-relativity
4. Wikipedia Tsiolkovsky — https://en.wikipedia.org/wiki/Tsiolkovsky_rocket_equation

### Propulsion Engineering
5. NASA NTP — https://ntrs.nasa.gov/api/citations/20150016484/downloads/20150016484.pdf
6. Stanford AA284A — https://web.stanford.edu/~cantwell/AA284A_Course_Material/
7. NASA Goebel & Katz — https://web.stanford.edu/~cantwell/AA284A_Course_Material/AA284A_Resources/
8. Energy density table — https://en.wikipedia.org/wiki/Energy_density_extended_reference_table
9. Auburn engine scaling — https://etd.auburn.edu/bitstream/handle/10415/6916/

### Biological Scaling
10. Kleiber's Law — https://en.wikipedia.org/wiki/Kleiber%27s_law
11. PLoS Computational Biology — https://journals.plos.org/ploscompbiol/article?id=10.1371%2Fjournal.pcbi.1000171
12. Squid thrust scaling — https://labs.bio.unc.edu/kier/pdf/Thompson_%20Kier_2002_Thrust.pdf
13. Nature fish scaling — https://www.nature.com/articles/s41467-023-41368-6
14. Murray's Law — https://en.wikipedia.org/wiki/Murray%27s_law
15. Heart mass scaling — https://www.sciencedirect.com/science/article/abs/pii/0034568784900185
16. Cost of transport — https://pmc.ncbi.nlm.nih.gov/articles/PMC4040623/
17. Fineness ratio — https://journals.plos.org/pone/article?id=10.1371%2Fjournal.pone.0075422
18. Strouhal number — https://doi.org/10.1103/physrevfluids.2.083102

### Plasma & Bioelectrogenesis
19. Plasma energy density — https://doi.org/10.1017/s002237782200054x
20. Electric eel — https://www.nature.com/articles/s41467-019-11690-z
21. Muscle power — https://polypedal.berkeley.edu/publications/063_Full_MetricsofNaturalMuscle_ElectroActivePolymers_2001.pdf

## Methodology
Searched 30+ queries across web. Analyzed 40+ sources. Sub-questions investigated:
- Cosmic distances and relativistic travel times
- Propulsion energy densities and specific impulse
- Rocket equation and mass ratios
- Allometric scaling exponents for biological systems
- Squid jet propulsion scaling
- Fish caudal fin propulsion scaling
- Murray's law for duct scaling
- Plasma propulsion characteristics
- Biological energy production rates
