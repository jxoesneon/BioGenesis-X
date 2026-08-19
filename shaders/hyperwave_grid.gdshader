// ============================================================================
// HYPERWAVE SPOOL GRID SHADER - BioGenesis-X
// Pumilio Studios — Wave Engine Charge-Up / Drop-Out Visual Effect
// ============================================================================
// During the Wave Engine's charge-up phase (before the Alcubierre bubble forms)
// and drop-out phase (as the bubble collapses), a spool grid materializes in
// front of the ship. This grid depicts the bio-plasma frequencies resonating
// through the Void-Fauna's vascular conduit network as the caudal siphon system
// spools up to deform spacetime.
//
// CHARGE PHASE (charge_ratio 0 → 1):
//   The grid appears flat, then the center deforms forward (away from ship)
//   as a funnel shape. This represents spacetime beginning to contract ahead
//   of the ship — the Alcubierre metric's "front contraction" building up
//   before the full warp bubble forms. The funnel grows as the bio-plasma
//   resonance intensifies toward the threshold where spacetime tears open.
//
// DROP-OUT PHASE (charge_ratio 1 → 0):
//   The funnel flattens back out as the warp bubble collapses. The central
//   hole (which opened during transit) closes as spacetime returns to flat.
//   This is the inverse of the charge phase — the Void-Fauna's siphon system
//   is releasing its grip on spacetime, returning the ship to normal space.
//
// The central hole (pow(charge_ratio, 5.0) * 0.15) opens rapidly at the END
// of the charge phase because the Alcubierre bubble formation is non-linear —
// spacetime resists deformation until a threshold, then yields suddenly.
// The pow(..., 5.0) exponent models this threshold behavior.
//
// Color: grid_color (cyan-white #CCF2FF) matches the Wave Engine's bio-cyan
// warp field from wave_engine.gdshader and the "healthy neural sync" color
// from the 12-color bioluminescent coding system (docs/DESIGN_DIRECTION.md).
// The grid glows with high intensity (ALBEDO * 6.0) to trigger bloom — the
// spool grid should feel like radiant bio-energy, not a flat texture.
//
// Lore reference: LORE.md "The Wave Engine" — the Void-Fauna's caudal siphon
// system is "resonantly tuned to deform spacetime itself when driven at
// specific bio-plasma frequencies."
// ============================================================================
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

// 0 = flat grid (rest), 1 = fully charged (funnel formed, hole open)
uniform float charge_ratio : hint_range(0.0, 1.0) = 0.0;
// Bio-cyan warp field color — matches wave_engine.gdshader grid_color
uniform vec3 grid_color : source_color = vec3(0.8, 0.95, 1.0);
uniform float grid_thickness : hint_range(0.0, 1.0) = 0.02;
// Grid cell density — 30 cells across the 800m plane (~27m per cell)
uniform float grid_scale = 30.0;

void vertex() {
    // Distance from center in local space (XZ plane)
    float dist = length(VERTEX.xz);
    
    // Deform the center forward (away from ship) as charge_ratio increases.
    // This is the Alcubierre front contraction building up — spacetime ahead
    // of the ship is being pulled inward toward the bubble center. The
    // smoothstep(80.0, 0.0, dist) creates a bell-like funnel curve: maximum
    // deformation at the center, fading to flat at the grid edges.
    // The 200.0 multiplier scales the deformation to be visually dramatic
    // across the 800m grid plane.
    float deform = smoothstep(80.0, 0.0, dist) * charge_ratio * 200.0;
    VERTEX.y -= deform;
}

void fragment() {
    // Use UV mapped to the grid scale
    vec2 grid_uv = UV * grid_scale;
    
    // Procedural grid lines
    vec2 grid = fract(grid_uv);
    float line_x = smoothstep(grid_thickness, 0.0, grid.x) + smoothstep(1.0 - grid_thickness, 1.0, grid.x);
    float line_y = smoothstep(grid_thickness, 0.0, grid.y) + smoothstep(1.0 - grid_thickness, 1.0, grid.y);
    float grid_alpha = clamp(line_x + line_y, 0.0, 1.0);
    
    // Distance from center of the plane (0.0 to 0.5)
    float dist = length(UV - 0.5);
    
    // Central hole that opens rapidly at the END of charge — models the
    // non-linear threshold behavior of Alcubierre bubble formation. Spacetime
    // resists deformation until the bio-plasma resonance crosses a threshold,
    // then yields suddenly. The pow(..., 5.0) exponent concentrates the hole
    // opening in the final ~30% of the charge phase.
    float hole_radius = pow(charge_ratio, 5.0) * 0.15;
    float hole_mask = smoothstep(hole_radius, hole_radius + 0.02, dist);
    
    // Soft fade at the outer edges
    float outer_fade = smoothstep(0.5, 0.1, dist);
    
    // Fade in when charging starts
    float appear = smoothstep(0.0, 0.1, charge_ratio);
    
    ALBEDO = grid_color * 6.0; // High intensity for bloom
    ALPHA = grid_alpha * hole_mask * outer_fade * appear * 0.15;
}
