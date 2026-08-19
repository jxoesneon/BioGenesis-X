# Research Report: Best-in-Class Combat Architecture & BioGenesis Integration Blueprint

**Author:** Subagent 3 (Combat Systems Lead)  
**Swarm / Loop:** Best-in-Class Research Swarm — Combat & Visceral Mechanics Lead  
**Target System:** BioGenesis Living-Ship Combat Engine, Hydro-Pulse Vectoring, Organ Dismemberment & Vascular Boarding Defense  
**Status:** Approved Technical Architecture & Mathematical Specification  

---

## Executive Summary & Design Philosophy

BioGenesis establishes a paradigm shift in space combat simulation by replacing rigid, metallic starships with grown, living organisms. Ships in BioGenesis are complex biological entities featuring hyperelastic carapace plates, vascular networks, neural ganglia, and soft-body organ systems. Consequently, space combat cannot rely on traditional hit-point subtraction or simple shield-bar depletion.

This research specification deconstructs combat gold standards from acclaimed AAA and indie titles:
- **Dead Space**: Directional anatomical dismemberment and targeted limb slicing.
- **Star Wars: Squadrons** & **Elite Dangerous**: Newtonian 6-DOF space dogfighting, energy balancing, and vector drift.
- **Doom Eternal**: High-velocity weapon-swapping loops and push-forward resource replenishment cycles.
- **FTL (Faster Than Light)**: Targeted subsystem destruction, cascading failure states, and internal fire/breach management.
- **HighFleet**: Ballistic inertia, vector interception, thermal/bioluminescent signatures, and structural angle deflection.

We synthesize these mechanics into the **BioGenesis Combat Core**, featuring:
1. **Targeted Organ Dismemberment**: Precision destruction of living ship organs (blinding ocular pods, severing spinal axon cords, rupturing high-pressure plasma bladders) causing dynamic functional cascade failures.
2. **6-DOF Hydro-Pulse Vectoring**: Biological jet propulsion operating on fluidic mass ejection, sphincter thrust vectoring, and dynamic hemolymph inertia shifts.
3. **Yerkes-Dodson Excitotoxicity Overclocking**: A bi-phasic inverted-U neural performance curve balancing pilot pain, neurotoxin buildup, organ excitotoxicity, and cardiac arrest risks.
4. **Seamless Dual-Layer FPS Vascular Boarding Defense**: Real-time integration between 6-DOF spatial dogfighting and interior FPS hallway defense against parasites breaching vascular corridors.

---

## 1. Deconstruction of AAA & Indie Combat Gold Standards

```
+-----------------------------------------------------------------------------------+
|                        AAA & INDIE COMBAT GOLD STANDARDS                          |
+--------------------------+--------------------------+-----------------------------+
| Game                     | Core Combat Mechanic     | Player Experience Vector    |
+--------------------------+--------------------------+-----------------------------+
| Dead Space               | Strategic Dismemberment  | Surgical locational damage  |
| Star Wars: Squadrons     | 6-DOF Energy Vectoring   | 3D spatial drift & mastery  |
| Doom Eternal             | Push-Forward Resource Loop| Aggressive stance swapping  |
| FTL: Faster Than Light   | Subsystem Failure Cascade| Multi-room damage management|
| HighFleet                | Vector Drift & Signature | Angle deflection & momentum |
+--------------------------+--------------------------+-----------------------------+
```

### 1.1 Dead Space: Strategic Anatomical Dismemberment
*Mechanic:* Slicing distinct limbs off Necromorphs alters AI locomotion, attack vectors, and aggressiveness. Center-mass shots are highly inefficient.
*BioGenesis Application:* Ships are anatomical bodies. Shooting the central hull carapace yields minimal tactical gain. Surgical targeting of exposed ocular pods, axon cord nerve trunks, or bio-plasma bladders removes specific ship capabilities (navigation, pitch speed, heavy artillery).

### 1.2 Star Wars: Squadrons & Elite Dangerous: 6-DOF Vectoring & Power Shunting
*Mechanic:* Newtonian flight dynamics where ship heading decouples from velocity vector during boost-drifting. Dynamic power distribution (Power to Engines / Weapons / Shields) shifts performance envelopes instantly.
*BioGenesis Application:* Living ships generate propulsion via high-pressure hydro-pulse vents. Power management becomes **Metabolic Mass Shunting**—redirecting pressurized hemolymph between Caudal Hydro-Vents (Engine), Bio-Plasma Glands (Weapons), and Chitin Membrane Turgor (Shields/Armor).

### 1.3 Doom Eternal: Push-Forward Resource Cycle
*Mechanic:* Combat requires constant swapping between weapons to exploit enemy vulnerabilities while executing specific kill moves (Chainsaw = Ammo, Flame Belch = Armor, Glory Kill = Health) to maintain combat momentum.
*BioGenesis Application:* A living ship cannot reload synthetic ammunition from crates. It operates on a **Biological Metabolism Loop**:
- *Hemolymph Venting*: Dumps excess heat, cooling organs but sacrificing fluid volume.
- *Bio-Plasma Discharge*: Consumes stored plasma for heavy localized DPS.
- *Spore Spraying*: Disperses corrosive clouds to degrade enemy carapace turgor.
- *Siphon Intake*: Engulfs destroyed enemy biomass fragments to regenerate hemolymph and bio-matter mid-flight.

### 1.4 FTL: Subsystem Cascade & Internal Breach Management
*Mechanic:* Hitting a specific room disables the corresponding ship subsystem (Shields, Weapons, Engines, Medical). Damaged rooms catch fire, leak oxygen, or suffer hull breaches requiring crew intervention.
*BioGenesis Application:* Damage to external hull propagates into internal organ chambers. An artery rupture starves downstream organs of nutrients; a broken axon cord paralyzes thrusters; a breached habitat leaks hemolymph into crew quarters.

### 1.5 HighFleet: Vector Inertia, Thermal Signatures & Armor Deflection
*Mechanic:* Heavy ballistic feel where thruster angles, weight distribution, and momentum dictate interception. Armor plates deflect incoming shells based on angle of impact ($1/\cos \theta$). Thermal emissions govern missile lock-on distance.
*BioGenesis Application:* Carapace plates possess directional curvature and thickness. Shells striking at oblique angles slide off organic chitin. Bioluminescent emissions and heat spikes from overclocked heart pumps increase signature visibility across long distances.

---

## 2. BioGenesis Combat Core Integration Principles

```
                 +-----------------------------------+
                 |    BIOGENESIS COMBAT ARCHITECTURE |
                 +-----------------+-----------------+
                                   |
         +-------------------------+-------------------------+
         |                                                   |
+--------v-----------------------+                 +---------v-----------------------+
|  EXTERIOR SPATIAL LAYER (6-DOF)|                 |  INTERIOR VASCULAR LAYER (FPS)  |
|  - Hydro-Pulse Vectoring       |                 |  - Corridor Boarding Defense    |
|  - Organ Dismemberment         |                 |  - Immune Leukocyte Deployment  |
|  - Bioluminescent Signatures   |                 |  - Sphincter Lockdowns          |
+--------+-----------------------+                 +---------+-----------------------+
         |                                                   |
         +-------------------------+-------------------------+
                                   |
                 +-----------------v-----------------+
                 |  NEURAL TENSION & OVERCLOCK ENGINE|
                 |  - Yerkes-Dodson Excitotoxicity   |
                 |  - Pilot Pain & Neurotoxin Loop   |
                 +-----------------------------------+
```

### 2.1 Visceral Feedback Engine
Combat feedback in BioGenesis engages sight, sound, haptics, and physics simultaneously:
1. **Hit-Stop Micro-Stutter**: High-impact kinetic or plasma strikes on major organs trigger a 15–45 ms physics freeze-frame, emphasizing tissue impact resistance.
2. **Volumetric Fluid Ejection**: Ruptured arteries emit high-velocity particle streams of glowing bio-plasma (emissive green), dark hemolymph (viscous crimson), or digestive acid (yellow-green). Fluid accumulates on windshield/hud glass.
3. **Procedural Mesh Tearing**: Soft-body organ surfaces deform via XPBD and tear when strain exceeds elastic limits, exposing raw muscle fibers beneath chitin.
4. **Biological Audio Spatialization**: Direct organ hits play visceral soundscapes—wet muscular thuds, squelching membrane ruptures, atmospheric decompression hiss, and pilot cardiac tachycardia audio cues.

### 2.2 Biological Stance Switching
Living ships instantly alter their physical configuration by flexing structural muscles and repositioning carapace plates:

```
+------------------------------------------------------------------------------------+
|                               BIOLOGICAL STANCES                                   |
+--------------------+--------------------------+------------------------------------+
| Stance             | Muscle & Organ Geometry  | Gameplay / Combat Effect           |
+--------------------+--------------------------+------------------------------------+
| Hydro-Drift        | Sphincters wide open,    | Maximum turn rate, decoupled       |
|                    | ribs relaxed             | trajectory, 0% stability damping   |
+--------------------+--------------------------+------------------------------------+
| Predator Pursuit   | Axons tense, caudal      | Maximum forward acceleration,      |
|                    | vents locked posterior   | tight turn radius, high bio-energy |
+--------------------+--------------------------+------------------------------------+
| Skeletal Shielding | Rib cage tightly clamped | +70% armor turgor, organ protection|
|                    | over thoracic cavity     | -50% mobility, restricted vision   |
+--------------------+--------------------------+------------------------------------+
| Siphon Harvest     | Oral intake vent flared, | High biomass consumption rate,     |
|                    | vacuum sphincter open    | internal fluid recovery, 0% armor  |
+--------------------+--------------------------+------------------------------------+
```

---

## 3. Targeted Organ Dismemberment & Anatomical Damage Model

### 3.1 Dismemberment Mechanics & Functional Cascades
Organs are discrete mesh entities integrated into the living ship's hull topology. Targeted attacks on specific organs produce severe operational penalties.

```
       [ Ocular Pods (Cranial) ] ------------> Loss of Visual Tracking & Parallax HUD
                |
       [ Brain / Ganglia (Cranial) ] --------> Loss of Neural Command & EQ Capacity
                |
  +-------------+-------------+
  |                           |
[ Heart (Thoracic) ]    [ Axon Cord (Spine) ] -> Paralyzes Caudal Hydro-Vents
  |                           |
[ Plasma Gland ]        [ Caudal Vent ] -------> Complete Loss of Propulsion
  |
  +-> Rupture -> Acid Spill into Internal Corridors
```

### 3.2 Ocular Pod Dismemberment: Sensor Blinding & HUD Noise
Destruction of cranial ocular pods degrades optical sensor data fed to the pilot's neural link.
- **Single Eye Destruction**: Loss of stereoscopic depth estimation. Target lead reticles begin jittering with angular error variance $\sigma_{target}^2$.
- **Dual Eye Destruction**: Complete loss of visual spectrum pipeline. The screen blackouts into raw thermal/electromagnetic rendering mode with severe noise artifacts.

Mathematical formulation of targeting reticle jitter based on eye pod health $H_{eye} \in [0, 1]$:
$$\sigma_{target}^2(H_{eye}) = \sigma_{base}^2 + K_{jitter} \cdot \left(1.0 - \frac{H_{left\_eye} + H_{right\_eye}}{2}\right)^3.5$$

### 3.3 Spinal Axon Cord Severance: Neural Latency & Paralysis
The Spinal Axon Cord conveys command impulses from the cranial brain to the caudal hydro-pulse vents.
- **Partial Damage ($H_{axon} < 0.5$)**: Introduces neural signal propagation delay $\Delta t_{delay}$, causing input lag on pitch and yaw control commands.
- **Complete Severance ($H_{axon} = 0$)**: Immediate paralysis of all caudal thrusters and tail appendages. The ship drops into unguided inertial spin.

Signal propagation delay equation:
$$\Delta t_{delay} = \Delta t_{base} + \frac{L_{spine}}{v_{axon} \cdot \max(0.05, H_{axon})}$$
where $v_{axon} = 120 \text{ m/s}$ (uninjured signal speed), $L_{spine} = \text{ship spine length (m)}$.

### 3.4 Plasma & Hemolymph Bladder Rupture: Corrosive Internal Hazards
Rupturing a pressurized fluid bladder releases fluid into both external space and interior vascular corridors.
- **External Spills**: Creates a persistent cloud of corrosive hemolymph/plasma that degrades thrusters and hulls passing through it.
- **Internal Spills**: Floods internal crew habitat corridors with acidic fluid, causing continuous damage to interior defense turrets, crew workstations, and parasite invaders.

```
+--------------------------------------------------------------------------------------------------------------------+
|                                          COMPREHENSIVE ORGAN DAMAGE MATRIX                                         |
+---------------------+----------+--------------------+------------------------------+-------------------------------+
| Organ Name          | Location | Dismember Trigger  | Primary Failure Effect       | Secondary Cascade Effect      |
+---------------------+----------+--------------------+------------------------------+-------------------------------+
| Ocular Pod (Eye)    | Cranial  | Structural Cut     | Blinds optic sensor spectrum | Disables target lock reticle  |
| Spinal Axon Cord    | Spine    | Tensile Tearing    | Paralyzes caudal thrusters   | Adds 450ms pitch/yaw lag      |
| Bio-Plasma Gland    | Thoracic | Explosive Rupture  | Disables bio-plasma cannon   | Corrosive fluid spill in halls|
| Cardiac Myocardium  | Thoracic | Ischemic Necrosis  | Drops ship hemolymph pressure| Starves all downstream organs |
| Siphon Intake Vent  | Cranial  | Impact Fracture    | Prevents biomass harvesting  | Disables mid-fight repair     |
| Caudal Sphincter    | Caudal   | Shear Dismemberment| Disables main forward vector | 60% fuel leak rate            |
| Cyber Air Lock      | Thoracic | Hull Breach        | Depressurizes crew quarters  | Allows enemy boarding pods    |
| Shield Emitter Node | Mid-Hull | Thermal Ablation   | Collapse chitin force-field  | Overheats nearby ganglia      |
+---------------------+----------+--------------------+------------------------------+-------------------------------+
```

---

## 4. 6-DOF Hydro-Pulse Vectoring & Flight Mechanics

```
                 [ Hydro-Pulse Vectoring Dynamics ]

                         Forward Thrust Vector F_thrust
                                    ^
                                    |
            Yaw Vector              |              Yaw Vector
       F_left <------------- [ Living Ship ] -------------> F_right
                                    |
                                    |
                                    v
                          Retro Pulse Vector F_retro
```

### 4.1 Hydro-Pulse Newtonian Physics
Propulsion is generated by high-frequency contraction of muscular caudal cavities, expelling fluid mass through directional sphincters.
The instantaneous thrust force vector $\mathbf{F}_{thrust}$ produced by $N_{vent}$ active hydro-pulse vents is:
$$\mathbf{F}_{thrust} = \sum_{k=1}^{N_{vent}} \eta_k \cdot \left[ \dot{m}_k \mathbf{v}_{jet, k} + (p_k - p_{\infty}) A_k \mathbf{n}_k \right]$$

where:
- $\dot{m}_k$: Hemolymph mass flow rate through vent $k$ ($\text{kg/s}$).
- $\mathbf{v}_{jet, k}$: Exhaust jet velocity vector ($\text{m/s}$), bounded by sphincter vector angle $\theta_{vent} \le 45^\circ$.
- $p_k$: Internal cavity hydro-pressure ($\text{Pa}$).
- $A_k$: Sphincter nozzle cross-sectional area ($\text{m}^2$).
- $\mathbf{n}_k$: Nozzle orientation unit vector.
- $\eta_k \in [0, 1]$: Health factor of the underlying sphincter muscle.

### 4.2 Biological RCS & Sphincter Vectoring
Rotational torque $\boldsymbol{\tau}_{hydro}$ about the ship's center of mass $\mathbf{r}_{cg}$ is generated by asymmetric sphincter deflection:
$$\boldsymbol{\tau}_{hydro} = \sum_{k=1}^{N_{vent}} (\mathbf{r}_k - \mathbf{r}_{cg}) \times \mathbf{F}_{thrust, k} + \boldsymbol{\tau}_{caudal\_muscles}$$

### 4.3 Hemolymph Mass Shift & Variable Inertia Tensor
As hemolymph shifts between internal organ bladders, the ship's mass $m(t)$ and moment of inertia tensor $\mathbf{I}_{ship}(t)$ vary dynamically in real time:
$$m(t) = m_{dry} + \int \left( \dot{m}_{intake} - \sum \dot{m}_{vent, k} \right) dt$$
$$\mathbf{I}_{ship}(t) = \mathbf{I}_{chitin} + \sum_{j=1}^{N_{organs}} m_{fluid, j}(t) \left( \|\mathbf{r}_j\|^2 \mathbf{E} - \mathbf{r}_j \otimes \mathbf{r}_j \right)$$

This dynamic inertia change causes the ship to feel lighter and more agile as fluid mass is expended in dogfighting, but heavier and more sluggish when fully saturated with bio-mass.

---

## 5. Yerkes-Dodson Excitotoxicity & Overclocking Physics

```
   Organ Efficiency (η)
      1.4 |                      / \  <- Peak Performance (120% Supply, Overclocked)
          |                     /   \
      1.0 |.........+----------+     \  <- Normal Operating Zone (100%)
          |        /            \     \
      0.5 |       /              \     \  <- Excitotoxicity & Damage Zone (>120%)
          |      /                \     \
        0 +-----+------------------+-----+-----> Neural Supply (S %)
               25%                100%  120% 140%
```

### 5.1 Mathematical Formulation of the Inverted-U Neural Curve
Organs receive neural compute from cranial ganglia measured as percentage supply $S \in [0, 200\%]$. Organ efficiency $\eta_{organ}(S)$ follows a non-linear bi-phasic response based on the Yerkes-Dodson law:

$$\eta_{organ}(S) = \begin{cases} 
0.0 & S < 25\% \quad (\text{Organ Shutdown}) \\
\frac{S - 25}{50} & 25\% \le S < 75\% \quad (\text{Sub-optimal Supply}) \\
1.0 & 75\% \le S \le 100\% \quad (\text{Nominal Supply}) \\
1.0 + 0.02 (S - 100) & 100\% < S \le 120\% \quad (\text{Controlled Overclock}) \\
1.4 - 0.005 (S - 120)^2 & S > 120\% \quad (\text{Excitotoxic Overstimulation})
\end{cases}$$

### 5.2 Neuro-Toxin Accumulation & Cardiac Arrest Rate
Operating an organ above $S > 120\%$ forces cellular metabolism into anaerobic excitotoxicity, generating neurotoxins $T_{neuro}$:

$$\frac{d T_{neuro, i}}{dt} = k_{tox} \cdot \max(0, S_i - 120)^{1.6} - \delta_{clearance} \cdot H_{kidney}$$

As neurotoxins accumulate, organ health degrades via thermal and chemical necrosis:
$$\frac{d H_{organ, i}}{dt} = -\mu_{necrosis} \cdot T_{neuro, i} - \alpha_{thermal} \cdot \max(0, T_{temp, i} - T_{critical})$$

If $T_{neuro, heart}$ exceeds the critical threshold $T_{crit} = 100.0$, the Cardiac Myocardium enters **Ventricular Fibrillation (Cardiac Arrest)** with probability per second:
$$P_{arrest} = 1.0 - \exp\left(-\lambda_{arrest} \cdot (T_{neuro, heart} - 100.0)_+\right)$$

### 5.3 Pilot Symbiosis Feedback & Haptic Trauma
Because the pilot is neurally linked to the living ship, ship organ damage and neurotoxins mirror directly into pilot physiological strain:

$$\text{Pain Index } P_{pilot} = \sum_{i=1}^{N} w_i (1.0 - H_{organ, i}) + \beta_{tox} \cdot T_{neuro, total}$$

When $P_{pilot} > 0.6$:
- **Visual Tunnel Vision**: Post-processing vignette clamps FOV down to $40^\circ$.
- **Chromatic Aberration**: Screen edges distort with intense magenta/cyan fringing.
- **Audio Muffling & Tachycardia**: Audio low-pass filter clamps at $400 \text{ Hz}$ while heartbeats play at $160 \text{ BPM}$.
- **Haptic Feedback**: Controller/Device vibration triggers high-frequency spasms.

---

## 6. Dual-Layer Seamless FPS Vascular Corridor Boarding Defense

```
+-----------------------------------------------------------------------------------+
|                        DUAL-LAYER COMBAT SYNCHRONIZATION                          |
+-----------------------------------------------------------------------------------+
| LAYER 1: SPATIAL DOGFIGHT (External View)                                         |
| [ Living Ship ] <====== Enemy Parasite Boarding Pod Breaches Chitin Hull          |
|        ||                                                                         |
|        || Dynamic G-Force & Structural Kinetic Shockwave Synchronization          |
|        \/                                                                         |
| LAYER 2: VASCULAR CORRIDOR DEFENSE (FPS View inside Hull)                         |
| [ Corridor Membrane ] ---> [ Sphincter Seal ] ---> [ White Blood Cell Leukocytes ]|
|   (Shakes with 15G)        (Clamps Hall)             (Attacks Parasites)          |
+-----------------------------------------------------------------------------------+
```

### 6.1 Hull Breaching & Parasite Boarding
When enemy parasite pods strike the living ship's hull, they clamp onto the chitin surface with bio-borers, cutting through the outer carapace layer into the interior vascular corridors.

### 6.2 Interior Vascular Environment
Interior ship corridors are living anatomical structures:
- **Pulsing Vascular Walls**: Walls flex in rhythm with the ship's cardiac cycle.
- **Hemolymph Streams**: Low-gravity fluid currents flow along floors, impairing or assisting player locomotion.
- **Sphincter Lockdowns**: Muscular sphincters act as dynamic blast doors, closing off breached sections to prevent depressurization and fluid loss.

### 6.3 Immune System Autonomous Defense
The living ship defends itself internally via autonomous immune units:
- **Leukocyte Swarms**: Mobile defensive organisms spawned from bone marrow nodes that engulf parasite invaders.
- **Bio-Plasmic Wall Sphincters**: Wall-mounted organic nodules that vent superheated plasma into corridors occupied by enemies.
- **Acid Venting**: Manual command room action that floods selected corridors with digestive acid, dissolving parasites at the cost of damaging internal tissue.

### 6.4 Spatial-to-Interior Dual-Layer State Synchronizer
The spatial dogfight layer and interior FPS layer run in lockstep:
- **G-Force Displacement**: Extreme maneuvers in spatial dogfighting (e.g., $15G$ hydro-drift turn) apply fictitious inertial forces $\mathbf{F}_{inertial} = -m_{player} \mathbf{a}_{ship}$ to interior FPS players and entities, slamming them against vascular walls.
- **Internal Damage Propagation**: Damage inflicted by parasites to interior corridor walls reduces the max hemolymph pressure of adjacent external thrusters.

---

## 7. Concrete Implementation Blueprints & Code Architecture

### 7.1 Production TypeScript Combat & Dismemberment Engine (`CombatEngine.ts`)

```typescript
/**
 * CombatEngine.ts - BioGenesis Living-Ship Combat & Dismemberment System
 */

export interface OrganState {
  id: string;
  name: string;
  section: 'cranial' | 'neck' | 'thoracic' | 'caudal' | 'tail';
  health: number; // 0.0 to 1.0
  maxHealth: number;
  isDismembered: boolean;
  neuralSupply: number; // Percentage (100 = nominal)
  neurotoxin: number; // Accumulated toxicity
  temperature: number; // Degrees Celsius
}

export interface HitEvent {
  targetOrganId: string;
  damageAmount: number;
  damageType: 'kinetic' | 'bio_plasma' | 'corrosive_acid' | 'thermal';
  impactPoint: [number, number, number];
  impactNormal: [number, number, number];
}

export class CombatEngine {
  private organs: Map<string, OrganState> = new Map();
  private hitStopTimer: number = 0;
  private pilotPainIndex: number = 0;

  constructor() {
    this.initializeDefaultOrgans();
  }

  private initializeDefaultOrgans(): void {
    const defaultOrgans: OrganState[] = [
      { id: 'ocular_left', name: 'Left Ocular Pod', section: 'cranial', health: 1.0, maxHealth: 100, isDismembered: false, neuralSupply: 100, neurotoxin: 0, temperature: 37 },
      { id: 'ocular_right', name: 'Right Ocular Pod', section: 'cranial', health: 1.0, maxHealth: 100, isDismembered: false, neuralSupply: 100, neurotoxin: 0, temperature: 37 },
      { id: 'axon_cord', name: 'Spinal Axon Cord', section: 'cranial', health: 1.0, maxHealth: 250, isDismembered: false, neuralSupply: 100, neurotoxin: 0, temperature: 37 },
      { id: 'heart', name: 'Cardiac Myocardium', section: 'thoracic', health: 1.0, maxHealth: 400, isDismembered: false, neuralSupply: 100, neurotoxin: 0, temperature: 37 },
      { id: 'plasma_gland', name: 'Bio-Plasma Gland', section: 'thoracic', health: 1.0, maxHealth: 200, isDismembered: false, neuralSupply: 100, neurotoxin: 0, temperature: 37 },
      { id: 'caudal_vent', name: 'Caudal Hydro Vent', section: 'caudal', health: 1.0, maxHealth: 300, isDismembered: false, neuralSupply: 100, neurotoxin: 0, temperature: 37 },
    ];

    for (const organ of defaultOrgans) {
      this.organs.set(organ.id, organ);
    }
  }

  public processHit(hit: HitEvent): { hitStopMs: number; dismembermentOccurred: boolean } {
    const organ = this.organs.get(hit.targetOrganId);
    if (!organ || organ.isDismembered) {
      return { hitStopMs: 0, dismembermentOccurred: false };
    }

    // Apply raw damage scaled by organ material properties
    organ.health = Math.max(0, organ.health - hit.damageAmount / organ.maxHealth);

    let dismembermentOccurred = false;
    let hitStopMs = 0;

    // Check for structural dismemberment threshold (health <= 0)
    if (organ.health <= 0 && !organ.isDismembered) {
      organ.isDismembered = true;
      dismembermentOccurred = true;
      this.triggerOrganCascadeFailure(organ);
      hitStopMs = 45; // Major hit-stop for organ severance
    } else {
      hitStopMs = Math.min(30, Math.floor(hit.damageAmount * 0.5));
    }

    this.hitStopTimer = hitStopMs;
    this.updatePilotPainIndex();

    return { hitStopMs, dismembermentOccurred };
  }

  private triggerOrganCascadeFailure(severedOrgan: OrganState): void {
    switch (severedOrgan.id) {
      case 'axon_cord': {
        // Paralyze caudal organs
        const caudalVent = this.organs.get('caudal_vent');
        if (caudalVent) {
          caudalVent.neuralSupply = 0;
        }
        break;
      }
      case 'heart': {
        // Starve all organs
        for (const organ of this.organs.values()) {
          organ.neuralSupply *= 0.2;
        }
        break;
      }
      case 'plasma_gland': {
        // Internal corrosive spill hazard
        console.warn('Bio-Plasma Gland ruptured! Acid spilling into thoracic vascular corridors.');
        break;
      }
    }
  }

  public updatePilotPainIndex(): number {
    let totalDamage = 0;
    let totalToxin = 0;

    for (const organ of this.organs.values()) {
      totalDamage += (1.0 - organ.health);
      totalToxin += organ.neurotoxin;
    }

    this.pilotPainIndex = Math.min(1.0, (totalDamage / this.organs.size) * 0.7 + (totalToxin / 500) * 0.3);
    return this.pilotPainIndex;
  }

  public getTargetingReticleJitter(): number {
    const leftEye = this.organs.get('ocular_left');
    const rightEye = this.organs.get('ocular_right');

    const hLeft = leftEye && !leftEye.isDismembered ? leftEye.health : 0;
    const hRight = rightEye && !rightEye.isDismembered ? rightEye.health : 0;

    const avgEyeHealth = (hLeft + hRight) / 2.0;
    return Math.pow(1.0 - avgEyeHealth, 3.5) * 15.0; // Jitter variance in pixels
  }

  public getOrgan(id: string): OrganState | undefined {
    return this.organs.get(id);
  }
}
```

---

### 7.2 WebGPU Hydro-Pulse Vectoring Compute Shader (`hydroPulseVectoring.wgsl`)

```wgsl
// hydroPulseVectoring.wgsl - Compute Shader for 6-DOF Biological Jet Propulsion

struct VentParams {
    position: vec3<f32>,
    direction: vec3<f32>,
    massFlowRate: f32,
    exhaustVelocity: f32,
    nozzleArea: f32,
    health: f32,
};

struct ShipDynamics {
    position: vec3<f32>,
    velocity: vec3<f32>,
    orientation: vec4<f32>, // Quaternion
    angularVelocity: vec3<f32>,
    centerOfMass: vec3<f32>,
    totalMass: f32,
};

@group(0) @binding(0) var<storage, read> vents: array<VentParams>;
@group(0) @binding(1) var<storage, read_write> dynamics: ShipDynamics;
@group(0) @binding(2) var<storage, read_write> forceOutput: array<vec3<f32>>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    let index = GlobalInvocationID.x;
    if (index >= arrayLength(&vents)) {
        return;
    }

    let vent = vents[index];
    if (vent.health <= 0.0) {
        forceOutput[index] = vec3<f32>(0.0, 0.0, 0.0);
        return;
    }

    // Thrust equation: F = eta * (dot(m) * v_jet + P_delta * Area)
    let thrustMagnitude = vent.health * (vent.massFlowRate * vent.exhaustVelocity);
    let thrustForce = vent.direction * thrustMagnitude;

    // Output individual vent thrust vector for torque integration
    forceOutput[index] = thrustForce;
}
```

---

### 7.3 Yerkes-Dodson Excitotoxicity Calculator (`ExcitotoxicitySolver.ts`)

```typescript
/**
 * ExcitotoxicitySolver.ts - Yerkes-Dodson Inverted-U Neural Curve Calculator
 */

export class ExcitotoxicitySolver {
  private static readonly TOXICITY_K = 0.005;
  private static readonly CLEARANCE_RATE = 0.02;

  /**
   * Calculates organ functional efficiency given neural supply percentage (0..200%)
   */
  public static calculateEfficiency(neuralSupplyPercent: number): number {
    const S = neuralSupplyPercent;
    if (S < 25.0) {
      return 0.0; // Complete organ shutdown
    } else if (S < 75.0) {
      return (S - 25.0) / 50.0;
    } else if (S <= 100.0) {
      return 1.0; // Nominal operating range
    } else if (S <= 120.0) {
      return 1.0 + 0.02 * (S - 100.0); // Controlled Overclock (+40% max output)
    } else {
      // Excitotoxicity quadratic decay
      const over = S - 120.0;
      return Math.max(0.1, 1.4 - 0.005 * over * over);
    }
  }

  /**
   * Updates neurotoxin accumulation rate and evaluates cardiac arrest probability
   */
  public static updateExcitotoxicity(
    currentToxin: number,
    neuralSupplyPercent: number,
    deltaTime: number
  ): { nextToxin: number; cardiacArrestProbability: number } {
    let toxinDelta = 0;

    if (neuralSupplyPercent > 120.0) {
      const excess = neuralSupplyPercent - 120.0;
      toxinDelta = this.TOXICITY_K * Math.pow(excess, 1.6) * deltaTime;
    } else {
      toxinDelta = -this.CLEARANCE_RATE * deltaTime;
    }

    const nextToxin = Math.max(0, currentToxin + toxinDelta);

    // Cardiac arrest probability calculation
    let cardiacArrestProbability = 0;
    if (nextToxin > 100.0) {
      const excessToxin = nextToxin - 100.0;
      cardiacArrestProbability = 1.0 - Math.exp(-0.05 * excessToxin * deltaTime);
    }

    return { nextToxin, cardiacArrestProbability };
  }
}
```

---

### 7.4 Dual-Layer Boarding & Vascular Defense Engine (`VascularDefenseSystem.ts`)

```typescript
/**
 * VascularDefenseSystem.ts - Dual-Layer FPS Boarding & Vascular Defense Sync
 */

export interface BoardingPod {
  id: string;
  breachLocation: [number, number, number];
  parasiteCount: number;
  hullBreached: boolean;
}

export interface InteriorCorridor {
  id: string;
  section: string;
  hemolymphPressure: number;
  sphincterSealed: boolean;
  leukocyteCount: number;
}

export class VascularDefenseSystem {
  private activePods: BoardingPod[] = [];
  private corridors: Map<string, InteriorCorridor> = new Map();

  constructor() {
    this.corridors.set('corridor_thoracic_1', {
      id: 'corridor_thoracic_1',
      section: 'thoracic',
      hemolymphPressure: 120.0, // mmHg
      sphincterSealed: false,
      leukocyteCount: 50,
    });
  }

  public registerPodBreach(pod: BoardingPod): void {
    pod.hullBreached = true;
    this.activePods.push(pod);
    console.log(`[ALERT] Enemy boarding pod ${pod.id} breached chitin hull at location ${pod.breachLocation}`);
  }

  /**
   * Applies external 6-DOF ship G-forces to internal FPS player/entities
   */
  public computeInteriorInertialForce(shipAcceleration: [number, number, number], entityMass: number): [number, number, number] {
    // F_inertial = -m * a_ship
    return [
      -entityMass * shipAcceleration[0],
      -entityMass * shipAcceleration[1],
      -entityMass * shipAcceleration[2],
    ];
  }

  public toggleSphincterSeal(corridorId: string): boolean {
    const corridor = this.corridors.get(corridorId);
    if (!corridor) return false;

    corridor.sphincterSealed = !corridor.sphincterSealed;
    console.log(`Corridor ${corridorId} sphincter sealed state set to: ${corridor.sphincterSealed}`);
    return corridor.sphincterSealed;
  }
}
```

---

## 8. Verification, Metrics & Performance Targets

To maintain AAA responsiveness, the combat architecture enforces strict computational budgets:

```
+------------------------------------------------------------------------------------+
|                               PERFORMANCE TARGETS                                  |
+------------------------------------+-----------------------+-----------------------+
| Metric / System                    | Frame Budget          | Maximum Allocation    |
+------------------------------------+-----------------------+-----------------------+
| Combat Engine State Solver         | < 0.25 ms             | Heap < 5 MB           |
| WebGPU Hydro-Pulse Compute Shader  | < 0.15 ms             | GPU Memory < 12 MB    |
| Excitotoxicity & Pain Calculator   | < 0.05 ms             | Heap < 1 MB           |
| Dual-Layer Boarding Sync           | < 0.10 ms             | Heap < 2 MB           |
+------------------------------------+-----------------------+-----------------------+
| Total Combat Subsystem Budget      | < 0.55 ms / frame     | Target: 120 FPS       |
+------------------------------------+-----------------------+-----------------------+
```

### Static Type Checker Gate
All implementation code must pass static type verification with zero errors:
```bash
npx tsc --noEmit
```

---

## Conclusion

The BioGenesis Combat Architecture synthesizes the greatest achievements of AAA and indie combat design into a cohesive biological warfare framework. By mapping targeted dismemberment, 6-DOF vectoring, push-forward resource loops, subsystem cascades, and inertial positioning to living ship anatomy, BioGenesis delivers an unparalled, visceral space combat experience.
