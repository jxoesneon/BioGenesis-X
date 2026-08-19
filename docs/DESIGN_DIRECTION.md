# BioGenesis-X — Design Direction & Aesthetic Bible

> **Pumilio Studios** — Canonical design reference for all visual, audio, and
> gameplay systems in BioGenesis-X. Every system must be consistent with this
> document and the lore bible (`LORE.md`, `ORGAN_SYSTEMS.md`).
>
> Ported and enhanced from the legacy BioGenesis project. Research details in
> `docs/research/` subdirectories.

---

## 1. Aesthetic Direction — Subnautica-Inspired Layered Design

BioGenesis-X's visual identity is inspired by Subnautica's design philosophy:
the *tension* between clean familiar tech and alien organic environments. The
player's living ship has five concentric aesthetic layers, each adapted from
Subnautica's design languages. Full details in
`docs/research/LIVING_SHIPS_RESEARCH.md` Section 10.

### Five Aesthetic Layers

1. **Interface Layer (Frutiger Aero / Skeuomorphic Futurism)**: Player-facing
   control surfaces, cockpit, habitable spaces. Glossy white surfaces with
   rounded organic curves, bright accent colors (cyan #00CED1, orange
   #FF6B35, yellow #FFD23F), skeuomorphic UI with depth and reflections.
   Bioluminescent amber backlighting (#FFB347) shows through translucent
   panels — the ship is alive, you can see it through the clean surface.
   Inspired by Alterra habitats/Seamoth.

2. **Structure Layer (Cassette Futurism / Raypunk)**: Heavy
   mechanical-equivalent systems — structural frame, engine mounting,
   weapons hardpoints, cargo bays. Chunky, tactile, utilitarian,
   "working-class in space." Muted industrial colors (#8B7D6B) with
   caution-striping (hazard yellow/orange). Wear and tear visible — scar
   tissue, healed fractures. Inspired by PRAWN Suit/Cyclops.

3. **Biology Layer (Bioluminescent Fantasy / Seapunk)**: The ship's organic
   interior — organ chambers, vascular tunnels, growth areas. Deep darkness
   (#0A0A20) as canvas with saturated bioluminescence (amber, cyan,
   magenta). Organic textures everywhere — membranes, veins, pulsing
   tissues. Everything moves: pulses, breathes, flows. This is where the
   ship feels truly alien.

4. **Environment Layer (Seapunk + Stylized Realism)**: External world —
   space environments, other ships, stations. Stylized realism (not
   photorealistic), readable silhouettes, atmospheric depth. Space as
   ocean: deep darkness with vivid bioluminescent life. Seven biome
   concepts mapped to Subnautica biomes (Nursery Belt = Safe Shallows,
   Abyssal Ruins = Lost River, etc.).

5. **Ancient Layer (Alien Brutalism / Mayan Revival)**: Precursor bio-tech
   ruins, ancient organisms. Monolithic, blocky, geometric sharpness.
   Green-black palette (#4A5D4A, #2E4030) with architect-green conduit
   glow (#00FF7F). Bio-carved hieroglyphic patterns. Non-human
   proportions. Inspired by Subnautica's Architect/Precursor structures.

### Faction Aesthetic Layering

- **Symbiotic (Player)**: All 5 layers present — comfort bubble in alien
  space. Damage strips away the interface layer to reveal biology beneath
  (dread).
- **Hive/Swarm (Enemy)**: Layers 3 & 4 only — no interface, no structure.
  Pure bioluminescent fantasy. Alien and incomprehensible.
- **Corruption/Horror**: Layer 3 corrupted — bioluminescence goes sickly,
  textures become necrotic. Beauty becomes horror.
- **Bio-Mechanical Hybrid (Ancient)**: Layer 5 dominant — Alien Brutalism,
  Mayan Revival. Flying temples. Geometric sharpness vs. player's organic
  curves.

### Design Principles for Implementation

- **Comfort bubble**: The player's ship interior is a safe, clean, friendly
  space (Frutiger Aero) — until damage breaches the hull and exposes alien
  biology.
- **Depth as progression**: Deeper into the ship's biology (or deeper into
  space) = more alien and dangerous. Interface layer = "shallows"; biology
  = "deep"; ancient = "void."
- **Stylized realism**: Not photorealistic — slightly smoothed, readable
  silhouettes, distinct visual identity per biome. Ages well visually.
- **Space as ocean**: Nebulae as coral reefs, ship graveyards as whale
  falls, stations as hydrothermal vent communities. Deep darkness +
  bioluminescent life.
- **Translucent panels**: The clean interface layer should have translucent
  sections that reveal the biology beneath — constant reminder the ship is
  alive.
- **Glossy skeuomorphic UI**: Not flat-material design. Glass-like panels
  with depth, reflections, rounded glossy buttons. UI feels *grown* by the
  ship.

---

## 2. Bioluminescent Color Coding

12 distinct bioluminescent colors indicate organ function and ship state.
Every shader, VFX, HUD element, and telemetry display must use these colors
consistently.

| Color | Hex | Meaning | Where Used |
|-------|-----|---------|------------|
| Cyan | #00CED1 | Healthy operation, neural sync | HUD, neural systems, shield |
| Amber | #FFB347 | Bio-plasma, propulsion, warmth | Engine, fuel, plasma weapons |
| Green | #00FF7F | Healing, regeneration, nanites | NeuralRegen, repair systems |
| Magenta | #FF3E9D | Expansion, warp field, growth | Wave engine, hull growth |
| Blue | #2B7FFF | Contraction, cooling, sensors | Sensors, scanning, comms |
| Orange | #FF6B35 | Warning, thermal, charge | Charging, heat, caution |
| Yellow | #FFD23F | Energy, power, alert | Power systems, alerts |
| Red | #FF2A2A | Damage, danger, hostile | Damage, enemies, hull breach |
| Purple | #9B4DCA | Corruption, mutation, anomaly | Corruption, horror faction |
| Teal | #0D9B8A | Life support, bio-moss | O2, habitat, life support |
| White | #E0FFFA | Pure energy, full sync, max | Max sync, overload, flash |
| Sickly Green | #6B8E23 | Necrotic, diseased, failing | Organ failure, necrosis |

---

## 3. Biological Reference Systems

Eight taxonomic groups mapped to ship organ functions. Every organ mesh,
texture, and animation should reference its biological inspiration.

| Taxonomic Group | Ship Function | Example Organs |
|----------------|---------------|----------------|
| Cephalopods | Propulsion, tentacles, neural | Siphon nozzles, tentacles, ganglion brain |
| Cnidarians | Defense, shields, bioluminescence | Shield emitters, spore sacs |
| Echinoderms | Regeneration, vascular | Hemolymph system, nanite repair |
| Arthropods | Armor, exoskeleton | Carapace plates, chitin vertebrae |
| Fungi | Networks, growth, decomposition | Vascular conduits, bio-nanite swarms |
| Plants | Photosynthesis, growth | Bio-moss carpet, bio-moss habitats |
| Biofilms | Surface patterns, self-assembly | Hull textures, reaction-diffusion patterns |
| Vertebrates | Structural, nervous system | Spinal cord, heart core, skeletal frame |

---

## 4. Procedural Generation Techniques

Research-backed techniques for BioGenesis-X's procedural systems. Full
details in `docs/research/PROCEDURAL_MESH_GENERATION_RESEARCH.md`.

### Organ Mesh Generation

- **SDF-first organ representation** — represent organs as composited SDFs
  with smooth-min blending; mesh via marching cubes on demand.
- **Catmull-Clark with semi-sharp creases** for the hull carapace (smooth
  organic bulges + defined ridge lines).
- **Space colonization / CCO** for vascular network organs (Arteries,
  Veins).
- **Bishop frame** for tube-based organs (avoids twisting at inflection
  points).
- **Reaction-diffusion (Gray-Scott)** for bioluminescent hull surface
  patterns. This is why NeuralRegen uses a Gray-Scott reaction-diffusion
  model on the GPU — it's the same biological pattern formation that
  creates real bioluminescent markings on deep-sea organisms.
- **ARAP deformation** for organic shape morphing during genetics-driven
  mutation.
- **GPU compute pipeline** as the architecture for real-time organ
  regeneration (implemented in `GPUComputeManager.gd`).

### Planet & Terrain Generation

- **Multi-octave fractal Brownian motion (fBm)** for base terrain height.
  Why fBm: natural terrain exhibits self-similarity across scales — a
  coastline looks similar at 1m, 100m, and 10km. fBm captures this with
  persistence and lacunarity controls.
- **Worley/cellular noise** for biome boundaries and Voronoi-style region
  partitioning. Why Worley: biological cell patterns, crystal formations,
  and tectonic plates all follow Voronoi-like space partitioning.
- **Domain warping** for organic, non-repeating terrain features. Why:
  pure fBm produces obvious grid-aligned patterns; domain warping breaks
  this by perturbing the input coordinates, producing the organic
  meandering seen in real coastlines and river systems.

### Audio Synthesis

- **Procedural synthesis via AudioStreamGenerator** at 22050 Hz. Why not
  samples: the ship is alive — its sounds must respond to organ state,
  damage, healing, and speed in real-time. Pre-recorded samples can't
  morph with the ship's biological state.
- **Layered soundscape architecture** inspired by No Man's Sky's
  procedural audio: multiple synthesis layers (engine drone, organ pulse,
  ambient bed, combat stings) that crossfade based on game state rather
  than hard-cutting between tracks.

---

## 5. Neural Compute Architecture

Full spec at `docs/research/NEURAL_COMPUTE_ARCHITECTURE.md`.

### Brain Scaling (Haller's Rule + Jerison Allometry)

- **EQ** scales from 7 (smallest ship, 20% energy budget) to 3 (largest,
  8% energy budget) following Haller's rule (smaller = proportionally
  larger brain).
- **Brain mass**: `E = 0.12 × shipVolume^0.67 × EQ` (Jerison power law).
- **Brain compute**: `neuronCount × 5 bits/s` (conservative from retinal
  ganglion data).
- **Mutualism**: Small ships are metabolically strained and NEED humans.
  Large ships are autonomous but value human direction (goal-setting,
  ethics). Mutualism doesn't require equal intelligence (dog EQ 1.2 +
  human EQ 7 model).

### Efficiency Curve (Yerkes-Dodson Inverted-U)

- `< 25%` supply: organ shutdown (non-functional).
- `25-50%`: heavy loss (20-50% efficiency).
- `50-100%`: linear ramp to 100%.
- `100%`: normal (default — ganglion meets demand exactly).
- `100-120%`: enhanced (overclocked — ONLY via captain's command or items).
- `> 120%`: overstimulated, efficiency drops (excitotoxicity analog).

---

## 6. Command Room

Full spec at `docs/research/COMMAND_ROOM_SPEC.md`.

### Crew Roles (5)

1. **Commander** — neural-link to brain, overall command, overclocking
   authority.
2. **Helm** — propulsion, navigation, ship movement.
3. **Bio-Systems Officer** — organ health, regeneration, metabolism.
4. **Tactical** — spores, bio-plasma weapons, armor defense.
5. **Science/Sensors** — ocular pods, scanning, research.

### Sizing

- Each workstation: 2m × 2m × 2.5m (large cubicle equivalent).
- Fixed overhead: 15 m³ (walls, life support, shared display).
- 1 crew = ~19 m³, 5 crew = ~55 m³.
- Crew capacity scales on integers by ship length:
  6m→1, 10m→2, 14m→3, 20m→4, 30m+→5.
- Negative gravity keeps humans grounded (not floating).

---

## 7. Physics Design Rationale

### Why Newtonian 6-DOF (Not Arcade Flight)

The Void-Fauna are real organisms in a real vacuum. Newton's laws apply. A
biological ship doesn't have magical drag — it has thrusters (siphon
nozzles) and mass. 6-DOF Newtonian physics is the physically correct model.
Accessibility is achieved through control layering (tethered assist,
dampening), not by violating physics.

### Why the Alcubierre Metric (Not "Warp Speed")

The Wave Engine is canonically an adapted Alcubierre drive. The Alcubierre
metric is a real solution to Einstein's field equations that allows
effective FTL by contracting spacetime ahead and expanding it behind the
ship. Inside the warp bubble, the ship is in free-fall — zero proper
acceleration, zero G-forces. This is why:

- The ship experiences **1G during transit** (normal body weight only).
- **No camera shake during cruise** (the bubble is smooth).
- **No collision detection during warp** (the ship isn't moving through
  space — space is moving around the ship).
- **Geometric alignment, not torque** (the bubble carries the ship's
  orientation; no angular acceleration inside the bubble).
- **Shake on engage/disengage** (bubble formation/collapse is violent —
  spacetime is being torn open and sealed).

### Why Real Astronomical Scale

Planets, stars, and distances are at real-world scale (km, AU, light-years).
Floating origin keeps float32 precision high near the ship. Gameplay pacing
is adjusted through ship and Wave Engine properties, not by shrinking the
universe. Why: a 1:1 scale universe creates the genuine sense of vastness
that defines space exploration. Shrinking distances to make them
"gameplay-friendly" destroys the core fantasy.

### Why Reaction-Diffusion for Hull Healing

NeuralRegen uses a Gray-Scott reaction-diffusion model on the GPU. Why:
this is the same mathematical model that creates real biological pattern
formation — from leopard spots to coral growth to bioluminescent markings
on deep-sea organisms. The Void-Fauna's hull healing should look like
biological pattern formation, not a simple "damage value decreases" timer.
The reaction-diffusion model produces visually emergent healing patterns
that match the biopunk aesthetic.

---

## 8. Audio Design Rationale

Full research at `docs/research/AUDIO_SYSTEMS_RESEARCH.md`.

### Why Procedural Synthesis (Not Samples)

The ship is a living organism. Its sounds must respond to:

- **Organ state** — a damaged heart core sounds different from a healthy
  one. The peristaltic heart beats at 68 BPM (canonical), but the timbre
  changes with hemolymph pressure, damage, and stress.
- **Speed and acceleration** — the plasma siphon's pitch and intensity
  scale with thrust output, not just "engine loudness goes up."
- **Healing and damage** — NeuralRegen's reaction-diffusion model produces
  a visual pattern; the audio should mirror this with evolving textures,
  not a simple "repair sound."
- **Wave Engine state** — the Alcubierre drive produces a spacetime
  distortion, not a conventional engine roar. The audio should feel like
  reality bending, not rockets firing.

Pre-recorded samples can't morph with these states. Procedural synthesis
at 22050 Hz allows real-time parameter-driven sound generation that
breathes with the ship.

### Why 22050 Hz (Not 44100/48000)

GDScript-based AudioStreamGenerator processing has a per-frame budget. At
22050 Hz with a 0.15s buffer, each fill processes ~3308 samples. At 44100
Hz, that doubles to ~6615 samples — exceeding the GDScript per-frame time
budget on mid-range hardware. 22050 Hz is sufficient for the ship's
organic sound palette (low-frequency drones, pulses, textures) and leaves
headroom for the game's other per-frame work.

### Layered Soundscape (NMS-Inspired)

No Man's Sky's procedural audio uses layered synthesis that crossfades
based on game state. BioGenesis-X follows the same architecture:

1. **Engine drone layer** — always present, scales with thrust/speed.
2. **Organ pulse layer** — heart (68 BPM), hemolymph, breathing — the
   ship's "heartbeat."
3. **Ambient bed layer** — space environment: radiation hiss, solar wind,
   distant cosmic phenomena.
4. **Combat stings layer** — weapon fire, impacts, shield hits —
   transient, triggered by events.
5. **Wave Engine layer** — spacetime distortion hum, charging whine,
   transit roar, dropout boom.

Layers crossfade (not hard-cut) based on game state transitions. This is
why `BioAudioDirector` exists as a separate autoload from `BioAudioSynth` —
the director manages layer state and crossfades, the synth generates the
actual audio.

---

## 9. Propulsion Scaling

Full research at `docs/research/PROPULSION_SCALING_RESEARCH.md`.

### Speed Tiers

| Tier | Speed | Propulsion | Lore Justification |
|------|-------|------------|-------------------|
| Docking | < 50 m/s | RCS thrusters | Precision maneuvering |
| Sublight | 50 - 2,000 km/s | Bio-plasma siphon | Normal space travel |
| Boost | 2,000 km/s | Overcharged siphon | Combat / evasion |
| Wave Engine | 200M km/s (668c) | Alcubierre warp | In-system supercruise |
| HyperWave | Inter-system | Jump drive | Star system transit |

### Why These Specific Values

- **Sublight max 2,000 km/s**: Fast enough to cross a planet's orbit in
  seconds, slow enough that planetary approach is a deliberate act. At
  2,000 km/s, crossing 1 AU takes ~75 seconds — long enough to feel like
  travel, short enough to not be boring.
- **Wave Engine 200M km/s (668c)**: 1 AU in 0.75s, 50 AU (Kuiper Belt) in
  37s, 400 AU (inner Oort) in 5.5 min. This makes the entire solar system
  accessible within a single play session while preserving the sense of
  scale.
- **Wave safe disengage 5,000 km**: Close enough to see the planet's full
  disc, far enough to not spawn inside the atmosphere. At sublight speeds,
  the final 5,000 km approach takes ~2.5 seconds — a brief "emergence"
  moment.
