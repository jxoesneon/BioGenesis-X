shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// ============================================================================
// ALCUBIERRE WAVE ENGINE SHADER - BioGenesis-X
// Pumilio Studios — Spacetime Warp Plane Visual Effect
// ============================================================================
// Depicts the Alcubierre metric as a translucent grid plane that materializes
// around the ship. The front of the plane deforms and dips DOWN (spacetime
// contraction ahead of the ship), while the back RAISES UP (spacetime
// expansion behind the ship). The ship rides inside a flat warp bubble.
//
// The shape function uses the Alcubierre tanh form:
//   f(r_s) = (tanh(σ(r_s + R)) - tanh(σ(r_s - R))) / (2 * tanh(σR))
// where r_s is the distance from the bubble center along the travel axis,
// R is the bubble radius, and σ is the skin depth (wall thickness).
//
// Vertex displacement: the grid plane's Y coordinate is displaced by the
// York time (expansion scalar) θ = v_s * df/dr_s, producing the visual
// "dip in front, raise behind" spacetime distortion.
// ============================================================================

group_uniforms Warp_Bubble;
uniform float bubble_radius : hint_range(2.0, 50.0, 0.5) = 12.0;    // R: flat region radius
uniform float skin_depth : hint_range(0.5, 20.0, 0.1) = 4.0;        // σ: wall thickness (inverse)
uniform float wave_velocity : hint_range(0.0, 1.0, 0.01) = 0.0;     // Normalized 0..1 (engaged intensity)
uniform float plane_size : hint_range(10.0, 200.0, 1.0) = 60.0;     // Total grid plane extent

group_uniforms Visual_Appearance;
uniform vec4 grid_color : source_color = vec4(0.8, 0.95, 1.0, 0.2);  // Bio-cyan warp field (translucent white)
uniform vec4 contraction_color : source_color = vec4(0.2, 0.5, 1.0, 0.9); // Blue (front dip)
uniform vec4 expansion_color : source_color = vec4(1.0, 0.3, 0.6, 0.9);   // Magenta (rear raise)
uniform float grid_line_thickness : hint_range(0.5, 10.0, 0.1) = 2.0;
uniform float grid_cell_size : hint_range(0.5, 10.0, 0.1) = 2.0;
uniform float glow_intensity : hint_range(0.0, 5.0, 0.1) = 1.5;
uniform float opacity : hint_range(0.0, 1.0, 0.05) = 0.0;           // Animated 0→1 on materialize

group_uniforms Animation;
uniform float time_scale : hint_range(0.0, 5.0, 0.1) = 1.0;
uniform float pulse_frequency : hint_range(0.1, 10.0, 0.1) = 1.5;

// Alcubierre shape function f(r_s)
// Returns 1.0 inside the bubble, 0.0 outside, smooth tanh transition at walls.
float alcubierre_shape(float r_s, float R, float sigma) {
	float denom = 2.0 * tanh(sigma * R);
	if (abs(denom) < 0.001) return 0.0;
	return (tanh(sigma * (r_s + R)) - tanh(sigma * (r_s - R))) / denom;
}

// York time (expansion scalar): θ = d(f)/d(r_s)
// Positive = expansion (behind ship), negative = contraction (ahead of ship).
float york_time(float r_s, float R, float sigma) {
	float denom = 2.0 * tanh(sigma * R);
	if (abs(denom) < 0.001) return 0.0;
	float dsigma = sigma;
	// Derivative of tanh is sech² = 1 - tanh²
	float d_plus = dsigma * (1.0 - tanh(sigma * (r_s + R)) * tanh(sigma * (r_s + R)));
	float d_minus = dsigma * (1.0 - tanh(sigma * (r_s - R)) * tanh(sigma * (r_s - R)));
	return (d_plus - d_minus) / denom;
}

void vertex() {
	// Local space: ship forward is -Z, so "ahead" = -Z (negative Z), "behind" = +Z (positive Z)
	// r_s = distance along travel axis from bubble center
	float r_s = VERTEX.z;  // Positive Z = behind ship, Negative Z = ahead

	// Compute York time displacement
	float theta = york_time(r_s, bubble_radius, skin_depth);

	// Scale displacement by wave velocity (0 at rest, 1 at full cruise)
	float displacement = theta * wave_velocity * 8.0;

	// Apply Y displacement: contraction (ahead, theta<0) dips DOWN,
	// expansion (behind, theta>0) raises UP
	VERTEX.y += displacement;

	// Slight inward pinch at the bubble walls for visual depth
	float shape = alcubierre_shape(r_s, bubble_radius, skin_depth);
	VERTEX.x *= 1.0 - (1.0 - shape) * 0.15 * wave_velocity;
}

void fragment() {
	// r_s along travel axis from center
	float r_s = VERTEX.z;

	// Shape function: 1 inside bubble, 0 outside
	float shape = alcubierre_shape(r_s, bubble_radius, skin_depth);

	// York time for color blending
	float theta = york_time(r_s, bubble_radius, skin_depth);
	float theta_norm = clamp(theta * 0.5, -1.0, 1.0);

	// Grid pattern: concentric rings along Z + radial lines along X
	float grid_z = abs(fract(VERTEX.z / grid_cell_size - 0.5) - 0.5) / fwidth(VERTEX.z / grid_cell_size);
	float grid_x = abs(fract(VERTEX.x / grid_cell_size - 0.5) - 0.5) / fwidth(VERTEX.x / grid_cell_size);
	float grid_line = 1.0 - min(min(grid_z, grid_x), 1.0);
	float grid = smoothstep(0.0, grid_line_thickness * 0.1, grid_line);

	// Animated pulse traveling along the grid
	float pulse_wave = sin(r_s * 2.0 - TIME * time_scale * pulse_frequency * 3.0) * 0.5 + 0.5;
	pulse_wave *= shape; // Only visible inside/near bubble

	// Color: blend contraction (front, blue) and expansion (rear, magenta) based on York time
	vec3 base_color = grid_color.rgb;
	vec3 contracted = mix(base_color, contraction_color.rgb, clamp(-theta_norm, 0.0, 1.0));
	vec3 expanded = mix(contracted, expansion_color.rgb, clamp(theta_norm, 0.0, 1.0));

	// Add pulse wave glow
	vec3 final_color = expanded * (0.6 + pulse_wave * 0.4) * glow_intensity;

	// Alpha: grid lines + bubble shape falloff + materialize opacity
	float alpha = grid * opacity;
	// Fade out at plane edges
	float edge_fade = 1.0 - smoothstep(plane_size * 0.35, plane_size * 0.5, length(VERTEX.xz));
	alpha *= edge_fade;
	// Boost alpha near bubble walls where distortion is strongest
	float wall_boost = 1.0 - shape;
	alpha *= (0.3 + wall_boost * 0.7);

	ALBEDO = final_color;
	EMISSION = final_color * glow_intensity * 0.5;
	ALPHA = alpha;
}
