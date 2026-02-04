shader_type canvas_item;

/* ---------- TUNING ---------- */
uniform float intensity : hint_range(0.0, 2.0) = 1.0;

uniform float noise_amount : hint_range(0.0, 1.0) = 0.08;
uniform float scanline_amount : hint_range(0.0, 1.0) = 0.12;

uniform float glow_amount : hint_range(0.0, 2.0) = 0.25;
uniform float glow_speed : hint_range(0.0, 4.0) = 1.2;

uniform float vignette_amount : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_density : hint_range(64.0, 2048.0) = 480.0;

/* ---------- NOISE ---------- */
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	vec4 base = texture(TEXTURE, uv);
	vec3 col = base.rgb;

	float t = TIME;

	/* ---- SCANLINES ---- */
	float sl = sin(uv.y * scanline_density + t * 60.0) * 0.5 + 0.5;
	col *= mix(1.0, 0.92, sl * scanline_amount * intensity);

	/* ---- GRAIN ---- */
	float n = hash(uv * vec2(900.0, 520.0) + vec2(t * 12.0, t * 7.0));
	col += (n - 0.5) * noise_amount * 0.06 * intensity;

	/* ---- BREATHING GLOW (GREEN LIGHTS) ---- */
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float mask = smoothstep(0.25, 0.7, luma);
	float pulse = sin(t * glow_speed) * 0.5 + 0.5;
	col += vec3(0.02, 0.08, 0.02) * glow_amount * mask * pulse * intensity;

	/* ---- VIGNETTE ---- */
	vec2 p = uv * 2.0 - 1.0;
	float v = 1.0 - vignette_amount * smoothstep(0.4, 1.2, dot(p, p));
	col *= v;

	COLOR = vec4(col, base.a);
}
