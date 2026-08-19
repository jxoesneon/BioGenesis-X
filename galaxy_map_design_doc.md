# AAA+ Galaxy Map Design Document

## Vision
A breathtaking, highly interactive 3D Galaxy Map for BioGenesis-X, inspired by Mass Effect, No Man's Sky, and Elite Dangerous. It must feel diegetic, premium, and astronomically accurate based on our Lin-Shu Spiral Density Wave model.

## 1. Graphics & Rendering (Graphics Council)
- **3D Star Cloud**: Thousands of stars rendered efficiently (e.g., using `MultiMeshInstance3D` or point cloud shaders).
- **Spectral Colors**: Stars must be colored accurately based on their Harvard Spectral Class (O, B, A, F, G, K, M).
- **Galactic Core & Nebula Volumetrics**: A glowing core and subtle spiral arm dust clouds.
- **Hyperlane Connections**: Subtle glowing lines connecting nearby navigable star systems.

## 2. UI / UX & Interaction (UX Council)
- **Interactive Star Nodes**: Clicking a star smoothly focuses the camera on it and opens an information panel.
- **Premium Information Panel**: 
  - System Name (e.g., ALDER-7149)
  - Spectral Class & Luminosity
  - Planetary Count & Resources
  - Threat Level / Dominant Faction
- **Typography & Styling**: Clean, futuristic sans-serif fonts, glassmorphism backdrops, and cyan/amber glowing accents.
- **Warp/Wave Engine Trigger**: A prominent "ENGAGE WAVE-RIDE" button to initiate travel to the selected system.

## 3. Core Architecture & Navigation (Systems Council)
- **Galaxy Map Camera**: A 6-DOF tactical orbiting camera (Pan, Zoom, Orbit) restricted within the galactic bounds.
- **Data Integration**: Fetch deterministic star positions and metadata from `ProceduralGalaxy.gd`.
- **Scene Structure**: `scenes/galaxy_map.tscn` combining the 3D environment, camera, and CanvasLayer UI.

## Execution Strategy
The agents will work in parallel:
- **Systems Council**: Builds the base scene `galaxy_map.tscn`, `GalaxyMapCamera.gd`, and the data-fetching logic.
- **Graphics Council**: Implements the `MultiMeshInstance3D` generator and `star_point.gdshader`.
- **UX Council**: Implements `GalaxyMapUI.gd` and the HUD overlay.
