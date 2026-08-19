shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ============================================================================
// BIO-GENESIS-X: BIO-CAUSTIC FLUID SHADER
// ============================================================================
// Adapted from godotshaders.com caustics/water patterns (MIT / CC0 sources).
// Renders animated organic fluid caustics for amniotic tanks, bio-fluid
// surfaces, and bioluminescent liquid pools:
//   - Procedural caustic light patterns (no texture dependency)
//   - Layered flowing noise for depth & turbulence
//   - Cyan-green to amber biopunk palette (bio-fluid glow)
//   - Fresnel-based surface sheen
// Use for: amniotic fluid tanks, bio-reactor surfaces, planet bio-oceans.
// Floating-origin safe: UV + TIME only.
// ============================================================================

group_uniforms Caustic_Dynamics;
uniform float caustic_scale : hint_range(1.0, 30.0, 0.5) = 8.0;
uniform float caustic_speed : hint_range(0.0, 3.0, 0.05) = 0.6;
uniform float caustic_intensity : hint_range(0.0, 4.0, 0.05) = 1.8;
uniform float caustic_sharpness : hint_range(1.0, 12.0, 0.5) = 4.0;
uniform int caustic_layers : hint_range(1, 4, 1) = 3;

group_uniforms Surface;
uniform float flow_speed : hint_range(0.0, 2.0, 0.05) = 0.3;
uniform float flow_scale : hint_range(1.0, 15.0, 0.5) = 4.0;

group_uniforms Color_Palette;
uniform vec4 deep_color : source_color = vec4(0.0, 0.25, 0.3, 1.0);     // Dark bio-teal
uniform vec4 shallow_color : source_color = vec4(0.0, 0.9, 0.7, 1.0);   // Cyan-green
uniform vec4 caustic_color : source_color = vec4(1.0, 0.75, 0.2, 1.0);  // Amber caustics
uniform float emission_boost : hint_range(0.0, 6.0, 0.1) = 2.0;

group_uniforms Fresnel;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 3.0;
uniform float rim_boost : hint_range(0.0, 4.0, 0.1) = 1.2;

// ----------------------------------------------------------------------------
// 2D noise (UV-space)
// ----------------------------------------------------------------------------
float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
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
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		val += amp * noise2d(p);
		p *= 2.13;
		amp *= 0.47;
	}
	return val;
}

// Procedural caustics via layered abs-noise (cheap, texture-free)
float caustics(vec2 uv, float t) {
	float c = 0.0;
	float amp = 1.0;
	vec2 p = uv;
	for (int i = 0; i < 4; i++) {
		if (i >= caustic_layers) break;
		vec2 q = p + vec2(t * 0.7, -t * 0.5) * (1.0 + float(i) * 0.3);
		float n = fbm2d(q);
		// Sharp ridged pattern = caustic light beams
		c += amp * pow(1.0 - abs(n - 0.5) * 2.0, caustic_sharpness);
		p *= 1.8;
		amp *= 0.55;
	}
	return c / 1.8;
}

void fragment() {
	vec2 uv = UV * caustic_scale;
	float t = TIME * caustic_speed;

	// --- Caustic light pattern ---
	float caustic = caustics(uv, t);
	caustic = pow(caustic, 1.5) * caustic_intensity;

	// --- Surface flow (slow drift) ---
	float flow = fbm2d(UV * flow_scale + vec2(TIME * flow_speed, -TIME * flow_speed * 0.7));

	// --- Depth gradient (shallow -> deep via flow) ---
	float depth = clamp(flow * 1.2, 0.0, 1.0);
	vec3 base = mix(shallow_color.rgb, deep_color.rgb, depth);

	// --- Fresnel sheen ---
	float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - NdotV, rim_power) * rim_boost;

	// --- Composite ---
	vec3 color = base;
	color += caustic_color.rgb * caustic * 1.5;
	color += shallow_color.rgb * rim;

	float alpha = 0.75 + caustic * 0.2 + rim * 0.3;
	alpha = clamp(alpha, 0.0, 1.0);

	ALBEDO = color * 0.4;
	EMISSION = (caustic_color.rgb * caustic + shallow_color.rgb * rim * 0.5) * emission_boost;
	ROUGHNESS = 0.25;
	METALLIC = 0.0;
	ALPHA = alpha;
}
