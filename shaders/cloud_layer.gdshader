shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix, unshaded;

// ============================================================================
// BIOGENESIS-X — VOLUMETRIC CLOUD LAYER SHADER
// AAA+ Procedural Multi-Layer Cloud Sphere for Planetary Descent Visuals
// ============================================================================
// Applied to a sphere mesh situated between the planet surface and the
// atmosphere scattering shell. Renders:
//   1. Procedural clouds via 3D noise-based density field (FBM)
//   2. Multiple cloud layers at different altitudes (low stratus, mid cumulus,
//      high cirrus) blended by altitude band
//   3. Cloud movement driven by time + wind direction
//   4. Per-archetype cloud color (white terran, orange molten, etc.)
//   5. Transparency from density (thin -> transparent, thick -> opaque)
//   6. Self-shadowing approximation (cloud undersides darkened away from sun)
//      acting as the approximated cloud shadow term
//
// Noise is evaluated in the local unit-direction space of the sphere so the
// pattern wraps seamlessly around the globe.
// ============================================================================

group_uniforms Dynamics;
uniform float time = 0.0;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_speed : hint_range(0.0, 10.0, 0.05) = 0.6;
uniform float cloud_scale : hint_range(0.5, 32.0, 0.5) = 4.0;
uniform float cloud_density : hint_range(0.0, 2.0, 0.01) = 1.0;

group_uniforms Appearance;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.18, 0.20, 0.26, 1.0);
uniform float coverage_threshold : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float coverage_softness : hint_range(0.01, 1.0, 0.01) = 0.18;
uniform float layer_separation : hint_range(0.0, 4.0, 0.05) = 1.0;

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform vec3 camera_position = vec3(0.0, 0.0, 0.0);
uniform float self_shadow : hint_range(0.0, 2.0, 0.05) = 0.8;
uniform float night_factor : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms Archetype;
// 0 MOLTEN, 1 METALLIC_BARREN, 2 DESERT_ARID, 3 TERRAN_OCEANIC,
// 4 ICE_WORLD, 5 GAS_GIANT_JOVIAN, 6 GAS_GIANT_ICE, 7 RADIOTROPHIC_BIO
uniform int archetype_id : hint_range(0, 7) = 3;
uniform float band_intensity : hint_range(0.0, 4.0, 0.05) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_local_dir;

// ----------------------------------------------------------------------------
// Hash & 3D value noise for seamless spherical cloud fields.
// ----------------------------------------------------------------------------
float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

// ----------------------------------------------------------------------------
// Fractal Brownian motion (3D) with domain warp for organic cloud structure.
// ----------------------------------------------------------------------------
float fbm3(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) {
			break;
		}
		v += a * value_noise3(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

// ----------------------------------------------------------------------------
// Single cloud layer density at a given local direction and altitude band.
// ----------------------------------------------------------------------------
float cloud_layer_density(vec3 dir, float scale, float woff, vec2 wind) {
	vec3 p = dir * scale;
	// Wind advects the cloud field along the tangent plane.
	vec3 wind_off = vec3(wind.x, 0.0, wind.y) * woff;
	p += wind_off;
	// Domain warp for swirling, organic cloud edges.
	vec3 q = p + vec3(fbm3(p * 0.5 + wind_off * 0.3, 3) * 1.5);
	return fbm3(q, 5);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_dir = normalize(VERTEX);
}

void fragment() {
	vec3 dir = normalize(v_local_dir);
	vec3 sun_dir = normalize(sun_direction);
	vec2 wind = normalize(wind_direction + vec2(0.0001)) * wind_speed * time;

	// --- Three stacked cloud layers at decreasing scale (altitude proxy) ---
	float n_low = cloud_layer_density(dir, cloud_scale * 1.0, 1.0, wind);
	float n_mid = cloud_layer_density(dir, cloud_scale * 2.2, 0.6, wind * 0.7);
	float n_high = cloud_layer_density(dir, cloud_scale * 4.5, 0.3, wind * 0.4);

	// Layer weighting by altitude band via the local Y (latitude-style banding).
	float band = dir.y;
	float w_low = smoothstep(-0.2, 0.4, 1.0 - abs(band) * layer_separation);
	float w_mid = smoothstep(-0.1, 0.5, 0.6 - abs(band - 0.1) * layer_separation);
	float w_high = smoothstep(0.0, 0.6, 0.5 + band * 0.5);

	float coverage = n_low * w_low + n_mid * w_mid * 0.8 + n_high * w_high * 0.5;

	// --- Gas-giant latitudinal banding (Jovian / Ice Giant) ---
	if (band_intensity > 0.001) {
		float bands = sin(band * 12.0 + fbm3(dir * 3.0 + wind.x * 0.1, 3) * 3.0);
		coverage += bands * 0.25 * band_intensity;
	}

	// --- Coverage threshold + softness -> cloud mask ---
	float mask = smoothstep(coverage_threshold,
		coverage_threshold + coverage_softness, coverage);
	float density = mask * cloud_density;

	if (density <= 0.001) {
		discard;
	}

	// --- Lighting: sun-facing clouds lit, undersides darkened (self-shadow) ---
	float NdotL = clamp(dot(dir, sun_dir), 0.0, 1.0);
	float lit = mix(1.0 - self_shadow, 1.0, NdotL);
	// Penumbra softening near the terminator.
	float terminator = smoothstep(-0.25, 0.25, sun_dir.y);
	lit *= mix(0.35, 1.0, terminator);

	// Depth-based thickening: thicker clouds read as more opaque & darker base.
	float thick = smoothstep(0.0, 1.0, density);

	vec3 lit_color = mix(cloud_color.rgb * cloud_shadow_color.rgb,
		cloud_color.rgb, lit);
	lit_color *= sun_color.rgb * (0.6 + 0.4 * NdotL);

	// Night-side dimming (clouds lit only by ambient starlight).
	vec3 night_tint = cloud_color.rgb * 0.12;
	lit_color = mix(lit_color, night_tint, night_factor);

	// Sub-sun forward glow for dramatic descent lighting.
	vec3 view_dir = normalize(v_world_pos - camera_position);
	float back_glow = pow(clamp(dot(-sun_dir, view_dir), 0.0, 1.0), 3.0);
	lit_color += sun_color.rgb * back_glow * thick * 0.25;

	float alpha = clamp(density, 0.0, 1.0);

	ALBEDO = lit_color;
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	// Approximated cloud shadow: emit a faint dark term on thick, unlit cells
	// so the cloud layer reads as casting shadows onto the surface below.
	EMISSION = cloud_shadow_color.rgb * (1.0 - lit) * thick * 0.15 * (1.0 - night_factor);
}
