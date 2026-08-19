# AAA+ UI/UX & Spatial Hologram Systems Research — BioGenesis

**Scope**: Architectural specifications, spatial UI mathematics, shader algorithms, accessibility standards, and multi-input responsiveness systems for BioGenesis.
**Author**: Subagent 7 (AAA+ UI/UX & Spatial Hologram Systems Architect) — Loop 1
**Target System**: BioGenesis (TypeScript / React 19 / Three.js / WebGL2 / WebGPU / GLSL)
**Date**: 2026-08

---

## 1. Executive Summary & Aesthetic Architecture

BioGenesis demands a high-fidelity visual and interactive paradigm bridging the clean, familiar control systems of human spacefarers with the living, alien biology of Void-Fauna ships.

Following the project's **Five Aesthetic Layers** framework (defined in `LIVING_SHIPS_RESEARCH.md`), the UI/UX architecture primarily inhabits **Layer 1: The Interface Layer (Frutiger Aero / Skeuomorphic Futurism)**, while dynamically visualizing and reflecting **Layer 3: The Biology Layer**.

### Core Pillars
1. **Frutiger Aero 3D Spatial Glass UI**: Tactile 3D floating glass control surfaces with physical depth, refraction (IOR 1.45–1.52), dual-filter Kawase blur, specular highlights, and translucent window panels showing bio-luminescent organic activity underneath.
2. **Volumetric 3D Holographic Telemetry**: Real-time volumetric raymarching for 3D tactical navigation maps and 3D organ telemetry, complete with scanline interference, depth-sorted point clouds, and bio-plasma heat maps.
3. **Neuro-Link HUD Post-Processing**: Dynamic pain and stress feedback rendering via multi-pass screen-space shaders featuring radial chromatic aberration, Simplex electrical noise, smoothstep vignetting, and heartbeat-synced lens deformation.
4. **Universal Accessibility (a11y)**: WCAG AAA compliant high-contrast modes (7:1+ contrast ratios), post-process Daltonization colorblind filters (Protanopia, Deuteranopia, Tritanopia), gaze/laser dwell selection, horizon lock, and full input remapping.
5. **Unified Multi-Input Engine**: Seamless cross-platform input abstraction supporting 6DOF VR spatial controllers, gamepads with adaptive haptics, and mouse/keyboard with 6DOF freelook.

---

## 2. Frutiger Aero 3D Spatial Glass UI Engine

### 2.1 Visual & Optical Properties
The Frutiger Aero glass aesthetic combines ultra-clean glossy surfaces, rounded organic borders, vibrant cyan (`#00CED1`), orange (`#FF6B35`), yellow (`#FFD23F`) accents, and warm amber (`#FFB347`) backlit biological illumination showing through translucent panels.

```
+-------------------------------------------------------------------+
|                        FRUTIGER AERO GLASS PANEL                 |
|  +-------------------------------------------------------------+  |
|  | [Specular Highlight / Glossy Rim Sweep (Fresnel)]           |  |
|  |                                                             |  |
|  | Reflected Skybox/Cockpit + Refracted Bio-Organ Chamber      |  |
|  | (Kawase Dual-Filter Blur + Chromatic Dispersion \Delta n)       |  |
|  |                                                             |  |
|  | Backlit Amber Glow (#FFB347) from underlying Organ Vasculature|  |
|  +-------------------------------------------------------------+  |
+-------------------------------------------------------------------+
```

### 2.2 Glass Shader Technical Specification (`frutigerGlass.glsl`)

```glsl
// GLSL Fragment Shader: Frutiger Aero Spatial Glass
uniform sampler2D u_BackgroundTexture; // Scene render behind glass
uniform sampler2D u_NormalMap;         // Surface organic micro-curvature
uniform vec3 u_GlassColor;             // Tint (e.g. vec3(0.0, 0.8, 0.82))
uniform vec3 u_AmberBacklight;         // Bio-glow (e.g. vec3(1.0, 0.7, 0.28))
uniform float u_IOR;                   // Index of Refraction ~ 1.48
uniform float u_BlurStrength;          // Mipmap / Kawase blur level
uniform float u_Roughness;             // Surface roughness (0.05 - 0.2)
uniform float u_BioGlowIntensity;      // Organ pulse intensity [0.0 - 1.0]
uniform vec2 u_ScreenResolution;

varying vec3 v_Normal;
varying vec3 v_ViewPosition;
varying vec2 v_Uv;

// Schlick's approximation for Fresnel reflectivity
float FresnelSchlick(float cosTheta, float F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
    vec3 N = normalize(v_Normal);
    vec3 V = normalize(-v_ViewPosition);
    
    // 1. Refraction & Chromatic Dispersion
    float cosTheta = max(dot(N, V), 0.0);
    vec3 refractDirR = refract(-V, N, 1.0 / (u_IOR - 0.015));
    vec3 refractDirG = refract(-V, N, 1.0 / u_IOR);
    vec3 refractDirB = refract(-V, N, 1.0 / (u_IOR + 0.015));
    
    vec2 screenUv = gl_FragCoord.xy / u_ScreenResolution;
    
    // Sample background with dispersion offset
    float bgR = texture2D(u_BackgroundTexture, screenUv + refractDirR.xy * 0.03, u_BlurStrength).r;
    float bgG = texture2D(u_BackgroundTexture, screenUv + refractDirG.xy * 0.03, u_BlurStrength).g;
    float bgB = texture2D(u_BackgroundTexture, screenUv + refractDirB.xy * 0.03, u_BlurStrength).b;
    vec3 refractedColor = vec3(bgR, bgG, bgB);

    // 2. Fresnel Specular Rim & Sunlight Highlight
    float F0 = 0.04; // Glass baseline reflection
    float fresnel = FresnelSchlick(cosTheta, F0);
    vec3 lightDir = normalize(vec3(0.5, 1.0, 0.8));
    vec3 H = normalize(V + lightDir);
    float spec = pow(max(dot(N, H), 0.0), 128.0 / u_Roughness);
    vec3 specularColor = vec3(1.0) * spec * 1.5;

    // 3. Bio-luminescent Amber Backlight (Subnautica Translucent Panel effect)
    vec3 bioGlow = u_AmberBacklight * u_BioGlowIntensity * (1.0 - cosTheta);

    // 4. Composition
    vec3 finalColor = mix(refractedColor * u_GlassColor, vec3(1.0), fresnel * 0.4);
    finalColor += specularColor + bioGlow;

    // High glossy alpha with smooth rim fallback
    float alpha = clamp(0.45 + fresnel * 0.5, 0.0, 0.95);
    gl_FragColor = vec4(finalColor, alpha);
}
```

### 2.3 3D Spatial UI Layout Mathematics

#### Curved Cylindrical Projection & World-Space Anchoring
To prevent distortion and maintain ergonomic readability in VR/3D space, UI elements are projected onto a virtual cylindrical canvas surrounding the camera/pilot head.

Given panel position parameters:
- \(R\): Curvature radius (meters, default \(1.25\,\text{m}\))
- \(\theta\): Horizontal angle on cylinder (radians)
- \(y\): Vertical displacement along cylinder axis (meters)
- \(\phi_{\text{tilt}}\): Forward ergonomic tilt angle (\(-5^\circ\) to \(-15^\circ\))

The 3D spatial position \(\mathbf{P}_{\text{world}}\) relative to head center \(\mathbf{H}\) is:

\[
\mathbf{P}_{\text{world}}(\theta, y) = \mathbf{H} + \mathbf{R}_{\text{tilt}}(\phi_{\text{tilt}}) \begin{pmatrix} R \sin\theta \\ y \\ R \cos\theta \end{pmatrix}
\]

The normal vector \(\mathbf{N}_{\text{panel}}\) pointing toward the pilot is:

\[
\mathbf{N}_{\text{panel}}(\theta) = -\mathbf{R}_{\text{tilt}}(\phi_{\text{tilt}}) \begin{pmatrix} \sin\theta \\ 0 \\ \cos\theta \end{pmatrix}
\]

#### Parallax Offset Math (Spatial Depth Layers)
Multi-layered UI components (e.g. text floating above a glass card with background bio-gauges) calculate vertex displacement based on gaze/cursor vector \(\mathbf{V}_{\text{gaze}}\):

\[
\Delta \mathbf{P}_{\text{layer}} = d_{\text{layer}} \cdot \left( \mathbf{V}_{\text{gaze}} - (\mathbf{V}_{\text{gaze}} \cdot \mathbf{N}_{\text{panel}}) \mathbf{N}_{\text{panel}} \right)
\]

where \(d_{\text{layer}}\) is the visual depth layer multiplier (\(0.02\,\text{m}\) to \(0.08\,\text{m}\)).

#### 3D World-Space Hit Testing & Raycasting
Ray-cylinder collision math for 6DOF VR lasers and mouse screen-rays:

Given ray \(\mathbf{r}(t) = \mathbf{O} + t\mathbf{D}\), substitute into cylindrical equation \((x - H_x)^2 + (z - H_z)^2 = R^2\):

\[
(O_x + tD_x - H_x)^2 + (O_z + tD_z - H_z)^2 = R^2
\]

Solving quadratic equation \(A t^2 + B t + C = 0\):
- \(A = D_x^2 + D_z^2\)
- \(B = 2(D_x(O_x - H_x) + D_z(O_z - H_z))\)
- \(C = (O_x - H_x)^2 + (O_z - H_z)^2 - R^2\)

Interpolated UV coordinates on panel:

\[
u = \frac{\theta - \theta_{\text{min}}}{\theta_{\text{max}} - \theta_{\text{min}}}, \quad v = \frac{y_{\text{hit}} - y_{\text{min}}}{y_{\text{max}} - y_{\text{min}}}
\]

---

## 3. Volumetric 3D Holographic Tactical Maps & Telemetry

### 3.1 Volumetric Raymarching & Holographic Visual Engine
The holographic tactical map renders volumetric ship interiors, organ networks, and external tactical environments using a raymarched bounding box pipeline.

```
Ray Origin (Camera) ---> [ Bounding Box Entry t_near ]
                                |
                                v Raymarching Steps (\Delta t)
                            * S_1: Sample Density & Temperature
                            * S_2: Sample Bio-Pulse Noise
                            * S_3: Accumulate Emission & Opacity
                            * S_4: Apply Scanline Interference
                                |
                                v
                        [ Bounding Box Exit t_far ] ---> Composite Output
```

### 3.2 Hologram Shader Code Specification (`volumetricHologram.glsl`)

```glsl
// GLSL Fragment Shader: Volumetric Holographic Organ Telemetry Map
uniform vec3 u_VolumeBoundsMin;
uniform vec3 u_VolumeBoundsMax;
uniform sampler3D u_OrganDensityMap;  // 3D SDF/Density texture of ship organs
uniform float u_Time;                  // Animated scanlines & pulse
uniform vec3 u_HoloColorPrimary;      // Cyan (0.0, 0.9, 1.0)
uniform vec3 u_HoloColorWarning;      // Amber/Red for damaged organs
uniform float u_GlitchIntensity;       // Interference spikes

varying vec3 v_WorldPos;
varying vec3 v_RayDirection;

// Ray-box intersection algorithm
bool IntersectBox(vec3 ro, vec3 rd, vec3 boxMin, vec3 boxMax, out float t0, out float t1) {
    vec3 invR = 1.0 / rd;
    vec3 tbot = invR * (boxMin - ro);
    vec3 ttop = invR * (boxMax - ro);
    vec3 tmin = min(ttop, tbot);
    vec3 tmax = max(ttop, tbot);
    t0 = max(tmin.x, max(tmin.y, tmin.z));
    t1 = min(tmax.x, min(tmax.y, tmax.z));
    return t1 > max(t0, 0.0);
}

void main() {
    vec3 rayOrigin = cameraPosition;
    vec3 rayDir = normalize(v_RayDirection);

    float tNear, tFar;
    if (!IntersectBox(rayOrigin, rayDir, u_VolumeBoundsMin, u_VolumeBoundsMax, tNear, tFar)) {
        discard;
    }

    int STEPS = 64;
    float stepSize = (tFar - tNear) / float(STEPS);
    vec3 currentPos = rayOrigin + rayDir * (tNear + stepSize * 0.5);

    vec4 accumulatedColor = vec4(0.0);

    for (int i = 0; i < 64; i++) {
        // Normalize position to [0, 1] within volume box
        vec3 texCoord = (currentPos - u_VolumeBoundsMin) / (u_VolumeBoundsMax - u_VolumeBoundsMin);
        
        // Sample organ density and health telemetry from 3D texture
        vec4 densitySample = texture(u_OrganDensityMap, texCoord);
        float density = densitySample.a;
        float health = densitySample.r; // 1.0 = healthy, 0.0 = damaged

        if (density > 0.01) {
            // Color interpolation: Cyan (Healthy) to Amber/Magenta (Stressed/Damaged)
            vec3 organColor = mix(u_HoloColorWarning, u_HoloColorPrimary, health);

            // Additive scanline interference & flicker
            float scanline = sin(currentPos.y * 150.0 - u_Time * 10.0) * 0.5 + 0.5;
            float flicker = fract(sin(dot(currentPos.xz + u_Time, vec2(12.9898, 78.233))) * 43758.5453);
            scanline = mix(scanline, flicker, u_GlitchIntensity);

            vec3 emission = organColor * density * (0.8 + 0.4 * scanline);
            float alpha = density * stepSize * 2.5;

            // Front-to-back volumetric opacity accumulation
            accumulatedColor.rgb += (1.0 - accumulatedColor.a) * emission * alpha;
            accumulatedColor.a += (1.0 - accumulatedColor.a) * alpha;

            if (accumulatedColor.a >= 0.98) break;
        }

        currentPos += rayDir * stepSize;
    }

    // Depth grid overlay & edge glow
    float edgeGlow = pow(1.0 - abs(dot(normalize(-cameraPosition), vec3(0.0, 1.0, 0.0))), 3.0);
    accumulatedColor.rgb += u_HoloColorPrimary * edgeGlow * 0.2;

    gl_FragColor = accumulatedColor;
}
```

### 3.3 Dynamic Organ Telemetry Metrics

| Telemetry Axis | Data Source | Visual Representation in Hologram | Refresh Rate |
| :--- | :--- | :--- | :--- |
| **Hemolymph Flux** | Vascular Fluid Solver | Pulsing flow directional arrows + velocity vectors | 60 Hz |
| **Compute Demand** | Neural Compute Pipeline | Node cluster particle density & interconnect line glow | 30 Hz |
| **Bio-Plasma Heat** | Weapon/Propulsion Thermal | Temperature gradient colormap (Cyan \(\rightarrow\) Gold \(\rightarrow\) Magenta) | 60 Hz |
| **Structural Damage** | Hull Chitin Stress Solver | Flashing red wireframe mesh overlay with fracture vectors | Real-time event |
| **Oxygenation / Bio-Mass**| Metabolism System | Organ volume opacity shift & internal rib shading | 10 Hz |

---

## 4. Neuro-Link HUD & Post-Processing Pain Feedback

### 4.1 Biological Feedback Pipeline
The Neuro-Link HUD simulates direct neural connection between the pilot's brain and the ship's nervous system. When organs sustain damage, heat overload, or oxygen deprivation, pain signals induce real-time screen-space optical feedback.

```
Ship Damage / Pain Vector (P \in [0, 1])
  |
  +---> 1. Chromatic Aberration (\Delta RGB \propto P^2)
  +---> 2. Neural Noise (Simplex Discharge \propto P^{1.5})
  +---> 3. Smoothstep Vignetting (Edge Darkening \propto P)
  +---> 4. Bio-Pulse Lens Shift (Heartbeat Pulse Amplitude \propto Heat)
```

### 4.2 Composite Neuro-Link Post-Processing Shader (`neuroLinkHUD.glsl`)

```glsl
// GLSL Fragment Shader: Composite Neuro-Link HUD Post-Processing
uniform sampler2D u_SceneTexture;
uniform float u_PainIntensity;       // [0.0 = Healthy, 1.0 = Critical Pain]
uniform float u_NeuralStrain;        // [0.0 = Calm, 1.0 = Overclocked/Strained]
uniform float u_PulsePhase;          // Heartbeat sync phase [0.0 - 2\pi]
uniform float u_Time;
uniform vec2 u_Resolution;

varying vec2 v_Uv;

// 2D Simplex Noise generator for electrical neural discharge
vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }
float SimplexNoise2D(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                       -0.577350269189626, 0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy) );
    vec2 x0 = v -   i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod(i, 289.0);
    vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
        + i.x + vec3(0.0, i1.x, 1.0 ));
    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m ;
    m = m*m ;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
    vec3 g;
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

void main() {
    vec2 uv = v_Uv;
    vec2 distFromCenter = uv - vec2(0.5);
    float dist = length(distFromCenter);

    // 1. Radial Heartbeat Bio-Pulse Lens Shift
    float pulseDistortion = sin(u_PulsePhase) * 0.015 * (1.0 + u_PainIntensity * 2.0);
    uv += normalize(distFromCenter) * pulseDistortion * smoothstep(0.2, 0.8, dist);

    // 2. Pain-Driven Radial Chromatic Aberration
    float offset = pow(u_PainIntensity, 2.0) * 0.035 * dist;
    float r = texture2D(u_SceneTexture, uv + distFromCenter * offset).r;
    float g = texture2D(u_SceneTexture, uv).g;
    float b = texture2D(u_SceneTexture, uv - distFromCenter * offset).b;
    vec3 sceneColor = vec3(r, g, b);

    // 3. Electrical Neural Discharge Noise
    float noiseScale = 25.0;
    float n = SimplexNoise2D(uv * noiseScale + vec2(u_Time * 15.0));
    float spark = pow(clamp(n, 0.0, 1.0), 5.0) * u_NeuralStrain;
    vec3 sparkColor = vec3(0.2, 0.8, 1.0) * spark * 2.5;

    // 4. Smoothstep Vignette & Red Pain Tint
    float vignette = smoothstep(0.75, 0.25, dist * (1.0 + u_PainIntensity * 0.5));
    vec3 painBorder = vec3(0.8, 0.05, 0.1) * (1.0 - vignette) * u_PainIntensity * 1.8;

    vec3 finalColor = sceneColor * vignette + sparkColor + painBorder;
    gl_FragColor = vec4(finalColor, 1.0);
}
```

---

## 5. Accessibility (a11y) & Motor-Inclusivity Systems

### 5.1 WCAG AAA Compliance & High-Contrast Systems
BioGenesis enforces strict contrast compliance across all 3D UI overlays:
- **Normal Text (< 18pt / 24px)**: Contrast ratio \(\ge 7:1\) against background.
- **Large Text (\(\ge\) 18pt / 24px bold)**: Contrast ratio \(\ge 4.5:1\).
- **High-Contrast Scheme Toggle**: Replaces glass translucency with opaque dark backgrounds (`#050811`, 100% alpha) and ultra-sharp borders (`#00FFFF`, 3px stroke).

```
Default Frutiger Glass (Translucent)  <--->  High-Contrast A11y Mode (Opaque)
+-----------------------------------+        +-----------------------------------+
| Alpha: 0.45, Refraction Active    |        | Alpha: 1.00, Solid Dark (#050811) |
| Text: Amber/Cyan (4.8:1 ratio)    |        | Text: Pure White (14.2:1 ratio)   |
| Subtle Fresnel Border             |        | High-Viz 3px Solid Border         |
+-----------------------------------+        +-----------------------------------+
```

### 5.2 Post-Processing Colorblind Filter Algorithms (Daltonization Shader)
For color-deficient pilots, BioGenesis applies real-time Daltonization in screen space:

Given LMS color space conversion matrix \(\mathbf{M}_{\text{RGB}\rightarrow\text{LMS}}\) and deficiency simulation matrix \(\mathbf{S}_{\text{type}}\):

```glsl
// Daltonization Matrix Transformations
const mat3 RGB_TO_LMS = mat3(
    17.8824, 43.5161, 4.11935,
    3.45565, 27.1554, 3.86714,
    0.0299566, 0.184309, 1.46709
);

const mat3 LMS_TO_RGB = mat3(
    0.080944, -0.130504, 0.116721,
    -0.0102485, 0.0540194, -0.0113615,
    -0.000365294, -0.00412161, 0.693511
);

// Protanopia Simulation Matrix
const mat3 SIM_PROTANOPIA = mat3(
    0.0, 2.02344, -2.52581,
    0.0, 1.0, 0.0,
    0.0, 0.0, 1.0
);

vec3 ApplyDaltonization(vec3 rgb, mat3 simMatrix) {
    vec3 lms = RGB_TO_LMS * rgb;
    vec3 simLms = simMatrix * lms;
    vec3 simRgb = LMS_TO_RGB * simLms;

    // Error vector between original and simulated
    vec3 err = rgb - simRgb;

    // Shift error into readable color spectrum
    vec3 shift;
    shift.r = 0.0;
    shift.g = (err.g * 0.7) + (err.r * 0.3);
    shift.b = (err.b * 0.7) + (err.r * 0.3);

    return clamp(rgb + shift, 0.0, 1.0);
}
```

### 5.3 Motor Accessibility & Motion Sickness Mitigation

| Accessibility Feature | Implementation Spec | Benefit |
| :--- | :--- | :--- |
| **Gaze/Laser Dwell Select** | Continuous raycast timer (0.2s - 2.0s configurable dwell ring) | Hands-free / single-trigger UI control |
| **Horizon Lock** | World-up vector constraint on camera roll & pitch damping (\(\tau = 0.3\,\text{s}\)) | Prevents spatial disorientation & VR motion sickness |
| **Field-of-View Vignetting** | Dynamic peripheral FOV reduction (\(75^\circ \rightarrow 50^\circ\)) during fast roll/boost | Reduces optical flow motion sickness |
| **Auto-Target Lock Assist** | Magnetic cursor snapping (\(15^\circ\) cone threshold, spring force solver) | Assists pilots with tremors or low precision |
| **Hold-to-Toggle Override** | Global toggle state machine converting press-and-hold into single clicks | Eliminates motor fatigue on long actions |

---

## 6. Multi-Input Unified Controller Architecture

### 6.1 Input Abstraction & Device Normalization Engine

```
[ VR Spatial (6DOF) ]     [ Gamepad (XInput/DualSense) ]     [ Mouse / Keyboard ]
        |                              |                             |
        v                              v                             v
+--------------------------------------------------------------------------+
|                       UNIFIED INPUT ABSTRACTION LAYER                    |
|  - Normalizes 6DOF rays, analog sticks, and screen mouse coordinates    |
|  - Action Mapping: "Interact", "TargetOrgan", "Overclock", "Pitch/Yaw"   |
|  - Auto-Detects active device on last event (0ms transition delay)       |
+--------------------------------------------------------------------------+
                                       |
                                       v
                     [ Active UI Focus State Manager ]
                                       |
                                       +---> 3D Raycast Hit
                                       +---> Spatial Sound Event
                                       +---> Haptic Impulse Trigger
```

### 6.2 Cross-Device Interaction Matrix

```typescript
// Unified Action Event Definition
export interface SpatialInputEvent {
  deviceType: 'VR_CONTROLLER' | 'GAMEPAD' | 'MOUSE_KEYBOARD';
  action: 'INTERACT_PRIMARY' | 'INTERACT_SECONDARY' | 'NAVIGATE_RADIAL' | 'FREELOOK';
  rayOrigin?: THREE.Vector3;
  rayDirection?: THREE.Vector3;
  analogAxis?: { x: number; y: number };
  timestamp: number;
}
```

### 6.3 Input Polling & Latency Mitigation Specs
1. **Asynchronous Time Warp (ATW) & Space Warp (ASW) Compatibility**: Spatial UI transform matrices are updated in frame-end pre-render hooks using predicted pose vectors derived from IMU timestamps.
2. **Radial Menu Navigation**: Gamepads trigger a 360-degree analog radial selector divided into 8 biological organ slices. Angular deadzone is fixed at \(0.25\) radius.
3. **Cursor Micro-Animations**: Hovering over interactive glass panels triggers a visual micro-elevation (\(\Delta z = +0.015\,\text{m}\)) and a localized pulse of amber backlight over a \(150\,\text{ms}\) cubic-bezier curve (`cubic-bezier(0.25, 1, 0.5, 1)`).

---

## 7. Technical Integration Roadmap for BioGenesis

### Step 1: Core Glass Shader & UI Anchor System
- Deploy `FrutigerGlassMaterial` using Three.js `ShaderMaterial` with background texture copy pass.
- Wire curved spatial UI container into `Canvas3D.tsx` anchored to cockpit head transform.

### Step 2: Volumetric Telemetry Hologram Integration
- Connect `OrganSDFRegistry` to a 3D scalar volume sampler.
- Wire raymarched hologram into the Tactical Command Room display grid.

### Step 3: Neuro-Link Post-Processing Chain
- Implement screen-space post-processing pass using Three.js `EffectComposer`.
- Connect pain feedback parameters dynamically to `shipStatus` / organ strain metrics.

### Step 4: Accessibility & Multi-Input System
- Implement Daltonization shader pass and WCAG high-contrast theme toggles in `GeneticsDrawer`.
- Deploy `InputManager` supporting VR 6DOF raycasting, gamepad radial menus, and keyboard hotkeys.

---
*End of Report — Subagent 7 (AAA+ UI/UX & Spatial Hologram Systems Architect)*
