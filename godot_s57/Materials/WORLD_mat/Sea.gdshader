shader_type spatial;
render_mode blend_mix, specular_schlick_ggx, cull_back, depth_draw_opaque;

// --- MEVCUT UNIFORM'LAR ---
uniform vec3 shallow_color : source_color = vec3(0.18, 0.63, 0.79);
uniform vec3 deep_color : source_color = vec3(0.05, 0.15, 0.28);
uniform float depth_power : hint_range(0.2, 4.0, 0.05) = 1.4;

uniform sampler2D normal_map_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_map_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D height_map : repeat_enable, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// --- YENİ EKLENEN: DEPTH TEXTURE ---
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

// --- YENİ EKLENEN: KIYI YUMUŞATMA AYARLARI ---
uniform float shore_fade_distance : hint_range(0.0, 5.0, 0.1) = 1.0; // Kıyı şeffaflık mesafesi
uniform float shore_foam_distance : hint_range(0.0, 2.0, 0.1) = 0.5; // Kıyı köpük genişliği
uniform float shore_foam_strength : hint_range(0.0, 2.0, 0.1) = 1.2; // Kıyı köpük parlaklığı

uniform float normal_frequency : hint_range(0.001, 0.15, 0.001) = 0.035;
uniform vec2 normal_direction_a = vec2(1.0, 0.25);
uniform vec2 normal_direction_b = vec2(-0.45, 1.0);
uniform float normal_speed_a : hint_range(0.0, 4.0, 0.01) = 0.65;
uniform float normal_speed_b : hint_range(0.0, 4.0, 0.01) = 0.45;
uniform float normal_mix : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float normal_detail_strength : hint_range(0.0, 1.0, 0.01) = 0.32;

uniform float height_frequency : hint_range(0.001, 0.1, 0.001) = 0.02;
uniform vec2 height_direction = vec2(0.55, 0.78);
uniform float height_speed : hint_range(0.0, 2.0, 0.01) = 0.32;
uniform float height_amplitude : hint_range(0.0, 5.0, 0.01) = 0.85;

uniform float foam_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float foam_bias : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float foam_width : hint_range(0.01, 1.0, 0.01) = 0.45;
uniform vec3 foam_color : source_color = vec3(0.78, 0.85, 0.92);
uniform float foam_emission_strength : hint_range(0.0, 1.0, 0.01) = 0.12;

uniform float fresnel_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float fresnel_power : hint_range(1.0, 8.0, 0.1) = 2.8;
uniform vec3 reflection_tint : source_color = vec3(0.56, 0.64, 0.74);
uniform float reflection_strength : hint_range(0.0, 1.0, 0.01) = 0.08;

uniform float base_roughness : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.25;

uniform float transparency_shallow : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float transparency_deep : hint_range(0.0, 1.0, 0.01) = 0.26;
uniform float color_noise_strength : hint_range(0.0, 1.0, 0.01) = 0.08;

varying float v_depth_norm;
varying float v_wave_height;
varying vec3 v_world_position;

vec2 rotate_uv(vec2 uv, vec2 direction) {
	float len = max(length(direction), 0.0001);
	vec2 dir = direction / len;
	return vec2(dir.x * uv.x - dir.y * uv.y, dir.y * uv.x + dir.x * uv.y);
}

void vertex() {
	// Senin mevcut Vertex Color'dan gelen derinlik verin (bunu koruyoruz)
	float depth_norm = clamp(COLOR.r, 0.0, 1.0);
	v_depth_norm = depth_norm;

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 height_uv = world_pos.xz * height_frequency + height_direction * (TIME * height_speed);
	float height_sample = texture(height_map, height_uv).r;
	float height_offset = (height_sample - 0.5) * height_amplitude;

	VERTEX.y += height_offset;

	vec3 displaced_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_position = displaced_world;
	v_wave_height = height_offset;
}

void fragment() {
	// --- MEVCUT RENK VE NORMAL HESAPLAMALARI ---
	float depth_norm = clamp(v_depth_norm, 0.0, 1.0);
	float shallow_factor = pow(1.0 - depth_norm, depth_power);
	vec3 base_color = mix(deep_color, shallow_color, shallow_factor);

	vec2 world_uv = v_world_position.xz * normal_frequency;
	vec2 uv_a = world_uv + rotate_uv(vec2(TIME * normal_speed_a), normal_direction_a);
	vec2 uv_b = world_uv + rotate_uv(vec2(TIME * normal_speed_b), normal_direction_b);

	vec3 n_a = texture(normal_map_a, uv_a).rgb * 2.0 - 1.0;
	vec3 n_b = texture(normal_map_b, uv_b).rgb * 2.0 - 1.0;
	vec3 blended_normal = normalize(mix(n_a, n_b, normal_mix));
	NORMAL = normalize(mix(NORMAL, blended_normal, normal_detail_strength));

	vec3 light_dir = normalize(vec3(-0.3, 0.92, -0.41));
	float diffuse = max(dot(NORMAL, light_dir), 0.0);

	vec3 view_dir = normalize(-VIEW);
	float fresnel = pow(clamp(1.0 - dot(NORMAL, view_dir), 0.0, 1.0), fresnel_power) * fresnel_strength;

	float color_noise = sin(dot(v_world_position.xz, vec2(0.045, -0.038)) + TIME * 0.3) * 0.5 + 0.5;
	base_color = mix(base_color, base_color + vec3(0.05, 0.07, 0.09) * color_noise, color_noise_strength);

	vec3 reflection_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, 3.0).rgb * reflection_tint;
	float fresnel_mix = mix(0.05, 1.0, clamp(fresnel, 0.0, 1.0));
	base_color = mix(base_color, reflection_color, reflection_strength * fresnel_mix);

	// --- YENİ EKLENEN: DERİNLİK VE YUMUŞATMA (DEPTH FADE) ---

	// 1. Derinlik Texture'ını oku (Depth Buffer)
	float depth_tex = texture(depth_texture, SCREEN_UV).x;
	// 2. Linear Derinliğe çevir (Kamera Z'si)
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_tex);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_scene_depth = -view.z;
	float linear_surface_depth = FRAGCOORD.z / FRAGCOORD.w; // Alternatif hesaplama gerekebilir ama Godot 4 için VERTEX.z yeterli

	// Daha basit ve güvenilir Godot 4.x derinlik farkı hesabı:
	// VERTEX.z (View Space'teki Z) negatiftir.
	// Linear Scene Depth pozitiftir (genelde).
	// Fark = Sahne Derinliği - Su Yüzeyi Derinliği
	float depth_diff = linear_scene_depth - linear_surface_depth;
	// Eğer VERTEX.z ile sorun yaşarsan: depth_diff = linear_scene_depth - (1.0 / FRAGCOORD.w);

	// 3. Kıyı Şeffaflığı (Fade)
	// depth_diff küçükse (kıyıya yakınsa) alpha 0'a yaklaşır.
	float shore_alpha = clamp(depth_diff / shore_fade_distance, 0.0, 1.0);
	shore_alpha = pow(shore_alpha, 0.5); // Daha yumuşak geçiş için

	// 4. Kıyı Köpüğü (Shore Foam)
	// Kıyıya çok yakın yerlerde (shore_foam_distance) beyazlık ekle
	float shore_foam_factor = clamp(1.0 - (depth_diff / shore_foam_distance), 0.0, 1.0);
	shore_foam_factor = pow(shore_foam_factor, 2.0); // Keskinleştir

	// Mevcut Dalga Köpüğü ile Kıyı Köpüğünü Birleştir
	float wave_intensity = smoothstep(foam_bias, foam_bias + foam_width, abs(v_wave_height));
	float wave_foam_factor = foam_strength * wave_intensity * (1.0 - depth_norm);

	// Toplam köpük
	float total_foam = clamp(wave_foam_factor + (shore_foam_factor * shore_foam_strength), 0.0, 1.0);

	// Rengi Köpükle Karıştır
	base_color = mix(base_color, foam_color, total_foam);

	// --- ÇIKIŞ ---
	float lighting = 0.35 + diffuse * 0.25;
	ALBEDO = base_color * lighting;
	SPECULAR = specular_strength;
	ROUGHNESS = clamp(base_roughness + (1.0 - fresnel) * 0.05, 0.03, 1.0);
	METALLIC = 0.0;

	// Köpük parlasın
	EMISSION = foam_color * total_foam * foam_emission_strength;

	// Mevcut transparanlık mantığını Kıyı Fade ile çarp
	float base_transparency_val = mix(transparency_deep, transparency_shallow, pow(1.0 - depth_norm, 1.3));
	float base_alpha = clamp(1.0 - base_transparency_val, 0.2, 0.95);

	// Son Alpha: Hem derinliğe göre hem de kıyı yakınlığına göre şeffaflaş
	ALPHA = base_alpha * shore_alpha;
}