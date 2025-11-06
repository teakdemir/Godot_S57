class_name TerrainGenerator
extends Node

const SEA_FLOOR_MATERIAL := "res://Materials/WORLD_mat/SeaFloorMaterial.tres"
const SEA_SURFACE_MATERIAL := "res://Materials/WORLD_mat/SeaMaterial.tres"
const SEA_FLOOR_DEPTH_SCALE := 3.0

const COASTLINE_MATERIAL := "res://Materials/WORLD_mat/CoastlineMaterial.tres"
const COASTLINE_Y_OFFSET := 0.05
const MAX_POINTS_PER_COASTLINE_MESH := 512
const COASTLINE_HALF_WIDTH := 0.8
const COASTLINE_HEIGHT := 0.45
const COASTLINE_SEAFLOOR_MARGIN := 0.1
const LAND_MATERIAL := "res://Materials/WORLD_mat/LandMaterial.tres"
const LAND_Y_OFFSET := 0.03
const LAND_EXTRUSION_HEIGHT := 0.8
const LAND_SEAFLOOR_MARGIN := 0.1

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
	print("- SEAARE points: " + str(seaare_polygon.size()))
	print("- Navigation object count: " + str(total_objects))
	print("- Coastline segment groups: " + str(total_coastline_segments))
	print("- Land polygons: " + str(total_land_polygons))
	print("- Scale: 1:" + str(scale))

	var sea_surface := generate_sea_surface(seaare_polygon, depth_areas, scale)
	environment_root.add_child(sea_surface)

	var sea_floor := generate_seafloor(depth_areas, seaare_polygon, scale)
	if sea_floor:
		environment_root.add_child(sea_floor)

	var land_root := generate_landmasses(land_polygons_data, depth_areas, scale)
	if land_root:
		environment_root.add_child(land_root)

	var coastline_root := generate_coastlines(coastline_data, depth_areas, scale)
	if coastline_root:
		environment_root.add_child(coastline_root)

	var navigation_root := generate_navigation_objects(nav_objects, scale)
	if navigation_root:
		environment_root.add_child(navigation_root)

	return environment_root

func generate_sea_surface(seaare_polygon: Array, depth_areas: Array, scale: int) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "SeaSurface"

	var bounds := _calculate_polygon_bounds(seaare_polygon)
	if bounds.is_empty():
		var fallback_extent := float(scale) * 0.75
		bounds = {
			"min_x": -fallback_extent,
			"max_x": fallback_extent,
			"min_z": -fallback_extent,
			"max_z": fallback_extent
		}

	var width: float = max(bounds.get("max_x", 0.0) - bounds.get("min_x", 0.0), 1.0)
	var depth_span: float = max(bounds.get("max_z", 0.0) - bounds.get("min_z", 0.0), 1.0)

	var resolution_x: int = clamp(int(width * 1.2), 32, 160)
	var resolution_z: int = clamp(int(depth_span * 1.2), 32, 160)

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
			var depth_value: float = abs(_sample_depth_for_point(local_x, local_z, depth_areas))

			min_depth = min(min_depth, depth_value)
			max_depth = max(max_depth, depth_value)

			row.append({
				"pos": Vector2(local_x, local_z),
				"depth": depth_value
			})
		samples.append(row)

	if min_depth == INF:
		min_depth = 0.0
	if max_depth == -INF:
		max_depth = 1.0

	var depth_range: float = max(max_depth - min_depth, 0.001)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x_index in range(resolution_x):
		for z_index in range(resolution_z):
			var v00: Dictionary = samples[x_index][z_index]
			var v10: Dictionary = samples[x_index + 1][z_index]
			var v11: Dictionary = samples[x_index + 1][z_index + 1]
			var v01: Dictionary = samples[x_index][z_index + 1]

			var uv00 := Vector2(float(x_index) / float(resolution_x), float(z_index) / float(resolution_z))
			var uv10 := Vector2(float(x_index + 1) / float(resolution_x), float(z_index) / float(resolution_z))
			var uv11 := Vector2(float(x_index + 1) / float(resolution_x), float(z_index + 1) / float(resolution_z))
			var uv01 := Vector2(float(x_index) / float(resolution_x), float(z_index + 1) / float(resolution_z))

			_add_sea_surface_vertex(st, v00, scale, min_depth, depth_range, uv00)
			_add_sea_surface_vertex(st, v10, scale, min_depth, depth_range, uv10)
			_add_sea_surface_vertex(st, v11, scale, min_depth, depth_range, uv11)

			_add_sea_surface_vertex(st, v00, scale, min_depth, depth_range, uv00)
			_add_sea_surface_vertex(st, v11, scale, min_depth, depth_range, uv11)
			_add_sea_surface_vertex(st, v01, scale, min_depth, depth_range, uv01)

	st.generate_normals()
	var mesh: Mesh = st.commit()

	if mesh:
		mesh_instance.mesh = mesh
	else:
		mesh_instance.mesh = _build_fallback_sea_mesh(scale)

	var sea_material: Material = _load_material(SEA_SURFACE_MATERIAL)
	if sea_material:
		mesh_instance.material_override = sea_material

	print("Sea surface created with %s vertices (%s x %s grid)" % [
		(resolution_x + 1) * (resolution_z + 1),
		resolution_x,
		resolution_z
	])
	return mesh_instance

func _add_sea_surface_vertex(st: SurfaceTool, sample: Dictionary, scale: int, min_depth: float, depth_range: float, uv: Vector2) -> void:
	var local_pos: Vector2 = sample.get("pos", Vector2.ZERO)
	var depth_value: float = float(sample.get("depth", 0.0))
	var normalized_depth: float = clamp((depth_value - min_depth) / depth_range, 0.0, 1.0)
	var vertex := _sea_surface_vertex(local_pos, scale)

	st.set_uv(uv)
	st.set_color(Color(normalized_depth, normalized_depth, normalized_depth, normalized_depth))
	st.add_vertex(vertex)

func _sea_surface_vertex(local_pos: Vector2, scale: int) -> Vector3:
	var api_coords := {
		"x": local_pos.x,
		"y": 0.0,
		"z": local_pos.y
	}
	var converted := MapManager.api_to_godot_coordinates(api_coords, scale)
	return Vector3(converted.x, 0.0, converted.z)

func _build_fallback_sea_mesh(scale: int) -> Mesh:
	var extent := float(scale) * 0.75

	var s00 := {"pos": Vector2(-extent, -extent), "depth": 0.0}
	var s10 := {"pos": Vector2(extent, -extent), "depth": 0.3}
	var s11 := {"pos": Vector2(extent, extent), "depth": 0.6}
	var s01 := {"pos": Vector2(-extent, extent), "depth": 0.3}

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var min_depth := 0.0
	var depth_range := 1.0

	_add_sea_surface_vertex(st, s00, scale, min_depth, depth_range, Vector2(0, 0))
	_add_sea_surface_vertex(st, s10, scale, min_depth, depth_range, Vector2(1, 0))
	_add_sea_surface_vertex(st, s11, scale, min_depth, depth_range, Vector2(1, 1))

	_add_sea_surface_vertex(st, s00, scale, min_depth, depth_range, Vector2(0, 0))
	_add_sea_surface_vertex(st, s11, scale, min_depth, depth_range, Vector2(1, 1))
	_add_sea_surface_vertex(st, s01, scale, min_depth, depth_range, Vector2(0, 1))

	st.generate_normals()
	return st.commit()

func generate_navigation_objects(nav_objects: Dictionary, scale: int) -> Node3D:
	var root := Node3D.new()
	root.name = "NavigationObjects"

	var placed := 0
	if nav_objects:
		for category in nav_objects.keys():
			var objects: Array = nav_objects.get(category, []) as Array
			if objects and objects.size() > 0:
				var category_node := Node3D.new()
				category_node.name = category.capitalize()

				for obj_data_variant in objects:
					var obj_data: Dictionary = obj_data_variant as Dictionary
					if not obj_data or obj_data.is_empty():
						continue
					var instance := instantiate_navigation_object(obj_data, scale)
					if instance:
						category_node.add_child(instance)
						placed += 1

				if category_node.get_child_count() > 0:
					root.add_child(category_node)

	if placed == 0:
		return null

	print("- Navigation objects spawned: " + str(placed))
	return root

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

func generate_landmasses(land_polygons: Array, depth_areas: Array, scale: int) -> Node3D:
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
			var mesh_instance := _create_land_polygon_mesh(polygon_points, depth_areas, scale, land_material)
			if mesh_instance:
				mesh_instance.name = "LandPolygon_%d" % created_meshes
				land_root.add_child(mesh_instance)
				created_meshes += 1

	return land_root if created_meshes > 0 else null

func generate_coastlines(coastlines: Array, depth_areas: Array, scale: int) -> Node3D:
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

				var mesh_instance := _create_coastline_mesh(chunk, depth_areas, scale, coastline_material)
				if mesh_instance:
					mesh_instance.name = "CoastlineSegment_%d" % created_segments
					if coastline.has("length_km") and coastline["length_km"] != null:
						mesh_instance.set_meta("length_km", float(coastline["length_km"]))
					coastline_root.add_child(mesh_instance)
					created_segments += 5

				if end_index >= segment_points.size():
					break
				start_index = end_index - 1

	return coastline_root if created_segments > 0 else null

func _create_coastline_mesh(points: Array, depth_areas: Array, scale: int, coastline_material: Material) -> MeshInstance3D:
	if points.size() < 2:
		return null

	var world_points: Array = []
	var seafloor_points: Array = []

	for point_variant in points:
		var point: Dictionary = point_variant as Dictionary
		if not point or point.is_empty():
			continue
		var local_x := float(point.get("x", 0.0))
		var local_z := float(point.get("z", 0.0))
		var api_coords := point.duplicate()
		api_coords["y"] = 0.0
		var godot_pos := MapManager.api_to_godot_coordinates(api_coords, scale)
		godot_pos.y = COASTLINE_Y_OFFSET
		world_points.append(godot_pos)

		var seabed := _build_seafloor_vertex(Vector2(local_x, local_z), depth_areas, scale)
		seabed.y += COASTLINE_SEAFLOOR_MARGIN
		seafloor_points.append(seabed)

	if world_points.size() < 2 or seafloor_points.size() != world_points.size():
		return null

	var mesh_instance := MeshInstance3D.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var left_points: Array = []
	var right_points: Array = []
	var left_top: Array = []
	var right_top: Array = []
	var left_bottom: Array = []
	var right_bottom: Array = []

	for idx in range(world_points.size()):
		var current: Vector3 = world_points[idx]
		var seabed_point: Vector3 = seafloor_points[idx]
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
		var side := Vector3(forward.z, 0, -forward.x).normalized() * COASTLINE_HALF_WIDTH
		if side.length_squared() < 1e-6:
			side = Vector3(0, 0, 1) * COASTLINE_HALF_WIDTH
		var left_base := current - side
		var right_base := current + side
		left_points.append(left_base)
		right_points.append(right_base)
		left_top.append(Vector3(left_base.x, left_base.y + COASTLINE_HEIGHT, left_base.z))
		right_top.append(Vector3(right_base.x, right_base.y + COASTLINE_HEIGHT, right_base.z))
		left_bottom.append(Vector3(left_base.x, seabed_point.y, left_base.z))
		right_bottom.append(Vector3(right_base.x, seabed_point.y, right_base.z))

	for idx in range(world_points.size() - 1):
		var l0: Vector3 = left_points[idx]
		var r0: Vector3 = right_points[idx]
		var l1: Vector3 = left_points[idx + 1]
		var r1: Vector3 = right_points[idx + 1]

		var lt0: Vector3 = left_top[idx]
		var rt0: Vector3 = right_top[idx]
		var lt1: Vector3 = left_top[idx + 1]
		var rt1: Vector3 = right_top[idx + 1]
		var lb0: Vector3 = left_bottom[idx]
		var rb0: Vector3 = right_bottom[idx]
		var lb1: Vector3 = left_bottom[idx + 1]
		var rb1: Vector3 = right_bottom[idx + 1]

		# Top surface
		st.add_vertex(lt0)
		st.add_vertex(rt0)
		st.add_vertex(lt1)

		st.add_vertex(rt0)
		st.add_vertex(rt1)
		st.add_vertex(lt1)

		# Left wall
		st.add_vertex(l0)
		st.add_vertex(l1)
		st.add_vertex(lt1)

		st.add_vertex(l0)
		st.add_vertex(lt1)
		st.add_vertex(lt0)

		# Right wall
		st.add_vertex(r0)
		st.add_vertex(rt0)
		st.add_vertex(rt1)

		st.add_vertex(r0)
		st.add_vertex(rt1)
		st.add_vertex(r1)

		# Left column (seafloor to base)
		st.add_vertex(lb0)
		st.add_vertex(lb1)
		st.add_vertex(l1)

		st.add_vertex(lb0)
		st.add_vertex(l1)
		st.add_vertex(l0)

		# Right column (seafloor to base)
		st.add_vertex(rb0)
		st.add_vertex(r0)
		st.add_vertex(r1)

		st.add_vertex(rb0)
		st.add_vertex(r1)
		st.add_vertex(rb1)

		# Bottom surface
		st.add_vertex(rb0)
		st.add_vertex(lb0)
		st.add_vertex(lb1)

		st.add_vertex(rb0)
		st.add_vertex(lb1)
		st.add_vertex(rb1)

	# End caps
	var l_start: Vector3 = left_points[0]
	var r_start: Vector3 = right_points[0]
	var lt_start: Vector3 = left_top[0]
	var rt_start: Vector3 = right_top[0]
	var lb_start: Vector3 = left_bottom[0]
	var rb_start: Vector3 = right_bottom[0]

	st.add_vertex(l_start)
	st.add_vertex(rt_start)
	st.add_vertex(r_start)

	st.add_vertex(l_start)
	st.add_vertex(lt_start)
	st.add_vertex(rt_start)

	st.add_vertex(lb_start)
	st.add_vertex(rb_start)
	st.add_vertex(r_start)

	st.add_vertex(lb_start)
	st.add_vertex(r_start)
	st.add_vertex(l_start)

	var last := left_points.size() - 1
	var l_end: Vector3 = left_points[last]
	var r_end: Vector3 = right_points[last]
	var lt_end: Vector3 = left_top[last]
	var rt_end: Vector3 = right_top[last]
	var lb_end: Vector3 = left_bottom[last]
	var rb_end: Vector3 = right_bottom[last]

	st.add_vertex(l_end)
	st.add_vertex(r_end)
	st.add_vertex(rt_end)

	st.add_vertex(l_end)
	st.add_vertex(rt_end)
	st.add_vertex(lt_end)

	st.add_vertex(lb_end)
	st.add_vertex(r_end)
	st.add_vertex(rb_end)

	st.add_vertex(lb_end)
	st.add_vertex(l_end)
	st.add_vertex(r_end)

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return null

	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if coastline_material:
		mesh_instance.material_override = coastline_material

	return mesh_instance

func _create_land_polygon_mesh(polygon_points: Array, depth_areas: Array, scale: int, land_material: Material) -> MeshInstance3D:
	if polygon_points.size() < 3:
		return null

	var polygon2d := PackedVector2Array()
	var base_points: Array = []
	var deep_points: Array = []

	for point_variant in polygon_points:
		var point_dict: Dictionary = point_variant as Dictionary
		if not point_dict or point_dict.is_empty():
			continue
		var local_x := float(point_dict.get("x", 0.0))
		var local_z := float(point_dict.get("z", 0.0))
		var api_coords := point_dict.duplicate()
		api_coords["y"] = 0.0
		var godot_pos := MapManager.api_to_godot_coordinates(api_coords, scale)
		polygon2d.append(Vector2(godot_pos.x, godot_pos.z))
		base_points.append(Vector3(godot_pos.x, LAND_Y_OFFSET, godot_pos.z))
		var seabed := _build_seafloor_vertex(Vector2(local_x, local_z), depth_areas, scale)
		seabed.y += LAND_SEAFLOOR_MARGIN
		deep_points.append(seabed)

	if polygon2d.size() < 3:
		return null

	if polygon2d.size() >= 2 and polygon2d[0].distance_to(polygon2d[polygon2d.size() - 1]) < 0.001:
		polygon2d.remove_at(polygon2d.size() - 1)
		base_points.remove_at(base_points.size() - 1)
		deep_points.remove_at(deep_points.size() - 1)
		if polygon2d.size() < 3:
			return null

	var top_points: Array = []
	for base_point in base_points:
		top_points.append(Vector3(base_point.x, base_point.y + LAND_EXTRUSION_HEIGHT, base_point.z))

	var indices := Geometry2D.triangulate_polygon(polygon2d)
	if indices.is_empty():
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(0, indices.size(), 3):
		var idx0 := indices[i]
		var idx1 := indices[i + 1]
		var idx2 := indices[i + 2]
		st.add_vertex(top_points[idx0])
		st.add_vertex(top_points[idx1])
		st.add_vertex(top_points[idx2])

	for i in range(0, indices.size(), 3):
		var idx0 := indices[i]
		var idx1 := indices[i + 1]
		var idx2 := indices[i + 2]
		st.add_vertex(deep_points[idx2])
		st.add_vertex(deep_points[idx1])
		st.add_vertex(deep_points[idx0])

	for i in range(base_points.size()):
		var next := (i + 1) % base_points.size()
		var b0: Vector3 = base_points[i]
		var b1: Vector3 = base_points[next]
		var t0: Vector3 = top_points[i]
		var t1: Vector3 = top_points[next]
		var d0: Vector3 = deep_points[i]
		var d1: Vector3 = deep_points[next]

		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(t1)

		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t0)

		st.add_vertex(d0)
		st.add_vertex(d1)
		st.add_vertex(b1)

		st.add_vertex(d0)
		st.add_vertex(b1)
		st.add_vertex(b0)

	st.generate_normals()
	var mesh := st.commit()
	if mesh == null:
		return null

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if land_material:
		mesh_instance.material_override = land_material
	return mesh_instance

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
	var scaled_depth := depth_value * SEA_FLOOR_DEPTH_SCALE
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
