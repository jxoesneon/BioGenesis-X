shader_type spatial;
render_mode cull_back, depth_draw_opaque, blend_mix;

// ============================================================================
// BIOGENESIS-X — TRUE-SCALE OCEANIC PLANET SURFACE SHADER
// AAA+ Gerstner-Wave Ocean Surface with Fresnel, SSS, Foam & Bioluminescence
// ============================================================================
// Renders a large follow-plane representing the planetary ocean surface.
// Features:
//   1. Multi-direction Gerstner waves (vertex displacement, wind-driven)
//   2. Fresnel sky reflection (grazing-angle mirror, nadir transparency)
//   3. Subsurface scattering approximation (light penetration depth)
//   4. Wave-crest & shoreline foam
//   5. Depth-based color gradient (shallow turquoise -> deep dark blue)
//   6. Night-time bioluminescent particle motes drifting with currents
//   7. Time-animated, wind-driven, sun-lit specular highlights
// ============================================================================

group_uniforms Wave_Dynamics;
uniform vec2 wind_direction = vec2(1.0, 0.0);          // Normalized wind dir
uniform float wind_strength : hint_range(0.0, 15.0, 0.1) = 4.0;
uniform float wave_scale : hint_range(0.05, 8.0, 0.05) = 1.0;
uniform float wave_speed : hint_range(0.0, 4.0, 0.05) = 1.0;
uniform float choppiness : hint_range(0.0, 2.0, 0.05) = 0.65;

group_uniforms Water_Color;
uniform vec4 water_color_shallow : source_color = vec4(0.18, 0.78, 0.72, 1.0); // Turquoise
uniform vec4 water_color_deep : source_color = vec4(0.01, 0.06, 0.22, 1.0);   // Deep blue
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform vec4 biome_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform vec3 camera_position = vec3(0.0, 0.0, 0.0);
uniform float time = 0.0;

group_uniforms Surface_Optics;
uniform float fresnel_power : hint_range(0.5, 12.0, 0.1) = 4.0;
uniform float fresnel_bias : hint_range(0.0, 1.0, 0.01) = 0.02;
uniform float sss_intensity : hint_range(0.0, 4.0, 0.05) = 1.1;
uniform float sss_depth : hint_range(0.1, 20.0, 0.1) = 4.0;
uniform float foam_threshold : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float foam_softness : hint_range(0.01, 1.0, 0.01) = 0.18;
uniform float specular_sharpness : hint_range(1.0, 256.0, 1.0) = 96.0;
uniform float specular_intensity : hint_range(0.0, 8.0, 0.05) = 2.2;

group_uniforms Bioluminescence;
uniform float bioluminescence_intensity : hint_range(0.0, 4.0, 0.05) = 1.4;
uniform float night_factor : hint_range(0.0, 1.0, 0.01) = 0.0;   // 0 = day, 1 = night
uniform float bioluminescence_scale : hint_range(1.0, 80.0, 0.5) = 22.0;

group_uniforms Procedural_Noise;
uniform sampler2D noise_texture : hint_default_white;
uniform float noise_scale : hint_range(0.5, 40.0, 0.5) = 6.0;

varying vec3 v_world_pos;
varying vec3 v_normal_world;
varying float v_gerstner_height;
varying float v_foam_factor;

// ----------------------------------------------------------------------------
// Procedural hash & value noise (UV-space) for foam & bioluminescent motes
// ----------------------------------------------------------------------------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2d(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * value_noise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

// ----------------------------------------------------------------------------
// Gerstner wave: displaces position along wind-driven direction and pinches
// normals for sharp crests. Returns the vertical height contribution.
// ----------------------------------------------------------------------------
float gerstner_wave(
		in vec2 pos,
		in vec2 dir,
		in float amplitude,
		in float wavelength,
		in float speed,
		in float t,
		inout vec3 displacement,
		inout vec3 tangent_accum,
		inout vec3 binormal_accum
	) {
	float k = 6.2831853 / wavelength;        // wavenumber
	float c = speed * sqrt(9.80665 / k);     // phase speed (deep-water disp.)
	vec2 d = normalize(dir);
	float phase = dot(d, pos) * k + t * c;
	float s = sin(phase);
	float crest = pow(0.5 + 0.5 * s, 1.0 + choppiness); // sharpened crest

	// Horizontal displacement (pinch toward crest)
	displacement.xz += d * amplitude * choppiness * cos(phase);
	// Vertical displacement
	displacement.y += amplitude * crest;
	float h = amplitude * crest;

	// Derivatives for normal reconstruction
	float dh_dx = amplitude * d.x * k * cos(phase) * (1.0 + choppiness) * (0.5 + 0.5 * cos(phase));
	float dh_dz = amplitude * d.y * k * cos(phase) * (1.0 + choppiness) * (0.5 + 0.5 * cos(phase));
	tangent_accum += vec3(1.0, dh_dx, 0.0);
	binormal_accum += vec3(0.0, dh_dz, 1.0);
	return h;
}

void vertex() {
	// World-space XZ of the vertex (plane lies in XZ, Y is up)
	vec2 wpos_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float t = time * wave_speed;
	vec2 wdir = normalize(wind_direction + vec2(0.0001));

	// Four stacked Gerstner waves at decreasing amplitude / increasing wavelength
	vec3 disp = vec3(0.0);
	vec3 tang = vec3(0.0);
	vec3 binorm = vec3(0.0);
	float base_amp = wave_scale * (0.25 + 0.75 * wind_strength);

	float h1 = gerstner_wave(wpos_xz, wdir,                    base_amp * 1.00,  9.0, 1.0, t, disp, tang, binorm);
	float h2 = gerstner_wave(wpos_xz, vec2(wdir.y, -wdir.x),   base_amp * 0.55,  4.7, 1.2, t, disp, tang, binorm);
	float h3 = gerstner_wave(wpos_xz, wdir + vec2(0.3, 0.2),   base_amp * 0.30,  2.3, 1.5, t, disp, tang, binorm);
	float h4 = gerstner_wave(wpos_xz, vec2(-wdir.y * 0.6, wdir.x * 0.8), base_amp * 0.16, 1.1, 1.8, t, disp, tang, binorm);

	v_gerstner_height = h1 + h2 + h3 + h4;

	// Apply displacement in local space (MODEL_MATRIX already encodes follow)
	VERTEX += disp;

	// Reconstruct normal from accumulated tangents
	vec3 n = normalize(cross(binorm, tang));
	if (dot(n, vec3(0.0, 1.0, 0.0)) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	v_normal_world = (MODEL_MATRIX * vec4(n, 0.0)).xyz;

	// Foam factor: peaks where crest height is high AND high-frequency chop
	float chop_noise = fbm2d(wpos_xz * 0.4 + t * 0.15);
	float crest_norm = clamp(v_gerstner_height / max(base_amp * 1.8, 0.001), 0.0, 1.0);
	v_foam_factor = smoothstep(foam_threshold, foam_threshold + foam_softness, crest_norm * (0.6 + 0.4 * chop_noise));
}

void fragment() {
	vec3 N = normalize(v_normal_world);
	vec3 V = normalize(camera_position - v_world_pos);
	float NdotV = clamp(dot(N, V), 0.0, 1.0);

	// --- Depth-based color gradient (use world Y of fragment as depth proxy) ---
	// Shallow near crest peaks (high Y), deep in troughs (low Y).
	float depth_grad = clamp(0.5 + 0.5 * v_gerstner_height / max(wave_scale * 2.0, 0.001), 0.0, 1.0);
	vec3 water_col = mix(water_color_deep.rgb, water_color_shallow.rgb, depth_grad);
	water_col *= biome_tint.rgb;

	// --- Fresnel sky reflection ---
	float fresnel = fresnel_bias + (1.0 - fresnel_bias) * pow(1.0 - NdotV, fresnel_power);
	// Approximate sky color from sun direction (warm at horizon, blue at zenith)
	vec3 sky_col = mix(vec3(0.45, 0.62, 0.92), vec3(0.72, 0.82, 0.95), clamp(N.y, 0.0, 1.0));
	sky_col = mix(sky_col, sun_color.rgb * 0.9, clamp(sun_direction.y * 0.5 + 0.5, 0.0, 1.0) * 0.4);
	vec3 reflection = sky_col * fresnel;

	// --- Subsurface scattering approximation ---
	// Light that has travelled through the wave thickness; strongest when
	// back-lit (sun behind wave) and at thin crests viewed from below-grazing.
	vec3 L = normalize(sun_direction);
	float back_light = clamp(dot(-L, V), 0.0, 1.0);
	float thickness = clamp(1.0 - depth_grad, 0.0, 1.0); // crests are "thin"
	float sss = pow(back_light, 2.0) * thickness * sss_intensity;
	vec3 sss_col = mix(water_color_shallow.rgb, sun_color.rgb, 0.3) * sss / sss_depth;

	// --- Sun specular (Blinn-Phong on reconstructed normal) ---
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, specular_sharpness) * specular_intensity * clamp(sun_direction.y, 0.0, 1.0);

	// --- Foam ---
	float foam_n = texture(noise_texture, v_world_pos.xz * noise_scale * 0.25 + time * 0.05).r;
	float foam = v_foam_factor * smoothstep(0.35, 0.75, foam_n);
	vec3 foam_col = foam_color.rgb * foam;

	// --- Bioluminescent motes (night only) ---
	float bio = 0.0;
	if (night_factor > 0.001 && bioluminescence_intensity > 0.001) {
		vec2 bio_uv = v_world_pos.xz * bioluminescence_scale * 0.1 + time * 0.04 * wind_direction;
		float bn = fbm2d(bio_uv);
		float motes = pow(smoothstep(0.55, 0.95, bn), 6.0);
		float pulse = 0.6 + 0.4 * sin(time * 1.7 + bn * 18.0);
		bio = motes * pulse * bioluminescence_intensity * night_factor;
	}
	vec3 bio_col = biome_tint.rgb * bio * 2.2;

	// --- Composite ---
	vec3 base = water_col * (1.0 - fresnel * 0.6);
	vec3 col = base + reflection + sss_col + sun_color.rgb * spec + foam_col + bio_col;

	// Alpha: transparent at nadir (looking straight down into water), opaque at grazing
	float alpha = clamp(0.35 + 0.65 * fresnel + foam * 0.5, 0.35, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.08, 0.35, fresnel);
	SPECULAR = 0.6;
	EMISSION = bio_col + foam_col * 0.15;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0); // keep reconstructed normal (no tangent-space map)
}
