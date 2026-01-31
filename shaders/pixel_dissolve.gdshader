shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;          // 0 = intact, 1 = gone
uniform float pixel_size : hint_range(1.0, 12.0) = 3.0;        // dissolve “chunk” size (in pixels)
uniform float edge_width : hint_range(0.0, 0.3) = 0.08;        // glow band thickness
uniform vec4 edge_color : source_color = vec4(0.6, 1.0, 0.6, 1.0); // glow tint

// deterministic hash per “pixel block”
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a <= 0.001) discard;

	// Godot 4: TEXTURE_PIXEL_SIZE is vec2 (1/width, 1/height)
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;

	// Quantize into pixel blocks (stable “chunky” dissolve)
	vec2 grid = floor((UV * tex_size) / max(pixel_size, 1.0));

	// Random threshold per block
	float rnd = hash21(grid);

	// Cutoff: pixels with rnd < progress dissolve away
	float cut = progress;

	// Keep pixels where rnd >= cut
	float alive = step(cut, rnd);

	// Glow band along the dissolving frontier
	float e0 = smoothstep(cut, cut + edge_width, rnd);
	float e1 = smoothstep(cut + edge_width, cut + edge_width * 2.0, rnd);
	float edge = clamp(e0 - e1, 0.0, 1.0);

	// Apply
	vec4 col = tex;
	col.rgb += edge_color.rgb * edge * tex.a; // glow only where sprite exists
	col.a *= alive;

	if (col.a <= 0.001) discard;
	COLOR = col;
}
