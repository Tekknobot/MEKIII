shader_type canvas_item;

// fire palette (dark -> bright)
uniform vec3 p0 : source_color = vec3(0.10, 0.02, 0.02); // deep ember
uniform vec3 p1 : source_color = vec3(0.45, 0.05, 0.02); // dark red
uniform vec3 p2 : source_color = vec3(1.00, 0.22, 0.02); // orange
uniform vec3 p3 : source_color = vec3(1.00, 0.85, 0.25); // yellow/white

uniform float intensity = 1.1;

// pixel animation controls
uniform float rise_speed = 6.0;      // higher = faster upward crawl
uniform float flicker_speed = 10.0;
uniform float ember_chance = 0.015;  // 0..1 (chance a pixel becomes an ember)
uniform float ember_boost = 0.75;    // how much brighter embers are

// --- small hash for per-pixel randomness ---
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a <= 0.0) discard;

	// --- identify pixel grid so effects step per pixel ---
	// TEXTURE_PIXEL_SIZE is 1/texture_size
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE); // integer pixel coords

	// --- sample a pixel "below" this one over time (rising heat) ---
	// This makes bright pixels crawl upward in pixel steps.
	float t = TIME;
	float y_offset = floor(t * rise_speed);
	vec2 px_below = px + vec2(0.0, y_offset);

	// wrap in texture height
	float h = 1.0 / TEXTURE_PIXEL_SIZE.y;
	px_below.y = mod(px_below.y, h);

	// convert back to UV centered in that pixel
	vec2 uv_below = (px_below + vec2(0.5)) * TEXTURE_PIXEL_SIZE;
	vec4 below = texture(TEXTURE, uv_below);

	// base brightness from the sprite’s own pixels (so it "affects individual pixel colors")
	float luma0 = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float luma1 = dot(below.rgb, vec3(0.299, 0.587, 0.114));

	// flicker per pixel
	float r = hash(px);
	float flicker = sin(t * flicker_speed + r * 6.2831) * 0.5 + 0.5;
	flicker = 0.85 + 0.30 * flicker;

	// combine: original pixel + rising contribution
	float heat = clamp(luma0 * 0.75 + luma1 * 0.55, 0.0, 1.0);
	heat *= flicker;

	// quantize heat into 4 palette bands (pixel-art style)
	// This is the key "per-pixel palette" look.
	float q;
	if (heat < 0.20) q = 0.0;
	else if (heat < 0.45) q = 1.0;
	else if (heat < 0.75) q = 2.0;
	else q = 3.0;

	vec3 col = p0;
	if (q < 0.5) col = p0;
	else if (q < 1.5) col = p1;
	else if (q < 2.5) col = p2;
	else col = p3;

	// ember pixels: random bright sparks that appear/disappear
	float ember = step(1.0 - ember_chance, hash(px + vec2(floor(t * 12.0), 0.0)));
	// bias embers toward “hotter” pixels so it feels natural
	ember *= smoothstep(0.45, 1.0, heat);

	col = mix(col, p3, ember * ember_boost);

	COLOR = vec4(col * intensity, tex.a);
}
