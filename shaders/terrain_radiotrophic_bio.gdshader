shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 7: RADIOTROPHIC BIO TERRAIN SURFACE SHADER
// ----------------------------------------------------------------------------
// Bioluminescent alien world: organic membrane surface with pulsing green/teal
// bioluminescent veins glowing in crevices, green/teal/purple elevation
// palette, drifting spore particles, fungal worley-cell texture, and a
// subsurface scattering approximation for a soft organic feel.
// Fully procedural — no external textures required.
// ============================================================================

group_uniforms Elevation;
uniform float elevation_min = -8000.0;
uniform float elevation_max = 8000.0;
uniform float displacement_strength : hint_range(0.0, 2.0, 0.01) = 0.10;
uniform sampler2D elevation_data : hint_default_white;

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(0.55, 0.95, 0.85, 1.0);
uniform float time = 0.0;

group_uniforms Bio;
uniform vec4 bio_color_low : source_color = vec4(0.10, 0.42, 0.30, 1.0);   // valleys: deep green
uniform vec4 bio_color_mid : source_color = vec4(0.18, 0.68, 0.52, 1.0);   // slopes: teal membrane
uniform vec4 bio_color_high : source_color = vec4(0.34, 0.20, 0.48, 1.0);  // peaks: muted purple
uniform vec4 vein_color : source_color = vec4(0.20, 1.0, 0.78, 1.0);       // bioluminescent teal
uniform vec4 spore_color : source_color = vec4(0.55, 1.0, 0.85, 1.0);      // drifting spores
uniform float pulse_frequency : hint_range(0.05, 8.0, 0.05) = 1.4;
uniform float pulse_amplitude : hint_range(0.0, 2.0, 0.01) = 0.85;
uniform float vein_scale : hint_range(2.0, 60.0, 0.5) = 9.0;
uniform float vein_threshold : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float vein_emission_strength : hint_range(0.0, 12.0, 0.1) = 5.0;
uniform float membrane_scale : hint_range(2.0, 40.0, 0.5) = 7.0;           // worley cell scale
uniform float spore_density : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float spore_scale : hint_range(4.0, 60.0, 0.5) = 18.0;
uniform float spore_drift_speed : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float sss_intensity : hint_range(0.0, 4.0, 0.05) = 1.2;
uniform float sss_depth : hint_range(0.1, 20.0, 0.1) = 2.5;

varying vec3 v_world_pos;
varying vec3 v_normal_w;
varying float v_elevation;
varying float v_slope;
varying vec2 v_spore_uv;

// ----------------------------------------------------------------------------
// Procedural hash & 3D value noise
// ----------------------------------------------------------------------------
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(p + vec3(0, 0, 0)), hash3(p + vec3(1, 0, 0)), f.x),
			mix(hash3(p + vec3(0, 1, 0)), hash3(p + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(p + vec3(0, 0, 1)), hash3(p + vec3(1, 0, 1)), f.x),
			mix(hash3(p + vec3(0, 1, 1)), hash3(p + vec3(1, 1, 1)), f.x), f.y),
		f.z
	);
}

float fbm3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	mat3 rot = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64)
	);
	for (int i = 0; i < oct; i++) {
		v += a * vnoise3(p);
		p = rot * p * 2.02;
		a *= 0.5;
	}
	return v;
}

float ridge3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		float n = 1.0 - abs(vnoise3(p) * 2.0 - 1.0);
		v += a * n * n;
		p *= 2.08;
		a *= 0.48;
	}
	return v;
}

// ----------------------------------------------------------------------------
// Worley / cellular noise (fungal membrane cell pattern)
// Returns F1 (distance to nearest feature point) in .x and F2 in .y.
// ----------------------------------------------------------------------------
vec2 worley3(vec3 p) {
	vec3 pi = floor(p);
	vec3 pf = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 b = vec3(float(x), float(y), float(z));
				vec3 h = vec3(hash3(pi + b), hash3(pi + b + 31.7), hash3(pi + b + 73.1));
				vec3 r = b + h - pf;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec2(sqrt(f1), sqrt(f2));
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Elevation from optional elevation_data sampler, else local Y normalized.
	float elev_tex = texture(elevation_data, UV).r;
	bool has_tex = elev_tex > 0.001 && abs(elev_tex - 1.0) > 0.001;
	v_elevation = has_tex ? elev_tex : clamp((VERTEX.y - elevation_min) / max(elevation_max - elevation_min, 0.001), 0.0, 1.0);
	v_slope = 1.0 - clamp(v_normal_w.y, 0.0, 1.0);

	// Drifting spore UV (slow vertical scroll + lateral wobble).
	v_spore_uv = UV + vec2(time * spore_drift_speed, time * spore_drift_speed * 0.6);

	// Organic membrane bulge: worley cells push surface outward subtly.
	vec2 w = worley3(vec3(UV * membrane_scale, 0.0));
	float bulge = smoothstep(0.0, 0.6, w.x) * displacement_strength;
	VERTEX += NORMAL * bulge;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(VIEW);
	vec3 L = normalize(sun_direction);

	// --- Elevation-based green/teal/purple palette ---
	vec3 base = mix(bio_color_low.rgb, bio_color_mid.rgb, smoothstep(0.0, 0.55, v_elevation));
	base = mix(base, bio_color_high.rgb, smoothstep(0.55, 1.0, v_elevation));

	// --- Fungal / membrane worley texture ---
	vec2 w = worley3(vec3(UV * membrane_scale, time * 0.03));
	float membrane = smoothstep(0.0, 0.35, w.x);            // cell interiors bright
	float cell_edge = smoothstep(0.05, 0.0, w.y - w.x);     // thin membrane walls
	base *= (0.78 + 0.22 * membrane);
	base = mix(base, base * 0.55, cell_edge * 0.6);

	// --- Bioluminescent veins (ridge noise) in crevices ---
	float vein_n = ridge3(vec3(UV * vein_scale, time * 0.05), 5);
	float vein_mask = smoothstep(vein_threshold, vein_threshold + 0.06, vein_n);
	// Veins concentrate in low-elevation crevices and slopes.
	float crevice = (1.0 - v_elevation) * (0.4 + 0.6 * v_slope);
	vein_mask *= crevice;

	// --- Pulsing glow driven by TIME and pulse_frequency ---
	float pulse = 0.5 + 0.5 * sin(time * pulse_frequency + vein_n * 6.2831);
	float pulse_glow = (0.55 + pulse_amplitude * pulse);
	vec3 vein_rgb = vein_color.rgb * pulse_glow;

	// --- Spore-like particles (procedural noise sparkles drifting on surface) ---
	float spore_n = vnoise3(vec3(v_spore_uv * spore_scale, time * spore_drift_speed * 0.5));
	float spores = smoothstep(1.0 - spore_density, 1.0, spore_n);
	// Twinkle
	float twinkle = 0.5 + 0.5 * sin(time * (pulse_frequency * 2.0) + spore_n * 30.0);
	spores *= twinkle;

	// --- Composite albedo ---
	vec3 albedo_out = mix(base, vein_rgb, vein_mask * 0.8);
	albedo_out += spore_color.rgb * spores * 0.35;

	// --- Subsurface scattering approximation (back-lit organic glow) ---
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	float back_light = clamp(dot(-L, V), 0.0, 1.0);
	float thickness = clamp(1.0 - v_elevation, 0.0, 1.0);
	float sss = pow(back_light, 2.0) * thickness * sss_intensity / sss_depth;
	vec3 sss_col = mix(vein_color.rgb, sun_color.rgb, 0.3) * sss;

	// --- Specular (soft membrane sheen) ---
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, 48.0) * 0.30 * NdotL;

	// --- Composite lighting ---
	albedo_out *= (0.30 + 0.70 * NdotL);
	albedo_out += sun_color.rgb * spec;
	albedo_out += sss_col;

	// --- Emission: pulsing veins + spore glow (visible on night side) ---
	float emit = vein_mask * vein_emission_strength * pulse_glow;
	emit += spores * vein_emission_strength * 0.25;
	vec3 emission_out = vein_color.rgb * emit;

	ALBEDO = albedo_out;
	ROUGHNESS = mix(0.55, 0.30, vein_mask);
	METALLIC = 0.0;
	EMISSION = emission_out;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}
