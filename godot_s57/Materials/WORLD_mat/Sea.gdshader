shader_type spatial;
render_mode blend_mix, specular_schlick_ggx, cull_back;

uniform vec3 shallow_color : source_color = vec3(0.18, 0.63, 0.79);
uniform vec3 deep_color : source_color = vec3(0.05, 0.15, 0.28);
uniform float depth_power : hint_range(0.2, 4.0, 0.05) = 1.4;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float wave_amplitude : hint_range(0.0, 5.0, 0.01) = 0.75;
uniform float wave_length : hint_range(1.0, 200.0, 0.5) = 60.0;
uniform float wave_speed : hint_range(0.0, 10.0, 0.01) = 0.7;
uniform float secondary_wave_weight : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float tertiary_wave_weight : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float tertiary_wave_scale : hint_range(0.2, 2.0, 0.01) = 0.65;
uniform float choppiness : hint_range(0.0, 2.0, 0.01) = 0.45;

uniform float foam_strength : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float foam_cutoff : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform vec3 foam_color : source_color = vec3(0.86, 0.93, 0.98);
uniform float foam_emission_strength : hint_range(0.0, 1.0, 0.01) = 0.35;

uniform float fresnel_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float fresnel_power : hint_range(1.0, 8.0, 0.1) = 5.0;

uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.08;

uniform float detail_frequency : hint_range(0.1, 12.0, 0.1) = 6.0;
uniform float detail_speed : hint_range(0.0, 3.0, 0.01) = 0.5;
uniform float normal_detail_strength : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float reflection_strength : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform vec3 reflection_tint : source_color = vec3(0.6, 0.74, 0.9);

uniform float transparency_shallow : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float transparency_deep : hint_range(0.0, 1.0, 0.01) = 0.15;

varying float v_depth_norm;
varying float v_wave_magnitude;

void vertex() {
	float depth_norm = clamp(COLOR.r, 0.0, 1.0);
	v_depth_norm = depth_norm;

	float wavelength = max(wave_length, 0.01);
	float wavelength_secondary = max(wave_length * 0.55, 0.01);
	float wavelength_tertiary = max(wave_length * tertiary_wave_scale, 0.01);

	float phase_primary = (VERTEX.x + VERTEX.z) / wavelength + TIME * wave_speed;
	float phase_secondary = (VERTEX.x * 1.37 - VERTEX.z * 0.82) / wavelength_secondary + TIME * wave_speed * 1.7;
	float phase_tertiary = (VERTEX.x * 0.58 + VERTEX.z * 1.05) / wavelength_tertiary + TIME * wave_speed * 2.2;

	float wave_primary = sin(phase_primary);
	float wave_secondary = sin(phase_secondary);
	float wave_tertiary = sin(phase_tertiary);

	float depth_influence = mix(0.32, 1.0, depth_norm);
	float amplitude = wave_amplitude * depth_influence;

	float wave_height = wave_primary
		+ wave_secondary * secondary_wave_weight
		+ wave_tertiary * tertiary_wave_weight;

	float micro_variation = sin((VERTEX.x * 0.19 + VERTEX.z * 0.26) + TIME * (wave_speed * 2.4)) * 0.06;
	wave_height += micro_variation;

	VERTEX.y += wave_height * amplitude;

	float d_primary = cos(phase_primary) / wavelength;
	float d_secondary = cos(phase_secondary) / wavelength_secondary * secondary_wave_weight;
	float d_tertiary = cos(phase_tertiary) / wavelength_tertiary * tertiary_wave_weight;

	float slope_x = (d_primary + d_secondary * 1.3 + d_tertiary * 0.65) * amplitude;
	float slope_z = (d_primary - d_secondary * 0.75 + d_tertiary * 1.1) * amplitude;

	vec3 normal = normalize(vec3(-slope_x * choppiness, 1.0, -slope_z * choppiness));
	NORMAL = normal;

	v_wave_magnitude = abs(wave_height);
}

void fragment() {
	float depth_norm = clamp(v_depth_norm, 0.0, 1.0);
	float shallow_factor = pow(1.0 - depth_norm, depth_power);
	vec3 base_color = mix(deep_color, shallow_color, shallow_factor);

	vec3 light_dir = normalize(vec3(-0.25, 0.9, -0.35));
	float diffuse = max(dot(NORMAL, light_dir), 0.0);

	vec3 view_dir = normalize(-VIEW);
	float fresnel = pow(clamp(1.0 - dot(NORMAL, view_dir), 0.0, 1.0), fresnel_power) * fresnel_strength;

	float shallow_mask = 1.0 - smoothstep(foam_cutoff, 1.0, depth_norm);
	float foam_wave = smoothstep(0.05, 0.6, v_wave_magnitude);
	vec2 detail_uv = UV * detail_frequency + vec2(TIME * detail_speed, -TIME * detail_speed * 0.74);
	float detail_a = sin(detail_uv.x) * cos(detail_uv.y);
	float detail_b = sin(detail_uv.x * 2.15 + detail_uv.y * 1.27 + TIME * detail_speed * 0.62);
	float detail_noise = clamp(detail_a * 0.5 + detail_b * 0.5 + 0.5, 0.0, 1.0);
	float foam = foam_strength * shallow_mask * max(foam_wave, detail_noise * 0.6);

	vec3 tint_color = mix(vec3(0.78, 0.9, 0.97), vec3(0.15, 0.28, 0.45), depth_norm);
	float tint_factor = mix(0.22, 0.05, depth_norm);
	vec3 color = mix(base_color, tint_color, tint_factor + detail_noise * 0.05);

	vec3 reflection_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, roughness * 4.0).rgb * reflection_tint;
	color = mix(color, reflection_color, reflection_strength * fresnel);

	float foam_blend = clamp(foam, 0.0, 1.0);
	vec3 foam_tint = foam_color * 0.65;
	color = mix(color, color + foam_tint, foam_blend);

	vec3 detail_normal = normalize(vec3(detail_b, 1.0, detail_a));
	NORMAL = normalize(mix(NORMAL, detail_normal, normal_detail_strength));

	float lighting = 0.2 + diffuse * 0.4;
	ALBEDO = color * lighting;
	SPECULAR = specular_strength;
	ROUGHNESS = clamp(roughness + (1.0 - depth_norm) * 0.08, 0.03, 1.0);
	METALLIC = 0.0;
	EMISSION = foam * foam_color * (foam_emission_strength * 0.5);

	float alpha_shallow = clamp(1.0 - transparency_shallow, 0.05, 1.0);
	float alpha_deep = clamp(1.0 - transparency_deep, 0.05, 1.0);
	ALPHA = mix(alpha_deep, alpha_shallow, 1.0 - depth_norm);
}
