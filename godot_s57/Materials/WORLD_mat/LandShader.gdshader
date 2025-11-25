shader_type spatial;
render_mode cull_disabled;

// --- RENK AYARLARI ---
uniform vec3 sand_color_main : source_color = vec3(0.82, 0.78, 0.60); 
uniform vec3 sand_color_detail : source_color = vec3(0.65, 0.60, 0.45); 
uniform vec3 rock_color : source_color = vec3(0.25, 0.28, 0.32); 

// --- DOKU ---
uniform sampler2D noise_texture : filter_linear_mipmap; 
uniform float noise_scale = 0.02; 

// --- YÜKSEKLİK VE EĞİM ---
uniform float sand_height_max = 1.5; 
uniform float blend_sharpness = 2.0; 
uniform float slope_factor = 0.7; 

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_world_normal; // YENİ: Dünya Normali

void vertex() {
	v_height = VERTEX.y;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// KRİTİK DÜZELTME: Normal vektörünü kameraya göre değil, dünyaya göre alıyoruz.
	// Böylece kamera dönünce renkler değişmez.
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float noise_val = texture(noise_texture, v_world_pos.xz * noise_scale).r;
	
	// Dokular
	vec3 final_sand = mix(sand_color_main, sand_color_detail, noise_val * 0.4);
	vec3 final_rock = mix(rock_color, rock_color * 0.7, noise_val * 0.5);
	
	// 1. Yükseklik Faktörü
	float height_threshold = sand_height_max + (noise_val - 0.5) * 1.0;
	float is_high = clamp((v_height - height_threshold) * blend_sharpness, 0.0, 1.0);
	
	// 2. Eğim Faktörü (DÜZELTİLDİ)
	// Artık 'NORMAL' yerine 'v_world_normal' kullanıyoruz.
	float slope = dot(normalize(v_world_normal), vec3(0.0, 1.0, 0.0));
	float is_steep = 1.0 - smoothstep(slope_factor - 0.1, slope_factor + 0.1, slope);
	
	// 3. Karıştırma (Yüksekse VEYA Dikse -> Kaya)
	float rock_mask = max(is_high, is_steep);
	
	vec3 final_color = mix(final_sand, final_rock, rock_mask);
	
	ALBEDO = final_color;
	ROUGHNESS = mix(0.9, 0.6, rock_mask); 
	SPECULAR = 0.1;
}