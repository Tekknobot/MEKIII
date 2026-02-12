shader_type canvas_item;

uniform sampler2D sprite_tex : source_color;

uniform vec4 fire_color_hot   : source_color = vec4(1.0, 0.55, 0.10, 1.0);
uniform vec4 fire_color_mid   : source_color = vec4(1.0, 0.20, 0.05, 1.0);
uniform vec4 fire_color_smoke : source_color = vec4(0.12, 0.06, 0.02, 1.0);

uniform float fire_strength = 0.8;
uniform float flame_speed   = 1.5;
uniform float flame_scale   = 20.0;
uniform float flame_height  = 0.75; // 0..1, higher = flames reach higher

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec4 base = texture(sprite_tex, UV) * COLOR;

	// Always output something (no returns allowed)
	if (base.a < 0.01) {
		COLOR = base; // preserve transparent pixels
	} else {
		float y = 1.0 - UV.y;
		float t = TIME * flame_speed;

		// Upward-moving noise field
		float flame = vnoise(vec2(UV.x * flame_scale, UV.y * flame_scale - t * 3.0));

		// Stronger near bottom, fades with height
		float height_mask = smoothstep(0.0, flame_height, y);
		flame *= height_mask;

		// Chunkier “pixel fire” thresholding
		float mask = smoothstep(0.50, 0.65, flame);
		mask *= fire_strength * base.a;

		float heat = clamp(height_mask * 1.15, 0.0, 1.0);
		vec3 fire_col = mix(fire_color_mid.rgb, fire_color_hot.rgb, heat);
		fire_col = mix(fire_color_smoke.rgb, fire_col, mask);

		vec3 final_col = mix(base.rgb, max(base.rgb, fire_col), mask);

		COLOR = vec4(final_col, base.a);
	}
}
