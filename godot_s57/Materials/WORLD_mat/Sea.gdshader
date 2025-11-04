shader_type spatial;
render_mode depth_draw_opaque, specular_schlick_ggx, cull_back;

uniform vec3 shallow_color : source_color = vec3(0.129, 0.596, 0.776);
uniform vec3 deep_color : source_color = vec3(0.015, 0.082, 0.192);
uniform float depth_power : hint_range(0.2, 4.0, 0.05) = 1.35;

uniform float wave_amplitude : hint_range(0.0, 5.0, 0.01) = 0.8;
uniform float wave_length : hint_range(1.0, 200.0, 0.5) = 65.0;
uniform float wave_speed : hint_range(0.0, 10.0, 0.01) = 0.6;
uniform float secondary_wave_weight : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float choppiness : hint_range(0.0, 2.0, 0.01) = 0.4;

uniform float foam_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float foam_cutoff : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform vec3 foam_color : source_color = vec3(0.83, 0.92, 1.0);

uniform float fresnel_strength : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float fresnel_power : hint_range(1.0, 8.0, 0.1) = 5.0;

uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.18;

varying float v_depth_norm;
varying float v_wave_magnitude;

void vertex() {
	float depth_norm = clamp(COLOR.r, 0.0, 1.0);
	v_depth_norm = depth_norm;

	float wavelength = max(wave_length, 0.01);
	float wavelength_secondary = max(wave_length * 0.5, 0.01);

	float phase_primary = (VERTEX.x + VERTEX.z) / wavelength + TIME * wave_speed;
	float phase_secondary = (VERTEX.x * 1.3 - VERTEX.z * 0.7) / wavelength_secondary + TIME * wave_speed * 1.65;

	float wave_primary = sin(phase_primary);
	float wave_secondary = sin(phase_secondary);

	float depth_influence = mix(0.35, 1.0, depth_norm);
	float amplitude = wave_amplitude * depth_influence;

	float wave_height = wave_primary + wave_secondary * secondary_wave_weight;
	VERTEX.y += wave_height * amplitude;

	float d_primary = cos(phase_primary) / wavelength;
	float d_secondary = cos(phase_secondary) / wavelength_secondary * secondary_wave_weight;

	float slope_x = (d_primary + d_secondary * 1.3) * amplitude;
	float slope_z = (d_primary - d_secondary * 0.7) * amplitude;

	vec3 normal = normalize(vec3(-slope_x * choppiness, 1.0, -slope_z * choppiness));
	NORMAL = normal;

	v_wave_magnitude = abs(wave_height);
}

void fragment() {
	float depth_norm = clamp(v_depth_norm, 0.0, 1.0);
	float shallow_factor = pow(1.0 - depth_norm, depth_power);
	vec3 base_color = mix(deep_color, shallow_color, shallow_factor);

	vec3 light_dir = normalize(vec3(-0.3, 0.85, -0.4));
	float diffuse = max(dot(NORMAL, light_dir), 0.0);

	vec3 view_dir = normalize(-VIEW);
	float fresnel = pow(clamp(1.0 - dot(NORMAL, view_dir), 0.0, 1.0), fresnel_power) * fresnel_strength;

	float shallow_mask = 1.0 - smoothstep(foam_cutoff, 1.0, depth_norm);
	float foam_wave = smoothstep(0.05, 0.6, v_wave_magnitude);
	float foam = foam_strength * shallow_mask * foam_wave;

	vec3 color = base_color;
	color += foam * foam_color;
	color += fresnel * mix(base_color, vec3(0.55, 0.75, 0.9), 0.5);

	float lighting = 0.35 + diffuse * 0.45;
	ALBEDO = color * lighting;
	SPECULAR = specular_strength;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	ALPHA = 1.0;
}

