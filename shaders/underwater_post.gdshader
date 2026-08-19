shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// ============================================================================
// BIOGENESIS-X — UNDERWATER POST-PROCESSING SHADER
// AAA+ 4-Layer Depth Fog, Caustics, Distortion, Particulates & Pressure Vignette
// ============================================================================
// Applied as a full-screen ColorRect (CanvasLayer) when the camera is below
// the ocean surface. Drives four depth-layer presets:
//   SHALLOW  (0-30m)    bright, clear, warm color, strong caustics
//   MID      (30-200m)  moderate light, blue-green, moderate caustics
//   DEEP     (200-1000m) dim, dark blue, weak caustics, bioluminescence begins
//   ABYSS    (1000m+)    near black, bioluminescent creatures, pressure vignette
// ============================================================================

group_uniforms Depth_State;
uniform float water_depth : hint_range(0.0, 6000.0, 1.0) = 0.0;     // Sea floor depth (m)
uniform float camera_depth : hint_range(0.0, 6000.0, 1.0) = 0.0;    // Player camera depth below surface (m)

group_uniforms Fog;
uniform vec4 fog_color : source_color = vec4(0.02, 0.18, 0.32, 1.0);
uniform float fog_density : hint_range(0.0, 0.2, 0.001) = 0.04;
uniform float caustic_scale : hint_range(0.5, 20.0, 0.1) = 4.0;
uniform float bioluminescence_intensity : hint_range(0.0, 4.0, 0.05) = 1.0;
uniform float pressure_intensity : hint_range(0.0, 2.0, 0.01) = 0.0;

group_uniforms Time;
uniform float time = 0.0;

group_uniforms Screen_Distortion;
uniform float distortion_amount : hint_range(0.0, 0.02, 0.0005) = 0.0025;
uniform float distortion_speed : hint_range(0.0, 4.0, 0.05) = 0.8;

// Layer thresholds (metres) — kept as uniforms so the GDScript side can tune them
group_uniforms Layer_Thresholds;
uniform float shallow_max : hint_range(1.0, 200.0, 1.0) = 30.0;
uniform float mid_max : hint_range(50.0, 800.0, 1.0) = 200.0;
uniform float deep_max : hint_range(300.0, 4000.0, 1.0) = 1000.0;

// ----------------------------------------------------------------------------
// Procedural noise helpers
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

// Voronoi-ish caustic pattern: sharp network of light lines
float caustics(vec2 uv, float t) {
	vec2 p = uv * caustic_scale;
	p += vec2(sin(t * 0.3 + uv.y * 6.0), cos(t * 0.27 + uv.x * 6.0)) * 0.35;
	vec2 g = abs(fract(p) - 0.5);
	float v = 1.0 - smoothstep(0.0, 0.08, min(g.x, g.y));
	// Secondary octave
	vec2 p2 = uv * caustic_scale * 2.1 + t * 0.2;
	vec2 g2 = abs(fract(p2) - 0.5);
	v += 0.5 * (1.0 - smoothstep(0.0, 0.06, min(g2.x, g2.y)));
	return clamp(v, 0.0, 2.0);
}

// ----------------------------------------------------------------------------
// Layer preset: returns (tint, fog_density_mult, caustic_mult, bio_mult,
// pressure_mult, vignette_intensity)
// ----------------------------------------------------------------------------
vec4 layer_params(float depth) {
	if (depth < shallow_max) {
		// SHALLOW: bright, clear, warm
		return vec4(0.45, 1.0, 1.0, 0.05); // caustic_mult, bio_mult, pressure_mult, vignette
	} else if (depth < mid_max) {
		// MID: moderate
		float k = (depth - shallow_max) / max(mid_max - shallow_max, 0.001);
		return mix(vec4(0.45, 1.0, 1.0, 0.05), vec4(0.25, 0.6, 0.4, 0.18), k);
	} else if (depth < deep_max) {
		// DEEP: dim, bioluminescence begins
		float k = (depth - mid_max) / max(deep_max - mid_max, 0.001);
		return mix(vec4(0.25, 0.6, 0.4, 0.18), vec4(0.08, 1.6, 0.9, 0.45), k);
	} else {
		// ABYSS: near black, strong bio, heavy pressure
		float k = clamp((depth - deep_max) / 2000.0, 0.0, 1.0);
		return mix(vec4(0.08, 1.6, 0.9, 0.45), vec4(0.02, 2.4, 1.6, 0.85), k);
	}
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;

	// --- Screen-space ripple distortion ---
	float dist_t = time * distortion_speed;
	vec2 distort = vec2(
		fbm2d(uv * 8.0 + vec2(dist_t, 0.0)) - 0.5,
		fbm2d(uv * 8.0 + vec2(0.0, dist_t * 1.13)) - 0.5
	) * distortion_amount;
	vec2 sample_uv = uv + distort;

	// --- Sample the screen (already-rendered underwater scene) ---
	vec4 scene = texture(screen_texture, sample_uv);

	// --- Depth fog (exponential in view distance via depth buffer) ---
	float scene_depth = texture(screen_texture, sample_uv).a; // not linear depth; use as proxy
	// Use a pseudo depth from luminance falloff is unreliable; instead drive fog by
	// camera_depth + a screen-edge atmospheric term.
	float view_fog = 1.0 - exp(-fog_density * camera_depth * 0.05);
	view_fog = clamp(view_fog, 0.0, 1.0);

	// --- Layer preset ---
	vec4 lp = layer_params(camera_depth);
	float caustic_mult = lp.x;
	float bio_mult = lp.y;
	float pressure_mult = lp.z;
	float vignette_base = lp.w;

	// --- Caustics overlay (animated light network) ---
	float c = caustics(uv, time) * caustic_mult;
	// Caustics fade with depth (less light penetrates)
	float caustic_fade = exp(-camera_depth * 0.004);
	vec3 caustic_col = vec3(0.7, 0.9, 1.0) * c * caustic_fade * 0.35;

	// --- Color shift toward blue/green with depth ---
	vec3 deep_tint = mix(vec3(0.05, 0.22, 0.38), vec3(0.01, 0.04, 0.12),
		clamp(camera_depth / deep_max, 0.0, 1.0));
	vec3 tinted = mix(scene.rgb, deep_tint, view_fog * 0.85);

	// Apply fog color blend
	tinted = mix(tinted, fog_color.rgb, view_fog * 0.6);

	// --- Bioluminescent particulates / motes ---
	vec3 bio_col = vec3(0.0);
	if (bio_mult > 0.001 && bioluminescence_intensity > 0.001) {
		vec2 bio_uv = uv * vec2(res.x / res.y, 1.0) * 18.0 + time * 0.05;
		float bn = fbm2d(bio_uv);
		float motes = pow(smoothstep(0.60, 0.97, bn), 5.0);
		float pulse = 0.55 + 0.45 * sin(time * 1.9 + bn * 22.0);
		// Drifting motes parallax with depth
		float drift = sin(time * 0.3 + uv.y * 12.0) * 0.5 + 0.5;
		bio_col = vec3(0.2, 0.9, 0.75) * motes * pulse * bio_mult * bioluminescence_intensity * drift;
	}

	// --- Pressure darkening & vignette ---
	float pressure = pressure_intensity * pressure_mult;
	float darkness = 1.0 - pressure * 0.55;
	// Radial vignette
	vec2 vc = uv - 0.5;
	float vig = 1.0 - dot(vc, vc) * (1.2 + vignette_base * 2.5 + pressure * 3.0);
	vig = clamp(vig, 0.0, 1.0);

	vec3 final_col = tinted * darkness * vig;
	final_col += caustic_col;
	final_col += bio_col;

	// Slight saturation reduction at extreme depth (desaturate toward abyss)
	float sat = mix(1.0, 0.55, clamp(camera_depth / deep_max, 0.0, 1.0));
	float lum = dot(final_col, vec3(0.299, 0.587, 0.114));
	final_col = mix(vec3(lum), final_col, sat);

	COLOR = vec4(final_col, 1.0);
}
