shader_type canvas_item;

uniform float metal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float shine_speed    : hint_range(0.0, 5.0) = 1.2;
uniform float shine_width    : hint_range(0.01, 0.5) = 0.12;
uniform float shine_angle    : hint_range(0.0, 6.28318) = 0.9;

uniform float rim_strength   : hint_range(0.0, 2.0) = 0.45;
uniform float dither_amount  : hint_range(0.0, 0.35) = 0.12;

uniform vec4 metal_tint : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform float pixel_grid = 32.0;

float hash12(vec2 p){
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Alpha mask (0 for transparent, 1 for opaque)
	float mask = step(0.01, tex.a);

	// Lock to pixel grid
	vec2 puv = floor(UV * pixel_grid) / pixel_grid;

	// Base color with subtle cool metal tint
	vec3 base = mix(tex.rgb, tex.rgb * metal_tint.rgb, 0.35 * metal_strength);

	// Moving diagonal highlight
	vec2 dir = vec2(cos(shine_angle), sin(shine_angle));
	float proj = dot(puv, dir) + TIME * shine_speed;
	float sweep = fract(proj);

	float band = 1.0 - smoothstep(
		0.5 - shine_width,
		0.5,
		abs(sweep - 0.5) * 2.0
	);

	// Pixel rim light
	float rim = 0.0;
	rim += smoothstep(0.0, 0.12, puv.x);
	rim += smoothstep(0.0, 0.12, puv.y);
	rim += smoothstep(0.0, 0.12, 1.0 - puv.x);
	rim += smoothstep(0.0, 0.12, 1.0 - puv.y);
	rim = clamp(rim * 0.5, 0.0, 1.0);

	// Grainy metallic dither
	float n = hash12(puv * pixel_grid);
	float dither = (n - 0.5) * dither_amount;

	float highlight = (band * 0.9 + rim * rim_strength) * metal_strength;

	vec3 color_out = base + vec3(highlight) + vec3(dither);

	// Contrast pop
	color_out = mix(color_out, pow(color_out, vec3(0.92)), 0.5 * metal_strength);

	// Preserve transparency WITHOUT return
	COLOR = vec4(
		mix(tex.rgb, color_out, mask),
		tex.a
	);
}
