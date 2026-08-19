shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// ============================================================================
// BIO-GENESIS-X: BIO-CONTAINMENT FIELD SHADER
// ============================================================================
// Adapted from godotshaders.com force-field / energy-shield patterns (MIT/CC0).
// Renders a bioluminescent containment / stasis field bubble:
//   - Hexagonal energy mesh (procedural voronoi-like cells)
//   - Pulsing organic flow along the mesh
//   - Fresnel rim glow + intersection highlight
//   - Cyan-amber biopunk palette with HDR emission
// Use for: containment bubbles, stasis fields, bio-barrier projections.
// Floating-origin safe: model-space + TIME only.
// ============================================================================

group_uniforms Field_Geometry;
uniform float mesh_scale : hint_range(2.0, 60.0, 0.5) = 24.0;
uniform float cell_edge_width : hint_range(0.01, 0.3, 0.01) = 0.04;
uniform float pulse_speed : hint_range(0.1, 8.0, 0.1) = 1.5;
uniform float pulse_amplitude : hint_range(0.0, 3.0, 0.05) = 1.0;

group_uniforms Flow;
uniform float flow_speed : hint_range(0.0, 3.0, 0.05) = 0.4;
uniform float flow_scale : hint_range(1.0, 20.0, 0.5) = 6.0;

group_uniforms Color_Palette;
uniform vec4 field_color : source_color = vec4(0.0, 0.9, 1.0, 1.0);    // Bio-cyan
uniform vec4 cell_color : source_color = vec4(1.0, 0.7, 0.15, 1.0);    // Amber
uniform vec4 rim_color : source_color = vec4(0.0, 1.0, 0.55, 1.0);     // Emerald
uniform float emission_boost : hint_range(0.0, 6.0, 0.1) = 2.5;

group_uniforms Fresnel;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.5;
uniform float rim_boost : hint_range(0.0, 5.0, 0.1) = 2.0;
uniform float intersection_sharpness : hint_range(1.0, 20.0, 0.5) = 8.0;

varying vec3 v_model_pos;
varying vec3 v_normal;
varying float v_depth;

// ----------------------------------------------------------------------------
// Procedural 3D noise
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

// Voronoi-like cellular pattern for hex mesh
float voronoi3d(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	float min_dist = 1.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 neighbor = vec3(float(x), float(y), float(z));
				vec3 point = neighbor + 0.5 + 0.5 * sin(TIME * 0.3 + vec3(
					dot(cell + neighbor, vec3(12.9898, 78.233, 37.719)),
					dot(cell + neighbor, vec3(39.346, 11.135, 83.155)),
					dot(cell + neighbor, vec3(73.156, 52.288, 9.151))
				) * 4.37);
				vec3 diff = neighbor + point - local;
				min_dist = min(min_dist, length(diff));
			}
		}
	}
	return min_dist;
}

void vertex() {
	v_model_pos = VERTEX;
	v_normal = NORMAL;
	v_depth = -VERTEX.z; // Approximate view-space depth for intersection
}

void fragment() {
	vec3 pos = v_model_pos;

	// --- Hexagonal / voronoi mesh ---
	float cells = voronoi3d(pos * mesh_scale);
	float cell_edge = smoothstep(0.0, cell_edge_width, cells);
	float mesh_glow = (1.0 - cell_edge) * 1.5;

	// --- Organic flow pulse ---
	float flow = fbm3d(pos * flow_scale + vec3(0.0, 0.0, TIME * flow_speed));
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed + flow * 6.2831);
	pulse = pulse * pulse_amplitude;

	// --- Fresnel rim ---
	float NdotV = clamp(dot(v_normal, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - NdotV, rim_power) * rim_boost;

	// --- Intersection highlight (where field meets geometry behind it) ---
	float intersection = pow(1.0 - NdotV, intersection_sharpness);

	// --- Composite ---
	vec3 color = vec3(0.0);
	color += cell_color.rgb * mesh_glow * (0.5 + pulse);
	color += field_color.rgb * pulse * 0.4;
	color += rim_color.rgb * rim;
	color += field_color.rgb * intersection * 1.5;

	float alpha = clamp(mesh_glow * 0.6 + pulse * 0.3 + rim * 0.5 + intersection, 0.0, 1.0);

	ALBEDO = color * 0.1;
	EMISSION = color * emission_boost;
	ALPHA = alpha * 0.85;
}
