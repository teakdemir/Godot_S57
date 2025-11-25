shader_type spatial;
render_mode cull_disabled; // Duvarların iki yüzü de görünsün

// --- RENK AYARLARI ---
uniform vec3 sand_color : source_color = vec3(0.76, 0.69, 0.5); // Kum Rengi
uniform vec3 rock_color : source_color = vec3(0.15, 0.17, 0.2); // Kaya Rengi
uniform vec3 grass_color : source_color = vec3(0.1, 0.25, 0.1); // İstersen çim

// --- YÜKSEKLİK AYARLARI ---
uniform float sand_height_max = 1.5; // Kum kaça kadar çıksın (Metre/Unit)
uniform float blend_sharpness = 4.0; // Geçiş yumuşaklığı

varying float v_height;

void vertex() {
	// Vertex'in dünya yüksekliğini fragment'a taşı
	v_height = VERTEX.y;
}

void fragment() {
	// Yüksekliğe göre Kum ve Kaya karışımı
	// Yükseklik sand_height_max'tan küçükse kum, büyükse kaya
	float height_factor = clamp((v_height - sand_height_max) * blend_sharpness, 0.0, 1.0);
	
	vec3 final_color = mix(sand_color, rock_color, height_factor);
	
	ALBEDO = final_color;
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
}
