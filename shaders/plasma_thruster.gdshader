shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never;

// ============================================================================
// PLASMA THRUSTER EXHAUST SHADER - BioGenesis-X
// Pumilio Studios - 3D Organic Mesh & Shader System
// ============================================================================

group_uniforms Flame_Palette;
uniform vec4 core_flame_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);   // Hot Core: Ultra-bright Cyan/White
uniform vec4 mid_flame_color : source_color = vec4(0.0, 0.65, 1.0, 1.0);    // Mid Plume: Bio-Plasma Blue
uniform vec4 outer_flame_color : source_color = vec4(1.0, 0.0, 0.5, 0.8);   // Tail Edge: Bio-Violet/Magenta

group_uniforms Dynamics_And_Noise;
uniform float scroll_speed : hint_range(0.5, 20.0, 0.5) = 8.0;
uniform float turbulence_scale : hint_range(1.0, 50.0, 1.0) = 15.0;
uniform float vertex_displacement_strength : hint_range(0.0, 2.0, 0.05) = 0.35;
uniform float emission_intensity : hint_range(1.0, 50.0, 1.0) = 18.0;
uniform float plume_falloff_exp : hint_range(0.5, 5.0, 0.1) = 2.0;

group_uniforms Spark_And_Shockwave;
uniform float spark_density : hint_range(0.0, 1.0, 0.05) = 0.55;
uniform float spark_brightness : hint_range(0.0, 10.0, 0.5) = 4.0;
uniform float shockwave_intensity : hint_range(0.0, 3.0, 0.1) = 1.2;
uniform float heat_distortion : hint_range(0.0, 0.1, 0.005) = 0.025;

// ----------------------------------------------------------------------------
// Procedural Simplex-like Noise
// ----------------------------------------------------------------------------
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Upgraded to 4 octaves for richer plasma turbulence
float fbm(vec2 p) {
    float val = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        val += amp * noise(p);
        p *= 2.02;
        amp *= 0.5;
    }
    return val;
}

// Hash-based spark/ember particle generation
float spark_particles(vec2 uv, float time_val) {
    float sparks = 0.0;
    // Multiple spark layers at different scales
    for (int layer = 0; layer < 3; layer++) {
        float scale = 30.0 + float(layer) * 20.0;
        vec2 spark_uv = uv * scale;
        // Scroll sparks along plume direction
        spark_uv.y -= time_val * (12.0 + float(layer) * 4.0);
        
        vec2 cell = floor(spark_uv);
        vec2 local = fract(spark_uv) - 0.5;
        
        float h = hash(cell + float(layer) * 17.3);
        if (h > (1.0 - spark_density * 0.3)) {
            // Random offset within cell
            vec2 spark_pos = vec2(hash(cell * 1.7) - 0.5, hash(cell * 2.3) - 0.5) * 0.6;
            float d = length(local - spark_pos);
            // Tiny bright point
            float spark_shape = exp(-d * d * 180.0);
            // Flicker
            float flicker = 0.5 + 0.5 * sin(time_val * 15.0 + h * 50.0);
            sparks += spark_shape * flicker * (1.0 - float(layer) * 0.25);
        }
    }
    return sparks;
}

void vertex() {
    // Animate nozzle plume pulsation & expansion along local normal
    vec2 noise_uv = vec2(UV.x * 4.0, UV.y * turbulence_scale - TIME * scroll_speed);
    float disp = fbm(noise_uv);
    
    // Heat distortion shimmer — high-frequency vertex wobble
    float shimmer = sin(UV.y * 80.0 + TIME * 25.0) * cos(UV.x * 60.0 + TIME * 18.0);
    float shimmer_mask = (1.0 - UV.y) * heat_distortion; // Stronger near nozzle base
    
    // Taper displacement near nozzle root (UV.y = 0) and amplify near tail (UV.y = 1)
    float disp_factor = sin(UV.y * 3.14159) * vertex_displacement_strength;
    VERTEX += NORMAL * ((disp - 0.5) * disp_factor + shimmer * shimmer_mask);
}

void fragment() {
    // Heat distortion UV shimmer
    float shimmer_uv = sin(UV.y * 40.0 + TIME * 20.0) * heat_distortion * (1.0 - UV.y);
    vec2 distorted_uv = UV + vec2(shimmer_uv, 0.0);

    // 1. UV Scrolling & Turbulent Plasma Noise (with heat distortion)
    vec2 scrolling_uv = vec2(distorted_uv.x * 3.0, distorted_uv.y * turbulence_scale - TIME * scroll_speed);
    float plasma_noise = fbm(scrolling_uv);

    // 2. Length Falloff (UV.y from 0 [nozzle base] to 1 [plume tip])
    float length_gradient = clamp(1.0 - UV.y, 0.0, 1.0);
    float plume_alpha = pow(length_gradient, plume_falloff_exp);

    // 3. Radial Edge Erosion (Cylinder/Cone rim falloff)
    float radial_dist = abs(UV.x - 0.5) * 2.0;
    float edge_falloff = pow(clamp(1.0 - radial_dist, 0.0, 1.0), 1.5);

    // 4. Shockwave Ring Effect at Nozzle Base
    float ring_dist = abs(UV.y - 0.05); // Ring positioned near base
    float ring_radial = 1.0 - radial_dist; // Stronger in center
    float ring_pulse = sin(TIME * 8.0) * 0.5 + 0.5;
    float ring_pulse2 = sin(TIME * 12.5 + 2.0) * 0.5 + 0.5;
    float shockwave = exp(-ring_dist * ring_dist * 800.0) * ring_radial;
    shockwave *= (0.6 + 0.4 * ring_pulse) * shockwave_intensity;
    // Secondary expanding ring
    float ring2_pos = fract(TIME * 2.0) * 0.3;
    float ring2_dist = abs(UV.y - ring2_pos);
    float shockwave2 = exp(-ring2_dist * ring2_dist * 400.0) * ring_radial * 0.5;
    shockwave2 *= ring_pulse2 * shockwave_intensity;

    // 5. Multi-stage Flame Gradient Interpolation
    // Near base (length_gradient ~ 1.0): core_flame_color (hot white/cyan)
    // Mid plume: mid_flame_color (deep plasma blue)
    // Outer tail: outer_flame_color (violet/magenta)
    vec3 flame_rgb;
    if (length_gradient > 0.6) {
        float t = (length_gradient - 0.6) / 0.4;
        flame_rgb = mix(mid_flame_color.rgb, core_flame_color.rgb, pow(t, 0.5));
    } else {
        float t = length_gradient / 0.6;
        flame_rgb = mix(outer_flame_color.rgb, mid_flame_color.rgb, t);
    }

    // Add noise turbulence brightness Modulation
    flame_rgb *= (0.7 + plasma_noise * 0.6);

    // 6. Spark / Ember Particles
    float sparks = spark_particles(UV, TIME);
    // Sparks are brighter near plume edges and tail
    float spark_mask = (1.0 - edge_falloff * 0.5) * plume_alpha;
    vec3 spark_color = mix(core_flame_color.rgb, vec3(1.0, 0.7, 0.3), 0.4) * sparks * spark_brightness * spark_mask;

    // 7. Shockwave Ring Color (hot white-cyan at base)
    vec3 shockwave_color = core_flame_color.rgb * (shockwave + shockwave2);

    // 8. Output Color & Emission Glow
    vec3 final_emission = flame_rgb * emission_intensity * plume_alpha * edge_falloff
        + spark_color
        + shockwave_color * emission_intensity * 0.5;
    
    ALBEDO = flame_rgb * plume_alpha * edge_falloff + spark_color * 0.3;
    EMISSION = final_emission;
    ALPHA = clamp(plume_alpha * edge_falloff * outer_flame_color.a + sparks * spark_mask * 0.3 + shockwave * 0.4, 0.0, 1.0);
}
