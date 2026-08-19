shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform vec3 energy_color_1 : source_color = vec3(0.1, 0.5, 1.0);
uniform vec3 energy_color_2 : source_color = vec3(0.0, 0.9, 1.0);
uniform vec3 dark_matter_color : source_color = vec3(0.01, 0.0, 0.1);

uniform float scroll_speed : hint_range(0.1, 20.0) = 8.0;
uniform float swirl_speed : hint_range(0.0, 5.0) = 1.5;
uniform float intensity_multiplier : hint_range(0.1, 10.0) = 3.0;

// Fast 2D Hash function
vec2 hash( vec2 p ) {
	p = vec2( dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)) );
	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

// Simplex noise
float noise( in vec2 p ) {
    const float K1 = 0.366025404; // (sqrt(3)-1)/2;
    const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2  i = floor( p + (p.x+p.y)*K1 );
    vec2  a = p - i + (i.x+i.y)*K2;
    float m = step(a.y,a.x); 
    vec2  o = vec2(m,1.0-m);
    vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0*K2;
    vec3  h = max( 0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	vec3  n = h*h*h*h*vec3( dot(a,hash(i+0.0)), dot(b,hash(i+o)), dot(c,hash(i+1.0)));
    return dot( n, vec3(70.0) );
}

// Fractal Brownian Motion
float fbm(vec2 p) {
    float f = 0.0;
    f += 0.5000 * noise(p); p = p * 2.02;
    f += 0.2500 * noise(p); p = p * 2.03;
    f += 0.1250 * noise(p); p = p * 2.01;
    f += 0.0625 * noise(p);
    return f / 0.9375;
}

void vertex() {
    // Add a slight wobble to the tunnel walls
    float wobble = sin(TIME * 5.0 + VERTEX.z * 0.1) * 0.5;
    float wobble2 = cos(TIME * 3.0 + VERTEX.y * 0.1) * 0.5;
    VERTEX.x += wobble;
    VERTEX.y += wobble2;
}

void fragment() {
    vec2 uv = UV;
    
    // Create the fast forward-moving effect
    float z_scroll = TIME * scroll_speed;
    float swirl = TIME * swirl_speed;
    
    vec2 noise_uv = vec2(uv.x * 3.0 + swirl, uv.y * 10.0 - z_scroll);
    
    // Generate layered noise
    float n1 = fbm(noise_uv);
    float n2 = fbm(noise_uv * 1.5 + vec2(TIME * 0.5));
    
    // Combine noise for energy bands
    float energy = smoothstep(0.1, 0.8, n1 * n2 + 0.2);
    
    // Add lightning / high-energy streaks
    float streaks = pow(fbm(vec2(uv.x * 20.0, uv.y * 2.0 - z_scroll * 2.0)), 3.0) * 2.0;
    
    // Calculate energy color
    vec3 energy_fx = mix(dark_matter_color, energy_color_1, energy);
    energy_fx = mix(energy_fx, energy_color_2, streaks);
    energy_fx *= intensity_multiplier;
    
    // Fade the ends of the cylinder so it doesn't have hard cuts
    float edge_fade = smoothstep(0.0, 0.2, uv.y) * smoothstep(1.0, 0.8, uv.y);
    
    // --- SPACE WARPING (Refraction) ---
    // Distort the screen UV based on the flowing noise
    vec2 screen_uv = SCREEN_UV;
    float warp_strength = 0.15 * edge_fade; // High distortion
    screen_uv.x += (n1 - 0.5) * warp_strength;
    screen_uv.y += (n2 - 0.5) * warp_strength;
    
    // Chromatic aberration on the background warp
    float ca = 0.02 * edge_fade;
    float bg_r = texture(screen_texture, screen_uv + vec2(ca, 0.0)).r;
    float bg_g = texture(screen_texture, screen_uv).g;
    float bg_b = texture(screen_texture, screen_uv - vec2(ca, 0.0)).b;
    
    vec3 warped_background = vec3(bg_r, bg_g, bg_b);
    
    // Blend the warped space background with the energy tunnel
    // Dark matter obscures the background, while energy adds to it
    vec3 final_color = mix(warped_background, warped_background * dark_matter_color * 5.0, energy * 0.5);
    final_color += energy_fx * (energy + streaks);
    
    ALBEDO = final_color;
    
    // Fade out the entire tunnel at the edges to reveal normal space seamlessly
    ALPHA = edge_fade * clamp(energy + streaks + 0.1, 0.0, 1.0);
}
