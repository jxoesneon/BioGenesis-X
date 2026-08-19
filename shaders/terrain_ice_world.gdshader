shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 4: ICE WORLD / CRYOGENIC TERRAIN SURFACE SHADER
// ----------------------------------------------------------------------------
// Crystalline ice surface with refraction, blue-white palette, ice cracks and
// crevasses (dark blue lines), snow accumulation on flat surfaces, subsurface
// scattering for ice. Fully procedural — no external textures required.
// ============================================================================

group_uniforms Elevation;
uniform float elevation_min = -8000.0;
uniform float elevation_max = 8000.0;
uniform float displacement_strength : hint_range(0.0, 2.0, 0.01) = 0.06;

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform float time = 0.0;

group_uniforms Ice;
uniform vec4 ice_color_bright : source_color = vec4(0.88, 0.94, 1.0, 1.0);
uniform vec4 ice_color_deep : source_color = vec4(0.42, 0.65, 0.88, 1.0);
uniform vec4 crack_color : source_color = vec4(0.05, 0.18, 0.42, 1.0);
uniform vec4 snow_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform float crack_scale : hint_range(2.0, 60.0, 0.5) = 10.0;
uniform float crack_threshold : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float sss_intensity : hint_range(0.0, 4.0, 0.05) = 1.4;
uniform float sss_depth : hint_range(0.1, 20.0, 0.1) = 3.0;
uniform float refraction_amount : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float snow_flatness : hint_range(0.0, 1.0, 0.01) = 0.65; // snow on flat surfaces

varying vec3 v_world_pos;
varying vec3 v_normal_w;
varying float v_elevation;
varying float v_slope;

// ----------------------------------------------------------------------------
// Procedural hash & noise
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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_elevation = clamp((VERTEX.y - elevation_min) / max(elevation_max - elevation_min, 0.001), 0.0, 1.0);
	v_slope = 1.0 - clamp(v_normal_w.y, 0.0, 1.0); // 0 flat, 1 vertical

	// Subtle ice-crevasse vertex ripple.
	float crack = ridge3(vec3(UV * crack_scale, 0.0), 4);
	VERTEX.y += smoothstep(crack_threshold, crack_threshold + 0.1, crack) * displacement_strength;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(VIEW);
	vec3 L = normalize(sun_direction);

	// --- Ice crevasses: dark blue crack lines via ridge noise ---
	float crack = ridge3(vec3(UV * crack_scale, time * 0.02), 5);
	float crack_mask = smoothstep(crack_threshold, crack_threshold + 0.04, crack);
	// Thin dark line at the very ridge peak
	float crack_line = smoothstep(crack_threshold + 0.04, crack_threshold, crack);

	// --- Crystalline ice base ---
	float ice_n = fbm3(vec3(UV * 6.0, 0.0), 5);
	float micro_frost = vnoise3(vec3(UV * 48.0, 0.0));
	vec3 ice = mix(ice_color_deep.rgb, ice_color_bright.rgb, ice_n);
	ice += (micro_frost - 0.5) * 0.05;
	// Darken along crack lines
	ice = mix(ice, crack_color.rgb, crack_line * 0.85);

	// --- Snow accumulation on flat surfaces ---
	float flatness = 1.0 - smoothstep(0.0, snow_flatness, v_slope);
	float snow_n = fbm3(vec3(UV * 14.0, 1.0), 4);
	float snow_amt = flatness * smoothstep(0.4, 0.7, snow_n);
	vec3 snow = snow_color.rgb * (0.94 + 0.06 * snow_n);
	vec3 albedo_out = mix(ice, snow, snow_amt);

	// --- Subsurface scattering for ice (back-lit glow through thickness) ---
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	float back_light = clamp(dot(-L, V), 0.0, 1.0);
	float thickness = clamp(1.0 - v_elevation, 0.0, 1.0); // thicker at low elev
	float sss = pow(back_light, 2.0) * thickness * sss_intensity / sss_depth;
	vec3 sss_col = mix(ice_color_deep.rgb, sun_color.rgb, 0.25) * sss;

	// --- Refraction approximation: perturb sampling by view-dependent offset ---
	// (Faked as an albedo tint shift toward deep ice at grazing angles.)
	float NdotV = clamp(dot(N, V), 0.0, 1.0);
	float refr = pow(1.0 - NdotV, 3.0) * refraction_amount;
	albedo_out = mix(albedo_out, ice_color_deep.rgb, refr * 0.5);

	// --- Specular (sharp ice glint) ---
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, 96.0) * 0.6 * NdotL;

	// --- Composite lighting ---
	albedo_out *= (0.35 + 0.65 * NdotL);
	albedo_out += sun_color.rgb * spec;
	albedo_out += sss_col;

	// Crystalline shimmer sparkle
	float sparkle = pow(vnoise3(vec3(UV * 120.0, time * 0.5)), 18.0);
	albedo_out += sun_color.rgb * sparkle * 0.5 * NdotL;

	ALBEDO = albedo_out;
	ROUGHNESS = mix(0.18, 0.45, snow_amt);
	METALLIC = 0.10;
	EMISSION = sss_col * 0.4;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}
