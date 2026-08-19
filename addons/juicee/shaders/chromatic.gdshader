shader_type canvas_item;

uniform float intensity : hint_range(0.0, 20.0) = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	float r = texture(SCREEN_TEXTURE, uv + vec2(intensity * 0.001, 0.0)).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv - vec2(intensity * 0.001, 0.0)).b;
	COLOR = vec4(r, g, b, 1.0);
}
