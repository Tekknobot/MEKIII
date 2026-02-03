shader_type canvas_item;

uniform float intensity : hint_range(0.0, 3.0) = 1.0;

uniform float scanline_strength : hint_range(0.0, 2.0) = 0.55;
uniform float scanline_density  : hint_range(50.0, 600.0) = 240.0;

uniform float shimmer_strength : hint_range(0.0, 2.0) = 0.35;
uniform float shimmer_speed    : hint_range(0.0, 10.0) = 2.0;

uniform float glitch_strength  : hint_range(0.0, 2.0) = 0.35;
uniform float glitch_rate      : hint_range(0.1, 20.0) = 3.5;

uniform float rgb_split        : hint_range(0.0, 6.0) = 1.25;

uniform float edge_glow        : hint_range(0.0, 4.0) = 1.15;
uniform vec4  glow_color : source_color = vec4(0.20, 1.00, 0.45, 1.0);

uniform float vignette         : hint_range(0.0, 1.0) = 0.20;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float band_noise(float y, float t) {
	return hash21(vec2(floor(y * 180.0), floor(t * 10.0)));
}

void fragment() {
	vec2 uv = UV;
	vec4 base = texture(TEXTURE, uv);

	float t = TIME;

	// If alpha is basically 0, keep it transparent and avoid heavy effects
	float alive = step(0.001, base.a); // 0 when transparent, 1 when visible

	// ---------------------------
	// Scanlines
	// ---------------------------
	float scan = sin((uv.y * scanline_density + t * 18.0) * 6.28318);
	float scan_amt = (0.5 + 0.5 * scan) * scanline_strength * intensity;

	// ---------------------------
	// Shimmer
	// ---------------------------
	float shimmer = sin((uv.y * 28.0 + t * shimmer_speed) * 6.28318)
	              + sin((uv.y * 57.0 - t * (shimmer_speed * 0.7)) * 6.28318);
	shimmer *= 0.5;

	float shx = shimmer * 0.0025 * shimmer_strength * intensity;

	// ---------------------------
	// Glitch strips
	// ---------------------------
	float g = band_noise(uv.y, t * glitch_rate);
	float glitch_on = step(0.78, g) * glitch_strength * intensity;
	float strip = step(0.65, band_noise(uv.y * 1.8, t * glitch_rate * 0.7));
	float gx = (hash21(vec2(g, t)) - 0.5) * 0.018 * glitch_on * strip;

	// Combine UV distortion
	vec2 duv = uv + vec2((shx + gx) * alive, 0.0); // no wobble on transparent pixels

	// ---------------------------
	// RGB split
	// ---------------------------
	float split = 0.0008 * rgb_split * intensity * alive;
	vec4 cR = texture(TEXTURE, duv + vec2(split, 0.0));
	vec4 cG = texture(TEXTURE, duv);
	vec4 cB = texture(TEXTURE, duv - vec2(split, 0.0));

	vec4 col = vec4(cR.r, cG.g, cB.b, base.a);

	// ---------------------------
	// Edge glow (alpha-based)
	// ---------------------------
	vec2 px = TEXTURE_PIXEL_SIZE * 1.25;
	float a  = col.a;
	float aL = texture(TEXTURE, duv + vec2(-px.x, 0.0)).a;
	float aR = texture(TEXTURE, duv + vec2( px.x, 0.0)).a;
	float aU = texture(TEXTURE, duv + vec2(0.0, -px.y)).a;
	float aD = texture(TEXTURE, duv + vec2(0.0,  px.y)).a;

	float edge = abs(a - aL) + abs(a - aR) + abs(a - aU) + abs(a - aD);
	edge = clamp(edge * 2.5, 0.0, 1.0) * alive;

	float pulse = 0.7 + 0.3 * sin(t * 2.2 + uv.y * 8.0);
	vec3 glow = glow_color.rgb * edge * edge_glow * pulse * intensity;

	// ---------------------------
	// Vignette
	// ---------------------------
	vec2 p = uv * 2.0 - 1.0;
	float vig = 1.0 - vignette * clamp(dot(p, p), 0.0, 1.0);

	// Final color
	col.rgb = col.rgb * (1.0 - 0.12 * scan_amt * alive) + glow;
	col.rgb = mix(col.rgb, pow(max(col.rgb, vec3(0.0)), vec3(0.85)), 0.25 * intensity * alive);
	col.rgb *= mix(1.0, vig, alive);

	// Preserve true transparency
	col.rgb *= alive;
	col.a   *= alive;

	COLOR = col;
}
