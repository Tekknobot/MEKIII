shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float thickness_px = 1.0;

void fragment() {
	// ✅ This contains Modulate/SelfModulate tint
	vec4 modulate = COLOR;

	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * thickness_px;

	float neighbor_alpha =
		texture(TEXTURE, UV + vec2( px.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(-px.x, 0.0)).a +
		texture(TEXTURE, UV + vec2(0.0,  px.y)).a +
		texture(TEXTURE, UV + vec2(0.0, -px.y)).a;

	if (tex.a > 0.0) {
		// sprite, preserving modulation
		COLOR = tex * modulate;
	} else if (neighbor_alpha > 0.0) {
		// outline, also preserving modulation
		COLOR = outline_color * modulate;
	} else {
		COLOR = vec4(0.0);
	}
}
