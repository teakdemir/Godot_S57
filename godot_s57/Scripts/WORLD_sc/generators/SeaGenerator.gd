extends RefCounted

# Deniz ile ilgili butun mesh uretim kodlarini ayri bir sinifta toplar.
class_name SeaGenerator

var owner: TerrainGenerator

func _init(owner_ref) -> void:
	owner = owner_ref

# Haritanin tum deniz poligonlari icin yuzey meshlerini olusturur.
func build_surface(sea_polygons: Array, fallback_polygon: Array, depth_areas: Array, scale: int) -> Node3D:
	var polygons: Array = owner._sanitize_polygon_collection(sea_polygons)
	if polygons.is_empty():
		var sanitized_fallback: Array = owner._sanitize_polygon(fallback_polygon)
		if sanitized_fallback.size() >= 3:
			polygons.append(sanitized_fallback)

	if polygons.is_empty():
		return null

	var sea_root := Node3D.new()
	sea_root.name = "SeaSurface"
	var sea_material: Material = owner._load_material(owner.SEA_SURFACE_MATERIAL)
	var created := 0

	for polygon_points in polygons:
		var mesh_instance := _create_water_polygon_mesh(polygon_points, scale, sea_material, depth_areas)
		if mesh_instance:
			mesh_instance.name = "SeaPatch_%d" % created
			sea_root.add_child(mesh_instance)
			created += 1

	return sea_root if created > 0 else null

# Depth verisini kullanarak deniz tabanini temsil eden mesh olusturur.
func build_seafloor(depth_areas: Array, sea_polygon: Array, scale: int) -> MeshInstance3D:
	if depth_areas.is_empty() or sea_polygon.is_empty():
		return null

	var bounds: Dictionary = owner._calculate_polygon_bounds(sea_polygon)
	if bounds.is_empty():
		return null

	var width: float = bounds.get("max_x", 0.0) - bounds.get("min_x", 0.0)
	var depth: float = bounds.get("max_z", 0.0) - bounds.get("min_z", 0.0)
	if width <= 0.01 or depth <= 0.01:
		return null

	var resolution_x: int = clamp(int(width * 2), 12, 64)
	var resolution_z: int = clamp(int(depth * 2), 12, 64)

	var step_x: float = width / float(resolution_x)
	var step_z: float = depth / float(resolution_z)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x_index in range(resolution_x):
		for z_index in range(resolution_z):
			var samples: Array = _get_cell_samples(bounds, step_x, step_z, x_index, z_index)
			var p00: Vector3 = _build_seafloor_vertex(samples[0], depth_areas, scale)
			var p10: Vector3 = _build_seafloor_vertex(samples[1], depth_areas, scale)
			var p11: Vector3 = _build_seafloor_vertex(samples[2], depth_areas, scale)
			var p01: Vector3 = _build_seafloor_vertex(samples[3], depth_areas, scale)

			var uv00: Vector2 = Vector2(float(x_index) / resolution_x, float(z_index) / resolution_z)
			var uv10: Vector2 = Vector2(float(x_index + 1) / resolution_x, float(z_index) / resolution_z)
			var uv11: Vector2 = Vector2(float(x_index + 1) / resolution_x, float(z_index + 1) / resolution_z)
			var uv01: Vector2 = Vector2(float(x_index) / resolution_x, float(z_index + 1) / resolution_z)

			st.set_uv(uv00)
			st.add_vertex(p00)
			st.set_uv(uv10)
			st.add_vertex(p10)
			st.set_uv(uv11)
			st.add_vertex(p11)

			st.set_uv(uv00)
			st.add_vertex(p00)
			st.set_uv(uv11)
			st.add_vertex(p11)
			st.set_uv(uv01)
			st.add_vertex(p01)

	st.generate_normals()
	var mesh: Mesh = st.commit()
	if not mesh:
		return null

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "SeaFloor"
	mesh_instance.mesh = mesh

	var sea_floor_material: Material = owner._load_material(owner.SEA_FLOOR_MATERIAL)
	if sea_floor_material:
		mesh_instance.material_override = sea_floor_material

	return mesh_instance

# --- Yardimcilar -------------------------------------------------------------

# Tek bir deniz poligonunu grid tabanli suprfasa donusturur.
func _create_water_polygon_mesh(polygon_points: Array, scale: int, sea_material: Material, depth_areas: Array) -> MeshInstance3D:
	var sanitized: Array = owner._sanitize_polygon(polygon_points)
	if sanitized.size() < 3:
		return null

	var polygon_api := PackedVector2Array()
	for point_dict in sanitized:
		polygon_api.append(Vector2(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0))))

	var bounds: Dictionary = owner._calculate_polygon_bounds(sanitized)
	if bounds.is_empty():
		return null

	var width: float = max(bounds.get("max_x", 0.0) - bounds.get("min_x", 0.0), 0.01)
	var depth_span: float = max(bounds.get("max_z", 0.0) - bounds.get("min_z", 0.0), 0.01)

	var resolution_x: int = clamp(int(width * 1.2), 24, 200)
	var resolution_z: int = clamp(int(depth_span * 1.2), 24, 200)

	var step_x: float = width / float(resolution_x)
	var step_z: float = depth_span / float(resolution_z)

	var samples: Array = []
	var min_depth := INF
	var max_depth := -INF

	for x_index in range(resolution_x + 1):
		var row: Array = []
		for z_index in range(resolution_z + 1):
			var local_x: float = bounds.get("min_x", 0.0) + step_x * float(x_index)
			var local_z: float = bounds.get("min_z", 0.0) + step_z * float(z_index)
			var inside_polygon := Geometry2D.is_point_in_polygon(Vector2(local_x, local_z), polygon_api)
			var depth_value: float = abs(_sample_depth_for_point(local_x, local_z, depth_areas))
			min_depth = min(min_depth, depth_value)
			max_depth = max(max_depth, depth_value)
			var top_point := _api_to_world_surface_point(local_x, local_z, scale)
			var bottom_point := top_point + Vector3(0.0, -owner.SEA_SURFACE_THICKNESS, 0.0)
			row.append({
				"pos": Vector2(local_x, local_z),
				"top": top_point,
				"bottom": bottom_point,
				"depth": depth_value,
				"inside": inside_polygon
			})
		samples.append(row)

	if min_depth == INF:
		min_depth = 0.0
	if max_depth <= min_depth:
		max_depth = min_depth + 0.001
	var depth_range: float = max(max_depth - min_depth, 0.001)

	for x_index in range(samples.size()):
		for z_index in range(samples[x_index].size()):
			var sample: Dictionary = samples[x_index][z_index]
			sample["color"] = _depth_to_color(float(sample.get("depth", 0.0)), min_depth, depth_range)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x_index in range(resolution_x):
		for z_index in range(resolution_z):
			var v00: Dictionary = samples[x_index][z_index]
			var v10: Dictionary = samples[x_index + 1][z_index]
			var v11: Dictionary = samples[x_index + 1][z_index + 1]
			var v01: Dictionary = samples[x_index][z_index + 1]

			if _triangle_overlaps_polygon(v00, v10, v11, polygon_api):
				_add_sea_surface_triangle(st, v00, v10, v11)
				_add_sea_surface_triangle_bottom(st, v00, v10, v11)

			if _triangle_overlaps_polygon(v00, v11, v01, polygon_api):
				_add_sea_surface_triangle(st, v00, v11, v01)
				_add_sea_surface_triangle_bottom(st, v00, v11, v01)

	var boundary_top: Array = []
	var boundary_bottom: Array = []
	var boundary_colors: Array = []
	for point_dict in sanitized:
		var top_point := _api_to_world_surface_point(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0)), scale)
		var bottom_point := top_point + Vector3(0.0, -owner.SEA_SURFACE_THICKNESS, 0.0)
		var depth_value: float = abs(_sample_depth_for_point(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0)), depth_areas))
		boundary_top.append(top_point)
		boundary_bottom.append(bottom_point)
		boundary_colors.append(_depth_to_color(depth_value, min_depth, depth_range))

	for idx in range(boundary_top.size()):
		var next := (idx + 1) % boundary_top.size()
		var color_a: Color = boundary_colors[idx]
		var color_b: Color = boundary_colors[next]
		owner._add_quad_surface(st, boundary_top[idx], boundary_top[next], boundary_bottom[next], boundary_bottom[idx], color_a, color_b)

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return null

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if sea_material:
		mesh_instance.material_override = sea_material

	return mesh_instance

# Ust yuz olekleri icin ucgen ekler.
func _add_sea_surface_triangle(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var color_a: Color = a.get("color", Color.WHITE)
	var color_b: Color = b.get("color", Color.WHITE)
	var color_c: Color = c.get("color", Color.WHITE)

	st.set_color(color_a)
	st.add_vertex(a.get("top"))
	st.set_color(color_b)
	st.add_vertex(b.get("top"))
	st.set_color(color_c)
	st.add_vertex(c.get("top"))

# Alt yuzeyi kapatan ucgenleri ekler.
func _add_sea_surface_triangle_bottom(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var color_a: Color = a.get("color", Color.WHITE)
	var color_b: Color = b.get("color", Color.WHITE)
	var color_c: Color = c.get("color", Color.WHITE)

	st.set_color(color_c)
	st.add_vertex(c.get("bottom"))
	st.set_color(color_b)
	st.add_vertex(b.get("bottom"))
	st.set_color(color_a)
	st.add_vertex(a.get("bottom"))

# Ucgenin hedef poligonla kesistigini kontrol eder.
func _triangle_overlaps_polygon(a: Dictionary, b: Dictionary, c: Dictionary, polygon: PackedVector2Array) -> bool:
	if polygon.is_empty():
		return true
	if bool(a.get("inside", false)) or bool(b.get("inside", false)) or bool(c.get("inside", false)):
		return true
	var centroid: Vector2 = (a.get("pos", Vector2.ZERO) + b.get("pos", Vector2.ZERO) + c.get("pos", Vector2.ZERO)) / 3.0
	return Geometry2D.is_point_in_polygon(centroid, polygon)

# API koordinatlarini Godot dunya koordinatina çevirir.
func _api_to_world_surface_point(local_x: float, local_z: float, scale: int) -> Vector3:
	var api_coords := {
		"x": local_x,
		"y": 0.0,
		"z": local_z
	}
	var converted := MapManager.api_to_godot_coordinates(api_coords, scale)
	return Vector3(converted.x, 0.0, converted.z)

# Derinlik degerini 0-1 araliginda normalize ederek renk dondurur.
func _depth_to_color(depth_value: float, min_depth: float, depth_range: float) -> Color:
	var normalized: float = clamp((depth_value - min_depth) / depth_range, 0.0, 1.0)
	return Color(normalized, normalized, normalized, normalized)

# Grid hucrelerinin kose noktalarini geri doner.
func _get_cell_samples(bounds: Dictionary, step_x: float, step_z: float, x_index: int, z_index: int) -> Array:
	var min_x: float = float(bounds.get("min_x", 0.0))
	var min_z: float = float(bounds.get("min_z", 0.0))
	var local_x: float = min_x + step_x * float(x_index)
	var local_z: float = min_z + step_z * float(z_index)
	return [
		Vector2(local_x, local_z),
		Vector2(local_x + step_x, local_z),
		Vector2(local_x + step_x, local_z + step_z),
		Vector2(local_x, local_z + step_z)
	]

# Depth alanindan metriye cevirip Godot koordinatina yansitir.
func _build_seafloor_vertex(local_pos: Vector2, depth_areas: Array, scale: int) -> Vector3:
	var depth_value: float = _sample_depth_for_point(local_pos.x, local_pos.y, depth_areas)
	var scaled_depth: float = depth_value * owner.SEA_FLOOR_DEPTH_SCALE * owner.SEA_FLOOR_DEPTH_MULTIPLIER
	var api_coords := {
		"x": local_pos.x,
		"y": scaled_depth,
		"z": local_pos.y
	}
	return MapManager.api_to_godot_coordinates(api_coords, scale)

# Verilen noktaya en yakin depth kaydini bulur.
func _sample_depth_for_point(local_x: float, local_z: float, depth_areas: Array) -> float:
	if depth_areas.is_empty():
		return -5.0

	var closest_depth := -5.0
	var closest_distance := INF

	for area_variant in depth_areas:
		var area: Dictionary = area_variant as Dictionary
		if area.is_empty():
			continue

		var center_dict: Dictionary = area.get("center", {}) as Dictionary
		if center_dict.is_empty():
			continue

		var center_x: float = float(center_dict.get("x", 0.0))
		var center_z: float = float(center_dict.get("z", 0.0))
		var dx: float = center_x - local_x
		var dz: float = center_z - local_z
		var distance: float = dx * dx + dz * dz

		if distance < closest_distance:
			closest_distance = distance
			var avg_depth_value = area.get("avg_depth", null)
			var fallback_depth = area.get("min_depth", null)
			var depth_variant = avg_depth_value if avg_depth_value != null else fallback_depth
			var depth_value: float = 5.0 if depth_variant == null else float(depth_variant)
			closest_depth = -abs(depth_value)

	return closest_depth
