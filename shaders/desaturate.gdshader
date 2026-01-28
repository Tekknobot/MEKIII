shader_type canvas_item;

uniform float saturation : hint_range(0.0, 1.0) = 1.0; // 1 = normal, 0 = grayscale

void fragment() {
	vec4 c = texture(TEXTURE, UV);

	// Luma (perceptual grayscale)
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 gray = vec3(g);

	c.rgb = mix(gray, c.rgb, saturation);

	COLOR = c;
}
