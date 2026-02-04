shader_type canvas_item;

/* ---------- SCREEN TEXTURE ---------- */
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

/* ---------- PIXELATION ---------- */
uniform float pixel_size : hint_range(1.0, 8.0) = 2.0;

/* ---------- CRT EFFECTS ---------- */
uniform float scanline_amount : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_density : hint_range(64.0, 1024.0) = 240.0;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.05;

/* ---------- COLOR GRADING ---------- */
uniform float contrast : hint_range(0.5, 2.0) = 1.1;
uniform float saturation : hint_range(0.0, 2.0) = 1.15;
uniform vec3 color_tint : source_color = vec3(1.0, 0.98, 0.95);

/* ---------- VIGNETTE ---------- */
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.2;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.8;

/* ---------- CHROMATIC ABERRATION ---------- */
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 0.5;

/* ---------- SCREEN SHAKE ---------- */
uniform float shake_amount : hint_range(0.0, 10.0) = 0.0;

/* ---------- NOISE ---------- */
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

/* ---------- SATURATION ---------- */
vec3 adjust_saturation(vec3 col, float sat) {
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	return mix(vec3(luma), col, sat);
}

/* ---------- CONTRAST ---------- */
vec3 adjust_contrast(vec3 col, float con) {
	return (col - 0.5) * con + 0.5;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	
	/* ---- SCREEN SHAKE ---- */
	if (shake_amount > 0.0) {
		float shake_x = (hash(vec2(t * 10.0, 1.0)) - 0.5) * shake_amount * 0.001;
		float shake_y = (hash(vec2(t * 10.0, 2.0)) - 0.5) * shake_amount * 0.001;
		uv += vec2(shake_x, shake_y);
	}
	
	/* ---- PIXELATION ---- */
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 pixel_uv = uv;
	if (pixel_size > 1.0) {
		vec2 pixel_count = viewport_size / pixel_size;
		pixel_uv = floor(uv * pixel_count) / pixel_count;
		pixel_uv += 0.5 / pixel_count; // Center the pixel
	}
	
	/* ---- CHROMATIC ABERRATION ---- */
	vec3 col;
	if (chromatic_aberration > 0.0) {
		vec2 offset = vec2(chromatic_aberration * 0.001, 0.0);
		float r = texture(SCREEN_TEXTURE, pixel_uv - offset).r;
		float g = texture(SCREEN_TEXTURE, pixel_uv).g;
		float b = texture(SCREEN_TEXTURE, pixel_uv + offset).b;
		col = vec3(r, g, b);
	} else {
		col = texture(SCREEN_TEXTURE, pixel_uv).rgb;
	}
	
	/* ---- COLOR GRADING ---- */
	col = adjust_contrast(col, contrast);
	col = adjust_saturation(col, saturation);
	col *= color_tint;
	
	/* ---- SCANLINES (using original UV for screen-space effect) ---- */
	if (scanline_amount > 0.0) {
		float sl = sin(uv.y * scanline_density + t * 30.0) * 0.5 + 0.5;
		col *= mix(1.0, 0.9, sl * scanline_amount);
	}
	
	/* ---- GRAIN ---- */
	if (noise_amount > 0.0) {
		float n = hash(uv * vec2(1920.0, 1080.0) + vec2(t * 5.0, t * 3.0));
		col += (n - 0.5) * noise_amount * 0.08;
	}
	
	/* ---- VIGNETTE ---- */
	if (vignette_amount > 0.0) {
		vec2 p = uv * 2.0 - 1.0;
		float v = 1.0 - vignette_amount * smoothstep(0.3, vignette_softness, length(p));
		col *= v;
	}
	
	COLOR = vec4(col, 1.0);
}