extends RefCounted

class_name LandGenerator

var owner: TerrainGenerator
# Halka Halka kara oluşturma toplam 3 halkamız var --> algoritma internetten 
# --- Genel AYARLAR zart zort ---
# Bu değerler ne kadar büyük olursa eğim o kadar yumuşak olur.
const UNDERWATER_SKIRT_WIDTH_M := 150.0 # Su altı genişliği (Dışarı)
const BEACH_SLOPE_WIDTH_M := 80.0     # Kumsal genişliği (İçeri)
const PLATEAU_HEIGHT_BOOST := 55.0

func _init(owner_ref) -> void:
	owner = owner_ref

func extend_land_polygons(land_entries: Array, factor: float) -> Array:
	if land_entries.is_empty(): return []
	# Genişletmeyi geometri aşamasında yapacağız, orijinal veri kalsın.
	return land_entries.duplicate(true)

func build_landmasses(land_polygons: Array, scale: int) -> Node3D:
	if land_polygons.is_empty(): return null

	var land_root := Node3D.new()
	land_root.name = "Landmasses"

	var land_material: Material = owner._load_material(owner.LAND_MATERIAL)
	
	var created_meshes := 0

	for land_variant in land_polygons:
		var land_dict: Dictionary = land_variant as Dictionary
		if land_dict.is_empty(): continue

		var polygons_variant = land_dict.get("polygons", [])
		if not (polygons_variant is Array): continue

		var polygons: Array = polygons_variant
		for polygon_variant in polygons:
			if not (polygon_variant is Array): continue
			var polygon_points: Array = polygon_variant
			
			# Güvenli ve Eğimli Chunk Üretimi
			var land_chunk := _create_sloped_safe_chunk(polygon_points, land_dict, scale, land_material)
			if land_chunk:
				land_chunk.name = "LandPolygon_%d" % created_meshes
				land_root.add_child(land_chunk)
				created_meshes += 1

	return land_root if created_meshes > 0 else null

func build_coastlines(_coastlines: Array, _scale: int) -> Node3D:
	return null 

#EĞİM -Geometry2D Offset ile
func _create_sloped_safe_chunk(polygon_points: Array, land_props: Dictionary, scale: int, land_material: Material) -> Node3D:
	var sanitized: Array = owner._sanitize_polygon(polygon_points)
	if sanitized.size() < 3: return null

	var world_points: Array = []
	for point_dict in sanitized:
		world_points.append(MapManager.api_to_godot_coordinates(point_dict, scale))

	if world_points.size() < 3: return null

	# 1. Halka: KIYI (COAST)
	var coast_planar: Array[Vector2] = _build_planar_loop(world_points)
	
	# Godot Offset fonksiyonu için yön önemli (Saat yönü tersi)
	if Geometry2D.is_polygon_clockwise(PackedVector2Array(coast_planar)):
		world_points.reverse()
		coast_planar = _build_planar_loop(world_points)

	# Birim Çevirileri
	var skirt_offset: float = owner._meters_to_world_units(UNDERWATER_SKIRT_WIDTH_M, scale)
	var plateau_offset: float = owner._meters_to_world_units(BEACH_SLOPE_WIDTH_M, scale)

	# 2. Halka: ETEK (SKIRT) - Dışarı Genişletme
	# Geometry2D.offset_polygon şekli bozmadan güvenli genişletir.
	
	var skirt_polys = Geometry2D.offset_polygon(PackedVector2Array(coast_planar), skirt_offset, Geometry2D.JOIN_ROUND)
	if skirt_polys.is_empty(): return null
	# Genelde tek parça döner, ilkini alıyoruz.
	var skirt_planar_vec2 = skirt_polys[0]

	# 3. Halka: PLATO - İçeri Daraltma
	# Negatif offset vererek içeri daraltıyoruz.
	var plateau_polys = Geometry2D.offset_polygon(PackedVector2Array(coast_planar), -plateau_offset, Geometry2D.JOIN_ROUND)
	
	var plateau_planar_vec2: PackedVector2Array
	if plateau_polys.is_empty():
		# Ada çok darsa ve daralınca yok oluyorsa, olduğu gibi kalsın (duvar gibi yükselsin)
		plateau_planar_vec2 = PackedVector2Array(coast_planar)
	else:
		plateau_planar_vec2 = plateau_polys[0]

	# Yükseklik Ayarları
	var base_height_m: float = float(land_props.get("base_height_m", owner.LAND_BASE_HEIGHT_MIN_M)) * (owner.LAND_HEIGHT_MULTIPLIER * 1.5) 
	var max_height_m: float = float(land_props.get("max_height_m", owner.LAND_BASE_HEIGHT_MAX_M)) * (owner.LAND_HEIGHT_MULTIPLIER * 2.0)
	
	var h_skirt: float = owner._meters_to_height_units(-45.0) 
	var h_coast: float = owner._meters_to_height_units(0.0)
	# Plato yüksekliği
	var h_plateau: float = owner._meters_to_height_units(base_height_m) + owner._meters_to_height_units(PLATEAU_HEIGHT_BOOST)
	
	# Vertex Listelerini Hazırla (Yüksekliklerini Vererek)
	var skirt_verts: Array[Vector3] = []
	for p in skirt_planar_vec2:
		skirt_verts.append(Vector3(p.x, h_skirt, p.y))
		
	var coast_verts: Array[Vector3] = []
	for p in coast_planar:
		coast_verts.append(Vector3(p.x, h_coast, p.y))
		
	var plateau_verts: Array[Vector3] = []
	for p in plateau_planar_vec2:
		plateau_verts.append(Vector3(p.x, h_plateau, p.y))

	# Mesh Oluşturma
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Eğim: Etek -> Kıyı
	_stitch_rings(st, skirt_verts, coast_verts)

	# 2. Eğim: Kıyı -> Plato
	_stitch_rings(st, coast_verts, plateau_verts)

	# 3. Plato Kapağı (Lid)
	var indices = Geometry2D.triangulate_polygon(plateau_planar_vec2)
	if not indices.is_empty():
		for i in range(0, indices.size(), 3):
			st.add_vertex(plateau_verts[indices[i]])
			st.add_vertex(plateau_verts[indices[i+1]])
			st.add_vertex(plateau_verts[indices[i+2]])

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null: return null

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if land_material:
		mesh_instance.material_override = land_material

	var land_chunk := Node3D.new()
	land_chunk.add_child(mesh_instance)

	var collider: StaticBody3D = owner._create_static_body_from_mesh(mesh)
	if collider:
		land_chunk.add_child(collider)

	return land_chunk

# --- İKİ FARKLI HALKAYI BİRBİRİNE DİKEN FONKSİYON (CRASH FIX) ---
func _stitch_rings(st: SurfaceTool, ring_outer: Array[Vector3], ring_inner: Array[Vector3]):
	if ring_outer.is_empty() or ring_inner.is_empty(): return

	var loop_out = ring_outer.duplicate()
	var loop_in = ring_inner.duplicate()
	
	# Halkaları kapat (Son noktayı başa bağla)
	loop_out.append(loop_out[0])
	loop_in.append(loop_in[0])
	
	var i_out = 0
	var i_in = 0
	
	var n_out = ring_outer.size()
	var n_in = ring_inner.size()
	
	# "En yakın komşu" mantığıyla ilerleyerek örgü yap
	while i_out < n_out or i_in < n_in:
		
		# Hangi tarafta ilerleyeceğimize karar verelim
		var advance_outer = false
		
		# Eğer dış halka bittiyse mecburen içten devam et
		if i_out >= n_out:
			advance_outer = false
		# Eğer iç halka bittiyse mecburen dıştan devam et
		elif i_in >= n_in:
			advance_outer = true
		else:
			# İkisi de bitmediyse mesafeye bak
			var p_out = loop_out[i_out]
			var p_out_next = loop_out[i_out + 1]
			var p_in = loop_in[i_in]
			var p_in_next = loop_in[i_in + 1]
			
			var dist1 = p_out_next.distance_squared_to(p_in)
			var dist2 = p_out.distance_squared_to(p_in_next)
			
			advance_outer = (dist1 < dist2)
		
		if advance_outer:
			# Dış halkada bir adım at
			var p_curr = loop_out[i_out]
			var p_next = loop_out[i_out + 1]
			var p_anchor = loop_in[i_in]
			owner._add_quad_surface(st, p_curr, p_next, p_anchor, p_anchor, Color.WHITE, Color.WHITE, false)
			i_out += 1
		else:
			# İç halkada bir adım at
			var p_anchor = loop_out[i_out]
			var p_curr = loop_in[i_in]
			var p_next = loop_in[i_in + 1]
			owner._add_quad_surface(st, p_anchor, p_anchor, p_next, p_curr, Color.WHITE, Color.WHITE, false)
			i_in += 1

func _build_planar_loop(points: Array) -> Array[Vector2]:
	var loop: Array[Vector2] = []
	for point in points:
		if point is Vector3:
			loop.append(Vector2(point.x, point.z))
	return loop
