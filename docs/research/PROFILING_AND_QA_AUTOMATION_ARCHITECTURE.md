# AAA+ QA Automation & Performance Profiling Architecture — BioGenesis

**Document Status**: APPROVED SPECIFICATION  
**Author**: Subagent 10 (AAA+ QA Automation & Performance Profiling Architect)  
**Target Platform**: BioGenesis Engineering & Procedural Mesh Engine  
**Runtime Environment**: TypeScript · React 19 · Vite 6 · Three.js (WebGL2) · Express · Playwright  

---

## 1. Executive Summary & Architectural Scope

BioGenesis is a complex biopunk living-ship engineering simulator incorporating real-time procedural mesh generation (SDFs, Marching Cubes, Surface Nets, Dual Contouring, ARAP deformation, L-Systems, reaction-diffusion texturing), a 3D force-field repulsion organ placement solver, biological organ system topology, and a bio-neural compute pipeline based on Haller's rule, Jerison allometry, and the Yerkes-Dodson inverted-U efficiency curve.

To achieve AAA+ quality, stability, and framerate consistency, BioGenesis requires an automated quality assurance and profiling architecture. This document defines the exact technical specifications for:
1. **Automated Continuous Integration (CI) Performance Benchmarking** (60 FPS / 120 FPS frame budgets).
2. **Headless Testing Suites** for organ intersection auditing, force-field solver convergence, and procedural SDF grid bounds.
3. **Real-time VRAM/RAM Memory Leak Detection** and V8 heap snapshot analysis.
4. **Telemetry Collection Pipeline** tracking pilot neuro-sync errors, organ failure states, and micro-stutters.
5. **Static Gate Compliance Validation** via `tsc --noEmit`, build verification, and headless CLI test runners.

---

## 2. Automated CI Performance Benchmarking

### 2.1 Frame Budget Allocation Matrix

For AAA+ responsiveness, BioGenesis mandates strict frame time budgets split between CPU simulation (force-field solver, neural compute, vascular network generation) and GPU rendering (Three.js draw calls, shader evaluation, reaction-diffusion texture updates).

| Metric / Target | 60 FPS Target (Standard Display) | 120 FPS Target (High Refresh Display) | CI Regression Failure Threshold |
| :--- | :--- | :--- | :--- |
| **Total Frame Time Budget** | **16.67 ms** | **8.33 ms** | > 16.67 ms (60 FPS) / > 8.33 ms (120 FPS) |
| **CPU Simulation Budget** | 5.50 ms | 2.75 ms | > +10% over baseline |
| — *Force-Field Repulsion Solver* | 1.80 ms (35-45 passes) | 0.90 ms | > 2.50 ms |
| — *Neural Compute & Yerkes-Dodson* | 0.50 ms | 0.25 ms | > 0.80 ms |
| — *SDF & Organ Blend Evaluation* | 2.20 ms | 1.10 ms | > 3.00 ms |
| — *Scripting / React Re-renders* | 1.00 ms | 0.50 ms | > 1.50 ms |
| **GPU Render Budget** | 11.17 ms | 5.58 ms | > +15% over baseline |
| — *Geometry Draw Calls & Shadows* | 6.00 ms | 3.00 ms | > 7.50 ms |
| — *Bioluminescent Reaction-Diffusion* | 2.50 ms | 1.25 ms | > 3.50 ms |
| — *Post-Processing / Shaders* | 2.67 ms | 1.33 ms | > 3.50 ms |
| **Frame Spike Ceiling (p99)** | < 33.33 ms (1 dropped frame) | < 16.67 ms (1 dropped frame) | > 2 consecutive dropped frames |

### 2.2 CI Performance Runner Architecture

The automated performance suite runs headlessly in CI using Playwright with WebGL passthrough (`--enable-unsafe-webgpu`, `--use-gl=angle` or SwiftShader fallback).

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                      Playwright Headless CI Runner                      │
 └────────────────────────────────────┬────────────────────────────────────┘
                                      │
           ┌──────────────────────────┴──────────────────────────┐
           ▼                                                     ▼
┌─────────────────────┐                               ┌─────────────────────┐
│ Frame Time Sampling │                               │ CPU Execution Profil│
│ (PerformanceObserver│                               │ (v8 Profiler API /  │
│  longtask / fps)    │                               │  performance.mark)  │
└──────────┬──────────┘                               └──────────┬──────────┘
           │                                                     │
           └──────────────────────────┬──────────────────────────┘
                                      │
                                      ▼
             ┌──────────────────────────────────────────────────┐
             │ Benchmark Aggregator & Regression Gate Evaluator │
             │  - Calculates p50, p95, p99 frame times          │
             │  - Compares against baseline.json metrics        │
             │  - Triggers failure if p95 exceeds budget by >5% │
             └──────────────────────────────────────────────────┘
```

#### Benchmark Execution Protocol:
1. **Scenario 1: Baseline Idle Rendering** — Ship at rest with active bioluminescence textures; 1,000 frames sampled.
2. **Scenario 2: Heavy Organ Drag & Solver Update** — Drag primary organ across hull causing real-time solver recalculation (`SOLVER_PASSES = 45`) and blend bridge mesh regeneration (`BlendBridgeManager`).
3. **Scenario 3: Maximum Pipeline Complexity** — 30+ organs, 5 habitats, 19 conduits, full reaction-diffusion map active, command room window cuts rendered.

---

## 3. Headless Testing Suites

### 3.1 Organ Intersection & Placement Audit Suite

The force-field solver in `Canvas3D.tsx` enforces spatial separation, but actual mesh extents (e.g. rib spurs sweeping 2.5m, dangling tentacles) exceed center-point radii. The headless audit suite validates anatomical exclusion layers without requiring a DOM/browser instance.

#### 5-Section Anatomical Placement Bands
- **Cranial**: $U \in [0.02, 0.15]$ (Eyes / Ocular Pods, Brain, Neural Ganglia)
- **Neck / Upper Trunk**: $U \in [0.15, 0.30]$ (Neural Cluster, Dorsal Sail)
- **Thoracic**: $U \in [0.30, 0.65]$ (Heart, Plasma Gland, Habitats, Ribs, Spiracles, Pectoral Fins, Landing Limbs)
- **Caudal**: $U \in [0.65, 0.85]$ (Spores, Tentacles, Caudal Manifold)
- **Tail Tip**: $U \in [0.85, 0.98]$ (Caudal Fluke, Vent Nozzles)

#### Audit Exclusion Verification Layers
1. **Threading Elements** (`isThreadingElement`): Skip conduits, ducts, feeds, lines, tendons, fibers, arteries, veins, blend bridges.
2. **Direct Exclusions**:
   - Plasma gland $\leftrightarrow$ neural ganglion (nervous system interfaces all organs).
   - Plasma gland $\leftrightarrow$ spiracle / rib / spore / tentacle / ocular (internal vs surface).
   - Spiracle / Ocular / Spore $\leftrightarrow$ habitat (hull-skin sharing).
3. **Anatomical Expected Pairs** (`isExpectedPair`): Vertebra + spinal cord, artery + heart, nozzle + cowl, spiracle + rib, brain + neurolink, heart + atrium, gland + bladder, disruptor + plasma trunk, appendage + appendage, vertebra + vertebra, thoracic organs.
4. **Distance-Aware Internal vs Surface Exclusion**: Internal organs vs surface organs are excluded when center distance $d > 0.5 \times (r_A + r_B)$.

### 3.2 Force-Field Collision Solver Stability Suite

Tests force-field convergence and bilateral symmetry invariants in `Canvas3D.tsx`:
- **Iterative Repulsion Passes**: Enforces `SOLVER_PASSES = 45` iterations.
- **Adaptive Spatial Grid Size**: Verifies $GRID\_SIZE = \text{clamp}(1.5, 4.0, \min(r_{\text{clearance}}) \times 2.0)$.
- **Locked Partner Invariance**: Primary organs (starboard / sideIdx 0) move via force field; locked partners (port / sideIdx > 0) receive exact mirrored $V$ ($V_{\text{port}} = 1.0 - V_{\text{starboard}}$) and identical $U$.
- **Convergence Metric**: Failure if net movement per organ $\Delta U > 0.001$ after pass 45 (detects solver oscillation).

### 3.3 Procedural Mesh & SDF Grid Bounds Suite

Direct headless verification of implicit geometry algorithms:
- **SDF Range & Continuity** (`src/utils/sdf.ts`): Tests smooth-min blending ($smin(a, b, k)$) across gradient boundaries; verifies zero NaN/Infinity return values for invalid evaluation coordinates.
- **Marching Cubes Isosurface Extraction** (`src/utils/marchingCubes.ts`): Verifies canonical 256-entry Paul Bourke triangle lookup table; checks exported `BufferGeometry` for manifold closure (no unshared edges) and non-zero normal vectors.
- **Dual Contouring Sharp Feature Preservation** (`src/utils/dualContouring.ts`): Quadratic Error Function (QEF) solver validation for crystalline structures (disruptor glands, chitin vertebrae).
- **Subdivision Surface Creases** (`src/utils/subdivision.ts`): Catmull-Clark subdivision dihedral angle crease detection and Taubin shrinkage-free Laplacian smoothing verification.

---

## 4. Real-time VRAM/RAM Memory Leak Detection

### 4.1 GPU VRAM & Three.js Disposal Audit

Three.js requires manual GPU resource deallocation. The VRAM leak detector hooks into Three.js rendering loops to audit memory disposal during ship rebuilds and organ mutations.

```typescript
export interface VRAMMemorySnapshot {
  geometries: number;
  textures: number;
  programs: number;
  totalVRAMBytesEstimate: number;
}

export class VRAMLeakAuditor {
  private baselineSnapshot: VRAMMemorySnapshot | null = null;

  public captureSnapshot(renderer: THREE.WebGLRenderer): VRAMMemorySnapshot {
    const info = renderer.info.memory;
    const programs = renderer.info.programs?.length || 0;
    return {
      geometries: info.geometries,
      textures: info.textures,
      programs,
      totalVRAMBytesEstimate: this.estimateVRAMUsage(renderer),
    };
  }

  public assertNoLeak(current: VRAMMemorySnapshot, tolerance: number = 0): void {
    if (!this.baselineSnapshot) return;
    if (current.geometries > this.baselineSnapshot.geometries + tolerance) {
      throw new Error(`[VRAM Leak] Geometry count leaked: expected <= ${this.baselineSnapshot.geometries}, got ${current.geometries}`);
    }
    if (current.textures > this.baselineSnapshot.textures + tolerance) {
      throw new Error(`[VRAM Leak] Texture count leaked: expected <= ${this.baselineSnapshot.textures}, got ${current.textures}`);
    }
  }
}
```

#### Disposal Verification Checklist:
- `geometry.dispose()` called on all replaced SDF/Marching Cubes meshes.
- `material.dispose()` and `texture.dispose()` called on reaction-diffusion canvas data textures.
- `TransformControls` detached from `shipGroup` prior to clearing scene nodes.

### 4.2 V8 Engine Heap Snapshot & Retainer Tree Tracking

Automated RAM memory leak detection runs via Node.js / Playwright using `v8.getHeapSnapshot()`:
- **Leak Benchmark**: Re-render ship 500 times with random organ placements.
- **Max Heap Growth Ceiling**: $< 5.0\text{ MB}$ total growth after garbage collection trigger (`window.gc()`).
- **Retainer Inspection**: Automatically detects detached `HTMLCanvasElement` nodes, orphaned Three.js `Object3D` instances, and uncleared `requestAnimationFrame` handle callbacks.

---

## 5. Telemetry Collection Pipeline Architecture

### 5.1 Pilot Neuro-Sync Error & Efficiency Curve Tracking

The bio-neural compute model (`src/utils/neuralCompute.ts`) computes brain mass, Encephalization Quotient (EQ), nerve conduction delays, and organ compute efficiency based on the Yerkes-Dodson inverted-U curve.

$$\text{EQ} = \text{clamp}\left(7.0 \times \left(\frac{V_{\text{ref}}}{V_{\text{ship}}}\right)^{1/3}, 3.0, 7.0\right)$$
$$E_{\text{brain}} = 0.12 \times V_{\text{ship}}^{0.67} \times \text{EQ}$$
$$\text{Supply Ratio} = \frac{\text{Available Compute (bits/s)}}{\text{Total Organ Compute Demand}}$$

#### Neuro-Sync Telemetry Metric Classification:

```
Efficiency Curve (Yerkes-Dodson)
 1.20+ ┌───────────────────────────┐ Excitotoxicity Overstimulation (Drop in Efficiency)
       │       /───────────\       │
 1.00  ├──────/─────────────\──────┤ Normal Operational Range (100% Efficiency)
       │     /               \     │
 0.50  ├────/                 \────┤ Heavy Performance Loss (20%-50% Efficiency)
       │   /                       │
 0.25  ├──/                        └── Shutdown State (0% Efficiency / Organ Failure)
       └──┴──────┴──────┴──────┴───
         0.25   0.50   1.00   1.20+   Supply Ratio
```

- **Neuro-Sync Error Flags**:
  - `ERR_NEURAL_SHUTDOWN`: Supply ratio $< 0.25$ (organ completely unpowered).
  - `ERR_NEURAL_STRAIN`: Brain metabolic cost $> 25\%$ of total ship energy budget.
  - `ERR_NEURAL_EXCITOTOXICITY`: Supply ratio $> 1.20$ (overclocked state past safe duration).
  - `ERR_AXON_LATENCY_SPIKE`: Conduction delay $> 15\text{ ms}$ over spinal axon cord ($v = 120\text{ m/s}$).

### 5.2 Organ Failure & Metabolic Health Telemetry

Monitors real-time organ operational states:
- **Thermal Overload**: Plasma gland output exceeding heat dissipation capacity.
- **Vascular Blockage**: Fluid velocity drop in bi-directional vascular loop conduits.
- **Structural Integrity Breach**: Hull stress exceeding carapace yield tolerance.

### 5.3 Frame Stutter & Micro-Lag Detection

Telemetry collector logs render stutters in real time via high-resolution timing:
- **Frame Stutter Event**: Any individual frame exceeding $24.0\text{ ms}$ (60 FPS mode) or $12.0\text{ ms}$ (120 FPS mode).
- **GC Correlation**: Correlates frame stutters with V8 garbage collection pauses using `PerformanceObserver` entry type `gc`.

### 5.4 End-to-End Telemetry Pipeline Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Client Telemetry Engine                           │
│  ┌─────────────────────────┐   ┌───────────────────┐   ┌─────────────────┐  │
│  │ NeuroSyncMonitor        │   │ OrganHealthLogger │   │ FrameStutterRec │  │
│  └───────────┬─────────────┘   └─────────┬─────────┘   └────────┬────────┘  │
└──────────────┼───────────────────────────┼──────────────────────┼───────────┘
               │                           │                      │
               └───────────────────────────┼──────────────────────┘
                                           ▼
                       ┌───────────────────────────────────────┐
                       │ RingBufferQueue (Max 1,000 Events)    │
                       └───────────────────┬───────────────────┘
                                           │ (Batched every 5s / Web Worker)
                                           ▼
                       ┌───────────────────────────────────────┐
                       │ Express Telemetry Endpoint            │
                       │ POST /api/telemetry (gzip compressed) │
                       └───────────────────┬───────────────────┘
                                           │
                                           ▼
                       ┌───────────────────────────────────────┐
                       │ Telemetry TelemetryPanel Dashboard    │
                       │  - Live Neuro-Sync Error Graph        │
                       │  - FPS & Stutter Distribution         │
                       │  - Organ Failure Alert Feed           │
                       └───────────────────────────────────────┘
```

---

## 6. Static Gate Compliance & Continuous Integration Pipeline

### 6.1 Static Code Quality & Type Safety Verification

BioGenesis relies on strict static typing as the primary correctness gate:
- **Type Checker**: `tsc --noEmit` (Must pass with 0 errors).
- **Production Build**: `vite build` (Must complete clean bundle generation).
- **Symmetry & Math Suite**: `npx tsx src/tests/symmetryTest.ts` (Headless bounding box and V-coordinate mirror verification).

### 6.2 GitHub Actions Automated CI Workflow (`.github/workflows/ci.yml`)

```yaml
name: BioGenesis AAA+ QA & Profiling CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  static-gate:
    name: Static Type & Build Gate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - name: TypeScript Static Check
        run: npm run lint
      - name: Production Bundle Build
        run: npm run build
      - name: Headless Symmetry Test Suite
        run: npm run test:symmetry

  performance-benchmark:
    name: 60/120 FPS Performance & VRAM Leak Audit
    needs: static-gate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - name: Install Playwright & Browsers
        run: npx playwright install --with-deps chromium
      - name: Run Headless WebGL Performance Benchmarks
        run: npx tsx src/tests/perfBenchmark.ts
      - name: Run VRAM & Heap Memory Leak Audit
        run: npx tsx src/tests/memoryLeakAudit.ts
```

---

## 7. Summary Table of QA & Profiling Technical Specifications

| Domain | Key Parameter / Rule | Target Specification | Automated Verification Suite |
| :--- | :--- | :--- | :--- |
| **60 FPS Budget** | Total Frame Time | $\le 16.67\text{ ms}$ (11.17ms GPU, 5.5ms CPU) | Playwright Performance Benchmark Runner |
| **120 FPS Budget** | Total Frame Time | $\le 8.33\text{ ms}$ (5.58ms GPU, 2.75ms CPU) | Playwright Performance Benchmark Runner |
| **Force Solver** | Pass Count & Spatial Grid | 45 passes, $GRID\_SIZE \in [1.5, 4.0]$ | Headless Solver Stability Suite |
| **Organ Placement** | 5 Hull Bands | Cranial, Neck, Thoracic, Caudal, Tail Tip | Organ Intersection Audit Suite |
| **VRAM Leaks** | Disposable Resources | 0 leaked geometries/textures on rebuild | Three.js VRAM Auditor (`renderer.info`) |
| **RAM Leaks** | V8 Heap Growth | $< 5.0\text{ MB}$ growth per 500 mutations | V8 Heap Snapshot Comparison (`v8.getHeapSnapshot`) |
| **Neuro-Sync** | Yerkes-Dodson Curve | Supply Ratio $[0.50, 1.20]$ optimal | Client Telemetry Ring Buffer (`/api/telemetry`) |
| **Static Gate** | TypeScript Strictness | `tsc --noEmit` cleanly (0 errors) | CI Static Gate Pipeline |

---
*Report stored in mempalace memory drawer #56286. Ready for integration into BioGenesis codebase.*
