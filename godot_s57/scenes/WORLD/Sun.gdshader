shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

void fragment() {
    vec2 centered = UV * 2.0 - 1.0;
    float r = length(centered);
    if (r > 1.0) {
        discard;
    }
    float intensity = smoothstep(1.0, 0.0, r);
    ALBEDO = vec3(1.0);
    EMISSION = vec3(1.0, 0.95, 0.8) * pow(intensity, 1.5) * 3.0;
}