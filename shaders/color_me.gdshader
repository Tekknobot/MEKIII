shader_type canvas_item;

uniform vec4 target_color : source_color = vec4(1.0, 0.2, 0.6, 1.0);

// Hue window for "green" (0..1). Green is around ~0.33.
uniform float hue_center = 0.33;
uniform float hue_width  = 0.12;   // widen to catch yellow-green/teal
uniform float min_sat    = 0.20;   // ignore greys
uniform float min_val    = 0.08;   // ignore near-black
uniform float preserve_shading = 1.0;

// --- RGB -> HSV (0..1) ---
vec3 rgb_to_hsv(vec3 c) {
    float cmax = max(c.r, max(c.g, c.b));
    float cmin = min(c.r, min(c.g, c.b));
    float delta = cmax - cmin;

    float h = 0.0;
    if (delta > 0.00001) {
        if (cmax == c.r) {
            h = mod((c.g - c.b) / delta, 6.0);
        } else if (cmax == c.g) {
            h = ((c.b - c.r) / delta) + 2.0;
        } else {
            h = ((c.r - c.g) / delta) + 4.0;
        }
        h /= 6.0;
        if (h < 0.0) h += 1.0;
    }

    float s = (cmax <= 0.00001) ? 0.0 : (delta / cmax);
    float v = cmax;
    return vec3(h, s, v);
}

// circular hue distance (wrap-around safe)
float hue_dist(float a, float b) {
    float d = abs(a - b);
    return min(d, 1.0 - d);
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);

    vec3 hsv = rgb_to_hsv(col.rgb);
    float h = hsv.x;
    float s = hsv.y;
    float v = hsv.z;

    // 1 when hue is near green, else 0 (soft edge)
    float hd = hue_dist(h, hue_center);
    float hue_mask = 1.0 - smoothstep(hue_width * 0.6, hue_width, hd);

    // prevent recoloring greys/blacks
    float sat_mask = smoothstep(min_sat, min_sat + 0.10, s);
    float val_mask = smoothstep(min_val, min_val + 0.08, v);

    float mask = hue_mask * sat_mask * val_mask;

    // Preserve original shading by matching luminance
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    float t_lum = max(dot(target_color.rgb, vec3(0.299, 0.587, 0.114)), 0.001);

    vec3 shaded_target = mix(
        target_color.rgb,
        target_color.rgb * (lum / t_lum),
        preserve_shading
    );

    vec3 out_rgb = mix(col.rgb, shaded_target, mask);
    COLOR = vec4(out_rgb, col.a);
}
