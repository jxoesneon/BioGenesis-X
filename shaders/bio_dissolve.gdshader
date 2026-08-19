shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ============================================================================
// BIO-GENESIS-X: BIO-DISSOLVE / ORGANIC DISINTEGRATION SHADER
// ============================================================================
// Adapted from godotshaders.com dissolve/burn patterns (MIT / CC0 sources).
// Renders an organic disintegration effect for ship death / teleport / spore
// dispersal:
//   - Noise-driven dissolve threshold (cells "melt" away procedurally)
//   - Bioluminescent glowing edge along the dissolution frontier
//   - Cyan-green to magenta edge gradient (healthy -> dissolving)
//   - Dissolve progress driven by uniform `dissolve_amount` [0 = solid, 1 = gone]
// Floating-origin safe: model-space + TIME only.
// ============================================================================

group_uniforms Dissolve_Control;
uniform float dissolve_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_width : hint_range(0.01, 0.5, 0.01) = 0.08;
uniform float noise_scale : hint_range(2.0, 50.0, 0.5) = 18.0;
uniform float noise_speed : hint_range(0.0, 2.0, 0.05) = 0.3;

group_uniforms Color_Palette;
uniform vec4 base_color : source_color = vec4(0.1, 0.4, 0.35, 1.0);    // Dark bio-teal
uniform vec4 edge_color_inner : source_color = vec4(0.0, 1.0, 0.55, 1.0); // Emerald
uniform vec4 edge_color_outer : source_color = vec4(1.0, 0.05, 0.45, 1.0); // Bio-magenta
uniform float emission_boost : hint_range(0.0, 8.0, 0.1) = 3.0;

varying vec3 v_model_pos;

// ----------------------------------------------------------------------------
// Procedural 3D noise (self-contained)
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

void vertex() {
	v_model_pos = VERTEX;
}

void fragment() {
	vec3 pos = v_model_pos;

	// --- Animated noise field ---
	float n = fbm3d(pos * noise_scale + vec3(0.0, 0.0, TIME * noise_speed));

	// --- Dissolve threshold: cells below (dissolve_amount) are removed ---
	float threshold = dissolve_amount;
	float dissolved = n - threshold;

	// Edge band: cells near the threshold glow
	float edge = 1.0 - abs(dissolved) / edge_width;
	edge = clamp(edge, 0.0, 1.0);
	edge = pow(edge, 2.0);

	// --- Visibility: only render cells above threshold ---
	float visible = step(threshold, n);

	// --- Edge color gradient (inner emerald -> outer magenta) ---
	vec3 edge_color = mix(edge_color_inner.rgb, edge_color_outer.rgb, smoothstep(0.0, 1.0, 1.0 - edge));

	// --- Composite ---
	vec3 color = base_color.rgb * visible;
	color += edge_color * edge * 2.5;

	float alpha = visible + edge * 0.8;
	alpha = clamp(alpha, 0.0, 1.0);

	ALBEDO = color * 0.3;
	EMISSION = edge_color * edge * emission_boost;
	ALPHA = alpha;
}
