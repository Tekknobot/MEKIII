shader_type canvas_item;

uniform float stim_strength : hint_range(0.0, 1.0) = 0.0; // tween this 0->1
uniform float time_scale : hint_range(0.0, 5.0) = 1.0;
uniform float glow : hint_range(0.0, 2.0) = 0.6;
uniform float jitter_px : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a;

	// Keep transparency clean
	if (a < 0.01) {
		discard;
	}

	float t = TIME * time_scale;

	// --- Pixel jitter in UV space ---
	// jitter in pixels -> UV
	vec2 px = TEXTURE_PIXEL_SIZE * jitter_px;

	// pseudo-random jitter based on UV + time
	float jx = sin((UV.y * 180.0) + t * 18.0) * 0.5 + sin(t * 7.0) * 0.5;
	float jy = cos((UV.x * 160.0) + t * 15.0) * 0.5;

	vec2 jitter_uv = vec2(jx, jy) * px * stim_strength;

	vec4 tex_j = texture(TEXTURE, UV + jitter_uv);

	// --- Scanline / “charge” shimmer ---
	float scan = sin((UV.y / TEXTURE_PIXEL_SIZE.y) * 0.35 + t * 30.0) * 0.5 + 0.5;
	float charge = pow(scan, 3.0) * stim_strength;

	// --- Simple outline-ish glow (neighbor alpha) ---
	vec2 step_uv = TEXTURE_PIXEL_SIZE;
	float n =
		texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(-step_uv.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a +
		texture(TEXTURE, UV + vec2(0.0, -step_uv.y)).a;

	// edge factor: strong at edges, weak in solid interior
	float edge = clamp(n * 0.25 - a, 0.0, 1.0) * stim_strength;

	// Neon tint (yellow-green “stim” vibe)
	vec3 neon = vec3(0.2, 1.0, 0.55);

	// Base color respects modulate/tint via COLOR (vertex color)
	vec4 base = tex_j * COLOR;

	// Boost brightness + add neon edge glow
	base.rgb += neon * (edge * glow);
	base.rgb += neon * (charge * 0.35);

	// Optional tiny “overbright” pop
	float pop = stim_strength * 0.15;
	base.rgb *= (1.0 + pop);

	COLOR = vec4(base.rgb, base.a);
}
