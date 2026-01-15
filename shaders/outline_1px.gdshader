shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.2, 1.0);
uniform float thickness_px = 1.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	// Compute 1px in UV space
	vec2 px = TEXTURE_PIXEL_SIZE * thickness_px;

	// Sample neighbors alpha
	float neighbor_alpha =
		texture(TEXTURE, UV + vec2(px.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(-px.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(0.0, px.y)).a +
		texture(TEXTURE, UV + vec2(0.0, -px.y)).a;

	// If original pixel exists → draw original
	// Else if neighbor exists → draw outline
	// Else → transparent
	if (col.a > 0.0) {
		COLOR = col;
	} 
	else if (neighbor_alpha > 0.0) {
		COLOR = outline_color;
	} 
	else {
		COLOR = vec4(0.0);
	}
}
