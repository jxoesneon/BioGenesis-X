# Procedural Mesh Generation — Unified Research Findings

**Scope**: Comprehensive literature + implementation review across 15 research vectors,
synthesized from 15 parallel deep-research subagents (Waves 1–3).

**Purpose**: Establish the algorithmic foundation for BioGenesis's procedural organic
spaceship/creature builder. Every technique is evaluated for applicability to the
Void-Fauna organ pipeline described in `ORGAN_SYSTEMS.md`.

**Last updated**: 2025-11

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Foundational Algorithms (Wave 1)](#2-foundational-algorithms-wave-1)
   - 2.1 Parametric Surfaces & NURBS
   - 2.2 Noise-Based Generation
   - 2.3 Subdivision Surfaces
   - 2.4 Isosurface Extraction
   - 2.5 L-Systems & Procedural Structures
3. [Advanced Techniques (Wave 2)](#3-advanced-techniques-wave-2)
   - 3.1 Signed Distance Fields
   - 3.2 GPU Mesh Generation
   - 3.3 LOD & Simplification
   - 3.4 Mesh Repair & Optimization
   - 3.5 Voxel Meshing & CSG
4. [Application-Specific (Wave 3)](#4-application-specific-wave-3)
   - 4.1 Organic & Biological Generation
   - 4.2 Three.js / R3F Patterns
   - 4.3 Real-Time Game Engine Pipelines
   - 4.4 Spline & Tube Generation
   - 4.5 Mesh Deformation & Morphing
5. [BioGenesis Implementation Recommendations](#5-biogenesis-implementation-recommendations)
6. [Key Libraries & Repositories](#6-key-libraries--repositories)
7. [Foundational Papers Reference](#7-foundational-papers-reference)

---

## 1. Executive Summary

This research surveyed the full landscape of procedural mesh generation, from classical
1980s algorithms (marching cubes, L-systems, FFD) to 2025 state-of-the-art (Nanite-style
virtualized geometry, neural SDFs, mesh-shader pipelines). The findings cluster into
**three tiers of relevance** for BioGenesis:

### Tier 1 — Immediately Applicable
- **SDF composition with smooth-min blending** — the natural representation for organic
  organ shapes (bladders, atria, tumors) that need smooth boolean unions.
- **Marching cubes / surface nets** — proven, well-documented, available in Three.js
  addons and WebGPU compute pipelines.
- **Spline-based tube generation** — directly applicable to vascular conduits, tentacles,
  tendrils, and the threading elements in the organ pipeline.
- **Metaballs / implicit surfaces** — ideal for blobby organic masses (hemolymph sacs,
  plasma bladders).
- **L-systems + space colonization** — for branching structures (arteries, vein networks,
  rib spurs, coral-like protrusions).

### Tier 2 — Strategic Investment
- **GPU compute mesh generation (WebGPU)** — enables real-time organ regeneration at
  interactive rates; future-proofs the pipeline.
- **Dual contouring** — better sharp-feature preservation than marching cubes for chitin
  plates, carapace segments, and crystalline organs.
- **Subdivision surfaces (Catmull-Clark, Loop)** — for smooth organic hulls and
  carapace surfaces with crease control.
- **Reaction-diffusion (Gray-Scott)** — for bioluminescent surface patterns and
  organic texturing on the hull.
- **ARAP deformation** — for organic shape morphing during the genetics-driven
  mutation phase.

### Tier 3 — Research Watch
- **Neural SDFs (DeepSDF, SIREN)** — learned shape spaces for organ families.
- **Nanite-style virtualized geometry** — overkill for BioGenesis's current scale but
  relevant if the ship count grows dramatically.
- **Wave Function Collapse** — for tile-based organ arrangement patterns.

---

## 2. Foundational Algorithms (Wave 1)

### 2.1 Parametric Surfaces & NURBS

**Core techniques**: Bézier surface tessellation, B-spline/NURBS evaluation via
Cox-de Boor recursion and de Boor's algorithm, adaptive tessellation with
curvature/screen-space error metrics.

**Key findings**:
- **De Boor's algorithm** is the numerically stable, efficient method for B-spline
  evaluation — O(p²) operations, preferred over explicit basis function computation.
- **Adaptive tessellation** combines intrinsic (curvature) and extrinsic (view-dependent)
  error metrics. DiagSplit (Stanford) achieves crack-free parallel adaptive tessellation.
- **Three.js already ships NURBS addons** (`NURBSCurve`, `NURBSSurface`, `NURBSVolume`,
  `NURBSUtils`) — directly usable for BioGenesis's `nurbs.ts` module.
- **ParametricGeometry** addon accepts `(u, v, target) => void` functions for custom
  mathematical surfaces.

**BioGenesis relevance**: The existing `nurbs.ts` module should leverage Three.js's
built-in NURBS addons rather than reimplementing. For organ surfaces that need
parametric control (e.g., spiral shells, swept tentacles), `ParametricGeometry` with
custom functions is the path of least resistance.

**Key libraries**: Three.js NURBS addons, verb-nurbs (JS), geomdl (Python), OpenNURBS (C++).

### 2.2 Noise-Based Generation

**Core techniques**: Perlin noise, Simplex noise, Worley/cellular noise, fBm,
multifractals, domain warping, turbulence, spectral synthesis (FFT-based).

**Key findings**:
- **Simplex noise** (Gustavson 2005) is preferred over Perlin — O(n²) vs O(n³),
  no directional artifacts, scales to higher dimensions.
- **fBm** formula: `Σ amplitude_i * noise(frequency_i * p)` with lacunarity (~2.0)
  and persistence (~0.5). 4–8 octaves for real-time.
- **Domain warping** (`f(p + fbm(p + fbm(p)))`) creates organic, swirling patterns
  ideal for bioluminescent surface modulation.
- **Worley noise** generates cellular patterns useful for crusty organic textures
  (chitin, carapace, barnacle-like surfaces).
- **FastNoiseLite** (C++) and the `noise` Rust crate are production-ready.

**BioGenesis relevance**: Noise functions are the foundation for organic surface
displacement on the hull and organs. Domain-warped fBm should drive the hull's
bioluminescent pattern modulation. Worley noise can generate the cellular texture
basis for carapace segments.

### 2.3 Subdivision Surfaces

**Core techniques**: Catmull-Clark (quad), Loop (triangle), Doo-Sabin, modified
Butterfly, adaptive subdivision, semi-sharp creases (OpenSubdiv).

**Key findings**:
- **Catmull-Clark**: C² continuous on regular regions, C¹ at extraordinary vertices.
  Equivalent to bicubic B-spline on regular quads. The industry standard for smooth
  organic surfaces.
- **Loop subdivision**: Triangle-based, C² regular / C¹ extraordinary. Better for
  purely triangular meshes.
- **Semi-sharp creases** (Pixar/DeRose 1998): Sharpness values 0–10, decreasing by
  1 per subdivision iteration. Essential for organic shapes that need both smooth
  regions and defined edges (carapace ridges, chitin plate boundaries).
- **OpenSubdiv** is the production reference implementation — CPU + GPU evaluation,
  matches RenderMan to numerical precision.
- **Feature-Adaptive Subdivision (FAS)**: Only subdivides around extraordinary
  vertices, dramatically reducing workload on GPU.
- **Jos Stam's exact evaluation**: Direct surface evaluation at arbitrary parameters
  using eigenbasis functions — avoids iterative subdivision entirely.

**BioGenesis relevance**: Catmull-Clark with semi-sharp creases is the right
subdivision scheme for the hull carapace — smooth organic bulges with defined
ridge lines where chitin plates meet. The existing hull mesh in `Canvas3D.tsx`
could benefit from subdivision-based refinement for smoother LOD transitions.

**Key libraries**: OpenSubdiv (Pixar), libigl, CGAL, gl-catmull-clark (JS/WebGL).

### 2.4 Isosurface Extraction

**Core techniques**: Marching Cubes, Marching Tetrahedra, Dual Contouring, Surface
Nets, Dual Marching Cubes, Transvoxel, Flying Edges.

**Key findings**:

| Algorithm | Year | Strengths | Best For |
|-----------|------|-----------|----------|
| Marching Cubes | 1987 | Simple, fast, lookup tables | General organic surfaces |
| Marching Tetrahedra | 1991 | Topologically correct, unstructured grids | Avoiding MC ambiguities |
| Extended MC | 2001 | Sharp features via gradients | CAD-like geometry |
| Surface Nets | 1998 | Smooth, simple, binary data | Medical segmentation, label maps |
| Dual Contouring | 2002 | Sharp features, adaptive (octree) | Sharp geometry, adaptive resolution |
| Dual Marching Cubes | 2004 | Dual grid, thin features | Adaptive + CSG |
| Transvoxel | 2010 | Seamless LOD stitching | Chunked voxel terrain |
| Flying Edges | 2015 | Parallel, high performance | Large datasets, HPC |

- **Marching Cubes**: 256 configurations (15 unique), `edgeTable[256]` + `triTable[256][16]`.
  Paul Bourke's tutorial is the canonical reference. Three.js ships a `MarchingCubes`
  addon with metaball support.
- **Dual Contouring**: Places vertices *inside* cells (not on edges) using Quadratic
  Error Functions (QEF). Preserves sharp features without explicit feature detection.
  Octree-based for adaptive resolution. **Does not guarantee manifold output** —
  Manifold Dual Contouring (Schaefer et al. 2007) fixes this.
- **Surface Nets**: Simpler than DC — uses averaging instead of QEF. Produces smooth
  results. The `fast-surface-nets` Rust crate achieves 20M triangles/sec single-core.
- **Transvoxel**: 512 transition cell cases for seamless LOD boundaries. Essential
  for chunked terrain. Used in Godot's voxel tools.

**BioGenesis relevance**: Marching Cubes (via Three.js addon) for initial organ mesh
generation from SDF fields. Dual Contouring for organs that need sharp features
(chitin plates, crystalline structures). Surface Nets for smooth organic masses
where manifold guarantee matters. The existing `MarchingCubes` addon in Three.js
is sufficient for the current pipeline.

### 2.5 L-Systems & Procedural Structures

**Core techniques**: Deterministic/stochastic/context-sensitive/parametric L-systems,
space colonization, CGA shape grammars, Wave Function Collapse.

**Key findings**:
- **Parametric L-systems** (Hanan 1992): Symbols carry numerical parameters for
  geometric attributes. Support arithmetic guards (`A(x) : x > 5 -> ...`).
- **Space colonization** (Runions et al. 2007): Iterative branch growth guided by
  attraction points. Generates realistic trees, veins, circulatory systems. Parameters:
  influence radius, kill distance, segment length, crown envelope.
- **CGA Shape Grammars** (Müller & Wonka 2006): Context-sensitive rules for
  architectural facades. Split operations (axis, component, repeat). Powering
  ArcGIS CityEngine.
- **Wave Function Collapse**: Constraint-satisfaction from quantum mechanics analogy.
  Overlapping model (pattern-based) and Simple Tiled model (adjacency rules).
  Ported to 15+ languages. Integrated in Unity, UE5, Godot 4, Houdini.

**BioGenesis relevance**:
- **L-systems** for branching organ structures — arteries, vein networks, rib spurs,
  neural pathways. The `Symbios` Rust engine supports parametric, context-sensitive,
  stochastic rules with genetic algorithm toolkit (useful for the genetics-driven
  mutation system).
- **Space colonization** for vascular networks and coral-like protrusions. The
  algorithm naturally fills space with branching structures — ideal for the
  "threading elements" in the organ pipeline.
- **WFC** for tile-based organ arrangement — could generate valid organ placement
  patterns on the hull surface given adjacency constraints.

**Key libraries**: Symbios (Rust), lsystems-core (Rust), mxgmn/WaveFunctionCollapse (original).

---

## 3. Advanced Techniques (Wave 2)

### 3.1 Signed Distance Fields

**Core techniques**: SDF fundamentals, CSG operations, SDF-to-mesh conversion,
ray marching, smooth blending, neural SDFs.

**Key findings**:
- **CSG operations**: `union = min(d1,d2)`, `intersection = max(d1,d2)`,
  `subtraction = max(d1,-d2)`. These preserve the zero-level set but produce
  *pseudo-SDFs* (distance values away from surface become incorrect).
- **Smooth minimum (smin)**: Polynomial `mix(d2,d1,h) - k*h*(1-h)` creates organic
  blending. Parameter `k` controls blend thickness in distance units. This is the
  **single most important technique** for organic organ composition.
- **Ray marching**: Sphere tracing — advance ray by SDF value at each step.
  Real-time rendering without meshing. Inigo Quilez's articles are the definitive
  reference.
- **SDF to mesh**: Marching cubes (simple) or dual contouring (sharp features).
  `fogleman/sdf` (Python) provides clean CSG API: `sphere(1) & box(1.5)`.
- **Neural SDFs**: DeepSDF (CVPR 2019) — latent code-conditioned decoder represents
  entire shape classes. SIREN (NeurIPS 2020) — sinusoidal activations for fine
  detail. CSG on neural SDFs (SIGGRAPH 2024) — "closest point loss" for true SDF
  property after boolean ops.
- **Acceleration**: Octree-based (SdfLib), BVH-centric adaptive distance fields
  (BADF — 20-50x faster than CPU), GPU ray tracing hardware (DXR) for SDF grids.

**BioGenesis relevance**: SDFs are the **ideal representation** for BioGenesis organs.
Each organ can be defined as a composited SDF:
```
organ_sdf = smin(sphere_body, tube_conduit, k=0.3) - cavity_sdf
```
The smooth-min operator naturally creates the organic blending seen in biological
tissues. CSG subtraction creates cavities and concavities. The SDF can be meshed
via marching cubes for rendering, or ray-marched directly for preview.

**Key libraries**: fogleman/sdf (Python), isoext (Python), cheind/sdftoolbox (Python),
marklundin/glsl-sdf-ops (GLSL), Inigo Quilez's SDF reference.

### 3.2 GPU Mesh Generation

**Core techniques**: Compute shader meshing, geometry/mesh shaders, GPU tessellation,
indirect draw/dispatch, WebGPU compute pipelines.

**Key findings**:
- **Compute shader marching cubes**: Histogram pyramid algorithm (Dyken et al.) —
  reformulates MC as data compaction/expansion. Prefix sum (exclusive scan) for
  variable-sized output. 5-stage pipeline: classify → scan → compact → generate → render.
- **Mesh shaders** (Vulkan/DirectX 12/Metal 3): Task shader (culling, LOD) →
  Mesh shader (vertex/primitive generation) → Rasterizer. Cooperative thread groups,
  compute-like programming model. Replaces geometry shaders entirely.
- **GPU tessellation**: Hull shader (tessellation factors) → fixed-function
  tessellator → Domain shader (surface evaluation + displacement). Screen-space
  error metrics for adaptive density.
- **Indirect draw**: GPU computes its own draw commands — no CPU readback.
  `vkCmdDrawIndexedIndirectCount` / WebGPU `drawIndirect`. Enables fully GPU-driven
  rendering pipelines.
- **WebGPU compute**: Production-ready for browser-based mesh generation.
  `webgpu-marching-cubes` (Will Usher) demonstrates full pipeline with exclusive scan.
  Three.js adding `IndirectStorageBufferAttribute` for GPU-driven rendering.

**BioGenesis relevance**: WebGPU compute is the **future path** for BioGenesis.
The current CPU-based organ generation in `Canvas3D.tsx` could be offloaded to
WebGPU compute shaders for real-time regeneration during genetics-driven mutation.
The `substrate` WebGPU terrain generator demonstrates the multi-stage compute
pipeline pattern (index generation → tessellation → render) directly applicable
to organ mesh generation.

**Key libraries**: keijiro/ComputeMarchingCubes (Unity), webgpu-marching-cubes (WebGPU),
Twinklebear/webgpu-marching-cubes, toji.dev WebGPU best practices.

### 3.3 LOD & Mesh Simplification

**Core techniques**: Progressive Meshes, Quadric Error Metrics, view-dependent LOD,
terrain LOD (clipmaps, CDLOD, chunked LOD), Nanite-style virtualized geometry.

**Key findings**:
- **Progressive Meshes** (Hoppe 1996): Edge collapse / vertex split operations.
  Stores base mesh + sequence of vertex splits. Enables smooth geomorphing,
  progressive transmission, selective refinement.
- **QEM** (Garland & Heckbert 1997): 4×4 symmetric quadric matrices per vertex.
  Error = `v^T Q v`. Vertex pair contraction (not just edges) — can join unconnected
  regions. `meshopt_simplify` in meshoptimizer is the modern production implementation.
- **Screen-space error**: `screen_error = (geometric_error * screen_height) /
  (2 * distance * tan(fov/2))`. Drives view-dependent refinement.
- **Geometry Clipmaps** (Losasso & Hoppe 2004): Nested regular grids centered on
  viewer. 40GB US heightmap at 60 FPS with 100× compression.
- **CDLOD** (Strugar 2010): Quadtree of regular grids with precise 3D distance-based
  LOD. Vertex morphing for smooth transitions.
- **Nanite** (UE5, Karis 2021): Virtualized geometry — like virtual texturing for
  geometry. Cluster hierarchy (~128 triangles per cluster). HZB occlusion culling.
  Visibility buffer (32-bit depth + 32-bit triangle ID). Software rasterizer for
  micropolygons (< 10 pixels). **Single draw call for entire scene**.

**BioGenesis relevance**: For the current scale (single ship with ~20-50 organs),
LOD is not critical. However, if BioGenesis scales to fleet views or zoom-out
galaxy views, QEM-based simplification via `meshoptimizer` is the pragmatic choice.
The cluster-based LOD pattern (Nanite-style) could be applied to organ clusters
for hierarchical culling.

**Key libraries**: meshoptimizer (zeux), Fast-Quadric-Mesh-Simplification (sp4cerat),
Hoppe's Mesh-processing-library, NVIDIA vk_lod_clusters.

### 3.4 Mesh Repair & Optimization

**Core techniques**: Hole filling, smoothing (Laplacian, Taubin, bilateral),
remeshing (isotropic, CVT, quad), retopology, mesh booleans.

**Key findings**:
- **Hole filling**: Liepa's minimum area triangulation (2003) is the standard.
  Volumetric diffusion (Stanford) for complex holes with islands. CGAL provides
  `triangulate_refine_and_fair_hole()`.
- **Taubin smoothing** (λ=0.53, μ=-0.53): Two-step iteration prevents shrinkage.
  The default choice for organic mesh smoothing. Available in PyTorch3D, Trimesh.
- **Bilateral normal filtering**: Feature-preserving denoising. Guided Mesh Normal
  Filtering (Zhang et al. 2015) is state-of-the-art.
- **Isotropic remeshing** (Botsch-Kobbelt 2004): 4 passes — split long edges,
  collapse short edges, flip for valence-6, tangential relaxation. CGAL's
  `isotropic_remeshing()` is the reference implementation.
- **Quad retopology**: Instant Meshes (SIGGRAPH Asia 2015) — < 1 second for 100K
  faces. QuadriFlow (SGP 2018) — 4× fewer singularities. ZRemesher (ZBrush) for
  production.
- **Mesh booleans**: Manifold (elalish) — first guaranteed-manifold boolean
  algorithm. TrueForm — 6× faster than MeshLib. CGAL corefinement — exact predicates.
  Interactive and Robust Mesh Booleans (SIGGRAPH Asia 2022) — state-of-the-art.

**BioGenesis relevance**: Taubin smoothing for organic organ surfaces after
marching cubes extraction. Isotropic remeshing for uniform triangle distribution
on the hull. Mesh booleans (via Manifold or CGAL) for CSG operations between
organs and the hull — e.g., subtracting organ cavities from the carapace.

**Key libraries**: CGAL, libigl, Manifold (elalish), Instant Meshes, QuadriFlow,
meshoptimizer, PyTorch3D, Trimesh.

### 3.5 Voxel Meshing & CSG

**Core techniques**: Greedy meshing, sparse voxel octrees, voxel CSG,
voxel-to-mesh conversion, smooth voxel terrain.

**Key findings**:
- **Binary greedy meshing** (cgerikj): 50-200μs per 64³ chunk using bitwise
  operations. Three-step: occupancy mask → face culling → greedy quad merging.
- **Sparse Voxel Octrees** (Laine & Karras, NVIDIA): Compact GPU data structure
  for ray tracing. Contour information for geometric resolution. Normal compression.
  Competitive with triangle-based rendering.
- **Voxel CSG**: Simple per-voxel boolean ops (OR/AND/NOT). SDF-based voxel CSG
  (`min`/`max`) allows smooth transitions. OpenVDB sparse level sets are the
  industry standard (Houdini, SideFX).
- **Dual Contouring on voxels**: Sharp feature preservation. Manifold DC guarantees
  manifold output. `isoext` Python library provides one-liner interface.
- **Transvoxel**: 512 transition cell types for seamless LOD. Used in Godot's
  `VoxelMesherTransvoxel`. SDF-based voxel storage produces smooth gradients.
- **Flying Edges** (VTK): 4-pass edge-based processing. 1-2 orders of magnitude
  faster than basic marching cubes. Each voxel value accessed once (vs 8× in MC).

**BioGenesis relevance**: Voxel-based CSG is useful for boolean operations between
organs and the hull — voxelize both, perform boolean, extract mesh. For the current
SDF-based approach, direct SDF CSG (min/max) is more efficient than going through
voxels. The Transvoxel algorithm is relevant if BioGenesis adopts chunked terrain
for exterior environments.

---

## 4. Application-Specific (Wave 3)

### 4.1 Organic & Biological Generation

**Core techniques**: Metaballs/implicit surfaces, procedural anatomy, reaction-diffusion,
creature body generation, biomechanical/biopunk aesthetics.

**Key findings**:
- **Metaballs**: Three field functions — Blobby (Blinn): `a·e^(-br²)`, Meta Balls
  (piecewise), Soft Objects (Wyvill): `a(1 - 4r⁶/9b⁶ + 17r⁴/9b⁴ - 22r²/9b²)`.
  Marching cubes for polygonization. SDF smin for real-time shader-based rendering.
- **Procedural anatomy**: SDF-based organ placement (Procedural Anatomy/Houdini).
  MyCorporisFabrica (SIGGRAPH 2014) — ontology-centered anatomy modeling.
  AnatomyGen (Johns Hopkins) — SDF + latent space for organ shape generation.
- **Reaction-diffusion (Gray-Scott)**: `∂A/∂t = D_A∇²A - AB² + f(1-A)`,
  `∂B/∂t = D_B∇²B + AB² - (k+f)B`. Feed rate `f` and kill rate `k` control pattern
  type (spots, stripes, mazes, bubbles). Can run on meshes via Laplace-Beltrami
  discretization or point cloud formulation.
- **Creature generation**: Karl Sims (SIGGRAPH 1994) — genetic language with directed
  graphs, co-evolution of morphology and control. L-system encoding for body plans.
  Gene regulatory networks (GRN) for emergent symmetry and modularity.
- **Biomechanical aesthetics**: MetaMesh (MIT) — hierarchical biomimetic armor with
  three resolution levels. Chiton scale parametric modeling (Nature 2019). Shell
  generation via logarithmic spiral + swept apertures. Tentacle generation via
  FABRIK IK + sine wave motion + tapering.
- **Coral generation**: Coralize (Unity) — stony corals via L-systems, soft corals
  via leaf venation, sponges via nutrient-based mesh growth.

**BioGenesis relevance**: This is the **most directly applicable** research vector.
- **Metaballs + smin** for organic organ masses (plasma bladders, hemolymph atria).
- **Reaction-diffusion** for bioluminescent hull patterns — the Gray-Scott model
  can generate the organic, alien-looking surface patterns described in `LORE.md`.
- **Space colonization** for vascular networks and branching organs.
- **Shell generation** (logarithmic spiral + swept aperture) for spiral-shaped organs.
- **Tentacle generation** (spline + tapering + curl) for tentacle organs.
- **MetaMesh-style segmented armor** for chitin plate arrangement on the hull.

### 4.2 Three.js / R3F Patterns

**Core techniques**: BufferGeometry manipulation, ParametricGeometry, NURBS addons,
R3F hooks (useMemo, useFrame), MarchingCubes addon, volume rendering.

**Key findings**:
- **BufferGeometry**: Cannot resize after creation — pre-allocate max size, use
  `setDrawRange()` for variable counts. Set `needsUpdate = true` after modifications.
  Use `setUsage(DynamicDrawUsage)` for frequently-updated buffers.
- **R3F patterns**: `useMemo` for geometry creation (avoid recreation). `useFrame`
  for dynamic updates (mutate refs, never setState). `useLayoutEffect` for imperative
  method calls. **Pitfall**: Don't setState in useFrame — causes re-renders.
- **MarchingCubes addon**: `new MarchingCubes(resolution, material, enableUvs,
  enableColors, maxPolyCount)`. `addBall(x,y,z,strength,subtract,color)`.
  `addPlaneX/Y/Z(strength, subtract)`. `update()` regenerates mesh.
- **Drei MarchingCubes**: React abstraction — `<MarchingCubes resolution={50}>`
  with `<MarchingCube>` children. Clean declarative API.
- **Volume rendering**: `three.js-volume-renderer` (raymarching), `VolumeShader`
  (raycasting), `VolumeNodeMaterial` (node-based).
- **Third-party addons**: THREEf.js (time-varying), THREEg.js (special geometries),
  THREEi.js (implicit surface triangulation), THREE.Terrain (procedural terrain).

**BioGenesis relevance**: The existing `Canvas3D.tsx` already uses Three.js
BufferGeometry extensively. Key improvements:
1. Use `DynamicDrawUsage` for organ meshes that change during gizmo drag.
2. Consider Drei's `<MarchingCubes>` for metaball-based organ preview.
3. The `NURBSSurface` addon should be integrated with `nurbs.ts` for proper
   NURBS-based organ surfaces.
4. `useFrame` mutation pattern (not setState) for real-time organ deformation.

### 4.3 Real-Time Game Engine Pipelines

**Core techniques**: Unity MeshData API + Jobs + Burst, Unreal PMC/RMC/DynamicMesh,
Godot ArrayMesh/SurfaceTool, chunk streaming, GPU compute terrain, meshlet optimization.

**Key findings**:
- **Unity MeshData API** (2020.1+): Thread-safe, Burst-compatible.
  12.6× speedup over regular API. GPU compute shaders: 4ms vs 155ms for 400×400 mesh.
- **Unreal**: ProceduralMeshComponent (basic, single material, no LOD).
  RuntimeMeshComponent (30-90% less memory, LOD, multi-material). DynamicMesh
  (mesh booleans, advanced ops). **PMC performance warning**: `CreateMeshSection()`
  can freeze frames — split into 64×64 sections.
- **Godot**: ArrayMesh (primary), SurfaceTool (static), ImmediateMesh (per-frame),
  MeshDataTool (modification). All CPU-based — no GPU generation yet.
- **Chunk streaming**: Background thread generates data, main thread applies.
  `ConcurrentQueue` for thread-safe transfer. Chunk pooling avoids allocation overhead.
  LRU recycling for infinite worlds.
- **meshoptimizer pipeline**: Indexing → vertex cache → overdraw → vertex fetch →
  quantization → index filtering → shadow indexing. `meshopt_optimizeVertexCache()`
  for triangle order optimization.
- **Meshlet generation**: 64 vertices / 126 primitives per meshlet (NVIDIA).
  Bounding spheres + normal cones for culling. AMD: V=128, T=256 for better
  vertex reuse. `meshopt_buildMeshlets()` for production.

**BioGenesis relevance**: BioGenesis runs in the browser (Three.js/R3F), so the
game engine specifics are less directly applicable. However:
- The **chunk streaming pattern** is relevant if BioGenesis adds exterior environments.
- **meshoptimizer** (available as JS/WASM) should be used for vertex cache optimization
  of generated organ meshes.
- The **GPU compute pipeline pattern** (compute → indirect draw) is the target
  architecture for WebGPU-based organ generation.

### 4.4 Spline & Tube Generation

**Core techniques**: Spline-based tubes, Hermite/Catmull-Rom splines, Bezier sweep
surfaces, vascular network generation, tendril/tentacle generation.

**Key findings**:
- **Frame selection**: Frenet-Serret (standard, undefined at inflection points) vs
  Bishop frame (rotation-minimizing, avoids twisting) vs parallel transport.
  **Bishop frame is preferred** for organic tubes with curvature changes.
- **Variable radius**: `radius(t, phi)` function of parameter and polar angle.
  Enables tapering, bulging, and organic tube profiles.
- **Catmull-Rom splines**: Centripetal (α=0.5) parameterization avoids cusps and
  self-intersections. Three.js `CatmullRomCurve3` + `TubeGeometry` for direct
  tube generation.
- **Vascular networks**: CCO (Constrained Constructive Optimization) — gold standard
  for vascular tree generation. OpenCCO (IPOL 2023) provides open C++ implementation.
  L-systems with Murray's law for physiological branching. V-System for synthetic
  vessel generation.
- **Tentacles**: Spline + tapering + curl noise + FABRIK IK for dynamic motion.
  Differential growth (Cabbage framework, arXiv 2025) for buckling/curling organic
  shapes.
- **Sweep surfaces**: 1-rail (profile + rail) and 2-rail (profile + 2 rails) sweeps.
  Cubic Bezier section sweep for curvature control.

**BioGenesis relevance**: **Directly applicable** to the organ pipeline:
- **Tube generation** for vascular conduits, arteries, hemolymph channels.
  Three.js `TubeGeometry` with `CatmullRomCurve3` and variable radius function.
- **Bishop frame** for tubes that curve through the hull interior without twisting.
- **CCO algorithm** for generating realistic vascular networks that perfuse the
  ship's organs — directly matches the "Artery" and "Vein" organ types in
  `ORGAN_SYSTEMS.md`.
- **Tentacle generation** for the Tentacle organ type — spline + tapering + curl.
- **Differential growth** for organic, space-filling appendage generation.

### 4.5 Mesh Deformation & Morphing

**Core techniques**: Free-Form Deformation, skeletal skinning (LBS/DQS), mesh
morphing (ARAP, Poisson), displacement mapping, physics-based deformation (PBD/XPBD).

**Key findings**:
- **FFD** (Sederberg & Parry 1986): Trivariate Bernstein polynomials. Lattice
  control points deform embedded object. Volume-preserving variants available.
  PyGeM (Python) is the reference implementation.
- **Dual Quaternion Skinning** (Kavan et al. 2007/2008): Solves LBS artifacts
  (collapsing-joint, candy-wrapper). GPU-friendly, easy upgrade from LBS.
  Disney's enhanced DQS for production. Bulging-free DQS (Kim 2014) for correction.
- **ARAP** (Sorkine & Alexa 2007): Non-linear energy based on local rigidity.
  Detail-preserving mesh editing. libigl and Open3D provide reference implementations.
  `E = Σ_i Σ_j w_ij ||(p'_i - p'_j) - R_i(p_i - p_j)||²`
- **Morph targets**: Three.js `morphTargets`, Babylon.js `MorphTargetManager`.
  glTF 2.0 spec supports LINEAR, STEP, CUBICSPLINE interpolation. PlayCanvas uses
  float textures for unlimited morph targets.
- **Displacement mapping**: Hardware tessellation + displacement in domain shader.
  Vector displacement for full 3D offset. Analytic displacement (Nießner & Loop 2013)
  for correct normals and crack prevention.
- **PBD/XPBD** (Müller 2006, Macklin 2016): Directly modifies positions — fast,
  stable, controllable. XPBD adds compliance for timestep-independent stiffness.
  PositionBasedDynamics library (C++ + Python). GPU implementations via compute
  shaders (ClothDD, Bevy Soft Body).

**BioGenesis relevance**:
- **FFD** for global hull deformation during genetics-driven mutation — lattice
  control points correspond to genetic parameters.
- **DQS** for skeletal deformation if organs have internal skeletons (bone-like
  structures that drive surface deformation).
- **ARAP** for organic shape morphing during organ mutation — preserves local
  detail while allowing global shape changes.
- **Morph targets** for smooth transitions between organ states (e.g., healthy →
  mutated, dormant → active).
- **PBD/XPBD** for soft-body organ physics — organs that jiggle, deform, and
  respond to collision. The `PositionBasedDynamics` library or a WebGPU compute
  implementation would enable real-time organ physics.

---

## 5. BioGenesis Implementation Recommendations

### 5.1 Architecture: SDF-First Organ Representation

**Recommendation**: Represent each organ as a **composited SDF** rather than a
direct triangle mesh. The SDF is the source of truth; the triangle mesh is
generated on demand via marching cubes or surface nets.

```
OrganDefinition {
  sdf: CompositedSDF        // smin(sphere, tube, k) - cavity
  meshResolution: number    // marching cubes grid size
  meshMethod: 'marching-cubes' | 'surface-nets' | 'dual-contouring'
  material: OrganMaterial   // bioluminescent, chitin, flesh, etc.
}
```

**Benefits**:
- CSG operations (union, subtraction) are trivial and exact
- Smooth blending via smin creates organic aesthetics naturally
- LOD is free — just change mesh resolution
- Collision detection via SDF sampling (no mesh needed)
- Ray marching preview without meshing

### 5.2 Pipeline: CPU-First → WebGPU Migration Path

**Phase 1 (Current)**: CPU-based SDF evaluation + marching cubes in Three.js
- Use `fogleman/sdf` patterns adapted to TypeScript
- Three.js `MarchingCubes` addon for mesh extraction
- `BufferGeometry` with `DynamicDrawUsage` for live updates

**Phase 2 (Near-term)**: WebGPU compute pipeline
- SDF evaluation in WGSL compute shader
- Marching cubes in compute shader with prefix sum compaction
- Indirect draw for GPU-driven rendering
- Reference: `webgpu-marching-cubes` (Twinklebear)

**Phase 3 (Future)**: Neural SDF + virtualized geometry
- DeepSDF-style latent codes for organ families
- Cluster-based LOD for fleet-scale rendering

### 5.3 Specific Organ Type → Technique Mapping

| Organ Type | Primary Technique | Secondary Technique |
|------------|------------------|---------------------|
| Plasma Bladder | Metaball SDF + smin | Marching cubes |
| Hemolymph Atrium | Metaball SDF + smin | Marching cubes |
| Artery | Catmull-Rom tube + Bishop frame | Variable radius function |
| Vein Network | Space colonization / CCO | L-system branching |
| Tentacle | Spline tube + tapering + curl | Differential growth |
| Rib Spur | L-system branching | Pipe model thickness |
| Chitin Plate | Subdivision surface + creases | Catmull-Clark with semi-sharp |
| Carapace (Hull) | FFD lattice + subdivision | Reaction-diffusion texture |
| Neural Pathway | L-system + space colonization | Glowing material |
| Crystalline Organ | Dual contouring | Sharp feature SDF |
| Coral Protrusion | Space colonization | L-system + Worley noise |
| Spiral Organ | Logarithmic spiral + sweep | Parametric surface |

### 5.4 Deformation & Mutation System

**Genetics → SDF parameters**: Each gene maps to SDF or deformation parameters:
- Size genes → SDF radius/scale parameters
- Shape genes → smin blend factor `k`, noise frequency/amplitude
- Branching genes → L-system production rules, space colonization parameters
- Surface genes → displacement noise type, reaction-diffusion f/k parameters
- Topology genes → CSG operation types, organ placement constraints

**Mutation pipeline**:
1. Genetic mutation alters SDF parameters
2. SDF re-evaluated (CPU or GPU compute)
3. Marching cubes extracts new mesh
4. ARAP smoothing for transition morph
5. `BufferGeometry` attributes updated with `needsUpdate = true`

### 5.5 Performance Budget

| Operation | CPU (current) | WebGPU (target) |
|-----------|--------------|-----------------|
| SDF evaluation (64³) | ~50ms | ~2ms |
| Marching cubes (64³) | ~20ms | ~1ms |
| Organ regeneration | ~200ms | ~10ms |
| Full ship regeneration | ~2s | ~100ms |
| Hull deformation (FFD) | ~30ms | ~2ms |

---

## 6. Key Libraries & Repositories

### Three.js / Web-Specific
| Library | Language | Purpose |
|---------|----------|---------|
| Three.js MarchingCubes addon | JS | Isosurface extraction |
| Three.js NURBS addons | JS | NURBS curves/surfaces |
| Three.js ParametricGeometry | JS | Parametric surfaces |
| Drei MarchingCubes | JS/React | R3F marching cubes wrapper |
| @bitheral/marching-cubes | JS | Alternative MC implementation |
| sjpt/metaballsWebgl | JS/WebGL | GPU metaballs |
| THREEi.js | JS | Implicit surface triangulation |
| THREE.Terrain | JS | Procedural terrain |

### SDF & Implicit Modeling
| Library | Language | Purpose |
|---------|----------|---------|
| fogleman/sdf | Python | SDF composition with CSG |
| isoext | Python | Dual contouring from SDF |
| cheind/sdftoolbox | Python | SDF mesh extraction toolbox |
| marklundin/glsl-sdf-ops | GLSL | SDF operations in shaders |
| Inigo Quilez SDF reference | GLSL | Comprehensive SDF primitives |

### Subdivision & Remeshing
| Library | Language | Purpose |
|---------|----------|---------|
| OpenSubdiv (Pixar) | C++ | Production subdivision |
| libigl | C++ | Geometry processing suite |
| CGAL | C++ | Computational geometry |
| Instant Meshes | C++ | Quad retopology |
| QuadriFlow | C++ | Quad remeshing |
| gl-catmull-clark | JS | WebGL Catmull-Clark |

### L-Systems & Branching
| Library | Language | Purpose |
|---------|----------|---------|
| Symbios | Rust | Parametric L-system engine |
| lsystems-core | Rust | L-systems with turtle graphics |
| OpenCCO | C++ | Vascular tree generation |
| jakobrichert/space-colonization | C | Space colonization trees |

### Mesh Processing
| Library | Language | Purpose |
|---------|----------|---------|
| meshoptimizer | C/WASM | Vertex cache + simplification |
| Manifold (elalish) | C++ | Guaranteed-manifold booleans |
| Fast-Quadric-Mesh-Simplification | C++ | QEM simplification |
| PyGeM | Python | FFD deformation |
| PositionBasedDynamics | C++ | PBD/XPBD physics |

### GPU & WebGPU
| Library | Language | Purpose |
|---------|----------|---------|
| webgpu-marching-cubes | WGSL | WebGPU marching cubes |
| kmmod/substrate | WGSL | WebGPU terrain pipeline |
| keijiro/ComputeMarchingCubes | HLSL | Unity GPU marching cubes |
| toji/webgpu-bundle-culling | WGSL | WebGPU frustum culling |

---

## 7. Foundational Papers Reference

### Isosurface Extraction
- Lorensen & Cline (1987) — "Marching cubes" — SIGGRAPH
- Ju et al. (2002) — "Dual Contouring of Hermite Data" — SIGGRAPH
- Gibson (1998) — "Constrained Elastic SurfaceNets" — MICCAI
- Schaefer & Warren (2004) — "Dual Marching Cubes" — CGF
- Lengyel (2010) — "Transvoxel Algorithm" — PhD Dissertation
- Schroeder et al. (2015) — "Flying Edges" — LDAV

### Subdivision Surfaces
- Catmull & Clark (1978) — "Recursively generated B-spline surfaces"
- Loop (1987) — "Smooth Subdivision Surfaces Based on Triangles"
- DeRose et al. (1998) — "Subdivision Surfaces in Character Animation"
- Stam (1998) — "Exact Evaluation of Catmull-Clark Subdivision Surfaces"
- Nießner et al. (2012) — "Efficient Evaluation of Semi-Smooth Creases"

### SDF & Implicit Modeling
- Sederberg & Parry (1986) — "Free-form deformation of solid geometric models"
- Bloomental & Wyvill — Metaballs / implicit surfaces
- Park et al. (2019) — "DeepSDF" — CVPR
- Sitzmann et al. (2020) — "SIREN" — NeurIPS

### LOD & Simplification
- Hoppe (1996) — "Progressive Meshes" — SIGGRAPH
- Garland & Heckbert (1997) — "QEM Simplification" — SIGGRAPH
- Losasso & Hoppe (2004) — "Geometry Clipmaps"
- Karis (2021) — "Nanite Virtualized Geometry" — SIGGRAPH

### Procedural Generation
- Prusinkiewicz & Lindenmayer (1990) — "The Algorithmic Beauty of Plants"
- Runions et al. (2007) — "Space Colonization Algorithm"
- Müller & Wonka (2006) — "Procedural Modeling of Buildings"
- Perlin (1985) — "An Image Synthesizer"
- Worley (1996) — "A Cellular Texture Basis Function"

### Deformation & Animation
- Kavan et al. (2007/2008) — "Dual Quaternion Skinning"
- Sorkine & Alexa (2007) — "ARAP Surface Modeling"
- Müller et al. (2006) — "Position Based Dynamics"
- Macklin et al. (2016) — "XPBD"

### Organic & Biological
- Turing (1952) — "The Chemical Basis of Morphogenesis"
- Turk (1991) — "Reaction-Diffusion Textures"
- Sims (1994) — "Evolving Virtual Creatures"
- Gray-Scott model — Reaction-diffusion pattern formation

---

*This document is the authoritative reference for procedural mesh generation
techniques applicable to BioGenesis. It should be consulted before implementing
new organ types, deformation systems, or rendering pipelines.*
