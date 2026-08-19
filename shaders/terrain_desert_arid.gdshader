shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 2: DESERT ARID TERRAIN SURFACE SHADER
// ----------------------------------------------------------------------------
// Sandy desert with wind ripple patterns, soft dune shadows, dust particle
// effect on surface, iron-oxide red/orange palette. Fully procedural.
// ============================================================================

group_uniforms Elevation;
uniform float elevation_min = -8000.0;
uniform float elevation_max = 8000.0;
uniform float displacement_strength : hint_range(0.0, 2.0, 0.01) = 0.08;

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float time = 0.0;

group_uniforms Wind;
uniform vec2 wind_direction = vec2(1.0, 0.3);
uniform float wind_speed : hint_range(0.0, 2.0, 0.01) = 0.25;
uniform float ripple_scale : hint_range(2.0, 60.0, 0.5) = 14.0;
uniform float dune_scale : hint_range(0.5, 12.0, 0.1) = 3.0;

group_uniforms Surface;
uniform vec4 sand_color_light : source_color = vec4(0.82, 0.52, 0.28, 1.0);  // iron oxide light
uniform vec4 sand_color_dark : source_color = vec4(0.55, 0.28, 0.12, 1.0);   // iron oxide dark
uniform vec4 dust_color : source_color = vec4(0.90, 0.66, 0.40, 1.0);
uniform float dust_intensity : hint_range(0.0, 2.0, 0.05) = 0.6;

varying vec3 v_world_pos;
varying vec3 v_normal_w;
varying float v_elevation;
varying vec2 v_wind_uv;

// ----------------------------------------------------------------------------
// Procedural hash & noise
// ----------------------------------------------------------------------------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * vnoise2(p);
		p = (p + vec2(3.1, 7.7)) * 2.03;
		a *= 0.5;
	}
	return v;
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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_elevation = clamp((VERTEX.y - elevation_min) / max(elevation_max - elevation_min, 0.001), 0.0, 1.0);

	// Wind-aligned UV that scrolls over time for drifting ripples.
	vec2 wdir = normalize(wind_direction + vec2(0.0001));
	v_wind_uv = UV * ripple_scale + wdir * time * wind_speed;

	// Subtle dune ripple displacement along wind direction.
	float ripple = sin(dot(v_wind_uv, wdir) * 3.0) * 0.5 + 0.5;
	VERTEX.y += ripple * displacement_strength * 0.5;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(VIEW);
	vec3 L = normalize(sun_direction);
	vec2 wdir = normalize(wind_direction + vec2(0.0001));

	// --- Large dune structures (soft gradient shading) ---
	float dune = fbm2(UV * dune_scale + wdir * time * wind_speed * 0.3, 5);
	float dune_shadow = smoothstep(0.35, 0.65, dune);

	// --- Wind ripple patterns (perpendicular to wind, fine) ---
	vec2 ripple_uv = v_wind_uv;
	// Ripples run perpendicular to wind: sample across wind direction.
	float ripple_a = sin(dot(ripple_uv, vec2(-wdir.y, wdir.x)) * 6.2831) * 0.5 + 0.5;
	float ripple_b = fbm2(ripple_uv * 0.5, 3);
	float ripples = ripple_a * 0.6 + ripple_b * 0.4;

	// --- Sand albedo: light/dark iron oxide by dune + ripple modulation ---
	vec3 sand = mix(sand_color_dark.rgb, sand_color_light.rgb, dune_shadow);
	sand += (ripples - 0.5) * 0.10;
	// Fine grain
	float grain = vnoise3(vec3(UV * 40.0, 0.0)) * 0.06;
	sand += grain - 0.03;

	// --- Dune soft shadows: shade lee side (downwind) based on dune gradient ---
	float dune_grad = fbm2(UV * dune_scale + wdir * 0.5, 4) - dune;
	float lee = clamp(-dune_grad * 4.0, 0.0, 1.0);
	sand *= (1.0 - lee * 0.35);

	// --- Sun lighting ---
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, 24.0) * 0.15 * NdotL;
	vec3 albedo_out = sand * (0.30 + 0.70 * NdotL);
	albedo_out += sun_color.rgb * spec;

	// --- Dust particle effect: drifting bright motes near surface ---
	float dust_uv_t = time * wind_speed * 2.0;
	vec2 dust_uv = UV * 30.0 + wdir * dust_uv_t;
	float dust_n = fbm2(dust_uv, 3);
	float dust_motes = pow(smoothstep(0.55, 0.92, dust_n), 5.0);
	// Dust catches sunlight -> glints.
	float dust_glint = dust_motes * (0.5 + 0.5 * sin(time * 5.0 + dust_n * 20.0));
	albedo_out += dust_color.rgb * dust_glint * dust_intensity * NdotL;

	ALBEDO = albedo_out;
	ROUGHNESS = 0.92;
	METALLIC = 0.02;
	EMISSION = dust_color.rgb * dust_glint * dust_intensity * 0.25;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}
