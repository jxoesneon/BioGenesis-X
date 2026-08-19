// ============================================================================
// HYPERWAVE TRANSIT TUNNEL SHADER - BioGenesis-X
// Pumilio Studios — Inter-System Wave Engine Jump Visual Effect
// ============================================================================
// During HyperWaveAutopilot inter-system jumps, the Wave Engine's biological
// adaptation of the Void-Fauna's caudal siphon system creates a transient
// spacetime conduit between star systems. Unlike the in-system Wave Engine
// (wave_engine.gdshader) which depicts the Alcubierre metric as a warp plane,
// the HyperWave tunnel depicts the visual experience of transit THROUGH that
// conduit — the pilot sees the fabric of spacetime flowing past the ship as
// energy bands, streaks, and refracted starlight.
//
// Visual design follows the Biology aesthetic layer (Bioluminescent Fantasy):
//   - energy_color_1 (blue #1A80FF): Contraction energy ahead of the ship,
//     matching the wave_engine.gdshader contraction_color. Represents spacetime
//     compression — the destination being pulled toward the ship.
//   - energy_color_2 (cyan #00E6FF): High-energy streaks — the bio-plasma
//     resonating through the Void-Fauna's vascular conduit network at warp
//     frequencies. Cyan is the canonical "healthy neural sync" color from
//     the 12-color bioluminescent coding system (see docs/DESIGN_DIRECTION.md).
//   - dark_matter_color (deep purple #03001A): The void between stars —
//     space that hasn't been contracted or expanded yet. Purple maps to the
//     "corruption/anomaly" color in bioluminescent coding, appropriate here
//     because uncompressed interstellar space is alien and hostile to the
//     Void-Fauna (they feed on stellar radiation, not empty void).
//
// The screen-space refraction (chromatic aberration on the background) depicts
// gravitational lensing — light from the destination system is bent through
// the warp conduit, arriving distorted and color-split before the ship exits.
//
// Lore reference: LORE.md "The Wave Engine" — the Void-Fauna's caudal siphon
// system, originally evolved for plasma-jet locomotion, is resonantly tuned
// to deform spacetime at specific bio-plasma frequencies.
// ============================================================================
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Contraction energy (blue) — spacetime compression ahead of ship
uniform vec3 energy_color_1 : source_color = vec3(0.1, 0.5, 1.0);
// Bio-plasma resonance (cyan) — neural sync color from bioluminescent coding
uniform vec3 energy_color_2 : source_color = vec3(0.0, 0.9, 1.0);
// Uncompressed void (deep purple) — hostile interstellar space between stars
uniform vec3 dark_matter_color : source_color = vec3(0.01, 0.0, 0.1);

// Forward scroll speed — how fast energy bands appear to flow past the ship
uniform float scroll_speed : hint_range(0.1, 20.0) = 8.0;
// Swirl speed — rotational turbulence in the warp conduit walls
uniform float swirl_speed : hint_range(0.0, 5.0) = 1.5;
// Overall intensity — scales emission for bloom post-processing
uniform float intensity_multiplier : hint_range(0.1, 10.0) = 3.0;

// Fast 2D Hash function
vec2 hash( vec2 p ) {
	p = vec2( dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)) );
	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

// Simplex noise
float noise( in vec2 p ) {
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2  i = floor( p + (p.x+p.y)*K1 );
    vec2  a = p - i + (i.x+i.y)*K2;
    float m = step(a.y,a.x); 
    vec2  o = vec2(m,1.0-m);
    vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0*K2;
    vec3  h = max( 0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	vec3  n = h*h*h*h*vec3( dot(a,hash(i+0.0)), dot(b,hash(i+o)), dot(c,hash(i+1.0)));
    return dot( n, vec3(70.0) );
}

// Fractal Brownian Motion
float fbm(vec2 p) {
    float f = 0.0;
    f += 0.5000 * noise(p); p = p * 2.02;
    f += 0.2500 * noise(p); p = p * 2.03;
    f += 0.1250 * noise(p); p = p * 2.01;
    f += 0.0625 * noise(p);
    return f / 0.9375;
}

void vertex() {
    // The tunnel walls wobble because the warp conduit is biological, not
    // mechanical — the Void-Fauna's vascular conduit network pulses and
    // flexes as it channels bio-plasma at warp frequencies. A perfectly
    // rigid tunnel would look mechanical; the wobble communicates that this
    // is a living structure breathing around the ship.
    float wobble = sin(TIME * 5.0 + VERTEX.z * 0.1) * 0.5;
    float wobble2 = cos(TIME * 3.0 + VERTEX.y * 0.1) * 0.5;
    VERTEX.x += wobble;
    VERTEX.y += wobble2;
}

void fragment() {
    vec2 uv = UV;
    
    // Create the fast forward-moving effect
    float z_scroll = TIME * scroll_speed;
    float swirl = TIME * swirl_speed;
    
    vec2 noise_uv = vec2(uv.x * 3.0 + swirl, uv.y * 10.0 - z_scroll);
    
    // Generate layered noise
    float n1 = fbm(noise_uv);
    float n2 = fbm(noise_uv * 1.5 + vec2(TIME * 0.5));
    
    // Combine noise for energy bands
    float energy = smoothstep(0.1, 0.8, n1 * n2 + 0.2);
    
    // Add lightning / high-energy streaks
    float streaks = pow(fbm(vec2(uv.x * 20.0, uv.y * 2.0 - z_scroll * 2.0)), 3.0) * 2.0;
    
    // Calculate energy color
    vec3 energy_fx = mix(dark_matter_color, energy_color_1, energy);
    energy_fx = mix(energy_fx, energy_color_2, streaks);
    energy_fx *= intensity_multiplier;
    
    // Fade the ends of the cylinder so it doesn't have hard cuts
    float edge_fade = smoothstep(0.0, 0.2, uv.y) * smoothstep(1.0, 0.8, uv.y);
    
    // --- SPACE WARPING (Gravitational Lensing Refraction) ---
    // The warp conduit bends light from the destination system. Light arrives
    // distorted and color-split (chromatic aberration) because different
    // wavelengths follow different geodesics through the warped spacetime.
    // This is real gravitational lensing physics — the same effect seen around
    // black holes, here applied to the Alcubierre conduit.
    vec2 screen_uv = SCREEN_UV;
    float warp_strength = 0.15 * edge_fade; // Strong lensing inside the conduit
    screen_uv.x += (n1 - 0.5) * warp_strength;
    screen_uv.y += (n2 - 0.5) * warp_strength;
    
    // Chromatic aberration on the background warp
    float ca = 0.02 * edge_fade;
    float bg_r = texture(screen_texture, screen_uv + vec2(ca, 0.0)).r;
    float bg_g = texture(screen_texture, screen_uv).g;
    float bg_b = texture(screen_texture, screen_uv - vec2(ca, 0.0)).b;
    
    vec3 warped_background = vec3(bg_r, bg_g, bg_b);
    
    // Blend the warped space background with the energy tunnel
    // Dark matter obscures the background, while energy adds to it
    vec3 final_color = mix(warped_background, warped_background * dark_matter_color * 5.0, energy * 0.5);
    final_color += energy_fx * (energy + streaks);
    
    ALBEDO = final_color;
    
    // Fade out the entire tunnel at the edges to reveal normal space seamlessly
    ALPHA = edge_fade * clamp(energy + streaks + 0.1, 0.0, 1.0);
}
