shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform float bounding_radius = 500.0;
uniform float schwarzschild_radius = 30.0;
uniform float disk_inner_radius = 38.0;
uniform float disk_outer_radius = 160.0;
uniform float disk_thickness = 3.0;
uniform float disk_tilt_x = 0.35;
uniform float disk_tilt_z = -0.13;
uniform float brightness = 2.5;
uniform int ray_steps = 160;
uniform float ray_bend_strength = 1.0;
uniform float doppler_boost = 2.5;
uniform float gravitational_redshift = 0.8;
uniform float disk_rotation_speed = 2.0;
uniform float temperature_inner = 15000.0;
uniform float temperature_outer = 3000.0;
uniform float noise_scale = 6.0;
uniform float noise_speed = 0.5;
uniform float photon_sphere_radius = 45.0;
uniform float step_size = 5.0;
uniform float doppler_angle = 0.0;
uniform float bloom_threshold = 2.0;
uniform sampler2D background_stars;
uniform float background_enabled = 0.0;
uniform int debug_mode = 0;

vec3 blackbody(float temp_k) {
	float t = clamp(temp_k / 100.0, 0.0, 400.0);
	vec3 color;
	if (t <= 66.0) {
		color.r = 1.0;
		color.g = clamp(0.39008157876 * log(t) - 0.63184144378, 0.0, 1.0);
		color.b = (t <= 19.0) ? 0.0 : clamp(0.54320678911 * log(t - 10.0) - 1.19625408934, 0.0, 1.0);
	} else {
		color.r = clamp(1.29293618606 * pow(t - 60.0, -0.1332047592), 0.0, 1.0);
		color.g = clamp(1.12989086089 * pow(t - 60.0, -0.0755148492), 0.0, 1.0);
		color.b = 1.0;
	}
	return color;
}

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise2d(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float disk_fbm(float radius, float angle, float time) {
	vec2 p = vec2(cos(angle), sin(angle)) * radius * noise_scale;
	float value = 0.0; float amp = 0.5; float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		value += amp * noise2d(p * freq + vec2(time * 0.3 * float(i + 1), 0.0));
		amp *= 0.5; freq *= 2.1;
	}
	return value;
}

vec3 rotate_axis(vec3 v, vec3 axis, float angle) {
	float c = cos(angle); float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

vec3 get_disk_normal() {
	vec3 n = vec3(0.0, 1.0, 0.0);
	n = rotate_axis(n, vec3(1.0, 0.0, 0.0), disk_tilt_x);
	n = rotate_axis(n, vec3(0.0, 0.0, 1.0), disk_tilt_z);
	return normalize(n);
}

vec3 disk_emission(vec3 pos, vec3 disk_n, vec3 view_dir, float r_in, float r_out, float half_thick) {
	float height = dot(pos, disk_n);
	vec3 planar = pos - disk_n * height;
	float r = length(planar);
	if (r < r_in || r > r_out) return vec3(0.0);

	float r_norm = (r - r_in) / (r_out - r_in);
	float local_thick = half_thick * mix(1.0, 2.2, r_norm);
	float vertical = exp(-(height * height) / max(local_thick * local_thick, 1e-5));

	float omega = disk_rotation_speed / max(pow(r, 1.5), 0.2);
	float angle = atan(planar.z, planar.x) + TIME * omega;

	float warp = disk_fbm(r_norm * 3.0 + 1.7, angle * 2.0, TIME * noise_speed);
	float turb = disk_fbm(r_norm * 4.0, angle * 3.0 + warp * 2.5, TIME * noise_speed);
	float density = pow(turb, 1.5) * 1.8 + 0.15;

	float spiral = sin(angle * 2.0 - r_norm * 14.0) * 0.5 + 0.5;
	density *= mix(0.55, 1.25, spiral);

	float radial = pow(1.0 - r_norm, 1.8) * smoothstep(0.0, 0.06, r_norm) + 0.02;
	radial += exp(-r_norm * 14.0) * 2.5;

	float temp = mix(temperature_inner, temperature_outer, pow(r_norm, 0.5));
	vec3 color = blackbody(temp);

	float rshift = gravitational_redshift * exp(-r_norm * 6.0) * 0.5;
	color = mix(color, color * vec3(1.0, 0.55, 0.28), clamp(rshift, 0.0, 1.0));

	vec3 radial_dir = normalize(planar);
	vec3 vel_dir = normalize(cross(disk_n, radial_dir));
	float orbital_v = 0.7 / sqrt(max(r, 0.5));
	float v_los = dot(vel_dir, -view_dir) * orbital_v;
	float g = clamp(1.0 + doppler_boost * v_los * 0.55, 0.25, 3.0);
	float beam = g * g * g;
	color = mix(color, color * vec3(0.75, 0.85, 1.35), clamp(v_los * 1.5, 0.0, 0.6));
	color = mix(color, color * vec3(1.3, 0.75, 0.5), clamp(-v_los * 1.5, 0.0, 0.6));

	return color * density * radial * vertical * beam;
}

void fragment() {
	// With cull_disabled, both front and back faces render. Since we use
	// blend_add, running the raymarch on both faces would double the output.
	// Only execute on back faces (far side from camera) — this gives exactly
	// one render per pixel whether the camera is inside or outside the sphere.
	if (!FRONT_FACING) {
		vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 frag_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 ray_dir = normalize(frag_pos - cam_pos);

		if (debug_mode == 1) {
			ALBEDO = vec3(1.0, 0.0, 0.0);
			ALPHA = 1.0;
		} else if (debug_mode == 2) {
			ALBEDO = vec3(UV, 0.0);
			ALPHA = 1.0;
		} else {
			float rs = max(schwarzschild_radius, 1e-3);
			float bound_r = bounding_radius;

			// Ray-sphere intersection
			vec3 oc = cam_pos;
			float b_coef = 2.0 * dot(oc, ray_dir);
			float c_coef = dot(oc, oc) - bound_r * bound_r;
			float disc = b_coef * b_coef - 4.0 * c_coef;

			vec3 entry_w = cam_pos;
			if (disc >= 0.0) {
				float t_near = (-b_coef - sqrt(disc)) * 0.5;
				if (t_near > 0.0) {
					entry_w = cam_pos + ray_dir * t_near;
				}
			}

			// Normalize to Rs = 1
			vec3 p = entry_w / rs;
			vec3 dir = ray_dir;
			float r_in = disk_inner_radius / rs;
			float r_out = disk_outer_radius / rs;
			float half_thick = disk_thickness / rs;

			vec3 disk_n = get_disk_normal();
			vec3 Lv = cross(p, dir);
			float h2 = dot(Lv, Lv) * ray_bend_strength;

			vec3 emission = vec3(0.0);
			bool captured = false;
			float min_r = 999.0;
			float escape_r = r_out * 1.3 + 2.0;
			float escape_r2 = escape_r * escape_r;

			for (int i = 0; i < 300; i++) {
				if (i >= ray_steps) break;
				float r2 = dot(p, p);
				float r = sqrt(r2);
				if (r < min_r) min_r = r;
				if (r < 1.0) { captured = true; break; }
				if (r2 > escape_r2 && dot(p, dir) > 0.0) break;

				float dstep = clamp(r * 0.09, 0.03, 0.45);
				float h_dist = abs(dot(p, disk_n));
				if (r < r_out * 1.1 && h_dist < half_thick * 6.0) {
					dstep = min(dstep, max(half_thick * 0.7, 0.025));
				}

				vec3 accel = -1.5 * h2 * p / max(r2 * r2 * r, 1e-4);
				dir = normalize(dir + accel * dstep);
				p += dir * dstep;

				if (r < r_out * 1.15) {
					emission += disk_emission(p, disk_n, dir, r_in, r_out, half_thick) * dstep;
				}
			}

			float b = sqrt(max(h2, 0.0) / max(ray_bend_strength, 1e-4));
			float ring = exp(-pow((b - 2.598) * 2.2, 2.0));
			if (!captured) {
				emission += blackbody(temperature_inner) * ring * brightness * 0.6;
			}

			if (background_enabled > 0.5 && !captured) {
				vec2 bg_uv = vec2(atan(dir.z, dir.x), asin(clamp(dir.y, -1.0, 1.0))) / vec2(6.283, 3.141) + 0.5;
				emission += texture(background_stars, bg_uv).rgb * 0.5;
			}

			if (debug_mode == 3) {
				float cap = 0.0;
				if (captured) cap = 1.0;
				vec3 dbg = vec3(clamp(min_r / 10.0, 0.0, 1.0), cap, clamp(b / 5.0, 0.0, 1.0));
				ALBEDO = dbg;
				ALPHA = 1.0;
			} else {
				vec3 hdr = emission * brightness;
				ALBEDO = hdr;
				ALPHA = clamp(max(max(hdr.r, hdr.g), hdr.b), 0.0, 1.0);
			}
		}
	} else {
		// Front face: contribute nothing (back face handles the raymarch)
		ALBEDO = vec3(0.0);
		ALPHA = 0.0;
	}
}
