shader_type canvas_item;

uniform sampler2D sprite_tex : source_color;

uniform float frost_amount = 0.75;
uniform float rim_strength = 0.9;
uniform float shimmer_speed = 0.8;
uniform float sparkle_strength = 0.45;
uniform float crack_strength = 0.35;
uniform float block_px = 2.0;

uniform vec4 ice_tint  : source_color = vec4(0.55, 0.85, 1.00, 1.0);
uniform vec4 deep_ice  : source_color = vec4(0.20, 0.55, 0.90, 1.0);
uniform vec4 highlight : source_color = vec4(0.95, 0.98, 1.00, 1.0);

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

float edge_mask(vec2 uv, vec2 texel){
	float a  = texture(sprite_tex, uv).a;
	float al = texture(sprite_tex, uv + vec2(-texel.x, 0.0)).a;
	float ar = texture(sprite_tex, uv + vec2( texel.x, 0.0)).a;
	float au = texture(sprite_tex, uv + vec2(0.0, -texel.y)).a;
	float ad = texture(sprite_tex, uv + vec2(0.0,  texel.y)).a;

	float e = 0.0;
	e += step(al, 0.01);
	e += step(ar, 0.01);
	e += step(au, 0.01);
	e += step(ad, 0.01);

	return clamp(e, 0.0, 1.0) * step(0.01, a);
}

void fragment(){
	vec4 base = texture(sprite_tex, UV) * COLOR;
	vec4 out_col = base;

	if (base.a >= 0.01) {
		vec2 tex_size = vec2(textureSize(sprite_tex, 0));
		vec2 texel = 1.0 / max(tex_size, vec2(1.0));

		vec2 block = texel * max(1.0, block_px);
		vec2 quv = (floor(UV / block) + 0.5) * block;

		float rim = edge_mask(quv, texel * max(1.0, block_px)) * rim_strength;

		float n1 = noise(quv * 42.0);
		float n2 = noise(quv * 84.0 + 7.13);
		float cracks = smoothstep(0.78, 0.90, n1) * (0.5 + 0.5 * n2);
		cracks *= crack_strength;

		float t = TIME * shimmer_speed;
		float g = noise(quv * 36.0 + vec2(t * 0.7, -t * 0.9));
		float spark = smoothstep(0.93, 0.985, g) * sparkle_strength;

		float lum = (base.r + base.g + base.b) / 3.0;
		float depth = 1.0 - lum;

		vec3 ice_col = mix(ice_tint.rgb, deep_ice.rgb, clamp(depth, 0.0, 1.0));
		ice_col = mix(ice_col, highlight.rgb, clamp(rim + spark, 0.0, 1.0));
		ice_col = mix(ice_col, highlight.rgb, cracks * 0.7);

		float overlay = clamp(frost_amount + rim * 0.6 + cracks * 0.35 + spark * 0.8, 0.0, 1.0);
		vec3 rgb = mix(base.rgb, (base.rgb * 0.65 + ice_col * 0.75), overlay);
		rgb = max(rgb, highlight.rgb * (0.15 * rim + 0.25 * spark));

		out_col = vec4(rgb, base.a);
	}

	COLOR = out_col;
}
