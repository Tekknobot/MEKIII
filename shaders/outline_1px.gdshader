shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float thickness_px = 2.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * thickness_px;

	float neighbor_alpha =
		texture(TEXTURE, UV + vec2( px.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(-px.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(0.0,  px.y)).a +
		texture(TEXTURE, UV + vec2(0.0, -px.y)).a;

	// ✅ Only draw OUTLINE pixels (transparent pixels next to opaque pixels)
	if (tex.a <= 0.0 && neighbor_alpha > 0.0) {
		COLOR = outline_color; // do NOT multiply by COLOR/modulate, keep it pure
	} else {
		COLOR = vec4(0.0);
	}
}
