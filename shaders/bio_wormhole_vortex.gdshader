shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ============================================================================
// BIO-GENESIS-X: BIO-WORMHOLE VORTEX SHADER
// ============================================================================
// Adapted from godotshaders.com portal/vortex patterns (MIT / CC0 sources).
// Renders a swirling bioluminescent energy vortex for wormholes / jump points.
//   - Rotating multi-arm spiral with procedural noise turbulence
//   - Inward radial flow (matter spiraling toward the throat)
//   - Cyan-magenta-amber biopunk palette with HDR emission
//   - Depth-aware darkening toward the vortex center (the "throat")
// Apply to a cylinder/disc mesh oriented face-on to the camera.
// Floating-origin safe: uses UV + TIME only, no world-space dependency.
// ============================================================================

group_uniforms Vortex_Geometry;
uniform float spiral_arms : hint_range(1.0, 8.0, 1.0) = 3.0;
uniform float spiral_tightness : hint_range(0.5, 12.0, 0.1) = 4.0;
uniform float rotation_speed : hint_range(-3.0, 3.0, 0.05) = 0.6;
uniform float throat_radius : hint_range(0.0, 0.8, 0.01) = 0.15;

group_uniforms Flow_Dynamics;
uniform float inflow_speed : hint_range(0.0, 3.0, 0.05) = 0.8;
uniform float turbulence_strength : hint_range(0.0, 2.0, 0.05) = 0.6;
uniform float turbulence_scale : hint_range(1.0, 30.0, 0.5) = 8.0;

group_uniforms Color_Palette;
uniform vec4 arm_color : source_color = vec4(0.0, 0.95, 1.0, 1.0);     // Bio-cyan
uniform vec4 fringe_color : source_color = vec4(1.0, 0.05, 0.45, 1.0); // Bio-magenta
uniform vec4 throat_color : source_color = vec4(1.0, 0.7, 0.15, 1.0);  // Amber
uniform float emission_boost : hint_range(0.0, 8.0, 0.1) = 3.0;

// ----------------------------------------------------------------------------
// 2D noise for turbulence (UV-space shader)
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

void fragment() {
	// Center UVs: (0,0) at disc center
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0; // 0 at center, ~1 at edge
	float angle = atan(uv.y, uv.x);

	// --- Inward radial flow: coordinate spirals inward over time ---
	float flow_r = r + TIME * inflow_speed;
	float spiral = angle * spiral_tightness + flow_r * 6.0 - TIME * rotation_speed * 6.2831;

	// --- Multi-arm spiral intensity ---
	float arm = 0.5 + 0.5 * cos(spiral * spiral_arms);
	arm = pow(arm, 3.0);

	// --- Turbulence (procedural noise) ---
	float turb = fbm2d(uv * turbulence_scale + vec2(TIME * 0.3, -TIME * 0.2));
	arm *= 1.0 + (turb - 0.5) * turbulence_strength * 2.0;

	// --- Radial falloff: bright arms, dark gaps, dark throat ---
	float radial = smoothstep(1.0, 0.2, r) * smoothstep(throat_radius * 0.5, throat_radius, r);

	// --- Throat glow (amber core) ---
	float throat = smoothstep(throat_radius, 0.0, r) * (0.5 + 0.5 * sin(TIME * 4.0));

	// --- Color composite ---
	vec3 color = mix(fringe_color.rgb, arm_color.rgb, smoothstep(0.2, 0.8, r));
	color *= arm * radial * 2.0;
	color += throat_color.rgb * throat * 1.5;

	float alpha = clamp(arm * radial + throat * 0.6, 0.0, 1.0);

	ALBEDO = color * 0.1;
	EMISSION = color * emission_boost;
	ALPHA = alpha;
}
