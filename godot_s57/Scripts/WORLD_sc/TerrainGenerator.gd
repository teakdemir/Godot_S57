# res://scripts/WORLD_sc/TerrainGenerator.gd
class_name TerrainGenerator
extends Node

const SEA_FLOOR_MATERIAL := "res://Materials/WORLD_mat/SeaFloorMaterial.tres"
const SEA_FLOOR_DEPTH_SCALE := 3.0

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

	var total_objects := 0
	if nav_objects:
		for category_value in nav_objects.values():
			var category_objects: Array = category_value as Array
			if category_objects:
				total_objects += category_objects.size()

	print("Generating 3D environment:")
	print("- SEAARE points: " + str(seaare_polygon.size()))
	print("- Navigation object count: " + str(total_objects))
	print("- Scale: 1:" + str(scale))

	var sea_surface := generate_sea_surface(seaare_polygon, scale)
	environment_root.add_child(sea_surface)

	var sea_floor := generate_seafloor(depth_areas, seaare_polygon, scale)
	if sea_floor:
		environment_root.add_child(sea_floor)

	var navigation_root := generate_navigation_objects(nav_objects, scale)
	if navigation_root:
		environment_root.add_child(navigation_root)

	return environment_root

func generate_sea_surface(seaare_polygon: Array, scale: int) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "SeaSurface"

	var vertices := PackedVector3Array()
	for point in seaare_polygon:
		var godot_pos := MapManager.api_to_godot_coordinates(point, scale)
		vertices.append(Vector3(godot_pos.x, 0.0, godot_pos.z))

	var bounds_size := 0.0
	if vertices.size() >= 2:
		bounds_size = vertices[0].distance_to(vertices[2]) if vertices.size() >= 4 else vertices[0].distance_to(vertices[1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	if bounds_size < 50.0 or vertices.size() != 4:
		print("Creating scaled default sea surface")
		var sea_size := scale * 0.5
		vertices = PackedVector3Array([
			Vector3(-sea_size, 0, -sea_size),
			Vector3(sea_size, 0, -sea_size),
			Vector3(sea_size, 0, sea_size),
			Vector3(-sea_size, 0, sea_size)
		])

	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	])

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var normals := PackedVector3Array()
	for i in vertices.size():
		normals.append(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh

	var sea_material := load("res://materials/WORLD_mat/SeaMaterial.tres")
	if sea_material:
		mesh_instance.material_override = sea_material
	else:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#1a4d80")
		material.metallic = 0.2
		material.roughness = 0.1
		mesh_instance.material_override = material

	print("Sea surface created with ", vertices.size(), " vertices")
	return mesh_instance

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
		instance = _create_default_marker(obj_type)

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
