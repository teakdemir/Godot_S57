extends RefCounted

class_name LandGenerator

var owner: TerrainGenerator

# --- AYARLAR (Yükseltilmiş Değerler) ---
const UNDERWATER_SKIRT_WIDTH_M := 250.0 # Su altı genişliği
const BEACH_SLOPE_WIDTH_M := 150.0     # Sahil eğim genişliği (Artırıldı)
const PEAK_HEIGHT_BOOST_M := 45.0      # Tepe ek yüksekliği (Ciddi oranda artırıldı)

func _init(owner_ref) -> void:
	owner = owner_ref

# Harita sinirlarini tasirmamak icin kara poligonlarini genisletir.
func extend_land_polygons(land_entries: Array, factor: float) -> Array:
	if land_entries.is_empty():
		return []
	if factor <= 1.0:
		return land_entries.duplicate(true)

	var extended_entries: Array = []
	for entry_variant in land_entries:
		var land_dict: Dictionary = entry_variant as Dictionary
		if land_dict.is_empty():
			continue

		var polygons_variant = land_dict.get("polygons", [])
		if not (polygons_variant is Array):
			continue

		var expanded_polygons: Array = owner._expand_polygon_collection(polygons_variant, factor)
		if expanded_polygons.is_empty():
			expanded_polygons = owner._sanitize_polygon_collection(polygons_variant)

		if expanded_polygons.is_empty():
			continue

		var duplicated := land_dict.duplicate(true)
		duplicated["polygons"] = expanded_polygons
		extended_entries.append(duplicated)

	return extended_entries if extended_entries.size() > 0 else land_entries.duplicate(true)

# Kara poligonlarini hacimli arazi bloklarina donusturur.
func build_landmasses(land_polygons: Array, scale: int) -> Node3D:
	if land_polygons.is_empty():
		return null

	var land_root := Node3D.new()
	land_root.name = "Landmasses"

	var land_material: Material = owner._load_material(owner.LAND_MATERIAL)
	if land_material:
		land_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var created_meshes := 0

	for land_variant in land_polygons:
		var land_dict: Dictionary = land_variant as Dictionary
		if land_dict.is_empty():
			continue

		var polygons_variant = land_dict.get("polygons", [])
		if not (polygons_variant is Array):
			continue

		var polygons: Array = polygons_variant
		for polygon_variant in polygons:
			if not (polygon_variant is Array):
				continue
			var polygon_points: Array = polygon_variant
			# Yeni Tepe Noktali Chunk Üretimi
			var land_chunk := _create_peaked_land_chunk(polygon_points, land_dict, scale, land_material)
			if land_chunk:
				land_chunk.name = "LandPolygon_%d" % created_meshes
				land_root.add_child(land_chunk)
				created_meshes += 1

	return land_root if created_meshes > 0 else null

# Kiyi cizgilerini dekoratif serit meshleri olarak olusturur.
func build_coastlines(coastlines: Array, scale: int) -> Node3D:
	if coastlines.is_empty():
		return null

	var coastline_root := Node3D.new()
	coastline_root.name = "Coastlines"

	var coastline_material: Material = owner._load_material(owner.COASTLINE_MATERIAL)
	var created_segments := 0

	for coastline_variant in coastlines:
		var coastline: Dictionary = coastline_variant as Dictionary
		if coastline.is_empty():
			continue

		var segments_variant = coastline.get("segments", [])
		if not (segments_variant is Array):
			continue

		var segments: Array = segments_variant as Array
		var ribbon_width_m := float(coastline.get("ribbon_width_m", 40.0))
		var crest_height_m := float(coastline.get("crest_height_m", owner.COASTLINE_CREST_HEIGHT_DEFAULT)) + 0.2 
		var coastline_profile = coastline.get("profile", null)

		for segment_variant in segments:
			var segment_points: Array = segment_variant as Array
			if segment_points.size() < 2:
				continue

			var start_index := 0
			while start_index < segment_points.size():
				var end_index: int = mini(start_index + owner.MAX_POINTS_PER_COASTLINE_MESH, segment_points.size())
				var chunk: Array = []

				if start_index > 0:
					chunk.append(segment_points[start_index - 1])

				for idx in range(start_index, end_index):
					chunk.append(segment_points[idx])

				var mesh_instance := _create_coastline_mesh(
					chunk,
					scale,
					coastline_material,
					ribbon_width_m,
					crest_height_m,
					coastline_profile
				)
				if mesh_instance:
					mesh_instance.name = "CoastlineSegment_%d" % created_segments
					if coastline.has("length_km") and coastline["length_km"] != null:
						mesh_instance.set_meta("length_km", float(coastline["length_km"]))
					coastline_root.add_child(mesh_instance)
					created_segments += 1

				if end_index >= segment_points.size():
					break
				start_index = end_index - 1

	return coastline_root if created_segments > 0 else null

# --- Yardimcilar -------------------------------------------------------------

func _create_coastline_mesh(points: Array, scale: int, coastline_material: Material, ribbon_width_m: float, crest_height_m: float, profile_data) -> MeshInstance3D:
	if points.size() < 2:
		return null

	var world_points: Array[Vector3] = []
	for point_variant in points:
		var point: Dictionary = point_variant as Dictionary
		if not point or point.is_empty():
			continue
		var godot_pos := MapManager.api_to_godot_coordinates(point, scale)
		godot_pos.y = 0.0
		world_points.append(godot_pos)

	if world_points.size() < 2:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var left_points: Array = []
	var right_points: Array = []
	var half_width_world: float = max(owner._meters_to_world_units(ribbon_width_m, scale) * 0.5, owner.COASTLINE_HALF_WIDTH)
	var crest_height_units: float = max(owner._meters_to_height_units(crest_height_m), owner.COASTLINE_Y_OFFSET)
	var sea_height: float = owner._meters_to_height_units(-0.5) 

	var land_color := Color(0.94, 0.86, 0.68, 1.0)
	var water_blend_color := Color(0.35, 0.55, 0.78, 0.85)
	if profile_data and profile_data is Dictionary and profile_data.has("sand_color"):
		var profile_color_variant = profile_data.get("sand_color")
		if profile_color_variant is Color:
			land_color = profile_color_variant

	for idx in range(world_points.size()):
		var current: Vector3 = world_points[idx]
		var forward: Vector3
		if idx == 0:
			forward = (world_points[idx + 1] - current).normalized()
		elif idx == world_points.size() - 1:
			forward = (current - world_points[idx - 1]).normalized()
		else:
			var forward_prev: Vector3 = (current - world_points[idx - 1]).normalized()
			var forward_next: Vector3 = (world_points[idx + 1] - current).normalized()
			forward = (forward_prev + forward_next).normalized()
		if forward.length_squared() < 1e-6:
			forward = Vector3(1, 0, 0)
		var side: Vector3 = Vector3(forward.z, 0, -forward.x).normalized() * half_width_world
		if side.length_squared() < 1e-6:
			side = Vector3(0, 0, 1) * half_width_world
		var land_point: Vector3 = current - side
		land_point.y = crest_height_units
		var sea_point: Vector3 = current + side
		sea_point.y = sea_height
		left_points.append(land_point)
		right_points.append(sea_point)

	for idx in range(world_points.size() - 1):
		var l0: Vector3 = left_points[idx]
		var r0: Vector3 = right_points[idx]
		var l1: Vector3 = left_points[idx + 1]
		var r1: Vector3 = right_points[idx + 1]

		st.set_color(land_color)
		st.add_vertex(l0)
		st.set_color(water_blend_color)
		st.add_vertex(r0)
		st.set_color(land_color)
		st.add_vertex(l1)

		st.set_color(water_blend_color)
		st.add_vertex(r0)
		st.set_color(water_blend_color)
		st.add_vertex(r1)
		st.set_color(land_color)
		st.add_vertex(l1)

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return null

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if coastline_material:
		mesh_instance.material_override = coastline_material

	return mesh_instance

# YENILENMIS FONKSIYON: 3 Halkalı + Zirve Noktalı Arazi
func _create_peaked_land_chunk(polygon_points: Array, land_props: Dictionary, scale: int, land_material: Material) -> Node3D:
	var sanitized: Array = owner._sanitize_polygon(polygon_points)
	if sanitized.size() < 3:
		return null

	var world_points: Array = []
	for point_dict in sanitized:
		world_points.append(MapManager.api_to_godot_coordinates(point_dict, scale))

	if world_points.size() < 3:
		return null

	# 1. Halka: KIYI (COAST)
	var coast_planar: Array[Vector2] = _build_planar_loop(world_points)
	var polygon2d := PackedVector2Array(coast_planar)
	if Geometry2D.is_polygon_clockwise(polygon2d):
		world_points.reverse()
		coast_planar = _build_planar_loop(world_points)

	var centroid: Vector2 = _calculate_planar_centroid(coast_planar)
	
	# Birim Çevirileri
	var skirt_width_units: float = owner._meters_to_world_units(UNDERWATER_SKIRT_WIDTH_M, scale)
	var beach_width_units: float = owner._meters_to_world_units(BEACH_SLOPE_WIDTH_M, scale)
	
	# 2. Halka: ETEK (SKIRT - SU ALTI)
	var skirt_planar_vec2: Array[Vector2] = []
	for i in range(coast_planar.size()):
		var p = coast_planar[i]
		var dir = (p - centroid).normalized()
		skirt_planar_vec2.append(p + dir * skirt_width_units)
	
	# 3. Halka: PLATO KENARI (PLATEAU RIM - OMUZ)
	var plateau_planar: Array[Vector2] = _shrink_loop_towards_centroid(coast_planar, centroid, beach_width_units)
	if plateau_planar.is_empty() or plateau_planar.size() < 3:
		plateau_planar = _shrink_loop_towards_centroid(coast_planar, centroid, beach_width_units * 0.2)
		if plateau_planar.is_empty():
			plateau_planar = coast_planar.duplicate()

	# Yükseklik Ayarları
	# Base (Kenar) yüksekliğini de artırıyoruz ki su seviyesinden hemen yükselsin
	var base_height_m: float = float(land_props.get("base_height_m", owner.LAND_BASE_HEIGHT_MIN_M)) * (owner.LAND_HEIGHT_MULTIPLIER * 1.5) 
	var max_height_m: float = float(land_props.get("max_height_m", owner.LAND_BASE_HEIGHT_MAX_M)) * (owner.LAND_HEIGHT_MULTIPLIER * 2.0)
	
	# Yükseklik Seviyeleri (Godot Birimleri)
	var h_skirt: float = owner._meters_to_height_units(-12.0)
	var h_coast: float = owner._meters_to_height_units(0.0)
	
	# Omuz Yüksekliği (Plato kenarı) - Kıyıdan itibaren daha dik bir çıkış veriyoruz
	var h_plateau: float = owner._meters_to_height_units(base_height_m) + owner._meters_to_height_units(10.0) 
	
	# ZİRVE Yüksekliği
	var h_peak: float = owner._meters_to_height_units(max_height_m) + owner._meters_to_height_units(PEAK_HEIGHT_BOOST_M)

	# Vertex Listeleri
	var skirt_verts: Array[Vector3] = []
	for p in skirt_planar_vec2:
		skirt_verts.append(Vector3(p.x, h_skirt, p.y))
		
	var coast_verts: Array[Vector3] = []
	for p in coast_planar:
		coast_verts.append(Vector3(p.x, h_coast, p.y))
		
	var plateau_verts: Array[Vector3] = []
	for p in plateau_planar:
		plateau_verts.append(Vector3(p.x, h_plateau, p.y))

	# Zirve Noktası (Centroid)
	var peak_vertex: Vector3 = Vector3(centroid.x, h_peak, centroid.y)

	# Mesh Oluşturma
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Aşama: Etek -> Kıyı
	if skirt_verts.size() == coast_verts.size():
		for i in range(skirt_verts.size()):
			var next = (i + 1) % skirt_verts.size()
			owner._add_quad_surface(st, coast_verts[i], coast_verts[next], skirt_verts[next], skirt_verts[i], Color.WHITE, Color.WHITE, false)

	# 2. Aşama: Kıyı -> Plato Kenarı
	if coast_verts.size() == plateau_verts.size():
		for i in range(coast_verts.size()):
			var next = (i + 1) % coast_verts.size()
			owner._add_quad_surface(st, plateau_verts[i], plateau_verts[next], coast_verts[next], coast_verts[i], Color.WHITE, Color.WHITE, false)

	# 3. Aşama: Plato Kenarı -> Zirve (Üçgen Yelpazesi)
	# Düz kapak yerine, tüm kenar noktalarını merkeze (Zirveye) bağlıyoruz.
	for i in range(plateau_verts.size()):
		var next = (i + 1) % plateau_verts.size()
		
		# Normal hesaplaması için renk vs gerekirse buraya eklenebilir
		st.add_vertex(plateau_verts[i])
		st.add_vertex(plateau_verts[next])
		st.add_vertex(peak_vertex) # Hepsini tepeye bağla

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return null

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

# --- Yardımcı Fonksiyonlar ---

func _build_planar_loop(points: Array) -> Array[Vector2]:
	var loop: Array[Vector2] = []
	for point in points:
		if point is Vector3:
			loop.append(Vector2(point.x, point.z))
	return loop

func _calculate_planar_centroid(points: Array[Vector2]) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var centroid: Vector2 = Vector2.ZERO
	for point: Vector2 in points:
		centroid += point
	return centroid / points.size()

func _shrink_loop_towards_centroid(points: Array[Vector2], centroid: Vector2, distance: float) -> Array[Vector2]:
	if points.is_empty() or distance <= 0.0:
		return []
	var shrunken: Array[Vector2] = []
	for point: Vector2 in points:
		var direction: Vector2 = centroid - point
		var length: float = direction.length()
		if length < 0.001:
			shrunken.append(point)
			continue
		var offset: float = min(length * 0.9, distance)
		shrunken.append(point + direction.normalized() * offset)
	return shrunken

func _calculate_max_distance(points: Array[Vector2], centroid: Vector2) -> float:
	var max_distance: float = 0.0
	for point: Vector2 in points:
		max_distance = max(max_distance, centroid.distance_to(point))
	return max_distance
