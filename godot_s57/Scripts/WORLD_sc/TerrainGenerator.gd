class_name TerrainGenerator
extends Node

const SEA_FLOOR_MATERIAL := "res://Materials/WORLD_mat/SeaFloorMaterial.tres"
const SEA_SURFACE_MATERIAL := "res://Materials/WORLD_mat/SeaMaterial.tres"
const SEA_FLOOR_DEPTH_SCALE := 2.0
const SEA_FLOOR_DEPTH_MULTIPLIER := 2.0
const SEA_BOUNDARY_EXPANSION_FACTOR := 1.0
const MAP_EXTENSION_FACTOR := 1.2

const COASTLINE_MATERIAL := "res://Materials/WORLD_mat/CoastlineMaterial.tres"
const COASTLINE_Y_OFFSET := 0.05
const MAX_POINTS_PER_COASTLINE_MESH := 512
const COASTLINE_HALF_WIDTH := 0.8
const COASTLINE_CREST_HEIGHT_DEFAULT := 0.8
const LAND_MATERIAL := "res://Materials/WORLD_mat/LandMaterial.tres"
const LAND_Y_OFFSET := 0.03
const LAND_BASE_HEIGHT_MIN_M := 1.5
const LAND_BASE_HEIGHT_MAX_M := 15.0
const LAND_SLOPE_RATIO_DEFAULT := 0.12
const LAND_EDGE_BLEND_M_DEFAULT := 60.0
const LAND_HEIGHT_MULTIPLIER := 1.6
const LAND_COLUMN_DEPTH_M := 18.0
const LAND_COLUMN_MODE := true
const BARRIER_HEIGHT := 25.0
const BARRIER_DEPTH_OFFSET := -6.0
const BARRIER_COLOR_BOTTOM := Color(0.08, 0.15, 0.23, 0.65)
const BARRIER_COLOR_TOP := Color(0.2, 0.28, 0.36, 0.0)
const SEA_SURFACE_THICKNESS := 0.5
const DEFAULT_LAND_BOTTOM_OFFSET := -2.0

const OBJECT_DEFINITIONS := {
	"hrbfac": {
		"prefab": "res://prefab/objects/harbours/harbour.tscn",
		"material": "res://materials/WORLD_mat/HarborMaterial.tres",
		"material_node": "harbour",
		"scale": Vector3(5, 5, 5),
		"y_offset": 5.0
	},
	"slcons": {
		"prefab": "res://prefab/objects/shoreline/slcons.tscn"
	},
	"bridge": {
		"prefab": "res://prefab/objects/bridges/bridge.tscn"
	},
	"lights": {
		"prefab": "res://prefab/objects/navigation/ligths/ligth.tscn"
	},
	"obstrn": {
		"prefab": "res://prefab/objects/hazards/obstrn/obstrn.tscn"
	},
	"uwtroc": {
		"prefab": "res://prefab/objects/hazards/uwtroc/uwtroc.tscn"
	},
	"wrecks": {
		"prefab": "res://prefab/objects/hazards/wrecks/wreck.tscn"
	}
}

var _prefab_cache: Dictionary = {}
var _material_cache: Dictionary = {}

func generate_3d_environment(map_data: Dictionary, scale: int) -> Node3D:
	var environment_root := Node3D.new()
	environment_root.name = "MapEnvironment"

	var terrain: Dictionary = map_data.get("terrain", {}) as Dictionary
	var seaare_polygon: Array = []
	if terrain:
		var seaare_variant = terrain.get("seaare_polygon", [])
		if seaare_variant is Array:
			seaare_polygon = seaare_variant

	var nav_objects: Dictionary = map_data.get("navigation_objects", {}) as Dictionary
	var depth_areas: Array = []
	if terrain:
		var depth_variant = terrain.get("depth_areas", [])
		if depth_variant is Array:
			depth_areas = depth_variant
	var coastline_data: Array = []
	if terrain:
		var coastline_variant = terrain.get("coastlines", [])
		if coastline_variant is Array:
			coastline_data = coastline_variant
	var land_polygons_data: Array = []
	if terrain:
		var land_variant = terrain.get("land_polygons", [])
		if land_variant is Array:
			land_polygons_data = land_variant

	var sea_polygons: Array = []
	if terrain:
		var sea_polygons_variant = terrain.get("sea_polygons", [])
		if sea_polygons_variant is Array:
			for polygon_variant in sea_polygons_variant:
				if polygon_variant is Array:
					sea_polygons.append(polygon_variant)
	if sea_polygons.is_empty() and not seaare_polygon.is_empty():
		sea_polygons.append(seaare_polygon)

	var base_sea_polygons := _sanitize_polygon_collection(sea_polygons)
	if base_sea_polygons.is_empty() and not seaare_polygon.is_empty():
		var sanitized_seaare := _sanitize_polygon(seaare_polygon)
		if sanitized_seaare.size() >= 3:
			base_sea_polygons.append(sanitized_seaare)

	var extended_sea_polygons := _expand_polygon_collection(base_sea_polygons, MAP_EXTENSION_FACTOR)
	if extended_sea_polygons.is_empty():
		extended_sea_polygons = base_sea_polygons.duplicate(true)

	var boundary_base_polygon: Array = []
	if not base_sea_polygons.is_empty():
		boundary_base_polygon = base_sea_polygons[0].duplicate(true)

	var boundary_polygon: Array = boundary_base_polygon
	if not boundary_base_polygon.is_empty():
		var expanded_boundary := _expand_polygon(boundary_base_polygon, SEA_BOUNDARY_EXPANSION_FACTOR)
		if expanded_boundary.size() >= 3:
			boundary_polygon = expanded_boundary

	var sea_surface_polygons: Array = extended_sea_polygons
	if sea_surface_polygons.is_empty() and boundary_base_polygon.size() >= 3:
		sea_surface_polygons = [boundary_base_polygon.duplicate(true)]

	var sea_polygon_for_depths: Array = []
	if not sea_surface_polygons.is_empty():
		sea_polygon_for_depths = sea_surface_polygons[0].duplicate(true)
	else:
		sea_polygon_for_depths = boundary_base_polygon

	var total_objects := 0
	if nav_objects:
		for category_value in nav_objects.values():
			var category_objects: Array = category_value as Array
			if category_objects:
				total_objects += category_objects.size()
	var total_coastline_segments := 0
	if coastline_data:
		for coastline_variant in coastline_data:
			var coastline_dict: Dictionary = coastline_variant as Dictionary
			var segments_variant = coastline_dict.get("segments", [])
			if segments_variant is Array:
				total_coastline_segments += segments_variant.size()
	var total_land_polygons := 0
	if land_polygons_data:
		total_land_polygons = land_polygons_data.size()

	print("Generating 3D environment:")
	print("- Sea polygon sets: " + str(sea_surface_polygons.size()))
	print("- Navigation object count: " + str(total_objects))
	print("- Coastline segment groups: " + str(total_coastline_segments))
	print("- Land polygons: " + str(total_land_polygons))
	print("- Scale: 1:" + str(scale))

	var sea_surface: Node3D = generate_sea_surface(sea_surface_polygons, boundary_base_polygon, depth_areas, scale)
	if sea_surface:
		environment_root.add_child(sea_surface)

	var sea_floor: MeshInstance3D = generate_seafloor(depth_areas, sea_polygon_for_depths, scale)
	if sea_floor:
		environment_root.add_child(sea_floor)

	var extended_land_polygons_data := _extend_land_polygons(land_polygons_data, MAP_EXTENSION_FACTOR)
	var land_root: Node3D = generate_landmasses(extended_land_polygons_data, scale)
	if land_root:
		environment_root.add_child(land_root)

	var coastline_root: Node3D = generate_coastlines(coastline_data, scale)
	if coastline_root:
		environment_root.add_child(coastline_root)

	var boundary_root: Node3D = generate_boundary_barrier(boundary_polygon, scale)
	if boundary_root:
		environment_root.add_child(boundary_root)

	var navigation_root: Node3D = generate_navigation_objects(nav_objects, scale)
	if navigation_root:
		environment_root.add_child(navigation_root)

	return environment_root

func generate_sea_surface(sea_polygons: Array, fallback_polygon: Array, depth_areas: Array, scale: int) -> Node3D:
	var polygons := _sanitize_polygon_collection(sea_polygons)
	if polygons.is_empty():
		var sanitized_fallback := _sanitize_polygon(fallback_polygon)
		if sanitized_fallback.size() >= 3:
			polygons.append(sanitized_fallback)

	if polygons.is_empty():
		return null

	var sea_root := Node3D.new()
	sea_root.name = "SeaSurface"
	var sea_material := _load_material(SEA_SURFACE_MATERIAL)
	var created := 0

	for polygon_points in polygons:
		var mesh_instance := _create_water_polygon_mesh(polygon_points, scale, sea_material, depth_areas)
		if mesh_instance:
			mesh_instance.name = "SeaPatch_%d" % created
			sea_root.add_child(mesh_instance)
			created += 1

	return sea_root if created > 0 else null

func _create_water_polygon_mesh(polygon_points: Array, scale: int, sea_material: Material, depth_areas: Array) -> MeshInstance3D:
	var sanitized := _sanitize_polygon(polygon_points)
	if sanitized.size() < 3:
		return null

	var polygon_api := PackedVector2Array()
	for point_dict in sanitized:
		polygon_api.append(Vector2(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0))))

	var bounds := _calculate_polygon_bounds(sanitized)
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
			var bottom_point := top_point + Vector3(0.0, -SEA_SURFACE_THICKNESS, 0.0)
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
		var bottom_point := top_point + Vector3(0.0, -SEA_SURFACE_THICKNESS, 0.0)
		var depth_value: float = abs(_sample_depth_for_point(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0)), depth_areas))
		boundary_top.append(top_point)
		boundary_bottom.append(bottom_point)
		boundary_colors.append(_depth_to_color(depth_value, min_depth, depth_range))

	for idx in range(boundary_top.size()):
		var next := (idx + 1) % boundary_top.size()
		var color_a: Color = boundary_colors[idx]
		var color_b: Color = boundary_colors[next]
		_add_quad_surface(st, boundary_top[idx], boundary_top[next], boundary_bottom[next], boundary_bottom[idx], color_a, color_b)

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

func _triangle_overlaps_polygon(a: Dictionary, b: Dictionary, c: Dictionary, polygon: PackedVector2Array) -> bool:
	if polygon.is_empty():
		return true
	if bool(a.get("inside", false)) or bool(b.get("inside", false)) or bool(c.get("inside", false)):
		return true
	var centroid: Vector2 = (a.get("pos", Vector2.ZERO) + b.get("pos", Vector2.ZERO) + c.get("pos", Vector2.ZERO)) / 3.0
	return Geometry2D.is_point_in_polygon(centroid, polygon)

func _api_to_world_surface_point(local_x: float, local_z: float, scale: int) -> Vector3:
	var api_coords := {
		"x": local_x,
		"y": 0.0,
		"z": local_z
	}
	var converted := MapManager.api_to_godot_coordinates(api_coords, scale)
	return Vector3(converted.x, 0.0, converted.z)

func _depth_to_color(depth_value: float, min_depth: float, depth_range: float) -> Color:
	var normalized: float = clamp((depth_value - min_depth) / depth_range, 0.0, 1.0)
	return Color(normalized, normalized, normalized, normalized)
func generate_seafloor(depth_areas: Array, seaare_polygon: Array, scale: int) -> MeshInstance3D:
	if depth_areas.is_empty() or seaare_polygon.is_empty():
		return null

	var bounds: Dictionary = _calculate_polygon_bounds(seaare_polygon)
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

	var sea_floor_material: Material = _load_material(SEA_FLOOR_MATERIAL)
	if sea_floor_material:
		mesh_instance.material_override = sea_floor_material

	return mesh_instance

func generate_navigation_objects(nav_objects: Dictionary, scale: int) -> Node3D:
	if nav_objects.is_empty():
		return null

	var root := Node3D.new()
	root.name = "NavigationObjects"
	var placed: int = 0

	for category in nav_objects.keys():
		var entries_variant = nav_objects.get(category, [])
		if not (entries_variant is Array):
			continue
		var entries: Array = entries_variant
		for obj_variant in entries:
			var obj_dict: Dictionary = obj_variant as Dictionary
			if obj_dict.is_empty():
				continue
			var instance: Node3D = instantiate_navigation_object(obj_dict, scale)
			if instance:
				root.add_child(instance)
				placed += 1

	if placed == 0:
		root.queue_free()
		return null

	return root

func _extend_land_polygons(land_entries: Array, factor: float) -> Array:
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

		var expanded_polygons := _expand_polygon_collection(polygons_variant, factor)
		if expanded_polygons.is_empty():
			expanded_polygons = _sanitize_polygon_collection(polygons_variant)

		if expanded_polygons.is_empty():
			continue

		var duplicated := land_dict.duplicate(true)
		duplicated["polygons"] = expanded_polygons
		extended_entries.append(duplicated)

	return extended_entries if extended_entries.size() > 0 else land_entries.duplicate(true)

func generate_landmasses(land_polygons: Array, scale: int) -> Node3D:
	if land_polygons.is_empty():
		return null

	var land_root := Node3D.new()
	land_root.name = "Landmasses"

	var land_material := _load_material(LAND_MATERIAL)
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

func generate_coastlines(coastlines: Array, scale: int) -> Node3D:
	if coastlines.is_empty():
		return null

	var coastline_root := Node3D.new()
	coastline_root.name = "Coastlines"

	var coastline_material := _load_material(COASTLINE_MATERIAL)
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
		var crest_height_m := float(coastline.get("crest_height_m", COASTLINE_CREST_HEIGHT_DEFAULT))
		var coastline_profile = coastline.get("profile", null)

		for segment_variant in segments:
			var segment_points: Array = segment_variant as Array
			if segment_points.size() < 2:
				continue

			var start_index := 0
			while start_index < segment_points.size():
				var end_index: int = mini(start_index + MAX_POINTS_PER_COASTLINE_MESH, segment_points.size())
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
	var half_width_world: float = max(_meters_to_world_units(ribbon_width_m, scale) * 0.5, COASTLINE_HALF_WIDTH)
	var crest_height_units: float = max(_meters_to_height_units(crest_height_m), COASTLINE_Y_OFFSET)
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

func _create_land_volume_chunk(polygon_points: Array, land_props: Dictionary, scale: int, land_material: Material) -> Node3D:
	var sanitized := _sanitize_polygon(polygon_points)
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

	var base_height_m: float = float(land_props.get("base_height_m", LAND_BASE_HEIGHT_MIN_M)) * LAND_HEIGHT_MULTIPLIER
	var max_height_m: float = float(land_props.get("max_height_m", LAND_BASE_HEIGHT_MIN_M + 2.0)) * LAND_HEIGHT_MULTIPLIER
	if max_height_m <= base_height_m:
		max_height_m = base_height_m + 0.5

	var slope_seed := float(land_props.get("slope_ratio", LAND_SLOPE_RATIO_DEFAULT))
	var slope_ratio: float = max((slope_seed * 0.35) if LAND_COLUMN_MODE else slope_seed, 0.01)
	var edge_blend_units: float = max(_meters_to_world_units(float(land_props.get("edge_blend_m", LAND_EDGE_BLEND_M_DEFAULT)), scale), 0.001)
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
	var base_height_units: float = _meters_to_height_units(base_height_m)
	var max_height_units: float = _meters_to_height_units(max_height_m)
	var bottom_height_units: float = _meters_to_height_units(-LAND_COLUMN_DEPTH_M) if LAND_COLUMN_MODE else _meters_to_height_units(DEFAULT_LAND_BOTTOM_OFFSET)

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
		_add_quad_surface(st, top_a, top_b, bottom_b, bottom_a, Color.WHITE, Color.WHITE, false)

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

	var collider := _create_static_body_from_mesh(mesh)
	if collider:
		land_chunk.add_child(collider)

	return land_chunk

func _calculate_polygon_bounds(points: Array) -> Dictionary:
	if points.is_empty():
		return {}
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for point_variant in points:
		var point: Dictionary = point_variant as Dictionary
		if point.is_empty():
			continue
		var px: float = float(point.get("x", 0.0))
		var pz: float = float(point.get("z", 0.0))
		min_x = min(min_x, px)
		max_x = max(max_x, px)
		min_z = min(min_z, pz)
		max_z = max(max_z, pz)

	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z
	}

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

func _build_seafloor_vertex(local_pos: Vector2, depth_areas: Array, scale: int) -> Vector3:
	var depth_value: float = _sample_depth_for_point(local_pos.x, local_pos.y, depth_areas)
	var scaled_depth := depth_value * SEA_FLOOR_DEPTH_SCALE * SEA_FLOOR_DEPTH_MULTIPLIER
	var api_coords := {
		"x": local_pos.x,
		"y": scaled_depth,
		"z": local_pos.y
	}
	return MapManager.api_to_godot_coordinates(api_coords, scale)

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

func instantiate_navigation_object(obj_data: Dictionary, scale: int) -> Node3D:
	var obj_type := String(obj_data.get("type", "")).strip_edges().to_lower()
	if obj_type.is_empty():
		return null

	var definition: Dictionary = OBJECT_DEFINITIONS.get(obj_type, {}) as Dictionary
	var instance: Node3D = null

	if not definition.is_empty():
		var prefab_path := String(definition.get("prefab", ""))
		var prefab := _load_prefab(prefab_path)
		if prefab:
			instance = prefab.instantiate()

	if instance == null:
		return null

	instance.name = obj_data.get("id", obj_type.capitalize())

	var position_dict: Dictionary = obj_data.get("position", {}) as Dictionary
	if not position_dict or position_dict.is_empty():
		return null

	var horizontal: Vector3 = MapManager.api_to_godot_coordinates(position_dict, scale)
	var y_value := horizontal.y
	var y_offset := 0.0
	if not definition.is_empty() and definition.has("y_offset"):
		y_offset = float(definition["y_offset"])

	instance.position = Vector3(horizontal.x, y_value + y_offset, horizontal.z)

	if not definition.is_empty() and definition.has("scale"):
		instance.scale = definition["scale"]

	if not definition.is_empty():
		_apply_definition_materials(instance, definition)

	return instance

func _apply_definition_materials(instance: Node3D, definition: Dictionary) -> void:
	if not definition.has("material"):
		return

	var target: Node = instance
	var material_node := String(definition.get("material_node", ""))
	if not material_node.is_empty():
		if instance.has_node(material_node):
			target = instance.get_node(material_node)
		else:
			var found := instance.find_child(material_node, true, false)
			if found:
				target = found

	if target and target is MeshInstance3D:
		var material := _load_material(String(definition["material"]))
		if material:
			(target as MeshInstance3D).material_override = material

func _create_default_marker(obj_type: String) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = obj_type.capitalize() + "_Marker"

	var mesh: Mesh = CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 4.0
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.4, 0.7)
	mesh_instance.material_override = material

	return mesh_instance

func _load_prefab(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if not _prefab_cache.has(path):
		if not ResourceLoader.exists(path):
			print("Prefab not found: " + path)
			_prefab_cache[path] = null
		else:
			var resource := load(path)
			if resource and resource is PackedScene:
				_prefab_cache[path] = resource
			else:
				print("Failed to load prefab: " + path)
				_prefab_cache[path] = null
	return _prefab_cache[path]

func _load_material(path: String) -> Material:
	if path.is_empty():
		return null
	if not _material_cache.has(path):
		_material_cache[path] = load(path)
	return _material_cache[path]

func _expand_polygon(points: Array, factor: float) -> Array:
	if factor <= 1.0:
		return points.duplicate(true)

	var sanitized := _sanitize_sea_polygon(points)
	if sanitized.size() < 3:
		return sanitized

	var centroid := Vector2.ZERO
	for point_variant in sanitized:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict:
			continue
		centroid += Vector2(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0)))

	centroid /= sanitized.size()

	var expanded: Array = []
	for point_variant in sanitized:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict:
			continue
		var original := Vector2(float(point_dict.get("x", 0.0)), float(point_dict.get("z", 0.0)))
		var direction := original - centroid
		var scaled := centroid + direction * factor
		expanded.append({
			"x": scaled.x,
			"z": scaled.y
		})

	return expanded

func generate_boundary_barrier(seaare_polygon: Array, scale: int) -> Node3D:
	if seaare_polygon.is_empty():
		return null

	var sanitized := _sanitize_sea_polygon(seaare_polygon)
	if sanitized.size() < 3:
		return null

	var world_points: Array = []
	for point_variant in sanitized:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict or point_dict.is_empty():
			continue
		var api_coords := {
			"x": float(point_dict.get("x", 0.0)),
			"y": 0.0,
			"z": float(point_dict.get("z", 0.0))
		}
		var world := MapManager.api_to_godot_coordinates(api_coords, scale)
		world_points.append(Vector3(world.x, 0.0, world.z))
	if world_points.size() < 3:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var collision_faces := PackedVector3Array()

	for idx in range(world_points.size()):
		var next := (idx + 1) % world_points.size()
		var base_a: Vector3 = world_points[idx]
		var base_b: Vector3 = world_points[next]
		var bottom_a: Vector3 = base_a + Vector3(0, BARRIER_DEPTH_OFFSET, 0)
		var bottom_b: Vector3 = base_b + Vector3(0, BARRIER_DEPTH_OFFSET, 0)
		var top_a: Vector3 = base_a + Vector3(0, BARRIER_HEIGHT, 0)
		var top_b: Vector3 = base_b + Vector3(0, BARRIER_HEIGHT, 0)

		st.set_color(BARRIER_COLOR_BOTTOM)
		st.add_vertex(bottom_a)
		st.set_color(BARRIER_COLOR_BOTTOM)
		st.add_vertex(bottom_b)
		st.set_color(BARRIER_COLOR_TOP)
		st.add_vertex(top_b)

		st.set_color(BARRIER_COLOR_BOTTOM)
		st.add_vertex(bottom_a)
		st.set_color(BARRIER_COLOR_TOP)
		st.add_vertex(top_b)
		st.set_color(BARRIER_COLOR_TOP)
		st.add_vertex(top_a)

		collision_faces.append_array([
			bottom_a, bottom_b, top_b,
			bottom_a, top_b, top_a
		])
	

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return null

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.vertex_color_use_as_alpha = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "BoundaryFade"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material

	var boundary_root := Node3D.new()
	boundary_root.name = "Boundary"
	boundary_root.add_child(mesh_instance)

	var static_body := StaticBody3D.new()
	static_body.name = "BoundaryCollider"
	var collision_shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(collision_faces)
	collision_shape.shape = concave
	static_body.add_child(collision_shape)
	boundary_root.add_child(static_body)

	return boundary_root

func _add_quad_surface(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	color_a: Color = Color(1, 1, 1, 1),
	color_b: Color = Color(1, 1, 1, 1),
	use_color: bool = true
) -> void:
	if use_color:
		st.set_color(color_a)
	st.add_vertex(a)
	if use_color:
		st.set_color(color_b)
	st.add_vertex(b)
	if use_color:
		st.set_color(color_b)
	st.add_vertex(c)
	if use_color:
		st.set_color(color_a)
	st.add_vertex(a)
	if use_color:
		st.set_color(color_b)
	st.add_vertex(c)
	if use_color:
		st.set_color(color_a)
	st.add_vertex(d)

func _create_static_body_from_mesh(mesh: Mesh) -> StaticBody3D:
	if mesh == null:
		return null
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return null
	var body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	body.add_child(collision_shape)
	return body

func _meters_to_world_units(value_m: float, scale: int) -> float:
	return (value_m / 1000.0) * float(scale) * 0.1

func _meters_to_height_units(value_m: float) -> float:
	return value_m * 0.1

func _sanitize_polygon(points: Array) -> Array:
	var result: Array = []
	for point_variant in points:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict or point_dict.is_empty():
			continue
		if not point_dict.has("x") or not point_dict.has("z"):
			continue
		result.append({
			"x": float(point_dict.get("x", 0.0)),
			"z": float(point_dict.get("z", 0.0))
		})
	if result.size() > 2:
		var first: Dictionary = result[0]
		var last: Dictionary = result[result.size() - 1]
		if abs(float(first.get("x", 0.0)) - float(last.get("x", 0.0))) < 0.0001 and abs(float(first.get("z", 0.0)) - float(last.get("z", 0.0))) < 0.0001:
			result.remove_at(result.size() - 1)
	return result

func _sanitize_polygon_collection(polygons: Array) -> Array:
	var sanitized_collection: Array = []
	for polygon_variant in polygons:
		if not (polygon_variant is Array):
			continue
		var sanitized := _sanitize_polygon(polygon_variant)
		if sanitized.size() >= 3:
			sanitized_collection.append(sanitized)
	return sanitized_collection

func _expand_polygon_collection(polygons: Array, factor: float) -> Array:
	if factor <= 1.0:
		return _sanitize_polygon_collection(polygons)

	var expanded_collection: Array = []
	for polygon_variant in polygons:
		if not (polygon_variant is Array):
			continue
		var sanitized := _sanitize_polygon(polygon_variant)
		var expanded := _expand_polygon(sanitized, factor)
		if expanded.size() >= 3:
			expanded_collection.append(expanded)
	return expanded_collection

func _sanitize_sea_polygon(points: Array) -> Array:
	return _sanitize_polygon(points)
