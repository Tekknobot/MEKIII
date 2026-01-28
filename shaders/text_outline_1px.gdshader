shader_type canvas_item;

uniform vec4 font_color    : source_color = vec4(0.8, 1.0, 0.6, 1.0); // fill color
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // outline color
uniform float outline_px = 2.0; // outline thickness in pixels

void fragment() {
    vec4 col = texture(TEXTURE, UV);

    // Original glyph alpha
    float a = col.a;

    // Pixel size in texture UV space
    vec2 px = TEXTURE_PIXEL_SIZE * outline_px;

    // Sample neighboring alpha to detect edges
    float n =
        texture(TEXTURE, UV + vec2( px.x, 0.0)).a +
        texture(TEXTURE, UV + vec2(-px.x, 0.0)).a +
        texture(TEXTURE, UV + vec2(0.0,  px.y)).a +
        texture(TEXTURE, UV + vec2(0.0, -px.y)).a +
        texture(TEXTURE, UV + vec2( px.x,  px.y)).a +
        texture(TEXTURE, UV + vec2(-px.x,  px.y)).a +
        texture(TEXTURE, UV + vec2( px.x, -px.y)).a +
        texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;

    // Edge mask where original glyph isn't drawn
    float edge = clamp(n, 0.0, 1.0) * (1.0 - a);

    vec3 final_rgb =
        mix(outline_color.rgb, font_color.rgb, a);

    float final_a = max(a, edge * outline_color.a);

    COLOR = vec4(final_rgb, final_a);
}
