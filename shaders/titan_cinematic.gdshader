shader_type canvas_item;

uniform float glitch_amount : hint_range(0.0, 1.0) = 0.55;
uniform float glitch_speed  : hint_range(0.0, 10.0) = 4.0;

uniform float slice_count   : hint_range(4.0, 96.0) = 32.0;
uniform float max_shift_px  : hint_range(0.0, 24.0) = 6.0;

uniform float rgb_split_px  : hint_range(0.0, 6.0) = 1.5;
uniform float noise_amount  : hint_range(0.0, 1.0) = 0.20;

uniform float blockiness_px : hint_range(1.0, 16.0) = 2.0; // 1 = none, 2/3/4 = chunkier

uniform vec4 glow_tint : source_color = vec4(0.55, 0.85, 1.0, 1.0);

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	// ✅ Preserve modulation/self_modulate so your code can fade it
	vec4 mod = COLOR;

	// Sample base sprite with modulation
	vec4 base = texture(TEXTURE, UV) * mod;
	if (base.a <= 0.0) discard;

	// Screen pixel coords (valid in CanvasItem)
	vec2 sp = SCREEN_UV / SCREEN_PIXEL_SIZE;

	// Pixel-art chunking (optional)
	if (blockiness_px > 1.0) {
		sp = floor(sp / blockiness_px) * blockiness_px;
	}

	float t = TIME * glitch_speed;

	// Viewport height in pixels (no VIEWPORT_RECT_SIZE needed)
	float viewport_h_px = 1.0 / SCREEN_PIXEL_SIZE.y;
	float slice_h_px = max(1.0, viewport_h_px / max(1.0, slice_count));
	float slice_id = floor(sp.y / slice_h_px);

	// Stable randomness per slice over time
	float r = hash11(slice_id + floor(t * 6.0));
	float active = step(0.55, r); // some slices glitch at a time

	// Horizontal slice shift (in pixels)
	float shift_dir = (hash11(slice_id * 7.13 + 2.0) * 2.0 - 1.0);
	float shift_px = active * shift_dir * max_shift_px * glitch_amount;

	// Apply the shift in TEXTURE UV space
	vec2 tex_uv = UV + vec2(shift_px, 0.0) * TEXTURE_PIXEL_SIZE;

	// RGB split (still sprite-space)
	float split_px = rgb_split_px * glitch_amount * active;
	vec2 split = vec2(split_px, 0.0) * TEXTURE_PIXEL_SIZE;

	float rr = texture(TEXTURE, tex_uv + split).r;
	float gg = texture(TEXTURE, tex_uv).g;
	float bb = texture(TEXTURE, tex_uv - split).b;

	float aa = texture(TEXTURE, tex_uv).a * mod.a;

	vec3 rgb = vec3(rr, gg, bb) * mod.rgb;

	// Noise sparkles (screen-pixel stable)
	float n = hash12(floor(sp) + floor(t * 20.0));
	float spark = step(1.0 - (noise_amount * glitch_amount * 0.35), n) * active;
	rgb = mix(rgb, glow_tint.rgb, spark * 0.6);

	// Occasional tear line
	float tear_r = hash11(floor(t * 8.0) + 99.0);
	float tear_y = floor(tear_r * viewport_h_px);
	float tear = step(abs(sp.y - tear_y), 1.0) * glitch_amount;
	rgb += glow_tint.rgb * tear * 0.35;

	// ✅ Final: keep modulated alpha so your fade code still works
	COLOR = vec4(rgb, aa);
}
