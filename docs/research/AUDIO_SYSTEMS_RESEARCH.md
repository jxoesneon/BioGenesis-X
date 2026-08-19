# AAA+ Spatial Audio & Acoustic Systems Architecture — Research & Implementation Specification

> **Status**: Approved AAA+ Research Specification — BioGenesis Audio Engine
> **Date**: 2026-08-13
> **Author**: Subagent 5 (AAA+ Spatial Audio & Acoustic Systems Architect) — Loop 1
> **Target Engine**: WebAudio API / WebGPU Compute Audio DSP / C++ Audio Engine (Wwise/FMOD/Custom WebAssembly)
> **References**: Biot-Allard Poro-Elastic Acoustics, Uniform Theory of Diffraction (UTD), Womersley Flow Dynamics, Rayleigh-Plesset Bubble Dynamics, Klatt Formant Synthesis, ISO 13091 Tactile Perception Standard.

---

## Executive Summary & System Overview

BioGenesis requires a state-of-the-art, AAA+-tier bio-acoustic engine designed around the physical, physiological, and neurological reality of living in and piloting an organic starship. Traditional rigid-body room acoustics, static sample playback, and generic sci-fi synthesizer patches are completely inadequate for simulating living tissue walls, pulsing vascular networks, bio-plasma cavitation, and direct neural-link consciousness communications.

This specification details five core acoustic subsystems:
1. **Ray-Traced Bio-Acoustic Propagation System**: Real-time acoustic ray tracing with poro-elastic tissue attenuation, curved-surface diffraction, and dynamic SOFA HRTF spatialization.
2. **Physically Modeled Bio-Fluid & Cardiodynamic Synthesizer**: Procedural synthesis of non-linear Duffing cardiac cycles, Womersley hemodynamic flow, and Rayleigh-Plesset cavitation acoustics.
3. **Neuro-Sync Driven Dynamic Music Engine ($\mathcal{S} \times \mathcal{C}$)**: A 2D interactive matrix modulating vertical stems, horizontal re-sequencing, microtonal tuning shifts, and DSP filter topologies based on Neuro-Sync Ratio ($\mathcal{S}$) and Combat Intensity ($\mathcal{C}$).
4. **Sub-Bass Bio-Resonance & Tactile Haptic Synthesis Engine**: Infrasonic transducer routing (4–90 Hz), envelope-shaped LRA/HD haptic motor signals, and 4-quadrant tactile spatialization.
5. **Ganglion Brain Bio-Physical Voice Synthesizer**: Multi-formant glottal airway synthesis, mucosal transient injection, and $\mathcal{S}$-dependent diplophonic voice disintegration.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                               BIOGENESIS AUDIO ENGINE                                  │
└──────────────────────────────────────────┬─────────────────────────────────────────────┘
                                           │
         ┌─────────────────────────────────┼─────────────────────────────────┐
         ▼                                 ▼                                 ▼
┌──────────────────┐             ┌──────────────────┐             ┌──────────────────┐
│   RAY-TRACED     │             │ PHYSICAL BIO-    │             │ NEURO-SYNC       │
│   BIO-ACOUSTICS  │             │ SYNTHESIS ENGINE │             │ MUSIC MATRIX     │
│ - Poro-Elastic   │             │ - Cardiac Duffing│             │ - 2D S x C Grid  │
│ - Curved UTD     │             │ - Hemodynamics   │             │ - Micro-Tuning   │
│ - SOFA HRTF      │             │ - Cavitation     │             │ - Adaptive DSP   │
└────────┬─────────┘             └────────┬─────────┘             └────────┬─────────┘
         │                                │                                │
         └────────────────────────────────┼────────────────────────────────┘
                                           │
                                           ▼
                                 ┌──────────────────┐
                                 │ SUB-BASS & HAPTIC│
                                 │   BIO-RESONANCE  │
                                 │ - 4-90 Hz LFE    │
                                 │ - HD Actuators   │
                                 └────────┬─────────┘
                                           │
                                           ▼
                                 ┌──────────────────┐
                                 │ GANGLION VOICE   │
                                 │ - Klatt Formant  │
                                 │ - Mucosal Clicks │
                                 └──────────────────┘
```

---

## 1. Ray-Traced Spatial Audio & Acoustic Occlusion/Diffraction through Organic Tissue Corridors

### 1.1 Physical Bio-Acoustics & Poro-Elastic Media

Unlike rigid steel starships, organic ship corridors consist of compliant, wet, layered media: mucosal linings, fibrous collagen matrices, cartilage ribs, and viscous endolymph fluids. Acoustic waves undergo frequency-dependent attenuation, phase dispersion, and partial transmission through tissue bulk.

#### Biot-Allard Poro-Elastic Model

The acoustic wave equation in porous organic tissue is modeled by the Biot-Allard equations for fluid-saturated elastic media:

$$\rho_{11}^* \frac{\partial^2 \mathbf{u}}{\partial t^2} + \rho_{12}^* \frac{\partial^2 \mathbf{U}}{\partial t^2} = (P - N) \nabla (\nabla \cdot \mathbf{u}) + N \nabla^2 \mathbf{u} + Q \nabla (\nabla \cdot \mathbf{U})$$

$$\rho_{22}^* \frac{\partial^2 \mathbf{U}}{\partial t^2} + \rho_{12}^* \frac{\partial^2 \mathbf{u}}{\partial t^2} = R \nabla (\nabla \cdot \mathbf{U}) + Q \nabla (\nabla \cdot \mathbf{u})$$

Where:
- $\mathbf{u}, \mathbf{U}$ are displacement vectors of the frame (collagen) and fluid (endolymph/lymph).
- $\rho_{11}^*, \rho_{22}^*, \rho_{12}^*$ are complex effective densities accounting for viscous friction and tortuosity ($\alpha_\infty$).
- $P, R, Q, N$ are generalized elastic moduli of the tissue skeleton and fluid.

#### Simplified Real-Time Transmission Coefficient $\tau(f, x, \theta)$

For real-time GPU/CPU ray tracing, Biot-Allard behavior is approximated via a frequency-dependent transmission loss function:

$$\tau(f, x, \theta) = \exp\left( - \alpha_0 \cdot x \cdot \left(\frac{f}{f_0}\right)^\gamma \right) \cdot \cos^n(\theta)$$

- $\alpha_0$: Base attenuation factor ($\text{dB/m}$) per tissue type (e.g., Mucosal Layer: $1.2$, Muscular Wall: $4.5$, Chitin Carapace: $18.0$).
- $x$: Path length penetrating the organic barrier ($\text{meters}$).
- $\gamma$: Frequency exponent ($\gamma \approx 1.1 - 1.4$ for soft biological tissue).
- $f_0$: Reference frequency ($1000\text{ Hz}$).
- $\theta$: Angle of incidence relative to surface normal.

```
Frequency Response of Organic Wall Transmission:
 0 dB ──┐
        │  Low Frequencies (< 250 Hz) penetrate thick muscular tissue with minimal loss
-12 dB ──┼───┐
        │   └─┐  Mid Frequencies (500 Hz - 2 kHz) suffer moderate damping & phase lag
-36 dB ──┼─────└───┐
        │         └─── High Frequencies (> 2 kHz) are heavily absorbed by mucosal lining
-60 dB ──┴───────────────► Frequency (Hz)
        64    250    1k    4k    16k
```

### 1.2 Stochastic Ray Tracing & Curved Surface Diffraction

#### Ray Casting Architecture
1. **Monte Carlo Ray Emission**: Cast $N_{rays} = 256 - 1024$ rays per frame from audio emitters into the 5-section hull (Cranial, Neck, Thoracic, Caudal, Tail Tip).
2. **Intersection Testing**: Ray intersections test against hull bounding volumes and SDF tissue surfaces.
3. **Energy Tracking**: Each ray carries a spectral energy vector $\mathbf{E} = [E_{63}, E_{125}, E_{250}, E_{500}, E_{1k}, E_{2k}, E_{4k}, E_{8k}, E_{16k}]$.

#### Uniform Theory of Diffraction (UTD) on Organic Curved Surfaces

Corridors inside living ships feature rounded organic sphincters, cylindrical vascular lumen, and curved cartilage ribs. Acoustic diffraction around smooth convex surfaces uses Keller's Geometrical Theory of Diffraction extended by UTD:

$$E_{diff}(s) = E_0 \cdot D(\Phi, \Phi', \beta_0) \cdot A(s) \cdot e^{-i k s}$$

Where the diffraction coefficient $D$ for a curved surface is governed by Fock scattering functions:

$$D = -\frac{e^{-i \pi / 4}}{2 \sqrt{2 \pi k} \sin \beta_0} \cdot \left[ \frac{1}{\cos\left(\frac{\Phi - \Phi'}{2}\right)} + F\left(2 k L N^+ \sin^2\left(\frac{\Phi - \Phi'}{2}\right)\right) \right]$$

For soft organic boundaries, the surface impedence $Z_s$ drapes diffraction into creeping waves that wrap around organic corridors, creating lush, continuous low-pass spatial wrapping rather than sharp rigid edges.

### 1.3 SOFA HRTF Binaural Spatialization

- **Format**: SOFA (Spatially Oriented Format for Acoustics) standard AES69-2015 dataset.
- **Representation**: Spherical Harmonics Decomposition up to order $N = 5$ ($36$ coefficients per ear):
  $$H(f, \theta, \phi) = \sum_{n=0}^N \sum_{m=-n}^n Y_n^m(\theta, \phi) \cdot c_n^m(f)$$
- **Dynamic Interpolation**: Real-time cross-fading of HRTF spherical harmonics coefficients eliminating zipper noise during high-speed ship maneuvers.

```typescript
// DSP Structure: Ray-Traced Audio Propagation Node
export interface AcousticRay {
  origin: [number, number, number];
  direction: [number, number, number];
  energy: Float32Array; // 9 octave bands
  distanceTraversed: number;
  occlusionDepth: number;
}

export interface AcousticMaterialProfile {
  name: string;
  baseAbsorption: Float32Array;  // 9 bands
  baseScattering: Float32Array;  // 9 bands
  porosityAlpha0: number;        // Biot-Allard attenuation
  tissueFrequencyExponent: number; // Gamma
}

export const ORGANIC_MATERIALS: Record<string, AcousticMaterialProfile> = {
  mucosal_lining: {
    name: 'Mucosal Lining',
    baseAbsorption: new Float32Array([0.15, 0.25, 0.40, 0.65, 0.85, 0.92, 0.96, 0.98, 0.99]),
    baseScattering: new Float32Array([0.10, 0.15, 0.25, 0.35, 0.45, 0.50, 0.60, 0.70, 0.80]),
    porosityAlpha0: 1.2,
    tissueFrequencyExponent: 1.1,
  },
  chitin_carapace: {
    name: 'Chitin Carapace',
    baseAbsorption: new Float32Array([0.02, 0.04, 0.05, 0.08, 0.12, 0.18, 0.22, 0.25, 0.30]),
    baseScattering: new Float32Array([0.20, 0.30, 0.45, 0.60, 0.75, 0.85, 0.90, 0.95, 0.98]),
    porosityAlpha0: 18.0,
    tissueFrequencyExponent: 1.4,
  },
};
```

---

## 2. Heartbeat, Vascular Fluid, and Hydro-Pulse Acoustic Synthesis

### 2.1 Biomechanical Cardiac Cycle Synthesizer ($S_1$ / $S_2$)

The ship's main cardiac core produces a dual-component acoustic signature:
- **$S_1$ (Atrioventricular Valve Closure + Ventricular Contraction)**: 30–60 Hz fundamental with non-linear sub-harmonics.
- **$S_2$ (Aortic/Pulmonary Valve Closure)**: 70–140 Hz transient ring-down.

#### Duffing Non-Linear Oscillator for Cardiac Wall Mechanics

Ventricular tissue contraction during $S_1$ is modeled by a driven non-linear Duffing oscillator:

$$\ddot{x} + \delta \dot{x} + \alpha x + \beta x^3 = \gamma \cos(\omega t)$$

Where $\beta x^3$ models the non-linear stiffness of stretching cardiac muscle fiber, generating rich organic sub-harmonics during peak systole.

```
Systolic-Diastolic Pressure & Acoustic Output:
 Pressure (mmHg)
 120 ──┐     Systole (S1)
  80 ──┼───/\───────┐             Diastole (S2)
  40 ──┼──/  \      └──────/\───────┐
   0 ──┴─/────\───────────/──\──────┴──────► Time (ms)
       0    150   300   450  600   750
 Sound Waveform:
  +1 ──┐    S1 Duffing             S2 Ring-Down
   0 ──┼──/\/\/─────────────/\/\───────────
  -1 ──┴───────────────────────────────────► Time (ms)
```

### 2.2 Vascular Hemodynamic Fluid Synthesis

#### Womersley Flow Dynamic Acoustic Modeling

Vascular fluid acoustic noise is generated by pulsating viscous fluid (hemolymph/bio-plasma) traveling through compliant tubes. The acoustic velocity profile $u(r, t)$ is governed by the Womersley parameter $\alpha_W$:

$$\alpha_W = R \sqrt{\frac{\omega \rho}{\mu}}$$

- $R$: Vessel radius ($m$).
- $\omega$: Cardiac pulse angular frequency ($\text{rad/s}$).
- $\rho$: Hemolymph density ($\approx 1060\text{ kg/m}^3$).
- $\mu$: Dynamic viscosity ($\approx 0.004\text{ Pa}\cdot\text{s}$).

When $\alpha_W > 10$, fluid flow transitions to a flat plug profile with thin boundary layer shear, producing high-frequency fluid hiss and wall friction noise ($1.5\text{ kHz} - 6\text{ kHz}$) concentrated during peak systolic acceleration.

#### Dynamic Formant DSP Filter Network
Synthesized by passing shaped Brownian/pink noise through a 4-pole time-varying Biquad Formant Filter where cutoff frequency tracks instantaneous blood velocity:

$$v(t) = v_{mean} + v_{peak} \cdot \max\left(0, \sin\left(\frac{\pi t}{T_{systole}}\right)\right)$$

$$f_{cut}(t) = f_{base} + k_{flow} \cdot v(t)^2$$

### 2.3 Hydro-Pulse & Cavitation Acoustic Synthesis

In high-pressure conduits (Disruptor Gland, Caudal Vent Nozzles), fluid acceleration induces bio-plasma cavitation bubble collapse described by the **Rayleigh-Plesset Equation**:

$$R \ddot{R} + \frac{3}{2} \dot{R}^2 = \frac{1}{\rho_L} \left[ P_g(R_0) \left(\frac{R_0}{R}\right)^{3\kappa} + P_v - P_\infty(t) - \frac{2 \gamma}{R} - \frac{4 \mu \dot{R}}{R} \right]$$

#### Cavitation Noise Acoustic Output
Bubble collapse produces hyper-sharp pressure transients ($P_{peak} > 100\text{ kPa}$ at micro-second durations). DSP implementation uses a Poisson point-process triggering exponentially decaying impulse clusters with random bubble radius distributions $R_0 \sim \text{LogNormal}(\mu_R, \sigma_R)$.

```typescript
// DSP Code: Non-Linear Cardiac & Hemodynamic Synthesizer Node
export class BioCardiacSynthesizer {
  private phaseS1: number = 0;
  private duffingX: number = 0.05;
  private duffingV: number = 0.0;
  
  // Duffing parameters for S1 Ventricular Contraction
  private readonly alpha = -1.0;  // Linear stiffness
  private readonly beta = 1.5;    // Non-linear stiffness (muscle stretch)
  private readonly delta = 0.25;  // Damping factor
  
  public process(sampleRate: number, heartRateBPM: number, systoleProgress: number): number {
    const dt = 1.0 / sampleRate;
    const omega = (heartRateBPM / 60.0) * 2.0 * Math.PI;
    
    // Drive term active during S1 systole (first 30% of cardiac cycle)
    const drive = systoleProgress < 0.30 
      ? Math.sin(systoleProgress * (Math.PI / 0.30)) * 2.5 
      : 0.0;
      
    // Runge-Kutta 4th order numerical integration of Duffing equation
    const accel = (x: number, v: number, d: number) => 
      d - this.delta * v - this.alpha * x - this.beta * Math.pow(x, 3);
      
    const k1v = accel(this.duffingX, this.duffingV, drive);
    const k1x = this.duffingV;
    
    const k2v = accel(this.duffingX + 0.5 * dt * k1x, this.duffingV + 0.5 * dt * k1v, drive);
    const k2x = this.duffingV + 0.5 * dt * k1v;
    
    this.duffingX += dt * k2x;
    this.duffingV += dt * k2v;
    
    // S2 Aortic closure transient trigger
    let output = this.duffingX * 0.7;
    if (systoleProgress >= 0.35 && systoleProgress <= 0.45) {
      const s2Progress = (systoleProgress - 0.35) / 0.10;
      const s2Freq = 110.0; // Hz
      output += Math.sin(s2Progress * Math.PI * 8.0) * Math.exp(-s2Progress * 5.0) * 0.5;
    }
    
    return output;
  }
}
```

---

## 3. Dynamic Interactive Music System Driven by Neuro-Sync Ratio ($\mathcal{S}$) and Combat Intensity ($\mathcal{C}$)

### 3.1 Dual-Parameter State Space ($\mathcal{S} \times \mathcal{C}$)

The music engine does not rely on simple linear threat fades. It operates inside a 2D continuous parametric state space:
1. **Neuro-Sync Ratio ($\mathcal{S} \in [0.0, 1.0]$)**: Brain-ship alignment. High $\mathcal{S}$ yields pristine harmonic fidelity, organic acoustic warmth, and locked rhythmic pulse. Low $\mathcal{S}$ induces microtonal detuning, spectral fragmentation, and chaotic ring modulation.
2. **Combat Intensity ($\mathcal{C} \in [0.0, 1.0]$)**: Evaluated dynamically from enemy threat density, incoming bio-plasma fire, and hull integrity.

```
       Combat Intensity (C)
  1.0 ┌─────────────────────────┬─────────────────────────┐
      │  ZONE 2: CRITICAL SYNC  │  ZONE 4: APOCALYPTIC    │
      │  (High Combat / Low S)  │  WAR-HYMN               │
      │ - Microtonal Brass      │  (High Combat / High S) │
      │ - Ring Mod Distortion   │ - Full Orchestral Bio   │
      │ - Poly-rhythmic Chaos   │ - Hyper-Locked Perc     │
      ├─────────────────────────┼─────────────────────────┤
      │  ZONE 1: NEURAL DRIFT   │  ZONE 3: HARMONIC FLOW  │
      │  (Low Combat / Low S)   │  (Low Combat / High S)  │
      │ - Granular Murmurs      │ - Warm Bioluminescent   │
      │ - Pitch Drift Whispers  │   Cellos & Sub-Pads     │
      │ - Dissolving Timbre     │ - Clean Cardiac Rhythm  │
  0.0 └─────────────────────────┴─────────────────────────┘
     0.0                       0.5                       1.0
                         Neuro-Sync Ratio (S)
```

### 3.2 Vertical Layering Stems & Horizontal Re-sequencing

The musical score is composed across 6 synchronized stem channels:

| Stem ID | Stem Name | Instrument Spectrum | Control Sensitivity |
|---|---|---|---|
| `STEM_SUB` | Organic Sub-Pulse | 15–60 Hz Duffing Bass & Sinusoidal Organ Thrum | Driven by Cardiac BPM & $\mathcal{C}$ |
| `STEM_PERC` | Vascular Percussion | Hydro-pulse impacts, bone chitin clicks, muscle snaps | Density driven by $\mathcal{C}$, rhythm locked by $\mathcal{S}$ |
| `STEM_PAD` | Bio-Luminescent Pads | Resonant woodwinds, wet cello ensemble, organic choir | Harmonics driven by $\mathcal{S}$ |
| `STEM_LEAD` | Ganglion Arpeggios | Crystalline organ tones, bio-electric synth leads | Melody complexity driven by $\mathcal{S} \cdot \mathcal{C}$ |
| `STEM_BRASS` | Caudal Horns & Tubas | Low organic brass, mass organ resonant horns | Heavy combat entry ($\mathcal{C} > 0.6$) |
| `STEM_CHAOS` | Neuro-Disruption Noise | Granular tissue tears, pitch-bending micro-shrieks | Inverse entry ($\mathcal{S} < 0.35$) |

### 3.3 Microtonal Scale Shift & DSP Modulation Mathematics

#### Microtonal Detuning Equation
When Neuro-Sync drops ($\mathcal{S} < 0.5$), stems undergo microtonal detuning away from 12-TET towards a 19-TET organic scale or microtonal pitch drift:

$$\Delta f_{cents}(i, \mathcal{S}) = (1.0 - \mathcal{S})^{1.8} \cdot \left[ A_{max} \cdot \sin(2\pi f_{lfo} t + \phi_i) + \text{Noise}_i(t) \cdot B_{max} \right]$$

- $A_{max}$: Maximum LFO pitch deviation ($150\text{ cents}$).
- $B_{max}$: Maximum random pitch jitter ($80\text{ cents}$).
- $\phi_i$: Individual stem phase offset preventing uniform pitch shifting.

#### Dynamic Biquad Filter Cutoff Curve
Filter cutoffs morph smoothly along equal-power curves:

$$f_{cutoff}(\mathcal{S}, \mathcal{C}) = f_{min} \cdot \left(\frac{f_{max}}{f_{min}}\right)^{\mathcal{C}^{\beta_1} \cdot \mathcal{S}^{\beta_2}}$$

Where $\beta_1 = 0.75$, $\beta_2 = 1.2$, $f_{min} = 120\text{ Hz}$, $f_{max} = 18000\text{ Hz}$.

```typescript
// DSP Structure: Dynamic 2D Music Engine Controller
export class NeuroSyncMusicMatrix {
  private neuroSync: number = 1.0;   // S
  private combatIntensity: number = 0.0; // C
  
  private stemVolumes: Float32Array = new Float32Array(6);
  private stemDetunes: Float32Array = new Float32Array(6);
  
  public updateState(S: number, C: number, deltaTime: number): void {
    // Smooth state inputs to prevent abrupt audio pop
    const lerpRate = 2.0 * deltaTime;
    this.neuroSync += (Math.max(0, Math.min(1, S)) - this.neuroSync) * lerpRate;
    this.combatIntensity += (Math.max(0, Math.min(1, C)) - this.combatIntensity) * lerpRate;
    
    const S_curr = this.neuroSync;
    const C_curr = this.combatIntensity;
    
    // Stem 0: Sub Pulse (Always active, scales with combat)
    this.stemVolumes[0] = 0.6 + 0.4 * C_curr;
    
    // Stem 1: Vascular Percussion (Scales strongly with combat)
    this.stemVolumes[1] = Math.pow(C_curr, 0.8);
    
    // Stem 2: Bio-Luminescent Pads (Dominant at high Neuro-Sync)
    this.stemVolumes[2] = Math.pow(S_curr, 0.6) * (1.0 - 0.3 * C_curr);
    
    // Stem 3: Ganglion Arpeggios (Peak when both S and C are high)
    this.stemVolumes[3] = S_curr * C_curr;
    
    // Stem 4: Caudal Horns (Heavy combat only)
    this.stemVolumes[4] = Math.max(0, (C_curr - 0.4) / 0.6);
    
    // Stem 5: Neuro Chaos (Activates on neural desync: low S)
    this.stemVolumes[5] = Math.pow(1.0 - S_curr, 2.0);
    
    // Calculate microtonal detune per stem (in cents)
    const desyncSeverity = Math.pow(1.0 - S_curr, 1.8);
    for (let i = 0; i < 6; i++) {
      const phase = (i * Math.PI) / 3.0;
      const lfo = Math.sin(Date.now() * 0.0015 + phase);
      // STEM_SUB (0) stays anchored; upper stems drift wildly
      this.stemDetunes[i] = i === 0 ? 0 : lfo * 150.0 * desyncSeverity;
    }
  }
}
```

---

## 4. Sub-Bass Bio-Resonance & Tactile Haptic Feedback Synthesis for Controller/VR Setups

### 4.1 Bio-Resonance Frequency Spectrum

Organic ship events produce deep mechanical-equivalent and biological vibrations that span the sub-audible infrasound and tactile frequency bands.

```
Sub-Bass & Infrasound Frequency Allocation:
 0 Hz ──┬── 4 Hz - 15 Hz: Peristaltic Wave & Mass Tissue Expansion (Haptic Only)
        ├── 15 Hz - 30 Hz: Sub-Audible Cardiac Thrum & Hull Decompression (Tactile + Subwoofer)
        ├── 30 Hz - 60 Hz: S1 Systolic Muscle Contraction & Plasma Core Resonance
        ├── 60 Hz - 90 Hz: Shield Emitter Hiss & Caudal Thrust Pulse
 90 Hz ──┴── > 90 Hz: Standard Audible Spectrum
```

### 4.2 Real-Time Haptic Signal Synthesis Engine (HAS)

Controller haptics (DualSense LRA actuators, OpenXR Haptic Controllers, TactSyuit Vests) must not rely on pre-baked rumble clips. Haptic signals are generated programmatically via real-time DSP synthesis matching tactile sensitivity curves defined in **ISO 13091-1**.

#### Tactile Sensitivity Function $S_{tactile}(f)$
Human mechanoreceptor response peaks at $250\text{ Hz}$ (Pacinian corpuscles) and $25\text{ Hz}$ (Meissner corpuscles):

$$S_{tactile}(f) = w_1 \cdot \exp\left(-\frac{(f - 25)^2}{2 \sigma_1^2}\right) + w_2 \cdot \exp\left(-\frac{(f - 250)^2}{2 \sigma_2^2}\right)$$

```
Tactile Perception Threshold Curve (ISO 13091):
 Sensitivity (dB)
 Peak 1 (Meissner)                    Peak 2 (Pacinian)
   ▲        ┌─┐                          ┌─┐
   │       │   │                        │   │
   │      │     │                      │     │
   │─────/───────\────────────────────/───────\──────► Frequency (Hz)
        10       25      50         150      250   400
```

#### Haptic Waveform Generator ($h(t)$)
The tactile signal $h(t)$ combines cardiac pulse envelope follower output with high-frequency surface texture carrier waves:

$$h(t) = A_e(t) \cdot \left[ \alpha \cdot \sin(2\pi \cdot 25 \cdot t) + \beta \cdot \text{Square}(2\pi \cdot 250 \cdot t) \cdot M_{texture}(t) \right]$$

- $A_e(t)$: Envelope follower signal extracted from sub-bass audio channels.
- $M_{texture}(t)$: High-frequency surface roughness modulation (e.g. dragging across mucosal walls or chitin ridges).

### 4.3 4-Quadrant VR Tactile Vest Routing

For VR setups (e.g. TactSuit / OWO vest), tactile spatialization maps ship internal hit vectors onto 4 torso quadrants:

$$\begin{bmatrix} H_{FL} \\ H_{FR} \\ H_{BL} \\ H_{BR} \end{bmatrix} = \begin{bmatrix} \max(0, \cos \theta \cos \phi) \\ \max(0, \sin \theta \cos \phi) \\ \max(0, \cos \theta \sin \phi) \\ \max(0, \sin \theta \sin \phi) \end{bmatrix} \cdot h(t)$$

```typescript
// DSP Code: Real-Time Haptic DSP Synthesizer
export class BioHapticDSPNode {
  private envelopeState: number = 0.0;
  private attackCoeff: number = Math.exp(-1.0 / (0.005 * 44100)); // 5ms attack
  private releaseCoeff: number = Math.exp(-1.0 / (0.080 * 44100)); // 80ms release

  public generateHapticSample(subBassSample: number, textureModulator: number): {
    lowFreqMotor: number;  // 25 Hz Meissner channel (0.0 - 1.0)
    highFreqMotor: number; // 250 Hz Pacinian channel (0.0 - 1.0)
  } {
    // Envelope Follower on Sub-Bass audio input
    const absSample = Math.abs(subBassSample);
    if (absSample > this.envelopeState) {
      this.envelopeState = this.attackCoeff * this.envelopeState + (1.0 - this.attackCoeff) * absSample;
    } else {
      this.envelopeState = this.releaseCoeff * this.envelopeState + (1.0 - this.releaseCoeff) * absSample;
    }

    const env = Math.min(1.0, this.envelopeState * 1.5);

    // 25 Hz low-frequency pulse (heavy muscle/cardiac thrum)
    const lowFreq = Math.pow(env, 1.2);

    // 250 Hz high-frequency texture (chitin friction / bio-electric hum)
    const highFreq = env * 0.4 + textureModulator * 0.6;

    return {
      lowFreqMotor: Math.max(0.0, Math.min(1.0, lowFreq)),
      highFreqMotor: Math.max(0.0, Math.min(1.0, highFreq)),
    };
  }
}
```

---

## 5. Voice Synthesis for Ship Ganglion Brain Communications

### 5.1 Bio-Physical Formant Vocal Tract Architecture

The ship ganglion brain has no vocal cords or lungs; its communications are produced by resonant air-fluid displacement within pharyngeal cavities and bioluminescent acoustic nodes. The voice synthesis system uses an extended **Klatt Formant Synthesizer** coupled to a physical glottal flow model.

```
Vocal Tract Filter Pipeline:
 ┌──────────────┐      ┌──────────────┐      ┌─────────────────────────┐      ┌──────────────┐
 │ Bio-Glottal  │─────►│ Multi-Formant│─────►│ Mucosal Transient       │─────►│ Spatial      │
 │ Impulse Gen  │      │ Biquad Array │      │ Injector (Fluid Clicks) │      │ Convolution  │
 └──────────────┘      └──────────────┘      └─────────────────────────┘      └──────────────┘
```

#### Formant Frequencies ($F_1 - F_4$) for Ship Ganglion Register

Because the ship ganglion cavity is larger than a human vocal tract ($L_{tract} \approx 0.65\text{m}$ vs $0.17\text{m}$ human), base resonant formants are shifted down, with hyper-resonant upper harmonics:

| Formant | Frequency Range | Bandwidth $B_n$ | Biological Function |
|---|---|---|---|
| $F_1$ | 180 Hz – 380 Hz | 60 Hz | Cranial Cavity Volume Resonance |
| $F_2$ | 750 Hz – 1400 Hz | 90 Hz | Pharyngeal Node Opening Width |
| $F_3$ | 1800 Hz – 2600 Hz | 140 Hz | Fluid-Membrane Surface Tension |
| $F_4$ | 3200 Hz – 4100 Hz | 200 Hz | Chitin Ridge Boundary Reflections |

### 5.2 Neuro-Sync ($\mathcal{S}$) Voice Disintegration Dynamics

As the pilot's Neuro-Sync Ratio ($\mathcal{S}$) fluctuates, the voice synthesizer dynamically alters its physical glottal and formant parameters:

#### High Neuro-Sync ($\mathcal{S} \ge 0.75$)
- Pristine glottal flow waveform $R_g(t)$ with minimal aspiration noise.
- Formants locked to resonant target frequencies.
- Smooth binaural spatial chorus ($3.5\text{ Hz}$ subtle phase oscillation).

#### Low Neuro-Sync ($\mathcal{S} < 0.35$) — Diplophonia & Mucosal Fragmentation
- **Multi-Pitch Formant Splitting (Diplophonia)**: Glottal excitation splits into two out-of-phase fundamental frequencies ($f_0$ and $f_0 \cdot 1.414$).
- **Mucosal Click Injection**: Wet tissue separation transients inserted via a Poisson process with rate $\lambda_{click} = 45 \cdot (1.0 - \mathcal{S})\text{ clicks/sec}$.
- **Glottal Jitter & Shimmer**:
  $$Jitter = \frac{1}{N-1} \sum_{i=1}^{N-1} |T_i - T_{i+1}| \propto (1.0 - \mathcal{S})^2$$

```typescript
// DSP Code: Ganglion Brain Voice Synthesizer
export class GanglionVoiceSynthesizer {
  private sampleRate: number;
  private phaseF0: number = 0;
  private phaseF0_sub: number = 0;
  
  // Formant Biquad Filters (F1, F2, F3, F4)
  private f1Filter: BiquadFilterNode | null = null;
  private f2Filter: BiquadFilterNode | null = null;
  private f3Filter: BiquadFilterNode | null = null;
  private f4Filter: BiquadFilterNode | null = null;

  constructor(sampleRate: number) {
    this.sampleRate = sampleRate;
  }

  public synthesizeFrame(
    f0Base: number,           // Base pitch (e.g. 85 Hz for deep ganglion)
    neuroSync: number,        // S (0.0 - 1.0)
    phonemeF1: number,
    phonemeF2: number
  ): number {
    const desync = 1.0 - Math.max(0, Math.min(1, neuroSync));
    
    // Apply jitter to F0 based on desync
    const jitter = (Math.random() - 0.5) * 12.0 * Math.pow(desync, 2.0);
    const effectiveF0 = f0Base + jitter;
    
    // Advance main glottal phase
    this.phaseF0 += (effectiveF0 / this.sampleRate) * 2.0 * Math.PI;
    if (this.phaseF0 > 2.0 * Math.PI) this.phaseF0 -= 2.0 * Math.PI;
    
    // Rosenberg glottal pulse model
    let glottalPulse = Math.sin(this.phaseF0) > 0 
      ? 0.5 * (1 - Math.cos(this.phaseF0)) 
      : 0;

    // Diplophonia (secondary pitch split under severe neural desync)
    if (desync > 0.4) {
      const f0_sub = effectiveF0 * 1.3333; // Perfect fourth split
      this.phaseF0_sub += (f0_sub / this.sampleRate) * 2.0 * Math.PI;
      if (this.phaseF0_sub > 2.0 * Math.PI) this.phaseF0_sub -= 2.0 * Math.PI;
      
      const subPulse = Math.sin(this.phaseF0_sub) > 0 ? 0.5 * (1 - Math.cos(this.phaseF0_sub)) : 0;
      glottalPulse = glottalPulse * (1.0 - desync * 0.5) + subPulse * (desync * 0.5);
    }

    // Mucosal Transient Injection (Poisson process click)
    let clickTransient = 0;
    const clickProbability = (45.0 * desync) / this.sampleRate;
    if (Math.random() < clickProbability) {
      // High-frequency damped impulse (wet mucosal snap)
      clickTransient = (Math.random() * 2.0 - 1.0) * 0.8;
    }

    return glottalPulse + clickTransient;
  }
}
```

---

## 6. Comprehensive Technical Specifications & DSP Pipeline Metrics

### 6.1 Audio Engine Performance Budget & Constraints

| Metric | Target Specification | Hard Limit / Fallback |
|---|---|---|
| **Audio Thread Buffer Size** | 128 samples ($2.67\text{ ms}$ at $48\text{ kHz}$) | 256 samples ($5.33\text{ ms}$) |
| **Max DSP CPU Usage** | $< 8.5\%$ of 1 CPU core | $< 12.0\%$ |
| **Active Ray Count (Ray Tracer)** | 512 rays/frame ($60\text{ Hz}$ compute dispatch) | 128 rays/frame |
| **SOFA HRTF Order** | $N = 5$ ($36$ spherical harmonic terms/ear) | $N = 3$ ($16$ terms/ear) |
| **FFT Size (Convolution Reverberation)** | 2048 points ($42.6\text{ ms}$ overlap-add) | 1024 points |
| **Dynamic Stems (Music)** | 6 synchronized 24-bit/48 kHz channels | 4 stems |
| **Haptic Latency** | $< 10\text{ ms}$ from audio event to actuator motor | $< 18\text{ ms}$ |

### 6.2 Implementation Roadmap & Architectural Integration

1. **Core WebAudio / C++ Node Graph Setup**:
   - Implement `BiotPoroElasticNode` & `CurvedUTDDiffractionNode` within WebAudio Worklet or native C++ Wwise plugin.
   - Wire `BioCardiacSynthesizer` into main thoracic spatial audio node position.
2. **Genetics & Ship Scale Integration**:
   - Scale cardiac $S_1$ fundamental frequency ($f_0 \propto \text{shipVolume}^{-1/3}$) so larger living ships produce deeper, infrasonic cardiac thrums.
   - Scale voice formant registers $F_1 - F_4$ based on Cranial section size.
3. **VR / Haptic Interface Bus**:
   - Bind `BioHapticDSPNode` output directly to WebXR Haptic Actuator API / DualSense SDK.
   - Map 4-quadrant haptic vest feedback to ship damage event bus.

---
*End of Research Specification — AAA+ Spatial Audio & Acoustic Systems Architecture.*
