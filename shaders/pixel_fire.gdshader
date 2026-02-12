shader_type canvas_item;

uniform sampler2D sprite_tex : source_color;

uniform float intensity = 0.9;
uniform float flame_height = 0.75;
uniform float speed = 10.0;
uniform float block_px = 2.0;

uniform vec4 col_hot   : source_color = vec4(1.00, 0.95, 0.70, 1.0);
uniform vec4 col_mid   : source_color = vec4(1.00, 0.55, 0.15, 1.0);
uniform vec4 col_low   : source_color = vec4(1.00, 0.20, 0.05, 1.0);
uniform vec4 col_smoke : source_color = vec4(0.10, 0.04, 0.02, 0.0);

float hash21(vec2 p){
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

void fragment(){
	vec4 base = texture(sprite_tex, UV) * COLOR;

	// default output = original sprite
	vec4 out_col = base;

	// Only apply fire where the sprite exists
	if (base.a >= 0.01) {
		vec2 tex_size = vec2(textureSize(sprite_tex, 0));
		vec2 texel = 1.0 / max(tex_size, vec2(1.0));

		// snap UV to pixel blocks
		vec2 block = texel * max(1.0, block_px);
		vec2 quv = (floor(UV / block) + 0.5) * block;

		float step_t = floor(TIME * speed);
		float y_scroll = step_t * block.y * 1.5;

		float y = 1.0 - quv.y;
		float height_mask = smoothstep(0.0, flame_height, y);

		vec2 npos = vec2(quv.x * 24.0, quv.y * 24.0 - y_scroll);
		float n = noise(npos);

		float base_boost = smoothstep(0.0, 0.65, y);
		n *= base_boost;

		float thresh = mix(0.55, 0.25, y);
		float flame_mask = smoothstep(thresh, thresh + 0.18, n);
		flame_mask *= intensity * height_mask;

		float heat = clamp(base_boost * 1.2, 0.0, 1.0);
		vec3 fire_col = mix(col_low.rgb, col_mid.rgb, heat);
		fire_col = mix(fire_col, col_hot.rgb, heat * 0.6);
		fire_col = mix(col_smoke.rgb, fire_col, clamp(flame_mask * 1.4, 0.0, 1.0));

		vec3 out_rgb = mix(base.rgb, max(base.rgb, fire_col), flame_mask);
		out_col = vec4(out_rgb, base.a);
	}

	COLOR = out_col;
}
