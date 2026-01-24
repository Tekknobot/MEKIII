shader_type canvas_item;

uniform float wobble_strength = 0.6;     // 0.2–1.2
uniform float wobble_speed = 1.3;        // 0.5–2.5
uniform float shimmer_strength = 0.18;   // 0.05–0.35
uniform float shimmer_speed = 1.8;       // 0.5–3.0
uniform float pixelate = 1.0;            // keep 1.0 for pixel art

void fragment() {
	// preserve inspector modulation
	vec4 modulate = COLOR;

	// pixel-snapped UV (keeps it crunchy)
	vec2 uv = UV;
	vec2 px = TEXTURE_PIXEL_SIZE * pixelate;
	uv = floor(uv / px) * px + px * 0.5;

	// cheap “cloudy” wobble using sine layers
	float t = TIME;
	float w =
		sin((uv.y * 18.0) + t * wobble_speed) +
		sin((uv.x * 14.0) - t * (wobble_speed * 0.8));
	w *= 0.5;

	uv.x += w * TEXTURE_PIXEL_SIZE.x * wobble_strength;
	uv.y += sin((uv.x * 16.0) + t * (wobble_speed * 0.6)) * TEXTURE_PIXEL_SIZE.y * (wobble_strength * 0.6);

	vec4 tex = texture(TEXTURE, uv);

	// shimmer only where there’s alpha (inside the cloud)
	float s = sin((UV.x + UV.y) * 22.0 + t * shimmer_speed) * 0.5 + 0.5;
	float shimmer = (s - 0.5) * 2.0 * shimmer_strength;

	vec4 out_col = tex;
	out_col.rgb = clamp(out_col.rgb + shimmer * tex.a, 0.0, 1.0);

	COLOR = out_col * modulate;
}
