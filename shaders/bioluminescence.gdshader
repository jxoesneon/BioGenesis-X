shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ============================================================================
// ADVANCED PBR BIOLUMINESCENCE GLOW SHADER - BioGenesis-X
// Pumilio Studios - AAA+ Next-Gen Biological PBR System
// ============================================================================
// Features:
// 1. Continuous 3D Model-Space Vascular Traveling Waves (No Quad Seams)
// 2. Multi-Octave FBM Synaptic Nerve Filaments & Hemolymph Pulses
// 3. PBR Glassy Keratin Lens Shading (Roughness, Metallic, SSS Translucency)
// 4. Chromatic Aberration & Lens Dispersion at Glancing Angles
// 5. Dynamic Organic Vein Jitter & Cellular Luminescence
// ============================================================================

group_uniforms Color_Gradient_Palette;
uniform vec4 primary_color : source_color = vec4(0.0, 0.95, 1.0, 1.0);     // Default: Bio-Cyan
uniform vec4 secondary_color : source_color = vec4(1.0, 0.05, 0.45, 1.0);  // Default: Deep Bio-Pink
uniform vec4 core_color : source_color = vec4(0.0, 1.0, 0.55, 1.0);       // Default: Emerald Green

group_uniforms Procedural_PBR_Textures;
uniform sampler2D noise_texture_macro : hint_default_white;
uniform sampler2D noise_texture_micro : hint_default_white;

group_uniforms Pulsing_Dynamics;
uniform float pulse_frequency : hint_range(0.1, 10.0, 0.1) = 2.5;
uniform float pulse_min : hint_range(0.0, 1.0, 0.05) = 0.40;
uniform float pulse_max : hint_range(1.0, 25.0, 0.5) = 8.0;
uniform float pulse_harmonic_mix : hint_range(0.0, 1.0, 0.05) = 0.35;

group_uniforms Vascular_Conduit_Flow;
uniform float wave_frequency : hint_range(0.0, 20.0, 0.1) = 3.5;
uniform float wave_speed : hint_range(-20.0, 20.0, 0.5) = 5.0;
uniform float wave_sharpness : hint_range(1.0, 10.0, 0.5) = 3.2;

group_uniforms Lens_Fresnel;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.4;
uniform float rim_boost : hint_range(0.0, 5.0, 0.1) = 2.0;

group_uniforms Vein_Pattern;
uniform float vein_scale : hint_range(1.0, 50.0, 0.5) = 14.0;
uniform float vein_glow_intensity : hint_range(0.0, 10.0, 0.1) = 2.5;
uniform float chromatic_aberration : hint_range(0.0, 0.05, 0.001) = 0.015;

varying vec3 v_model_pos;

// ----------------------------------------------------------------------------
// Procedural 3D Noise Helpers
// ----------------------------------------------------------------------------
float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash31(i);
    float b = hash31(i + vec3(1.0, 0.0, 0.0));
    float c = hash31(i + vec3(0.0, 1.0, 0.0));
    float d = hash31(i + vec3(1.0, 1.0, 0.0));
    float e = hash31(i + vec3(0.0, 0.0, 1.0));
    float f1 = hash31(i + vec3(1.0, 0.0, 1.0));
    float g = hash31(i + vec3(0.0, 1.0, 1.0));
    float h = hash31(i + vec3(1.0, 1.0, 1.0));
    
    float nx0 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    float nx1 = mix(mix(e, f1, f.x), mix(g, h, f.x), f.y);
    return mix(nx0, nx1, f.z);
}

float fbm3d(vec3 p) {
    float val = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        val += amp * noise3d(p);
        p *= 2.15;
        amp *= 0.46;
    }
    return val;
}

// Ridged 3D Vein Filaments
float vein3d(vec3 p) {
    float n1 = fbm3d(p);
    float n2 = fbm3d(p * 1.6 + vec3(3.7, 5.9, 8.2));
    float ridged1 = 1.0 - abs(n1 - 0.5) * 2.0;
    float ridged2 = 1.0 - abs(n2 - 0.5) * 2.0;
    return clamp(pow(ridged1, 3.5) + pow(ridged2, 4.0) * 0.6, 0.0, 1.0);
}

void vertex() {
    v_model_pos = VERTEX;
}

void fragment() {
    vec3 pos = v_model_pos;

    // 1. Triple-Harmonic Pulse Frequency
    float time = TIME * pulse_frequency;
    float primary_sine   = sin(time) * 0.5 + 0.5;
    float secondary_sine = sin(time * 2.3 + 1.2) * 0.5 + 0.5;
    float tertiary_sine  = sin(time * 0.618 + 2.8) * 0.5 + 0.5; // Golden ratio subharmonic
    
    float pulse_raw = mix(mix(primary_sine, secondary_sine, pulse_harmonic_mix), tertiary_sine, 0.20);
    float glow_multiplier = mix(pulse_min, pulse_max, pulse_raw);

    // 2. Continuous 3D Vascular Traveling Wave along Ship Longitudinal Axis (Z-axis)
    float wave_pos = pos.z * wave_frequency - TIME * wave_speed;
    float wave_pulse = pow(sin(wave_pos) * 0.5 + 0.5, wave_sharpness);
    float sub_wave   = pow(sin(wave_pos * 0.42 + 1.7) * 0.5 + 0.5, wave_sharpness * 0.8);
    wave_pulse = mix(wave_pulse, sub_wave, 0.25);

    // 3. Fresnel / Lens Rim Glow
    float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float rim_glow = pow(1.0 - NdotV, rim_power) * rim_boost;

    // 4. 3D Synaptic Nerve & Vein Filaments
    float veins = vein3d(pos * vein_scale + vec3(0.0, 0.0, TIME * 0.15));
    float vein_pulse = veins * (0.5 + 0.5 * sin(TIME * 2.0 + pos.z * 2.0));
    vec3 vein_color = mix(primary_color.rgb, core_color.rgb, veins) * vein_pulse * vein_glow_intensity;

    // 5. Chromatic Aberration Dispersion
    float ca_dispersion = chromatic_aberration * pow(1.0 - NdotV, 2.0);
    float wave_r = pow(sin((pos.z + ca_dispersion * 3.0) * wave_frequency - TIME * wave_speed) * 0.5 + 0.5, wave_sharpness);
    float wave_b = pow(sin((pos.z - ca_dispersion * 3.0) * wave_frequency - TIME * wave_speed) * 0.5 + 0.5, wave_sharpness);

    // 6. Color Gradient Composite
    vec3 gradient_color = mix(primary_color.rgb, secondary_color.rgb, wave_pulse);
    gradient_color.r = mix(primary_color.r, secondary_color.r, wave_r);
    gradient_color.b = mix(primary_color.b, secondary_color.b, wave_b);
    
    // Core translucent depth
    float core_lens = pow(NdotV, 1.5);
    vec3 final_color = mix(gradient_color, core_color.rgb, core_lens * 0.5);
    final_color += vein_color;
    final_color += core_color.rgb * rim_glow;

    // 7. PBR Lens Properties
    ALBEDO = final_color * 0.15;
    METALLIC = 0.15;
    ROUGHNESS = 0.12; // Glassy organic lens
    SPECULAR = 0.85;

    // HDR Emission Output
    EMISSION = final_color * (glow_multiplier + wave_pulse * 4.0 + rim_glow * 2.5 + vein_pulse * 2.0);
}
