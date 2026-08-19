# Neural Compute Architecture — Research & Implementation Specification

> **Status**: Approved design — ready for implementation
> **Date**: 2026-08-12
> **Author**: Ciel (Lord of Wisdom) + Master
> **Sources**: Jerison 1973, Aiello & Wheeler 1995, Herculano-Houzel 2011,
>   Niven & Burrows 2008, Chklovskii 2004, Yerkes & Dodson 1908,
>   Perge et al. 2009, Murray 1926, Sterling & Laughlin 2015

---

## 1. Brain Scaling (Haller's Rule + Jerison Allometry)

### 1.1 Biological Foundation

**Jerison's Allometric Power Law**:
```
E = k × P^β
```
- E = brain mass
- P = body mass (proxy: ship volume)
- k = allometric coefficient (varies by clade)
- β = scaling exponent (~2/3 Jerison, ~3/4 Martin)

**Encephalization Quotient (EQ)**:
```
EQ = actual_brain_mass / expected_brain_mass = E / (k × P^β)
```
For mammals: `EQ = brain_mass / (0.12 × body_mass^0.67)`

**Haller's Rule**: Smaller animals have proportionally LARGER brains.
This holds across all vertebrates AND invertebrates. At the extreme,
the smallest insects (Megaphragma wasp) have brains = 8-16% of body mass.

**Metabolic Cost (Expensive Tissue Hypothesis)**:
- Brain tissue uses 22× more energy per unit mass than muscle
- Human brain = 2% body mass but 20% of total energy budget
- Energy budget per neuron is roughly constant across species
- Total brain energy ∝ neuron count (linear), not brain volume

### 1.2 BioGenesis Implementation

**EQ Scaling (Haller's Rule)**:
```
referenceVolume = 6.0 × 2.4 × 2.4 × π ≈ 108.6 m³  (smallest ship)
shipVolume = approximate hull volume (length × thoraxWidth² × π × fillFactor)

EQ = clamp(7 × (referenceVolume / shipVolume)^(1/3), 3, 7)
```

| Ship length | Approx volume | EQ | Brain % energy | Character |
|---|---|---|---|---|
| 6m | ~109 m³ | 7.0 | ~20% | Strained, NEEDS humans |
| 10m | ~302 m³ | 5.1 | ~15% | Balanced |
| 14m (default) | ~586 m³ | 4.1 | ~12% | Capable, values direction |
| 20m | ~1200 m³ | 3.3 | ~9% | Autonomous |
| 30m+ | ~2700 m³ | 3.0 (clamped) | ~8% | Wise, humans = strategy |

**Brain Mass**:
```
brainMass = 0.12 × shipVolume^0.67 × EQ
```

**Brain Radius** (assuming spherical brain, neural density ~86B neurons/m³):
```
brainRadius = cbrt(brainMass / (4/3 × π × neuralDensity)) × visualScale
```
Visual scale factor ensures the brain is visible (real brain would be tiny
relative to a 14m ship). We use a minimum visible radius of 0.3m.

**Brain Compute Generation**:
```
neuronCount = brainMass × neuronDensity           (neurons)
brainCompute = neuronCount × bitsPerNeuron         (bits/s)
  where bitsPerNeuron ≈ 5 bits/s (conservative, from retinal ganglion data)
```

**Brain Energy Cost**:
```
brainEnergyCost = brainMass × 22 × metabolicConstant
  → expressed as percentage of total ship energy budget
```

### 1.3 Mutualism Rationale

Research confirms: mutualism does NOT require equal intelligence.
- Dogs (EQ 1.2) cooperate with humans (EQ 7) via complementary capabilities
- The cooperation works because each species provides what the other cannot
- Dogs: sensory acuity, speed, emotional reading
- Humans: goal-setting, planning, ethical judgment, tool use

For BioGenesis:
- **Small ships (EQ 7)**: Metabolically strained, brain consumes 20% of energy.
  Humans are ESSENTIAL — they provide goal-setting and external perspective
  that the ship cannot afford to compute itself.
- **Large ships (EQ 3)**: Brain is cheap (8% of energy). Ship is autonomous
  and wise. Humans are valued for ethical judgment, strategic creativity,
  and neural-link piloting — things computation alone cannot provide.

The pilot-ship bond is strongest when the ship is small and strained,
creating gameplay tension: small ships are vulnerable but the bond is deepest.

---

## 2. Compute Pipeline (Generation → Transfer → Storage → Demand)

### 2.1 Architecture Overview

```
BRAIN (primary generator)
  │ generates computeCapacity (bits/s)
  │ ∝ brainVolume × neuronDensity × bitsPerNeuron
  │
  ▼
SPINAL AXON CORD (main trunk, dorsal)
  │ bandwidth = cordCrossSection × axonDensity × bitsPerAxon
  │ already exists — no additional wire cost for dorsal chain
  │
  ├──▶ DORSAL GANGLIA (per body segment)
  │      │ ganglionCompute = ganglionVolume × neuronDensity × bitsPerNeuron (small)
  │      │ nerveBandwidth = nerveCrossSection × axonDensity × bitsPerAxon
  │      │ nerveDelay = nerveLength / conductionVelocity (120 m/s)
  │      │ totalSupply = min(nerveBandwidth, available) + ganglionCompute
  │      │ stores excess as "reserve"
  │      │
  │      ▼
  │    ORGANS (demand)
  │      each organ type has computeRequirement (bits/s)
  │      supplyRatio = totalSupply / organDemand
  │
  ├──▶ VENTRAL GANGLIA (optional, separate toggle)
  │      │ same structure as dorsal, second nerve cord
  │      │ extra wire cost (new conduit along v=0.75)
  │      │
  │      ▼
  │    ORGANS (demand, ventral-side)
  │
  └──▶ CRANIAL GANGLIA (near brain, highest processing)
         │ shortest nerves, highest bandwidth
         │ process sensory data from eyes, spiracles
```

### 2.2 Nerve Physical Properties

**Bandwidth (Shannon channel capacity)**:
```
nerveBandwidth = nerveCrossSection × axonDensity × bitsPerAxon
  where:
    axonDensity ≈ 10⁶ axons/mm² (biological estimate)
    bitsPerAxon ≈ 5 bits/s (conservative, from Perge et al.)
    nerveCrossSection = π × nerveRadius²
```

**Conduction Delay**:
```
nerveDelay = nerveLength / conductionVelocity
  where conductionVelocity = 120 m/s (myelinated equivalent)
```

**Wire Cost (Chklovskii model)**:
```
wireCost = nerveLength² × nerveDiameter²
  (volume × delay trade-off)
```

**Murray's Law for Branching**:
```
d₀² = d₁² + d₂²
  (parent diameter² = sum of daughter diameters²)
```

**Branching Angle**: ~83° (biological optimum, NOT Steiner 120°)

**Maximum Branch Length**:
```
maxBranchLength = shipLength × 0.15
  (15% of body length — derived from 120 m/s × 50ms reflex = 6m
   on a 14m ship; scales proportionally)
```

### 2.3 Ganglion Compute (Small Self-Generation)

Ganglia are NOT passive relay nodes — they have their own neurons and
generate a small amount of compute locally, following the same rules
as the brain:

```
ganglionCompute = ganglionVolume × neuronDensity × bitsPerNeuron
```

This is typically 5-15% of what the brain generates per equivalent volume,
because ganglia are simpler structures (fewer neuron types, less connectivity).
We model this with a `ganglionEfficiencyFactor = 0.1` (10% of brain's
per-volume output).

**Ganglion Size by Region** (biological: thoracic > abdominal):
```
ganglionSize = baseGanglionSize × regionDemandMultiplier
  where regionDemandMultiplier scales with local organ compute demand
```

### 2.4 Organ Compute Demand

Each organ type has a compute requirement (bits/s) based on its function:

| Organ type | Compute demand (relative) | Rationale |
|---|---|---|
| eye (ocular pod) | 2.0 | High — visual processing, targeting |
| spiracle | 0.5 | Low — rhythmic autonomic control |
| rib | 0.3 | Low — proprioceptive feedback |
| spore | 1.5 | Medium-high — weapon timing, targeting |
| tentacle | 1.8 | High — FABRIK IK, motor control |
| habitat | 0.8 | Medium — life support monitoring |
| pectoralFin | 1.2 | Medium — flight control |
| caudalFluke | 1.0 | Medium — propulsion timing |
| landingLimb | 1.0 | Medium — locomotion |
| dorsalSail | 0.6 | Low-medium — stability adjustment |
| heart | 1.0 | Medium — circulatory regulation |
| plasmaGland | 1.5 | Medium-high — energy regulation |

These are relative units; absolute values scale with ship size.

---

## 3. Efficiency Curve (Yerkes-Dodson Inverted-U)

### 3.1 Biological Foundation

The Yerkes-Dodson law (1908) is an empirical relationship between arousal
and performance: performance increases with arousal up to an optimal point,
then decreases. This is an inverted U-shape.

Neurobiological basis (PNAS 2024): Two types of interneurons modulated by
an arousal signal produce two dynamical regimes — under-arousal (insufficient
signal) and over-arousal (excitotoxicity, glutamate accumulation).

Cholinergic overstimulation attenuates rule selectivity in prefrontal cortex
(JNeurosci 2018) — excessive neuromodulation IMPAIRS cognitive representations.

### 3.2 BioGenesis Implementation

```
supplyRatio = totalSupply / organDemand

Default state: ganglion supplies exactly 100% of demand
Excess capacity → stored as "reserve" (visible in telemetry)

efficiency(supplyRatio):
  r < 0.25   → 0%   (organ shutdown — non-functional)
  0.25 ≤ r < 0.50 → linear 20% → 50%   (heavy loss)
  0.50 ≤ r < 1.00 → linear 50% → 100%  (normal ramp)
  r = 1.00   → 100%  (normal, default state)
  1.00 < r ≤ 1.20 → linear 100% → 120% (enhanced — overclocked)
  r > 1.20   → declining from 120% → 80% → 50% (overstimulated)
```

### 3.3 Overclocking Mechanic

**By default**: Ganglion meets demand exactly (100%). Excess is stored as reserve.

**Overclocking to 100-120%** is ONLY triggered by:
1. **Captain's command** via neural-link — ganglion uses its natural excess
   (if any) to overclock assigned organs. Drains reserve.
2. **Consumable items** — directly inject compute, bypassing ganglion reserve.

**When reserve is empty**: overclocking stops, organ returns to 100%.

**Beyond 120%** (via stacked items): overstimulation → efficiency drops
(excitotoxicity analog). The organ takes damage over time if sustained.

### 3.4 Efficiency Function (Implementation)

```typescript
function organEfficiency(supplyRatio: number): number {
  if (supplyRatio < 0.25) return 0;           // shutdown
  if (supplyRatio < 0.50) return 0.20 + 0.60 * (supplyRatio - 0.25) / 0.25; // 20-50%
  if (supplyRatio < 1.00) return 0.50 + 0.50 * (supplyRatio - 0.50) / 0.50; // 50-100%
  if (supplyRatio <= 1.20) return 1.00 + 1.00 * (supplyRatio - 1.00) / 0.20; // 100-120%
  // Overstimulation: decline from 120% at r=1.2 to 50% at r=2.0
  const over = (supplyRatio - 1.20) / 0.80;
  return Math.max(0.50, 1.20 - 0.70 * over);
}
```

---

## 4. Ganglion Distribution

### 4.1 Segmental Chain Model

Based on insect ventral nerve cord (one ganglion pair per body segment)
and cephalopod distributed nervous system (ganglia along each arm).

**Dorsal chain** (free, default):
- Runs along existing Spinal Axon Cord (no additional trunk wire)
- One ganglion per anatomical section, distributed across full spine
- Ganglia sprout from the cord like vertebrae

**Ventral chain** (separate toggle, optional):
- Second nerve cord along ventral midline (v=0.75)
- Extra conduit with its own wire cost
- Independent visibility toggle (`showSystemNeuralVentral`)
- Only relevant for bilateral symmetry (insect model)

### 4.2 Distribution by Anatomical Section

Ganglia are distributed along the FULL spine, not clustered in the head:

| Section | U range | % of ganglia | Role | Bio analog |
|---|---|---|---|---|
| Cranial | 0.02-0.15 | ~20% | Ocular processing, sensory integration | Cranial ganglia |
| Neck | 0.15-0.30 | ~15% | Spinal cord relay, neuro-link bridge | Cervical ganglia |
| Thoracic | 0.30-0.65 | ~35% | Heart, spiracle, habitat, rib regulation | Thoracic/sympathetic |
| Caudal | 0.65-0.85 | ~20% | Spore, tentacle control | Lumbar/sacral |
| Tail Tip | 0.85-1.00 | ~10% | Thruster, fluke motor control | Caudal ganglia |

**Ganglion count formula**:
```
totalGanglia = neuralNodes (player-controlled, default 12)
sectionGanglia = round(totalGanglia × sectionFraction)
  where sectionFraction = sectionOrganDemand / totalOrganDemand
```

This means ganglia scale with organ density per section — the thoracic
section (which has the most organs) gets the most ganglia.

### 4.3 Ganglion Size Variation

```
ganglionSize = baseSize × (1 + localOrganDemand × 0.5)
  where baseSize = 0.28 + rng() × 0.20 (existing range)
  localOrganDemand = sum of compute demands of organs in this section

Cranial ganglia: largest (near brain, high processing)
Thoracic ganglia: large (many organs to regulate)
Caudal ganglia: medium (weapon/appendage control)
Tail ganglia: smallest (simple motor regulation)
```

### 4.4 Nerve Branching Visualization

Each ganglion connects to its nearest target organ via a visible nerve branch:

```
For each ganglion:
  Find nearest organs within maxBranchLength (15% × shipLength)
  For each assigned organ:
    Create a CatmullRomCurve3 from ganglion.pos to organ.pos
    Slight curve (organic, not straight line)
    TubeGeometry with radius following Murray's law:
      nerveRadius = baseNerveRadius × sqrt(organDemand / maxDemand)
    Material: mats.neuralGlow (bioluminescent, pulsing)
    Visibility: showSystemNeural (dorsal) or showSystemNeuralVentral (ventral)
```

---

## 5. Metabolic Cost Model

### 5.1 Total Neural Cost

```
totalNeuralCost = brainEnergyCost
  + Σ(ganglionEnergyCost)
  + Σ(nerveWireCost)
  + Σ(ventralChainCost)  [if enabled]

brainEnergyCost = brainMass × 22 × metabolicConstant
ganglionEnergyCost = ganglionMass × 22 × metabolicConstant × 0.1
  (ganglia are 10% as metabolically expensive per unit volume as brain)
nerveWireCost = Σ(nerveLength² × nerveDiameter²)
ventralChainCost = ventralCordLength × ventralCordDiameter² × costFactor
```

### 5.2 Energy Budget Impact

```
neuralEnergyPercentage = totalNeuralCost / totalShipEnergyBudget × 100

If neuralEnergyPercentage > 25%:
  → Ship is "metabolically strained"
  → All organ efficiency reduced by (neuralEnergyPercentage - 25)%
  → Telemetry shows warning: "Neural metabolic overload"

If neuralEnergyPercentage < 10%:
  → Ship is "neurally underinvested"
  → Reflex latency increases (ganglia too far apart)
  → Telemetry shows warning: "Neural underinvestment"
```

---

## 6. Implementation File Map

### New Files
- `src/utils/neuralCompute.ts` — Brain scaling, compute pipeline, efficiency curve
- `src/utils/nerveBranching.ts` — Nerve branch generation, Murray's law, cost calculation

### Modified Files
- `src/types.ts` — New AppState fields (showSystemNeuralVentral, showCommandRoom, crewCapacity)
- `src/App.tsx` — Default values for new fields
- `src/components/Canvas3D.tsx` — Brain dynamic sizing, ganglion redistribution, nerve branches, command room
- `src/components/GeneticsDrawer.tsx` — New toggles (ventral chain, command room)
- `src/components/TelemetryPanel.tsx` — Neural compute telemetry (brain EQ, reserve, efficiency)
- `src/utils/pipelineGraph.ts` — Dynamic brain node sizing

### Constants
```typescript
// Brain scaling
const REFERENCE_SHIP_VOLUME = 108.6;     // smallest ship (6m × 2.4m × 2.4m × π)
const MAX_EQ = 7.0;
const MIN_EQ = 3.0;
const JERISON_K = 0.12;
const JERISON_BETA = 0.67;
const NEURON_DENSITY = 86e9;             // neurons per m³ (human brain density)
const BITS_PER_NEURON = 5;               // bits/s per neuron (conservative)
const MIN_BRAIN_RADIUS = 0.3;            // minimum visible radius
const GANGLION_EFFICIENCY_FACTOR = 0.10; // ganglia produce 10% of brain per-volume

// Nerve properties
const AXON_DENSITY = 1e6;                // axons per mm²
const CONDUCTION_VELOCITY = 120;         // m/s (myelinated equivalent)
const MAX_BRANCH_LENGTH_RATIO = 0.15;    // 15% of ship length
const BRANCHING_ANGLE = 83;              // degrees (biological optimum)
const BASE_NERVE_RADIUS = 0.04;          // meters

// Efficiency curve
const SHUTDOWN_THRESHOLD = 0.25;
const HEAVY_LOSS_THRESHOLD = 0.50;
const NORMAL_THRESHOLD = 1.00;
const ENHANCED_THRESHOLD = 1.20;
const OVERSTIMULATION_FLOOR = 0.50;

// Metabolic
const BRAIN_METABOLIC_MULTIPLIER = 22;   // × muscle metabolic rate
const METABOLIC_STRAIN_THRESHOLD = 0.25; // 25% of energy budget
const METABOLIC_UNDERINVESTMENT_THRESHOLD = 0.10; // 10%
```

---

## 7. Research Citations

1. **Jerison 1973** — Evolution of the Brain and Intelligence. EQ formula.
2. **Aiello & Wheeler 1995** — Expensive Tissue Hypothesis. Brain 22× muscle metabolic cost.
3. **Herculano-Houzel 2011** — Scaling of Brain Metabolism with Fixed Energy Budget per Neuron.
4. **Niven & Burrows 2008** — Diversity and Evolution of the Insect Ventral Nerve Cord.
5. **Chklovskii 2004** — Synaptic Connectivity and Neuronal Morphology (wire cost = L²d²).
6. **Yerkes & Dodson 1908** — Arousal-performance inverted U-curve.
7. **Perge et al. 2009** — How the Optic Nerve Allocates Space, Energy, Capacity, and Information.
8. **Murray 1926** — The Physiological Principle of Minimum Work (Murray's Law).
9. **Sterling & Laughlin 2015** — Principles of Neural Design.
10. **Eberhard & Wcislo 2011** — Grade Changes in Brain-Body Allometry (Haller's Rule invertebrates).
11. **Nature Ecology & Evolution 2024** — Co-evolutionary dynamics of mammalian brain and body size.
12. **PNAS 2024** — Yerkes-Dodson law as general mechanism in human decision-making.
13. **JNeurosci 2018** — Cholinergic Overstimulation Attenuates Rule Selectivity.
14. **Budelmann 1995, Young 1963-1971** — Cephalopod nervous system, distributed arm ganglia.
15. **Scientific Reports 2022** — Brain information processing capacity modeling.
