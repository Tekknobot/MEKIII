shader_type canvas_item;

// radioactive palette (dark -> bright)
uniform vec3 g0 : source_color = vec3(0.02, 0.06, 0.03); // deep dark
uniform vec3 g1 : source_color = vec3(0.04, 0.25, 0.12); // dark green
uniform vec3 g2 : source_color = vec3(0.10, 0.85, 0.30); // neon green
uniform vec3 g3 : source_color = vec3(0.90, 1.00, 0.45); // hot highlight

uniform float intensity = 1.05;

// pixel animation controls
uniform float crawl_speed = 4.5;      // pixel-step drift
uniform float flicker_speed = 7.5;
uniform float hotspot_chance = 0.012; // random hot pixels
uniform float hotspot_boost = 0.85;   // how strongly hotspots push to g3

// hash for per-pixel randomness
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a <= 0.0) discard;

	// integer pixel coordinates in texture space
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);

	float t = TIME;

	// --- pixel-step "crawl": sample a neighbor that shifts over time ---
	// This creates that crawling radioactive shimmer but stays pixel-crisp.
	float step_amt = floor(t * crawl_speed);

	// alternate between sampling left/right and up/down in pixel steps
	vec2 dir = vec2(mod(step_amt, 2.0) == 0.0 ? 1.0 : -1.0, mod(step_amt, 3.0) == 0.0 ? 1.0 : -1.0);
	vec2 px2 = px + dir;

	// wrap to texture bounds
	float w = 1.0 / TEXTURE_PIXEL_SIZE.x;
	float h = 1.0 / TEXTURE_PIXEL_SIZE.y;
	px2.x = mod(px2.x + w, w);
	px2.y = mod(px2.y + h, h);

	// sample neighbor pixel
	vec2 uv2 = (px2 + vec2(0.5)) * TEXTURE_PIXEL_SIZE;
	vec4 ntex = texture(TEXTURE, uv2);

	// brightness from original pixel + neighbor (keeps original shading structure)
	float l0 = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float l1 = dot(ntex.rgb, vec3(0.299, 0.587, 0.114));

	// per-pixel flicker
	float r = hash(px);
	float flick = sin(t * flicker_speed + r * 6.2831) * 0.5 + 0.5;
	flick = 0.88 + 0.26 * flick;

	// heat/energy scalar
	float energy = clamp(l0 * 0.80 + l1 * 0.55, 0.0, 1.0) * flick;

	// quantize into 4 bands (Game Boy palette swap feel)
	float q;
	if (energy < 0.22) q = 0.0;
	else if (energy < 0.48) q = 1.0;
	else if (energy < 0.78) q = 2.0;
	else q = 3.0;

	vec3 col = g0;
	if (q < 0.5) col = g0;
	else if (q < 1.5) col = g1;
	else if (q < 2.5) col = g2;
	else col = g3;

	// hotspots: random “hot” pixels that pop, biased toward brighter areas
	float hot = step(1.0 - hotspot_chance, hash(px + vec2(floor(t * 12.0), 3.0)));
	hot *= smoothstep(0.45, 1.0, energy);
	col = mix(col, g3, hot * hotspot_boost);

	COLOR = vec4(col * intensity, tex.a);
}
