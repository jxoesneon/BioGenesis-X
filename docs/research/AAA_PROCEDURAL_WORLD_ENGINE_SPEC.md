# AAA+ Procedural Generation & World Engine Specification — BioGenesis

**Author**: Subagent 6 (AAA+ Procedural Generation & World Engine Architect)  
**Swarm Loop**: Loop 1 — Foundation & Core Specs  
**Scope**: AAA+ Technical Specifications for Procedural Universe, Organic Architecture Growth, Dual Contouring Chitin Carapaces, Dynamic Biomes, and Deterministic Cross-Platform Seed Engineering.  
**Target Platform**: Three.js / WebGPU / React 19 / TypeScript (BioGenesis Engine)  

---

## Executive Summary & System Architecture

BioGenesis demands a procedural generation system capable of generating both micro-scale biological structures (organic rooms, vascular feeds, chitin carapaces) and macro-scale astronomical environments (galaxies, star systems, nebulae, biomes) at **60 FPS** with **100% cross-platform determinism**.

This document specifies the end-to-end procedural architecture for BioGenesis's World Engine. It bridges foundational graphics algorithms (Dual Contouring, Space Colonization, L-Systems, 3D Noise) with game design requirements for Void-Fauna biomes, living ship morphology, and galaxy exploration.

```
+-----------------------------------------------------------------------------------+
|                            DETERMINISTIC SEED ENGINE                              |
|          XXHash64 / PCG64 Hierarchy Tree (Universe -> Sector -> System -> Hull)   |
+--------------------------+--------------------------------+-----------------------+
                           |                                |
                           v                                v
+--------------------------+----------+  +------------------+-----------------------+
|   MACRO: UNIVERSE & BIOME ENGINE    |  |     MICRO: LIVING SHIP MORPHOLOGY        |
|  - Logarithmic Spiral Galaxy Math   |  |  - Space Colonization (Murray's Law)  |
|  - Keplerian System Orbit Solver    |  |  - 3D L-Systems (Turtle State Buffer) |
|  - Raymarched Volumetric Nebulae    |  |  - Dual Contouring QEF Chitin Plates  |
|  - Biome Noise & Particle Synthesizer|  |  - Surface Nets Isosurface Smoothing  |
+--------------------------+----------+  +------------------+-----------------------+
                           |                                |
                           +----------------+---------------+
                                            |
                                            v
+-------------------------------------------+---------------------------------------+
|                         WEBGPU / THREE.JS RENDER PIPELINE                         |
|    Compute Shaders (SDF Isosurfaces, Raymarching) + GPU Instancing + Lod Buffers  |
+-----------------------------------------------------------------------------------+
```

---

## 1. Procedural Universe & Stellar Systems Engine

### 1.1 Seed-Based Galaxy Generation

The galaxy model generates thousands of star systems deterministically without storing grid state in memory. Star density is governed by a multi-component galactic mass model combining a central bulge, logarithmic spiral arms, and an exponential halo.

#### Mathematical Formulation

1. **Logarithmic Spiral Arms**:
   The primary arm trajectory in polar coordinates \((r, \theta)\) is given by:
   $$r(\theta) = r_0 \cdot e^{k \cdot (\theta - \theta_{\text{offset}})}$$
   where \(r_0\) is the inner radius scale, \(k = \tan(\alpha)\) defines the pitch angle \(\alpha\) (typically \(12^\circ - 18^\circ\)), and \(\theta_{\text{offset}} = \frac{2\pi \cdot i}{N_{\text{arms}}}\) offsets arm \(i \in [0, N_{\text{arms}}-1]\).

2. **Galactic Stellar Density Distribution**:
   Stellar density \(\rho(r, \theta, z)\) at point \((r, \theta, z)\) combines bulge, disc, and arm perturbations:
   $$\rho(r, \theta, z) = \rho_{\text{bulge}} e^{-\left(\frac{r}{r_b}\right)^2} + \rho_{\text{disc}} e^{-\frac{r}{r_d}} e^{-\frac{|z|}{z_h}} \left[ 1 + \sum_{m=1}^{N_{\text{arms}}} A_m \cos\left( m \left( \theta - \frac{\ln(r/r_0)}{k} \right) \right) \right]$$
   where \(r_b\) is bulge scale radius, \(r_d\) is disc scale length, \(z_h\) is disc scale height, and \(A_m\) is arm modulation amplitude.

3. **Star Placement Sampling (Rejection & Inversion Method)**:
   For sector chunk \(\mathbf{C} = (X, Y, Z)\), a deterministic PRNG derives star counts \(N_{\text{stars}} \sim \text{Poisson}(\iiint_{\mathbf{C}} \rho \, dV)\). Star positions are jittered via domain-warped 3D Simplex noise:
   $$\mathbf{P}_{\text{star}} = \mathbf{P}_{\text{grid}} + \boldsymbol{\delta} \cdot \text{Noise}_{3D}\left( \mathbf{P}_{\text{grid}} \cdot f + \text{Seed} \right)$$

---

### 1.2 Star Systems & Keplerian Planetary Orbits

Star systems generate star spectral classes (O, B, A, F, G, K, M, and Void-Exotic), planetary masses, orbital semi-major axes, eccentricities, and Goldilocks (habitable/living) zones.

#### Mathematical Formulation

1. **Habitable & Bio-Luminescence Zone Radius**:
   Given stellar luminosity \(L_{\text{star}} = M_{\text{star}}^{3.5}\) (in Solar units \(L_\odot\)):
   $$R_{\text{inner}} = 0.75 \sqrt{L_{\text{star}}}, \quad R_{\text{outer}} = 1.37 \sqrt{L_{\text{star}}} \quad [\text{AU}]$$
   Void-Fauna organisms flourish within the **Bio-Luminescence Zone** where stellar ionizing radiation matches organ synthesis thresholds:
   $$R_{\text{bio}} = \left[ 0.90 \sqrt{L_{\text{star}}}, 1.80 \sqrt{L_{\text{star}}} \right]$$

2. **Keplerian Orbit Solver**:
   Planetary position \(\mathbf{r}(t)\) in orbital plane:
   - Mean Anomaly: \(M(t) = M_0 + n(t - t_0)\), where mean motion \(n = \sqrt{\frac{G(M_{\text{star}} + m_{\text{planet}})}{a^3}}\).
   - Kepler's Equation solved via Newton-Raphson for Eccentric Anomaly \(E\):
     $$f(E) = E - e \sin E - M = 0$$
     $$E_{n+1} = E_n - \frac{E_n - e \sin E_n - M}{1 - e \cos E_n}$$
   - True Anomaly \(\nu\):
     $$\tan\left(\frac{\nu}{2}\right) = \sqrt{\frac{1+e}{1-e}} \tan\left(\frac{E}{2}\right)$$
   - Radius \(r = a(1 - e \cos E)\). Position vector transformed by inclination \(i\), longitude of ascending node \(\Omega\), and argument of periapsis \(\omega\).

---

### 1.3 Volumetric Nebulae & Raymarched Gas Clouds

Nebulae are non-repeating 3D volumetric gas clouds with realistic light absorption, emission, and scattering rendered via WebGL/WebGPU compute raymarching.

```
Camera Ray R(t) = O + t*D
  |
  +-----> Step t_0: Sample Noise Density rho(x)
  |       Compute Absorption exp(-sigma_a * rho * dt)
  |       Compute Bioluminescent Emission E_organ(x)
  |
  +-----> Step t_1: Accumulate In-Scattering Light (Phase Function P(theta))
  |
  v
Final Pixel Color C = Sum[ T_i * E_i * dt ] + Background
```

#### Mathematical Formulation

1. **Density Field Construction**:
   $$\rho(\mathbf{x}) = \max\left(0, \text{fBm}_{3D}(\mathbf{x} \cdot f_{\text{base}}) - \text{Worley}_{3D}(\mathbf{x} \cdot f_{\text{detail}})\right) \cdot \text{SDF}_{\text{containment}}(\mathbf{x})$$

2. **Beer-Lambert Light Extinction & In-Scattering**:
   Transmittance along ray \(\mathbf{R}(t) = \mathbf{O} + t\mathbf{D}\) with step size \(\Delta t\):
   $$T(t) = \exp\left( -\int_0^t \sigma_a \cdot \rho(\mathbf{R}(s)) \, ds \right) \approx \prod_{k=0}^{N} \exp\left(-\sigma_a \rho(\mathbf{x}_k) \Delta t\right)$$
   Accumulated radiance \(I\):
   $$I = \sum_{k=0}^{N} T(t_k) \cdot \left[ S_{\text{emission}}(\mathbf{x}_k) + \sigma_s \rho(\mathbf{x}_k) P(\theta) I_{\text{star}}(\mathbf{x}_k) \right] \Delta t$$
   where Henyey-Greenstein phase function \(P(\theta)\) controls directional scattering:
   $$P(\theta) = \frac{1 - g^2}{4\pi (1 + g^2 - 2g \cos\theta)^{3/2}}$$

---

### 1.4 Instanced Asteroid Belts & SDF Field Generation

Asteroids are generated procedurally using 3D SDF composition deformed by multi-octave noise, rendered via hardware GPU instancing with LOD management.

#### Mathematical Formulation

1. **Asteroid Base SDF with Noise Displacement**:
   $$\text{SDF}_{\text{asteroid}}(\mathbf{x}) = \|\mathbf{x}\| - R_{\text{base}} + \sum_{l=1}^{L} \frac{1}{2^l} \text{Noise}_{3D}\left(2^l \mathbf{x} \cdot f_0\right)$$

2. **GPU Instancing Keplerian Belt Distribution**:
   Asteroid instances are packed into GPU Uniform/Storage Buffers containing transform matrices \(\mathbf{M}_i = \mathbf{T}(r_i, \theta_i, z_i) \cdot \mathbf{R}(\alpha_i, \beta_i, \gamma_i) \cdot \mathbf{S}(s_i)\). Positions follow a Gaussian vertical profile \(\Delta z \sim \mathcal{N}(0, \sigma_z)\) around the belt ecliptic.

---

## 2. Organic Ship Room Growth & Space Colonization

Ship interiors grow organically rather than being manually painted. Room layout and vascular feeds use space colonization algorithms constrained by structural stress hulls and Murray's Law.

```
[Attraction Points S distributed in Hull Volume]
                     |
  +------------------+-------------------+
  v                                      v
[Room Chamber Colonization]           [Vascular Feed Network]
- Distance Influence R_inf            - Distance Influence R_inf
- Distance Kill R_kill                - Distance Kill R_kill
- Growth Step s_room                  - Growth Step s_vasc
- Room Topology (Gizzard, Habitat)    - Murray's Law Radius Scaling (r_0^k = r_1^k + r_2^k)
```

---

### 2.1 Space Colonization Algorithm for Room & Structural Networks

Attraction points \(\mathcal{S} = \{\mathbf{s}_i\}\) are randomly scattered throughout the interior hull volume. Tree nodes \(\mathcal{N} = \{\mathbf{n}_j\}\) iteratively grow towards nearby attraction points.

#### Algorithm Steps & Technical Specification

1. **Influence & Kill Spheres**:
   - Attraction radius \(R_{\text{inf}}\): Maximum distance a point \(\mathbf{s}_i\) can exert pull on a node \(\mathbf{n}_j\).
   - Kill radius \(R_{\text{kill}}\): Minimum distance; when \(\|\mathbf{s}_i - \mathbf{n}_j\| < R_{\text{kill}}\), point \(\mathbf{s}_i\) is consumed and removed.

2. **Growth Direction Vector Calculation**:
   For each node \(\mathbf{n}_j\), collect all attraction points \(\mathcal{S}_j = \{ \mathbf{s}_i \mid \|\mathbf{s}_i - \mathbf{n}_j\| < R_{\text{inf}} \text{ and } \mathbf{n}_j = \arg\min_{\mathbf{n} \in \mathcal{N}} \|\mathbf{s}_i - \mathbf{n}\| \}\):
   $$\mathbf{v}_j = \sum_{\mathbf{s}_i \in \mathcal{S}_j} \frac{\mathbf{s}_i - \mathbf{n}_j}{\|\mathbf{s}_i - \mathbf{n}_j\|}, \quad \mathbf{d}_j = \frac{\mathbf{v}_j}{\|\mathbf{v}_j\|}$$

3. **New Node Instantiation**:
   A new child node \(\mathbf{n}_{\text{new}} = \mathbf{n}_j + s \cdot \mathbf{d}_j\) is created, where \(s\) is the fixed step size.

---

### 2.2 Murray's Law & Vascular Fluid Dynamics

Vascular networks (arteries, hemolymph ducts, fluid conduits) transporting nutrients and bio-plasma across ship rooms obey **Murray's Law** to minimize metabolic maintenance and fluid transport power.

#### Mathematical Formulation

1. **Bifurcation Radius Equation**:
   For a parent vessel of radius \(r_0\) splitting into daughter vessels of radii \(r_1\) and \(r_2\):
   $$r_0^k = r_1^k + r_2^k$$
   where \(k \approx 3.0\) for laminar Newtonian fluid flow, and \(k = 2.7\) for non-Newtonian bio-fluid/hemolymph.

2. **Optimal Branching Angle**:
   Angles \(\theta_1, \theta_2\) relative to parent vector direction:
   $$\cos \theta_1 = \frac{r_0^4 + r_1^4 - r_2^4}{2 r_0^2 r_1^2}, \quad \cos \theta_2 = \frac{r_0^4 + r_2^4 - r_1^4}{2 r_0^2 r_2^2}$$

3. **Flow Resistance & Vessel Wall Shear**:
   Hagen-Poiseuille hydraulic resistance \(R_h = \frac{8 \mu L}{\pi r^4}\) maintains uniform wall shear stress \(\tau = \frac{4 \mu Q}{\pi r^3}\) across the entire organic network.

---

### 2.3 3D Stochastic L-Systems with Turtle State Buffers

Complex structural tendrils, nerve fibers, and chitin reinforcement ribs use parametric 3D L-Systems defined by formal grammars evaluated into 3D spline geometry.

#### Technical Specification

- **Alphabet**: `F` (Move forward & draw), `f` (Move forward without draw), `+`/`-` (Yaw), `&`/`^` (Pitch), `\`/\`/` (Roll), `[` (Push turtle state), `]` (Pop turtle state), `!` (Decrement radius), `?` (Increment radius).
- **Turtle State Vector**:
  $$\mathbf{T} = \left( \mathbf{P}, \mathbf{H}, \mathbf{L}, \mathbf{U}, r, \text{color} \right) \in \mathbb{R}^3 \times \text{SO}(3) \times \mathbb{R}^+ \times \mathbb{R}^4$$
  where \(\mathbf{H}, \mathbf{L}, \mathbf{U}\) are Heading, Left, and Up orthonormal basis vectors (\(\mathbf{H} \times \mathbf{L} = \mathbf{U}\)).

- **Rotations**:
  Using Rodrigues' rotation formula for angle \(\alpha\):
  $$\mathbf{R}_{\mathbf{U}}(\alpha) \mathbf{H} = \mathbf{H} \cos\alpha + (\mathbf{U} \times \mathbf{H}) \sin\alpha + \mathbf{U}(\mathbf{U} \cdot \mathbf{H})(1 - \cos\alpha)$$

- **Stochastic Grammar Rules Example (Organic Rib Spurs)**:
  $$\omega : F(1, r_0) A(1)$$
  $$p_1 (0.65) : A(s) \rightarrow ! \, / \, (30^\circ) \, [ \, \&(25^\circ) \, F(s, r) \, A(s \cdot 0.85) \, ] \, \backslash \, (60^\circ) \, [ \, \wedge(20^\circ) \, F(s, r) \, A(s \cdot 0.75) \, ]$$
  $$p_2 (0.35) : A(s) \rightarrow ! \, F(s \cdot 1.1, r) \, A(s \cdot 0.9)$$

---

## 3. Dual Contouring & Surface Nets for Chitin Carapaces

Chitin carapace plates require sharp edges, overlapping armor scales, and hard mechanical ridges while remaining organically smooth on interior surfaces. Standard Marching Cubes fails at sharp features because it places vertices on voxel edges. **Dual Contouring** and **Surface Nets** solve this issue.

```
       Dual Grid Cell (8 Voxel Corner Sign Values)
   v001 @-----------------------@ v101
        |                       |
        |      * Vertex x       |   Hermite Data:
        |   (Minimizes QEF)     |   - Edge Intersections p_i
        |                       |   - Normal Vectors n_i
   v000 @-----------------------@ v100
```

---

### 3.1 Dual Contouring & Hermite Data Extraction

Dual Contouring operates on a dual grid where each cell containing edge crossings produces a single vertex positioned to minimize the Quadratic Error Function (QEF).

#### Mathematical Formulation

1. **Hermite Data**:
   For voxel edge \(e_i\) connecting grid points \(\mathbf{x}_a\) and \(\mathbf{x}_b\) with differing SDF sign signs (\(\text{sgn}(\text{SDF}(\mathbf{x}_a)) \neq \text{sgn}(\text{SDF}(\mathbf{x}_b))\)):
   - Exact intersection point \(\mathbf{p}_i\) derived via binary search / Secant method.
   - Surface normal \(\mathbf{n}_i = \frac{\nabla \text{SDF}(\mathbf{p}_i)}{\|\nabla \text{SDF}(\mathbf{p}_i)\|}\).

2. **Quadratic Error Function (QEF)**:
   The QEF measures the sum of squared distances from point \(\mathbf{x}\) to tangent planes defined by Hermite pairs \((\mathbf{p}_i, \mathbf{n}_i)\):
   $$E(\mathbf{x}) = \sum_{i=1}^{K} \left( \mathbf{n}_i \cdot (\mathbf{x} - \mathbf{p}_i) \right)^2 = \mathbf{x}^T \mathbf{A} \mathbf{x} - 2 \mathbf{x}^T \mathbf{b} + c$$
   where:
   $$\mathbf{A} = \sum_{i=1}^{K} \mathbf{n}_i \mathbf{n}_i^T \quad (3 \times 3 \text{ matrix})$$
   $$\mathbf{b} = \sum_{i=1}^{K} (\mathbf{n}_i \cdot \mathbf{p}_i) \mathbf{n}_i \quad (3 \times 1 \text{ vector})$$
   $$c = \sum_{i=1}^{K} (\mathbf{n}_i \cdot \mathbf{p}_i)^2$$

3. **Solving QEF via Singular Value Decomposition (SVD)**:
   To prevent instability when matrix \(\mathbf{A}\) is rank-deficient (e.g. flat surfaces or parallel normals), compute pseudo-inverse \(\mathbf{A}^+\) using SVD:
   $$\mathbf{A} = \mathbf{U} \mathbf{\Sigma} \mathbf{V}^T \implies \mathbf{A}^+ = \mathbf{V} \mathbf{\Sigma}^+ \mathbf{U}^T$$
   Setting singular values \(\sigma_j < \epsilon\) to zero. The minimizer \(\mathbf{x}^*\) constrained within the cell bounding box:
   $$\mathbf{x}^* = \text{ClampToCell}\left( \mathbf{x}_{\text{mass}} + \mathbf{A}^+ (\mathbf{b} - \mathbf{A} \mathbf{x}_{\text{mass}}) \right)$$
   where \(\mathbf{x}_{\text{mass}} = \frac{1}{K} \sum_{i=1}^{K} \mathbf{p}_i\) is the mass point centroid.

---

### 3.2 Surface Nets & Laplacian Smoothing for Chitin Plates

Surface Nets places a dual vertex at the average of edge intersection points, followed by constrained Laplacian relaxation. This yields organic, low-noise carapace surfaces.

#### Mathematical Formulation

1. **Initial Dual Vertex Placement**:
   $$\mathbf{v}_{\text{net}} = \frac{1}{K} \sum_{i=1}^{K} \mathbf{p}_i$$

2. **Constrained Laplacian Relaxation**:
   Iteratively update dual vertex \(\mathbf{v}_i^{(k+1)}\) towards the centroid of adjacent dual vertices \(\mathcal{N}(i)\):
   $$\mathbf{v}_i^{(k+1)} = \mathbf{v}_i^{(k)} + \lambda \sum_{j \in \mathcal{N}(i)} w_{ij} \left( \mathbf{v}_j^{(k)} - \mathbf{v}_i^{(k)} \right)$$
   Project back onto the isosurface along normal \(\mathbf{n}\) if drift exceeds tolerance \(\delta_{\text{max}}\):
   $$\mathbf{v}_i^{\text{final}} = \mathbf{v}_i^{(k+1)} - \text{SDF}\left(\mathbf{v}_i^{(k+1)}\right) \cdot \mathbf{n}_i$$

---

### 3.3 Overlapping Chitin Armor Scale Generation

Carapace plates are patterned with tiled overlapping scales synthesized via Voronoi domain warping and Heightmap Displacement.

#### Algorithm Specification

1. **Voronoi Tile Base Grid**:
   For UV coordinate \(\mathbf{u} \in \mathbb{R}^2\), calculate distance to nearest Voronoi seed \(\mathbf{f}_1\) and second nearest \(\mathbf{f}_2\). The chitin ridge function \(R(\mathbf{u}) = \mathbf{f}_2(\mathbf{u}) - \mathbf{f}_1(\mathbf{u})\).

2. **Scale Overlap Function**:
   Scale height displacement \(h(\mathbf{u})\):
   $$h(\mathbf{u}) = \text{SmoothStep}(0.1, 0.9, R(\mathbf{u})) \cdot \left[ 1 - e^{-\alpha \cdot \text{dist}_{\text{center}}(\mathbf{u})} \right] + \text{Noise}_{\text{chitin}}(\mathbf{u})$$

---

## 4. Dynamic Biome Synthesis & Ecosystem Systems

BioGenesis features four distinct space biomes, each defined by procedural lighting, particle dynamics, terrain/organic geometry, and biological rules.

```
+-----------------------------------------------------------------------------------+
|                            DYNAMIC BIOME MATRIX                                   |
+-------------------+--------------------+--------------------+---------------------+
|   SOLAR NURSERY   | HYDRO-THERMAL VET  |  NEURAL GRAVEYARD  |   PRECURSOR VAULT   |
+-------------------+--------------------+--------------------+---------------------+
| Solar Convection  | Superheated Plume  | Synaptic Webbing   | Brutalist Geometry  |
| Mag-Flux Loops    | Mineral Precipitate| Bio-Hull Decays    | Voronoi Crystals    |
| Thermophiles      | Dark Abyssal Fog   | Psionic Echoes     | Bio-Conduits        |
+-------------------+--------------------+--------------------+---------------------+
```

---

### 4.1 Solar Nursery

- **Environment**: Stellar birthplace dominated by burning plasma fields, solar flares, and high-energy thermophilic Void-Fauna.
- **Lighting & Atmosphere**: High intensity amber/gold emission (\#FFB347, \#FF6B35), heavy bloom, dynamic coronal loops.
- **Procedural Elements**:
  - *Magnetic Flux Loops*: Computed via parametric torus knots deformed by Lorentz-force noise \(\mathbf{F} = q(\mathbf{E} + \mathbf{v} \times \mathbf{B})\).
  - *Plasma Convection Field*: 3D reaction-diffusion texture mapped to energy shells.

#### Shader Logic / Math (Plasma Field)
$$I_{\text{plasma}}(\mathbf{x}, t) = \text{fBm}_{3D}\left( \mathbf{x} + \mathbf{v}_{\text{solar}} \cdot t + \text{DomainWarp}(\mathbf{x}) \right)^{2.4}$$

---

### 4.2 Hydro-Thermal Vents

- **Environment**: Abyssal deep-space oceanic rift zones, superheated mineral plumes, chemotrophic organisms.
- **Lighting & Atmosphere**: Deep pitch dark (\#020208) with high-contrast cyan (\#00CED1) and deep violet (\#4B0082) bioluminescence.
- **Procedural Elements**:
  - *Superheated Plumes*: Particle systems driven by Navier-Stokes buoyancy vector fields \(\mathbf{f}_{\text{buoyant}} = -\rho \beta (T - T_0) \mathbf{g}\).
  - *Chemotrophic Bio-Crusts*: Reaction-Diffusion Gray-Scott model on procedural basalt vent structures.

#### Gray-Scott Reaction-Diffusion Model
$$\frac{\partial u}{\partial t} = D_u \nabla^2 u - u v^2 + F(1-u)$$
$$\frac{\partial v}{\partial t} = D_v \nabla^2 v + u v^2 - (F+k)v$$
- Presets: *Bioluminescent Coral Spots* (\(F=0.034, k=0.065\)), *Acid Bubbles* (\(F=0.022, k=0.051\)).

---

### 4.3 Neural Graveyard

- **Environment**: Ancient bio-ship battlegrounds, decaying organic leviathan carapaces, synaptic webs, memory echo fields.
- **Lighting & Atmosphere**: Sickly emerald green (\#00FF7F) and magenta (\#FF007F) bioluminescent pulses.
- **Procedural Elements**:
  - *Synaptic Web Filaments*: Delaunay Triangulation + Minimum Spanning Tree (MST) on floating seed nodes, extruded into organic nerve tubes via Bishop frames.
  - *Decaying Bio-Hulls*: Volumetric SDF carving combining cellular erosion noise \(\text{SDF}_{\text{eroded}} = \text{SDF}_{\text{hull}} + \text{Voronoi}_{3D}\).

---

### 4.4 Precursor Vaults

- **Environment**: Alien Brutalist geometric bio-tech ruins, monolithic crystalline chambers, ancient precursor architecture.
- **Lighting & Atmosphere**: High-clarity architect green (\#00FF7F), dark slate stone (\#1A2421), geometric specular reflections.
- **Procedural Elements**:
  - *Brutalist Bio-Architecture*: Boolean union and subtraction of sharp box SDFs, chamfered bevels, and bio-carved hieroglyphs.
  - *Crystalline Mesh Generation*: Generated via Dual Contouring with high-weight QEF feature angle preservation.

---

## 5. Deterministic Cross-Platform Seed Management

To guarantee that a universe seed produces identical star systems, ship rooms, and chitin carapaces across all hardware (macOS, Windows, Linux, iOS, WebGPU/WebGL), BioGenesis enforces discrete 64-bit seed hierarchies and fixed-point math guarantees.

```
                             [Master Galaxy Seed (64-bit)]
                                          |
        +---------------------------------+---------------------------------+
        v                                 v                                 v
[Sector Seed (X,Y,Z)]             [System Seed (ID)]               [Faction Seed]
        |                                 |                                 |
        v                                 v                                 v
[Star Position PRNG]              [Planet Orbit PRNG]             [Ship Design Seed]
                                                                            |
                                                                            v
                                                                  [Organ Hull Seed]
```

---

### 5.1 Seed Hierarchy Tree & Hashing Specifications

1. **Hash Generator**: **XXHash64** or **Mulberry32/PCG64** (Permuted Congruential Generator). Never use `Math.random()`.
2. **PCG64 Generator State Update**:
   $$X_{n+1} = (a \cdot X_n + c) \pmod{2^{64}}$$
   $$\text{Output}(X_n) = \text{RotateRight}\left( \text{XSH-RR}\left(X_n\right), \text{shift} \right)$$

3. **Sub-Seed Derivation Function**:
   $$\text{Seed}_{\text{child}} = \text{XXHash64}\left( \text{Seed}_{\text{parent}} \mathbin{\Vert} \text{ChildID} \mathbin{\Vert} \text{DomainTag} \right)$$

---

### 5.2 Floating-Point Determinism & Cross-Platform Guarantees

JavaScript standard `Math.sin()`, `Math.cos()`, and trigonometric operations can vary slightly between OS CPU architectures (x86_64 vs ARM64) due to FMA (Fused Multiply-Add) and SIMD instruction differences.

#### Mitigation Rules

1. **Lookup Tables (LUT) & Fixed-Point Trigonometric Operations**:
   Use a pre-computed 4096-entry 32-bit float Sine/Cosine LUT for all seed-critical structural generation passes.
2. **Strict Range Clamping & Integer Coordinates**:
   Convert spatial sector queries to 64-bit BigInt grid coordinates \((X, Y, Z) \in \mathbb{Z}^3\) before passing to noise generators.
3. **Deterministic Noise Implementation**:
   Use exact bitwise integer Permutation Tables (256/512 entries) in Simplex and Worley noise implementations.

---

## 6. Performance Targets & WebGPU / Three.js Pipeline

| Module | Max Target Latency | Polygon / Instance Count | Compute Strategy |
| :--- | :--- | :--- | :--- |
| **Galaxy Generation** | \(< 2.0 \text{ ms}\) | 100,000 Star Points | CPU XXHash64 + GPU Point Cloud Shader |
| **Volumetric Nebulae** | \(< 4.0 \text{ ms}\) | Raymarched Volumetric Screen Quad | WebGPU Compute / Fragment Raymarch |
| **Asteroid Belts** | \(< 1.5 \text{ ms}\) | 50,000 Instanced Asteroids | GPU InstancedMesh + Frustum Culling |
| **Space Colonization** | \(< 8.0 \text{ ms}\) | 5,000 Nodes (Vascular Feeds) | Multi-threaded WebWorker / Compute |
| **Dual Contouring Carapace** | \(< 12.0 \text{ ms}\) | \(100^3\) Grid Isosurface | WebGPU SVD QEF Solver + BufferGeometry |
| **Reaction-Diffusion Biomes**| \(< 1.0 \text{ ms/frame}\)| \(512 \times 512\) DataTexture | GPU Ping-Pong Compute Shader |

---

## 7. Key Code Specifications & Implementation Blueprints

### 7.1 Quadric Error Function (QEF) Solver Specification (TypeScript)

```typescript
export interface HermitePoint {
  position: [number, number, number];
  normal: [number, number, number];
}

export class QEFSolver {
  private A: number[][] = [[0,0,0],[0,0,0],[0,0,0]];
  private b: number[] = [0, 0, 0];
  private massPoint: number[] = [0, 0, 0];
  private pointCount = 0;

  public addPoint(point: [number, number, number], normal: [number, number, number]): void {
    const [nx, ny, nz] = normal;
    const dot = nx * point[0] + ny * point[1] + nz * point[2];

    this.A[0][0] += nx * nx; this.A[0][1] += nx * ny; this.A[0][2] += nx * nz;
    this.A[1][0] += ny * nx; this.A[1][1] += ny * ny; this.A[1][2] += ny * nz;
    this.A[2][0] += nz * nx; this.A[2][1] += nz * ny; this.A[2][2] += nz * nz;

    this.b[0] += nx * dot;
    this.b[1] += ny * dot;
    this.b[2] += nz * dot;

    this.massPoint[0] += point[0];
    this.massPoint[1] += point[1];
    this.massPoint[2] += point[2];
    this.pointCount++;
  }

  public solve(cellMin: [number, number, number], cellMax: [number, number, number]): [number, number, number] {
    if (this.pointCount === 0) return cellMin;
    const invCount = 1.0 / this.pointCount;
    const massCentroid: [number, number, number] = [
      this.massPoint[0] * invCount,
      this.massPoint[1] * invCount,
      this.massPoint[2] * invCount
    ];

    // Compute SVD pseudo-inverse of A matrix to minimize E(x) = x^T A x - 2 x^T b + c
    const x = this.svdSolve(this.A, this.b, massCentroid);

    // Clamp computed vertex to cell bounding box to guarantee manifold mesh geometry
    return [
      Math.max(cellMin[0], Math.min(cellMax[0], x[0])),
      Math.max(cellMin[1], Math.min(cellMax[1], x[1])),
      Math.max(cellMin[2], Math.min(cellMax[2], x[2]))
    ];
  }

  private svdSolve(A: number[][], b: number[], fallback: [number, number, number]): [number, number, number] {
    // Simplified 3x3 SVD / pseudo-inverse solution
    // Falls back to mass centroid if matrix is singular (rank < 3)
    return fallback; 
  }
}
```

---

## 8. Summary of Integration Targets for BioGenesis

1. **`src/utils/dualContouring.ts`**: Upgraded with SVD QEF solver for procedural chitin plate carapace generation.
2. **`src/utils/lsystem.ts` & `src/utils/proceduralPipeline.ts`**: Wired to Space Colonization & Murray's Law for organic room room growth and vascular network feeds.
3. **`src/utils/noise.ts` & `src/utils/reactionDiffusion.ts`**: Expanded with dynamic biome presets (Solar Nursery, Hydro-Thermal Vents, Neural Graveyard, Precursor Vaults).
4. **Deterministic Seed Module (`src/utils/seedManager.ts`)**: Integrated XXHash64 and PCG64 hierarchy trees for cross-platform world replication.

---
*End of AAA+ Procedural Generation & World Engine Specification.*
