shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// ============================================================================
// BIO-GENESIS-X: BIO-SCAN HOLOGRAM SHADER
// ============================================================================
// Adapted from godotshaders.com hologram/scan-line patterns (MIT / CC0 sources).
// Renders a bioluminescent bio-scan holographic overlay on a mesh:
//   - Sweeping scan line that travels along the mesh (bio-analysis sweep)
//   - Wireframe-style organic grid (hexagonal-ish via noise)
//   - Cyan-green hologram color with flicker & fresnel rim
//   - Edge-boosted silhouette for that "scanning a specimen" look
// Use for: organ inspector, bio-scan targeting, diagnostic overlays.
// Floating-origin safe: model-space + TIME only.
// ============================================================================

group_uniforms Scan_Dynamics;
uniform float scan_speed : hint_range(0.0, 8.0, 0.05) = 1.5;
uniform float scan_width : hint_range(0.01, 0.5, 0.01) = 0.08;
uniform float scan_axis : hint_range(0.0, 2.0, 1.0) = 2.0; // 0=X,1=Y,2=Z
uniform float flicker_speed : hint_range(1.0, 30.0, 0.5) = 12.0;
uniform float flicker_amount : hint_range(0.0, 1.0, 0.05) = 0.15;

group_uniforms Grid_Pattern;
uniform float grid_scale : hint_range(2.0, 80.0, 0.5) = 30.0;
uniform float grid_thickness : hint_range(0.01, 0.3, 0.01) = 0.06;
uniform float grid_intensity : hint_range(0.0, 3.0, 0.05) = 1.2;

group_uniforms Color_Palette;
uniform vec4 scan_color : source_color = vec4(0.0, 0.95, 0.55, 1.0);  // Cyan-green
uniform vec4 grid_color : source_color = vec4(0.1, 0.8, 1.0, 1.0);    // Bio-cyan
uniform vec4 rim_color : source_color = vec4(0.0, 1.0, 0.85, 1.0);    // Emerald rim

group_uniforms Fresnel;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 3.0;
uniform float rim_boost : hint_range(0.0, 4.0, 0.1) = 1.5;

varying vec3 v_model_pos;

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

void vertex() {
	v_model_pos = VERTEX;
}

void fragment() {
	vec3 pos = v_model_pos;

	// --- Sweeping scan line along chosen axis ---
	float axis_coord = 0.0;
	if (scan_axis < 0.5) axis_coord = pos.x;
	else if (scan_axis < 1.5) axis_coord = pos.y;
	else axis_coord = pos.z;

	float sweep = fract(axis_coord * 0.5 + TIME * scan_speed * 0.1);
	float scan_line = smoothstep(1.0 - scan_width, 1.0, sweep) + smoothstep(scan_width, 0.0, sweep) * 0.0;
	scan_line = pow(scan_line, 2.0);

	// --- Organic wireframe grid (noise-thresholded) ---
	float n1 = noise3d(pos * grid_scale);
	float n2 = noise3d(pos * grid_scale + vec3(3.7, 5.9, 8.2));
	float grid = smoothstep(1.0 - grid_thickness, 1.0, max(n1, n2));

	// --- Flicker (procedural, no texture) ---
	float flicker = 1.0 - flicker_amount * (0.5 + 0.5 * sin(TIME * flicker_speed + pos.x * 7.0));

	// --- Fresnel rim ---
	float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - NdotV, rim_power) * rim_boost;

	// --- Composite ---
	vec3 color = vec3(0.0);
	color += scan_color.rgb * scan_line * 3.0;
	color += grid_color.rgb * grid * grid_intensity;
	color += rim_color.rgb * rim;

	color *= flicker;

	float intensity = scan_line * 1.5 + grid * grid_intensity + rim;
	float alpha = clamp(intensity * 0.7, 0.0, 1.0);

	ALBEDO = color * 0.1;
	EMISSION = color * 2.0;
	ALPHA = alpha;
}
