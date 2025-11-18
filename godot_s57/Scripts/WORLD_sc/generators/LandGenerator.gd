extends RefCounted

# Kara bloklari ve kiyi seritleri icin tum uretim kodunu icerir.
class_name LandGenerator

var owner: TerrainGenerator

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
			var land_chunk := _create_land_volume_chunk(polygon_points, land_dict, scale, land_material)
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
		var crest_height_m := float(coastline.get("crest_height_m", owner.COASTLINE_CREST_HEIGHT_DEFAULT))
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

# Tek bir kiyi segmentini capraz uv'li serit mesh'e cevirir.
func _create_coastline_mesh(points: Array, scale: int, coastline_material: Material, ribbon_width_m: float, crest_height_m: float, profile_data) -> MeshInstance3D:
	if points.size() < 2:
		return null

	var world_points: Array = []
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
	var sea_height: float = 0.0

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

# Kara poligonunu ekstrude edip alt kolonlarla destekler.
func _create_land_volume_chunk(polygon_points: Array, land_props: Dictionary, scale: int, land_material: Material) -> Node3D:
	var sanitized: Array = owner._sanitize_polygon(polygon_points)
	if sanitized.size() < 3:
		return null

	var points2d: Array = []
	var world_points: Array = []
	for point_dict in sanitized:
		var world := MapManager.api_to_godot_coordinates(point_dict, scale)
		points2d.append(Vector2(world.x, world.z))
		world_points.append(world)

	if points2d.size() < 3:
		return null

	var polygon2d := PackedVector2Array(points2d)
	if Geometry2D.is_polygon_clockwise(polygon2d):
		points2d.reverse()
		world_points.reverse()
		polygon2d = PackedVector2Array(points2d)

	var base_height_m: float = float(land_props.get("base_height_m", owner.LAND_BASE_HEIGHT_MIN_M)) * owner.LAND_HEIGHT_MULTIPLIER
	var max_height_m: float = float(land_props.get("max_height_m", owner.LAND_BASE_HEIGHT_MIN_M + 2.0)) * owner.LAND_HEIGHT_MULTIPLIER
	if max_height_m <= base_height_m:
		max_height_m = base_height_m + 0.5

	var slope_seed := float(land_props.get("slope_ratio", owner.LAND_SLOPE_RATIO_DEFAULT))
	var slope_ratio: float = max((slope_seed * 0.35) if owner.LAND_COLUMN_MODE else slope_seed, 0.01)
	var edge_blend_units: float = max(owner._meters_to_world_units(float(land_props.get("edge_blend_m", owner.LAND_EDGE_BLEND_M_DEFAULT)), scale), 0.001)
	var centroid := Vector2.ZERO
	for point in points2d:
		centroid += point
	centroid /= points2d.size()

	var max_distance := 0.0
	for point in points2d:
		max_distance = max(max_distance, centroid.distance_to(point))
	var radius: float = max(max_distance, edge_blend_units)

	var top_vertices: Array = []
	var bottom_vertices: Array = []
	var base_height_units: float = owner._meters_to_height_units(base_height_m)
	var max_height_units: float = owner._meters_to_height_units(max_height_m)
	var bottom_height_units: float = owner._meters_to_height_units(-owner.LAND_COLUMN_DEPTH_M) if owner.LAND_COLUMN_MODE else owner._meters_to_height_units(owner.DEFAULT_LAND_BOTTOM_OFFSET)

	for point in world_points:
		var planar := Vector2(point.x, point.z)
		var distance_ratio: float = 0.0
		if radius > 0.0:
			distance_ratio = clamp(planar.distance_to(centroid) / radius, 0.0, 1.0)
		var eased: float = pow(distance_ratio, slope_ratio)
		var height: float = lerp(max_height_units, base_height_units, eased)
		top_vertices.append(Vector3(planar.x, height, planar.y))
		bottom_vertices.append(Vector3(planar.x, bottom_height_units, planar.y))

	var indices := Geometry2D.triangulate_polygon(polygon2d)
	if indices.is_empty():
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(0, indices.size(), 3):
		var idx0: int = indices[i]
		var idx1: int = indices[i + 1]
		var idx2: int = indices[i + 2]
		st.add_vertex(top_vertices[idx0])
		st.add_vertex(top_vertices[idx1])
		st.add_vertex(top_vertices[idx2])

		st.add_vertex(bottom_vertices[idx2])
		st.add_vertex(bottom_vertices[idx1])
		st.add_vertex(bottom_vertices[idx0])

	for idx in range(top_vertices.size()):
		var next := (idx + 1) % top_vertices.size()
		var top_a: Vector3 = top_vertices[idx]
		var top_b: Vector3 = top_vertices[next]
		var bottom_a: Vector3 = bottom_vertices[idx]
		var bottom_b: Vector3 = bottom_vertices[next]
		owner._add_quad_surface(st, top_a, top_b, bottom_b, bottom_a, Color.WHITE, Color.WHITE, false)

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
