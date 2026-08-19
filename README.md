# 🌌 BioGenesis-X

> **AAA+ 3D Biopunk Starship Builder & Void Flight Combat Simulator**  
> *Developed by Pumilio Studios using Godot Engine 4.7*

[![Godot 4.7](https://img.shields.io/badge/Made%20with-Godot%204.7-478CBF?style=flat&logo=godot%20engine&logoColor=white)](https://godotengine.org)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen.svg)]()

---

## 🚀 Overview

**BioGenesis-X** is an enterprise-grade 3D biopunk space simulation title. Set in deep space beyond the Heliosphere, players pilot and customize colossal self-sustaining organic starships (**Void-Fauna**) bonded through the *Covenant of Symbiosis*.

Unlike traditional space games with static metal hulls, every ship in BioGenesis-X is a living biological organism powered by 5 closed-loop organ pipelines, real-time physiological telemetry (ECG heart rate, hemolymph pressure, bio-moss oxygenation yield), procedural NURBS/SurfaceTool 3D mesh generation, procedural audio synthesis, and 3D Wavefront `.OBJ` model export capabilities.

---

## 🧬 Key Features & Architectural Subsystems

### 1. 3D Procedural Bio-NURBS Mesh Engine ([`res://scripts/ProceduralBioMesh.gd`](file:///Users/mey/BioGenesis-X/scripts/ProceduralBioMesh.gd))
- Generates 3D living organic ship geometries in real-time using Godot's `SurfaceTool`.
- **Anatomical Structure Generation**:
  - Segmented Vertebral Spine Column.
  - Overlapping Chitin Carapace Armor Plates with nacre iridescence.
  - Exothermal Siphon Exhaust Vent Nozzles.
  - Multispectral Eye Pod Clusters with lens Fresnel glow.
  - Flank Vascular Conduits with traveling bioluminescent pulse waves.
  - Flexible Thoracic Appendages / Spines.
- **5 Void-Fauna Archetypes**:
  1. **Apex Hive Leviathan** (*Abyssocetus apex*): 16 segments, 28m habitat carrier.
  2. **Neuro-Spore Interceptor** (*Neuro-Spore interceptor*): 4 segments, high-agility strike symbiont.
  3. **Chitinous Void Harvester** (*Harvester chitinous*): 10 segments, 18m ore mining dreadnought.
  4. **Abyssal Symbiont Frigate** (*Symbiont abyssalis*): 8 segments, active chromatophore stealth vessel.
  5. **Viral Colony Carrier** (*Colony carrier-spore*): 12 segments, fleet support brood-mother.

### 2. 5 Closed-Loop Organ Telemetry Pipelines ([`res://scripts/OrganTelemetry.gd`](file:///Users/mey/BioGenesis-X/scripts/OrganTelemetry.gd))
Derived directly from the original IP specification:
1. **Bio-Plasma Power & Propulsion**: Ingestion Gizzard $\rightarrow$ Electrolysis Gland $\rightarrow$ Muscular Bladder (140 Bar) $\rightarrow$ Caudal Siphon Vents (1,700 kN) & Disruptors (450 MW).
2. **Hemolymph Circulation & Thermal Regulation**: Peristaltic Heart Core (68 BPM) $\rightarrow$ Hemolymph Atrium (18.5 Bar) $\rightarrow$ Central Aorta $\rightarrow$ Dorsal Spiracle Gill Vents (820 W/m²).
3. **Nervous Cyber-Synaptic System**: Ganglion Brain Core $\rightarrow$ Graphene Neuro-Link (95.0%–99.9% Sync) $\rightarrow$ Eye Pods & Spinal Tendons (120 m/s).
4. **Endosymbiotic Life Support**: Comet Ice Gizzard $\rightarrow$ Bio-Moss Carpet (420 L/min O₂) $\rightarrow$ Crew Quarters (1.0 atm).
5. **Exoskeleton & Nanite Defense**: Vertebrae Column $\rightarrow$ Chitin Armor Plates (85 Gy/hr) $\rightarrow$ Sub-Dermal Bio-Nanite Bed (1.2 m³/s) $\rightarrow$ Shield Emitters.

### 3. 6-DOF 3D Space Flight & Combat Simulation ([`res://scripts/FlightController.gd`](file:///Users/mey/BioGenesis-X/scripts/FlightController.gd))
- ** Newtonian Space Flight**: Pitch, yaw, roll, strafe, reverse siphons, and bio-hydro pulse inertia dampener toggle.
- **Bio-Boost Surge**: Consumes bio-plasma fuel reserve with camera FOV scaling and acceleration screen shake.
- **Wave Engine (Alcubierre In-System Transit)** ([`res://shaders/wave_engine.gdshader`](file:///Users/mey/BioGenesis-X/shaders/wave_engine.gdshader), [`res://scripts/WaveEngineFX.gd`](file:///Users/mey/BioGenesis-X/scripts/WaveEngineFX.gd)): FTL-style in-system supercruise based on the Alcubierre metric. Contracts spacetime ahead of the ship and expands it behind, riding a wave inside a flat-region warp bubble. A translucent grid plane materializes around the hull — the front deforms and dips down (spacetime contraction), the back raises up (spacetime expansion) — using the Alcubierre `tanh` shape function and York time displacement. 5-state machine: `OFF → CHARGING (2s spool-up) → ENGAGED (38 km/s) → DISENGAGING → INHIBITED`.
- **Tactical Weapon Systems** ([`res://scripts/WeaponSystem.gd`](file:///Users/mey/BioGenesis-X/scripts/WeaponSystem.gd)): Dual Bio-Plasma Disruptors, Defensive Spore Cloud Dispersal, Dorsal Spiracle Heat Venting, and 3-stage Conical Target Lock-On.
- **Procedural Void Environment** ([`res://scripts/AsteroidField.gd`](file:///Users/mey/BioGenesis-X/scripts/AsteroidField.gd)): 3D asteroid belt volume, procedural FBM nebula skybox shader, volumetric bio-fog, and orbiting target drones.

### 4. Real-Time Procedural Audio Synthesizer ([`res://scripts/BioAudioSynth.gd`](file:///Users/mey/BioGenesis-X/scripts/BioAudioSynth.gd))
- Programmatic audio synthesis via `AudioStreamGenerator`:
  - Thumping dual-pulse organic heartbeat.
  - Filtered brown-noise hydro-pulse siphon engine roar.
  - Micro-friction chitin creaks & hydraulic hiss.
  - FM frequency-swept bio-plasma cannon discharge.
  - Sub-harmonic deep space void drone.
  - Resonant membrane bio-shield impact thud.

### 5. 3D Model Wavefront ASCII .OBJ Exporter ([`res://scripts/ShipExporter.gd`](file:///Users/mey/BioGenesis-X/scripts/ShipExporter.gd))
- Exports any active 3D ship configuration directly to `.obj` files in `user://exports/bio_ship_<archetype>.obj`.
- Outputs full vertex lists (`v`), texture coordinates (`vt`), normal vectors (`vn`), and face definitions (`f`).

### 6. Dual-Mode `godot-mcp` Pro Bridge ([`res://addons/godot_mcp`](file:///Users/mey/BioGenesis-X/addons/godot_mcp))
- Integrated Model Context Protocol (MCP) server providing in-editor live TCP control over port 6505 and headless CLI execution for AI agentic loops.

---

## 📁 Project Directory Structure

```text
BioGenesis-X/
├── project.godot                     # Godot 4.7 Main Project Configuration
├── icon.svg                          # Biopunk Icon
├── addons/
│   └── godot_mcp/                    # In-Editor MCP Dual-Bridge Server (Port 6505)
├── scenes/
│   ├── main_menu.tscn                # Main Title Menu
│   ├── ship_builder.tscn             # 3D Starship Builder Lab
│   ├── space_flight.tscn             # 3D Space Flight & Combat Arena
│   ├── organ_inspector.tscn          # 5 Organ Pipeline Topology Inspector
│   └── pause_menu.tscn               # Pause Overlay Menu
├── scripts/
│   ├── BioManager.gd                 # Autoload: Game State & Archetype Manager
│   ├── OrganTelemetry.gd             # Autoload: Closed-Loop Telemetry & ECG Generator
│   ├── BioAudioSynth.gd              # Autoload: Real-Time Audio Synthesizer
│   ├── ProceduralBioMesh.gd          # 3D Organic SurfaceTool Mesh Builder
│   ├── FlightController.gd           # 6-DOF 3D Newtonian Flight Physics & Wave Engine
│   ├── WaveEngineFX.gd               # Alcubierre Warp Plane Visual Effect Controller
│   ├── WeaponSystem.gd               # Disruptors, Spore Clouds & Lock-On
│   ├── AsteroidField.gd              # Procedural Space Environment & Drones
│   ├── ShipExporter.gd               # Wavefront ASCII .OBJ Exporter
│   ├── ECGGraph.gd                   # Real-Time Oscilloscope HUD Widget
│   ├── FlightHUDUI.gd                # Tactical Combat Flight HUD Overlay
│   ├── ShipBuilderUI.gd              # 3D Ship Builder Controls & Sliders
│   ├── OrganInspectorUI.gd           # Organ System Pipeline UI Visualizer
│   ├── MainMenuUI.gd                 # Main Menu Screen
│   └── PauseMenuUI.gd                # In-Game Pause Menu Controller
└── shaders/
    ├── chitin_organic.gdshader       # Biopunk Nacre Iridescent Carapace Shader
    ├── bioluminescence.gdshader      # Pulsing Glow & Traveling Wave Shader
    ├── plasma_thruster.gdshader      # Exothermal Siphon Vent Plume Shader
    ├── space_nebula.gdshader         # Deep-Space FBM Nebula & Twinkle Sky Shader
    └── wave_engine.gdshader          # Alcubierre Warp Plane Grid Shader
```

---

## 🎮 How to Play & Run

### 1. Launch in Godot 4 Editor
```bash
godot --editor --path /Users/mey/BioGenesis-X
```

### 2. Run Main Game Scene
```bash
godot --path /Users/mey/BioGenesis-X res://scenes/main_menu.tscn
```

### 3. Headless Verification Test
```bash
godot --headless --path /Users/mey/BioGenesis-X -s res://scripts/export_all_archetypes.gd
```

---

## ⌨️ Flight & Gameplay Controls

| Action | Input Key / Mouse |
| :--- | :--- |
| **Pitch & Yaw** | Mouse Motion / Arrow Keys |
| **Roll Left / Right** | `Q` / `E` |
| **Forward / Reverse** | `W` / `S` |
| **Horizontal Strafe** | `A` / `D` |
| **Vertical Strafe** | `Space` (Up) / `Ctrl` (Down) |
| **Bio-Boost Surge** | `Shift` (Hold) |
| **Inertia Dampener Toggle** | `Z` |
| **Primary Disruptors** | `Left Mouse Click` |
| **Bio-Spore Cloud** | `Right Mouse Click` |
| **Organ Inspector UI** | `Tab` |
| **Pause Game** | `Escape` |

---

## 📄 License & Credits

Developed by **Pumilio Studios**  
Engine Architecture & Agentic Loop Orchestration by **Ciel Intelligence System**  
Built with **Godot Engine 4.7** (Official Open Source MIT License)
