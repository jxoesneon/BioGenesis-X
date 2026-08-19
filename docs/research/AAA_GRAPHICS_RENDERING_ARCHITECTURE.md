# BioGenesis AAA+ Graphics & Rendering Architecture Technical Specification

**Author**: Subagent 1 (AAA+ Graphics & Rendering Architect)  
**Target Runtime**: WebGPU (Browser Core) / Vulkan 1.3 & DirectX 12 (Native Engine Gate)  
**Target Performance**: 4K @ 120 FPS (Native Vulkan/DX12) / 1440p @ 60 FPS (WebGPU WebGL2 Fallback)  
**Version**: 1.0.0-AAA  

---

## 1. Executive Summary & Architectural Overview

BioGenesis features living, organic starships composed of dynamic biological tissues, translucent membranes, glowing hemolymph channels, reactive bio-moss, and bioluminescent neural clusters. Rendering these entities requires moving beyond traditional rigid-body PBR graphics to a **translucent, dynamic, GPU-driven biological rendering engine**.

### Key Architectural Pillars:
1. **Biological Subsurface Scattering (SSS)**: Physically-accurate Christensen-Burley Normalized Diffusion and Separable Screen-Space SSS for multi-layered organic tissue types (hemolymph, membranes, chitin, bio-moss, neural ganglia).
2. **Volumetric Atmosphere & Ray-Traced Bioluminescence**: 3D Froxel (Frustum Voxel Grid) Volumetric Integration with temporal jittering, phase function scattering, and distance-field/radiance-cascade bioluminescent light shafts.
3. **GPU-Driven Pipeline**: Bindless descriptor indexing, compute-driven indirect draw execution (`drawIndirect`), Hierarchical Z-Buffer (HZB) frustum/occlusion culling, and clustered deferred shading for 1,000+ simultaneous bioluminescent lights.
4. **Reactive Material Systems**: WebGPU compute-driven Gray-Scott Reaction-Diffusion solvers feeding real-time emissive, albedo, height, and roughness maps directly into material pipelines.
5. **Dual-Layer Interior/Exterior Stencil Shading**: Stencil-masked cross-sectional rendering allowing dynamic hull dissections, exposing inner vascular organs with back-face stencil cap shading.

---

## 2. Subsurface Scattering (SSS) Architecture for Biological Tissues

### 2.1 Physics & Mathematical Model: BSSRDF & Normalized Diffusion

Light transport in translucent biological tissue is governed by the Bidirectional Scattering-Surface Reflectance Distribution Function (BSSRDF), defined as:

$$dL_o(p_o, \omega_o) = S(p_i, \omega_i, p_o, \omega_o) L_i(p_i, \omega_i) (\omega_i \cdot n_i) dp_i d\omega_i$$

For real-time evaluation, we utilize **Christensen-Burley Normalized Diffusion**, which approximates the radial diffuse reflectance profile $R(r)$ as a single profile parameterized by the mean free path $\lambda$:

$$R(r) = \frac{e^{-r / d}}{8 \pi d r} + \frac{e^{-r / (3d)}}{40 \pi d r}$$

Where $r$ is the surface distance between entry point $p_i$ and exit point $p_o$, and $d = \frac{\lambda}{S_v}$ is the normalized search radius.

#### Translucency & Thickness Transmission
For thin organic membranes (e.g., dorsal fins, spiracle flaps, hemolymph vessels), direct transmission through the mesh volume is evaluated using an exponential depth decay model:

$$T(p_o, \omega_o) = e^{-\sigma_t \cdot d_{\text{back}}}$$

Where $d_{\text{back}}$ is measured via back-face depth map subtraction in screen-space, and $\sigma_t = \sigma_a + \sigma_s'$ is the extinction coefficient.

---

### 2.2 Optical Tissue Parameter Specification

| Tissue Type | Mean Free Path $\lambda$ (mm) | Absorption $\sigma_a$ ($mm^{-1}$) | Scattering $\sigma_s'$ ($mm^{-1}$) | Anymmetry Factor $g$ | Primary Colors (RGB Scatter) | Translucency Mode |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Hemolymph Fluid** | `(12.5, 3.2, 0.8)` | `(0.02, 0.15, 0.45)` | `(1.20, 0.85, 0.30)` | `0.92` (Forward) | `(0.95, 0.25, 0.08)` Amber/Crimson | Screen-Space SSS + Volumetric |
| **Epidermal Membrane** | `(4.8, 8.2, 6.1)` | `(0.08, 0.04, 0.06)` | `(0.85, 1.20, 0.95)` | `0.75` (Forward) | `(0.15, 0.85, 0.65)` Cyan/Teal | Translucency Thickness Map |
| **Chitin Carapace** | `(0.5, 0.3, 0.2)` | `(0.60, 0.70, 0.80)` | `(0.20, 0.15, 0.10)` | `0.40` (Isotropic) | `(0.35, 0.28, 0.20)` Muted Bronze | Pre-Integrated Skin Shading |
| **Bio-Moss / Plant Layer** | `(2.1, 7.8, 1.4)` | `(0.25, 0.05, 0.40)` | `(0.60, 1.80, 0.45)` | `0.65` (Forward) | `(0.20, 0.90, 0.25)` Emerald Bio-Glow | Subsurface Profile Gaussian |
| **Neural Ganglia / Brain** | `(8.0, 9.5, 14.0)` | `(0.04, 0.03, 0.01)` | `(1.10, 1.30, 1.90)` | `0.88` (Forward) | `(0.30, 0.60, 1.00)` Deep Violet/Blue | Separable Screen-Space SSS |

---

### 2.3 WGSL Screen-Space Subsurface Scattering Shader

```wgsl
// sss_pass.wgsl - Separable Screen-Space Subsurface Scattering in WGSL
struct SSSUniforms {
    sampleCount: u32,
    maxDistance: f32,
    subsurfaceColor: vec3<f32>,
    filterRadius: f32,
};

@group(0) @binding(0) var sceneColorTexture: texture_2d<f32>;
@group(0) @binding(1) var sceneDepthTexture: texture_2d<f32>;
@group(0) @binding(2) var linearSampler: sampler;
@group(0) @binding(3) var<uniform> sssParams: SSSUniforms;

// Burley Normalized Diffusion Kernel Evaluation
fn burleyProfile(r: f32, mfp: vec3<f32>) -> vec3<f32> {
    let d = mfp / 3.8; // Scaling factor for 99% energy preservation
    let term1 = exp(-vec3<f32>(r) / d) / (8.0 * 3.14159265 * d * r);
    let term2 = exp(-vec3<f32>(r) / (3.0 * d)) / (40.0 * 3.14159265 * d * r);
    return term1 + term2;
}

@fragment
fn fs_main_sss_horizontal(@builtin(position) fragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    let texSize = vec2<f32>(textureDimensions(sceneColorTexture));
    let uv = fragCoord.xy / texSize;
    let centerDepth = textureSample(sceneDepthTexture, linearSampler, uv).r;
    let centerColor = textureSample(sceneColorTexture, linearSampler, uv).rgb;
    
    var colorSum = centerColor;
    var weightSum = 1.0;
    
    let stepSize = (sssParams.filterRadius / centerDepth) / texSize.x;
    
    // Separable 1D Gaussian-Burley Filter Strip
    for (var i: i32 = -6; i <= 6; i++) {
        if (i == 0) { continue; }
        let offset = vec2<f32>(f32(i) * stepSize, 0.0);
        let sampleUV = uv + offset;
        
        let sampleDepth = textureSample(sceneDepthTexture, linearSampler, sampleUV).r;
        let depthDiff = abs(centerDepth - sampleDepth);
        
        // Depth bilateral constraint (prevent blurring across structural geometry edges)
        if (depthDiff < 0.05) {
            let dist = abs(f32(i));
            let weight = burleyProfile(dist, sssParams.subsurfaceColor).r;
            let sampleColor = textureSample(sceneColorTexture, linearSampler, sampleUV).rgb;
            colorSum += sampleColor * weight;
            weightSum += weight;
        }
    }
    
    return vec4<f32>(colorSum / weightSum, 1.0);
}
```

---

## 3. Volumetric Fog, Light Shafts, & Ray-Traced Bioluminescence

### 3.1 3D Froxel Grid Architecture (Frustum Voxel Grid)

To achieve AAA+ volumetric lighting (such as gas nebulae, internal ship atmospheric humidity, and light shafts), the view frustum is discretized into a 3D grid of **FroXels** ($160 \times 90 \times 64$ resolution).

```
Camera Near Plane (z=0.1m) ───► [FroXel (0,0,0)] ───► [FroXel (x,y,z)] ───► Camera Far Plane (z=500m)
                                logarithmic Z distribution: z_slice = z_near * (z_far / z_near)^(slice / N)
```

#### Logarithmic Slice Equation:
$$z(k) = z_{\text{near}} \cdot \left(\frac{z_{\text{far}}}{z_{\text{near}}}\right)^{\frac{k}{N_z}}$$

Where $N_z = 64$, $z_{\text{near}} = 0.1\text{m}$, $z_{\text{far}} = 500\text{m}$.

---

### 3.2 Henyey-Greenstein / Schlick Scattering & Integration

At each froxel voxel $(i, j, k)$, a compute shader accumulates scattering media parameters ($\sigma_s, \sigma_a, E_{\text{emissive}}$) and evaluates direct lighting from all overlapping lights using the **Schlick-approximated Henyey-Greenstein Phase Function**:

$$P(\theta) = \frac{1 - g^2}{4\pi (1 + g \cos\theta)^2} \approx \frac{1 - k^2}{4\pi (1 + k \cos\theta)^2}, \quad k \approx 1.55g - 0.55g^3$$

```wgsl
// volumetrics_froxel.wgsl - Compute shader voxelizing lighting & fog into 3D volume
struct LightData {
    positionRadius: vec4<f32>, // xyz: pos, w: radius
    colorIntensity: vec4<f32>, // rgb: color, w: intensity
};

@group(0) @binding(0) var froxelGridStorage: texture_storage_3d<rgba16float, write>;
@group(0) @binding(1) var shadowMapTexture: texture_depth_2d;
@group(0) @binding(2) var shadowSampler: sampler_comparison;
@group(0) @binding(3) var<storage, read> lights: array<LightData>;

fn henyeyGreenstein(cosTheta: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * 3.14159265 * pow(denom, 1.5));
}

@compute @workgroup_size(8, 8, 1)
fn main_froxel_build(@builtin(global_invocation_id) globalId: vec3<u32>) {
    let gridDim = vec3<u32>(160u, 90u, 64u);
    if (any(globalId >= gridDim)) { return; }
    
    let voxelPos = vec3<f32>(globalId) / vec3<f32>(gridDim);
    let worldPos = froxelUVToWorld(voxelPos);
    
    var accumulatedInscatter = vec3<f32>(0.0);
    let extinction = 0.015; // Uniform fog extinction
    
    // Evaluate lighting contribution for bioluminescent lights
    for (var i: u32 = 0u; i < arrayLength(&lights); i++) {
        let light = lights[i];
        let lightVec = light.positionRadius.xyz - worldPos;
        let dist = length(lightVec);
        if (dist < light.positionRadius.w) {
            let L = lightVec / dist;
            let attenuation = 1.0 / (1.0 + dist * dist);
            let phase = henyeyGreenstein(dot(-L, getCameraForward()), 0.4);
            accumulatedInscatter += light.colorIntensity.rgb * light.colorIntensity.w * attenuation * phase;
        }
    }
    
    // Store inscatter (RGB) and extinction coefficient (A)
    textureStore(froxelGridStorage, globalId, vec4<f32>(accumulatedInscatter, extinction));
}
```

---

### 3.3 Temporal Accumulation & Ray-Traced Bioluminescent Shafts

To eliminate high-frequency noise from volumetric light shafts without high sample counts, temporal reprojection accumulates voxel data across frames using a motion vector offset:

$$V_{\text{curr}}(i,j,k) = \alpha V_{\text{new}}(i,j,k) + (1 - \alpha) V_{\text{prev}}(\text{Reproject}(i,j,k))$$

With $\alpha = 0.05$ (95% temporal stability).

---

## 4. WebGPU Compute & Vulkan/DX12 Multi-Threaded Rendering Pipelines

### 4.1 Low-Overhead Direct API Architecture

To reach AAA performance across both native targets and browser runtimes, BioGenesis uses a **Direct Frame Execution Model**:

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      CPU Multi-Threaded Dispatch                       │
 └──────┬─────────────────────────────┬────────────────────────────┬──────┘
        │ Thread 1                    │ Thread 2                   │ Thread 3
 ┌──────▼─────────────────────┐ ┌─────▼────────────────────┐ ┌─────▼─────────────────────┐
 │ Render Thread (G-Buffer)   │ │ Compute Thread (Physics) │ │ Asset Streaming Thread  │
 └──────┬─────────────────────┘ └─────┬────────────────────┘ └─────┬─────────────────────┘
        │                              │                            │
        │ CommandEncoder               │ ComputePassEncoder         │ StagingBuffer Copy
        ▼                              ▼                            ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │                    GPU Queue Submission & Sync                         │
 ├────────────────────────────────────────────────────────────────────────┤
 │ [Compute Queue]: Reaction-Diffusion PDE -> HZB Cull -> Clustered Light │
 │ [Graphics Queue]: Depth Prepass -> G-Buffer -> Volumetric -> Composite │
 └────────────────────────────────────────────────────────────────────────┘
```

---

### 4.2 Bindless Descriptor Indexing System

Instead of binding textures individual per-draw call, BioGenesis binds a global **Descriptor Array / Storage Buffer** containing all material textures, indexed directly by mesh instance IDs:

```wgsl
// bindless_materials.wgsl - WebGPU / HLSL Bindless Texture & Material Lookup
struct MaterialData {
    albedoTexIdx: u32,
    normalTexIdx: u32,
    roughnessTexIdx: u32,
    emissiveTexIdx: u32,
    subsurfaceParams: vec4<f32>,
};

@group(1) @binding(0) var bindlessTextures: binding_array<texture_2d<f32>>;
@group(1) @binding(1) var globalSamplers: array<sampler, 4>;
@group(1) @binding(2) var<storage, read> materialBuffer: array<MaterialData>;

fn sampleInstanceAlbedo(materialId: u32, uv: vec2<f32>) -> vec4<f32> {
    let mat = materialBuffer[materialId];
    return textureSample(bindlessTextures[mat.albedoTexIdx], globalSamplers[0], uv);
}
```

---

## 5. GPU-Driven Pipeline: HZB Occlusion Culling & Clustered Deferred Shading

### 5.1 Hierarchical Z-Buffer (HZB) Construction & Compute Culling

Traditional CPU frustum culling cannot handle millions of procedural organic geometry instances. BioGenesis delegates all visibility testing to a **GPU Compute Shader**:

1. **Depth Pre-pass**: Render simplified bounding geometry.
2. **HZB Generation**: Downsample depth buffer into a MIP pyramid using a `min()` reduction filter ($2 \times 2$ depth texels $\rightarrow 1$ min-depth texel).
3. **Compute Culling**: Test instance bounding sphere against camera frustum planes and sample HZB at corresponding MIP level for occlusion testing.

```
Bounding Sphere (Center, Radius) ──► Frustum Planes Test (Pass/Fail)
                                           │ (Pass)
                                           ▼
                                 Project Sphere to Screen Rect
                                           │
                                           ▼
                                 Sample HZB MIP Pyramid at Min Depth
                                           │
                        ┌──────────────────┴──────────────────┐
                        ▼                                     ▼
             Depth <= HZB (Visible)                 Depth > HZB (Occluded)
                        │                                     │
                        ▼                                     ▼
             Append Instance to                     Discard Instance
             Indirect Draw Buffer
```

```wgsl
// hzb_cull.wgsl - GPU Compute Occlusion & Frustum Culling
struct DrawIndexedIndirectCommand {
    indexCount: u32,
    instanceCount: atomic<u32>,
    firstIndex: u32,
    baseVertex: i32,
    baseInstance: u32,
};

struct InstanceData {
    boundingCenter: vec3<f32>,
    boundingRadius: f32,
    worldMatrix: mat4x4<f32>,
};

@group(0) @binding(0) var hzbTexture: texture_2d<f32>;
@group(0) @binding(1) var pointSampler: sampler;
@group(0) @binding(2) var<storage, read> instanceInput: array<InstanceData>;
@group(0) @binding(3) var<storage, read_write> indirectDrawCommands: array<DrawIndexedIndirectCommand>;

@compute @workgroup_size(64, 1, 1)
fn main_hzb_cull(@builtin(global_invocation_id) globalId: vec3<u32>) {
    let instanceId = globalId.x;
    if (instanceId >= arrayLength(&instanceInput)) { return; }
    
    let instance = instanceInput[instanceId];
    
    // 1. Frustum Plane Test
    if (!isSphereInFrustum(instance.boundingCenter, instance.boundingRadius)) {
        return;
    }
    
    // 2. Hierarchical Z-Buffer Occlusion Test
    let screenRect = projectSphereToScreenRect(instance.boundingCenter, instance.boundingRadius);
    let mipLevel = calculateHzbMipLevel(screenRect);
    let maxDepth = sampleHzbMaxDepth(screenRect, mipLevel);
    let closestInstanceDepth = getSphereNearestDepth(instance.boundingCenter, instance.boundingRadius);
    
    if (closestInstanceDepth <= maxDepth) {
        // Increment atomic instance counter in indirect draw buffer
        atomicAdd(&indirectDrawCommands[0].instanceCount, 1u);
    }
}
```

---

### 5.2 Clustered Deferred Shading Engine

To support over **1,000 active bioluminescent light sources** (spore pods, hemolymph pulses, neural discharges), the screen space is divided into 3D clusters ($32 \times 18 \times 24$).

#### Clustering Compute Pipeline:
1. **Grid Generation**: Calculate AABBs for all $32 \times 18 \times 24$ frustum clusters in world space.
2. **Light Assignment**: Compute shader intersects light bounding spheres with cluster AABBs, outputting a bitmask list of light indices per cluster.
3. **Shading Evaluation**: Deferred fragment shader fetches cluster index using pixel depth and evaluates only lights within that cluster.

```
Screen Space (1920x1080) ──► Grid (32x18 tiles) ──► 24 Logarithmic Depth Slices
                                                          │
                                                          ▼
                                            13,824 Unique 3D Frustum Clusters
                                                          │
                                                          ▼
                                            Compute Shader Light-AABB Test
                                                          │
                                                          ▼
                                            Active Light Bitmask (Max 64 lights/cluster)
```

---

### 5.3 Auto-Exposure & AgX Tone Mapping Pipeline

BioGenesis environments range from pitch-black deep space voids to blinding bioluminescent core explosions. Temporal auto-exposure is calculated via a GPU **Luminance Histogram**:

```wgsl
// auto_exposure.wgsl - Logarithmic Luminance Histogram Compute Shader
@group(0) @binding(0) var hdrColorTexture: texture_2d<f32>;
@group(0) @binding(1) var<storage, read_write> luminanceHistogram: array<atomic<u32>, 256>;

fn colorToLogLuminance(color: vec3<f32>) -> f32 {
    let lum = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    if (lum < 0.0001) { return -10.0; }
    return log2(lum);
}

@compute @workgroup_size(16, 16, 1)
fn main_histogram(@builtin(global_invocation_id) globalId: vec3<u32>) {
    let dims = textureDimensions(hdrColorTexture);
    if (globalId.x >= dims.x || globalId.y >= dims.y) { return; }
    
    let color = textureLoad(hdrColorTexture, globalId.xy, 0).rgb;
    let logLum = colorToLogLuminance(color);
    
    // Map log luminance to [0, 255] histogram bin
    let binIdx = u32(clamp((logLum + 10.0) / 12.0 * 255.0, 0.0, 255.0));
    atomicAdd(&luminanceHistogram[binIdx], 1u);
}
```

#### AgX Tone Mapping Output:
Perceptual luminance contrast preservation avoids saturation blow-out on high-intensity bioluminescent emissions.

---

## 6. Dynamic Gray-Scott Reaction-Diffusion & Dual-Layer Stencil Shading

### 6.1 Gray-Scott Reaction-Diffusion PDE Compute Engine

Living ship hulls feature animated, organic skin patterns (spots, stripes, bioluminescent wave pulses) generated directly on the GPU by solving the coupled non-linear partial differential equations:

$$\frac{\partial U}{\partial t} = D_u \nabla^2 U - U V^2 + F (1 - U)$$

$$\frac{\partial V}{\partial t} = D_v \nabla^2 V + U V^2 - (F + k) V$$

Where:
- $U, V$: Morphogen chemical concentrations.
- $D_u = 0.16, D_v = 0.08$: Diffusion rates.
- $F$: Feed rate parameter ($0.010 \le F \le 0.090$).
- $k$: Kill rate parameter ($0.045 \le k \le 0.070$).

```wgsl
// gray_scott_pde.wgsl - GPU Reaction-Diffusion Solver
struct RDParams {
    feedRate: f32,
    killRate: f32,
    dt: f32,
    du: f32,
    dv: f32,
};

@group(0) @binding(0) var inputStateTexture: texture_2d<f32>;
@group(0) @binding(1) var outputStateStorage: texture_storage_2d<rg32float, write>;
@group(0) @binding(2) var<uniform> params: RDParams;

@compute @workgroup_size(16, 16, 1)
fn main_gray_scott_step(@builtin(global_invocation_id) globalId: vec3<u32>) {
    let coords = vec2<i32>(globalId.xy);
    let currentUV = textureLoad(inputStateTexture, coords, 0).rg;
    
    // 5-Point Laplacian Stencil Operator Evaluation
    let top    = textureLoad(inputStateTexture, coords + vec2<i32>(0, 1), 0).rg;
    let bottom = textureLoad(inputStateTexture, coords + vec2<i32>(0, -1), 0).rg;
    let left   = textureLoad(inputStateTexture, coords + vec2<i32>(-1, 0), 0).rg;
    let right  = textureLoad(inputStateTexture, coords + vec2<i32>(1, 0), 0).rg;
    
    let laplacian = top + bottom + left + right - 4.0 * currentUV;
    
    let uv2 = currentUV.r * currentUV.g * currentUV.g;
    let du_dt = params.du * laplacian.r - uv2 + params.feedRate * (1.0 - currentUV.r);
    let dv_dt = params.dv * laplacian.g + uv2 - (params.feedRate + params.killRate) * currentUV.g;
    
    let nextU = clamp(currentUV.r + du_dt * params.dt, 0.0, 1.0);
    let nextV = clamp(currentUV.g + dv_dt * params.dt, 0.0, 1.0);
    
    textureStore(outputStateStorage, coords, vec4<f32>(nextU, nextV, 0.0, 1.0));
}
```

---

### 6.2 Dual-Layer Interior/Exterior Stencil Shading Architecture

BioGenesis allows real-time engineering dissections of living ships, slicing away chitin carapace plates to reveal inner anatomical organs. This requires a **2-Pass Stencil Buffer Masking Pipeline**:

```
Pass 1: Outer Chitin Carapace (Clip Plane Enabled)
  ├─ Write Stencil Ref = 0x01 on Clip Plane Back-faces
  └─ Render Exterior PBR Shader + Reaction-Diffusion Skin

Pass 2: Inner Cavity & Vascular Mesh (Stencil Masked)
  ├─ Test Stencil Ref == 0x01
  └─ Render Internal Muscle/Vascular Shader + Bioluminescent Fluid
```

```
                        [Camera Ray]
                             │
                             ▼
               ┌───────────────────────────┐
               │ Clip Plane Intersection?  │
               └─────────────┬─────────────┘
                             │
             ┌───────────────┴───────────────┐
             ▼                               ▼
    (Outside Clip Volume)           (Inside Clip Volume)
             │                               │
             ▼                               ▼
     Render Exterior Hull          Write Stencil Ref = 0x01
  (Reaction-Diffusion PBR)                   │
                                             ▼
                                   Render Interior Cap Shader
                                  (Cross-Section Tissue + Hemolymph)
```

---

## 7. Target Hardware Architectural Budget & Technical Specifications

### 7.1 Frame Performance Budget (Target: 4K @ 120 FPS Native / 1440p @ 60 FPS WebGPU)

| Execution Pass | Target Time (120 FPS / 8.33ms) | Target Time (60 FPS / 16.6ms) | Primary GPU Workload |
| :--- | :--- | :--- | :--- |
| **Compute Async Pass** | `1.10 ms` | `2.20 ms` | Gray-Scott PDE (2 steps) + Physics Simulation |
| **Depth Pre-Pass & HZB** | `0.60 ms` | `1.20 ms` | Depth Render + HZB Min-Downsample Pyramid |
| **GPU Culling & Prep** | `0.40 ms` | `0.80 ms` | HZB Occlusion Compute + Indirect Buffer Write |
| **G-Buffer Geometry Pass** | `2.20 ms` | `4.40 ms` | Bindless Draw Call Execution + Stencil Masking |
| **Clustered Light Binning** | `0.50 ms` | `1.00 ms` | 3D Grid Frustum Light AABB Intersections |
| **Volumetric Froxel Build**| `1.20 ms` | `2.40 ms` | Voxel Light Integration + TAA Reprojection |
| **Deferred Shading & SSS** | `1.50 ms` | `3.00 ms` | Screen-Space SSS + Clustered Lighting Combine |
| **Post-FX & Tone Mapping** | `0.83 ms` | `1.60 ms` | Luminance Histogram + AgX Tone Map + Bloom |
| **TOTAL FRAME TIME** | **`8.33 ms`** | **`16.60 ms`** | **Fully Synchronized Frame Execution** |

---

### 7.2 VRAM & GPU Allocation Specification

- **G-Buffer Allocation (1440p)**: 48 MB (RT0: Albedo/Roughness RGBA8, RT1: Normal/Metal RGBA16F, RT2: Emissive/SSS RGBA16F, Depth/Stencil D32S8).
- **HZB Pyramid Texture**: 4.5 MB (MIP 0 to MIP 9).
- **Clustered Lighting Buffer**: 3.5 MB ($32 \times 18 \times 24$ clusters $\times 64$ light indices $\times 2$ bytes).
- **3D Froxel Grid Volume**: 14.1 MB ($160 \times 90 \times 64 \times \text{RGBA16F}$).
- **Reaction-Diffusion Morphogen Fields**: 32 MB ($2048 \times 2048$ dual RG32F ping-pong buffers).
- **Bindless Texture Array Capacity**: 4 GB VRAM Pool (Streaming LRU cache).

---

## 8. Architectural Conclusion & Implementation Roadmap

This specification establishes the blueprint for an ultra-high performance, physically rooted biological rendering engine for **BioGenesis**. By shifting geometry processing, visibility culling, organic texture generation, and volumetric lighting entirely into **GPU Compute**, BioGenesis achieves unparalleled visual fidelity while ensuring 60 FPS performance in WebGPU runtimes and 120 FPS performance in native Vulkan/DX12 engines.
