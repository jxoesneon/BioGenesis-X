# Research Report: Physics & Tissue Deformation Architecture for BioGenesis (AAA+ Quality)

**Author:** Subagent 2 (AAA+ Physics & Tissue Deformation Architect)  
**Swarm / Loop:** AAA+ Engineering Research Swarm — Loop 1  
**Target System:** BioGenesis Living-Ship Soft-Body & Hydro-Vascular Engine  
**Status:** Approved Technical Architecture & Mathematical Specification  

---

## Executive Summary

BioGenesis represents a living-ship biopunk simulation where ships are grown organic organisms rather than rigid metal structures. Achieving AAA+ quality physics requires going beyond rigid-body approximations to simulate **hyperelastic tissue deformation**, **active muscular contraction**, **high-pressure hydro-pulse jet propulsion**, **viscous hemolymph Fluid-Structure Interaction (FSI)**, **strain-induced mesh fracture tearing**, and **statically stable organ placement force-fields**.

This report establishes the complete mathematical, algorithmic, and architectural specification for the BioGenesis Physics Engine, designed for execution in TypeScript/Three.js with WebGPU compute shader acceleration.

---

## 1. XPBD & Chaos Soft-Body Physics for Organ Deformation

### 1.1 Extended Position-Based Dynamics (XPBD) Formulation
Traditional Position-Based Dynamics (PBD) suffers from severe iteration- and timestep-dependent stiffness. BioGenesis adopts **Extended Position-Based Dynamics (XPBD)** (Macklin et al., 2016), introducing compliance $\alpha = 1/k$ (inverse stiffness) and physical damping $\beta$ directly into the constraint force formulation.

#### State Vector & Time Integration
For a mesh with $N$ vertices, position $\mathbf{x}_i \in \mathbb{R}^3$, velocity $\mathbf{v}_i \in \mathbb{R}^3$, and mass $m_i$ ($M = \text{diag}(m_1 \mathbf{I}, \dots, m_N \mathbf{I})$):

$$\mathbf{x}_i^* = \mathbf{x}_i^t + \Delta t \mathbf{v}_i^t + \Delta t^2 \mathbf{M}^{-1} \mathbf{f}_{ext}$$

#### Constraint Equations & Lagrange Multipliers
For a vector of constraints $\mathbf{C}(\mathbf{x}) = \mathbf{0}$, XPBD solves for Lagrange multiplier updates $\Delta \boldsymbol{\lambda}$:

$$\Delta \lambda_j = \frac{-C_j(\mathbf{x}^*) - \tilde{\alpha}_j \lambda_j}{\boldsymbol{\nabla} C_j^T \mathbf{M}^{-1} \boldsymbol{\nabla} C_j + \tilde{\alpha}_j}$$

where:
$$\tilde{\alpha}_j = \frac{\alpha_j}{\Delta t^2 \left(1 + \frac{\beta_j}{\Delta t}\right)}$$

Position corrections for vertex $i$ participating in constraint $j$:
$$\Delta \mathbf{x}_i = \mathbf{M}_i^{-1} \boldsymbol{\nabla}_{\mathbf{x}_i} C_j \Delta \lambda_j$$
$$\mathbf{x}_i^* \leftarrow \mathbf{x}_i^* + \Delta \mathbf{x}_i$$

Velocity update with numerical damping:
$$\mathbf{v}_i^{t+\Delta t} = \frac{\mathbf{x}_i^* - \mathbf{x}_i^t}{\Delta t}$$

---

### 1.2 Constraint Types for Volumetric Organic Organs

```
               [ Volumetric Tetrahedron Mesh ]
                           /\
                          /  \  <- Distance Constraints (Edges)
                         /    \
                        /______\ <- Volume Preservation (Tetrahedron)
                       /\      /\
                      /  \    /  \ <- Hyperelastic Strain Energy (Neo-Hookean)
                     /____\  /____\
```

#### 1. Distance Constraint (Skin & Tendons)
$$C_{dist}(\mathbf{x}_1, \mathbf{x}_2) = \|\mathbf{x}_1 - \mathbf{x}_2\| - d_0$$
$$\boldsymbol{\nabla}_{\mathbf{x}_1} C_{dist} = \mathbf{n}_{12} = \frac{\mathbf{x}_1 - \mathbf{x}_2}{\|\mathbf{x}_1 - \mathbf{x}_2\|}, \quad \boldsymbol{\nabla}_{\mathbf{x}_2} C_{dist} = -\mathbf{n}_{12}$$

#### 2. Tetrahedron Volume Preservation (Organ Parenchyma)
For a tetrahedral element with vertices $(\mathbf{x}_1, \mathbf{x}_2, \mathbf{x}_3, \mathbf{x}_4)$:
$$C_{vol}(\mathbf{x}_1, \mathbf{x}_2, \mathbf{x}_3, \mathbf{x}_4) = \frac{1}{6} (\mathbf{x}_2 - \mathbf{x}_1) \cdot \left((\mathbf{x}_3 - \mathbf{x}_1) \times (\mathbf{x}_4 - \mathbf{x}_1)\right) - V_0$$
$$\boldsymbol{\nabla}_{\mathbf{x}_1} C_{vol} = -\frac{1}{6} (\mathbf{x}_2 - \mathbf{x}_3) \times (\mathbf{x}_4 - \mathbf{x}_3)$$

#### 3. Stable Neo-Hookean Hyperelastic Material Constraint
For organic tissue undergoing large non-linear deformations (e.g., heart pumping, liver impact), we enforce a strain energy density constraint based on the deformation gradient $\mathbf{F} = \frac{\partial \mathbf{x}}{\partial \mathbf{X}}$:

$$\Psi_{Neo-Hookean}(\mathbf{F}) = \frac{\mu}{2} \left(\text{tr}(\mathbf{F}^T \mathbf{F}) - 3\right) + \frac{\lambda}{2} (J - 1)^2$$
where $J = \det(\mathbf{F})$, and $\mu, \lambda$ are Lamé parameters related to Young's modulus $E$ and Poisson's ratio $\nu$:
$$\mu = \frac{E}{2(1 + \nu)}, \quad \lambda = \frac{E \nu}{(1 + \nu)(1 - 2\nu)}$$

In XPBD, the Neo-Hookean energy density per tetrahedron element is solved as a scalar strain constraint:
$$C_{NH}(\mathbf{x}) = \sqrt{2 \Psi_{Neo-Hookean}(\mathbf{F}) \cdot V_0}$$

---

### 1.3 Hyperelastic Tissue Material Matrix

| Organ Tissue Type | Young's Modulus $E$ (kPa) | Poisson Ratio $\nu$ | Compliance $\alpha$ ($m^2/N$) | Damping $\beta$ ($s$) |
| :--- | :--- | :--- | :--- | :--- |
| **Cardiac Myocardium** | 120.0 | 0.48 (quasi-incompressible) | $8.33 \times 10^{-6}$ | 0.025 |
| **Hepatic / Glandular Tissue** | 15.0 | 0.45 | $6.67 \times 10^{-5}$ | 0.040 |
| **Arterial Vessel Wall** | 450.0 | 0.49 | $2.22 \times 10^{-6}$ | 0.010 |
| **Chitinous Carapace Plate** | 5000.0 | 0.30 | $2.00 \times 10^{-7}$ | 0.002 |
| **Tentacle Muscle Core** | 45.0 | 0.47 | $2.22 \times 10^{-5}$ | 0.030 |

---

### 1.4 Spatial Acceleration for Collision & Self-Collision
For dynamic collisions between internal organs and ship carapace, BioGenesis employs **GPU Uniform Spatial Hashing** combined with a **Bounding Volume Hierarchy (BVH)**:

1. **Cell Hash Key Function**:
   $$H(x, y, z) = \left(( \lfloor x / S \rfloor \times 73856093) \oplus (\lfloor y / S \rfloor \times 19349663) \oplus (\lfloor z / S \rfloor \times 83492791)\right) \bmod M_{hash}$$
   where $S = 2 \times \max(r_{particle})$ is cell size, $M_{hash} = 65536$.
2. **Sub-stepping & Convergence**:
   - Sub-steps per frame: $N_{sub} = 8$ to $16$.
   - Solver iterations per sub-step: $N_{iter} = 4$.
   - This architecture prevents interpenetration during $20G$ extreme maneuvers.

---

## 2. Muscle Contraction & Sphincter Hydro-Pulse Propulsion Physics

### 2.1 Active Muscle Contraction Algorithm
To simulate bio-mechanical propulsion and organ contraction, BioGenesis combines the **Hill-Type Active Muscle Model** with anisotropic fiber-oriented stress tensors.

```
       +-------------------------------------------------------+
       |                  Active Muscle Fiber                  |
       |  f_0 (Fiber Dir) -------> Active Contraction T_active |
       +-------------------------------------------------------+
                |                                 |
        [Parallel Elastic]               [Series Elastic]
            F_PE(lambda)                    F_SE(lambda)
```

#### Fiber Stress Tensor Formulation
Total Cauchy stress in muscular tissue:
$$\boldsymbol{\sigma}_{total} = \boldsymbol{\sigma}_{passive}(\mathbf{F}) + \boldsymbol{\sigma}_{active}(a, \lambda_{f})$$

Active stress contribution oriented along fiber unit vector $\mathbf{f}_0$:
$$\boldsymbol{\sigma}_{active} = a(t) \cdot \sigma_{max} \cdot f_L(\lambda_f) \cdot f_V(\dot{\lambda}_f) \cdot (\mathbf{f}_0 \otimes \mathbf{f}_0)$$

where:
- $a(t) \in [0, 1]$: Neural activation signal from the ship's brain/ganglion.
- $\sigma_{max}$: Maximum isometric muscular stress ($\approx 350 \text{ kPa}$).
- $\lambda_f = \|\mathbf{F} \mathbf{f}_0\|$: Fiber stretch ratio.
- $f_L(\lambda_f) = \exp\left(-\left|\frac{\lambda_f - 1}{W}\right|^b\right)$: Force-length relationship ($W=0.4, b=1.8$).
- $f_V(\dot{\lambda}_f)$: Force-velocity relationship (Hill relation during shortening, force enhancement during lengthening).

---

### 2.2 Muscular Sphincter Nozzle Hydro-Pulse Jet Propulsion

Propulsion in BioGenesis living ships is generated by muscular caudal sphincters ejecting high-velocity bio-plasma or hemolymph fluid in pulsating jets.

```
  Caudal Conduit (Radius R_0)        Sphincter Nozzle (Radius R_exit)
  ===========================\      /===============================
  --> Peristaltic Wave      ===>   ||  ===> Ejected Jet Stream v_e
  ===========================/      \===============================
  <--- Length L --->                 <-- Constriction Ratio gamma -->
```

#### Peristaltic Wave Propagation Dynamics
A peristaltic contraction wave propagates posteriorly along the caudal conduit of length $L$:
$$R(z, t) = R_0 - A_{peri} \sin^2\left(\frac{\pi}{\lambda_{wave}} (z - c_{wave} t)\right)$$

where $c_{wave}$ is wave propagation velocity ($15 - 45 \text{ m/s}$), $A_{peri}$ is contraction amplitude.

#### Sphincter Contraction Pressure (Laplace's Law for Thick Muscular Walls)
The internal hydro-dynamic pressure generated inside the nozzle chamber by sphincter muscular contraction:
$$P_{muscular}(t) = P_{ambient} + \frac{\sigma_{active}(a, \lambda_\theta) \cdot h_{wall}(t)}{R_{exit}(t)}$$
where $h_{wall}(t) = h_0 \frac{R_0}{R_{exit}(t)}$ (volume preservation of sphincter wall tissue).

#### Ejection Velocity Equation (Unsteady Bernoulli with Nozzle Constriction)
Applying unsteady Bernoulli along the caudal lumen with exit area ratio $\gamma(t) = \frac{A_{exit}(t)}{A_{conduit}}$:

$$v_e(t) = \sqrt{\frac{2 \left(P_{muscular}(t) - P_{ambient}\right)}{\rho_{fluid} \left(1 - \gamma(t)^2\right) + \frac{\rho_{fluid} L_{nozzle}}{A_{exit}(t)} \frac{d A_{exit}}{dt}}}$$

#### Net Hydro-Pulse Thrust Force Equation
The instant thrust force $F_{thrust}(t)$ delivered to the ship hull:

$$F_{thrust}(t) = \dot{m}(t) v_e(t) + \left(P_{exit}(t) - P_{ambient}\right) A_{exit}(t)$$

$$\dot{m}(t) = \rho_{fluid} A_{exit}(t) v_e(t)$$

$$F_{thrust}(t) = \rho_{fluid} A_{exit}(t) v_e(t)^2 + \left(P_{muscular}(t) - P_{ambient}\right) \gamma(t) A_{exit}(t)$$

#### Total Impulse per Pulsation Cycle
$$J_{pulse} = \int_{0}^{T_{cycle}} F_{thrust}(t) \, dt$$

---

## 3. Fluid-Structure Interaction (FSI) for Arterial Hemolymph Dynamics

### 3.1 1D Reduced Navier-Stokes Arterial Network
The arterial system (flank arteries, dorsal aorta, caudal feeds) is modeled as a compliance-coupled 1D vascular network.

```
       Heart / Pulse Generator
                ||
     +----------++----------+
     | Primary  |  Flank    |
     | Aorta    |  Artery   |
     +----+-----+-----+-----+
          |           |
          v           v
     [ Windkessel Compliance Chambers ]
```

#### Governing Partial Differential Equations
$$\frac{\partial A}{\partial t} + \frac{\partial Q}{\partial z} = 0 \quad \text{(Mass Conservation)}$$

$$\frac{\partial Q}{\partial t} + \frac{\partial}{\partial z} \left( \frac{Q^2}{A} \right) + \frac{A}{\rho} \frac{\partial p}{\partial z} = -K_r \frac{Q}{A} \quad \text{(Momentum Conservation)}$$

where:
- $A(z, t)$: Local arterial cross-sectional area.
- $Q(z, t) = A u$: Volumetric flow rate ($u$ = average axial velocity).
- $\rho$: Hemolymph density ($\approx 1060 \text{ kg/m}^3$).
- $K_r = \frac{8 \pi \mu}{\rho}$: Friction profile resistance ($\mu$ = dynamic viscosity).

#### Non-Linear Elastic Pressure-Area Constitutive Relation
$$p(A, z) = p_0 + \frac{\beta_{wall}}{A_0(z)} \left(\sqrt{A(z, t)} - \sqrt{A_0(z)}\right)$$

$$\beta_{wall} = \frac{4}{3} \sqrt{\pi} E_{wall} h_{wall}$$

---

### 3.2 Pulse Wave Velocity (PWV) & Moens-Korteweg Equation
Pressure pulses generated by heartbeats propagate down compliant vessels at Pulse Wave Velocity ($PWV$):

$$PWV = c_p = \sqrt{\frac{A}{\rho} \frac{\partial p}{\partial A}} = \sqrt{\frac{E_{wall} h_{wall}}{2 \rho R_0}}$$

For BioGenesis arterial parameters ($E_{wall} = 450 \text{ kPa}, h/R_0 = 0.15, \rho = 1060 \text{ kg/m}^3$):
$$PWV = \sqrt{\frac{450000 \times 0.15}{2 \times 1060}} \approx 5.64 \text{ m/s}$$

---

### 3.3 Three-Element Windkessel Terminal Boundary Condition
At terminal capillary beds (organ feeds), the 1D domain connects to a 3-Element Windkessel Model representing distal vascular resistance and tissue compliance:

```
  1D Vessel End ----[ R_1 ]----+----[ R_2 ]----> Venous Return
                               |
                             [ C_t ]
                               |
                              GND
```

$$Q(t) \left(1 + \frac{R_1}{R_2}\right) + C_t R_1 \frac{dQ}{dt} = \frac{P(t) - P_{venous}}{R_2} + C_t \frac{dP}{dt}$$

where:
- $R_1$: Characteristic impedance of arterial tube.
- $R_2$: Peripheral vascular resistance of target organ.
- $C_t$: Tissue compliance reservoir.

---

### 3.4 Non-Newtonian Viscosity of Hemolymph (Carreau-Yasuda Model)
Biopunk hemolymph exhibits shear-thinning non-Newtonian dynamics. Dynamic viscosity $\mu(\dot{\gamma})$ depends on shear rate $\dot{\gamma} = \left|\frac{\partial u}{\partial r}\right|$:

$$\mu(\dot{\gamma}) = \mu_\infty + (\mu_0 - \mu_\infty) \left[ 1 + (\lambda_{cy} \dot{\gamma})^a \right]^{\frac{n-1}{a}}$$

- $\mu_0 = 0.050 \text{ Pa}\cdot\text{s}$ (zero shear viscosity, thick like oil).
- $\mu_\infty = 0.0035 \text{ Pa}\cdot\text{s}$ (high shear viscosity, water-like flow).
- $\lambda_{cy} = 3.313 \text{ s}$, $a = 1.25$, $n = 0.356$ (shear thinning exponent).

---

## 4. Damage Mesh Fracturing & Real-Time Procedural Wound Tearing

### 4.1 Strain-Based Element Tearing & Fracture Criterion
When kinetic impacts or bio-plasma fire strikes an organ or hull carapace, BioGenesis computes the **Green-Lagrange Strain Tensor** for each tetrahedral/triangular element:

$$\mathbf{E} = \frac{1}{2} \left( \mathbf{F}^T \mathbf{F} - \mathbf{I} \right)$$

#### Principal Tensile Strain Criterion
The eigenvalues $\varepsilon_1 \ge \varepsilon_2 \ge \varepsilon_3$ of $\mathbf{E}$ represent principal strains. Fracture occurs when principal tensile strain exceeds tissue ultimate tensile limit:

$$\varepsilon_1 > \varepsilon_{critical}$$

- **Carapace Plate**: $\varepsilon_{critical} = 0.08$ ($8\%$ max elongation).
- **Muscle / Membrane**: $\varepsilon_{critical} = 0.35$ ($35\%$ max elongation).
- **Arterial Vessel**: $\varepsilon_{critical} = 0.50$ ($50\%$ max elongation).

---

### 4.2 Procedural Cut-Plane & Voronoi Mesh Splitting Algorithm

```
        Impact Location p_impact
                 |
        [ Voronoi Cell Generation ]
                 |
        +--------+--------+
        | Cell A | Cell B |  <- Dynamic Edge Duplication along Cut Plane
        +--------+--------+
                 |
        [ Cap Geometry Hole Filling ]
                 |
        [ Spawn Hemolymph Emitters & Necrotic Tissue Tex ]
```

#### Step-by-Step Algorithm
1. **Fracture Seeding**: Upon impact at $\mathbf{p}_{impact}$ with kinetic energy $K_e$, generate $N_{fracture} = \min(32, \lfloor K_e / K_0 \rfloor)$ Voronoi seed points on the surface mesh.
2. **Edge Splitting**: For every mesh edge $e_{ij} = (\mathbf{x}_i, \mathbf{x}_j)$ intersecting a Voronoi boundary or cut plane $\mathbf{n}_{cut} \cdot (\mathbf{x} - \mathbf{p}_0) = 0$:
   $$t_{split} = \frac{\mathbf{n}_{cut} \cdot (\mathbf{p}_0 - \mathbf{x}_i)}{\mathbf{n}_{cut} \cdot (\mathbf{x}_j - \mathbf{x}_i)}$$
   Create new vertex $\mathbf{x}_{new} = \mathbf{x}_i + t_{split} (\mathbf{x}_j - \mathbf{x}_i)$.
3. **Topology Duplication**: Duplicate vertices along the fracture boundary to break edge connectivity, creating two distinct mesh sub-components.
4. **Hole Capping (Ear Clipping / Delaunay Triangulation)**: Construct closed inner boundary loops along split planes and triangulate to form inner flesh surfaces.
5. **Necrotic & Vascular Decorator**:
   - Assign procedural wound UVs to internal cap triangles.
   - Attach particle emitters for hemolymph spray at severed arterial stubs.

---

## 5. Force-Field Organ Solver Stability & Clearance Constraints

### 5.1 Mathematical Force-Field Repulsion Potential
In BioGenesis, organ placement is governed by continuous non-linear potential energy fields to keep internal organs from overlapping while constraining them to anatomically valid sections along the ship's 5-section spine.

```
       V(r) Repulsion Potential
        ^
    Max | \
   Force|  \  Quadratic Repulsion Zone
        |   \
        |    +----------------------------- Zero Force
        +----+------------------------------> r (Inter-Organ Center Dist)
           r_min   Clearance R_clear
```

#### Combined Potential Field Equation
For two organs $A$ and $B$ centered at $\mathbf{p}_A, \mathbf{p}_B$ with clearance radii $R_A, R_B$:
$$R_{clear} = R_A + R_B$$
$$r = \|\mathbf{p}_A - \mathbf{p}_B\|$$
$$\mathbf{n}_{AB} = \frac{\mathbf{p}_A - \mathbf{p}_B}{r}$$

The repulsion force $\mathbf{F}_{repulsion}$ applied to organ $A$:

$$\mathbf{F}_{repulsion} = \begin{cases}
k_{rep} \left(R_{clear} - r\right)^2 \mathbf{n}_{AB} + k_{exp} \exp\left(-\frac{r}{\delta}\right) \mathbf{n}_{AB} & \text{if } r < R_{clear} \\
\mathbf{0} & \text{if } r \ge R_{clear}
\end{cases}$$

where:
- $k_{rep} = 250.0 \text{ N/m}^2$: Stiffness of quadratic clearance barrier.
- $k_{exp} = 50.0 \text{ N}$: Short-range exponential anti-tunneling force.
- $\delta = 0.20 \text{ m}$: Exponential decay scale.

---

### 5.2 Section Bounds & Surface Clamping Constraints
Organs must remain locked to their assigned anatomical section $u \in [u_{min}, u_{max}]$ on the parametric hull surface $\mathbf{S}(u, v)$:

$$\mathbf{p}_{target} = \mathbf{S}(u_{clamped}, v_{original})$$
$$u_{clamped} = \text{clamp}\left(u_{current} + \Delta u_{solver}, u_{min}, u_{max}\right)$$

#### Anatomical Section Mapping Matrix

| Organ Type | Section Name | Parametric $u$ Range | Symmetry Rule |
| :--- | :--- | :--- | :--- |
| **Ocular Pods (Eyes)** | Cranial | $[0.02, 0.15]$ | Bilateral Pair ($v=0.20, 0.80$) |
| **Neural Ganglia / Brain** | Cranial + Neck | $[0.02, 0.98]$ | Central / Segmental Chain |
| **Spiracles & Ribs** | Thoracic | $[0.30, 0.65]$ | Bilateral Arrays |
| **Habitats (Crew Quarters)** | Thoracic | $[0.30, 0.60]$ | Offset Staggered ($v=0.12, 0.62, \dots$) |
| **Spores & Tentacles** | Caudal | $[0.65, 0.85]$ | Radial / Dorsal-Ventral Splays |
| **Caudal Fluke / Nozzle** | Tail Tip | $[0.85, 0.98]$ | Midline Terminal ($v=0.50$) |

---

### 5.3 Numerical Stability & Adaptive Sub-Stepping Analysis

To prevent numeric explosions during solver iterations (e.g., organ blow-up or jittering), the solver uses an **Adaptive Damped Verlet Integrator** with spatial hash acceleration.

```
       [ Spatial Hash Candidate Filter ]
                      |
       [ Evaluate Repulsion Vectors F_total ]
                      |
       [ Clamp Max Velocity Shift: ||dr|| <= dr_max ]
                      |
       [ Update Parametric U Position & Mirror Symmetry Partner ]
```

#### Step Update Formulation
For organ $i$ with virtual mass $m_i \propto R_i^3$:

$$\mathbf{a}_i = \frac{1}{m_i} \sum_{j \ne i} \mathbf{F}_{repulsion}(i, j) - \gamma_{solver} \mathbf{v}_i$$

$$\Delta \mathbf{p}_i = \mathbf{v}_i \Delta t_{solver} + \frac{1}{2} \mathbf{a}_i \Delta t_{solver}^2$$

$$\Delta \mathbf{p}_i^{clamped} = \frac{\Delta \mathbf{p}_i}{\|\Delta \mathbf{p}_i\|} \min\left(\|\Delta \mathbf{p}_i\|, \Delta r_{max}\right)$$

where:
- $\Delta r_{max} = 0.05 \text{ m}$: Maximum shift allowed per solver pass.
- $\gamma_{solver} = 12.0 \text{ s}^{-1}$: Heavy solver velocity damping coefficient for rapid static convergence.
- Pass Iterations: $N_{passes} = 45$.

---

## 6. BioGenesis Integration Blueprint & Tech Stack

```
+-----------------------------------------------------------------------+
|                    BIOGENESIS SIMULATION PIPELINE                      |
+-----------------------------------------------------------------------+
|  [ WebGPU Compute Shaders ]                                           |
|   ├── XPBD Soft-Body Solver (Tetrahedral Parenchyma & Vessel Walls)   |
|   ├── Hill Muscle Activation & Active Fiber Contraction Tensors       |
|   └── 1D FSI Hemolymph Pressure-Flow & Windkessel Solver             |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
|  [ Three.js Render & Mesh Pipeline ]                                  |
|   ├── Marching Cubes / Dual Contouring isosurface reconstruction      |
|   ├── Procedural Fracture Mesh Splitting & Wound Cap Capping          |
|   └── Reaction-Diffusion Gray-Scott Bioluminescent Tex Mapping         |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
|  [ Anatomical Force-Field Solver & Telemetry Engine ]                |
|   ├── Spatial Hash Grid Organ Clearance Solver (45 passes, damped)    |
|   └── Real-time Cardiac & Hydro-Pulse Jet Propulsion Output           |
+-----------------------------------------------------------------------+
```

---

## References

1. Macklin, M., Müller, M., & Chentanez, N. (2016). *XPBD: Extended Position-Based Dynamics*. Proceedings of the 9th International Conference on Motion in Games (MIG '16).
2. Hill, A. V. (1938). *The heat of shortening and the dynamic constants of muscle*. Proceedings of the Royal Society of London. Series B - Biological Sciences.
3. Formaggia, L., Quarteroni, A., & Veneziani, A. (2009). *Cardiovascular Mathematics: Modeling and simulation of the circulatory system*. Springer Science & Business Media.
4. Müller, M., Solenthaler, B., Keiser, R., & Gross, M. (2007). *Particle-based fluid-structure interaction*. Eurographics Workshop on Virtual Reality Interaction and Physical Simulation (VRIPHYS).
5. Ju, T., Losasso, F., Schaefer, S., & Warren, J. (2002). *Dual contouring of hermite data*. ACM Transactions on Graphics (TOG), 21(3), 339-346.
