# Best-in-Class Crafting & Synthesis Research Spec

*Generated: 2026-08-13 | Subagent 4: Crafting & Splicing Lead | Project: BioGenesis | Status: Spec & Architecture Blueprint*

---

## Executive Summary

Traditional crafting systems in sci-fi and fantasy games frequently rely on abstract grid menus, text lists, and instant inventory recipes. While functional, these abstract UI paradigms break immersion when applied to living, breathing biological entities. In **BioGenesis**, the player's living ship is not an assembled machine of cold steel; it is a bio-engineered organism grown, mutated, and grafted in real time. 

This research spec presents the **Best-in-Class Crafting & Synthesis Architecture** for BioGenesis. By synthesizing design principles from the world's most acclaimed crafting and customization systems—including *Monster Hunter* (anatomical tissue progression), *Tears of the Kingdom* (spatial physics & dynamic property fusion), *Path of Exile* (deep socketed modifier trees), *Subnautica* (diegetic physical installation), *Terraria/Minecraft* (tiered environmental synthesis), and *Cyberpunk 2077* (surgical body modification limits)—we formulate a visceral, somatic biological crafting engine.

The core technical integration leverages four foundational BioGenesis systems:
1. **Real-Time SDF Organ Smooth-Min Splicing (`organBlending.ts`)**: Volumetric implicit mesh fillets that organically fuse tissue grafts into the swept-sphere hull or parent organs without rigid seams.
2. **Continuous Chromosome Parameter Vector ($\mathbf{g} \in [0, 1]^{32}$)**: Smooth, non-linear phenotype expression mapping that drives morphology, metabolic rates, and structural scales.
3. **Mutagenic Plasmid Socketing Engine**: Support-gem-style mutagenic vectors inserted directly into organ nodes to alter physiological function and pipeline output.
4. **Hadamard Bio-Match Index ($M_H$)**: Orthogonal matrix algebra determining tissue compatibility, immune rejection risks, and dynamic blend radii ($k$).

---

## 1. Deconstruction of AAA & Acclaimed Indie Crafting Systems

To design a gold-standard biological crafting system, we first deconstruct six iconic crafting architectures across AAA and indie gaming, extracting their psychological reward drivers and mapping them directly to BioGenesis.

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                       GOLD-STANDARD CRAFTING DECONSTRUCTION MATRIX                      │
├───────────────────┬───────────────────────────────────┬─────────────────────────────────┤
│ Game / System     │ Key Psychological & Mechanics Driver│ BioGenesis Biological Mapping   │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ Monster Hunter    │ Anatomical carcass harvesting,    │ Harvesting wild Void-Fauna     │
│ (World / Rise)    │ targeted tissue hunting, visual   │ organs & chitin carapaces;      │
│                   │ armor identity matching monster.  │ visible tissue traits on ship.  │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ Zelda: TotK       │ Spatial physical fusion, dynamic  │ Drag-and-drop 3D organ grafting │
│ (Fuse / Ultrahand)│ property inheritance, structural  │ with real-time SDF smooth-min   │
│                   │ integrity vs mass trade-offs.     │ filleting (`organBlending.ts`). │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ Path of Exile     │ Massive node trees, support gem   │ 32-gene chromosome vector $\mathbf{g}$│
│ (Skill Tree/Gems) │ multiplicative chaining, severe   │ + Mutagenic Plasmids socketed   │
│                   │ keystone trade-offs.              │ into organ pipeline nodes.      │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ Subnautica        │ Diegetic physical installation,   │ Habitat chamber customization & │
│ (Vehicle Console) │ spatial module slotting, environmental│ life-support module grafting   │
│                   │ depth & pressure thresholds.      │ inside the cranial/thoracic hull.│
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ Terraria /        │ Tiered material progression,      │ Biological Incubator Chambers,  │
│ Minecraft         │ station ecosystem dependencies,   │ Enzymatic Splicing Troughs, &   │
│                   │ environmental catalyst crafting.  │ Metabolic Catalyst feeds.       │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ Cyberpunk 2077    │ Surgical body modification,       │ Hadamard Bio-Match Index ($M_H$)│
│ (Ripperdoc)       │ capacity/immuno limits, visceral  │ immune tolerance, rejection     │
│                   │ somatic installation feedback.    │ risk, & bio-immuno capacity.    │
└───────────────────┴───────────────────────────────────┴─────────────────────────────────┘
```

### 1.1 Monster Hunter World / Rise: Targeted Tissue Harvesting & Visual Identity
- **Reward Core**: Gear directly reflects the conquered target. Harvesting a Rathalos plate yields fire resistance and flared red scales.
- **BioGenesis Adaptation**: Destroying or pacifying wild Void-Fauna allows players to harvest intact organ specimens (e.g., *Abyssal Siphon Vent*, *Disruptor Gland*, *Radiotrophic Membrane*). Grafting these tissues visually transforms the ship's carapace and emissive bioluminescence to match the harvested fauna's taxonomy.

### 1.2 Zelda: Tears of the Kingdom: Spatial Physics & Property Fusion
- **Reward Core**: Infinite creativity through spatial attachment. Fusing a horn to a sword changes reach, weight, element, and damage dynamically.
- **BioGenesis Adaptation**: Organs are not abstract inventory items. Players physically position candidate organs onto the ship's hull or internal spine nodes in 3D space. Using `organBlending.ts`, the engine computes real-time Signed Distance Functions (SDFs) and generates smooth-min fillets (`opSmoothUnion`), rendering organic skin transitions, fillets, and vascular bridges.

### 1.3 Path of Exile: Multiplicative Socket Trees & Keystone Trade-Offs
- **Reward Core**: Unprecedented customization depth through socketed Support Gems that alter base skill behavior (e.g., *Greater Multiple Projectiles* adds arrows but reduces individual damage).
- **BioGenesis Adaptation**: Each organ node possesses 1 to 3 **Plasmid Sockets**. Inserting a Mutagenic Plasmid alters organ behavior. For instance, socketing a *Hyper-Vascular Plasmid* into the Heart boosts hemolymph throughput by +50%, but increases stroke pressure and metabolic energy drain by +30%.

### 1.4 Subnautica: Diegetic Installation & Environmental Scaling
- **Reward Core**: Physical interaction inside vehicle hulls; upgrades unlock deeper oceanic exploration zones by mitigating crush depth and temperature.
- **BioGenesis Adaptation**: Grafting life-support and habitat modules occurs inside the living ship's internal chambers (Command Room & Thoracic Habitats). Upgrades increase hull pressure tolerance, enabling exploration of extreme abyssal nebulae and acidic space biomes.

### 1.5 Terraria & Minecraft: Station Ecosystems & Environmental Catalysts
- **Reward Core**: Multi-tiered crafting trees gated by specialized stations (Hellforge, Mythril Anvil) and environmental conditions.
- **BioGenesis Adaptation**: Complex gene splicing requires specific organ incubators within the ship. Crafting high-tier plasmids requires feeding raw biomass and specific enzymatic catalysts through the *Moss Bed Filter* during active solar radiation or nebula immersion.

### 1.6 Cyberpunk 2077: Surgical Capacity & Immune Limits
- **Reward Core**: High-powered cyberware is constrained by "Humanity" or Cyberware Capacity limits. Over-equipping triggers debuffs or physiological strain.
- **BioGenesis Adaptation**: Every graft introduces foreign genetic code. The **Hadamard Bio-Match Index** measures immunological compatibility. Low compatibility triggers acute tissue rejection, requiring immunosuppressive bio-fluids or organ adaptation cycles.

---

## 2. Mathematical Foundations of Biological Synthesis & Gene Mutation

BioGenesis replaces discrete item recipes with continuous mathematical modeling of genetics, implicit volumetric surfaces, and immunology.

```
                                  GENETIC SPLICING & EXPRESSION PIPELINE
                                  
  ┌──────────────────────┐       ┌──────────────────────┐       ┌──────────────────────┐
  │ Host Gene Vector g_H │       │ Graft Gene Vector g_G│       │ Mutagenic Plasmid p  │
  │   g_H ∈ [0, 1]^32    │       │   g_G ∈ [0, 1]^32    │       │  Δp_i , W_plasmid    │
  └──────────┬───────────┘       └──────────┬───────────┘       └──────────┬───────────┘
             │                              │                              │
             └──────────────┬───────────────┘                              │
                            │                                              │
                            ▼                                              │
             ┌──────────────────────────────┐                              │
             │ Hadamard Bio-Match Index M_H │                              │
             │  M_H = (1/N) ∑ (H_N · (g_H⊙g_G))                            │
             └──────────────┬───────────────┘                              │
                            │                                              │
                            ├──────────────────────────────────────────────┘
                            ▼
             ┌──────────────────────────────┐
             │ Phenotype Expression Vector  │
             │ P_i = P_min + (P_max - P_min)│
             │   · σ( α_i (g_i + Δp_i) )    │
             └──────────────┬───────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│ SDF Smooth-Min Blend (k)  │   │ Immune Rejection Risk (R) │
│ k(M_H) = k_0 · (M_H)^γ    │   │ R = σ( β(1 - M_H) - μ )   │
└───────────────────────────┘   └───────────────────────────┘
```

### 2.1 Continuous Chromosome Vector & Phenotype Mapping

The genome of any BioGenesis organism (host ship or grafted organ) is defined as a 32-dimensional normalized vector:

$$\mathbf{g} = \left[ g_1, g_2, \dots, g_{32} \right]^T \in [0, 1]^{32}$$

#### Phenotype Expression Formula
Each physical trait $P_i$ (e.g., chitin hardness, neural bandwidth, vascular flow rate, bioluminescent frequency) is mapped from $\mathbf{g}$ via a non-linear sigmoidal transfer function with epigenetic plasmid offsets $\mathbf{\Delta p}$:

$$P_i(\mathbf{g}, \mathbf{\Delta p}) = P_{i,\text{min}} + \left( P_{i,\text{max}} - P_{i,\text{min}} \right) \cdot \sigma \left( \alpha_i \cdot \left( g_i + \Delta p_i - \theta_i \right) \right)$$

Where:
- $P_{i,\text{min}}, P_{i,\text{max}}$ are the absolute biological bounds of trait $i$.
- $\sigma(x) = \frac{1}{1 + e^{-x}}$ is the standard logistic sigmoid function.
- $\alpha_i$ is the gene expression gain factor (steepness of phenotypic shift).
- $\theta_i$ is the genetic activation threshold.
- $\Delta p_i$ is the linear trait shift induced by socketed Mutagenic Plasmids.

#### Multi-Gene Epigenetic Epistasis Matrix
Complex organ systems depend on interactions between multiple genes (epistasis). We model epistasis via a weight matrix $\mathbf{W} \in \mathbb{R}^{32 \times 32}$:

$$\mathbf{g}_{\text{expressed}} = \sigma \left( \mathbf{W} \cdot \mathbf{g} + \mathbf{\Delta p} \right)$$

---

### 2.2 Hadamard Bio-Match Index ($M_H$)

When a graft organ with genome $\mathbf{g}_{\text{graft}}$ is spliced into a host ship with genome $\mathbf{g}_{\text{host}}$, the host's immune system evaluates tissue compatibility. To compute multi-locus compatibility efficiently, BioGenesis employs an orthogonal transformation based on the **Sylvester-Hadamard Matrix** $\mathbf{H}_N$.

#### Hadamard Matrix Definition
For $N = 32$ (padded to $2^k = 32$), the Hadamard matrix $\mathbf{H}_N$ is constructed recursively:

$$\mathbf{H}_1 = \begin{bmatrix} 1 \end{bmatrix}, \quad \mathbf{H}_{2^{k}} = \begin{bmatrix} \mathbf{H}_{2^{k-1}} & \mathbf{H}_{2^{k-1}} \\ \mathbf{H}_{2^{k-1}} & -\mathbf{H}_{2^{k-1}} \end{bmatrix}$$

#### Bio-Match Index Formula
Let $\mathbf{v}_{\text{diff}} \in \{-1, +1\}^{32}$ be the binarized genetic alignment vector between host and graft:

$$v_i = \begin{cases} +1 & \text{if } |g_{\text{host}, i} - g_{\text{graft}, i}| \le \epsilon_{\text{tol}} \\ -1 & \text{otherwise} \end{cases}$$

The Hadamard Bio-Match Index $M_H \in [0, 1]$ is computed as the normalized magnitude of the spectral projection:

$$M_H(\mathbf{g}_{\text{host}}, \mathbf{g}_{\text{graft}}) = \frac{1}{N^2} \left\| \mathbf{H}_N \cdot \mathbf{v}_{\text{diff}} \right\|_1$$

Where $\|\cdot\|_1$ is the $L_1$ norm. An exact match yields $M_H = 1.0$ (perfect tissue harmony), whereas completely incompatible genomes yield $M_H \to 0.0$.

#### Rejection Risk Rate ($R_{\text{rejection}}$)
The probability per second of acute tissue rejection, necrosis, or auto-immune flare-up is given by:

$$R_{\text{rejection}}(M_H, \mu_{\text{immuno}}) = \frac{1}{1 + e^{\lambda \cdot \left( M_H - (1.0 - \mu_{\text{immuno}}) \right)}}$$

Where:
- $\mu_{\text{immuno}} \in [0, 0.5]$ is the ship's current immunosuppression level (boosted by Coagulation Beds or Bio-Fluids).
- $\lambda \approx 12.0$ controls the steepness of the rejection curve.

---

### 2.3 SDF Smooth-Min Fillet Splicing Math (`organBlending.ts`)

In `organBlending.ts`, implicit surface blending between host hull SDF $d_{\text{hull}}(\mathbf{p})$ and grafted organ SDF $d_{\text{organ}}(\mathbf{p})$ uses Inigo Quilez's polynomial smooth-minimum operator:

$$d_{\text{smin}}(d_1, d_2, k) = \text{opSmoothUnion}(d_1, d_2, k)$$

#### Polynomial Smooth Minimum Definition
$$h = \max \left( k - |d_1 - d_2|, 0.0 \right) / k$$

$$d_{\text{smin}}(d_1, d_2, k) = \min(d_1, d_2) - \frac{k}{4} \cdot h^2$$

#### Dynamic Genetic Blend Radius $k(M_H)$
Rather than using a fixed blend radius, $k$ dynamically scales with the Hadamard Bio-Match Index $M_H$:

$$k(M_H) = k_0 \cdot \left( M_H \right)^{\gamma_{\text{blend}}}$$

Where:
- $k_0$ is the base blend radius (typically $0.35\text{m} - 0.85\text{m}$ depending on organ scale).
- $\gamma_{\text{blend}} \approx 1.5$.
- **High Compatibility ($M_H \approx 1.0$)**: $k \approx k_0$, producing a wide, smooth, organic fillet that seamlessly merges host and graft tissues.
- **Low Compatibility ($M_H \to 0.0$)**: $k \to 0.01$, producing a sharp, scarred, inflamed seam with visible tissue friction and necrosis artifacts.

---

### 2.4 Metabolic Energy & Energy-Budget Trade-Offs

Grafting organs increases metabolic demand. The ship's net energy balance $E_{\text{net}}$ dictates operational performance:

$$E_{\text{net}} = E_{\text{generation}}(\mathbf{g}) - \sum_{j \in \text{Organs}} \left( E_{\text{base},j} \cdot \left( 1 + \gamma_j \cdot g_{\text{expressed}, j}^2 \right) \cdot \prod_{m \in \text{Plasmids}_j} \mu_{m} \right) - E_{\text{immuno}}(R_{\text{rejection}})$$

Where:
- $E_{\text{generation}}$ is derived from the Hemolymph Atrium & Radiotrophic Carapace absorption.
- $E_{\text{base},j}$ is the baseline power demand of organ $j$.
- $\mu_m$ is the energy multiplier of socketed Mutagenic Plasmid $m$.
- $E_{\text{immuno}}$ is the metabolic cost of suppressing auto-immune rejection.

If $E_{\text{net}} < 0$, the ship enters **Metabolic Strain**, triggering organ efficiency degradation following the Yerkes-Dodson curve (see `NEURAL_COMPUTE_ARCHITECTURE.md`).

---

## 3. BioGenesis Organic Crafting & Splicing Blueprint

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                           BIOGENESIS CRAFTING ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   ┌────────────────────────┐      ┌────────────────────────┐      ┌─────────────────┐   │
│   │ 3D Surgical Canvas     │      │ Organ Blending Manager │      │ Gene & Plasmid  │   │
│   │ (Canvas3D.tsx)         │◄────►│ (organBlending.ts)     │◄────►│ Drawer UI       │   │
│   │ - TransformControls    │      │ - Hull SDF Eval        │      │ - 32-Gene Dials │   │
│   │ - Drag & Snap Sockets  │      │ - Dynamic k(M_H)       │      │ - Hadamard Meter│   │
│   │ - Emissive Heat Map    │      │ - Marching Cubes Fillet│      │ - Plasmid Slots │   │
│   └───────────┬────────────┘      └───────────┬────────────┘      └────────┬────────┘   │
│               │                               │                            │            │
│               └───────────────────────┬───────┴────────────────────────────┘            │
│                                       ▼                                                 │
│                        ┌──────────────────────────────┐                                 │
│                        │ Bio-Splicing Engine Core     │                                 │
│                        │ (bioSplicingEngine.ts)       │                                 │
│                        │ - Hadamard Matrix H_32       │                                 │
│                        │ - Sigmoid Expression Vector  │                                 │
│                        │ - Rejection Risk Simulation  │                                 │
│                        │ - Energy Balance Solver      │                                 │
│                        └──────────────────────────────┘                                 │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Real-Time SDF Organ Smooth-Min Splicing (`organBlending.ts`)
The organ splicing pipeline seamlessly integrates with `organBlending.ts` through the following step-by-step process:

1. **Spatial Attachment**: When a user drags a candidate organ near an anatomical section (Cranial, Neck, Thoracic, Caudal, Tail Tip), the target anchor node is identified on the spine.
2. **Hadamard Evaluation**: The system calculates $M_H(\mathbf{g}_{\text{host}}, \mathbf{g}_{\text{graft}})$.
3. **Dynamic SDF Bridge Generation**:
   - `buildHullSDF()` calculates the swept-sphere hull distance.
   - `buildCandidateOrganSDF()` calculates the graft distance field.
   - `opSmoothUnion(sdfHull, sdfOrgan, k(M_H))` blends the two scalar fields.
   - `sdfToMesh()` runs Marching Cubes over the local bounding box of the splice zone.
4. **Mesh Registration**: The resulting fillet mesh is assigned `userData.isBlendBridge = true` and attached to `shipGroup`.
5. **Interactive Regeneration**: When an organ is repositioned via `TransformControls`, `BlendBridgeManager.update()` regenerates the fillet mesh in real time.

---

### 3.2 Continuous Chromosome Parameter Engine

The 32 genes in vector $\mathbf{g}$ map directly to ship morphology and system performance:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                 CHROMOSOME VECTOR MAP (g)                               │
├──────┬─────────────────────────────┬───────────────────┬────────────────────────────────┤
│ Index│ Gene Name                   │ Phenotype Target  │ Physical / System Effect       │
├──────┼─────────────────────────────┼───────────────────┼────────────────────────────────┤
│ g_01 │ Chitin Carapace Density     │ Armor / Mass      │ Carapace thickness, Mass +25%  │
│ g_02 │ Spinal Flexibility          │ Hydrodynamics     │ Wobble frequency, Turn rate    │
│ g_03 │ Vascular Wall Thickness     │ Pressure Max      │ Max hemolymph stroke pressure  │
│ g_04 │ Neural Axon Density         │ Bandwidth         │ Bits/sec compute generation    │
│ g_05 │ Bioluminescent Wavelength   │ Emitter Color     │ Hue shift (400nm -> 700nm)     │
│ g_06 │ Radiotrophic Chloroplasts   │ Energy Generation │ Solar/Radiation absorption     │
│ g_07 │ Myofibril Elasticity        │ Propulsion Thrust │ Bio-thruster impulse (N)       │
│ g_08 │ Immune Tolerance Threshold  │ Immuno-Capacity   │ Baseline rejection resistance  │
│ g_09 │ Spore Pod Incubation Rate   │ Weapon Cooldown   │ Bio-plasma firing velocity     │
│ g_10 │ Habitat Chamber Thermal Reg │ Life Support      │ Human crew comfort capacity    │
│ ...  │ ... (g_11 to g_32)          │ ...               │ ...                            │
└──────┴─────────────────────────────┴───────────────────┴────────────────────────────────┘
```

#### Mutagenic Vector Application
Players can modify $\mathbf{g}$ through three directed mechanics:
- **CRISPR Bio-Splicing Vector**: Targeted single-gene modification (+0.05 to +0.20 shift in specific $g_i$).
- **Radiotrophic Mutation Trough**: Immersion in radioactive nebulae induces random Gaussian drift across all genes: $\mathbf{g} \leftarrow \text{clamp}(\mathbf{g} + \mathcal{N}(0, \sigma^2), 0, 1)$.
- **Plasmid Inoculation**: Instant epigenetic offset via socketed mutagenic plasmids.

---

### 3.3 Mutagenic Plasmid Unlock System

Mutagenic Plasmids act as socketable modifiers for organ nodes. They are divided into three distinct functional tiers:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                MUTAGENIC PLASMID TAXONOMY                               │
├─────────────┬──────────────────────────┬────────────────────────────────────────────────┤
│ Tier        │ Category                 │ Physiological Mechanics & Trade-Offs           │
├─────────────┼──────────────────────────┼────────────────────────────────────────────────┤
│ Tier 1      │ Catalyst Plasmids        │ Linear performance multipliers (+30% throughput,│
│             │ (Amplifiers)             │ +15% energy cost).                             │
├─────────────┼──────────────────────────┼────────────────────────────────────────────────┤
│ Tier 2      │ Morphing Plasmids        │ Shape & functional shift (e.g., Converts Eye   │
│             │ (Morphology Shifts)      │ Pod to Bioluminescent Radar Beacon).           │
├─────────────┼──────────────────────────┼────────────────────────────────────────────────┤
│ Tier 3      │ Chimera Plasmids         │ Cross-pipeline conversion (e.g., Routes Plasma │
│             │ (System Integration)     │ Gland fluid into Vascular Arteries for heat).   │
└─────────────┴──────────────────────────┴────────────────────────────────────────────────┘
```

#### Plasmid Socket Capacity
Organ nodes feature 1 to 3 sockets based on Encephalization Quotient (EQ) and organ mass:

$$N_{\text{sockets}} = \min \left( 3, \left\lfloor 1 + \log_2 \left( \frac{\text{Mass}_{\text{organ}}}{\text{Mass}_{\text{base}}} \right) \right\rfloor \right)$$

---

### 3.4 Hadamard Bio-Match Compatibility & Immune System Dynamics

When $M_H < 0.70$, the host organism detects foreign surface antigens, initiating an immune response:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                               IMMUNE REJECTION TIMELINE                                 │
├───────────────────┬───────────────────────────────────┬─────────────────────────────────┤
│ Stage             │ Compatibility Threshold           │ Visual & Gameplay Symptoms      │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ 1. Harmonious     │ M_H >= 0.85                       │ Wide SDF fillet, vibrant glow,  │
│    Symbiosis      │                                   │ 100% organ efficiency.          │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ 2. Immune Strain  │ 0.65 <= M_H < 0.85                │ Narrow SDF fillet, mild redness,│
│    (Inflammation) │                                   │ -15% efficiency, +10% energy cost│
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ 3. Acute Tissue   │ 0.45 <= M_H < 0.65                │ Inflamed green/purple seam,     │
│    Rejection      │                                   │ hemolymph leakage, -40% eff.    │
├───────────────────┼───────────────────────────────────┼─────────────────────────────────┤
│ 4. Necrotic Rot   │ M_H < 0.45                        │ Tissue blackening, toxic slime, │
│    & Auto-Immune  │                                   │ Organ shutdown, structural damage│
└───────────────────┴───────────────────────────────────┴─────────────────────────────────┘
```

#### Mitigating Rejection
To maintain low-compatibility organ grafts ($M_H < 0.65$), players must:
- Install **Coagulation Beds** in the Armor Defense pipeline to flood the splice zone with immunosuppressive lymph.
- Administer **Immunosuppressive Bio-Fluids** synthesized via the Life Support Moss Bed.
- Perform **Epigenetic Adaptation Cycles** over time to force host gene alignment toward graft parameters.

---

## 4. Tactical UI/UX & Visceral Somatic Splicing Workflow

BioGenesis eschews flat inventory screens in favor of a **3D Visceral Surgical Interface** layered directly over the living ship model.

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                             BIOGENESIS SURGICAL INTERFACE (UI/UX)                       │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  [ Header: SHIP GENOME EDITION ]                     [ Telemetry: IMMUNE & METABOLIC ]  │
│  ───────────────────────────────                     ─────────────────────────────────  │
│  Genome Seed: #849204-DELTA                          Net Energy: +142.4 MW            │
│  Hadamard Match: 0.91 [HARMONIOUS]                   Immuno Budget: 88% [STABLE]      │
│                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                   │  │
│  │                                  ( ( HULL 3D ) )                                  │  │
│  │                                                                                   │  │
│  │                       ┌─────────────┐                                             │  │
│  │                       │ GRAFT ORGAN │ ══ Drag ══► [ THORACIC SOCKET #3 ]          │  │
│  │                       │ DISRUPTOR   │             ( Pulsing Fillet Preview )      │  │
│  │                       └─────────────┘                                             │  │
│  │                                                                                   │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │ CHROMOSOME DIALS (g_1 .. g_32)    PLASMID SOCKETS           ACTION FOOTER         │  │
│  │ ├─ Chitin:    [====|====] 0.72    [Socket 1: Hyper-Vasc]    [ CONFIRM GRAFT ]     │  │
│  │ ├─ Vascular:  [======|==] 0.88    [Socket 2: Empty     ]    [ INJECT BIO-FLUID]   │  │
│  │ └─ Neural:    [===|=====] 0.45    [Socket 3: Locked    ]    [ PURGE GRAFT     ]   │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Visceral Somatic Feedback Elements
- **Visual Feedback**:
  - **Live SDF Filleting**: As the candidate organ approaches a socket, a transparent holographic volumetric fillet expands, showing the exact smooth-min junction.
  - **Vascular Auto-Wiring**: Highlighting an organ illuminates target arterial and venous pathways in real time, projecting animated hemolymph flow lines.
  - **Inflammation Heatmap**: Incompatible grafts ($M_H < 0.65$) display glowing red/purple inflammation rings around the fillet margin.
- **Audio Feedback**:
  - Wet, organic suction sounds upon spatial socket snapping.
  - Deep, rhythmic heartbeats accelerating during tissue rejection.
  - High-pitched bio-electric arc hums when socketing chimera plasmids.

---

### 4.2 UI/UX System Flowcharts

#### Flowchart 1: Organ Harvesting, Grafting & Splicing Workflow
```
 ┌────────────────────────┐
 │ Void-Fauna Defeated    │
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │ Harvest Organ Specimen │
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │ Open Surgical Canvas   │
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐      Is Socket Valid?
 │ Drag Organ to Hull     ├─────────────────────────────┐
 └───────────┬────────────┘                             │ No
             │ Yes                                      ▼
             ▼                             ┌────────────────────────┐
 ┌────────────────────────┐                │ Snap Back to Inventory │
 │ Evaluate Hadamard M_H  │                └────────────────────────┘
 └───────────┬────────────┘
             │
             ├───────────────────────────┬───────────────────────────┐
             ▼                           ▼                           ▼
 ┌────────────────────────┐  ┌────────────────────────┐  ┌────────────────────────┐
 │ M_H >= 0.85            │  │ 0.65 <= M_H < 0.85     │  │ M_H < 0.65             │
 │ Wide Fillet (k = k_0)  │  │ Medium Fillet          │  │ Narrow Fillet (Scarred)│
 │ Harmonious Fusion      │  │ Inflammatory Warning   │  │ Rejection Risk Alert   │
 └───────────┬────────────┘  └───────────┬────────────┘  └───────────┬────────────┘
             │                           │                           │
             └───────────────────────────┼───────────────────────────┘
                                         ▼
                             ┌────────────────────────┐
                             │ Generate SDF Bridge    │
                             │ (`organBlending.ts`)   │
                             └───────────┬────────────┘
                                         │
                                         ▼
                             ┌────────────────────────┐
                             │ Confirm Graft & Connect│
                             │ Vascular Networks      │
                             └────────────────────────┘
```

#### Flowchart 2: Genetic Synthesis & Plasmid Editing Engine Pipeline
```
 ┌────────────────────────┐
 │ Select Organ Node      │
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │ Inspect Plasmid Slots  │
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │ Drag Mutagenic Plasmid │
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │ Recalculate Expression │
 │ g_exp = σ(W·g + Δp)    │
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │ Update Energy Budget   │
 │ E_net = E_gen - ∑E_dem │
 └───────────┬────────────┘
             │
             ├──────────────────────────────────────────┐
             ▼                                          ▼
 ┌────────────────────────┐                ┌────────────────────────┐
 │ Net Energy >= 0        │                │ Net Energy < 0         │
 │ Optimal Operation      │                │ Trigger Metabolic      │
 │ (Yerkes-Dodson Peak)   │                │ Strain Efficiency Loss │
 └────────────────────────┘                └────────────────────────┘
```

---

## 5. Technical Implementation Blueprint & Code Schemas

### 5.1 Data Model Extensions (`src/types.ts`)

```typescript
// ── Biological Chromosome & Splicing Data Models ──

/** 32-Dimensional Normalized Chromosome Vector (g ∈ [0, 1]^32) */
export type ChromosomeVector = number[];

/** Mutagenic Plasmid Category */
export type PlasmidCategory = 'CATALYST' | 'MORPHING' | 'CHIMERA';

/** Mutagenic Plasmid Definition */
export interface MutagenicPlasmid {
  id: string;
  name: string;
  category: PlasmidCategory;
  tier: 1 | 2 | 3;
  description: string;
  traitOffsets: Partial<Record<string, number>>; // Δp_i offsets
  energyMultiplier: number;                       // Metabolic cost scale
  immunoCost: number;                            // Immuno-suppression cost
  iconUrl?: string;
}

/** Grafted Organ Node Data Model */
export interface GraftedOrganNode {
  id: string;
  organTypeId: string;
  name: string;
  position: [number, number, number];
  orientation: [number, number, number, number]; // Quaternion
  genome: ChromosomeVector;
  socketedPlasmids: (MutagenicPlasmid | null)[];
  hadamardMatchScore: number;                    // M_H vs Host
  rejectionRisk: number;                         // R_rejection [0, 1]
  isGrafted: boolean;
  blendRadiusOverride?: number;
}

/** Hadamard Compatibility Evaluation Result */
export interface HadamardMatchResult {
  hadamardIndex: number;          // M_H ∈ [0, 1]
  rejectionRiskRate: number;      // R_rejection per sec
  suggestedBlendRadius: number;   // k(M_H)
  immuneStatus: 'HARMONIOUS' | 'INFLAMED' | 'ACUTE_REJECTION' | 'NECROTIC_ROT';
}

/** Biological Synthesis / Crafting Recipe */
export interface CraftingRecipe {
  id: string;
  outputPlasmidId?: string;
  outputOrganId?: string;
  name: string;
  requiredBiomass: number;
  requiredEnzymes: Record<string, number>;
  incubatorTierRequired: number;
  catalystRequired?: string;
  synthesisTimeSeconds: number;
}
```

---

### 5.2 Core Splicing & Hadamard Engine (`src/utils/bioSplicingEngine.ts`)

```typescript
/**
 * Bio-Splicing & Hadamard Compatibility Engine
 *
 * Implements Hadamard Bio-Match Index computation, continuous chromosome vector
 * mutation, sigmoidal phenotype expression, and dynamic SDF blend radius calculation.
 */

import { ChromosomeVector, HadamardMatchResult, MutagenicPlasmid } from '../types';

const CHROMOSOME_DIM = 32;

/**
 * Generates a 32x32 Sylvester-Hadamard Matrix recursively.
 */.
export function generateHadamardMatrix(n: number = CHROMOSOME_DIM): number[][] {
  if (n === 1) return [[1]];
  const half = generateHadamardMatrix(n / 2);
  const H: number[][] = Array.from({ length: n }, () => new Array(n).fill(0));

  for (let i = 0; i < n / 2; i++) {
    for (let j = 0; j < n / 2; j++) {
      const val = half[i][j];
      H[i][j] = val;
      H[i][j + n / 2] = val;
      H[i + n / 2][j] = val;
      H[i + n / 2][j + n / 2] = -val;
    }
  }
  return H;
}

const HADAMARD_32 = generateHadamardMatrix(32);

/**
 * Calculates the Hadamard Bio-Match Index (M_H) between Host and Graft genomes.
 */
export function calculateHadamardBioMatch(
  hostGenome: ChromosomeVector,
  graftGenome: ChromosomeVector,
  tolerance: number = 0.15,
  immunoSuppression: number = 0.0,
  baseBlendRadius: number = 0.5
): HadamardMatchResult {
  // 1. Build binarized alignment vector v_diff ∈ {-1, +1}^32
  const vDiff = new Array(CHROMOSOME_DIM).fill(0);
  for (let i = 0; i < CHROMOSOME_DIM; i++) {
    const diff = Math.abs((hostGenome[i] || 0) - (graftGenome[i] || 0));
    vDiff[i] = diff <= tolerance ? 1 : -1;
  }

  // 2. Compute Spectral Projection: H_32 · v_diff
  const projection = new Array(CHROMOSOME_DIM).fill(0);
  let l1Norm = 0;
  for (let i = 0; i < CHROMOSOME_DIM; i++) {
    let sum = 0;
    for (let j = 0; j < CHROMOSOME_DIM; j++) {
      sum += HADAMARD_32[i][j] * vDiff[j];
    }
    projection[i] = sum;
    l1Norm += Math.abs(sum);
  }

  // 3. Normalize Hadamard Match Index M_H ∈ [0, 1]
  const hadamardIndex = Math.min(1.0, Math.max(0.0, l1Norm / (CHROMOSOME_DIM * CHROMOSOME_DIM)));

  // 4. Compute Rejection Risk Rate R_rejection
  const lambda = 12.0;
  const exponent = -lambda * (hadamardIndex - (1.0 - immunoSuppression));
  const rejectionRiskRate = 1.0 / (1.0 + Math.exp(exponent));

  // 5. Dynamic Blend Radius k(M_H) = k_0 · (M_H)^1.5
  const suggestedBlendRadius = Math.max(0.02, baseBlendRadius * Math.pow(hadamardIndex, 1.5));

  // 6. Immune Status Classification
  let immuneStatus: HadamardMatchResult['immuneStatus'] = 'HARMONIOUS';
  if (hadamardIndex < 0.45) immuneStatus = 'NECROTIC_ROT';
  else if (hadamardIndex < 0.65) immuneStatus = 'ACUTE_REJECTION';
  else if (hadamardIndex < 0.85) immuneStatus = 'INFLAMED';

  return {
    hadamardIndex,
    rejectionRiskRate,
    suggestedBlendRadius,
    immuneStatus,
  };
}

/**
 * Sigmoidal Phenotype Expression Function
 */
export function expressPhenotypeTrait(
  g_i: number,
  deltaP: number = 0,
  minVal: number,
  maxVal: number,
  gain: number = 5.0,
  threshold: number = 0.5
): number {
  const x = gain * (g_i + deltaP - threshold);
  const sig = 1.0 / (1.0 + Math.exp(-x));
  return minVal + (maxVal - minVal) * sig;
}

/**
 * Applies socketed mutagenic plasmids to an organ's base chromosome vector.
 */
export function applyPlasmidModifiers(
  baseGenome: ChromosomeVector,
  plasmids: (MutagenicPlasmid | null)[]
): ChromosomeVector {
  const modified = [...baseGenome];
  for (const plasmid of plasmids) {
    if (!plasmid) continue;
    for (const [traitIndexStr, offset] of Object.entries(plasmid.traitOffsets)) {
      const idx = parseInt(traitIndexStr, 10);
      if (idx >= 0 && idx < CHROMOSOME_DIM) {
        modified[idx] = Math.min(1.0, Math.max(0.0, modified[idx] + (offset || 0)));
      }
    }
  }
  return modified;
}
```

---

### 5.3 Wiring Splicing Engine into `organBlending.ts` & `Canvas3D.tsx`

To integrate the Splicing Engine with BioGenesis's existing 3D rendering pipeline:

```typescript
// Integration Snippet for organBlending.ts (Dynamic Blend Evaluation)

import { calculateHadamardBioMatch } from './bioSplicingEngine';

export function evaluateGraftBlend(
  hostGenome: number[],
  graftNode: GraftedOrganNode,
  baseRadius: number = 0.45
): { kBlend: number; matchInfo: HadamardMatchResult } {
  const matchInfo = calculateHadamardBioMatch(
    hostGenome,
    graftNode.genome,
    0.15,
    0.0, // Immuno-suppression level
    baseRadius
  );

  return {
    kBlend: matchInfo.suggestedBlendRadius,
    matchInfo,
  };
}
```

---

## 6. Synthesis & Next-Steps Roadmap

| Phase | Milestone | Deliverable | Target System |
|---|---|---|---|
| **Phase 1** | Hadamard & Genome Core | Implement `bioSplicingEngine.ts` and unit tests. | Splicing Logic Core |
| **Phase 2** | Dynamic SDF Filleting | Wire dynamic $k(M_H)$ into `organBlending.ts` & `BlendBridgeManager`. | Volumetric Rendering |
| **Phase 3** | UI Surgical Drawer | Create 3D drag-and-drop surgical UI & plasmid socket HUD. | React 19 Frontend |
| **Phase 4** | Rejection & Energy Loops | Connect immune rejection cascades & Yerkes-Dodson compute curves. | System Simulation |

This research spec provides the complete mathematical, architectural, and visual blueprint to elevate BioGenesis's crafting and synthesis from abstract menus into a best-in-class, visceral biological experience.
