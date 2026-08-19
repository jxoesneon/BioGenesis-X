shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 conduit_base_color : source_color = vec3(0.05, 0.08, 0.12);
uniform vec3 fluid_glow_color : source_color = vec3(0.0, 0.85, 0.75);
uniform float pulse_speed = 2.5;
uniform float pulse_frequency = 4.0;
uniform float emission_strength = 2.2;
uniform float metallic_val = 0.85;
uniform float roughness_val = 0.2;

void fragment() {
    float wave = sin(UV.y * pulse_frequency * 6.28318 - TIME * pulse_speed) * 0.5 + 0.5;
    wave = pow(wave, 2.5);
    
    // Core fluid conduit pulse
    vec3 col = mix(conduit_base_color, fluid_glow_color, wave * 0.7);
    
    ALBEDO = col;
    METALLIC = metallic_val;
    ROUGHNESS = roughness_val;
    EMISSION = fluid_glow_color * wave * emission_strength;
}
